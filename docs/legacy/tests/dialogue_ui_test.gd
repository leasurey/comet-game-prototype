## DialogueUiTest — 对话正式 UI（P7）
##
## 用法：godot --headless --script res://tests/dialogue_ui_test.gd
##
## U1  对话面板 API：开/关/状态查询
## U2  话题列表渲染与点击 → topic_chosen(index)
## U3  台词 + 回复分支渲染与点击 → reply_chosen(index) / goto 推进
## U4  对话授予认知（走 UI 链路，hint 显示「你了解到」）
## U5  goto=null 的回复结束对话
## U6  话题入口判定：被 goto 引用的节点不是话题；认知闸门控制话题可见性
## U7  「结束对话」按钮与关闭信号

extends SceneTree

const KEVIN_GREET_TEXT := "你醒了？停电把保险烧了，别担心。桌上还有吃的。"

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _main: Node = null
var _ui = null
var _npc: NPC = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _close_events: Array = []


func _initialize() -> void:
	print("=== COMET dialogue ui test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_u1_panel_api"),
		Callable(self, "step_u2_topics"),
		Callable(self, "step_u3_branch"),
		Callable(self, "step_u4_grant"),
		Callable(self, "step_u5_end"),
		Callable(self, "step_u6_entries"),
		Callable(self, "step_u7_close"),
		Callable(self, "step_report"),
	]


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
		if _ticks > 300:
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


func _btn(path: String) -> Button:
	return _ui.get_node_or_null("Root/DialogueRoot/Panel/VBox/" + path) as Button


func _dlg_label(name: String) -> Label:
	return _ui.get_node_or_null("Root/DialogueRoot/Panel/VBox/" + name) as Label


func _option_count() -> int:
	var list: Node = _ui.get_node_or_null("Root/DialogueRoot/Panel/VBox/OptionList")
	if list == null:
		return -1
	return list.get_child_count()


func _press_option(i: int) -> void:
	var b := _btn("OptionList/OptionButton%d" % i)
	if b != null:
		b.pressed.emit()


# ---------------------------------------------------------------- 步骤

func step_setup() -> bool:
	if _t_state == 0:
		# 存档隔离：不许继承别的测试/真实存档里的认知，否则话题数断言会被污染
		var sm = _svc.save_manager
		sm.use_test_path("dialogue_ui")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _ticks < 10:
		return false
	_ui = _main.get_node_or_null("HUD")
	_check(_ui != null, "setup. HUD 已装配")
	_check(_ui != null and _ui.has_method("show_dialogue_topics"),
		"setup. 对话面板接口存在")
	_npc = NPC.new()
	_npc.setup("kevin", "Kevin", "kitchen")
	root.add_child(_npc)
	if _ui != null and _ui.has_signal("dialogue_close_requested"):
		_ui.dialogue_close_requested.connect(func() -> void: _close_events.append(1))
	return true


func step_u1_panel_api() -> bool:
	_check(not _ui.is_dialogue_open(), "U1 初始对话面板关闭")
	_ui.show_dialogue_topics("Kevin", ["话题甲", "话题乙"])
	_check(_ui.is_dialogue_open(), "U1 show_dialogue_topics 后面板打开")
	_check(_option_count() == 2, "U1 话题按钮数量正确", str(_option_count()))
	_ui.hide_dialogue()
	_check(not _ui.is_dialogue_open(), "U1 hide_dialogue 后面板关闭")
	return true


func step_u2_topics() -> bool:
	# 走 main 的正式入口：E 交互背后调用的 _start_dialogue
	_main._start_dialogue(_npc)
	_check(_ui.is_dialogue_open(), "U2 _start_dialogue 打开对话面板")
	var speaker := _dlg_label("SpeakerLabel")
	_check(speaker != null and speaker.text == "Kevin",
		"U2 说话人显示正确", str(speaker.text) if speaker != null else "-")
	# kevin 初始（未查过便签）只有 kevin_greet 一个话题入口
	_check(_option_count() == 1, "U2 话题按钮数量 = 认知闸门过滤后的入口数",
		"%d 个" % _option_count())
	var topic_btn := _btn("OptionList/OptionButton0")
	_check(topic_btn != null and topic_btn.text == "打个招呼",
		"U2 话题按钮文案取 topic 字段", str(topic_btn.text) if topic_btn != null else "-")
	return true


func step_u3_branch() -> bool:
	_press_option(0)
	var text := _dlg_label("TextLabel")
	_check(text != null and text.text == KEVIN_GREET_TEXT,
		"U3 话题点击后显示 NPC 台词", str(text.text) if text != null else "-")
	_check(_option_count() == 2, "U3 回复分支按钮数量正确", "%d 个" % _option_count())
	# 第一条回复 goto kevin_far_house —— 点击应推进到那个节点
	_press_option(0)
	var text2 := _dlg_label("TextLabel")
	_check(text2 != null and text2.text.find("发电机") >= 0,
		"U3 回复 goto 推进到分支节点", str(text2.text) if text2 != null else "-")
	return true


func step_u4_grant() -> bool:
	# step_u3 的推进已让 kevin_far_house 授予 fact_far_house
	_check(_svc.cognition.knows("fact_far_house"),
		"U4 对话经 UI 链路授予认知")
	var hint := _dlg_label("HintLabel")
	_check(hint != null and hint.visible and hint.text.find("你了解到") >= 0,
		"U4 面板副行显示「你了解到」", str(hint.text) if hint != null else "-")
	return true


func step_u5_end() -> bool:
	# kevin_far_house 的第二条回复「好。」goto=null → 结束对话
	_check(_option_count() == 2, "U5 前置：分支节点有 2 条回复", "%d 个" % _option_count())
	_press_option(1)
	_check(not _ui.is_dialogue_open(), "U5 goto=null 的回复结束对话")
	_check(_npc.get_state() != NPC.STATE_TALKING, "U5 结束后 NPC 退出交谈状态",
		_npc.get_state())
	return true


func step_u6_entries() -> bool:
	var dlg = _svc.dialogue_manager
	var entries: Array = dlg.get_entry_nodes_for("kevin")
	var ids: Array = []
	for n in entries:
		ids.append(str((n as Dictionary).get("id", "")))
	_check(ids.has("kevin_greet"), "U6 kevin_greet 是话题入口", str(ids))
	_check(not ids.has("kevin_far_house"),
		"U6 被 goto 引用的节点不是话题入口", str(ids))
	_check(not ids.has("kevin_two_houses"),
		"U6 深层分支节点不是话题入口", str(ids))
	# 认知闸门：学到便签后 kevin_sticky 解锁为话题
	_svc.cognition.learn("fact_sticky_note", "inspect", "StickyNote", "world_alpha", 0)
	var after: Array = dlg.get_entry_nodes_for("kevin")
	var after_ids: Array = []
	for n in after:
		after_ids.append(str((n as Dictionary).get("id", "")))
	_check(after_ids.has("kevin_sticky"),
		"U6 认知闸门解锁话题", str(after_ids))
	return true


func step_u7_close() -> bool:
	_ui.show_dialogue_line("Kevin", "测试台词", ["回复甲", "回复乙"])
	_check(_ui.is_dialogue_open(), "U7 前置：面板已开")
	var b := _btn("DialogueClose")
	_check(b != null, "U7 存在「结束对话」按钮")
	if b != null:
		b.pressed.emit()
	_check(_close_events.size() > 0, "U7 关闭按钮发出 dialogue_close_requested")
	_check(not _ui.is_dialogue_open(), "U7 关闭后面板隐藏")
	return true


func step_report() -> bool:
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== DIALOGUE UI RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
