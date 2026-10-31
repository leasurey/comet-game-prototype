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
## 玩家可以穿过 NPC（灰盒阶段可接受；正式版需另行设计避让）。
const NPC_LAYER := 4
const ENV_LAYER := 1

func _ready() -> void:
	collision_layer = NPC_LAYER
	collision_mask = ENV_LAYER
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
			velocity.x = dir.x * MOVE_SPEED
			velocity.z = dir.z * MOVE_SPEED
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


# ---------------------------------------------------------------- 存档

func serialize() -> Dictionary:
	return {
		"id": character_id,
		"position": [global_position.x, global_position.y, global_position.z],
		"rotation_y": rotation.y,
		"state": state,
	}


func restore(data: Dictionary) -> void:
	var pos: Variant = data.get("position", null)
	if typeof(pos) == TYPE_ARRAY and (pos as Array).size() >= 3:
		global_position = Vector3(float((pos as Array)[0]), float((pos as Array)[1]),
				float((pos as Array)[2]))
	rotation.y = float(data.get("rotation_y", 0.0))
	_set_state(str(data.get("state", STATE_IDLE)))
	_has_target = false
