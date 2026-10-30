## PlayerController — 第一人称环视
##
## 职责边界：
##   只把鼠标拖动翻译成 yaw/pitch，不做任何交互判定，不读世界状态。
##
## 实现取向：
##   yaw 施加在自身（Y 轴），pitch 施加在子 Camera3D 的 X 轴。
##   分开两层可以避免欧拉角耦合导致的视角翻转；
##   pitch 额外做硬性限位，双保险。

class_name PlayerController
extends Node3D

const MAX_PITCH_DEGREES := 75.0

@export var mouse_sensitivity: float = 0.0035
@export var eye_height: float = 1.62
@export var invert_y: bool = false

var input_enabled: bool = true
var yaw: float = 0.0
var pitch: float = 0.0

var _camera: Camera3D = null
var _is_dragging: bool = false
var _last_mouse_pos := Vector2.ZERO


func _ready() -> void:
	_discover_camera()
	position.y = eye_height
	_apply_rotation()


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


func _input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging = true
				_last_mouse_pos = mb.position
			else:
				_is_dragging = false

	elif event is InputEventMouseMotion:
		if not _is_dragging:
			return
		var mm := event as InputEventMouseMotion
		var delta := mm.position - _last_mouse_pos
		_last_mouse_pos = mm.position
		yaw -= delta.x * mouse_sensitivity
		var pitch_delta := delta.y * mouse_sensitivity
		if invert_y:
			pitch -= pitch_delta
		else:
			pitch += pitch_delta
		_apply_rotation()


func _apply_rotation() -> void:
	pitch = clampf(pitch, -MAX_PITCH_DEGREES, MAX_PITCH_DEGREES)
	if pitch > MAX_PITCH_DEGREES:
		pitch = MAX_PITCH_DEGREES
	elif pitch < -MAX_PITCH_DEGREES:
		pitch = -MAX_PITCH_DEGREES
	rotation_degrees.y = rad_to_deg(yaw)
	if _camera != null and is_instance_valid(_camera):
		_camera.rotation_degrees.x = -pitch


func get_camera() -> Camera3D:
	if _camera == null:
		_discover_camera()
	return _camera


## 供存档与动作序列化使用：外部可直接还原视角。
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
