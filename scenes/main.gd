## Main — 应用装配与输入路由
##
## 职责边界：
##   把 GameServices（逻辑层）与各场景节点（表现层）连起来，并把原始输入翻译成游戏动作。
##   这里不写任何剧情规则，也不直接操作 UI 文本。
##
## 输入约定（鼠标捕获式第一人称）：
##   鼠标移动          → 直接转动视角（捕获状态下，无须按住任何键）
##   E 键 / 鼠标左键   → 与屏幕中心所指的热点交互
##   ESC               → 释放鼠标、显示系统光标（此时可操作 UI）
##   Q 键              → 退出游戏
##   鼠标释放后点击画面 → 重新捕获鼠标（这次点击只用于恢复捕获，不触发交互）
##
## 所有输入判定放在 _unhandled_input：
##   UI 控件会先消费掉落在自己身上的事件，因此点击 HUD 按钮不会被当成场景交互，
##   也不会误触发「重新捕获」，镜头控制与 UI 操作互不抢占。

extends Node3D

@onready var _location_container: Node3D = $LocationContainer
@onready var _camera_rig = $CameraRig
@onready var _ui = $HUD

var _started := false

## 待消费的门级落点。热点带 use_target_spawn 时，在 go_to() 之前写入这里，
## 由 _on_location_entered 取用后立即清空。
## 用「挂起—消费」而不是给 SceneManager 加参数，是为了让 enter_location 的
## 旧签名与所有既有调用（含测试、go_back、读档）保持完全不变。
var _pending_spawn: Variant = null
var _pending_yaw_deg: float = 0.0


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

	# 等一帧确保窗口就绪，再捕获鼠标。
	# 过早捕获在部分平台会失败，导致玩家进入游戏后鼠标仍然可见。
	await get_tree().process_frame
	_capture_mouse()
	if _ui != null:
		_ui.set_message("移动鼠标环视 · E 交互 · ESC 释放鼠标 · Q 退出", 7.0)


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
	# ---- 键盘 ----
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE:
				# ESC 专职释放鼠标；退出改由 Q 键负责
				_release_mouse()
				get_viewport().set_input_as_handled()
				return
			if key.keycode == KEY_Q:
				_on_quit_requested()
				get_viewport().set_input_as_handled()
				return

	# ---- 交互键 E ----
	if event.is_action_pressed(GameServices.ACTION_INTERACT):
		_try_interact()
		get_viewport().set_input_as_handled()
		return

	# ---- 鼠标左键 ----
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _is_mouse_captured():
				_try_interact()
			else:
				# 未捕获状态下，这一次点击只用于恢复捕获，不触发交互，
				# 避免玩家「点回游戏画面」时被误判成与某个热点交互。
				_capture_mouse()
			get_viewport().set_input_as_handled()


func _try_interact() -> void:
	if GameServices.interaction_manager == null:
		return
	if not GameServices.interaction_manager.activate_focused():
		_notify("这里没有什么可以互动的。", 2.0)


func _is_mouse_captured() -> bool:
	var pc = GameServices.player_controller
	return pc != null and pc.is_mouse_captured()


func _capture_mouse() -> void:
	var pc = GameServices.player_controller
	if pc != null:
		pc.capture_mouse()


func _release_mouse() -> void:
	var pc = GameServices.player_controller
	if pc != null:
		pc.release_mouse()


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
			# 门级落点：热点自带出现位置与朝向。没有则清空挂起值，
			# 保证「从非门热点 / 程序化切换」仍走地点 spawn。
			if spot.use_target_spawn:
				_pending_spawn = spot.target_spawn
				_pending_yaw_deg = spot.target_yaw_deg
			else:
				_pending_spawn = null
			var label := GameServices.scene_manager.get_exit_label(
				GameServices.get_current_location_id(), spot.target_location
			)
			_notify(label)
			if not GameServices.go_to(spot.target_location):
				_pending_spawn = null
				_notify("无法前往那里。")
		"examine":
			var text := spot.examine_text
			if text.is_empty():
				text = "你看不出它有什么特别。"
			_notify(text)
			# 观察也是一个消耗时间的动作；移动的时间消耗由 go_to 内部推进
			GameServices.advance_tick(1)
		_:
			_notify("什么也没有发生。")


func _on_location_entered(location_id: String, display_name: String) -> void:
	if _ui != null:
		_ui.set_location_name(display_name)
		_ui.set_back_enabled(GameServices.scene_manager.can_go_back())
		_ui.set_focus_text("")

	# 把玩家放到落点。
	# 优先消费门级落点：从哪扇门出来就落在对应位置、面朝对应方向。
	# 没有门级落点时才回退到地点 spawn——这是读档、go_back、首次开局等
	# 非穿门路径的唯一正确行为。
	var pc = GameServices.player_controller
	if pc != null and pc.has_method("reset_to_spawn"):
		if _pending_spawn != null:
			var pos: Vector3 = _pending_spawn
			var yaw_deg: float = _pending_yaw_deg
			_pending_spawn = null
			_pending_yaw_deg = 0.0
			pc.reset_to_spawn(pos)
			pc.yaw = deg_to_rad(yaw_deg)
			pc.pitch = 0.0
			pc._apply_rotation()
		else:
			pc.reset_to_spawn(GameServices.scene_manager.get_location_spawn(location_id))

	# 本场景新建的 portal 需要重新连接（旧实例的连接已随实例销毁）
	_connect_portals(GameServices.scene_manager.get_current_instance())


## 连接本场景内的所有 AutoPortal。
## 每次进入地点后必须重连：场景实例是新建的，旧连接随旧实例一起销毁。
func _connect_portals(root_node: Node) -> void:
	if root_node == null:
		return
	for c in _collect_nodes(root_node):
		if c is AutoPortal:
			var portal := c as AutoPortal
			if not portal.player_entered.is_connected(_on_portal_entered):
				portal.player_entered.connect(_on_portal_entered)


func _collect_nodes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_collect_nodes(c))
	return out


## 区域触发（黑暗区域穿越）。
##
## 顺序至关重要：先求值事件（可能切换现实），再切场景。
## 反过来的话，新场景会先按旧现实加载一帧，再刷新成新现实——玩家会看到画面「闪一下」，
## 那正是我们想避免的「像加载」的观感。
func _on_portal_entered(portal: AutoPortal) -> void:
	if portal == null:
		return

	if not portal.event_kind.is_empty() and GameServices.event_manager != null:
		var errs: Array = []
		GameServices.event_manager.evaluate(
			portal.event_kind, portal.event_keys,
			GameServices.world_manager, errs)
		for e in errs:
			push_warning("区域事件求值: %s" % str(e))

	if portal.target_location.is_empty():
		return

	if portal.use_target_spawn:
		_pending_spawn = portal.target_spawn
		_pending_yaw_deg = portal.target_yaw_deg
	else:
		_pending_spawn = null

	if not GameServices.go_to(portal.target_location):
		_pending_spawn = null
		_notify("这里走不通。")


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
	# 退出前必须把鼠标交还系统，否则可能残留捕获状态
	_release_mouse()
	get_tree().quit()


func _notification(what: int) -> void:
	# 窗口关闭按钮同样需要释放鼠标
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_release_mouse()
		get_tree().quit()


func _notify(text: String, duration: float = 4.0) -> void:
	if _ui != null:
		_ui.set_message(text, duration)
