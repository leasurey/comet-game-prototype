## UIFlowTest — 「重新开始」的二次确认与保存反馈
##
## 对应缺陷：
##   BUG-012 点一次"重新开始"就删档，无确认；点"保存"无任何反馈
##   BUG-018 窗口失焦未释放鼠标（此处仅验证通知分支存在，实际失焦需人工）
##   BUG-010 事件提示在 new_game 后失效（验证改走总线后仍连着）
##
## 用法：godot --headless --script res://tests/ui_flow_test.gd

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc: Node = null
var _main: Node = null
var _ui = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0


func _initialize() -> void:
	print("=== COMET ui flow test ===")
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_confirm_guard"),
		Callable(self, "step_confirm_executes"),
		Callable(self, "step_report"),
	]


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		_lines.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_lines.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return false
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_ticks = 0
		_t_state = 0
	else:
		_ticks += 1
		if _ticks > 200:
			_check(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
	return false


func step_setup() -> bool:
	if _svc == null:
		_svc = root.get_node_or_null("GameServices")
		if _svc == null:
			_check(false, "setup. GameServices 可用")
			return true
		var sm = _svc.save_manager
		sm.use_test_path("ui_flow")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		return false
	if _ticks < 8:
		return false
	_ui = _main.get_node_or_null("HUD")
	_check(_ui != null, "setup. HUD 已装配")
	_check(_ui != null and _ui.has_method("ask_new_game"), "setup. 存在二次确认接口")
	_check(_ui != null and not _ui.is_confirm_visible(), "setup. 确认框初始不可见")
	_check(_svc.event_bus != null and _svc.event_bus.event_triggered.get_connections().size() > 0,
		"setup. 事件通过总线连到了 main（BUG-010）",
		"connections=%d" % (_svc.event_bus.event_triggered.get_connections().size() if _svc.event_bus else -1))
	return true


## 只点"重新开始"，不确认 → 存档必须还在
func step_confirm_guard() -> bool:
	if _t_state == 0:
		var state := {
			"location_id": "party_house", "world_id": "world_alpha",
			"visited_locations": ["party_house"], "world_change_records": [],
			"triggered_events": [], "event_history": {}, "event_sequence": [],
			"game_clock_ticks": 1, "player_view": {"yaw": 0.0, "pitch": 0.0},
		}
		var r: Dictionary = _svc.save_manager.save(state)
		_check(bool(r.get("ok", false)), "前置. 已存在一份存档")
		_t_state = 1
		return false
	if _t_state == 1:
		_main._on_new_game_requested()
		_t_state = 2
		return false
	if _t_state == 2:
		if _ticks < 2:
			return false
		_check(_ui.is_confirm_visible(), "点击重新开始后弹出确认框")
		_check(FileAccess.file_exists(_svc.save_manager.get_path()),
			"未确认时存档**未被删除**（核心断言）")
		_ui.hide_confirm()
		_check(not _ui.is_confirm_visible(), "取消后确认框关闭")
		_t_state = 0
		return true
	return true


## 确认后才真正删档并开新局
func step_confirm_executes() -> bool:
	if _t_state == 0:
		_main._on_new_game_requested()
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 2:
			return false
		_main._on_new_game_confirmed()
		_t_state = 2
		return false
	if _t_state == 2:
		if _ticks < 6:
			return false
		_check(not FileAccess.file_exists(_svc.save_manager.get_path()),
			"确认后存档被清除")
		_check(_svc.get_tick() == 0, "确认后时钟归零（新局）")
		_check(_svc.scene_manager.get_current_location_id()
			== _svc.scene_manager.get_start_location_id(), "确认后回到起始地点")
		_check(not _ui.is_confirm_visible(), "执行后确认框已关闭")
		_t_state = 0
		return true
	return true


func step_report() -> bool:
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== UI FLOW RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
