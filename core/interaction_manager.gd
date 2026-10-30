## InteractionManager — 热点识别与交互派发
##
## 职责边界：
##   只负责「准星指向了哪个热点」「点击时派发给谁」。
##   不关心热点代表什么剧情，也不操作任何 UI 文本。
##
## 遮挡处理：
##   对静态环境层（layer 1）与热点层（layer 2）各投射一次射线。
##   若墙壁比热点更近，则视为被遮挡，不允许交互，避免隔墙点击。

class_name InteractionManager
extends Node

signal hotspot_focused(spot: Hotspot)
signal hotspot_unfocused(spot: Hotspot)
signal hotspot_activated(spot: Hotspot)

const HOTSPOT_LAYER_MASK := 2
const ENVIRONMENT_LAYER_MASK := 1
const RAY_LENGTH := 60.0

var enabled: bool = true

var _camera: Camera3D = null
var _hotspots: Array = []
var _focused: Hotspot = null


func set_camera(camera: Camera3D) -> void:
	_camera = camera


func set_hotspots(spots: Array) -> void:
	set_focused_internal(null)
	_hotspots.clear()
	for spot in spots:
		if spot is Hotspot:
			_hotspots.append(spot)


func get_hotspots() -> Array:
	return _hotspots.duplicate()


func get_focused() -> Hotspot:
	return _focused


func _process(_delta: float) -> void:
	if not enabled:
		return
	_update_focus()


func _update_focus() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if not _camera.is_inside_tree():
		return

	var space := _camera.get_world_3d().direct_space_state
	if space == null:
		return

	var origin := _camera.global_position
	var direction := -_camera.global_transform.basis.z
	var end := origin + direction * RAY_LENGTH

	var found: Hotspot = null

	var env_query := PhysicsRayQueryParameters3D.create(origin, end)
	env_query.collision_mask = ENVIRONMENT_LAYER_MASK
	env_query.collide_with_bodies = true
	env_query.collide_with_areas = false
	var env_hit := space.intersect_ray(env_query)
	var env_distance := INF
	if not env_hit.is_empty():
		var pos: Variant = env_hit.get("position", null)
		if typeof(pos) == TYPE_VECTOR3:
			env_distance = origin.distance_to(pos as Vector3)

	var spot_query := PhysicsRayQueryParameters3D.create(origin, end)
	spot_query.collision_mask = HOTSPOT_LAYER_MASK
	spot_query.collide_with_bodies = false
	spot_query.collide_with_areas = true
	var spot_hit := space.intersect_ray(spot_query)
	if not spot_hit.is_empty():
		var collider: Variant = spot_hit.get("collider", null)
		var pos2: Variant = spot_hit.get("position", null)
		var dist: float = INF
		if typeof(pos2) == TYPE_VECTOR3:
			dist = origin.distance_to(pos2 as Vector3)
		if collider is Hotspot and _hotspots.has(collider):
			var candidate := collider as Hotspot
			if candidate.is_interactable() and dist <= env_distance:
				found = candidate

	set_focused_internal(found)


func set_focused_internal(spot: Hotspot) -> void:
	if _focused == spot:
		return
	if _focused != null and is_instance_valid(_focused):
		var previous := _focused
		_focused = null
		previous.set_focused(false)
		hotspot_unfocused.emit(previous)
	_focused = spot
	if _focused != null:
		_focused.set_focused(true)
		hotspot_focused.emit(_focused)


## 激活当前聚焦的热点。返回是否成功，便于调用方决定是否给反馈。
func activate_focused() -> bool:
	if _focused == null or not is_instance_valid(_focused):
		return false
	if not _focused.is_interactable():
		return false
	var target := _focused
	hotspot_activated.emit(target)
	return true


func activate(spot: Hotspot) -> bool:
	if spot == null or not is_instance_valid(spot):
		return false
	if not spot.is_interactable():
		return false
	hotspot_activated.emit(spot)
	return true
