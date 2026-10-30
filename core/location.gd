## GameLocation — 一个地点的根节点
##
## 职责边界：
##   同一个地点场景被所有世界复用；节点通过一个 id 进入后在 VARIANT_PREFIX + world_id
##   命名的子节点中找到自己这一版内容并切换显示。
##
## 必须遵守的约定：
##   1. 所有随世界变化的内容都必须放在 Environment 节点下，且子节点命名为 Variant_<world_id>。
##   2. 不随世界变化的通用内容（例如通用出口热点）可直接挂在根节点下。
##   3. 热点若只应在特定世界出现，用其 visible_only_in_worlds 声明，
##      而不是在世界切换时动态增删节点——节点集合恒定，只有可见性变化，
##      这样 scene tree 结构稳定，不会在连续往返后错乱。

class_name GameLocation
extends Node3D

const VARIANT_PREFIX := "Variant_"

@export var environment_root_name: String = "Environment"

var location_id: String = ""
var applied_world_id: String = ""


func set_location_id(value: String) -> void:
	location_id = value


func get_environment_root() -> Node:
	if environment_root_name.is_empty():
		return null
	var found := find_child(environment_root_name, false, false)
	return found


## 按世界 id 切换表现。这是「同一个地点在不同世界呈现不同内容」的落地点。
func apply_world(world_id: String) -> void:
	applied_world_id = world_id

	var env := get_environment_root()
	if env != null:
		var target_name := VARIANT_PREFIX + world_id
		var matched := false
		var fallback_node: Node = null
		for child in env.get_children():
			var candidate := child as Node
			# 只有 Variant_ 前缀的节点才参与世界切换。
			# 其余节点属于共享内容（地面、房屋主体等），必须保持原状，否则会被误隐藏。
			if not candidate.name.begins_with(VARIANT_PREFIX):
				continue
			if candidate.name == target_name:
				candidate.visible = true
				matched = true
			else:
				candidate.visible = false
			if candidate.name == VARIANT_PREFIX + "default":
				fallback_node = candidate
			elif fallback_node == null or fallback_node.name == target_name:
				fallback_node = candidate
		if not matched and fallback_node != null:
			(fallback_node as Node).visible = true

	# 热点可见性同样由世界驱动
	for spot in _iter_hotspots():
		spot.apply_world(world_id)


func collect_hotspots() -> Array:
	var result: Array = []
	for spot in _iter_hotspots():
		result.append(spot)
	return result


func _iter_hotspots() -> Array:
	var found: Array = []
	_collect_hotspots_recursive(self, found)
	return found


func _collect_hotspots_recursive(node: Node, sink: Array) -> void:
	for child in node.get_children():
		var c := child as Node
		if c is Hotspot:
			sink.append(c)
		_collect_hotspots_recursive(c, sink)


## 供 SceneManager 在存档恢复后确认表现层确实已同步。
func get_applied_world_id() -> String:
	return applied_world_id
