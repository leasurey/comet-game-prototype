## Main — 应用装配与输入路由
##
## 职责边界：
##   把 GameServices（逻辑层）与各场景节点（表现层）连起来，并把原始输入翻译成游戏动作。
##   这里不写任何剧情规则，也不直接操作 UI 文本。
##
## 输入约定（鼠标捕获式第一人称）：
##   鼠标移动          → 直接转动视角（捕获状态下，无须按住任何键）
##   E 键 / 鼠标左键   → 与屏幕中心所指的热点交互
##   ESC               → 打开暂停菜单（暂停世界、释放鼠标）；菜单中再按 ESC 返回游戏
##   Q 键              → 退出游戏
##   鼠标释放后点击画面 → 重新捕获鼠标（这次点击只用于恢复捕获，不触发交互）
##
## 启动流程：
##   真实窗口 → 主菜单（新游戏 / 继续 / 设置 / 退出），由玩家选择后才进入世界
##   headless → 直接自动开局，保持既有测试的装配路径不变
##
## 所有输入判定放在 _unhandled_input：
##   UI 控件会先消费掉落在自己身上的事件，因此点击 HUD 按钮不会被当成场景交互，
##   也不会误触发「重新捕获」，镜头控制与 UI 操作互不抢占。

extends Node3D

## 暂停时必须继续接收输入（否则 ESC 关不掉菜单）。
## 世界节点仍是默认 PAUSABLE，`get_tree().paused` 会一并挡住移动与交互。

@onready var _location_container: Node3D = $LocationContainer
@onready var _camera_rig = $CameraRig
@onready var _ui = $HUD
@onready var _menu = $HUD/Menu

var _started := false

## 待消费的门级落点。热点带 use_target_spawn 时，在 go_to() 之前写入这里，
## 由 _on_location_entered 取用后立即清空。
## 用「挂起—消费」而不是给 SceneManager 加参数，是为了让 enter_location 的
## 旧签名与所有既有调用（含测试、go_back、读档）保持完全不变。
var _pending_spawn: Variant = null
var _pending_yaw_deg: float = 0.0

## 对话会话状态（P7 正式对话 UI）。
## _dlg_topic_nodes  = 当前话题列表对应的节点；_dlg_replies = 当前台词的回复分支。
var _dlg_npc: NPC = null
var _dlg_topic_nodes: Array = []
var _dlg_replies: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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

	# 输入锁的权威机制（CT-001/002）：世界子树显式 PAUSABLE。
	# Main 自身必须 ALWAYS（ESC 要在暂停时可达），子节点默认 INHERIT 会
	# 一路继承成 ALWAYS——实测暂停菜单打开时按 W 玩家仍移动、NPC 仍走动。
	# 显式把玩家与地点容器降为 PAUSABLE 后，get_tree().paused 就是唯一开关：
	# 暂停菜单与对话面板共用它，不再各自维护输入判断。
	if _camera_rig != null:
		_camera_rig.process_mode = Node.PROCESS_MODE_PAUSABLE
	if _location_container != null:
		_location_container.process_mode = Node.PROCESS_MODE_PAUSABLE

	if GameServices.scene_manager != null:
		GameServices.scene_manager.set_container(_location_container)
		GameServices.scene_manager.location_entered.connect(_on_location_entered)
		GameServices.scene_manager.location_failed.connect(_on_location_failed)

	if GameServices.interaction_manager != null and _camera_rig != null:
		GameServices.interaction_manager.set_camera(_camera_rig.get_camera())
		GameServices.interaction_manager.hotspot_focused.connect(_on_hotspot_focused)
		GameServices.interaction_manager.hotspot_unfocused.connect(_on_hotspot_unfocused)
		GameServices.interaction_manager.hotspot_activated.connect(_on_hotspot_activated)

	# 事件提示改走**总线**订阅。
	# 原因：new_game() 会重建 EventManager 实例，而 _bind_services 只在启动时跑一次，
	# 直接连 event_manager 的信号在"重新开始"之后就成了空连接——
	# 事件照样触发，但玩家再也看不到任何文字提示。
	# event_bus 由 GameServices 持有、生命周期与游戏同长，不存在被替换的问题。
	# 注意：只连总线，不再直连 event_manager，否则 GameServices 的转发会造成重复提示。
	if GameServices.event_bus != null:
		if not GameServices.event_bus.event_triggered.is_connected(_on_event_triggered):
			GameServices.event_bus.event_triggered.connect(_on_event_triggered)

	# 保存结果必须有反馈：此前调用后什么都不显示，玩家无法判断到底存没存上。
	if not GameServices.save_completed.is_connected(_on_save_completed):
		GameServices.save_completed.connect(_on_save_completed)

	if _ui != null:
		_ui.back_requested.connect(_on_back_requested)
		_ui.save_requested.connect(_on_save_requested)
		_ui.quit_requested.connect(_on_quit_requested)
		if _ui.has_signal("new_game_requested"):
			_ui.new_game_requested.connect(_on_new_game_requested)
		if _ui.has_signal("new_game_confirmed"):
			_ui.new_game_confirmed.connect(_on_new_game_confirmed)
		# 对话面板
		if _ui.has_signal("dialogue_topic_chosen"):
			_ui.dialogue_topic_chosen.connect(_on_dialogue_topic_chosen)
		if _ui.has_signal("dialogue_reply_chosen"):
			_ui.dialogue_reply_chosen.connect(_on_dialogue_reply_chosen)
		if _ui.has_signal("dialogue_close_requested"):
			_ui.dialogue_close_requested.connect(_on_dialogue_close_requested)

	# 主菜单 / 暂停 / 设置。
	# MenuController 不碰全局单例，服务引用在这里注入。
	if _menu != null:
		_menu.setup(GameServices.settings, GameServices)
		_menu.new_game_requested.connect(_on_menu_new_game)
		_menu.continue_requested.connect(_on_menu_continue)
		_menu.resume_requested.connect(_on_menu_resume)
		_menu.main_menu_requested.connect(_on_menu_main)
		_menu.quit_requested.connect(_on_quit_requested)

	# 玩家偏好（灵敏度/反转）在绑定到玩家的那一刻就生效。
	if GameServices.settings != null:
		GameServices.settings.apply(_camera_rig, false)

	# 移动/跳跃/落地音效跟随玩家状态
	GameServices.wire_player_audio(_camera_rig)


func _start_flow() -> void:
	if _started:
		return
	_started = true

	# headless（自动化测试）保持原来的自动开局路径，既有断言的装配时序不变。
	# 真实窗口走主菜单，由玩家决定新游戏还是继续。
	if DisplayServer.get_name() == "headless":
		_auto_start()
		return

	if _menu != null:
		_menu.show_main(GameServices.has_save())
	if _ui != null:
		_ui.set_message("选择「开始新游戏」或「继续游戏」进入。", 8.0)


## 测试与 headless 用的自动开局。
func _auto_start() -> void:
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
		_ui.set_message("移动鼠标环视 · E 交互 · ESC 暂停 · Q 退出", 7.0)


# ---------------------------------------------------------------- 主菜单动作

func _on_menu_new_game() -> void:
	# 有存档时先确认再删，避免「点错一下就没了」。
	if GameServices.has_save():
		if _ui != null:
			_ui.show_confirm("开始新游戏会覆盖当前进度，确定吗？", _on_menu_new_game_confirmed)
		return
	_on_menu_new_game_confirmed()


func _on_menu_new_game_confirmed() -> void:
	GameServices.delete_save()
	GameServices.new_game()
	_enter_world_from_menu("屋子里很安静。屏幕上映着一小段没有声音的画面。")


func _on_menu_continue() -> void:
	if GameServices.continue_game():
		_enter_world_from_menu("你回到了上次离开的地方。")
	else:
		if _ui != null:
			_ui.set_message("存档读取失败，已开始新的观察。", 5.0)
		GameServices.new_game()
		_enter_world_from_menu("存档已损坏，已开始新的观察。")


func _enter_world_from_menu(greeting: String) -> void:
	if _menu != null:
		_menu.hide_menu()
	get_tree().paused = false
	_refresh_ui_state()
	if _ui != null:
		_ui.set_message(greeting, 5.0)
	await get_tree().process_frame
	_capture_mouse()
	if _ui != null:
		_ui.set_message("移动鼠标环视 · E 交互 · ESC 暂停 · Q 退出", 7.0)


func _on_menu_resume() -> void:
	_close_pause()


func _on_menu_main() -> void:
	# 回主菜单 = 暂停世界但不销毁进度；玩家可继续或开新局。
	if _menu != null:
		_menu.show_main(GameServices.has_save())
	_release_mouse()
	get_tree().paused = true


func _open_pause() -> void:
	if _menu == null:
		_release_mouse()
		return
	_menu.show_pause()
	_release_mouse()
	get_tree().paused = true


func _close_pause() -> void:
	if _menu != null:
		_menu.hide_menu()
	get_tree().paused = false
	await get_tree().process_frame
	_capture_mouse()


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


func _process(_delta: float) -> void:
	# P7：驱动 NPC 的导航烘焙时序与状态推进
	if GameServices.npc_manager != null:
		GameServices.npc_manager.tick()


func _unhandled_input(event: InputEvent) -> void:
	# ---- 键盘 ----
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE:
				# ESC = 对话面板优先：开着对话时先结束对话，
				# 其次才是暂停菜单开关。
				if _ui != null and _ui.is_dialogue_open():
					_close_dialogue()
					get_viewport().set_input_as_handled()
					return
				# ESC = 暂停菜单开关。菜单开着时它是「返回游戏」，
				# 关着时它是「暂停」。世界被暂停后不再响应移动与交互。
				if _is_menu_open():
					_close_pause()
				else:
					_open_pause()
				get_viewport().set_input_as_handled()
				return
			if key.keycode == KEY_Q:
				_on_quit_requested()
				get_viewport().set_input_as_handled()
				return

	# 菜单开着时，世界输入全部屏蔽（暂停/主菜单/设置都不该触发交互）。
	if _is_menu_open():
		return

	# 对话面板开着时同样屏蔽世界输入：鼠标点击只作用于对话按钮，
	# E 键与场景交互一律不响应。
	if _ui != null and _ui.is_dialogue_open():
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
	if GameServices.interaction_manager.activate_focused():
		return
	# 没有热点被聚焦时，尝试与附近的 NPC 交谈。
	# 距离上限与热点交互一致（2.5 m），由 NPCManager 判定。
	if GameServices.npc_manager != null:
		var pc = GameServices.player_controller
		if pc != null:
			var near: NPC = GameServices.npc_manager.find_talkable_near(pc.global_position, 2.5)
			if near != null:
				_start_dialogue(near)
				return
	_notify("这里没有什么可以互动的。", 2.0)


## 与某个 NPC 开始对话：摆出话题列表（认知闸门过滤后的入口节点）。
## 之后由对话面板的点击驱动 _show_dialogue_node 的分支推进。
func _start_dialogue(npc: NPC) -> void:
	if npc == null or GameServices.dialogue_manager == null or _ui == null:
		return
	var entries: Array = GameServices.dialogue_manager.get_entry_nodes_for(npc.character_id)
	if entries.is_empty():
		_notify("%s 现在没什么可说的。" % npc.display_name, 3.0)
		return
	_dlg_npc = npc
	_dlg_topic_nodes = entries
	_dlg_replies = []
	npc.start_talking(GameServices.player_controller.global_position \
			if GameServices.player_controller != null else Vector3.ZERO)
	var labels: Array = []
	for n in entries:
		var t := str((n as Dictionary).get("topic", ""))
		if t.is_empty():
			# 数据没写 topic 时用台词作兜底文案，保证按钮永远有字
			t = str((n as Dictionary).get("text", ""))
		labels.append(t)
	_release_mouse()
	# 对话期间世界冻结（CT-002）：与暂停菜单共用树暂停。
	# 玩家不能边说话边走开，其他 NPC/物理也停在原地。
	get_tree().paused = true
	_ui.show_dialogue_topics(npc.display_name, labels)


## 推进到某个对话节点：听取（授予认知）→ 展示台词与回复分支。
func _show_dialogue_node(node_id: String) -> void:
	if GameServices.dialogue_manager == null or _ui == null:
		return
	var heard: Dictionary = GameServices.dialogue_manager.hear(
			node_id,
			GameServices.world_manager.get_current_world_id(),
			GameServices.get_tick())
	if not bool(heard.get("ok", false)):
		_notify(str(heard.get("error", "对话失败")), 3.0)
		_close_dialogue()
		return
	if _dlg_npc != null and GameServices.player_controller != null:
		_dlg_npc.start_talking(GameServices.player_controller.global_position)
	var hint := ""
	var granted: Array = heard.get("granted", [])
	if not granted.is_empty():
		var labels: Array = []
		for fid in granted:
			labels.append(GameServices.cognition.get_label(str(fid)))
		hint = "你了解到：%s" % "、".join(labels)
	# fires：对话点火事件（批次 2）——听懂了这段话 → 世界状态因此改变
	var fired_ids: Array = heard.get("fired", [])
	if not fired_ids.is_empty() and GameServices.event_manager != null:
		for eid in fired_ids:
			var errs: Array = []
			GameServices.event_manager.fire_event(str(eid), {
				"node_id": node_id,
				"speaker": str(heard.get("speaker", "")),
			}, GameServices.world_manager, errs)
			for e in errs:
				push_warning("对话事件 %s: %s" % [str(eid), str(e)])
	_dlg_replies = (heard.get("replies", []) as Array).duplicate(true)
	var reply_labels: Array = []
	for r in _dlg_replies:
		reply_labels.append(str((r as Dictionary).get("text", "")))
	_ui.show_dialogue_line(
			_dlg_npc.display_name if _dlg_npc != null else "",
			str(heard.get("text", "")),
			reply_labels,
			hint)


func _on_dialogue_topic_chosen(index: int) -> void:
	if index < 0 or index >= _dlg_topic_nodes.size():
		return
	_show_dialogue_node(str((_dlg_topic_nodes[index] as Dictionary).get("id", "")))


func _on_dialogue_reply_chosen(index: int) -> void:
	if index < 0 or index >= _dlg_replies.size():
		return
	var goto_id: Variant = (_dlg_replies[index] as Dictionary).get("goto", null)
	if goto_id == null:
		_close_dialogue()
		return
	_show_dialogue_node(str(goto_id))


func _on_dialogue_close_requested() -> void:
	_close_dialogue()


func _close_dialogue() -> void:
	if _ui != null:
		_ui.hide_dialogue()
	if _dlg_npc != null:
		_dlg_npc.stop_talking()
	_dlg_npc = null
	_dlg_topic_nodes = []
	_dlg_replies = []
	# 解冻世界（暂停菜单若同时开着则保持暂停）
	if not _is_menu_open():
		get_tree().paused = false
	_capture_mouse()



func _is_menu_open() -> bool:
	return _menu != null and _menu.is_open()


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
			if GameServices.audio_manager != null:
				GameServices.audio_manager.play_door_open()
			if not GameServices.go_to(spot.target_location):
				_pending_spawn = null
				_notify("无法前往那里。")
		"examine":
			if GameServices.audio_manager != null:
				GameServices.audio_manager.play_examine()
			# P6：亲眼检查过物品，玩家才「知道」它。
			# 这是认知的 inspect 来源，与世界状态无关。
			if GameServices.cognition != null and not spot.name.is_empty():
				var fid := "fact_inspected_%s" % spot.name
				if GameServices.cognition.learn(fid, "inspect", str(spot.name),
						GameServices.world_manager.get_current_world_id(),
						GameServices.get_tick()):
					_notify("你记下了关于「%s」的情况。" % spot.get_hint_text(), 3.0)
				# 语义事实（CT-019）：对话闸门用语义 id，必须由亲眼检查接通，
				# 否则「门上的便签」等话题在真实游玩中永远无法解锁。
				if not spot.grants_fact.is_empty():
					if GameServices.cognition.learn(spot.grants_fact, "inspect",
							str(spot.name),
							GameServices.world_manager.get_current_world_id(),
							GameServices.get_tick()):
						_notify("你了解到：%s。" % GameServices.cognition.get_label(spot.grants_fact), 4.0)
			var text := spot.examine_text
			if text.is_empty():
				text = "你看不出它有什么特别。"
			_notify(text)
			# 观察也是一个消耗时间的动作；移动的时间消耗由 go_to 内部推进
			GameServices.advance_tick(1)
		_:
			_notify("什么也没有发生。")

	# interact 事件求值（CT-005）：激活热点后让事件系统有机会改变世界状态。
	# 求值失败不阻断交互反馈，但要留痕。
	if GameServices.event_manager != null:
		var errs: Array = []
		GameServices.event_manager.evaluate("interact", {
			"hotspot_id": spot.name,
			"location_id": GameServices.get_current_location_id(),
		}, GameServices.world_manager, errs)
		for e in errs:
			push_warning("interact 事件求值: %s" % str(e))


func _on_location_entered(location_id: String, display_name: String) -> void:
	# 环境音随地点切换：室内房间底噪，室外风声。
	if GameServices.audio_manager != null:
		var indoor: bool = location_id != "house_exterior" and location_id != "dark_road"
		GameServices.audio_manager.set_ambience(indoor)
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

	# P7：在住宅里生成 NPC 并烘焙导航（其他地点不生成，避免角色出现在街上）
	if GameServices.npc_manager != null:
		var inst2 := GameServices.scene_manager.get_current_instance()
		if location_id == "party_house" and inst2 != null:
			GameServices.npc_manager.spawn_all(inst2)
		else:
			GameServices.npc_manager._despawn_all()


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
		var fired: Array = GameServices.event_manager.evaluate(
			portal.event_kind, portal.event_keys,
			GameServices.world_manager, errs)
		# 事件求值失败时**不切场景**。
		# 此前的实现只 push_warning 然后照切：玩家穿过黑暗到了对面，
		# 现实却没变——环境毫无差异，而叙事已经暗示"你走错了"，
		# 这是最难排查的静默不一致。宁可停在原地并给出提示。
		if not errs.is_empty():
			for e in errs:
				push_error("区域事件求值失败: %s" % str(e))
			_notify("有什么东西不对劲，你退了回来。", 5.0)
			return
		# fact_dark_road 由 transition 的 grant_fact effect 授予（批次 2），
		# 不再在此处硬编码。穿越完成的叙述反馈由事件 log 文本承担。

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


## 保存结果反馈。此前调用 save_game() 后什么都不显示，
## 玩家点完"保存"不知道到底存上了没有。
func _on_save_completed(ok: bool, message: String) -> void:
	if ok:
		_notify("进度已保存。", 3.0)
	else:
		_notify("保存失败：%s" % message, 8.0)


## 「重新开始」第一步：只问，不动数据。
## 鼠标必须可见，否则玩家没法点确认按钮。
func _on_new_game_requested() -> void:
	if _ui != null and _ui.has_method("ask_new_game"):
		_release_mouse()
		_ui.ask_new_game()
	else:
		_on_new_game_confirmed()


## 「重新开始」第二步：确认后才真正删档开新局。
func _on_new_game_confirmed() -> void:
	# 兜底关闭确认框：正常路径由"确定"按钮自己关闭，但任何直接调用
	# （测试、快捷键、未来的键盘确认）都必须让面板收起，否则会挡住画面。
	if _ui != null and _ui.has_method("hide_confirm"):
		_ui.hide_confirm()
	if not GameServices.delete_save():
		_notify("无法清除旧存档，已取消。", 5.0)
		return
	var ok: bool = GameServices.new_game()
	_refresh_ui_state()
	if ok:
		_notify("重新开始了。", 3.0)
	else:
		_notify("重新开始失败，请检查数据完整性。", 8.0)
	_capture_mouse()


func _on_quit_requested() -> void:
	# 退出前必须把鼠标交还系统，否则可能残留捕获状态
	_release_mouse()
	# 音频必须在主循环仍运转时停掉：放到退出阶段再释放，
	# AudioServer 侧的 voice 引用回收不掉，退出日志会报对象泄漏（P3）。
	if GameServices != null:
		GameServices.shutdown_audio()
	get_tree().quit()


func _notification(what: int) -> void:
	# 窗口关闭按钮同样需要释放鼠标
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_release_mouse()
		if GameServices != null:
			GameServices.shutdown_audio()
		get_tree().quit()
	# 窗口失焦时必须交出鼠标：否则 Alt+Tab 切走后回来，
	# 鼠标可能仍处于捕获态，玩家既看不见光标也点不到界面。
	# 聚焦不自动重新捕获——等玩家自己点击画面，避免视角在手一抖时突然跳转。
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_mouse()


func _notify(text: String, duration: float = 4.0) -> void:
	if _ui != null:
		_ui.set_message(text, duration)
