## PlayerController — 第一人称视角 + 地面移动
##
## 职责边界：
##   把鼠标移动翻译成 yaw/pitch，把 WASD 翻译成地面位移。
##   不做任何交互判定，不读世界状态，不操作 UI。
##
## 节点分工（沿用既有结构，未重建）：
##   本节点（CameraRig，CharacterBody3D）
##     ├─ yaw    ：rotation.y
##     ├─ 移动   ：velocity.x/z，move_and_slide()
##     └─ 子 Camera3D：pitch（rotation.x）+ 渲染，local y 固定为观察高度
##
##   两层分离除了避免欧拉角耦合造成的翻转，还让「移动只跟随水平朝向」
##   成为结构上的必然：本节点的 rotation 只含 yaw，pitch 只存在于子相机，
##   因此移动方向不可能被抬头/低头影响。
##
## 输入机制：
##   鼠标：Godot 原生捕获（Input.MOUSE_MODE_CAPTURED），
##        增量由 InputEventMouseMotion.relative 直接给出，不做屏幕坐标补偿。
##   键盘：WASD 经 InputMap 动作读取，Input.get_vector() 自带归一化，
##        因此斜向移动速度不会快于单方向。
##
## 单位约定：yaw 与 pitch 一律使用**弧度**。
##   历史上曾出现「按弧度累加、按度数使用」的混乱，
##   使垂直灵敏度比水平低约 57 倍。本文件内所有角度统一为弧度。

class_name PlayerController
extends CharacterBody3D

const MAX_PITCH_DEGREES := 75.0
## 75° 换算后的弧度值。写成字面量是因为 GDScript 的 const 初始化不允许调用全局函数。
const MAX_PITCH_RADIANS := 1.30900

## 灵敏度默认值。全项目唯一定义点，其他脚本不得重复定义。
## 单位：弧度 / 像素。
const DEFAULT_SENSITIVITY_X := 0.0035
const DEFAULT_SENSITIVITY_Y := 0.0035

## 移动参数默认值。
const DEFAULT_MOVE_SPEED := 2.6
const DEFAULT_RUN_SPEED := 4.2
const DEFAULT_GRAVITY := 18.0
## 跳跃初速度 4.8：最大高度约 0.64m，能过门槛，不能跳上厨房高台。
const DEFAULT_JUMP_VELOCITY := 4.8
const MAX_FALL_SPEED := 20.0
const JUMP_BUFFER_SECONDS := 0.12

signal jumped
signal landed(impact_speed: float)
signal movement_state_changed(state: String)

@export_group("鼠标灵敏度")
@export_range(0.0002, 0.02, 0.0001) var sensitivity_x: float = DEFAULT_SENSITIVITY_X
@export_range(0.0002, 0.02, 0.0001) var sensitivity_y: float = DEFAULT_SENSITIVITY_Y
@export var invert_y: bool = false

@export_group("移动")
## 水平移动速度，单位：米 / 秒。
@export_range(0.2, 12.0, 0.1) var move_speed: float = DEFAULT_MOVE_SPEED
@export_range(0.2, 16.0, 0.1) var run_speed: float = DEFAULT_RUN_SPEED
@export_range(0.0, 60.0, 0.5) var gravity: float = DEFAULT_GRAVITY
@export_range(0.5, 12.0, 0.1) var jump_velocity: float = DEFAULT_JUMP_VELOCITY
@export_range(0.0, 1.0, 0.05) var air_control: float = 0.85

@export_group("视角")
## Camera3D 相对玩家脚底的高度。
@export var eye_height: float = 1.62

var input_enabled: bool = true
var yaw: float = 0.0
var pitch: float = 0.0
## 对外只读的移动状态：idle/walking/running/jumping/falling/landing。
var movement_state: String = "idle"
var _jump_buffer: float = 0.0
var _landing_timer: float = 0.0
var _was_on_floor: bool = false
var _running: bool = false

## 逻辑捕获状态。单独维护而不只读 Input.mouse_mode，
## 是为了在 headless（无真实窗口）下也能被测试可靠断言；运行时两者同步。
var _mouse_captured: bool = false

var _camera: Camera3D = null


func _ready() -> void:
	_discover_camera()
	# 观察高度由「子相机相对脚底的高度」表达，不再改动自身 position.y：
	# 本节点原点现在是脚底，position.y 由物理（重力 / 地面）决定。
	if _camera != null:
		_camera.position.y = eye_height
	_apply_rotation()


func _exit_tree() -> void:
	release_mouse()


func _discover_camera() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	for child in get_children():
		if child is Camera3D:
			_camera = child as Camera3D
			return
	for child in get_children():
		var found: Node = child.find_child("Camera3D", true, false)
		if found is Camera3D:
			_camera = found as Camera3D
			return


# ------------------------------------------------------------------ 鼠标捕获

func capture_mouse() -> void:
	_mouse_captured = true
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	_mouse_captured = false
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return _mouse_captured


# ------------------------------------------------------------------ 视角输入

func _input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if not _mouse_captured:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_apply_look(mm.relative)


## 把一次鼠标位移转成视角增量。单独抽出便于测试直接调用。
func _apply_look(relative: Vector2) -> void:
	yaw -= relative.x * sensitivity_x
	var pitch_delta := relative.y * sensitivity_y
	if invert_y:
		pitch -= pitch_delta
	else:
		pitch += pitch_delta
	_apply_rotation()


func _apply_rotation() -> void:
	pitch = clampf(pitch, -MAX_PITCH_RADIANS, MAX_PITCH_RADIANS)
	# 把 yaw 收敛回 [-PI, PI]，避免长时间游玩后浮点精度下降。
	# -PI 与 +PI 是同一朝向，视觉连续，不会出现跳变或突然回正。
	yaw = wrapf(yaw, -PI, PI)
	rotation.y = yaw
	if _camera != null and is_instance_valid(_camera):
		_camera.rotation.x = -pitch


func get_camera() -> Camera3D:
	if _camera == null:
		_discover_camera()
	return _camera


# ------------------------------------------------------------------ 移动

func _physics_process(delta: float) -> void:
	if not input_enabled:
		return
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_landing_timer = maxf(0.0, _landing_timer - delta)
	if Input.is_action_just_pressed("jump"):
		request_jump()
	_running = Input.is_action_pressed("run")
	_apply_gravity(delta)
	_try_jump()
	_apply_horizontal_velocity()
	var fall_speed: float = -velocity.y
	move_and_slide()
	_update_movement_state(delta, fall_speed)


## 键盘与测试共用的跳跃入口。只设置短输入缓冲，不直接改坐标。
func request_jump() -> void:
	_jump_buffer = JUMP_BUFFER_SECONDS


## 只有地面状态才消耗跳跃缓冲；空中按键不会累积成无限推进。
func _try_jump() -> void:
	if _jump_buffer <= 0.0 or not is_on_floor():
		return
	_jump_buffer = 0.0
	_landing_timer = 0.0
	velocity.y = jump_velocity
	_set_movement_state("jumping")
	jumped.emit()


func _update_movement_state(_delta: float, fall_speed: float) -> void:
	if is_on_floor():
		if not _was_on_floor:
			_landing_timer = 0.12
			landed.emit(maxf(0.0, fall_speed))
		if _landing_timer > 0.0:
			_set_movement_state("landing")
		elif Vector2(velocity.x, velocity.z).length() > 0.1:
			_set_movement_state("running" if _running else "walking")
		else:
			_set_movement_state("idle")
	else:
		_set_movement_state("jumping" if velocity.y > 0.0 else "falling")
	_was_on_floor = is_on_floor()


func _set_movement_state(next: String) -> void:
	if movement_state == next:
		return
	movement_state = next
	movement_state_changed.emit(next)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		# 站住时把残余下落速度清零，避免贴地抖动
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
		velocity.y = maxf(velocity.y, -MAX_FALL_SPEED)


## 只使用本节点的 yaw 计算移动方向。
## 不使用 transform.basis —— 那样会把其它旋转分量一并带入。
## 当前结构下本节点只有 yaw，但显式写 Basis(UP, yaw) 能把这个约束固定下来，
## 将来即使有人给节点加了倾斜，也不会污染移动方向。
func _apply_horizontal_velocity() -> void:
	var input_dir := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	_apply_direction(input_dir)


## 把二维输入方向转成世界位移并写入 velocity。
## Input.get_vector() 已保证长度不超过 1，所以斜向不会快于单向。
func _apply_direction(input_dir: Vector2) -> void:
	var direction := Basis(Vector3.UP, yaw) * Vector3(input_dir.x, 0.0, input_dir.y)
	if direction.length_squared() > 0.000001:
		direction = direction.normalized()
	var speed: float = run_speed if _running else move_speed
	if not is_on_floor():
		speed *= air_control
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed


## 供测试直接注入移动输入，绕开真实键盘，但不改变物理流程。
func apply_move_input(input_dir: Vector2) -> void:
	_apply_direction(input_dir)


## 切换地点后把玩家放回该地点出生点，避免沿用上一个地点的坐标导致嵌墙。
func reset_to_spawn(spawn: Vector3) -> void:
	velocity = Vector3.ZERO
	_jump_buffer = 0.0
	_landing_timer = 0.0
	_was_on_floor = false
	_running = false
	_set_movement_state("idle")
	global_position = spawn


# ------------------------------------------------------------------ 存档

func serialize_view() -> Dictionary:
	return {"yaw": yaw, "pitch": pitch}


func restore_view(state: Dictionary) -> void:
	yaw = float(state.get("yaw", 0.0))
	pitch = float(state.get("pitch", 0.0))
	_apply_rotation()


func reset_view() -> void:
	yaw = 0.0
	pitch = 0.0
	_apply_rotation()


func get_pitch_degrees() -> float:
	return rad_to_deg(pitch)


func get_yaw_degrees() -> float:
	return rad_to_deg(yaw)
