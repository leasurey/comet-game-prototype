## DataValidator — 四份 JSON 的交叉校验统一入口
##
## 为什么单独存在：
##   各 Manager 的 load_from_data 只校验"自己那份数据内部"是否自洽，
##   但真正的坑都在**跨文件引用**上：
##     - locations.json 的 variants 写了一个 worlds.json 里不存在的现实
##     - transitions 的 to_world 指向拼错的世界 id
##     - area_enter 触发器忘了写 area_id（运行时永远不会触发，静默失效）
##     - exits 指向不存在的地点
##   这些错误在当前实现里要么被静默忽略，要么要到很久以后才以奇怪的方式暴露。
##
## 设计约定：
##   1. 纯静态、无状态、不读文件（数据由调用方注入），可脱离场景树单测。
##   2. 每条错误都自带「文件名 + 对象 + 字段 + 原因」四要素，便于直接定位。
##   3. 一次收集全部错误而不是遇到第一个就返回——修数据时需要一次看到所有问题。
##   4. 只校验**数据层**能判定的东西；场景文件内部结构（变体节点是否存在）
##      由 world_variant_test 负责，避免这里加载全部场景拖慢启动。

class_name DataValidator
extends RefCounted

const TRIGGER_KINDS := ["enter_location", "interact", "area_enter"]
const TRANSITION_TYPES := ["fixed", "conditional", "pseudo_random"]


## 返回 {"ok": bool, "errors": Array[String]}。
static func validate(worlds: Dictionary, events: Dictionary, transitions: Dictionary,
		locations: Dictionary) -> Dictionary:
	var errors: Array = []

	var world_ids := _collect_world_ids(worlds, errors)
	_validate_worlds(worlds, world_ids, errors)
	_validate_events(events, errors)
	_validate_transitions(transitions, world_ids, locations, errors)
	_validate_locations(locations, world_ids, errors)

	return {"ok": errors.is_empty(), "errors": errors}


# ------------------------------------------------------------------ worlds

static func _collect_world_ids(worlds: Dictionary, errors: Array) -> Array:
	var ids: Array = []
	var raw: Variant = worlds.get("worlds", [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("worlds.json: worlds 必须是数组")
		return ids
	var seen: Dictionary = {}
	for entry in (raw as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("worlds.json: worlds 中存在非对象元素")
			continue
		var wid := str((entry as Dictionary).get("id", "")).strip_edges()
		if wid.is_empty():
			errors.append("worlds.json: 存在缺少 id 的世界")
			continue
		if seen.has(wid):
			errors.append("worlds.json: 世界 id 重复: %s" % wid)
			continue
		seen[wid] = true
		ids.append(wid)
	return ids


static func _validate_worlds(worlds: Dictionary, world_ids: Array, errors: Array) -> void:
	var initial := str(worlds.get("initial_world", "")).strip_edges()
	if initial.is_empty():
		errors.append("worlds.json: 缺少 initial_world")
	elif not world_ids.has(initial):
		errors.append("worlds.json: initial_world 未定义: %s" % initial)

	var raw: Variant = worlds.get("worlds", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	for entry in (raw as Array):
		var w: Dictionary = entry
		var wid := str(w.get("id", ""))
		var origin := str(w.get("origin", "")).strip_edges()
		if not origin.is_empty() and not world_ids.has(origin):
			errors.append("worlds.json: 世界 %s 的 origin 指向未定义世界: %s" % [wid, origin])


# ------------------------------------------------------------------ events

static func _validate_events(events: Dictionary, errors: Array) -> void:
	var raw: Variant = events.get("events", [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("events.json: events 必须是数组")
		return
	var seen: Dictionary = {}
	for entry in (raw as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("events.json: events 中存在非对象元素")
			continue
		var eid := str((entry as Dictionary).get("id", "")).strip_edges()
		if eid.is_empty():
			errors.append("events.json: 存在缺少 id 的事件")
			continue
		if seen.has(eid):
			errors.append("events.json: 事件 id 重复: %s" % eid)
		seen[eid] = true


# ------------------------------------------------------------------ transitions

static func _validate_transitions(transitions: Dictionary, world_ids: Array,
		locations: Dictionary, errors: Array) -> void:
	var raw: Variant = transitions.get("transitions", [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("world_transitions.json: transitions 必须是数组")
		return

	var location_ids := _collect_location_ids(locations)
	var seen: Dictionary = {}

	for entry in (raw as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("world_transitions.json: transitions 中存在非对象元素")
			continue
		var t: Dictionary = entry
		var tid := str(t.get("id", "")).strip_edges()
		if tid.is_empty():
			errors.append("world_transitions.json: 存在缺少 id 的转移规则")
			continue
		if seen.has(tid):
			errors.append("world_transitions.json: 转移规则 id 重复: %s" % tid)
		seen[tid] = true

		var trigger_raw: Variant = t.get("trigger", {})
		if typeof(trigger_raw) != TYPE_DICTIONARY:
			errors.append("world_transitions.json: %s.trigger 必须是对象" % tid)
			continue
		var trigger: Dictionary = trigger_raw
		var kind := str(trigger.get("kind", "")).strip_edges()
		if not TRIGGER_KINDS.has(kind):
			errors.append("world_transitions.json: %s.trigger.kind 非法: %s" % [tid, kind])
		elif kind == "area_enter" and str(trigger.get("area_id", "")).strip_edges().is_empty():
			# 少了 area_id 的 area_enter 永远不会被任何 portal 命中——静默失效，最难查
			errors.append("world_transitions.json: %s 是 area_enter 但缺少 area_id" % tid)
		elif kind == "enter_location":
			var loc := str(trigger.get("location_id", "")).strip_edges()
			if loc.is_empty():
				errors.append("world_transitions.json: %s 是 enter_location 但缺少 location_id" % tid)
			elif not location_ids.has(loc):
				errors.append("world_transitions.json: %s 的触发地点未定义: %s" % [tid, loc])

		var ttype := str(t.get("type", "fixed")).strip_edges()
		if not TRANSITION_TYPES.has(ttype):
			errors.append("world_transitions.json: %s.type 非法: %s" % [tid, ttype])

		var to_world := str(t.get("to_world", "")).strip_edges()
		if to_world.is_empty():
			errors.append("world_transitions.json: %s 缺少 to_world" % tid)
		elif not world_ids.has(to_world):
			errors.append("world_transitions.json: %s.to_world 未定义: %s" % [tid, to_world])

		var from_world := str(t.get("require_from_world", "")).strip_edges()
		if not from_world.is_empty() and not world_ids.has(from_world):
			errors.append("world_transitions.json: %s.require_from_world 未定义: %s" % [tid, from_world])

		var cands: Variant = t.get("candidate_worlds", [])
		if typeof(cands) == TYPE_ARRAY:
			for c in (cands as Array):
				if not world_ids.has(str(c)):
					errors.append("world_transitions.json: %s.candidate_worlds 含未定义世界: %s" % [tid, str(c)])
		if ttype == "pseudo_random" and (typeof(cands) != TYPE_ARRAY or (cands as Array).is_empty()):
			errors.append("world_transitions.json: %s 是 pseudo_random 但 candidate_worlds 为空" % tid)


# ------------------------------------------------------------------ locations

static func _collect_location_ids(locations: Dictionary) -> Array:
	var ids: Array = []
	var raw: Variant = locations.get("locations", [])
	if typeof(raw) != TYPE_ARRAY:
		return ids
	for entry in (raw as Array):
		if typeof(entry) == TYPE_DICTIONARY:
			var lid := str((entry as Dictionary).get("id", "")).strip_edges()
			if not lid.is_empty():
				ids.append(lid)
	return ids


static func _validate_locations(locations: Dictionary, world_ids: Array, errors: Array) -> void:
	var raw: Variant = locations.get("locations", [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("locations.json: locations 必须是数组")
		return

	var ids := _collect_location_ids(locations)
	var seen: Dictionary = {}
	var start := str(locations.get("start_location", "")).strip_edges()
	if start.is_empty():
		errors.append("locations.json: 缺少 start_location")

	for entry in (raw as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("locations.json: locations 中存在非对象元素")
			continue
		var loc: Dictionary = entry
		var lid := str(loc.get("id", "")).strip_edges()
		if lid.is_empty():
			continue
		if seen.has(lid):
			errors.append("locations.json: 地点 id 重复: %s" % lid)
		seen[lid] = true

		if str(loc.get("scene", "")).strip_edges().is_empty():
			errors.append("locations.json: 地点 %s 缺少 scene" % lid)

		# 出生点：必须是三个数字的数组，否则运行时会静默落到原点并嵌进地面
		var spawn: Variant = loc.get("spawn", null)
		if typeof(spawn) == TYPE_DICTIONARY:
			var pos: Variant = (spawn as Dictionary).get("position", [])
			if typeof(pos) != TYPE_ARRAY or (pos as Array).size() != 3:
				errors.append("locations.json: 地点 %s 的 spawn.position 必须是长度 3 的数组" % lid)
			else:
				for v in (pos as Array):
					if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
						errors.append("locations.json: 地点 %s 的 spawn.position 含非数字" % lid)
						break

		# variants：必须声明，且每个都必须是已定义现实
		var variants: Variant = loc.get("variants", null)
		if typeof(variants) != TYPE_ARRAY or (variants as Array).is_empty():
			errors.append("locations.json: 地点 %s 未声明 variants" % lid)
		else:
			for v in (variants as Array):
				var vid := str(v)
				if not world_ids.has(vid):
					errors.append("locations.json: 地点 %s 的 variants 含未定义现实: %s" % [lid, vid])

		# exits：目标必须存在
		var exits: Variant = loc.get("exits", [])
		if typeof(exits) != TYPE_ARRAY:
			errors.append("locations.json: 地点 %s 的 exits 必须是数组" % lid)
		else:
			for ex in (exits as Array):
				if typeof(ex) != TYPE_DICTIONARY:
					errors.append("locations.json: 地点 %s 的 exits 含非法条目" % lid)
					continue
				var target := str((ex as Dictionary).get("target", "")).strip_edges()
				if target.is_empty():
					errors.append("locations.json: 地点 %s 存在缺少 target 的出口" % lid)
				elif not ids.has(target):
					errors.append("locations.json: 地点 %s 的出口指向未定义地点: %s" % [lid, target])

	if not start.is_empty() and not ids.has(start):
		errors.append("locations.json: start_location 未定义: %s" % start)
