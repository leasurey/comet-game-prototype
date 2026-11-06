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
## 区域触发：玩家走进某个 Area3D 即触发（黑暗区域穿越用，替代按键）
const TRIGGER_AREA_ENTER := "area_enter"

var _definitions: Dictionary = {}
var _transitions: Array = []
var _history: Dictionary = {}
var _sequence: Array = []
var _flags: Dictionary = {}
var _phase_id: String = ""
var _is_ready := false

## 随机源。未注入时内部自建（种子 0），保证 EventManager 始终可用且结果可复现。
var rng_service = null
## 提供 get_visited_locations() 的对象，通常为 SceneManager 或 GameServices。
var visit_provider = null
## 提供 get_tick() 的对象，通常为 TimeService。
var tick_provider = null


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
		if kind != TRIGGER_ENTER_LOCATION and kind != TRIGGER_INTERACT \
				and kind != TRIGGER_AREA_ENTER:
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

		# 条件在载入期就校验谓词白名单。未知谓词一律拒绝，
		# 避免「写错了条件、运行时静默当作无条件」这类最难排查的缺陷。
		if not ConditionEvaluator.validate(t.get("requires", null), out_error,
				"transition %s.requires" % tid):
			return false

		# 转移规则 id 补登记进事件定义表。
		# 二者原本分表，导致「规则只在 world_transitions.json 中定义」时，
		# 该规则自身产生的存档在重新载入时被 restore 拒绝——实测已复现。
		if not _definitions.has(tid):
			_definitions[tid] = {
				"label": str(t.get("label", tid)),
				"kind": ttype,
				"repeatable": not bool(t.get("once", false)),
				"narrative_hint": "",
			}

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

	# 快照语义：本次求值内所有规则都基于「进入时」的状态判定。
	# 早期实现在循环内直接改世界，后一条规则看到的是被前一条改过的世界，
	# 使结果依赖规则在数组中的排列顺序。
	var snapshot_world := str(world_mgr.get_current_world_id())
	var base_ctx: Dictionary = {
		"world_id": snapshot_world,
		"phase_id": _phase_id,
		"tick": _current_tick(),
		"flags": _flags,
		"visited": _collect_visited(),
		"event_history": _history,
	}

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
		if not required_from.is_empty() and snapshot_world != required_from:
			continue

		# requires 求值。此前 conditional 类型声明了 requires 却从不求值，
		# 实测可复现：条件不成立时事件照样触发。
		if not ConditionEvaluator.evaluate(rule.get("requires", null), base_ctx):
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
			# 伪随机改为具名流：结果只由 (master_seed, 流名, 该流已取次数) 决定。
			# 此前用「规则种子 + 全局事件序列长度」当种子，导致无关事件的发生次数
			# 会改变本规则的取值——实测已复现。
			_ensure_rng()
			var stream_name := str(rule.get("rng_stream", "")).strip_edges()
			if stream_name.is_empty():
				stream_name = "transition:" + str(rule.get("id", ""))
			var weights_raw: Variant = rule.get("weights", [])
			var weights: Array = weights_raw if typeof(weights_raw) == TYPE_ARRAY else []
			var pick_index: int = rng_service.pick_weighted(stream_name, candidates, weights)
			if pick_index < 0 or pick_index >= candidates.size():
				out_error.append("伪随机取值越界: %s" % str(rule.get("id", "")))
				return ""
			return str(candidates[pick_index]).strip_edges()
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


## 历史记录中保存的 id 是否仍能被识别。
## 历史里存的是 transfer rule 的 id，与 events.json 定义的 id 不一定同集合，两边都要认。
func _is_known_event_id(event_id: String) -> bool:
	if _definitions.has(event_id):
		return true
	for t in _transitions:
		if str((t as Dictionary).get("id", "")) == event_id:
			return true
	return false


func serialize() -> Dictionary:
	var payload: Dictionary = {
		"history": _history.duplicate(true),
		"sequence": _sequence.duplicate(),
		"flags": _flags.duplicate(true),
		"phase_id": _phase_id,
	}
	if rng_service != null and rng_service.has_method("get_counters"):
		payload["rng_counters"] = rng_service.get_counters()
	return payload


# ---------------------------------------------------------------- 旗标与阶段

func set_flag(name: String, value: Variant) -> void:
	if name.is_empty():
		return
	_flags[name] = value


func get_flag(name: String, default_value: Variant = null) -> Variant:
	return _flags.get(name, default_value)


func has_flag(name: String) -> bool:
	return _flags.has(name)


func set_phase(phase_id: String) -> void:
	_phase_id = phase_id


func get_phase() -> String:
	return _phase_id


# ---------------------------------------------------------------- 内部

func _ensure_rng() -> void:
	if rng_service != null:
		return
	rng_service = RngService.new()
	rng_service.set_seed(0)


func _current_tick() -> int:
	if tick_provider != null and tick_provider.has_method("get_tick"):
		return int(tick_provider.get_tick())
	return 0


func _collect_visited() -> Array:
	if visit_provider != null and visit_provider.has_method("get_visited_locations"):
		return visit_provider.get_visited_locations()
	return []


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

	# 校验历史中出现的 id 是否仍然可知。
	# 注意：历史记录里存的是 transfer rule 的 id，未必等于 events.json 中定义的 id，
	# 因此两者都要认；两侧都不认识的旧存档必须拒绝，否则后续判定会错乱。
	var history: Dictionary = raw_history
	for eid in history.keys():
		if not _is_known_event_id(str(eid)):
			out_error.append("存档引用了未定义的事件: %s" % str(eid))
			return false

	var flags_raw: Variant = state.get("flags", {})
	if typeof(flags_raw) != TYPE_DICTIONARY:
		out_error.append("flags 格式错误")
		return false

	_history = history.duplicate(true)
	_sequence = (raw_sequence as Array).duplicate()
	_flags = (flags_raw as Dictionary).duplicate(true)
	_phase_id = str(state.get("phase_id", ""))

	# 只恢复计数，不覆盖主种子——主种子属于存档的 meta 区，由 GameServices 负责。
	if rng_service != null and state.has("rng_counters"):
		var counters_raw: Variant = state.get("rng_counters", {})
		if typeof(counters_raw) != TYPE_DICTIONARY:
			out_error.append("rng_counters 格式错误")
			return false
		var rng_err: Array = []
		if not rng_service.restore({
			"master_seed": rng_service.master_seed,
			"counters": counters_raw,
		}, rng_err):
			out_error.append_array(rng_err)
			return false

	_is_ready = true
	return true
