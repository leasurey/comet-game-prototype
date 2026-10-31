## MenuController — 主菜单、暂停与设置界面
## 只负责界面与信号；游戏状态切换由 main 决定。
##
## 不引用 GameServices 全局标识符：该标识符在 `--script` 测试模式下不可用，
## 而且 UI 层也不该直接摸全局单例。服务引用由 setup() 注入。

class_name MenuController
extends Control

signal new_game_requested
signal continue_requested
signal resume_requested
signal quit_requested
signal main_menu_requested

var _settings: SettingsManager = null
var _services = null
var _root: Control = null
var _content: VBoxContainer = null
var _title: Label = null
var _status: Label = null
var _mode: String = ""
var _settings_return: String = "pause"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func setup(settings: SettingsManager, services = null) -> void:
	_settings = settings
	_services = services


func _build() -> void:
	_root = Control.new()
	_root.name = "MenuRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.018, 0.020, 0.026, 0.96)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -250
	panel.offset_top = -270
	panel.offset_right = 250
	panel.offset_bottom = 270
	_root.add_child(panel)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.add_theme_constant_override("separation", 12)
	panel.add_child(_content)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_content.add_child(_title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(440, 52)
	_content.add_child(_status)


func _clear() -> void:
	# 先摘出树再 queue_free：否则旧按钮会残留到帧末，
	# 遍历子树时会先撞上即将删除的那个，读到过期状态。
	for child in _content.get_children():
		if child != _title and child != _status:
			_content.remove_child(child)
			child.queue_free()


func _show(mode: String, title: String, subtitle: String) -> void:
	_mode = mode
	_clear()
	_title.text = title
	_status.text = subtitle
	visible = true


func hide_menu() -> void:
	visible = false
	_mode = ""


func is_open() -> bool:
	return visible


func get_mode() -> String:
	return _mode


func show_main(can_continue: bool) -> void:
	_show("main", "COMET", "彗星经过的那一夜，有些门不再通向原来的地方。")
	_button("开始新游戏", func() -> void: new_game_requested.emit())
	var cont := _button("继续游戏", func() -> void: continue_requested.emit())
	cont.disabled = not can_continue
	_button("设置", show_settings.bind("main"))
	_button("退出", func() -> void: quit_requested.emit())


func show_pause() -> void:
	_show("pause", "暂停", "屋里的声音停在了你按下 Esc 的那一刻。")
	_button("继续", func() -> void: resume_requested.emit())
	_button("保存进度", func() -> void: _save_from_pause())
	_button("设置", show_settings.bind("pause"))
	_button("返回主菜单", func() -> void: main_menu_requested.emit())
	_button("退出游戏", func() -> void: quit_requested.emit())


func _save_from_pause() -> void:
	if _services != null:
		_services.save_game()


func show_settings(return_to: String = "pause") -> void:
	_settings_return = return_to
	_show("settings", "设置", "修改后立即生效并保存。")
	if _settings == null:
		_button("返回", _return_from_settings)
		return
	_slider("水平灵敏度", "sensitivity_x", 0.0005, 0.010, 0.0001)
	_slider("垂直灵敏度", "sensitivity_y", 0.0005, 0.010, 0.0001)
	_check("反转垂直视角", "invert_y")
	_slider("总音量", "master_volume", 0.0, 1.0, 0.05)
	_slider("音乐音量", "music_volume", 0.0, 1.0, 0.05)
	_slider("环境音量", "ambience_volume", 0.0, 1.0, 0.05)
	_slider("音效音量", "sfx_volume", 0.0, 1.0, 0.05)
	_slider("语音音量", "voice_volume", 0.0, 1.0, 0.05)
	_option("分辨率", "resolution", ["1280x720", "854x480", "640x360"])
	_option("帧率上限", "max_fps", [0, 30, 60, 120])
	_check("全屏", "fullscreen")
	_button("返回", _return_from_settings)


func _player():
	return _services.player_controller if _services != null else null


func _has_save() -> bool:
	return _services.has_save() if _services != null else false


func _return_from_settings() -> void:
	_settings.apply(_player())
	if _settings_return == "main":
		show_main(_has_save())
	else:
		show_pause()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(action)
	_content.add_child(b)
	return b


func _slider(label_text: String, key: String, min_v: float, max_v: float, step: float) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = float(_settings.get_value(key))
	slider.custom_minimum_size = Vector2(250, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size = Vector2(60, 0)
	row.add_child(value)
	var update := func(v: float) -> void:
		value.text = "%.4f" % v if step < 0.01 else "%.2f" % v
		_settings.set_value(key, v)
		_settings.apply(_player(), false)
	slider.value_changed.connect(update)
	update.call(slider.value)


func _check(label_text: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = label_text
	c.button_pressed = bool(_settings.get_value(key))
	c.toggled.connect(func(v: bool) -> void:
		_settings.set_value(key, v)
		_settings.apply(_player()))
	_content.add_child(c)


func _option(label_text: String, key: String, options: Array) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	for item in options:
		option.add_item(str(item))
	var current: Variant = _settings.get_value(key)
	for i in range(options.size()):
		if str(options[i]) == str(current):
			option.selected = i
	option.item_selected.connect(func(index: int) -> void:
		_settings.set_value(key, options[index])
		_settings.apply(_player()))
