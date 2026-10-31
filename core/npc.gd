## NPC — 非玩家角色实体
##
## 职责边界：
##   负责「这个角色此刻在哪、在做什么、朝哪看」。
##   不决定他该说什么（DialogueManager）、不决定他该怎么走（由外部派目标）。
##
## 导航约束（依据 docs/NAVIGATION_FEASIBILITY.md）：
##   1. NavigationAgent3D.radius 必须与 navmesh 的 agent_radius 一致（0.35），
##      否则会出现「导航认为能过、物理上贴墙抖动」。
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

var character_id: String = ""
var display_name: String = ""
var home_room: String = ""

var state: String = STATE_IDLE
var _target: Vector3 = Vector3.ZERO
var _has_target := false
var _look_at: Vector3 = Vector3.ZERO
var _has_look := false

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
	# 与 navmesh 的 agent_radius 一致（可行性报告推荐值）
	_agent.radius = 0.35
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
		# 行走目标一并入档（CT-004）：否则「带着目标离场/存档」的 NPC
		# 恢复后会站在原地丢掉正在执行的行为。
		"target": null,
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
	var tg: Variant = data.get("target", null)
	if typeof(tg) == TYPE_ARRAY and (tg as Array).size() >= 3:
		# 续接行走目标。map 未同步时 agent 查不到路径是暂时的，
		# NPCManager 在导航就绪后会重发目标（tick 的 nav_ready 分支）。
		move_to(Vector3(float((tg as Array)[0]), float((tg as Array)[1]),
				float((tg as Array)[2])))
	else:
		_has_target = false
		_set_state(str(data.get("state", STATE_IDLE)))
		if state == STATE_WALKING:
			# 有状态无目标是坏快照（旧档无 target 字段时可能出现），归一为 idle
			_set_state(STATE_IDLE)
