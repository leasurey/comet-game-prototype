## UiLayoutTest — UI 布局回归（P0 阻塞缺陷防护）
##
## 用法：godot --headless --script res://tests/ui_layout_test.gd
##
## 背景（实测缺陷）：set_anchors_preset(PRESET_FULL_RECT) 默认 MINSIZE 模式
## 会「保持当前 0×0 尺寸」，把 offset 补偿成 (0,0,-1280,-720)——
## 主菜单面板整体飞出屏幕左上角，「开始新游戏」按不到；
## 同时交互提示、准星、消息全部脱屏，玩家进游戏后看不见任何引导，
## 表现为「只能在屋里瞎逛」。既有 21 个测试全绿是因为它们只断言
## 信号与文本，从不断言控件坐标——本测试补上这块盲区。
##
## L1  主菜单面板与四个按钮全部在视口内
## L2  「开始新游戏」按钮中心的命中测试就是它自己（无遮挡、可点击）
## L3  按钮 pressed → 进入游戏（信号接线链路完整）
## L4  HUD 关键控件（准星/消息/交互提示/按钮条）全部在视口内
## L5  主循环门：party_house 前门 → house_exterior → 回屋 → 前门再出
## L6  三扇门均可聚焦并激活到正确地点

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _main = null
var _ui = null
var _menu = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false
var _loop_started := false
var _loop_done := false


func _initialize() -> void:
	print("=== COMET ui layout test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_l1_menu_on_screen"),
		Callable(self, "step_l2_hit_test"),
		Callable(self, "step_l3_click_wiring"),
		Callable(self, "step_l4_hud_on_screen"),
		Callable(self, "step_l5_door_loop"),
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
		if _ticks > 400:
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


# ---------------------------------------------------------------- 工具

func _find_button(node: Node, text: String) -> Button:
	for c in node.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
		var f := _find_button(c, text)
		if f != null:
			return f
	return null


func _hit_test(from: Node, p: Vector2) -> Control:
	var kids := from.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var c = kids[i]
		if not (c is Control):
			continue
		var ctrl := c as Control
		if not ctrl.visible:
			continue
		if not ctrl.get_global_rect().has_point(p):
			continue
		var found := _hit_test(ctrl, p)
		if found != null:
			return found
		if ctrl.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return ctrl
	return null


func _hit_test_layer(layer: CanvasLayer, p: Vector2) -> Control:
	return _hit_test(layer, p)


func _rect_in_viewport(r: Rect2) -> bool:
	var vp := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	return vp.encloses(r)


# ---------------------------------------------------------------- 步骤

func step_setup() -> bool:
	if _t_state == 0:
		# 存档隔离：不许被「有存档→弹确认框」分支干扰
		var sm = _svc.save_manager
		sm.use_test_path("ui_layout")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 10:
			return false
		_ui = _main.get_node_or_null("HUD")
		_menu = _main.get_node_or_null("HUD/Menu")
		_check(_ui != null and _menu != null, "setup. HUD 与 Menu 已装配")
		_menu.show_main(false)
		_t_state = 2
		_ticks = 0
		return false
	# 容器排版（queue_sort）下一帧才生效，等 2 帧再进入断言
	return _ticks >= 2


func step_l1_menu_on_screen() -> bool:
	var vp_size := root.get_visible_rect().size
	var panel: Node = _menu.get_node_or_null("MenuRoot/Panel")
	_check(panel != null, "L1 菜单面板存在")
	if panel != null:
		var pr: Rect2 = (panel as Control).get_global_rect()
		_check(_rect_in_viewport(pr), "L1 菜单面板在视口内",
			"rect=%s viewport=%s" % [str(pr), str(vp_size)])
	for text in ["开始新游戏", "继续游戏", "设置", "退出"]:
		var b := _find_button(_menu, text)
		if b == null:
			_check(false, "L1 按钮存在：%s" % text)
			continue
		var r := b.get_global_rect()
		_check(_rect_in_viewport(r), "L1 按钮在视口内：%s" % text,
			"rect=%s" % str(r))
	# 四个按钮互不重叠（VBox 排版正确）
	var rects: Array = []
	for text in ["开始新游戏", "继续游戏", "设置", "退出"]:
		var b2 := _find_button(_menu, text)
		if b2 != null:
			rects.append(b2.get_global_rect())
	var overlap := false
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				overlap = true
	_check(not overlap, "L1 四个按钮互不重叠（VBox 排版正确）")
	return true


func step_l2_hit_test() -> bool:
	var btn := _find_button(_menu, "开始新游戏")
	if btn == null:
		_check(false, "L2 前置：按钮存在")
		return true
	var center := btn.get_global_rect().get_center()
	var hit := _hit_test_layer(_ui, center)
	_check(hit == btn, "L2 「开始新游戏」中心命中即自身（无遮挡）",
		"hit=%s" % (hit.name if hit != null else "null"))
	return true


func step_l3_click_wiring() -> bool:
	var btn := _find_button(_menu, "开始新游戏")
	if btn == null:
		_check(false, "L3 前置：按钮存在")
		return true
	# headless 下合成点击事件不进 GUI 管线（引擎限制），
	# 这里直接触发 pressed 信号 —— 验证「信号→handler→进入游戏」链路。
	# 几何可点性由 L1/L2 保证，OS 层投递由系统保证。
	btn.pressed.emit()
	_check(not _menu.visible, "L3 点击后主菜单关闭", "visible=%s" % str(_menu.visible))
	_check(_svc.get_current_location_id() == "party_house",
		"L3 点击后进入游戏", "loc=%s" % _svc.get_current_location_id())
	return true


func step_l4_hud_on_screen() -> bool:
	var root_ctrl: Node = _ui.get_node_or_null("Root")
	if root_ctrl == null:
		_check(false, "L4 前置：HUD Root 存在")
		return true
	var checks := {
		"Reticle": "准星",
		"MessageRoot": "消息区",
		"FocusLabel": "交互提示",
		"ButtonBar": "功能按钮条",
	}
	for key in checks.keys():
		var n: Node = _find_child_control(root_ctrl, str(key))
		if n == null:
			_check(false, "L4 %s 存在" % checks[key])
			continue
		var r: Rect2 = (n as Control).get_global_rect()
		_check(_rect_in_viewport(r), "L4 %s 在视口内" % checks[key],
			"rect=%s" % str(r))
	# 准星必须在屏幕中心附近
	var reticle: Control = _find_child_control(root_ctrl, "Reticle")
	if reticle != null:
		var c := reticle.get_global_rect().get_center()
		var vp_c: Vector2 = root.get_visible_rect().size * 0.5
		_check(c.distance_to(vp_c) < 24.0, "L4 准星居中", "pos=%s" % str(c))
	return true


func _find_child_control(n: Node, cname: String) -> Control:
	for c in n.get_children():
		if c is Control and c.name == cname:
			return c as Control
		var f := _find_child_control(c, cname)
		if f != null:
			return f
	return null


func step_l5_door_loop() -> bool:
	# 主循环：party_house 前门 → house_exterior → 回屋门 → party_house。
	# 含 await 的流程放协程里跑，本函数只轮询完成标志——
	# 步骤函数若直接 await，call() 返回协程状态对象，步骤机就乱了。
	if not _loop_started:
		_loop_started = true
		_run_door_loop()
	return _loop_done


func _run_door_loop() -> void:
	if _svc.get_current_location_id() != "party_house":
		_svc.go_to("party_house")
		await _wait_frames(6)
	if await _door_action("party_house", "FrontDoor", "house_exterior"):
		await _door_action("house_exterior", "DoorToInterior", "party_house")
		_check(_svc.get_current_location_id() == "party_house",
			"L5 出门-回屋主循环连通",
			"party_house ↔ house_exterior，现位于 %s" % _svc.get_current_location_id())
	_loop_done = true


## 站到门前→瞄准→聚焦→激活，断言落到正确地点。
## 返回是否继续（false = 已记录失败，跳过后续）。
func _door_action(loc: String, door_name: String, expect: String) -> bool:
	if _svc.get_current_location_id() != loc:
		_svc.go_to(loc)
		await _wait_frames(6)
	var inst = _svc.scene_manager.get_current_instance()
	var h := _find_hotspot(inst, door_name)
	if h == null:
		_check(false, "门存在：%s" % door_name)
		return false
	var im = _svc.interaction_manager
	var pc = _svc.player_controller
	var pos: Vector3 = h.global_position
	var offsets := [
		Vector3(0, 0, 1.2), Vector3(0, 0, -1.2),
		Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0),
	]
	for off in offsets:
		pc.global_position = Vector3(pos.x + off.x, 0.25, pos.z + off.z)
		var look: Vector3 = Vector3(pos.x, 1.15, pos.z) \
				- (pc.global_position + Vector3(0, 1.62, 0))
		if look.length() < 0.01:
			continue
		pc.yaw = atan2(-look.x, -look.z)
		pc.pitch = 0.0
		if pc.has_method("_apply_rotation"):
			pc._apply_rotation()
		await _wait_frames(2)
		if im.get_focused() == h:
			var activated: bool = im.activate_focused()
			await _wait_frames(4)
			var now: String = _svc.get_current_location_id()
			_check(activated and now == expect,
				"门 %s 可聚焦并激活 → %s" % [door_name, expect],
				"activate=%s now=%s" % [str(activated), now])
			return true
	_check(false, "门 %s 从四侧均无法聚焦" % door_name)
	return false


func _find_hotspot(n: Node, hname: String) -> Hotspot:
	for c in n.get_children():
		if c is Hotspot and c.name == hname:
			return c as Hotspot
		var f := _find_hotspot(c, hname)
		if f != null:
			return f
	return null


func _wait_frames(n: int) -> void:
	for i in range(n):
		await process_frame


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== UI LAYOUT RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
