## NPC — 非玩家角色实体
##
## 职责边界：
##   负责「这个角色此刻在哪、在做什么、朝哪看」。
##   不决定他该说什么（DialogueManager）、不决定他该怎么走（由外部派目标）。
##
## 导航约束（依据 docs/NAVIGATION_FEASIBILITY.md）：
##   1. NavigationAgent3D.radius 必须与 navmesh 的 agent_radius 一致（0.30），
##      否则会出现「导航认为能过、物理上贴墙抖动」。
##      P0-2 修复：此前 navmesh 用 0.30 而 agent 用 0.35，两者不一致。
##   2. 出生 Y 取 FLOOR_Y，不能用 navmesh 点的 Y——navmesh 比地面高 0.2~0.4 m，
##      直接用会浮空。
##   3. 烘焙与寻路之间必须等物理帧，本类不自己烘焙，由 NPCManager 负责。

class_name NPC
extends CharacterBody3D

signal arrived
signal state_changed(state: String)

const GRAVITY := 18.0
const MOVE_SPEED := 1.6          # 比玩家 2.6 慢，符合「NPC 自然走动」
const TURN_SPEED := 6.0
const ARRIVE_DISTANCE := 0.35

## 动态避让（邻近 NPC 分离转向）。
##
## 为什么不用 NavigationAgent3D 的 RVO（avoidance_enabled）：
## RVO 的 velocity_computed 回调在 NavigationServer 同步帧异步到达，
## 与重力、move_and_slide 的组合在 headless 下时序不确定，没法写稳定的
## 行为断言。分离转向是纯确定性计算：每物理帧对附近 NPC 产生推离速度，
## 7 个 NPC 只有 21 对检查，开销可忽略。
##
## 参数依据（胶囊半径 0.28，两人并排需 ≥0.56 m）：
##   AVOID_RADIUS    推离作用半径 1.10 m
##   AVOID_STRENGTH  推力增益 4.0 → 对向相逢的平衡距离约 0.66 m（> 0.56）
##   AVOID_MAX_PUSH  推力上限 2.2 m/s（可完全抵消前进 1.6 并后退）
const AVOID_RADIUS := 1.10
const AVOID_STRENGTH := 4.0
const AVOID_MAX_PUSH := 2.2
## 侧向分量比例。纯粹径向推离会让两个对向而行的 NPC 在平衡距离上「顶牛」
## 死锁（实测双双停在离目标 2.8 m 处）。附加绕自身前进方向的侧向分量后，
## 两人自动各走自己一侧错车（keep-right 约定，由 away 向量互反自动保证）。
const AVOID_TURN_RATIO := 0.9
const GROUP_NPCS := "npcs"

## 状态
const STATE_IDLE := "idle"
const STATE_WALKING := "walking"
const STATE_TALKING := "talking"

## 行为模式（自主行为用）
const BEHAVIOR_IDLE := "idle"
const BEHAVIOR_WANDER := "wander"

var character_id: String = ""
var display_name: String = ""
var home_room: String = ""

var state: String = STATE_IDLE
var _target: Vector3 = Vector3.ZERO
var _has_target := false
var _look_at: Vector3 = Vector3.ZERO
var _has_look := false

# ---------------------------------------------------------------- 人物系统（批次 3）

## 记忆条目：{tick, kind, content, about, world}。追加式、有序、入档。
## kind: "dialogue" | "event" | "observation" | "player_action"
## world: 记忆发生时的现实 id（空 = 跨现实通用记忆）
var memory: Array = []

## NPC 知道的事实 id 集合（与玩家认知平行但独立——NPC 只知道自己经历的）。
var known_facts: Array = []

## 已说过的对话节点 id（对话连续性：同问题二问给不同回答）。
var said_nodes: Array = []

## 人际关系：{target_id: {"trust": float(-1..1), "familiarity": float(0..1)}}
## target_id 可以是 "player" 或另一个 NPC id。
var relationships: Dictionary = {}

## 行为模式（自主游荡由 _wander_timer 驱动）
var behavior: String = BEHAVIOR_IDLE
var _wander_timer: float = 0.0
## 游荡间隔（秒）。不同角色可通过 setup_personality 调整。
var wander_interval: float = 10.0
var _wander_rooms: Array = []   # 可游荡的房间 id 列表（NPCManager 注入）
var _current_world: String = ""  # 当前现实（记忆归档用）
## 游荡回调（显式注入，不依赖 get_parent 链——NPC 的 parent 是地点容器，
## 不是 NPCManager，get_parent().has_method("npc_wander_to") 永远找不到）。
var wander_callback: Callable = Callable()

@onready var _agent: NavigationAgent3D = null
@onready var _body: CollisionShape3D = null


## 碰撞层约定：
##   layer 1 = 环境（墙/地板/家具）
##   layer 4 = NPC
## NPC 只与环境碰撞（站着不掉、不穿墙），但**不与玩家碰撞**——
## 任务书要求「NPC 不应频繁堵住门口和主要通道」，而实测发现
## 有碰撞的 NPC 会堵死门洞并破坏路线连通性测试。
## 玩家可以穿过 NPC（有意取舍：保证门口与通道永远畅通）。
## NPC 之间的动态避让由 _separation_push() 分离转向负责（见下方常量区）。
const NPC_LAYER := 4
const ENV_LAYER := 1

func _ready() -> void:
	collision_layer = NPC_LAYER
	collision_mask = ENV_LAYER
	add_to_group(GROUP_NPCS)
	# 碰撞体：比玩家略小，留出避让余量
	_body = CollisionShape3D.new()
	_body.name = "Body"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.68
	_body.shape = cap
	_body.position = Vector3(0, 0.84, 0)
	add_child(_body)

	_agent = NavigationAgent3D.new()
	_agent.name = "NavAgent"
	# 与 navmesh 的 agent_radius 一致（NPCManager.AGENT_RADIUS = 0.30，精确量化值）
	_agent.radius = 0.30
	_agent.height = 1.68
	_agent.path_desired_distance = 0.35
	_agent.target_desired_distance = 0.35
	_agent.avoidance_enabled = false      # 本轮不做动态避让，见报告「未验证项」
	add_child(_agent)


func setup(id: String, name_text: String, room: String) -> void:
	character_id = id
	display_name = name_text
	home_room = room
	name = "NPC_%s" % id


## 根据 characters.json 的 traits 调整行为参数。
## 例如 traits 含 "restless" → 游荡更频繁；"homebody" → 更少出门。
func setup_personality(traits: Array) -> void:
	if traits.has("restless"):
		wander_interval = 5.0
	elif traits.has("homebody"):
		wander_interval = 18.0
	else:
		wander_interval = 10.0


## 注入可游荡房间 id 列表（NPCManager 从 characters.json 的 rooms 读取）。
func set_wander_rooms(rooms: Array) -> void:
	_wander_rooms = rooms.duplicate()


## 更新当前现实 id（记忆归档用）。
func set_current_world(world_id: String) -> void:
	_current_world = world_id


# ---------------------------------------------------------------- 记忆

## 记录一条记忆。kind: "dialogue" | "event" | "observation" | "player_action"
## about: 关于谁（"player" 或 NPC id 或 ""）
## tick: 真实游戏时间（P1-4 修复：此前固定写 0）。
func remember(kind: String, content: String, about: String = "", tick: int = -1) -> void:
	memory.append({
		"tick": tick,
		"kind": kind,
		"content": content,
		"about": about,
		"world": _current_world,
	})
	# 记忆上限 60 条——防止无限制增长影响序列化效率
	if memory.size() > 60:
		memory.pop_front()


## 获取记忆（可按现实过滤）。world_id 为空 = 全部记忆。
func get_memory(world_id: String = "") -> Array:
	if world_id.is_empty():
		return memory.duplicate(true)
	var out: Array = []
	for m in memory:
		# 空 world 的记忆是跨现实通用的，总是可见
		if str((m as Dictionary).get("world", "")) == world_id \
				or str((m as Dictionary).get("world", "")).is_empty():
			out.append(m)
	return out


## NPC 是否知道某个事实。
func knows_fact(fact_id: String) -> bool:
	return known_facts.has(fact_id)


## 授予 NPC 一条事实。返回 true = 新学到。
func learn_fact(fact_id: String) -> bool:
	if known_facts.has(fact_id):
		return false
	known_facts.append(fact_id)
	return true


## 某段对话是否已经说过。
func has_said(node_id: String) -> bool:
	return said_nodes.has(node_id)


## 标记某段对话已经说过。
func mark_said(node_id: String) -> void:
	if not said_nodes.has(node_id):
		said_nodes.append(node_id)


# ---------------------------------------------------------------- 人际关系

## 获取与某对象的关系数据。返回 {"trust": float, "familiarity": float}
func get_relationship(target_id: String) -> Dictionary:
	if not relationships.has(target_id):
		return {"trust": 0.0, "familiarity": 0.0}
	return (relationships[target_id] as Dictionary).duplicate(true)


## 获取信任度（-1 ~ 1）。0 = 中性。
func get_trust(target_id: String) -> float:
	var r := get_relationship(target_id)
	return float(r.get("trust", 0.0))


## 调整关系。trust_delta: -0.5~+0.5, familiarity_delta: 0~+0.5
func adjust_relationship(target_id: String, trust_delta: float, familiarity_delta: float = 0.0) -> void:
	if not relationships.has(target_id):
		relationships[target_id] = {"trust": 0.0, "familiarity": 0.0}
	var r: Dictionary = relationships[target_id]
	r["trust"] = clampf(float(r.get("trust", 0.0)) + trust_delta, -1.0, 1.0)
	r["familiarity"] = clampf(float(r.get("familiarity", 0.0)) + familiarity_delta, 0.0, 1.0)


func get_state() -> String:
	return state


func is_talking() -> bool:
	return state == STATE_TALKING


## 让 NPC 走向某个点（世界坐标）。
func move_to(target: Vector3) -> void:
	_target = target
	# 目标 Y 固定取地面高度，不能用 global_position.y——
	# 若 NPC 此刻因碰撞被顶到半空，用当前 y 会让目标悬在 navmesh 之上，寻路失败。
	_target.y = 0.20
	_has_target = true
	_set_state(STATE_WALKING)
	if _agent != null:
		_agent.target_position = _target


## 让 NPC 原地停下。
func stop_moving() -> void:
	_has_target = false
	velocity.x = 0.0
	velocity.z = 0.0
	if state != STATE_TALKING:
		_set_state(STATE_IDLE)


## 当前行走目标（供 NPCManager 在导航就绪后重发）。
func has_goal() -> bool:
	return _has_target


func get_goal() -> Vector3:
	return _target


## 进入交谈状态（面向说话对象）。
func start_talking(towards: Vector3 = Vector3.ZERO) -> void:
	_look_at = towards
	_has_look = towards != Vector3.ZERO
	stop_moving()
	_set_state(STATE_TALKING)


func stop_talking() -> void:
	if state == STATE_TALKING:
		_set_state(STATE_IDLE)


func _set_state(s: String) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


func _physics_process(delta: float) -> void:
	# 重力：NPC 也要站在地面上
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# 自主行为：游荡决策（不干涉说话状态和正在执行的外部指令）
	_process_autonomy(delta)

	if state == STATE_WALKING and _has_target and _agent != null:
		var next := _agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			dir = dir.normalized()
			var desired := dir * MOVE_SPEED + _separation_push()
			velocity.x = desired.x
			velocity.z = desired.z
			# 平滑转向
			var want := atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, want, TURN_SPEED * delta)
		else:
			velocity.x = 0.0
			velocity.z = 0.0

		var flat := Vector2(global_position.x - _target.x, global_position.z - _target.z).length()
		if flat <= ARRIVE_DISTANCE or _agent.is_navigation_finished():
			_has_target = false
			velocity.x = 0.0
			velocity.z = 0.0
			_set_state(STATE_IDLE)
			arrived.emit()
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# 交谈时看向对方
	if state == STATE_TALKING and _has_look:
		var to := _look_at - global_position
		to.y = 0.0
		if to.length() > 0.05:
			var want2 := atan2(to.x, to.z)
			rotation.y = lerp_angle(rotation.y, want2, TURN_SPEED * delta)

	move_and_slide()


## 邻近 NPC 分离推力（动态避让）。
## 对半径 AVOID_RADIUS 内的每个其他 NPC 产生背离它的速度分量，
## 就近越近推力越大，上限 AVOID_MAX_PUSH。只作用于走动中的 NPC。
## 侧向分量（垂直于两人连线）让对向而行的两人从彼此侧面错开，
## 不会僵持在正前方互相顶住。
func _separation_push() -> Vector3:
	var push := Vector3.ZERO
	var me := Vector3(global_position.x, 0.0, global_position.z)
	for other in get_tree().get_nodes_in_group(GROUP_NPCS):
		if other == self or not (other is NPC):
			continue
		var op: Vector3 = (other as NPC).global_position
		var away := me - Vector3(op.x, 0.0, op.z)
		var d := away.length()
		if d >= AVOID_RADIUS or d < 0.001:
			continue
		var falloff := 1.0 - d / AVOID_RADIUS
		var radial := away.normalized()
		# 垂直于连线的侧向：两人的 away 互反 → 侧向也互反 → 各走各的一侧
		var perp := Vector3(-away.z, 0.0, away.x).normalized()
		push += (radial + perp * AVOID_TURN_RATIO) * falloff
	push *= AVOID_STRENGTH
	if push.length() > AVOID_MAX_PUSH:
		push = push.normalized() * AVOID_MAX_PUSH
	return push


# ---------------------------------------------------------------- 自主行为

## 自主行为驱动：空闲时游荡到 home 区域内随机房间。
## 说话 / 被外部派目标时自动暂停，不干扰外部指令。
func _process_autonomy(delta: float) -> void:
	# 说话中或正在走路 → 自主行为挂起
	if state != STATE_IDLE:
		return
	# 没有可游荡房间 → 不动
	if _wander_rooms.is_empty():
		return
	_wander_timer += delta
	if _wander_timer < wander_interval:
		return
	_wander_timer = 0.0
	# 随机选一个房间（排除当前 home，避免在原地打转）
	var candidates: Array = []
	for r in _wander_rooms:
		if str(r) != home_room:
			candidates.append(str(r))
	if candidates.is_empty():
		return
	var pick: String = str(candidates[randi() % candidates.size()])
	# 通过显式注入的回调交给 NPCManager（P0-1 修复）：
	# NPC 的 parent 是地点容器而非 NPCManager，get_parent() 找不到 npc_wander_to。
	if wander_callback.is_valid():
		wander_callback.call(character_id, pick)
	# 标记行为意图（入档用）
	behavior = BEHAVIOR_WANDER


# ---------------------------------------------------------------- 存档

## 世界坐标。离树后（SceneManager 摘下旧实例后才轮到 NPCManager 快照）
## global_* 会报 "!is_inside_tree()" 并返回零向量——快照会被写成 (0,0,0)。
## 手动累乘父链变换，保证离树也能取到正确位置。
func _world_position() -> Vector3:
	if is_inside_tree():
		return global_position
	var t := transform
	var p := get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t.origin


func serialize() -> Dictionary:
	var wp := _world_position()
	var rec := {
		"id": character_id,
		"position": [wp.x, wp.y, wp.z],
		"rotation_y": rotation.y,
		"state": state,
		"target": null,
		# 人物系统（批次 3）
		"memory": memory.duplicate(true),
		"known_facts": known_facts.duplicate(),
		"said_nodes": said_nodes.duplicate(),
		"relationships": relationships.duplicate(true),
		"behavior": behavior,
		"wander_timer": _wander_timer,
	}
	if _has_target:
		rec["target"] = [_target.x, _target.y, _target.z]
	return rec


func restore(data: Dictionary) -> void:
	var pos: Variant = data.get("position", null)
	if typeof(pos) == TYPE_ARRAY and (pos as Array).size() >= 3:
		global_position = Vector3(float((pos as Array)[0]), float((pos as Array)[1]),
				float((pos as Array)[2]))
	rotation.y = float(data.get("rotation_y", 0.0))
	# 人物系统恢复
	memory = (data.get("memory", []) as Array).duplicate(true)
	known_facts = (data.get("known_facts", []) as Array).duplicate()
	said_nodes = (data.get("said_nodes", []) as Array).duplicate()
	var rel_raw: Variant = data.get("relationships", null)
	if typeof(rel_raw) == TYPE_DICTIONARY:
		relationships = (rel_raw as Dictionary).duplicate(true)
	behavior = str(data.get("behavior", BEHAVIOR_IDLE))
	_wander_timer = float(data.get("wander_timer", 0.0))
	var tg: Variant = data.get("target", null)
	if typeof(tg) == TYPE_ARRAY and (tg as Array).size() >= 3:
		move_to(Vector3(float((tg as Array)[0]), float((tg as Array)[1]),
				float((tg as Array)[2])))
	else:
		_has_target = false
		_set_state(str(data.get("state", STATE_IDLE)))
		if state == STATE_WALKING:
			_set_state(STATE_IDLE)
