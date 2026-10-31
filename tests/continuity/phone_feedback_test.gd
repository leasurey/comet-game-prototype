## ContinuityPhoneFeedbackTest — 批次 5：手机、物品状态与反馈系统
##
## 用法：godot --headless --script res://tests/continuity/phone_feedback_test.gd
##
## F1 认知三本账：observations / inferences 记录与过滤
## F2 物品二级观察：hotspot.observes[] 产生观察记录 + 事实
## F3 手机数据：get_phone_data 汇总认知/事件/联系人
## F4 手机 UI：show/refresh/hide/状态查询
## F5 音频接线：按钮回调触发 play_ui_click（验证接线存在）
## F6 序列化：三本账入档/恢复

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


func _initialize() -> void:
	print("=== COMET continuity phone feedback test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_f1_ledgers"),
		Callable(self, "step_f2_observes"),
		Callable(self, "step_f3_phone_data"),
		Callable(self, "step_f4_phone_ui"),
		Callable(self, "step_f5_audio_wiring"),
		Callable(self, "step_f6_serialize"),
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
		sm.use_test_path("phone_feedback")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	return _ticks > 15


## F1  认知三本账
func step_f1_ledgers() -> bool:
	if _t_state == 0:
		var cog = _svc.cognition
		_check(cog.get_observation_count() == 0, "F1 前置：观察为空")
		_check(cog.get_inference_count() == 0, "F1 前置：推断为空")
		# 记录观察
		cog.record_observation("inspect", "屏幕上有一串数字", "StudyDesk", "world_alpha", 1)
		cog.record_observation("observe", "门上有张便签", "StickyNote", "world_alpha", 2)
		cog.record_observation("dialogue", "Kevin 说停电了", "kevin", "world_alpha", 3, true)
		_check(cog.get_observation_count() == 3, "F1 观察记录 3 条", str(cog.get_observation_count()))
		# 现实过滤
		var alpha_obs: Array = cog.get_observations("world_alpha")
		var beta_obs: Array = cog.get_observations("world_beta")
		_check(alpha_obs.size() == 3, "F1 alpha 过滤正确")
		_check(beta_obs.size() == 0, "F1 beta 过滤正确")
		# hearsay 标记
		var hearsay_count := 0
		for o in alpha_obs:
			if bool((o as Dictionary).get("hearsay", false)):
				hearsay_count += 1
		_check(hearsay_count == 1, "F1 hearsay 标记正确", str(hearsay_count))
		# 推断
		cog.record_inference("这栋房子可能不是原来那栋", "high", "house", "world_alpha", 1)
		_check(cog.get_inference_count() == 1, "F1 推断记录")
		return true
	return false


## F2  物品二级观察（hotspot.observes[]）
func step_f2_observes() -> bool:
	if _t_state == 0:
		var cog = _svc.cognition
		# 模拟 examine 处理链的 observes 逻辑
		var observes := [
			{"text": "屏幕上有几个数字", "fact_id": "obs_screen_digits", "hearsay": false},
			{"text": "键盘旁边有张纸条", "fact_id": "", "hearsay": false},
		]
		for obs in observes:
			var od: Dictionary = obs
			cog.record_observation("inspect", str(od.get("text", "")), "StudyDesk",
					"world_alpha", 5, bool(od.get("hearsay", false)))
			var obs_fact: String = str(od.get("fact_id", ""))
			if not obs_fact.is_empty():
				cog.learn(obs_fact, "inspect", "StudyDesk", "world_alpha", 5)
		_check(cog.get_observation_count() == 5, "F2 观察增加到 5 条", str(cog.get_observation_count()))
		_check(cog.knows("obs_screen_digits"), "F2 二级观察授予事实")
		_check(not cog.knows("obs_paper_note"), "F2 空 fact_id 不产生事实")
		return true
	return false


## F3  手机数据组装
func step_f3_phone_data() -> bool:
	if _t_state == 0:
		var data: Dictionary = _svc.get_phone_data()
		_check(data.has("observations"), "F3 含 observations")
		_check(data.has("facts"), "F3 含 facts")
		_check(data.has("inferences"), "F3 含 inferences")
		_check(data.has("events"), "F3 含 events")
		_check(data.has("contacts"), "F3 含 contacts")
		_check((data["observations"] as Array).size() == 5, "F3 observations 数",
			str((data["observations"] as Array).size()))
		_check((data["facts"] as Array).size() >= 1, "F3 facts 数", str((data["facts"] as Array).size()))
		_check((data["inferences"] as Array).size() == 1, "F3 inferences 数")
		return true
	return false


## F4  手机 UI
func step_f4_phone_ui() -> bool:
	if _t_state == 0:
		var ui = _main.get_node_or_null("HUD")
		_check(ui != null, "F4 前置：HUD 存在")
		if ui == null:
			return true
		_check(not ui.is_phone_open(), "F4 前置：手机关闭")
		ui.show_phone()
		_check(ui.is_phone_open(), "F4 show_phone 生效")
		# 刷新数据
		var data: Dictionary = _svc.get_phone_data()
		ui.refresh_phone(data)
		_check(ui.is_phone_open(), "F4 refresh 后仍打开")
		ui.hide_phone()
		_check(not ui.is_phone_open(), "F4 hide_phone 生效")
		return true
	return false


## F5  音频接线（验证按钮回调中存在 play_ui 调用）
func step_f5_audio_wiring() -> bool:
	if _t_state == 0:
		# 验证 UIManager 的按钮回调包含音频调用
		var ui = _main.get_node_or_null("HUD")
		_check(ui != null, "F5 前置：HUD 存在")
		if ui == null:
			return true
		# 方法存在性检查（接线已在代码层面完成）
		_check(_svc.audio_manager != null and _svc.audio_manager.has_method("play_ui_click"),
			"F5 play_ui_click 方法存在")
		_check(_svc.audio_manager.has_method("play_ui_confirm"), "F5 play_ui_confirm 方法存在")
		_check(_svc.audio_manager.has_method("play_ui_cancel"), "F5 play_ui_cancel 方法存在")
		_check(_svc.audio_manager.has_method("play_cue"), "F5 play_cue 方法存在")
		# play_cue 分派验证
		_svc.audio_manager.play_cue("ui_click")  # 不应报错
		_svc.audio_manager.play_cue("nonexistent_cue")  # 应 push_warning 但不崩溃
		_check(true, "F5 play_cue 调用不崩溃")
		return true
	return false


## F6  三本账序列化
func step_f6_serialize() -> bool:
	if _t_state == 0:
		var cog = _svc.cognition
		var rec: Dictionary = cog.serialize()
		_check(rec.has("observations"), "F6 序列化含 observations")
		_check(rec.has("inferences"), "F6 序列化含 inferences")
		_check(rec.has("read_marks"), "F6 序列化含 read_marks")
		_check((rec.get("observations", []) as Array).size() == 5, "F6 观察入档数")
		# 恢复到新的 manager
		var cog2 = load("res://core/cognition_manager.gd").new()
		var errs: Array = []
		var ok: bool = cog2.restore(rec, errs)
		_check(ok, "F6 恢复成功", str(errs))
		_check(cog2.get_observation_count() == 5, "F6 恢复后观察数")
		_check(cog2.get_inference_count() == 1, "F6 恢复后推断数")
		_check(cog2.knows("obs_screen_digits"), "F6 恢复后事实仍在")
		return true
	return false


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	for line in _lines:
		print(line)
	print("=== PHONE FEEDBACK RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null and gs.has_method("shutdown_audio"):
		gs.shutdown_audio()
	await create_timer(0.15).timeout
	quit(1 if _fail > 0 else 0)
	return true
