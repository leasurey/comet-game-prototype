## GameServices — 全局服务编排
##
## 这是唯一的 autoload。它不做业务逻辑，只负责：
##   1. 在系统启动时按顺序 bootstrap 各 Manager 并注入依赖；
##   2. 把「加载数据 / 开新局 / 读档 / 存档 / 导航」整理成稳定 API 暴露给 main；
##   3. 维护游戏内时钟。
##
## 之所以不把 Manager 各自注册为 autoload：
##   让它们成为这里持有与装配的普通对象，依赖关系显式可见，
##   后续替换实现或加单元测试都不需要改工程配置。

extends Node

signal bootstrap_completed
signal bootstrap_failed(reason: String)
signal save_completed(ok: bool, message: String)
signal load_completed(ok: bool, message: String)

# 时钟用「整数 tick」表示，且由玩家动作离散推进（见 advance_tick），
# 不再由真实时间 delta 驱动——否则同一操作序列在不同游玩速度下会得到不同 tick，
# 「重放一致性」无法成立。
const START_CLOCK_MINUTES := 1360
const DEFAULT_MINUTES_PER_TICK := 1
# 新游戏默认种子固定，保证默认路径可复现；需要不同周目时调用 set_master_seed()。
const DEFAULT_MASTER_SEED := 0

const PATH_WORLDS := "res://data/worlds.json"
const PATH_TRANSITIONS := "res://data/world_transitions.json"
const PATH_EVENTS := "res://data/events.json"
const PATH_LOCATIONS := "res://data/locations.json"
const PATH_CHARACTERS := "res://data/characters.json"
const PATH_DIALOGUE := "res://data/dialogue.json"

# 输入动作名。集中定义在此，避免各脚本各自硬编码字符串。
const ACTION_INTERACT := "interact"
const ACTION_MOVE_FORWARD := "move_forward"
const ACTION_MOVE_BACK := "move_back"
const ACTION_MOVE_LEFT := "move_left"
const ACTION_MOVE_RIGHT := "move_right"

var world_manager: WorldManager = null
var event_manager: EventManager = null
var save_manager: SaveManager = null
var scene_manager: SceneManager = null
var interaction_manager: InteractionManager = null

# 玩家设置（灵敏度/音量/分辨率）。与游戏存档分离：删档不会重置玩家偏好。
var settings: SettingsManager = null

# P6 玩家认知：玩家亲证过什么（与客观世界状态严格分离）
var cognition: CognitionManager = null
# P7 对话与 NPC
var dialogue_manager: DialogueManager = null
var npc_manager: NPCManager = null

# 音频播放与分类音量。
var audio_manager: AudioManager = null

# L0 核心服务：时钟、随机、信号总线。三者都不含业务规则，可被任意层使用。
var time_service: TimeService = null
var rng_service: RngService = null
var event_bus: EventBus = null

var player_controller = null
var ui = null

var is_ready: bool = false
var bootstrap_error: String = ""

## 统一数据校验的错误清单。启动失败时可直接读它定位到「文件 + 对象 + 字段 + 原因」。
var data_errors: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_bootstrap()


func _process(_delta: float) -> void:
	if not is_ready:
		return
	# 时钟已改为动作驱动，这里只负责把当前值同步到 UI。
	if ui != null and ui.has_method("set_clock"):
		ui.set_clock(get_clock_text())


func _bootstrap() -> void:
	var errors: Array = []
	_ensure_input_actions()

	# 设置先于一切加载：玩家的灵敏度/帧率偏好应在第一帧就生效。
	settings = SettingsManager.new()
	settings.load_settings()

	audio_manager = AudioManager.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	audio_manager.bind_settings(settings)

	time_service = TimeService.new()
	time_service.configure(DEFAULT_MINUTES_PER_TICK, START_CLOCK_MINUTES)
	rng_service = RngService.new()
	rng_service.set_seed(DEFAULT_MASTER_SEED)
	event_bus = EventBus.new()

	cognition = CognitionManager.new()
	dialogue_manager = DialogueManager.new()
	dialogue_manager.set_cognition(cognition)
	npc_manager = NPCManager.new()
	npc_manager.set_cognition(cognition)
	npc_manager.set_dialogue(dialogue_manager)

	world_manager = WorldManager.new()
	event_manager = EventManager.new()
	save_manager = SaveManager.new()
	scene_manager = SceneManager.new()
	interaction_manager = InteractionManager.new()

	scene_manager.name = "SceneManager"
	interaction_manager.name = "InteractionManager"
	add_child(scene_manager)
	add_child(interaction_manager)
	# NPCManager 是 Node，必须入树。
	# 此前它只被成员变量引用、从未 add_child——Node 不会被引用计数释放，
	# 退出时就成了孤儿实例（「9 ObjectDB instances were leaked」的主源），
	# 并连带拖住它引用的 cognition/dialogue 两个 RefCounted。
	add_child(npc_manager)
	npc_manager.name = "NPCManager"

	scene_manager.world_manager = world_manager
	scene_manager.event_manager = event_manager
	scene_manager.interaction_manager = interaction_manager

	_inject_services()
	_wire_signals()

	# 四份数据先全部读出来，再**统一交叉校验**，最后才交给各 Manager。
	#
	# 顺序很重要：各 Manager 的 load_from_data 只校验自己那份数据内部是否自洽，
	# 跨文件引用（variants 指向不存在的现实、transitions 的 to_world 拼错、
	# area_enter 忘写 area_id）它看不见。先validate再load，错误能在启动时就暴露，
	# 而不是等到玩家穿过黑暗发现现实没变。
	var worlds_result := DataLoader.load_dictionary(PATH_WORLDS)
	if not bool(worlds_result.get("ok", false)):
		_fail(str(worlds_result.get("error", "未知错误")))
		return
	var events_result := DataLoader.load_dictionary(PATH_EVENTS)
	if not bool(events_result.get("ok", false)):
		_fail(str(events_result.get("error", "未知错误")))
		return
	var transitions_result := DataLoader.load_dictionary(PATH_TRANSITIONS)
	if not bool(transitions_result.get("ok", false)):
		_fail(str(transitions_result.get("error", "未知错误")))
		return
	var locations_result := DataLoader.load_dictionary(PATH_LOCATIONS)
	if not bool(locations_result.get("ok", false)):
		_fail(str(locations_result.get("error", "未知错误")))
		return

	var report: Dictionary = DataValidator.validate(
		worlds_result.get("data", {}),
		events_result.get("data", {}),
		transitions_result.get("data", {}),
		locations_result.get("data", {})
	)
	data_errors = report.get("errors", [])
	if not bool(report.get("ok", false)):
		var first := str((data_errors as Array)[0]) if not (data_errors as Array).is_empty() else "数据校验失败"
		_fail("数据校验未通过（共 %d 项）: %s" % [(data_errors as Array).size(), first])
		return

	errors.clear()
	if not world_manager.load_from_data(worlds_result.get("data", {}), errors):
		_fail(errors[0] if errors.size() > 0 else "世界数据载入失败")
		return

	errors.clear()
	if not event_manager.load_from_data(events_result.get("data", {}), transitions_result.get("data", {}), errors):
		_fail(errors[0] if errors.size() > 0 else "事件数据载入失败")
		return

	errors.clear()
	if not scene_manager.load_from_data(locations_result.get("data", {}), errors):
		_fail(errors[0] if errors.size() > 0 else "地点数据载入失败")
		return

	# P6/P7：角色档案与对话树（纯数据，不参与世界状态）
	var chars_result := DataLoader.load_dictionary(PATH_CHARACTERS)
	if not bool(chars_result.get("ok", false)):
		_fail("角色数据载入失败: %s" % str(chars_result.get("error", "")))
		return
	errors.clear()
	if not npc_manager.load_from_data(chars_result.get("data", {}), errors):
		_fail(errors[0] if errors.size() > 0 else "角色数据解析失败")
		return

	var dlg_result := DataLoader.load_dictionary(PATH_DIALOGUE)
	if not bool(dlg_result.get("ok", false)):
		_fail("对话数据载入失败: %s" % str(dlg_result.get("error", "")))
		return
	errors.clear()
	if not dialogue_manager.load_from_data(dlg_result.get("data", {}), errors):
		_fail(errors[0] if errors.size() > 0 else "对话数据解析失败")
		return
	errors.clear()
	if not cognition.load_from_data(dlg_result.get("data", {}), errors):
		_fail(errors[0] if errors.size() > 0 else "认知目录解析失败")
		return

	is_ready = true
	bootstrap_completed.emit()


## 注册本项目需要的输入动作。
##
## 采用运行时注册而非写进 project.godot，是为了避开手写输入映射序列化的格式风险；
## 同时用 InputMap.has_action() 做幂等保护，
## 因此既不会与既有映射重复定义，也不会在重复 bootstrap 时报错。
##
## 交互键使用 E：项目目前不存在任何输入映射（已核实），不存在冲突。
func _ensure_input_actions() -> void:
	_register_key_action(ACTION_INTERACT, KEY_E)
	_register_key_action(ACTION_MOVE_FORWARD, KEY_W)
	_register_key_action(ACTION_MOVE_BACK, KEY_S)
	_register_key_action(ACTION_MOVE_LEFT, KEY_A)
	_register_key_action(ACTION_MOVE_RIGHT, KEY_D)
	_register_key_action("jump", KEY_SPACE)
	_register_key_action("run", KEY_SHIFT)
	_register_key_action("phone", KEY_TAB)


## 幂等注册「一个动作 + 一个物理按键」。
## 若动作已存在但尚未绑定按键，则只补按键，不重复创建动作。
func _register_key_action(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)

	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return

	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action, key_event)


func _fail(reason: String) -> void:
	is_ready = false
	bootstrap_error = reason
	push_error("COMET bootstrap failed: %s" % reason)
	bootstrap_failed.emit(reason)


## 把 L0 服务注入需要它们的模块。
## 依赖关系集中在这里显式可见，而不是让各模块在内部互相寻找。
func _inject_services() -> void:
	if event_manager == null:
		return
	event_manager.rng_service = rng_service
	event_manager.tick_provider = time_service
	event_manager.visit_provider = scene_manager
	# effects 服务提供者（批次 2：事件状态效果）
	event_manager.cognition_service = cognition
	event_manager.npc_service = npc_manager
	event_manager.audio_service = audio_manager


## 把各模块的状态变化转接到总线。表现层只订阅总线，不直接连每个 Manager。
func _wire_signals() -> void:
	if world_manager != null and not world_manager.world_changed.is_connected(_on_world_changed):
		world_manager.world_changed.connect(_on_world_changed)
	if event_manager != null and not event_manager.event_triggered.is_connected(_on_event_triggered):
		event_manager.event_triggered.connect(_on_event_triggered)
	if scene_manager != null:
		if not scene_manager.location_entered.is_connected(_on_location_entered):
			scene_manager.location_entered.connect(_on_location_entered)
		if not scene_manager.location_failed.is_connected(_on_location_failed):
			scene_manager.location_failed.connect(_on_location_failed)
	# NPC 行为 → 事件（CT-021）：到达目标时求值 npc_arrived 触发器
	if npc_manager != null and not npc_manager.npc_arrived.is_connected(_on_npc_arrived):
		npc_manager.npc_arrived.connect(_on_npc_arrived)


## 玩家控制器绑定后接上音频（脚部/跳跃/落地）。
## 由 main._bind_services 在拿到 player_controller 时调用。
func wire_player_audio(player) -> void:
	if audio_manager == null or player == null:
		return
	if not player.jumped.is_connected(_on_player_jumped):
		player.jumped.connect(_on_player_jumped)
	if not player.landed.is_connected(_on_player_landed):
		player.landed.connect(_on_player_landed)
	if not player.footstep.is_connected(_on_player_footstep):
		player.footstep.connect(_on_player_footstep)


func _on_player_jumped() -> void:
	if audio_manager != null:
		audio_manager.play_jump()


func _on_player_landed(_impact: float) -> void:
	if audio_manager != null:
		audio_manager.play_land()


## 脚步由 PlayerController 按实际位移触发（步距 STRIDE_DISTANCE），
## 因此频率与移动速度一致，停下立即停止，不依赖任何定时循环。
func _on_player_footstep() -> void:
	if audio_manager != null:
		audio_manager.play_footstep("wood")


func _on_world_changed(from_id: String, to_id: String, reason_id: String) -> void:
	if npc_manager != null:
		npc_manager.update_world(to_id)
	if event_bus != null:
		event_bus.world_changed.emit(from_id, to_id, reason_id)
	if audio_manager != null:
		audio_manager.play_reality_shift()


func _on_event_triggered(event_id: String, from_id: String, to_id: String, log_text: String) -> void:
	if event_bus != null:
		event_bus.event_triggered.emit(event_id, from_id, to_id, log_text)


## NPC 到达行走目标 → 求值 npc_arrived 事件触发器（CT-021）。
func _on_npc_arrived(npc_id: String, room_id: String) -> void:
	if event_manager == null:
		return
	var errs: Array = []
	event_manager.evaluate("npc_arrived", {
		"npc": npc_id,
		"room": room_id,
	}, world_manager, errs)
	for e in errs:
		push_warning("npc_arrived 事件求值: %s" % str(e))


func _on_location_entered(location_id: String, display_name: String) -> void:
	if event_bus != null:
		event_bus.location_entered.emit(location_id, display_name)


func _on_location_failed(location_id: String, error: String) -> void:
	if event_bus != null:
		event_bus.location_failed.emit(location_id, error)


# ---------------------------------------------------------------- 新局 / 读档

## 开新局。seed_value 为负数时使用默认固定种子，保证默认路径可复现。
func new_game(seed_value: int = -1) -> bool:
	if not is_ready:
		return false
	world_manager = WorldManager.new()
	var errors: Array = []
	var worlds_result := DataLoader.load_dictionary(PATH_WORLDS)
	if not world_manager.load_from_data(worlds_result.get("data", {}), errors):
		return false

	event_manager = EventManager.new()
	var events_result := DataLoader.load_dictionary(PATH_EVENTS)
	var transitions_result := DataLoader.load_dictionary(PATH_TRANSITIONS)
	if not event_manager.load_from_data(events_result.get("data", {}), transitions_result.get("data", {}), errors):
		return false

	scene_manager.world_manager = world_manager
	scene_manager.event_manager = event_manager

	if time_service != null:
		time_service.reset()
	if rng_service != null:
		rng_service.set_seed(seed_value if seed_value >= 0 else DEFAULT_MASTER_SEED)
	# P6/P7：新局的认知与 NPC 必须归零，否则「重新开始」会继承上一局的已知信息
	if cognition != null:
		cognition.reset()
	if npc_manager != null:
		npc_manager._despawn_all()
		# 快照也要清：否则新局 spawn_all 会续上上一局 NPC 的位置与行为
		npc_manager.reset_session()

	# world_manager / event_manager 被重建，注入与连线必须重做
	_inject_services()
	_wire_signals()
	npc_manager.update_world(world_manager.get_current_world_id())

	# 会话状态必须归零，否则「重新开始」会继承上一局：
	# 返回栈留着→一按返回就退回上局地点；访问记录留着→依赖 visited 的事件条件被污染；
	# 朝向留着→新局面朝上局最后看的方向。
	scene_manager.reset_session()
	if player_controller != null and player_controller.has_method("reset_view"):
		player_controller.reset_view()

	return scene_manager.enter_location(scene_manager.get_start_location_id(), false)


func continue_game() -> bool:
	if not is_ready:
		load_completed.emit(false, "服务尚未就绪")
		return false

	var result := save_manager.load_state(scene_manager.get_location_ids(), world_manager.get_world_ids())
	if not bool(result.get("ok", false)):
		# 隔离损坏存档：否则每次启动都会失败一次再回退新局，玩家永远看不到真正的"新开始"
		var moved := save_manager.quarantine_corrupt()
		if not moved.is_empty():
			push_warning("COMET: 损坏存档已隔离到 %s" % moved)
		load_completed.emit(false, str(result.get("error", "读档失败")))
		return false

	var data: Dictionary = result.get("data", {})

	var world_errors: Array = []
	var world_state := {
		"current_world_id": str(data.get("world_id", "")),
		"change_log": (data.get("world_change_records", []) as Array).duplicate(true),
	}
	if not world_manager.restore(world_state, world_errors):
		load_completed.emit(false, world_errors[0] if world_errors.size() > 0 else "世界状态恢复失败")
		return false

	var event_errors: Array = []
	var event_state := {
		"history": data.get("event_history", {}),
		"sequence": data.get("event_sequence", []),
		"flags": data.get("event_flags", {}),
		"phase_id": str(data.get("phase_id", "")),
	}
	if not event_manager.restore(event_state, event_errors):
		load_completed.emit(false, event_errors[0] if event_errors.size() > 0 else "事件历史恢复失败")
		return false

	var scene_errors: Array = []
	var scene_state := {
		"current_location_id": str(data.get("location_id", "")),
		"visited_locations": data.get("visited_locations", []),
		"visit_stack": data.get("visit_stack", []),
	}
	if not scene_manager.restore(scene_state, scene_errors):
		load_completed.emit(false, scene_errors[0] if scene_errors.size() > 0 else "地点恢复失败")
		return false

	# 时钟：只恢复整数 tick，浮点累加器不入档，因此不存在跨设备漂移
	if time_service != null:
		var clock_err: Array = []
		time_service.restore({
			"tick": _read_clock_ticks(data),
			"minutes_per_tick": time_service.minutes_per_tick,
			"start_minutes": time_service.start_minutes,
		}, clock_err)

	# 随机流：主种子与计数一并恢复，保证读档后下一次取值与存档前一致
	if rng_service != null and data.has("rng_master_seed"):
		rng_service.set_seed(int(data.get("rng_master_seed", DEFAULT_MASTER_SEED)))
		var rng_err: Array = []
		rng_service.restore({
			"master_seed": rng_service.master_seed,
			"counters": data.get("rng_counters", {}),
		}, rng_err)

	var target := str(data.get("location_id", scene_manager.get_start_location_id()))
	# P6 玩家认知：读档后恢复「玩家知道什么」，与世界状态分开恢复
	if cognition != null:
		var cog_data: Variant = data.get("cognition", null)
		if typeof(cog_data) == TYPE_DICTIONARY:
			var cog_err: Array = []
			cognition.restore(cog_data as Dictionary, cog_err)
			for e in cog_err:
				push_warning("认知恢复: %s" % str(e))

	# P7 NPC 状态（CT-003 修复）：此前写档不读档，NPC 全员回出生点。
	# restore 双写「会话快照+活实体」，因此在 enter_location（内部 spawn_all
	# 消费快照）之前调用即有效；旧档 npc_states 为空时自然回退配置出生点。
	if npc_manager != null:
		npc_manager.restore((data.get("npc_states", []) as Array).duplicate(true))

	if not scene_manager.enter_location(target, false):
		load_completed.emit(false, "恢复地点失败: %s" % target)
		return false

	# 位置：存档里有就恢复到存档位置，没有才沿用地点 spawn（v1 存档就走这条路）。
	# 恢复前做一次胶囊重叠检测：若存档位置落在墙体/家具内部（改了布局后的旧档），
	# 宁可退回 spawn 也不要让玩家卡在几何里。
	var restored_pos := false
	var raw_pos: Variant = data.get("player_position", [])
	if typeof(raw_pos) == TYPE_ARRAY and (raw_pos as Array).size() == 3:
		var pos := Vector3(float((raw_pos as Array)[0]),
			float((raw_pos as Array)[1]), float((raw_pos as Array)[2]))
		if _is_position_free(pos):
			player_controller.reset_to_spawn(pos)
			restored_pos = true
		else:
			push_warning("COMET: 存档位置 %s 被占用，回退到地点出生点" % str(pos))

	if player_controller != null and player_controller.has_method("restore_view"):
		player_controller.restore_view(data.get("player_view", {}))

	load_completed.emit(true, "已恢复到 %s%s" % [
		scene_manager.get_location_name(target), "" if restored_pos else "（位置已回退）"])
	return true


## 判断某个脚底位置是否可站立：胶囊与 layer 1（环境）不重叠即可。
func _is_position_free(pos: Vector3) -> bool:
	if player_controller == null or not is_instance_valid(player_controller):
		return true
	var world: World3D = player_controller.get_world_3d()
	if world == null:
		return true
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.66
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.86, 0))
	q.collision_mask = 1
	q.exclude = [player_controller.get_rid()]
	return space.intersect_shape(q, 1).is_empty()


func save_game() -> bool:
	if not is_ready:
		save_completed.emit(false, "服务尚未就绪")
		return false

	var payload := {
		"location_id": scene_manager.get_current_location_id(),
		"world_id": world_manager.get_current_world_id(),
		"visited_locations": scene_manager.get_visited_locations(),
		"world_change_records": world_manager.get_change_log(),
		"triggered_events": event_manager.get_sequence(),
		"event_history": event_manager.get_history(),
		"event_sequence": event_manager.get_sequence(),
		# P6 玩家认知：知道什么、怎么知道的
		"known_facts": cognition.get_known_facts() if cognition != null else [],
		"cognition": cognition.serialize() if cognition != null else {},
		# P7 NPC 状态
		"npc_states": npc_manager.serialize() if npc_manager != null else [],
		"game_clock_ticks": get_tick(),
		"game_clock_minutes": get_clock_minutes(),
		"rng_master_seed": rng_service.master_seed if rng_service != null else 0,
		"rng_counters": rng_service.get_counters() if rng_service != null else {},
		"event_flags": (event_manager.serialize().get("flags", {}) if event_manager != null else {}),
		"phase_id": (event_manager.get_phase() if event_manager != null else ""),
		"player_view": player_controller.serialize_view() if player_controller != null and player_controller.has_method("serialize_view") else {},
		# 位置必须单独存：serialize_view 只含朝向。
		# 缺失时读档会把玩家送回地点出生点，玩家会以为"进度丢了"。
		"player_position": _serialize_player_position(),
		# 返回栈此前只写不读：payload 里根本没有这个键，而 continue_game 在读它，
		# 导致读档后"返回"按钮永远置灰。
		"visit_stack": (scene_manager.serialize().get("visit_stack", []) if scene_manager != null else []),
	}

	var result := save_manager.save(payload)
	var ok := bool(result.get("ok", false))
	save_completed.emit(ok, result.get("error", "") if not ok else "已保存进度")
	return ok


func delete_save() -> bool:
	if not is_ready:
		return false
	return bool(save_manager.delete_save().get("ok", false))


func _serialize_player_position() -> Array:
	if player_controller == null or not is_instance_valid(player_controller):
		return []
	var p: Vector3 = player_controller.global_position
	return [p.x, p.y, p.z]


# ---------------------------------------------------------------- 导航 API

## 退出前的统一清理入口。必须在主循环仍运转时调用（quit 之前）。
##
## stop 之后必须给音频混音线程留一个真实时间窗口：voice 的回收是异步的，
## 抢在回收之前退出会把 AudioStreamPlaybackWAV + AudioStreamWAV 留在
## ObjectDB 清点里（实测同帧 stop 后立刻退出仍有约 40% 概率泄漏）。
## 150ms 对退出体感无影响，换来退出日志确定性干净。
func shutdown_audio() -> void:
	if audio_manager != null:
		audio_manager.shutdown()
	OS.delay_msec(150)


func has_save() -> bool:
	if not is_ready:
		return false
	return save_manager.has_save()


func go_to(location_id: String) -> bool:
	if not is_ready:
		return false
	advance_tick(1)
	return scene_manager.enter_location(location_id, true)


func go_back() -> bool:
	if not is_ready:
		return false
	advance_tick(1)
	return scene_manager.go_back()


func get_current_location_id() -> String:
	if not is_ready:
		return ""
	return scene_manager.get_current_location_id()


func get_current_world_id() -> String:
	if not is_ready:
		return ""
	return world_manager.get_current_world_id()


# ---------------------------------------------------------------- 时钟

## 推进时钟。节点式探索没有连续移动，时间随玩家动作离散前进。
func advance_tick(steps: int = 1) -> void:
	if time_service == null:
		return
	time_service.advance(steps)
	if event_bus != null:
		event_bus.tick_advanced.emit(time_service.get_tick())


func get_tick() -> int:
	return time_service.get_tick() if time_service != null else 0


func get_clock_minutes() -> int:
	return time_service.get_clock_minutes() if time_service != null else START_CLOCK_MINUTES


func get_clock_text() -> String:
	return time_service.get_clock_text() if time_service != null else "00:00"


func set_master_seed(value: int) -> void:
	if rng_service != null:
		rng_service.set_seed(value)


func get_master_seed() -> int:
	return rng_service.master_seed if rng_service != null else DEFAULT_MASTER_SEED


## 读取存档中的时钟。优先读整数 tick，旧格式回退到浮点分钟后再取整。
func _read_clock_ticks(data: Dictionary) -> int:
	if data.has("game_clock_ticks"):
		return maxi(int(data.get("game_clock_ticks", 0)), 0)
	if data.has("game_clock_minutes"):
		return maxi(int(data.get("game_clock_minutes", START_CLOCK_MINUTES)) - START_CLOCK_MINUTES, 0)
	return 0


## 世界已经发生过变化的次数，用于 UI 或测试判定。
func get_world_change_count() -> int:
	if not is_ready:
		return 0
	return world_manager.get_change_count()
