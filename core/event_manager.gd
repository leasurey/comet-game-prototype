## EventManager — 事件触发与历史记录
##
## 职责边界：
##   决定「什么时候该发生什么」，并记录「已经发生过什么」。
##   自身不直接修改世界，而是调用 WorldManager.apply_transition() 完成变更，
##   这样「判定」与「执行」分离，历史记录不会漏记。
##
## 设计要点：
##   继承 RefCounted，数据外部注入，可在 headless 下单元测试。
##   触发判定对所有规则求值一次（Snapshot 语义），返回本次实际触发的事件列表。

class_name EventManager
extends RefCounted

signal event_triggered(event_id: String, from_world_id: String, to_world_id: String, log_text: String)

const TYPE_FIXED := "fixed"
const TYPE_CONDITIONAL := "conditional"
const TYPE_PSEUDO_RANDOM := "pseudo_random"

const TRIGGER_ENTER_LOCATION := "enter_location"
const TRIGGER_INTERACT := "interact"

var _definitions: Dictionary = {}
var _transitions: Array = []
var _history: Dictionary = {}
var _sequence: Array = []
var _is_ready := false


## 载入 data/events.json 与 data/world_transitions.json 解析后的内容。
func load_from_data(events_data: Dictionary, transitions_data: Dictionary, out_error: Array = []) -> bool:
	_definitions.clear()
	_transitions.clear()
	_history.clear()
	_sequence.clear()
	_is_ready = false

	if typeof(events_data) != TYPE_DICTIONARY or events_data.is_empty():
		out_error.append("事件数据为空")
		return false

	var raw_events: Variant = events_data.get("events", null)
	if typeof(raw_events) != TYPE_ARRAY:
		out_error.append("events 必须是数组")
		return false

	for entry in (raw_events as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			out_error.append("events 中存在非对象元素")
			return false
		var e: Dictionary = entry
		var eid := str(e.get("id", "")).strip_edges()
		if eid.is_empty():
			out_error.append("event 缺少 id")
			return false
		_definitions[eid] = {
			"label": str(e.get("label", eid)),
			"kind": str(e.get("kind", TYPE_FIXED)),
			"repeatable": bool(e.get("repeatable", false)),
			"narrative_hint": str(e.get("narrative_hint", "")),
		}

	if typeof(transitions_data) != TYPE_DICTIONARY or transitions_data.is_empty():
		out_error.append("世界转移数据为空")
		return false

	var raw_transitions: Variant = transitions_data.get("transitions", null)
	if typeof(raw_transitions) != TYPE_ARRAY:
		out_error.append("transitions 必须是数组")
		return false

	for entry in (raw_transitions as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			out_error.append("transitions 中存在非对象元素")
			return false
		var t: Dictionary = entry
		var tid := str(t.get("id", "")).strip_edges()
		if tid.is_empty():
			out_error.append("transition 缺少 id")
			return false

		var trigger_raw: Variant = t.get("trigger", {})
		if typeof(trigger_raw) != TYPE_DICTIONARY:
			out_error.append("transition %s 的 trigger 必须是对象" % tid)
			return false
		var trigger: Dictionary = trigger_raw
		var kind := str(trigger.get("kind", "")).strip_edges()
		if kind != TRIGGER_ENTER_LOCATION and kind != TRIGGER_INTERACT:
			out_error.append("transition %s 使用了未知 trigger.kind: %s" % [tid, kind])
			return false

		var ttype := str(t.get("type", TYPE_FIXED)).strip_edges()
		if ttype != TYPE_FIXED and ttype != TYPE_CONDITIONAL and ttype != TYPE_PSEUDO_RANDOM:
			out_error.append("transition %s 使用了未知 type: %s" % [tid, ttype])
			return false

		if ttype == TYPE_PSEUDO_RANDOM:
			var cands_raw: Variant = t.get("candidate_worlds", [])
			if typeof(cands_raw) != TYPE_ARRAY or (cands_raw as Array).is_empty():
				out_error.append("pseudo_random transition %s 必须提供非空的 candidate_worlds" % tid)
				return false

		_transitions.append(t.duplicate(true))

	_is_ready = true
	return true


func is_ready() -> bool:
	return _is_ready


func has_occurred(event_id: String) -> bool:
	return _history.has(event_id)


func get_occurrence_count(event_id: String) -> int:
	if not _history.has(event_id):
		return 0
	return int((_history[event_id] as Dictionary).get("count", 0))


func get_sequence() -> Array:
	return _sequence.duplicate()


func get_history() -> Dictionary:
	return _history.duplicate(true)


func get_definition(event_id: String) -> Dictionary:
	if not _definitions.has(event_id):
		return {}
	return (_definitions[event_id] as Dictionary).duplicate(true)


func get_narrative_hint(event_id: String) -> String:
	var def := get_definition(event_id)
	return str(def.get("narrative_hint", ""))


## 核心求值入口。
##
## kind      —— 触发类型：enter_location / interact
## context   —— 上下文，例如 {"location_id": "dark_road"} 或 {"hotspot_id": "..."}
## world_mgr —— 世界管理器，由 EventManager 调用其 apply_transition 完成实际变更
##
## 返回本次求值中实际发生的事件 id 列表（世界未变化的不计入）。
func evaluate(kind: String, context: Dictionary, world_mgr, out_error: Array = []) -> Array:
	var fired: Array = []
	if not _is_ready:
		out_error.append("EventManager 尚未载入数据")
		return fired
	if world_mgr == null:
		out_error.append("evaluate 缺少 WorldManager")
		return fired

	for t in _transitions:
		var rule: Dictionary = t
		var trigger: Dictionary = rule.get("trigger", {})
		if str(trigger.get("kind", "")) != kind:
			continue

		var rule_id := str(rule.get("id", ""))

		# once 语义：同一事件在整个存档周期内只允许发生一次
		if bool(rule.get("once", false)) and has_occurred(rule_id):
			continue

		# 逐条匹配上下文键值，支持 location_id / hotspot_id 等不同触发键
		var ctx_matched := true
		for key in trigger.keys():
			if key == "kind":
				continue
			var expected := str(trigger[key])
			var actual := str(context.get(key, ""))
			if expected != actual:
				ctx_matched = false
				break
		if not ctx_matched:
			continue

		var required_from := str(rule.get("require_from_world", ""))
		if not required_from.is_empty() and str(world_mgr.get_current_world_id()) != required_from:
			continue

		var target_world_id := _resolve_target_world(rule, out_error)
		if target_world_id.is_empty():
			continue

		var before := str(world_mgr.get_current_world_id())
		var apply_err: Array = []
		if not world_mgr.apply_transition(target_world_id, rule_id, apply_err):
			out_error.append_array(apply_err)
			continue
		if str(world_mgr.get_current_world_id()) == before:
			# 目标与当前世界相同，视作未发生
			continue

		_record(rule_id)
		fired.append(rule_id)
		event_triggered.emit(
			rule_id,
			before,
			str(world_mgr.get_current_world_id()),
			str(rule.get("log", ""))
		)

	return fired


## 根据规则类型解析目标世界。返回空字符串表示该规则本次不应生效。
func _resolve_target_world(rule: Dictionary, out_error: Array) -> String:
	var ttype := str(rule.get("type", TYPE_FIXED))
	match ttype:
		TYPE_FIXED:
			return str(rule.get("to_world", "")).strip_edges()
		TYPE_CONDITIONAL:
			# 条件事件目前与固定事件走同一条解析路径，
			# 差别在于 require_from_world 必须显式给出，此约束已在 evaluate 中生效。
			return str(rule.get("to_world", "")).strip_edges()
		TYPE_PSEUDO_RANDOM:
			var candidates_raw: Variant = rule.get("candidate_worlds", [])
			if typeof(candidates_raw) != TYPE_ARRAY:
				return ""
			var candidates: Array = candidates_raw
			if candidates.is_empty():
				return ""
			# 伪随机：结果必须落在允许范围内，且由「规则种子 + 触发序号」决定。
			# 相同输入必然得到相同结果，可复现，不是全书意义的随机。
			var rule_seed := int(rule.get("seed", 0))
			var rng := RandomNumberGenerator.new()
			rng.seed = rule_seed + _sequence.size()
			var pick: int = rng.randi() % candidates.size()
			return str(candidates[pick]).strip_edges()
		_:
			out_error.append("未知 transition type: %s" % ttype)
	return ""


func _record(event_id: String) -> void:
	var index := _sequence.size()
	_sequence.append(event_id)
	if not _history.has(event_id):
		_history[event_id] = {"count": 0, "first_index": index, "last_index": index}
	var rec: Dictionary = _history[event_id]
	rec["count"] = int(rec.get("count", 0)) + 1
	rec["last_index"] = index


func serialize() -> Dictionary:
	return {
		"history": _history.duplicate(true),
		"sequence": _sequence.duplicate(),
	}


func restore(state: Dictionary, out_error: Array = []) -> bool:
	if state.is_empty():
		out_error.append("恢复数据为空")
		return false

	var raw_history: Variant = state.get("history", {})
	if typeof(raw_history) != TYPE_DICTIONARY:
		out_error.append("history 格式错误")
		return false
	var raw_sequence: Variant = state.get("sequence", [])
	if typeof(raw_sequence) != TYPE_ARRAY:
		out_error.append("sequence 格式错误")
		return false

	# 校验历史中出现的事件 id 都还在当前定义集合内，
	# 防止旧存档引用已删除的事件导致后续判定错乱
	var history: Dictionary = raw_history
	for eid in history.keys():
		if not _definitions.has(str(eid)):
			out_error.append("存档引用了未定义的事件: %s" % str(eid))
			return false

	_history = history.duplicate(true)
	_sequence = (raw_sequence as Array).duplicate()
	_is_ready = true
	return true
