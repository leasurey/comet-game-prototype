## UIManager — 界面与提示
##
## 职责边界：
##   只负责把游戏状态显示出来，并把界面操作转成信号发出去。
##   不读世界数据、不做射线检测、不直接调用 SceneManager。
##
## 为什么界面用代码构建而不是 .tscn：
##   在 .tscn 里手写 Control 的 anchor / offset / 容器约束，极易产出
##   「加载不报错但控件位置全错」的结果。第一阶段原型把界面构建集中在这里，
##   布局逻辑显式可读；后续若要改回 .tscn，只需删掉 _build_ui()
##   并在场景中提供同名节点即可，对外 API 与信号保持不变。
##
## 扩展性约定：
##   后续若要加入虚拟桌面、聊天软件、浏览器、文件管理器等浮层，
##   一律通过 register_overlay() 挂到 OverlayLayer 下，
##   不得塞进 HUD 分支，以免与场景逻辑耦合。

class_name UIManager
extends CanvasLayer

signal back_requested
signal save_requested
signal quit_requested
signal new_game_requested
## 「重新开始」的二次确认结果。请求与确认分开两个信号，
## 是为了让 UIManager 不承担"删档"这种破坏性决定，只负责问一句。
signal new_game_confirmed

## 对话面板（P7 正式对话 UI）。
## 面板只负责呈现与转发点击：说什么、说什么之后发生什么，由 main/对话系统决定。
signal dialogue_topic_chosen(index: int)
signal dialogue_reply_chosen(index: int)
signal dialogue_close_requested

const COLOR_TEXT := Color(0.86, 0.87, 0.88, 1.0)
const COLOR_MUTED := Color(0.55, 0.57, 0.59, 1.0)
const COLOR_ACCENT := Color(0.80, 0.65, 0.38, 1.0)
const COLOR_PANEL := Color(0.035, 0.037, 0.045, 0.74)

var _clock: Label = null
var _location_label: Label = null
var _focus_label: Label = null
var _message_label: Label = null
var _message_bg: ColorRect = null
var _reticle: Control = null
var _back_button: Button = null
var _overlay_root: Control = null
var _confirm_root: Control = null
var _confirm_label: Label = null
var _confirm_callback: Callable = Callable()
var _root: Control = null

# 对话面板
var _dialogue_root: Control = null
var _dlg_speaker: Label = null
var _dlg_text: Label = null
var _dlg_hint: Label = null
var _dlg_list: VBoxContainer = null


func _ready() -> void:
	layer = 1
	_build_ui()
	set_focus_text("")
	set_message("")


# ---------------------------------------------------------------- 界面构建

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_build_top_left()
	_build_reticle()
	_build_focus()
	_build_message()
	_build_button_bar()
	_build_confirm()
	_build_dialogue()

	_overlay_root = Control.new()
	_overlay_root.name = "OverlayLayer"
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay_root)


func _build_top_left() -> void:
	var box := VBoxContainer.new()
	box.name = "TopLeft"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.offset_left = 22.0
	box.offset_top = 18.0
	box.offset_right = 320.0
	box.offset_bottom = 92.0
	box.add_theme_constant_override("separation", 2)

	_clock = Label.new()
	_clock.name = "ClockLabel"
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock.text = "--:--"
	_clock.add_theme_font_size_override("font_size", 15)
	_clock.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(_clock)

	_location_label = Label.new()
	_location_label.name = "LocationLabel"
	_location_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_location_label.text = ""
	_location_label.add_theme_font_size_override("font_size", 19)
	_location_label.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(_location_label)


func _build_reticle() -> void:
	var holder := Control.new()
	holder.name = "Reticle"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	holder.set_anchors_preset(Control.PRESET_CENTER)
	holder.offset_left = -3.0
	holder.offset_top = -3.0
	holder.offset_right = 3.0
	holder.offset_bottom = 3.0

	var dot := ColorRect.new()
	dot.name = "Dot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.color = Color(0.92, 0.92, 0.90, 0.42)
	dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(dot)
	_reticle = holder


func _build_focus() -> void:
	_focus_label = Label.new()
	_focus_label.name = "FocusLabel"
	_focus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_focus_label)
	_focus_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_focus_label.offset_left = -300.0
	_focus_label.offset_right = 300.0
	_focus_label.offset_top = -186.0
	_focus_label.offset_bottom = -154.0
	_focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_focus_label.add_theme_font_size_override("font_size", 17)
	_focus_label.add_theme_color_override("font_color", COLOR_ACCENT)


func _build_message() -> void:
	var holder := Control.new()
	holder.name = "MessageRoot"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.offset_left = -320.0
	holder.offset_right = 320.0
	holder.offset_top = -136.0
	holder.offset_bottom = -66.0

	_message_bg = ColorRect.new()
	_message_bg.name = "MessageBg"
	_message_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_bg.color = COLOR_PANEL
	_message_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_message_bg)

	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message_label.offset_left = 14.0
	_message_label.offset_top = 8.0
	_message_label.offset_right = -14.0
	_message_label.offset_bottom = -8.0
	_message_label.add_theme_font_size_override("font_size", 16)
	_message_label.add_theme_color_override("font_color", COLOR_TEXT)
	holder.add_child(_message_label)


func _build_button_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "ButtonBar"
	_root.add_child(bar)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.offset_left = -372.0
	bar.offset_top = -56.0
	bar.offset_right = -20.0
	bar.offset_bottom = -20.0
	bar.add_theme_constant_override("separation", 10)

	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "返回"
	_back_button.custom_minimum_size = Vector2(80, 30)
	_back_button.add_theme_font_size_override("font_size", 14)
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	bar.add_child(_back_button)

	var save_button := Button.new()
	save_button.name = "SaveButton"
	save_button.text = "保存"
	save_button.custom_minimum_size = Vector2(80, 30)
	save_button.add_theme_font_size_override("font_size", 14)
	save_button.pressed.connect(func() -> void: save_requested.emit())
	bar.add_child(save_button)

	var restart_button := Button.new()
	restart_button.name = "NewGameButton"
	restart_button.text = "重新开始"
	restart_button.custom_minimum_size = Vector2(84, 30)
	restart_button.add_theme_font_size_override("font_size", 14)
	restart_button.pressed.connect(func() -> void: new_game_requested.emit())
	bar.add_child(restart_button)

	var quit_button := Button.new()
	quit_button.name = "QuitButton"
	quit_button.text = "退出"
	quit_button.custom_minimum_size = Vector2(72, 30)
	quit_button.add_theme_font_size_override("font_size", 14)
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	bar.add_child(quit_button)


## 二次确认面板。
##
## 为什么必须有：原来的「重新开始」按钮一点就直接 delete_save + new_game，
## 误触一次，几十小时的进度就没了，而且没有任何提示。
## 这里只负责"问一句"，真正的删档仍由 main 执行。
func _build_confirm() -> void:
	var root := Control.new()
	root.name = "ConfirmRoot"
	# STOP：面板显示期间吞掉点击，避免同一次点击既确认又落到场景交互上
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	_root.add_child(root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220.0
	panel.offset_top = -80.0
	panel.offset_right = 220.0
	panel.offset_bottom = 80.0
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var label := Label.new()
	label.name = "ConfirmLabel"
	label.text = "重新开始会清除当前存档，确定吗？"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(label)
	_confirm_label = label

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)

	var yes := Button.new()
	yes.name = "ConfirmYes"
	yes.text = "确定重来"
	yes.custom_minimum_size = Vector2(140, 34)
	yes.pressed.connect(func() -> void:
		hide_confirm()
		if _confirm_callback.is_valid():
			var cb := _confirm_callback
			_confirm_callback = Callable()
			cb.call()
		else:
			new_game_confirmed.emit())
	row.add_child(yes)

	var no := Button.new()
	no.name = "ConfirmNo"
	no.text = "取消"
	no.custom_minimum_size = Vector2(100, 34)
	no.pressed.connect(func() -> void: hide_confirm())
	row.add_child(no)

	_confirm_root = root


## 对话面板（正式对话 UI）。
##
## 形态：底部居中面板 = 说话人 + 台词 + 副提示行 + 回复/话题按钮列表。
## 全屏透明挡板吞掉世界点击（对话期间不该与场景热点交互），
## 点挡板空白处 = 结束对话（与「结束对话」按钮等价）。
func _build_dialogue() -> void:
	var root := Control.new()
	root.name = "DialogueRoot"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	_root.add_child(root)
	_dialogue_root = root

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.30)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim_click := func() -> void:
		dialogue_close_requested.emit()
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			dim_click.call())
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -340.0
	panel.offset_right = 340.0
	panel.offset_top = -330.0
	panel.offset_bottom = -150.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.058, 0.070, 0.94)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(16.0)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "VBox"
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_dlg_speaker = Label.new()
	_dlg_speaker.name = "SpeakerLabel"
	_dlg_speaker.text = ""
	_dlg_speaker.add_theme_font_size_override("font_size", 17)
	_dlg_speaker.add_theme_color_override("font_color", COLOR_ACCENT)
	box.add_child(_dlg_speaker)

	_dlg_text = Label.new()
	_dlg_text.name = "TextLabel"
	_dlg_text.text = ""
	_dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_text.custom_minimum_size = Vector2(0.0, 56.0)
	_dlg_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dlg_text.add_theme_font_size_override("font_size", 16)
	_dlg_text.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(_dlg_text)

	_dlg_hint = Label.new()
	_dlg_hint.name = "HintLabel"
	_dlg_hint.text = ""
	_dlg_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_hint.add_theme_font_size_override("font_size", 13)
	_dlg_hint.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(_dlg_hint)

	_dlg_list = VBoxContainer.new()
	_dlg_list.name = "OptionList"
	_dlg_list.add_theme_constant_override("separation", 6)
	box.add_child(_dlg_list)

	var close := Button.new()
	close.name = "DialogueClose"
	close.text = "结束对话"
	close.custom_minimum_size = Vector2(110, 30)
	close.add_theme_font_size_override("font_size", 14)
	close.pressed.connect(func() -> void: dialogue_close_requested.emit())
	box.add_child(close)


func ask_new_game() -> void:
	show_confirm("重新开始会清除当前存档，确定吗？", Callable())


## 通用确认框：调用方给文案与「确定」回调。
## callback 为空时回退到发出 new_game_confirmed（保持旧调用方语义不变）。
func show_confirm(text: String, on_yes: Callable) -> void:
	if _confirm_root == null:
		return
	if _confirm_label != null:
		_confirm_label.text = text
	_confirm_callback = on_yes
	_confirm_root.visible = true


func hide_confirm() -> void:
	if _confirm_root != null:
		_confirm_root.visible = false


func is_confirm_visible() -> bool:
	return _confirm_root != null and _confirm_root.visible


# ---------------------------------------------------------------- 对话面板 API

## 摆出话题列表（对话开始时）。topics 为 String 数组（按钮文案）。
func show_dialogue_topics(speaker: String, topics: Array, hint: String = "") -> void:
	if _dialogue_root == null:
		return
	_dlg_speaker.text = speaker
	_dlg_text.text = "想聊点什么？"
	_dlg_hint.text = hint
	_dlg_hint.visible = not hint.is_empty()
	_rebuild_options(topics, dialogue_topic_chosen)
	_dialogue_root.visible = true


## 摆出台词与回复分支。replies 为 String 数组（玩家回复文案），
## 点击第 i 个发出 dialogue_reply_chosen(i)；replies 为空表示这条线到头。
func show_dialogue_line(speaker: String, text: String, replies: Array, hint: String = "") -> void:
	if _dialogue_root == null:
		return
	_dlg_speaker.text = speaker
	_dlg_text.text = text
	_dlg_hint.text = hint
	_dlg_hint.visible = not hint.is_empty()
	_rebuild_options(replies, dialogue_reply_chosen)
	_dialogue_root.visible = true


func set_dialogue_hint(text: String) -> void:
	if _dlg_hint == null:
		return
	_dlg_hint.text = text
	_dlg_hint.visible = not text.is_empty()


func hide_dialogue() -> void:
	if _dialogue_root != null:
		_dialogue_root.visible = false


func is_dialogue_open() -> bool:
	return _dialogue_root != null and _dialogue_root.visible


## 重建选项按钮。按钮名带序号（OptionButton0…），便于测试定位。
func _rebuild_options(labels: Array, signal_ref: Signal) -> void:
	for c in _dlg_list.get_children():
		_dlg_list.remove_child(c)
		c.queue_free()
	for i in range(labels.size()):
		var b := Button.new()
		b.name = "OptionButton%d" % i
		b.text = str(labels[i])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0.0, 32.0)
		b.add_theme_font_size_override("font_size", 15)
		var idx := i
		b.pressed.connect(func() -> void: signal_ref.emit(idx))
		_dlg_list.add_child(b)


# ---------------------------------------------------------------- 对外 API

func set_clock(text: String) -> void:
	if _clock != null:
		_clock.text = text


func set_location_name(name: String) -> void:
	if _location_label != null:
		_location_label.text = name


func set_focus_text(text: String) -> void:
	if _focus_label == null:
		return
	_focus_label.text = text
	_focus_label.visible = not text.is_empty()


func set_message(text: String, duration_seconds: float = 0.0) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	var has_text := not text.is_empty()
	_message_label.visible = has_text
	if _message_bg != null:
		_message_bg.visible = has_text
	if duration_seconds > 0.0:
		var captured := text
		var timer := get_tree().create_timer(duration_seconds)
		timer.timeout.connect(func() -> void:
			if _message_label != null and _message_label.text == captured:
				_message_label.visible = false
				if _message_bg != null:
					_message_bg.visible = false
		)


func set_back_enabled(value: bool) -> void:
	if _back_button != null:
		_back_button.disabled = not value


func set_reticle_visible(value: bool) -> void:
	if _reticle != null:
		_reticle.visible = value


## 后续虚拟桌面 / 聊天 / 浏览器等扩展的挂载点。
func register_overlay(panel: Control) -> void:
	if panel == null or _overlay_root == null:
		return
	_overlay_root.add_child(panel)
