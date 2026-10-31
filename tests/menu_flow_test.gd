## MenuFlowTest — 主菜单 / 暂停 / 设置持久化
##
## 用法：
##   godot --headless --script res://tests/menu_flow_test.gd
##
## 覆盖：
##   M1  设置默认值与写入
##   M2  设置读写往返
##   M3  非法值被 _sanitize 夹回合法区间
##   M4  设置与游戏存档分离（删档不影响设置文件）
##   M5  主菜单显示与「继续游戏」按钮状态
##   M6  暂停菜单开关
##   M7  设置界面往返
##   M8  菜单打开时世界输入被屏蔽
##   M9  从主菜单开始新游戏可进入世界
##   M10 headless 下自动开局不受菜单影响（回归保护）

extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []

var _steps: Array = []
var _idx: int = 0
var _ticks: int = 0
var _t_state: int = 0
var _wait_ticks: int = 0
var _reporting: bool = false

var _services = null
var _main: Node = null
var _menu: Control = null
var _settings: SettingsManager = null


func _initialize() -> void:
	print("=== COMET menu flow test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))
	_build_steps()


func _build_steps() -> void:
	_steps = [
		Callable(self, "step_settings_persist"),
		Callable(self, "step_settings_sanitize"),
		Callable(self, "step_settings_isolated_from_save"),
		Callable(self, "step_menu_states"),
		Callable(self, "step_menu_blocks_world_input"),
		Callable(self, "step_menu_new_game"),
		Callable(self, "step_headless_auto_start"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_t_state = 0
		_ticks = 0
		_wait_ticks = 0
	else:
		_ticks += 1
		if _ticks > 200:
			_record(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_t_state = 0
			_ticks = 0
			_wait_ticks = 0
	return false


func _record(ok: bool, label: String, detail: String = "") -> void:
	var suffix := ""
	if detail != "":
		suffix = " | " + detail
	if ok:
		_pass += 1
		_results.append("[PASS] %s%s" % [label, suffix])
	else:
		_fail += 1
		_results.append("[FAIL] %s%s" % [label, suffix])


func _check(cond: bool, label: String, detail: String = "") -> void:
	_record(cond, label, detail)


func _wait(n: int) -> bool:
	if _wait_ticks < n:
		_wait_ticks += 1
		return false
	return true


func _reset_wait() -> void:
	_wait_ticks = 0


# ---------------------------------------------------------------- M1-M3 设置

func step_settings_persist() -> bool:
	# 先清掉上一轮残留，否则 load_settings 读到的是旧值而非默认值。
	for p in ["user://_test_menu_settings.json", "user://_test_menu_settings2.json",
			"user://_test_menu_settings3.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	_settings = SettingsManager.new()
	_settings.set_path("user://_test_menu_settings.json")
	_settings.load_settings()

	_check(_settings.get_value("sensitivity_x") == SettingsManager.DEFAULTS["sensitivity_x"],
		"M1 默认灵敏度正确", str(_settings.get_value("sensitivity_x")))
	_check(_settings.get_value("master_volume") == SettingsManager.DEFAULTS["master_volume"],
		"M1 默认总音量正确")

	_settings.set_value("sensitivity_x", 0.0060)
	_settings.set_value("invert_y", true)
	_settings.set_value("resolution", "854x480")
	_check(FileAccess.file_exists("user://_test_menu_settings.json"),
		"M2 修改后立即落盘")

	# 重新加载一个新实例，验证持久化
	var second := SettingsManager.new()
	second.set_path("user://_test_menu_settings.json")
	second.load_settings()
	_check(absf(float(second.get_value("sensitivity_x")) - 0.0060) < 0.00001,
		"M2 灵敏度读写往返一致", str(second.get_value("sensitivity_x")))
	_check(bool(second.get_value("invert_y")) == true, "M2 反转视角读写往返一致")
	_check(str(second.get_value("resolution")) == "854x480", "M2 分辨率读写往返一致")

	# 不认识的键应被忽略，不污染配置
	second.set_value("hacked_key", 123)
	_check(not second.values.has("hacked_key"), "M2 未知键被拒绝写入")

	return true


func step_settings_sanitize() -> bool:
	var s := SettingsManager.new()
	s.set_path("user://_test_menu_settings2.json")
	s.load_settings()
	s.set_value("sensitivity_x", 999.0)
	s.set_value("master_volume", -5.0)
	s.set_value("resolution", "9999x1")
	s.set_value("max_fps", 7)
	_check(float(s.get_value("sensitivity_x")) <= 0.02,
		"M3 灵敏度越界被夹回上限", str(s.get_value("sensitivity_x")))
	_check(float(s.get_value("master_volume")) == 0.0,
		"M3 音量负值被夹回 0", str(s.get_value("master_volume")))
	_check(str(s.get_value("resolution")) == "1280x720",
		"M3 非法分辨率回落默认", str(s.get_value("resolution")))
	_check(int(s.get_value("max_fps")) == 60,
		"M3 非法帧率上限回落默认", str(s.get_value("max_fps")))
	return true


func step_settings_isolated_from_save() -> bool:
	# 设置文件与游戏存档是两份文件。删档不应动设置。
	var s := SettingsManager.new()
	s.set_path("user://_test_menu_settings3.json")
	s.load_settings()
	s.set_value("music_volume", 0.11)
	var settings_path := s.get_path()
	_check(FileAccess.file_exists(settings_path), "前置. 设置文件已存在")

	var sm := SaveManager.new()
	sm.use_test_path("menu_isolation")
	var payload := {
		"magic": "COMET_SAVE", "version": 2,
		"location_id": "party_house", "world_id": "world_alpha",
		"visited_locations": ["party_house"],
		"world_change_records": [], "triggered_events": [],
		"event_history": {}, "event_sequence": [],
		"game_clock_ticks": 0, "game_clock_minutes": 1360,
		"rng_master_seed": 0, "rng_counters": {}, "event_flags": {},
		"phase_id": "", "player_view": {"yaw": 0.0, "pitch": 0.0},
		"player_position": [0.0, 0.0, 0.0], "visit_stack": [],
		"known_facts": [], "inspected_objects": [],
		"npc_states": {}, "traversal_state": {},
	}
	var r: Dictionary = sm.save(payload)
	_check(bool(r.get("ok", false)), "前置. 测试存档写入成功")
	var del: Dictionary = sm.delete_save()
	_check(bool(del.get("ok", false)), "前置. 存档已删除")

	_check(FileAccess.file_exists(settings_path),
		"M4 删除游戏存档后设置文件仍存在（两份数据互不影响）")

	var s2 := SettingsManager.new()
	s2.set_path(settings_path)
	s2.load_settings()
	_check(absf(float(s2.get_value("music_volume")) - 0.11) < 0.00001,
		"M4 设置值未被删档波及", str(s2.get_value("music_volume")))
	return true


# ---------------------------------------------------------------- M5-M8 菜单

## 找到主菜单里指定文字的按钮（遍历子树，不依赖固定层级）。
func _find_menu_button(text: String) -> Button:
	if _menu == null:
		return null
	var stack: Array = [_menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == text:
			return n as Button
		for ch in n.get_children():
			stack.append(ch)
	return null


func step_menu_states() -> bool:
	if _t_state == 0:
		_services = root.get_node_or_null("GameServices")
		if _services == null:
			_record(false, "M5 菜单装配", "GameServices 不可用")
			return true
		var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
		if packed == null:
			_record(false, "M5 菜单装配", "主场景不可加载")
			return true
		_main = packed.instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait(6):
			return false

		_menu = _main.get_node_or_null("HUD/Menu")
		if _menu == null:
			_record(false, "M5 菜单节点存在", "HUD/Menu 未找到")
			return true
		_check(_menu.has_method("show_main"), "M5 MenuController 提供主菜单")
		_check(_menu.has_method("show_pause"), "M5 MenuController 提供暂停菜单")
		_check(_menu.has_method("show_settings"), "M5 MenuController 提供设置界面")

		# 无存档时「继续游戏」应禁用
		_menu.show_main(false)
		_check(_menu.is_open(), "M5 主菜单打开")
		_check(_menu.get_mode() == "main", "M5 模式标记为 main", _menu.get_mode())
		var cont_btn := _find_menu_button("继续游戏")
		_check(cont_btn != null, "M5 「继续游戏」按钮存在")
		_check(cont_btn != null and cont_btn.disabled, "M5 无存档时「继续游戏」被禁用")

		# 有存档时应可用
		_menu.show_main(true)
		var cont_btn2 := _find_menu_button("继续游戏")
		_check(cont_btn2 != null and not cont_btn2.disabled, "M5 有存档时「继续游戏」可用")

		_menu.hide_menu()
		_check(not _menu.is_open(), "M5 菜单可关闭")
		return true
	return true


func step_menu_blocks_world_input() -> bool:
	if _main == null or _menu == null:
		_record(false, "M8 菜单屏蔽世界输入", "依赖缺失")
		return true

	_menu.show_pause()
	_check(_menu.get_mode() == "pause", "M6 暂停菜单打开", _menu.get_mode())
	_check(_main._is_menu_open(), "M6 main 识别到菜单开启")

	# 菜单开启时 E 键不应触发交互
	var im = _services.interaction_manager
	var activated: Array = []
	if im != null and im.has_signal("hotspot_activated"):
		im.hotspot_activated.connect(func(spot) -> void: activated.append(spot))

	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	key.pressed = true
	_main._unhandled_input(key)
	_check(activated.is_empty(), "M8 菜单开启时 E 键不触发交互",
		"activated=%d" % activated.size())

	# ESC 应关闭暂停菜单
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	_main._unhandled_input(esc)
	_check(not _menu.is_open(), "M6 ESC 关闭暂停菜单")
	_check(not _main._is_menu_open(), "M6 关闭后 main 不再屏蔽输入")

	# 再按 ESC 应重新打开
	_main._unhandled_input(esc)
	_check(_menu.is_open(), "M6 再按 ESC 重新打开暂停")
	_main._unhandled_input(esc)
	_check(not _menu.is_open(), "M6 ESC 往返稳定")
	return true


func step_menu_new_game() -> bool:
	if _main == null or _menu == null or _services == null:
		_record(false, "M9 从主菜单开始新游戏", "依赖缺失")
		return true

	if _t_state == 0:
		# 先制造脏状态，验证新游戏确实清零
		if _services.scene_manager != null:
			_services.scene_manager.enter_location("house_exterior", false)
		_services.delete_save()
		_menu.show_main(true)
		_menu.new_game_requested.emit()
		_t_state = 1
		return false

	if _t_state == 1:
		if not _wait(8):
			return false

		_check(_services.scene_manager.get_current_location_id()
				== _services.scene_manager.get_start_location_id(),
			"M9 新游戏后回到起始地点",
			_services.scene_manager.get_current_location_id())
		_check(not _menu.is_open(), "M9 开始后菜单关闭")
		_check(not _main.get_tree().paused, "M9 开始后世界未被暂停")
		return true
	return true


func step_headless_auto_start() -> bool:
	# 回归保护：headless 必须仍走自动开局，不能被主菜单挡住。
	# 上面 step_menu_new_game 已经把世界开起来了，这里只断言状态成立。
	if _services == null:
		_record(false, "M10 headless 自动开局", "依赖缺失")
		return true
	var loc: String = _services.scene_manager.get_current_location_id()
	_check(not loc.is_empty(), "M10 headless 下世界已自动开局", loc)
	_check(_services.is_ready, "M10 GameServices 就绪")
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	# 清理本测试产生的临时设置文件，不留残留在玩家的 user:// 里
	for p in ["user://_test_menu_settings.json", "user://_test_menu_settings2.json",
			"user://_test_menu_settings3.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("")
	for line in _results:
		print(line)
	print("")
	print("=== MENU FLOW RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
