## SceneManager — 地点加载与切换
##
## 职责边界：
##   只关心「当前在哪个地点」「怎么换到另一个地点」「从哪来能不能回去」。
##   地点内容呈现什么样子，由 GameLocation.apply_world() 根据世界 id 决定，SceneManager 不干预。
##
## 关键约定：
##   地点 id 与世界 id 是两个正交维度。更换地点不会改变世界；
##   但进入某个地点可能触发事件进而改变世界——这一求值由 EventManager 负责，
##   SceneManager 只在其结果改变了世界时，重刷一次当前地点的变体。

class_name SceneManager
extends Node

signal location_entered(location_id: String, display_name: String)
signal location_failed(location_id: String, error: String)

const ENVIRONMENT_ROOT := "Environment"

var world_manager = null
var event_manager = null
var interaction_manager = null

var _locations: Dictionary = {}
var _start_location_id: String = ""
var _current_location_id: String = ""
var _current_instance = null
var _container: Node = null
var _visit_stack: Array = []
var _visited_locations: Dictionary = {}
var _is_switching: bool = false


func load_from_data(data: Dictionary, out_error: Array = []) -> bool:
	_locations.clear()
	_visited_locations.clear()
	_visit_stack.clear()
	_start_location_id = ""

	if data.is_empty():
		out_error.append("地点数据为空")
		return false

	var start := str(data.get("start_location", "")).strip_edges()
	if start.is_empty():
		out_error.append("缺少 start_location")
		return false

	var raw_locations: Variant = data.get("locations", null)
	if typeof(raw_locations) != TYPE_ARRAY:
		out_error.append("locations 必须是数组")
		return false

	for entry in (raw_locations as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			out_error.append("locations 中存在非对象元素")
			return false
		var loc: Dictionary = entry
		var lid := str(loc.get("id", "")).strip_edges()
		if lid.is_empty():
			out_error.append("location 缺少 id")
			return false
		if _locations.has(lid):
			out_error.append("location id 重复: %s" % lid)
			return false

		var scene_path := str(loc.get("scene", "")).strip_edges()
		if scene_path.is_empty():
			out_error.append("location %s 缺少 scene" % lid)
			return false
		if not ResourceLoader.exists(scene_path):
			out_error.append("location %s 的场景文件不存在: %s" % [lid, scene_path])
			return false

		var exits_raw: Variant = loc.get("exits", [])
		if typeof(exits_raw) != TYPE_ARRAY:
			out_error.append("location %s 的 exits 必须是数组" % lid)
			return false
		for ex in (exits_raw as Array):
			if typeof(ex) != TYPE_DICTIONARY:
				out_error.append("location %s 的 exits 含非法条目" % lid)
				return false
			var target := str((ex as Dictionary).get("target", "")).strip_edges()
			if target.is_empty():
				out_error.append("location %s 存在缺少 target 的出口" % lid)
				return false

		_locations[lid] = loc.duplicate(true)

	if not _locations.has(start):
		out_error.append("start_location 未定义: %s" % start)
		return false

	# 校验所有出口目标都真实存在，避免运行时出现无法抵达的死链
	for lid_key in _locations.keys():
		var info: Dictionary = _locations[lid_key]
		for ex in (info.get("exits", []) as Array):
			var target := str((ex as Dictionary).get("target", ""))
			if not _locations.has(target):
				out_error.append("地点 %s 的出口指向未知地点: %s" % [lid_key, target])
				return false

	_start_location_id = start
	return true


func set_container(container: Node) -> void:
	_container = container


func has_location(location_id: String) -> bool:
	return _locations.has(location_id)


func get_location_ids() -> Array:
	return _locations.keys()


func get_start_location_id() -> String:
	return _start_location_id


func get_current_location_id() -> String:
	return _current_location_id


func get_current_instance() -> Node:
	return _current_instance


func get_location_info(location_id: String) -> Dictionary:
	if not _locations.has(location_id):
		return {}
	return (_locations[location_id] as Dictionary).duplicate(true)


func get_location_name(location_id: String) -> String:
	return str(get_location_info(location_id).get("display_name", location_id))


## 地点出生点。未配置时回退到原点 (0,0,0)。
##
## 之所以放在数据里而不是在代码中按地点硬编码：
## 三个地点的地面高度并不相同（室内地板顶面 y=0，室外门廊顶面 y=0.20），
## 若统一写一个常量，玩家在某处出生时会嵌进地面。
func get_location_spawn(location_id: String) -> Vector3:
	var info := get_location_info(location_id)
	var spawn: Variant = info.get("spawn", null)
	if typeof(spawn) != TYPE_DICTIONARY:
		return Vector3.ZERO
	var pos: Variant = (spawn as Dictionary).get("position", [])
	if typeof(pos) != TYPE_ARRAY:
		return Vector3.ZERO
	var arr: Array = pos
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func get_exit_label(from_location_id: String, target_location_id: String) -> String:
	var info := get_location_info(from_location_id)
	for ex in (info.get("exits", []) as Array):
		var d := ex as Dictionary
		if str(d.get("target", "")) == target_location_id:
			return str(d.get("label", get_location_name(target_location_id)))
	return get_location_name(target_location_id)


func get_visited_locations() -> Array:
	return _visited_locations.keys()


func has_visited(location_id: String) -> bool:
	return _visited_locations.has(location_id)


func can_go_back() -> bool:
	return _visit_stack.size() > 0


func get_previous_location_id() -> String:
	if _visit_stack.is_empty():
		return ""
	return str(_visit_stack[-1])


## 进入指定地点。remember=true 时会把上一个地点压入返回栈。
func enter_location(location_id: String, remember: bool = true) -> bool:
	if _is_switching:
		location_failed.emit(location_id, "地点正在切换中，忽略重复请求")
		return false

	if not _locations.has(location_id):
		location_failed.emit(location_id, "未知地点: %s" % location_id)
		return false
	if _container == null:
		location_failed.emit(location_id, "SceneManager 未绑定地点容器")
		return false

	var world_id := ""
	if world_manager != null:
		world_id = str(world_manager.get_current_world_id())

	_is_switching = true
	var previous_id := _current_location_id
	var ok := false

	if remember and not previous_id.is_empty() and previous_id != location_id:
		_visit_stack.append(previous_id)

	_release_current()

	var info: Dictionary = _locations[location_id]
	var packed: Resource = load(str(info.get("scene", "")))
	if packed == null or not (packed is PackedScene):
		_is_switching = false
		location_failed.emit(location_id, "场景加载失败: %s" % str(info.get("scene", "")))
		return false

	var instance: Node = (packed as PackedScene).instantiate()
	if instance == null:
		_is_switching = false
		location_failed.emit(location_id, "场景实例化失败: %s" % location_id)
		return false

	_container.add_child(instance)
	_current_instance = instance
	_current_location_id = location_id

	if instance.has_method("set_location_id"):
		instance.set_location_id(location_id)
	else:
		instance.set("location_id", location_id)

	_refresh_world_presentation()

	_visited_locations[location_id] = true

	if interaction_manager != null and instance.has_method("collect_hotspots"):
		interaction_manager.set_hotspots(instance.collect_hotspots())

	ok = true
	_is_switching = false

	location_entered.emit(location_id, get_location_name(location_id))

	# 进入地点后求值事件。若世界因此改变，同一地点需要按新世界重刷表现。
	var world_changed_after_enter := false
	if event_manager != null and event_manager.is_ready() and world_manager != null:
		var eval_error: Array = []
		var fired: Array = event_manager.evaluate(
			"enter_location", {"location_id": location_id}, world_manager, eval_error
		)
		if fired.size() > 0:
			var after_id := str(world_manager.get_current_world_id())
			if after_id != world_id:
				world_changed_after_enter = true
				_refresh_world_presentation()
				if interaction_manager != null and instance.has_method("collect_hotspots"):
					interaction_manager.set_hotspots(instance.collect_hotspots())

	if world_changed_after_enter:
		pass

	return ok


## 沿返回栈回到上一个地点。
func go_back() -> bool:
	if _visit_stack.is_empty():
		return false
	var target := str(_visit_stack.pop_back())
	# 回退时不再入栈，否则会形成 A<->B 死循环
	return enter_location(target, false)


func _release_current() -> void:
	if interaction_manager != null:
		interaction_manager.set_hotspots([])
	if _current_instance == null:
		return
	var old = _current_instance
	_current_instance = null
	if is_instance_valid(old):
		if old.is_inside_tree():
			old.get_parent().remove_child(old)
		old.queue_free()


## 按当前世界刷新场景表现，包括热点可见性。
func _refresh_world_presentation() -> void:
	if _current_instance == null or world_manager == null:
		return
	var world_id := str(world_manager.get_current_world_id())
	if world_manager.has_method("is_ready") and not world_manager.is_ready():
		world_id = str(world_manager.get_initial_world_id())
	if _current_instance.has_method("apply_world"):
		_current_instance.apply_world(world_id)


func serialize() -> Dictionary:
	return {
		"current_location_id": _current_location_id,
		"visited_locations": get_visited_locations(),
		"visit_stack": _visit_stack.duplicate(),
	}


func restore(state: Dictionary, out_error: Array = []) -> bool:
	if state.is_empty():
		out_error.append("恢复数据为空")
		return false

	var location_id := str(state.get("current_location_id", ""))
	if location_id.is_empty():
		out_error.append("缺少 current_location_id")
		return false
	if not _locations.has(location_id):
		out_error.append("存档中的地点已不存在: %s" % location_id)
		return false

	var visited_raw: Variant = state.get("visited_locations", [])
	if typeof(visited_raw) != TYPE_ARRAY:
		out_error.append("visited_locations 格式错误")
		return false
	for lid in (visited_raw as Array):
		if not _locations.has(str(lid)):
			out_error.append("访问记录含未知地点: %s" % str(lid))
			return false

	var stack_raw: Variant = state.get("visit_stack", [])
	if typeof(stack_raw) != TYPE_ARRAY:
		out_error.append("visit_stack 格式错误")
		return false
	for lid in (stack_raw as Array):
		if not _locations.has(str(lid)):
			out_error.append("返回栈含未知地点: %s" % str(lid))
			return false

	_visited_locations.clear()
	for lid in (visited_raw as Array):
		_visited_locations[str(lid)] = true
	_visit_stack = (stack_raw as Array).duplicate()
	return true
