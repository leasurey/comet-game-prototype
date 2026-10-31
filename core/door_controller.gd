## DoorController — 真实可开合门 + 门槛穿越检测
##
## 流程：玩家按 E → 门旋转打开 → 碰撞禁用 → 玩家实际跨过门槛 → 信号触发地点切换。
## 关闭时碰撞启用，无法穿过。

extends Node3D

signal door_opened
signal door_closed
signal player_crossed_threshold

@export var open_angle: float = 95.0
@export var open_duration: float = 0.55
@export var threshold_half_depth: float = 0.35
@export var threshold_half_width: float = 0.9

var _pivot: Node3D = null
var _door_body: StaticBody3D = null
var _is_open := false
var _is_animating := false
var _tween: Tween = null
var _player: Node3D = null
var _target_location: String = ""
var _last_side := 0
var _outward_dir := Vector3.ZERO  # 由目标落点推导的"门外"方向
var _outside_ref := Vector3.ZERO  # 门外参考点（目标落点）


func setup(pivot: Node3D, door_body: StaticBody3D, target_loc: String = "") -> void:
	_pivot = pivot
	_door_body = door_body
	_target_location = target_loc


## 场景加载后按节点名解析引用——构建期的 setup() 参数不会随 .tscn 保存。
func _ready() -> void:
	_resolve_refs()


func _resolve_refs() -> void:
	if _pivot != null and is_instance_valid(_pivot):
		return
	var holder := get_parent()
	if holder == null:
		return
	# 控制器名为 <HolderName>Controller，轴心名为 <HolderName>Pivot
	var holder_name := str(holder.name)
	var base := holder_name
	if base.ends_with("Geo"):
		base = base.substr(0, base.length() - 3)
	var pivot_name := holder_name + "Pivot"
	var body_name := base + "Body"
	_pivot = holder.get_node_or_null(pivot_name) as Node3D
	if _pivot == null:
		# 兜底：搜索任意含 Pivot 的直接子节点
		for c in holder.get_children():
			if c is Node3D and str(c.name).contains("Pivot"):
				_pivot = c
				break
	if _pivot != null:
		_door_body = _pivot.get_node_or_null(body_name) as StaticBody3D
		if _door_body == null:
			for c in _pivot.get_children():
				if c is StaticBody3D:
					_door_body = c
					break


func set_player(player: Node3D) -> void:
	_player = player


func set_target_location(loc: String) -> void:
	_target_location = loc


## 设定门外参考点（目标落点），用于推导"门外"方向，适配任意门朝向。
func set_outside_ref(world_pos: Vector3) -> void:
	_outside_ref = world_pos
	_outward_dir = (world_pos - global_position)
	_outward_dir.y = 0.0
	if _outward_dir.length() > 0.001:
		_outward_dir = _outward_dir.normalized()
	else:
		_outward_dir = -global_transform.basis.z


func get_target_location() -> String:
	return _target_location


func is_open() -> bool:
	return _is_open


func try_open() -> bool:
	if _is_open or _is_animating:
		return false
	_animate(true)
	return true


func try_close() -> bool:
	if not _is_open or _is_animating:
		return false
	_animate(false)
	return true


func toggle() -> void:
	if _is_animating:
		return
	_animate(not _is_open)


func _physics_process(_delta: float) -> void:
	if not _is_open or _player == null:
		return
	_check_threshold()


func _check_threshold() -> void:
	# 门外方向 = 门朝向（-局部Z）。geom.door 保证门面朝外构建。
	var outward := -global_transform.basis.z
	var origin := global_position
	var delta := _player.global_position - origin
	if absf(delta.y) > 2.0:
		return
	# 沿门外方向的有符号距离
	var along := delta.dot(outward)
	# 横向偏移（垂直于门外方向）
	var lateral_vec := delta - outward * along
	var lateral := Vector2(lateral_vec.x, lateral_vec.z).length()
	if lateral > threshold_half_width:
		return

	var side := 1 if along > 0.0 else -1
	if _last_side == 0:
		_last_side = side
		return
	# 跨门槛 = 从内侧(-)变到外侧(+)，适配任意门朝向
	if _last_side < 0 and side > 0:
		_last_side = side
		player_crossed_threshold.emit()
		return
	_last_side = side


func _animate(open: bool) -> void:
	if _pivot == null:
		return
	_is_animating = true
	_is_open = open
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	var target_angle := deg_to_rad(open_angle) if open else 0.0
	_tween.tween_property(_pivot, "rotation:y", target_angle, open_duration)
	_tween.tween_callback(_on_done.bind(open))


func _on_done(open: bool) -> void:
	_is_animating = false
	if _door_body != null:
		_door_body.collision_layer = 0 if open else 1
	if open:
		_last_side = 0
		door_opened.emit()
	else:
		door_closed.emit()
