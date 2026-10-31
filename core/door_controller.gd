## DoorController — 可开合门的运行时控制
##
## 功能：
##   1. 按 E 打开/关门（带旋转动画）
##   2. 关闭时碰撞体阻挡玩家
##   3. 打开时碰撞体禁用，玩家可通过
##   4. 门槛检测：玩家跨过门后触发地点切换
##
## 挂载在门框（Frame）节点下，door_pivot 是门板的旋转轴心。

extends Node3D

signal door_opened
signal door_closed
signal player_crossed_threshold

@export var pivot_path: NodePath
@export var collision_path: NodePath
@export var open_angle: float = 95.0
@export var open_duration: float = 0.5
@export var threshold_z_offset: float = 0.3  # 门槛判定偏移量

var _pivot: Node3D = null
var _collision: StaticBody3D = null
var _is_open := false
var _is_animating := false
var _tween: Tween = null
var _player_in_range := false
var _player_crossed := false
var _target_location := ""  # 跨过门槛后切换到的地点


func _ready() -> void:
	if pivot_path != NodePath(""):
		_pivot = get_node_or_null(pivot_path)
	if collision_path != NodePath(""):
		_collision = get_node_or_null(collision_path)
	set_process(false)  # 只在门开且玩家在附近时处理


## 玩家进入交互范围
func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range


## 尝试打开门（由交互系统调用）
func try_open() -> bool:
	if _is_open or _is_animating:
		return false
	_animate_door(true)
	return true


## 尝试关门
func try_close() -> bool:
	if not _is_open or _is_animating:
		return false
	_animate_door(false)
	return true


## 切换门状态
func toggle() -> void:
	if _is_animating:
		return
	_animate_door(not _is_open)


func is_open() -> bool:
	return _is_open


## 设置过门后的目标地点
func set_target_location(location_id: String) -> void:
	_target_location = location_id


func get_target_location() -> String:
	return _target_location


## 门槛检测：调用此方法检查玩家是否跨过门槛
func check_threshold(player_pos: Vector3) -> bool:
	if not _is_open:
		return false
	if _pivot == null:
		return false
	# 计算门框的世界位置和法线方向
	var door_world_pos := global_position
	var forward := -global_transform.basis.z  # 门面朝方向
	# 玩家在门的"内侧"→"外侧"跨越判定
	var to_player := player_pos - door_world_pos
	var side := to_player.dot(forward)
	# 只在开门状态下检测，且玩家在门槛附近
	if absf(side) < threshold_z_offset + 0.5:
		if not _player_crossed and side < -threshold_z_offset:
			_player_crossed = true
			player_crossed_threshold.emit()
			return true
		if _player_crossed and side > threshold_z_offset:
			_player_crossed = false  # 回到内侧，允许再次检测
	return false


# ------------------------------------------------------------------ 内部

func _animate_door(open: bool) -> void:
	if _pivot == null:
		return
	_is_animating = true
	_is_open = open

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)

	var target_angle := deg_to_rad(open_angle) if open else 0.0
	_tween.tween_property(_pivot, "rotation:y", target_angle, open_duration)
	_tween.tween_callback(_on_animation_done.bind(open))


func _on_animation_done(open: bool) -> void:
	_is_animating = false
	# 更新碰撞体
	if _collision != null:
		_collision.get_node_or_null("Shape").disabled = open if open else false
		# 关闭时启用碰撞，打开时禁用
		if open:
			_collision.collision_layer = 0  # 禁用碰撞层
		else:
			_collision.collision_layer = 1  # 恢复碰撞层

	if open:
		door_opened.emit()
	else:
		door_closed.emit()
		_player_crossed = false


## 设置碰撞体节点（由构建脚本注入）
func setup(pivot: Node3D, collision: StaticBody3D, target_loc: String = "") -> void:
	_pivot = pivot
	_collision = collision
	_target_location = target_loc
