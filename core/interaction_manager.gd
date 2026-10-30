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

## 最大交互距离（米）。射线长度与交互距离是两件事：
##   射线长度 60 m 同时承担「遮挡判定」——必须够长才能比较墙距与热点距；
##   交互距离 2.5 m 才是「玩家够不够得着」的判据。
## 两者混用会导致缩短射线后远处墙体不再参与遮挡比对。
## 这是设计初值，需按实际手感调整。
const MAX_INTERACT_DISTANCE := 2.5

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
			# 三重判据缺一不可：
			#   1 可交互（世界可见性 / 启用状态）
			#   2 未被墙体遮挡（dist <= env_distance）
			#   3 在交互距离内（dist <= MAX_INTERACT_DISTANCE）
			# 第 3 条是新加的：此前只看遮挡，站在客厅能聚焦 60 m 外门廊的热点。
			if candidate.is_interactable() \
					and dist <= env_distance \
					and dist <= MAX_INTERACT_DISTANCE:
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
## 玩家路径的唯一激活入口（E 键与鼠标左键都经 _try_interact 到达这里）。
##
## 必须做距离二次校验：_update_focus() 只保证「本帧聚焦时够得着」，
## 但聚焦状态可以保持多帧，玩家在按下 E 之前完全可能已经走开。
## 缺了这一条，就会出现「提示已消失但仍能隔空交互」。
func activate_focused() -> bool:
	if _focused == null or not is_instance_valid(_focused):
		return false
	if not _focused.is_interactable():
		return false
	if not _within_reach(_focused):
		set_focused_internal(null)
		return false
	var target := _focused
	hotspot_activated.emit(target)
	return true


## 程序化激活入口，供测试与脚本使用，不做距离校验（没有玩家位置的语义）。
## 玩家永远走不到这里——这条边界必须守住，否则距离限制形同虚设。
func activate(spot: Hotspot) -> bool:
	if spot == null or not is_instance_valid(spot):
		return false
	if not spot.is_interactable():
		return false
	hotspot_activated.emit(spot)
	return true


func _within_reach(spot: Hotspot) -> bool:
	if _camera == null or not is_instance_valid(_camera):
		return false
	return _camera.global_position.distance_to(spot.global_position) <= MAX_INTERACT_DISTANCE
