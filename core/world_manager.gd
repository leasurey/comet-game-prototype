## WorldManager — 世界状态的唯一权威
##
## 职责边界：
##   只负责「当前处在哪一个世界」以及「世界是怎么一步步变的」。
##   不认识任何地点、不认识任何场景节点、不认识任何 UI。
##
## 设计要点：
##   1. 继承 RefCounted 而非 Node，不依赖 SceneTree，可在 headless 环境下直接实例化做单元测试。
##   2. 世界数据由外部注入（load_from_data），不自己读文件，保证逻辑与环境解耦。
##   3. 世界只能通过 apply_transition() 按规则变更，杜绝运行时随意切换。

class_name WorldManager
extends RefCounted

signal world_changed(from_world_id: String, to_world_id: String, reason_id: String)

const KEY_INITIAL_WORLD := "initial_world"
const KEY_WORLDS := "worlds"

var _world_index: Dictionary = {}
var _initial_world_id: String = ""
var _current_world_id: String = ""
var _change_log: Array = []
var _is_ready: bool = false


## 载入 data/worlds.json 解析后的字典。返回是否成功，失败时给出人类可读原因。
func load_from_data(data: Dictionary, out_error: Array = []) -> bool:
	_world_index.clear()
	_change_log.clear()
	_initial_world_id = ""
	_current_world_id = ""
	_is_ready = false

	if data.is_empty():
		out_error.append("世界数据为空")
		return false

	if not data.has(KEY_INITIAL_WORLD):
		out_error.append("缺少 initial_world 字段")
		return false

	var initial := str(data[KEY_INITIAL_WORLD]).strip_edges()
	if initial.is_empty():
		out_error.append("initial_world 不能为空")
		return false

	var raw_worlds: Variant = data.get(KEY_WORLDS, null)
	if typeof(raw_worlds) != TYPE_ARRAY:
		out_error.append("worlds 必须是数组")
		return false

	var seen: Dictionary = {}
	for entry in (raw_worlds as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			out_error.append("worlds 中存在非对象元素")
			return false
		var w: Dictionary = entry
		var wid := str(w.get("id", "")).strip_edges()
		if wid.is_empty():
			out_error.append("world 缺少 id")
			return false
		if seen.has(wid):
			out_error.append("world id 重复: %s" % wid)
			return false
		seen[wid] = true
		_world_index[wid] = {
			"label": str(w.get("label", wid)),
			"descriptor": str(w.get("descriptor", "")),
			"origin": str(w.get("origin", "")),
		}

	if not _world_index.has(initial):
		out_error.append("initial_world 未在世界表中定义: %s" % initial)
		return false

	# 校验 origin 指向的世界必须存在，避免产生无法追溯的孤儿世界
	for wid_key in _world_index.keys():
		var info: Dictionary = _world_index[wid_key]
		var origin := str(info.get("origin", ""))
		if not origin.is_empty() and not _world_index.has(origin):
			out_error.append("world %s 的 origin 指向不存在的世界: %s" % [wid_key, origin])
			return false

	_initial_world_id = initial
	_current_world_id = initial
	_is_ready = true
	return true


func is_ready() -> bool:
	return _is_ready


func get_current_world_id() -> String:
	return _current_world_id


func get_initial_world_id() -> String:
	return _initial_world_id


func has_world(world_id: String) -> bool:
	return _world_index.has(world_id)


func get_world_ids() -> Array:
	return _world_index.keys()


func get_world_label(world_id: String) -> String:
	if not _world_index.has(world_id):
		return ""
	return str((_world_index[world_id] as Dictionary).get("label", world_id))


## 按规则切换世界。这是改变当前世界的唯一入口。
## reason_id 传入触发这次变化的事件 id，用于写入变更历史，保证可追溯。
func apply_transition(to_world_id: String, reason_id: String, out_error: Array = []) -> bool:
	if not _is_ready:
		out_error.append("WorldManager 尚未载入数据")
		return false
	if to_world_id.is_empty():
		out_error.append("目标世界 id 为空")
		return false
	if not _world_index.has(to_world_id):
		out_error.append("目标世界不存在: %s" % to_world_id)
		return false

	var from_world_id := _current_world_id
	if from_world_id == to_world_id:
		# 同世界不算一次变更，但调用方需要知道结果，这里返回 true 且不记录历史
		return true

	_current_world_id = to_world_id
	_change_log.append({
		"index": _change_log.size(),
		"from": from_world_id,
		"to": to_world_id,
		"reason": reason_id,
	})
	world_changed.emit(from_world_id, to_world_id, reason_id)
	return true


func get_change_log() -> Array:
	return _change_log.duplicate(true)


func get_change_count() -> int:
	return _change_log.size()


func has_ever_changed() -> bool:
	return _change_log.size() > 0


## 序列化为可写入存档的字典。
func serialize() -> Dictionary:
	return {
		"current_world_id": _current_world_id,
		"initial_world_id": _initial_world_id,
		"change_log": _change_log.duplicate(true),
	}


## 从存档恢复。校验失败返回 false，调用方应回退到新游戏而不是继续带病运行。
func restore(state: Dictionary, out_error: Array = []) -> bool:
	if state.is_empty():
		out_error.append("恢复数据为空")
		return false
	var world_id := str(state.get("current_world_id", ""))
	if world_id.is_empty():
		out_error.append("缺少 current_world_id")
		return false
	if not _world_index.has(world_id):
		out_error.append("存档中的世界已不存在: %s" % world_id)
		return false

	var raw_log: Variant = state.get("change_log", [])
	if typeof(raw_log) != TYPE_ARRAY:
		out_error.append("change_log 格式错误")
		return false

	# 逐条校验变更记录，任何一条非法都拒绝恢复，避免半损坏状态
	for entry in (raw_log as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			out_error.append("change_log 中存在非法条目")
			return false
		var rec: Dictionary = entry
		var from_id := str(rec.get("from", ""))
		var to_id := str(rec.get("to", ""))
		if not _world_index.has(from_id) or not _world_index.has(to_id):
			out_error.append("change_log 引用了不存在的世界: %s -> %s" % [from_id, to_id])
			return false

	_current_world_id = world_id
	_change_log = (raw_log as Array).duplicate(true)
	_is_ready = true
	return true
