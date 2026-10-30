## Main — 应用装配与输入路由
##
## 职责边界：
##   把 GameServices（逻辑层）与各场景节点（表现层）连起来，并把原始输入翻译成游戏动作。
##   这里不写任何剧情规则，也不直接操作 UI 文本。
##
## 输入约定：
##   鼠标左键按住拖动 → 环视
##   鼠标左键轻点（位移小于阈值）→ 与准星所指热点交互
##   ESC → 退出
##   点击判定放在 _unhandled_input，保证 UI 按钮上的点击不会被当成场景交互。

extends Node3D

const CLICK_TOLERANCE_PIXELS := 6.0

@onready var _location_container: Node3D = $LocationContainer
@onready var _camera_rig = $CameraRig
@onready var _ui = $HUD

var _press_position := Vector2.ZERO
var _press_valid := false
var _started := false


func _ready() -> void:
	randomize()

	if GameServices == null:
		push_error("COMET: GameServices autoload 不可用")
		return

	_bind_services()

	if GameServices.is_ready:
		_start_flow()
	else:
		GameServices.bootstrap_completed.connect(_start_flow)
		GameServices.bootstrap_failed.connect(_on_bootstrap_failed)


func _bind_services() -> void:
	GameServices.player_controller = _camera_rig
	GameServices.ui = _ui

	if GameServices.scene_manager != null:
		GameServices.scene_manager.set_container(_location_container)
		GameServices.scene_manager.location_entered.connect(_on_location_entered)
		GameServices.scene_manager.location_failed.connect(_on_location_failed)

	if GameServices.interaction_manager != null and _camera_rig != null:
		GameServices.interaction_manager.set_camera(_camera_rig.get_camera())
		GameServices.interaction_manager.hotspot_focused.connect(_on_hotspot_focused)
		GameServices.interaction_manager.hotspot_unfocused.connect(_on_hotspot_unfocused)
		GameServices.interaction_manager.hotspot_activated.connect(_on_hotspot_activated)

	if GameServices.event_manager != null:
		GameServices.event_manager.event_triggered.connect(_on_event_triggered)

	if _ui != null:
		_ui.back_requested.connect(_on_back_requested)
		_ui.save_requested.connect(_on_save_requested)
		_ui.quit_requested.connect(_on_quit_requested)
		if _ui.has_signal("new_game_requested"):
			_ui.new_game_requested.connect(_on_new_game_requested)


func _start_flow() -> void:
	if _started:
		return
	_started = true

	if GameServices.has_save():
		var ok := GameServices.continue_game()
		if not ok:
			GameServices.new_game()
			if _ui != null:
				_ui.set_message("存档已损坏，已开始新的观察。", 4.0)
		else:
			if _ui != null:
				_ui.set_message("你回到了上次离开的地方。", 4.0)
	else:
		GameServices.new_game()
		if _ui != null:
			_ui.set_message("屋子里很安静。屏幕上映着一小段没有声音的画面。", 5.0)

	_refresh_ui_state()


func _on_bootstrap_failed(reason: String) -> void:
	push_error("COMET bootstrap failed: %s" % reason)
	if _ui != null:
		_ui.set_message("初始化失败: %s" % reason, 12.0)


func _refresh_ui_state() -> void:
	if _ui == null or GameServices.scene_manager == null:
		return
	var current := GameServices.scene_manager.get_current_location_id()
	_ui.set_location_name(GameServices.scene_manager.get_location_name(current))
	_ui.set_back_enabled(GameServices.scene_manager.can_go_back())
	_ui.set_clock(GameServices.get_clock_text())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_position = mb.position
				_press_valid = true
			else:
				var is_click := _press_valid and mb.position.distance_to(_press_position) <= CLICK_TOLERANCE_PIXELS
				_press_valid = false
				if is_click and GameServices.interaction_manager != null:
					GameServices.interaction_manager.activate_focused()

	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			_on_quit_requested()


func _on_hotspot_focused(spot: Hotspot) -> void:
	if _ui == null:
		return
	_ui.set_focus_text(spot.get_hint_text())


func _on_hotspot_unfocused(_spot: Hotspot) -> void:
	if _ui == null:
		return
	_ui.set_focus_text("")


func _on_hotspot_activated(spot: Hotspot) -> void:
	if spot == null:
		return
	match spot.action_kind:
		"exit":
			if spot.target_location.is_empty():
				_notify("这里走不通。")
				return
			var label := GameServices.scene_manager.get_exit_label(
				GameServices.get_current_location_id(), spot.target_location
			)
			_notify(label)
			if not GameServices.go_to(spot.target_location):
				_notify("无法前往那里。")
		"examine":
			var text := spot.examine_text
			if text.is_empty():
				text = "你看不出它有什么特别。"
			_notify(text)
		_:
			_notify("什么也没有发生。")


func _on_location_entered(location_id: String, display_name: String) -> void:
	if _ui != null:
		_ui.set_location_name(display_name)
		_ui.set_back_enabled(GameServices.scene_manager.can_go_back())
		_ui.set_focus_text("")


func _on_location_failed(_location_id: String, error: String) -> void:
	push_error("COMET 地点切换失败: %s" % error)
	_notify("切换失败: %s" % error)


func _on_event_triggered(_event_id: String, _from_world: String, _to_world: String, log_text: String) -> void:
	if not log_text.is_empty():
		_notify(log_text, 6.0)


func _on_back_requested() -> void:
	if not GameServices.go_back():
		_notify("没有可以回去的地方。")


func _on_save_requested() -> void:
	GameServices.save_game()


func _on_new_game_requested() -> void:
	if GameServices.delete_save():
		GameServices.new_game()
		_refresh_ui_state()
		_notify("重新开始了。")


func _on_quit_requested() -> void:
	get_tree().quit()


func _notify(text: String, duration: float = 4.0) -> void:
	if _ui != null:
		_ui.set_message(text, duration)
