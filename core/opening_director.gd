## OpeningDirector — 序章阶段机
##
## 职责边界：
##   只负责「玩家现在处在序章的哪一段、下一段什么时候来」。
##   不直接改剧情数据，不碰 NPC 记忆，不做现实切换。
##   具体每一步做什么写在 data/opening.json 里（数据驱动），
##   本类只实现几种通用的条件判断与效果。
##
## 触发条件（complete.kind）：
##   enter_area  玩家进入以 center 为圆心、radius 为半径的圆，触发一次
##   dwell       玩家持续待在该圆内累计 seconds 秒
##   dialogue    与该 npc 的对话正常结束过一次
##
## 进入阶段时的效果（on_enter[].kind）：
##   message     HUD 文本
##   npc_greet   npc 进入 radius 范围内时提示（一次性）
##   blackout    停电：关掉电灯，保留烛光/炉火/门廊灯
##   fact        给玩家记一条认知事实
##
## 设计取舍：停电**不切换 WorldManager 的世界**。
##   电影里的停电发生在现实分裂之前，属于同一个现实内的事件；
##   若借用 world_beta 会造成「停电即穿越」的语义污染。

class_name OpeningDirector
extends Node

signal phase_changed(phase_id: String, objective: String)
signal opening_finished()
signal blackout_started()

const DATA_PATH := "res://data/opening.json"

## 这些名字的灯属于「市电照明」，停电时要灭
const ELECTRIC_LIGHT_KEYS := ["LivingLamp", "DiningLamp", "KitchenLamp", "FoyerLamp", "StudyLight"]

var _phases: Dictionary = {}
var _current: String = ""
var _objective: String = ""
var _elapsed: float = 0.0
var _dwell: float = 0.0
var _started := false
var _finished := false

var _greeted: Dictionary = {}
var _talked: Dictionary = {}
var _blackout_done := false

var _main: Node = null
var _ui = null


func setup(main_node: Node) -> void:
	_main = main_node


## 载入阶段数据。返回是否成功。
func load_data(path: String = DATA_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("OpeningDirector: 找不到 %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("OpeningDirector: %s 不是合法 JSON 对象" % path)
		return false
	var d: Dictionary = parsed
	var list: Array = d.get("phases", [])
	if list.is_empty():
		return false
	_phases.clear()
	for p in list:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pid := str((p as Dictionary).get("id", ""))
		if pid.is_empty():
			continue
		_phases[pid] = p
	var start_id := str(d.get("start", ""))
	if not _phases.has(start_id):
		# 兜底：用第一个阶段
		start_id = str((list[0] as Dictionary).get("id", ""))
	_current = start_id
	return not _current.is_empty()


func is_running() -> bool:
	return _started and not _finished


func get_phase_id() -> String:
	return _current


func get_objective() -> String:
	return _objective


func start(ui = null) -> void:
	if _started:
		return
	_ui = ui
	_started = true
	_finished = false
	_enter_phase(_current)


## 由 main 每帧驱动。
func tick(delta: float, player_pos: Vector3) -> void:
	if not is_running():
		return
	_elapsed += delta
	var phase: Dictionary = _phases.get(_current, {})
	if phase.is_empty():
		return
	_run_runtime_effects(phase, player_pos)
	if _check_complete(phase, delta, player_pos):
		var next_id := str(phase.get("next", ""))
		if next_id.is_empty() or not _phases.has(next_id):
			_finished = true
			_objective = ""
			opening_finished.emit()
			return
		_enter_phase(next_id)


## 对话正常结束时由 main 通知。
func notify_dialogue_closed(npc_id: String) -> void:
	if npc_id.is_empty():
		return
	_talked[npc_id] = true


# ------------------------------------------------------------------ 内部

func _enter_phase(phase_id: String) -> void:
	_current = phase_id
	_dwell = 0.0
	var phase: Dictionary = _phases.get(phase_id, {})
	_objective = str(phase.get("objective", ""))
	for eff in (phase.get("on_enter", []) as Array):
		_apply_effect(eff)
	phase_changed.emit(phase_id, _objective)


func _apply_effect(eff: Variant) -> void:
	if typeof(eff) != TYPE_DICTIONARY:
		return
	var e: Dictionary = eff
	match str(e.get("kind", "")):
		"message":
			_show_message(str(e.get("text", "")))
		"blackout":
			_apply_blackout()
		"fact":
			var svc = _svc()
			var cm = svc.cognition if svc != null else null
			if cm != null:
				var world_id := str(e.get("world", ""))
				if world_id.is_empty() and svc.world_manager != null:
					world_id = svc.world_manager.get_current_world_id()
				cm.learn(str(e.get("id", "")), str(e.get("source", "observe")),
					str(e.get("source_id", "")), world_id, _current_tick(svc))


## 运行期效果：只在条件满足时提示一次。
func _run_runtime_effects(phase: Dictionary, player_pos: Vector3) -> void:
	for eff in (phase.get("on_enter", []) as Array):
		if typeof(eff) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = eff
		if str(e.get("kind", "")) != "npc_greet":
			continue
		var npc_id := str(e.get("npc", ""))
		if npc_id.is_empty() or _greeted.has(npc_id):
			continue
		var npcm = _svc().npc_manager if _svc() != null else null
		if npcm == null:
			continue
		var npc: NPC = npcm.get_npc(npc_id)
		if npc == null:
			continue
		var r := float(e.get("radius", 3.0))
		if npc.global_position.distance_to(player_pos) <= r:
			_greeted[npc_id] = true
			_show_message(str(e.get("text", "")))


func _check_complete(phase: Dictionary, delta: float, player_pos: Vector3) -> bool:
	var c: Variant = phase.get("complete", null)
	if typeof(c) != TYPE_DICTIONARY:
		return false
	var cond: Dictionary = c
	match str(cond.get("kind", "")):
		"enter_area":
			return _in_area(cond, player_pos)
		"dwell":
			if _in_area(cond, player_pos):
				_dwell += delta
				return _dwell >= float(cond.get("seconds", 3.0))
			return false
		"dialogue":
			return _talked.has(str(cond.get("npc", "")))
	return false


func _in_area(cond: Dictionary, player_pos: Vector3) -> bool:
	var center: Array = cond.get("center", [0.0, 0.0])
	if center.size() < 2:
		return false
	var c := Vector2(float(center[0]), float(center[1]))
	var p := Vector2(player_pos.x, player_pos.z)
	return p.distance_to(c) <= float(cond.get("radius", 2.0))


func _show_message(text: String) -> void:
	if text.is_empty() or _ui == null:
		return
	if _ui.has_method("set_message"):
		_ui.set_message(text, 6.0)


## 停电：关掉市电照明，保留烛光/炉火/门廊灯。
func _apply_blackout() -> void:
	if _blackout_done:
		return
	_blackout_done = true
	var sm = _svc().scene_manager if _svc() != null else null
	if sm == null:
		return
	var inst: Node = sm.get_current_instance()
	if inst == null:
		return
	var lights: Array = []
	_collect_lights(inst, lights)
	var dimmed := 0
	for l in lights:
		var ol := l as OmniLight3D
		if ol == null:
			continue
		var key := str(ol.name)
		var is_electric := false
		for k in ELECTRIC_LIGHT_KEYS:
			if key.begins_with(k):
				is_electric = true
				break
		if is_electric:
			ol.light_energy *= 0.04
			dimmed += 1
	blackout_started.emit()
	print("[OPENING] 停电：已调暗 %d 盏市电灯" % dimmed)


func _collect_lights(n: Node, out: Array) -> void:
	if n is OmniLight3D:
		out.append(n)
	for c in n.get_children():
		_collect_lights(c, out)


func _svc():
	return get_node_or_null("/root/GameServices")


## 取当前 tick；GameServices 的 get_tick 返回类型不固定，这里统一转 int。
func _current_tick(svc) -> int:
	if svc == null or not svc.has_method("get_tick"):
		return -1
	var v = svc.get_tick()
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	return -1


# ------------------------------------------------------------------ 序列化

func serialize() -> Dictionary:
	return {
		"current": _current,
		"finished": _finished,
		"talked": _talked.duplicate(),
		"greeted": _greeted.duplicate(),
		"blackout": _blackout_done,
	}


func restore(state: Dictionary) -> void:
	if state.is_empty():
		return
	var cur := str(state.get("current", ""))
	if _phases.has(cur):
		_current = cur
		var phase: Dictionary = _phases.get(cur, {})
		_objective = str(phase.get("objective", ""))
	_finished = bool(state.get("finished", false))
	_talked = (state.get("talked", {}) as Dictionary).duplicate()
	_greeted = (state.get("greeted", {}) as Dictionary).duplicate()
	_blackout_done = bool(state.get("blackout", false))
	_started = true
	if _blackout_done:
		_apply_blackout()
	phase_changed.emit(_current, _objective)
