## PlayerController — 第一人称视角控制（鼠标捕获式）
##
## 职责边界：
##   只把鼠标移动翻译成 yaw/pitch，不做任何交互判定，不读世界状态。
##
## 输入机制：
##   使用 Godot 原生的鼠标捕获（Input.MOUSE_MODE_CAPTURED）。
##   捕获后系统光标隐藏、指针被锁定，引擎在 InputEventMouseMotion.relative
##   中直接给出「本次移动了多少」，无需自行做屏幕坐标补偿，
##   鼠标移到窗口边缘也不会中断。
##
## 节点分工（沿用既有结构，未重建）：
##   本节点（CameraRig）负责 yaw —— rotation.y
##   子 Camera3D         负责 pitch —— rotation.x
##   Camera3D 同时负责画面渲染
##   两层分离可以避免欧拉角耦合造成的翻转/倾斜。
##
## 单位约定：yaw 与 pitch 一律使用**弧度**。
##   历史上曾出现「按弧度累加、按度数使用」的单位混乱，
##   导致垂直方向灵敏度比水平低约 57 倍。本文件内所有角度计算统一为弧度，
##   只有在需要展示时才转换。

class_name PlayerController
extends Node3D

const MAX_PITCH_DEGREES := 75.0
## 75° 换算后的弧度值。这里写成字面量而不用 deg_to_rad()，
## 因为 GDScript 的 const 初始化不允许调用全局函数。
const MAX_PITCH_RADIANS := 1.30900

## 灵敏度默认值。这是全项目唯一的灵敏度来源，其他脚本不得重复定义。
## 单位：弧度 / 像素。0.0035 表示鼠标移动 1000 像素约转 3.5 弧度（约 200°）。
const DEFAULT_SENSITIVITY_X := 0.0035
const DEFAULT_SENSITIVITY_Y := 0.0035

@export_group("鼠标灵敏度")
@export_range(0.0002, 0.02, 0.0001) var sensitivity_x: float = DEFAULT_SENSITIVITY_X
@export_range(0.0002, 0.02, 0.0001) var sensitivity_y: float = DEFAULT_SENSITIVITY_Y
@export var invert_y: bool = false

@export_group("视角")
@export var eye_height: float = 1.62

var input_enabled: bool = true
var yaw: float = 0.0
var pitch: float = 0.0

## 逻辑上的捕获状态。
## 单独维护而不只读 Input.mouse_mode，是为了在 headless（无真实窗口）下
## 也能被测试可靠地断言；运行时两者保持同步。
var _mouse_captured: bool = false

var _camera: Camera3D = null


func _ready() -> void:
	_discover_camera()
	position.y = eye_height
	_apply_rotation()


func _exit_tree() -> void:
	# 退出时必须把鼠标交还系统，避免残留捕获状态
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


# ------------------------------------------------------------------ 输入处理

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
	# -PI 与 +PI 是同一朝向，因此视觉上连续，不会出现跳变或突然回正。
	yaw = wrapf(yaw, -PI, PI)
	rotation.y = yaw
	if _camera != null and is_instance_valid(_camera):
		_camera.rotation.x = -pitch


func get_camera() -> Camera3D:
	if _camera == null:
		_discover_camera()
	return _camera


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


## 以度数返回当前俯仰，仅用于日志与测试断言。
func get_pitch_degrees() -> float:
	return rad_to_deg(pitch)


func get_yaw_degrees() -> float:
	return rad_to_deg(yaw)
