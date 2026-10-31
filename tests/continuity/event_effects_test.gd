## ContinuityEventEffectsTest — 批次 2：事件 effects 与三条触发线
##
## 用法：godot --headless --script res://tests/continuity/event_effects_test.gd
##
## E1 interact 触发：evaluate("interact") 命中 evt_return_to_house → set_flag 生效
## E2 纯效果事件（无 to_world）可触发并入档
## E3 grant_fact effect 授予认知（黑路穿越迁入 effects）
## E4 对话 fires：听 kevin_sticky → evt_sticky_discussed → set_flag + grant_fact
## E5 NPC arrived 触发：send_to_room → arrived → evt_kevin_arrived_test → set_flag
## E6 事务回滚：含坏 effect 的规则不生效、不入档、不残留状态
## E7 log-only effects 载入期拒绝
## E8 未知 effect kind 载入期拒绝

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _main = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false

# E5 状态
var _kevin_arrived_flag := false


func _initialize() -> void:
	print("=== COMET continuity event effects test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_e1_interact_trigger"),
		Callable(self, "step_e2_grant_fact"),
		Callable(self, "step_e3_dialogue_fires"),
		Callable(self, "step_e4_npc_arrived"),
		Callable(self, "step_e5_rollback"),
		Callable(self, "step_e6_validation"),
		Callable(self, "step_report"),
	]


func _process(_d: float) -> bool:
	if _idx >= _steps.size():
		return false
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_ticks = 0
		_t_state = 0
	else:
		_ticks += 1
		if _ticks > 500:
			_check(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
	return false


func _check(cond: bool, label: String, detail: String = "") -> void:
	var suffix := "" if detail == "" else " | " + detail
	if cond:
		_pass += 1
	else:
		_fail += 1
	_lines.append("[%s] %s%s" % ["PASS" if cond else "FAIL", label, suffix])


func step_setup() -> bool:
	if _t_state == 0:
		var sm = _svc.save_manager
		sm.use_test_path("event_effects")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	return _ticks > 15


## E1  interact 触发 → evt_return_to_house（纯效果事件，无世界转移）
func step_e1_interact_trigger() -> bool:
	if _t_state == 0:
		var em = _svc.event_manager
		_check(em != null, "E1 前置：EventManager 存在")
		_check(not em.has_occurred("evt_return_to_house"), "E1 前置：evt_return_to_house 未发生")
		_check(not em.has_flag("returned_house_exterior"), "E1 前置：flag 未设置")
		# 模拟 _on_hotspot_activated 的 interact 求值
		var errs: Array = []
		var fired: Array = em.evaluate("interact", {
			"hotspot_id": "DoorToInterior",
			"location_id": "house_exterior",
		}, _svc.world_manager, errs)
		_check(errs.is_empty(), "E1 求值无错误", str(errs))
		_check(fired.has("evt_return_to_house"), "E1 interact 触发了 evt_return_to_house", str(fired))
		_check(em.has_flag("returned_house_exterior"), "E1 set_flag effect 生效")
		_check(em.has_occurred("evt_return_to_house"), "E1 事件已入档")
		# 不应改变世界（纯效果事件）
		_check(_svc.world_manager.get_current_world_id() == "world_alpha",
			"E1 纯效果事件不改变世界", _svc.world_manager.get_current_world_id())
		return true
	return false


## E2  grant_fact effect：黑路穿越的 effects 授予 fact_dark_road
func step_e2_grant_fact() -> bool:
	if _t_state == 0:
		var cog = _svc.cognition
		var em = _svc.event_manager
		_check(not cog.knows("fact_dark_road"), "E2 前置：不知道 fact_dark_road")
		# 用 area_enter 触发黑路穿越（真实 portal 事件链）
		var errs: Array = []
		var fired: Array = em.evaluate("area_enter", {
			"area_id": "dark_far_end",
		}, _svc.world_manager, errs)
		_check(errs.is_empty(), "E2 黑路穿越无错误", str(errs))
		_check(not fired.is_empty(), "E2 黑路穿越事件触发", str(fired))
		_check(cog.knows("fact_dark_road"), "E2 grant_fact effect 授予 fact_dark_road")
		# 验证来源标注
		var rec: Dictionary = cog.get_fact_record("fact_dark_road") \
				if cog.has_method("get_fact_record") else {}
		if not rec.is_empty():
			_check(str(rec.get("source_kind", "")) == "observe",
				"E2 来源标注 observe", str(rec.get("source_kind", "")))
		return true
	return false


## E3  对话 fires：听 kevin_sticky → evt_sticky_discussed → set_flag + grant_fact
func step_e3_dialogue_fires() -> bool:
	if _t_state == 0:
		var dm = _svc.dialogue_manager
		var cog = _svc.cognition
		var em = _svc.event_manager
		# 前置：需要 fact_sticky_note 才能听 kevin_sticky
		cog.learn("fact_sticky_note", "inspect", "StickyNote", "world_alpha", 0)
		_check(not cog.knows("fact_kevin_knows_sticky"), "E3 前置：不知道 fact_kevin_knows_sticky")
		_check(not em.has_flag("sticky_discussed"), "E3 前置：flag 未设置")
		# 听对话（返回 fires 列表）
		var heard: Dictionary = dm.hear("kevin_sticky", "world_alpha", 1)
		_check(bool(heard.get("ok", false)), "E3 听到 kevin_sticky", str(heard.get("error", "")))
		var fired_ids: Array = heard.get("fired", [])
		_check(fired_ids.has("evt_sticky_discussed"), "E3 fires 列出 evt_sticky_discussed", str(fired_ids))
		# 调用方负责向 EventManager 点火（main._show_dialogue_node 的逻辑）
		for eid in fired_ids:
			var errs: Array = []
			em.fire_event(str(eid), {"node_id": "kevin_sticky", "speaker": "kevin"},
					_svc.world_manager, errs)
			_check(errs.is_empty(), "E3 fire_event 无错误", str(errs))
		_check(em.has_flag("sticky_discussed"), "E3 set_flag effect 生效")
		_check(cog.knows("fact_kevin_knows_sticky"), "E3 grant_fact effect 授予认知")
		_check(em.has_occurred("evt_sticky_discussed"), "E3 事件已入档")
		return true
	return false


## E4  NPC arrived 触发：send_to_room → arrived → evt_kevin_arrived_test → set_flag
func step_e4_npc_arrived() -> bool:
	if _t_state == 0:
		var em = _svc.event_manager
		var npcm = _svc.npc_manager
		_check(em != null and npcm != null, "E4 前置：EventManager + NPCManager 存在")
		_check(not em.has_flag("kevin_reached_target_test"), "E4 前置：flag 未设置")
		# 确保 nav 就绪且 kevin 在场
		if not npcm.is_nav_ready() or npcm.get_npc("kevin") == null:
			if _ticks > 300:
				_check(false, "E4 前置：nav 就绪 + kevin 在场",
					"nav=%s kevin=%s" % [str(npcm.is_nav_ready()), str(npcm.get_npc("kevin") != null)])
				return true
			return false
		# 派目标 → 等到达 → npc_arrived 信号 → GameServices._on_npc_arrived → evaluate
		var sent: bool = npcm.send_to_room("kevin", "kitchen")
		_check(sent, "E4 派目标成功")
		_t_state = 1
		return false
	if _t_state == 1:
		# 等 Kevin 到达（walking → idle）
		var npcm = _svc.npc_manager
		var kevin = npcm.get_npc("kevin")
		if kevin != null and kevin.state == "walking":
			if _ticks > 350:
				_check(false, "E4 Kevin 超时未到达", "state=%s" % kevin.state)
				return true
			return false
		# 到达了（或 idle）——检查事件是否触发
		var em = _svc.event_manager
		_check(em.has_flag("kevin_reached_target_test"),
			"E4 npc_arrived 触发事件并 set_flag",
			"state=%s flag=%s" % [kevin.state if kevin else "?", str(em.has_flag("kevin_reached_target_test"))])
		_check(em.has_occurred("evt_kevin_arrived_test"), "E4 事件已入档")
		return true
	return false


## E5  事务回滚：含坏 effect（无 cognition_service 的 grant_fact）的规则不生效
func step_e5_rollback() -> bool:
	if _t_state == 0:
		# 构造一个独立 EventManager，注入空的 cognition_service（grant_fact 会失败）
		var em2 = load("res://core/event_manager.gd").new()
		var errs: Array = []
		var ok: bool = em2.load_from_data({
			"events": [{"id": "evt_rollback_test"}],
		}, {
			"transitions": [{
				"id": "evt_rollback_test",
				"type": "fixed",
				"trigger": {"kind": "interact", "hotspot_id": "TestSpot"},
				"to_world": "",
				"effects": [
					{"kind": "set_flag", "name": "rollback_flag", "value": true},
					{"kind": "grant_fact", "fact": "fact_rollback", "source": "observe"},
				],
			}],
		}, errs)
		_check(ok, "E5 载入含 grant_fact 的规则成功", str(errs))
		# 不注入 cognition_service → grant_fact 应失败 → 事务回滚
		var errs2: Array = []
		var fired: Array = em2.evaluate("interact", {"hotspot_id": "TestSpot"}, _svc.world_manager, errs2)
		_check(fired.is_empty(), "E5 回滚后事件不入档", str(fired))
		_check(not errs2.is_empty(), "E5 回滚报告了错误", str(errs2))
		_check(not em2.has_flag("rollback_flag"), "E5 set_flag 已回滚（未残留）")
		_check(not em2.has_occurred("evt_rollback_test"), "E5 事件未记录")
		return true
	return false


## E6  载入期校验：log-only 和未知 kind 拒绝
func step_e6_validation() -> bool:
	if _t_state == 0:
		# log-only 拒绝
		var em1 = load("res://core/event_manager.gd").new()
		var errs1: Array = []
		var ok1: bool = em1.load_from_data({
			"events": [{"id": "e1"}],
		}, {
			"transitions": [{
				"id": "e1", "type": "fixed",
				"trigger": {"kind": "interact", "hotspot_id": "X"},
				"to_world": "",
				"effects": [{"kind": "log", "text": "只有文字"}],
			}],
		}, errs1)
		_check(not ok1, "E6 log-only effects 拒绝载入")
		_check(errs1.size() > 0, "E6 log-only 报了错误", str(errs1))

		# 未知 kind 拒绝
		var em2 = load("res://core/event_manager.gd").new()
		var errs2: Array = []
		var ok2: bool = em2.load_from_data({
			"events": [{"id": "e2"}],
		}, {
			"transitions": [{
				"id": "e2", "type": "fixed",
				"trigger": {"kind": "interact", "hotspot_id": "X"},
				"to_world": "",
				"effects": [{"kind": "explode", "target": "everything"}],
			}],
		}, errs2)
		_check(not ok2, "E6 未知 effect kind 拒绝载入")
		_check(errs2.size() > 0, "E6 未知 kind 报了错误", str(errs2))

		# 无 to_world 且无 effects 拒绝
		var em3 = load("res://core/event_manager.gd").new()
		var errs3: Array = []
		var ok3: bool = em3.load_from_data({
			"events": [{"id": "e3"}],
		}, {
			"transitions": [{
				"id": "e3", "type": "fixed",
				"trigger": {"kind": "interact", "hotspot_id": "X"},
			}],
		}, errs3)
		_check(not ok3, "E6 无 to_world 且无 effects 拒绝载入")
		return true
	return false


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	for line in _lines:
		print(line)
	print("=== EVENT EFFECTS RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null and gs.has_method("shutdown_audio"):
		gs.shutdown_audio()
	await create_timer(0.15).timeout
	quit(1 if _fail > 0 else 0)
	return true
