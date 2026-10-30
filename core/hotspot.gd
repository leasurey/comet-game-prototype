## Hotspot — 场景中的可交互对象
##
## 这是 InteractionManager 唯一认识的节点类型。
## 热点本身不含任何剧情逻辑，只负责声明「我是什么」「点了之后要做什么」，
## 具体由 InteractionManager 派发给 SceneManager / UI 处理。
##
## visible_only_in_worlds 为空数组时表示在所有世界都可见；
## 非空时，只有当前世界 id 在列表内才显示并可交互。

class_name Hotspot
extends Area3D

signal focus_changed(hotspot: Hotspot, focused: bool)

@export var display_name: String = ""
@export var prompt: String = "查看"
@export var action_kind: String = "examine"
@export var target_location: String = ""
@export var examine_text: String = ""
@export var visible_only_in_worlds: Array = []

var _focused: bool = false
var _shape_ready: bool = false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	_ensure_collision_shape()


## 若场景中没有显式给出碰撞体，自动补一个球形区域，
## 保证「看得见就一定点得到」，避免热点成为哑对象。
func _ensure_collision_shape() -> void:
	if _shape_ready:
		return
	for child in get_children():
		if child is CollisionShape3D:
			_shape_ready = true
			return

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = _estimate_radius()
	shape.shape = sphere
	shape.name = "AutoShape"
	add_child(shape)
	_shape_ready = true


func _estimate_radius() -> float:
	var aabb := _local_aabb()
	var size := aabb.size
	if size.x <= 0.001 and size.y <= 0.001 and size.z <= 0.001:
		return 0.35
	return clampf(max(size.x, max(size.y, size.z)) * 0.6, 0.25, 1.6)


func _local_aabb() -> AABB:
	var combined := AABB()
	var found := false
	for child in get_children():
		if child is VisualInstance3D:
			var box: AABB = (child as VisualInstance3D).get_aabb()
			if not found:
				combined = box
				found = true
			else:
				combined = combined.merge(box)
	if not found:
		combined = AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))
	return combined


func is_focused() -> bool:
	return _focused


func set_focused(value: bool) -> void:
	if _focused == value:
		return
	_focused = value
	_update_visual_feedback()
	focus_changed.emit(self, value)


func _update_visual_feedback() -> void:
	# 悬停反馈刻意做得很轻：只轻微提亮自发光，不使用描边或跳动图标，
	# 以免破坏「热点不过度突出」的影片基调。
	var factor := 1.0
	if _focused:
		factor = 1.0
	_apply_emission(factor)


func _apply_emission(scale_factor: float) -> void:
	for child in get_children():
		if child is GeometryInstance3D:
			var gi := child as GeometryInstance3D
			if gi.material_override is StandardMaterial3D:
				var mat := gi.material_override as StandardMaterial3D
				mat.emission_enabled = _focused
				mat.emission = Color(1.0, 0.88, 0.62) * (0.22 * scale_factor)
			else:
				var new_mat := StandardMaterial3D.new()
				new_mat.emission_enabled = _focused
				new_mat.emission = Color(1.0, 0.88, 0.62) * (0.22 * scale_factor)
				gi.material_override = new_mat


## 热点的显示与否由世界状态驱动，而不是随机决定。
func apply_world(world_id: String) -> void:
	if visible_only_in_worlds.is_empty():
		visible = true
		return
	visible = visible_only_in_worlds.has(world_id)
	# 不可见的热点必须同时失去碰撞能力，防止出现空气墙式的隐形交互
	monitorable = visible
	collision_layer = 2 if visible else 0
	if not visible:
		set_focused(false)


func is_interactable() -> bool:
	if not is_instance_valid(self):
		return false
	if not is_inside_tree():
		return false
	# 使用 is_visible_in_tree 而非 visible：父级 variant 被隐藏时也必须判定为不可交互
	return visible and is_visible_in_tree()


func get_hint_text() -> String:
	if display_name.is_empty():
		return ""
	return "%s" % display_name
