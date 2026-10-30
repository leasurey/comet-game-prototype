## AcceptanceTest — COMET 第一阶段验收测试
##
## 用法：
##   godot --headless --script res://tests/acceptance_test.gd
##
## 设计原则：
##   1. 全部断言都基于实际实例化的场景与真实状态，不用静态检查或口头声明冒充测试。
##   2. 每个步骤在独立帧上执行，避免依赖同帧初始化顺序；射线检测需要额外帧才稳定。
##   3. 结果区分 PASS / FAIL，FAIL 必须携带具体数值以便定位。
##
## 覆盖范围对应任务书第十节的 10 条验收项。

extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []

# ---------------- 运行时对象
var _container: Node3D = null
var _rig: PlayerController = null
var _camera: Camera3D = null
var _interaction: InteractionManager = null
var _scene_mgr: SceneManager = null
var _world_mgr: WorldManager = null
var _event_mgr: EventManager = null
var _save_mgr: SaveManager = null
var _temp_root: Node3D = null

# ---------------- 状态机
var _steps: Array = []
var _step_index: int = 0
var _step_ticks: int = 0
var _reporting: bool = false

# ---------------- 测试中途数据
var _snapshot_visible: Array = []
var _aim_target: Hotspot = null
var _aim_ticks: int = 0
var _hotspot_scan_done: bool = false
var _saved_path: String = ""


func _initialize() -> void:
	print("=== COMET acceptance test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))
	_build_steps()


func _build_steps() -> void:
	_steps = [
		Callable(self, "step_setup"),

		# 验收 1：能够正常启动
		Callable(self, "step_01_bootstrap"),

		# 验收 2：客厅可以观察四周
		Callable(self, "step_02_look_around"),

		# 验收 3：进入房屋外部
		Callable(self, "step_03_to_exterior"),

		# 验收 4 + 5：进入黑暗区域并触发世界变化
		Callable(self, "step_04_to_dark_road"),

		# 验收 6：沿原路返回
		Callable(self, "step_05_return_back"),

		# 验收 7：返回同一地点后至少三处环境差异
		Callable(self, "step_06_world_differences"),

		# 验收 8：连续往返不导致状态异常
		Callable(self, "step_07_round_trip"),

		# 验收 10：热点可发现、可聚焦
		Callable(self, "step_08_hotspot_raycast"),

		# 验收 9：存档 -> 模拟重启 -> 读档
		Callable(self, "step_09_save"),
		Callable(self, "step_10_load"),

		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _step_index >= _steps.size():
		return true
	var fn: Callable = _steps[_step_index]
	var done: bool = bool(fn.call())
	if done:
		_step_index += 1
		_step_ticks = 0
	else:
		_step_ticks += 1
		if _step_ticks > 60:
			_record(false, "步骤超时", "step index=%d" % _step_index)
			_step_index += 1
			_step_ticks = 0
	return false


# ------------------------------------------------------------------ 断言工具

func _record(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		_results.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_results.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


func _check(condition: bool, label: String, detail: String = "") -> void:
	_record(condition, label, detail)


# ------------------------------------------------------------------ 场景装配

func step_setup() -> bool:
	_container = Node3D.new()
	_container.name = "TestLocationContainer"
	root.add_child(_container)

	_temp_root = Node3D.new()
	_temp_root.name = "TempRoot"
	root.add_child(_temp_root)

	var script_player := load("res://core/player_controller.gd") as Script
	_rig = script_player.new() as PlayerController
	_rig.name = "CameraRig"
	root.add_child(_rig)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_rig.add_child(_camera)
	_rig.position = Vector3(0, 1.62, 0)

	var script_interaction := load("res://core/interaction_manager.gd") as Script
	_interaction = script_interaction.new() as InteractionManager
	_interaction.name = "InteractionManager"
	root.add_child(_interaction)
	_interaction.set_camera(_camera)

	var script_scene := load("res://core/scene_manager.gd") as Script
	_scene_mgr = script_scene.new() as SceneManager
	_scene_mgr.name = "SceneManager"
	root.add_child(_scene_mgr)
	_scene_mgr.set_container(_container)

	var script_world := load("res://core/world_manager.gd") as Script
	var script_event := load("res://core/event_manager.gd") as Script
	var script_save := load("res://core/save_manager.gd") as Script
	_world_mgr = script_world.new() as WorldManager
	_event_mgr = script_event.new() as EventManager
	_save_mgr = script_save.new() as SaveManager

	_scene_mgr.world_manager = _world_mgr
	_scene_mgr.event_manager = _event_mgr
	_scene_mgr.interaction_manager = _interaction
	return true


func _load_data() -> void:
	var loader := DataLoader.new()
	var worlds: Dictionary = loader.load_dictionary("res://data/worlds.json")
	var events: Dictionary = loader.load_dictionary("res://data/events.json")
	var transitions: Dictionary = loader.load_dictionary("res://data/world_transitions.json")
	var locations: Dictionary = loader.load_dictionary("res://data/locations.json")

	var errs: Array = []
	_world_mgr.load_from_data(worlds.get("data", {}), errs)
	_event_mgr.load_from_data(events.get("data", {}), transitions.get("data", {}), errs)
	_scene_mgr.load_from_data(locations.get("data", {}), errs)


func step_01_bootstrap() -> bool:
	_load_data()

	_check(_world_mgr.is_ready(), "1. WorldManager 初始化",
			"current=%s" % _world_mgr.get_current_world_id())
	_check(_event_mgr.is_ready(), "1. EventManager 初始化")
	_check(_scene_mgr.get_location_ids().size() == 3, "1. 地点表载入三个地点",
			str(_scene_mgr.get_location_ids()))

	_save_mgr.delete_save()
	var entered: bool = _scene_mgr.enter_location(_scene_mgr.get_start_location_id(), false)
	_check(entered, "1. 可进入起始地点", "start=%s" % _scene_mgr.get_start_location_id())
	_check(_scene_mgr.get_current_location_id() == "living_room", "1. 起始地点为客厅",
			"current=%s" % _scene_mgr.get_current_location_id())

	var main_res := load("res://scenes/main.tscn")
	var main_packed: PackedScene = main_res as PackedScene
	_check(main_packed != null, "1. 主场景可加载")

	if main_packed != null:
		var instance: Node = main_packed.instantiate()
		var found_container := instance.find_child("LocationContainer", true, false)
		var found_rig := instance.find_child("CameraRig", true, false)
		var found_hud := instance.find_child("HUD", true, false)
		_check(found_container != null and found_rig != null and found_hud != null,
				"1. 主场景节点结构完整",
				"container=%s rig=%s hud=%s" % [
					found_container != null, found_rig != null, found_hud != null])
		instance.free()
	else:
		_check(false, "1. 主场景可实例化")
	return true


func step_02_look_around() -> bool:
	var inst: Node = _scene_mgr.get_current_instance()
	_check(inst != null, "2. 客厅实例存在")

	var spots: Array = (inst as GameLocation).collect_hotspots()
	_check(spots.size() >= 2, "2. 客厅存在可交互内容", "count=%d" % spots.size())
	_check(_camera.is_inside_tree(), "2. 第一人称相机在场景中")

	# 视角控制已由「按住左键拖动」升级为「鼠标捕获后直接移动」。
	# 断言强度不变：仍然验证 yaw/pitch 确实变化、且 pitch 不越过 ±75°。
	_rig.capture_mouse()
	_check(_rig.is_mouse_captured(), "2. 鼠标捕获已启用")

	var yaw_before: float = _rig.yaw
	var pitch_before: float = _rig.pitch

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(220.0, -60.0)
	_rig._input(motion)

	_check(absf(_rig.yaw - yaw_before) > 0.0001, "2. 水平视角可改变",
			"delta=%.4f rad" % (_rig.yaw - yaw_before))
	_check(absf(_rig.pitch - pitch_before) > 0.0001, "2. 垂直视角可改变",
			"delta=%.4f rad (%.2f deg)" % [
				_rig.pitch - pitch_before, _rig.get_pitch_degrees()])

	# 垂直视角限位：灌入极大位移，验证不会翻转
	for _i in 40:
		var m1 := InputEventMouseMotion.new()
		m1.relative = Vector2(0.0, -600.0)
		_rig._input(m1)
		var m2 := InputEventMouseMotion.new()
		m2.relative = Vector2(0.0, 600.0)
		_rig._input(m2)
	var pitch_deg: float = _rig.get_pitch_degrees()
	var pitch_ok: bool = pitch_deg <= 75.001 and pitch_deg >= -75.001
	_check(pitch_ok, "2. 垂直视角受限不翻转", "pitch=%.3f deg (限制 ±75)" % pitch_deg)

	_rig.reset_view()
	return true


func step_03_to_exterior() -> bool:
	var before_world: String = _world_mgr.get_current_world_id()
	var ok: bool = _scene_mgr.enter_location("house_exterior", true)
	_check(ok, "3. 可从客厅进入房屋外部")
	_check(_scene_mgr.get_current_location_id() == "house_exterior", "3. 当前地点为房屋外部",
			"current=%s" % _scene_mgr.get_current_location_id())
	_check(_world_mgr.get_current_world_id() == before_world,
			"3. 仅切换地点不改变世界", "world=%s" % _world_mgr.get_current_world_id())

	var inst: Node = _scene_mgr.get_current_instance()
	var spots: Array = (inst as GameLocation).collect_hotspots()
	var interactable: Array = []
	for s in spots:
		var spot := s as Hotspot
		if spot.is_interactable():
			interactable.append(spot.name)
	_check(interactable.size() >= 3, "3. 房屋外部热点可用", str(interactable))
	return true


func step_04_to_dark_road() -> bool:
	var before_world: String = _world_mgr.get_current_world_id()
	var change_before: int = _world_mgr.get_change_count()

	var ok: bool = _scene_mgr.enter_location("dark_road", true)
	_check(ok, "4. 可进入黑暗区域")
	_check(_scene_mgr.get_current_location_id() == "dark_road", "4. 当前地点为黑暗区域")

	var after_world: String = _world_mgr.get_current_world_id()
	_check(after_world != before_world, "5. 进入黑暗区域后世界发生变化",
			"%s -> %s" % [before_world, after_world])
	_check(after_world == "world_beta", "5. 世界按预设规则切到 world_beta", "got=%s" % after_world)
	_check(_world_mgr.get_change_count() == change_before + 1, "5. 世界变化被记录一次",
			"change_count=%d" % _world_mgr.get_change_count())
	_check(_event_mgr.has_occurred("evt_cross_dark_road"), "5. 对应事件写入历史")

	var inst: Node = _scene_mgr.get_current_instance()
	_check((inst as GameLocation).get_applied_world_id() == after_world,
			"5. 当前场景已按新世界重刷",
			"applied=%s" % (inst as GameLocation).get_applied_world_id())
	return true


func step_05_return_back() -> bool:
	var ok: bool = _scene_mgr.go_back()
	_check(ok, "6. 可沿原路返回")
	_check(_scene_mgr.get_current_location_id() == "house_exterior", "6. 返回到房屋外部",
			"current=%s" % _scene_mgr.get_current_location_id())
	_check(_world_mgr.get_current_world_id() == "world_beta", "6. 返回后仍处于新世界",
			"world=%s" % _world_mgr.get_current_world_id())

	var inst: Node = _scene_mgr.get_current_instance()
	_check((inst as GameLocation).get_applied_world_id() == "world_beta",
			"6. 返回后场景按新世界呈现",
			"applied=%s" % (inst as GameLocation).get_applied_world_id())
	return true


# -------------------------------------------------- 差异快照对比

## 查找当前真正可见的同名节点。
## 两个 variant 里存在同名子节点，直接用 find_child 只会拿到第一个（可能在隐藏分支里），
## 导致差异检测失真，因此必须按可见性筛选。
func _find_visible_node(from: Node, target_name: String) -> Node:
	var found: Node = null
	if from.name == target_name and from.is_visible_in_tree():
		return from
	for child in from.get_children():
		found = _find_visible_node(child, target_name)
		if found != null:
			return found
	return null


func _snapshot(world_id: String) -> Dictionary:
	var packed_res := load("res://scenes/locations/house_exterior.tscn")
	var packed: PackedScene = packed_res as PackedScene
	var inst: GameLocation = packed.instantiate() as GameLocation
	_temp_root.add_child(inst)
	inst.apply_world(world_id)

	var env: Node = inst.get_environment_root()
	var visible_variants: Array = []
	if env != null:
		for child in env.get_children():
			if child.visible:
				visible_variants.append(str(child.name))

	var hotspots: Array = []
	for s in inst.collect_hotspots():
		var spot := s as Hotspot
		if spot.is_interactable():
			hotspots.append(spot.name)

	var porch_energy := -1.0
	var porch_visible := false
	var found_light := _find_visible_node(inst, "PorchLight")
	if found_light is OmniLight3D:
		var omni := found_light as OmniLight3D
		porch_energy = omni.light_energy
		porch_visible = omni.is_visible_in_tree()

	var sign_rotation := -999.0
	var number_node := _find_visible_node(inst, "HouseNumber")
	if number_node != null:
		sign_rotation = rad_to_deg(number_node.rotation.z)

	var window_emissive := false
	var pane := _find_visible_node(inst, "WindowPaneL")
	if pane is MeshInstance3D:
		var m: Material = (pane as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			window_emissive = (m as StandardMaterial3D).emission_enabled

	var crate_pos := Vector3.ZERO
	for s in inst.collect_hotspots():
		var sp := s as Hotspot
		if sp.is_interactable() and sp.display_name == "一只木箱":
			crate_pos = sp.global_position
			break

	inst.free()
	return {
		"variants": visible_variants,
		"hotspots": hotspots,
		"porch_energy": porch_energy,
		"porch_visible": porch_visible,
		"sign_rotation": sign_rotation,
		"window_emissive": window_emissive,
		"crate_pos": crate_pos,
	}


func step_06_world_differences() -> bool:
	var a: Dictionary = _snapshot("world_alpha")
	var b: Dictionary = _snapshot("world_beta")

	var differences: Array = []

	if str(a["variants"]) != str(b["variants"]):
		differences.append("环境变体 %s -> %s" % [str(a["variants"]), str(b["variants"])])

	if str(a["hotspots"]) != str(b["hotspots"]):
		differences.append("可用热点 %s -> %s" % [str(a["hotspots"]), str(b["hotspots"])])

	var pa: Vector3 = a["crate_pos"]
	var pbv: Vector3 = b["crate_pos"]
	if pa.distance_to(pbv) > 0.5:
		differences.append("木箱位置 (%.2f,%.2f) -> (%.2f,%.2f)" % [pa.x, pa.z, pbv.x, pbv.z])

	if bool(a["porch_visible"]) != bool(b["porch_visible"]) or absf(float(a["porch_energy"]) - float(b["porch_energy"])) > 0.01:
		differences.append("门廊灯 visible=%s energy=%.2f -> visible=%s energy=%.2f" % [
			str(a["porch_visible"]), float(a["porch_energy"]),
			str(b["porch_visible"]), float(b["porch_energy"])])

	if bool(a["window_emissive"]) != bool(b["window_emissive"]):
		differences.append("窗户自发光 %s -> %s" % [str(a["window_emissive"]), str(b["window_emissive"])])

	if absf(float(a["sign_rotation"]) - float(b["sign_rotation"])) > 1.0:
		differences.append("门牌角度 %.1f° -> %.1f°" % [
			float(a["sign_rotation"]), float(b["sign_rotation"])])

	var glass_in_beta: bool = (b["hotspots"] as Array).has("GlassShards")
	var glass_in_alpha: bool = (a["hotspots"] as Array).has("GlassShards")
	if glass_in_beta and not glass_in_alpha:
		differences.append("新增线索 GlassShards")

	_check(differences.size() >= 3, "7. 同一地点存在 >=3 处可观察差异",
			"共 %d 处: %s" % [differences.size(), "; ".join(differences)])
	_check(not glass_in_alpha and glass_in_beta, "7. 新线索初始不存在、穿越后出现",
			"alpha=%s beta=%s" % [str(glass_in_alpha), str(glass_in_beta)])
	return true


func step_07_round_trip() -> bool:
	var world_before: String = _world_mgr.get_current_world_id()
	var change_before: int = _world_mgr.get_change_count()
	var ok_all := true
	var log: Array = []

	for i in 4:
		var to_dark: bool = _scene_mgr.enter_location("dark_road", true)
		var back_ok: bool = _scene_mgr.enter_location("house_exterior", true)
		log.append("round%d(dark=%s,back=%s)" % [i, str(to_dark), str(back_ok)])
		if not to_dark or not back_ok:
			ok_all = false

	_check(ok_all, "8. 连续往返无切换失败", "; ".join(log))
	_check(_world_mgr.get_current_world_id() == world_before, "8. 往返后世界不再变化",
			"world=%s" % _world_mgr.get_current_world_id())
	_check(_world_mgr.get_change_count() == change_before, "8. 世界变化次数稳定",
			"%d -> %d" % [change_before, _world_mgr.get_change_count()])

	var inst: Node = _scene_mgr.get_current_instance()
	_check(inst != null and (inst as GameLocation).get_applied_world_id() == _world_mgr.get_current_world_id(),
			"8. 表现层与逻辑层世界一致",
			"applied=%s" % (inst as GameLocation).get_applied_world_id())
	_check(_scene_mgr.get_visited_locations().size() == 3, "8. 访问记录完整",
			str(_scene_mgr.get_visited_locations()))
	return true


# -------------------------------------------------- 热点射线聚焦

func step_08_hotspot_raycast() -> bool:
	if not _hotspot_scan_done:
		_scene_mgr.enter_location("house_exterior", false)
		var inst: Node = _scene_mgr.get_current_instance()
		var pending: Array = []
		for s in (inst as GameLocation).collect_hotspots():
			var spot := s as Hotspot
			if spot.is_interactable():
				pending.append(spot)
		_snapshot_visible = pending
		_hotspot_scan_done = true
		return false

	if _aim_target == null:
		if _snapshot_visible.is_empty():
			_record(true, "10. 完成全部热点聚焦测试")
			return true
		_aim_target = _snapshot_visible.pop_back() as Hotspot
		# 每次换目标都要重新计时，否则会读到上一个目标遗留的聚焦结果
		_aim_ticks = 0

	_camera.look_at(_aim_target.global_position, Vector3.UP)

	# 射线检测依赖物理帧，需要多等几帧
	_aim_ticks += 1
	if _aim_ticks < 4:
		return false

	var focused: Hotspot = _interaction.get_focused()
	if focused == _aim_target:
		_record(true, "10. 热点可被射线聚焦", _aim_target.name)
	else:
		_record(false, "10. 热点可被射线聚焦",
				"target=%s focused=%s" % [_aim_target.name,
				str(focused.name) if focused != null else "null"])

	_aim_target = null
	return _snapshot_visible.is_empty()


func _build_payload() -> Dictionary:
	return {
		"location_id": _scene_mgr.get_current_location_id(),
		"world_id": _world_mgr.get_current_world_id(),
		"visited_locations": _scene_mgr.get_visited_locations(),
		"world_change_records": _world_mgr.get_change_log(),
		"triggered_events": _event_mgr.get_sequence(),
		"event_history": _event_mgr.get_history(),
		"event_sequence": _event_mgr.get_sequence(),
		"game_clock_minutes": 1420.0,
		"player_view": {"yaw": 0.0, "pitch": 0.0},
	}


func step_09_save() -> bool:
	_scene_mgr.enter_location("house_exterior", false)

	var result: Dictionary = _save_mgr.save(_build_payload())
	var ok: bool = bool(result.get("ok", false))
	_check(ok, "9. 存档写入成功", str(result.get("error", "")))
	_saved_path = str(result.get("path", ""))
	_check(_save_mgr.has_save(), "9. 存档文件确实落盘", _saved_path)

	# 错误处理：损坏存档必须被拒绝而不是崩溃
	var script_save := load("res://core/save_manager.gd") as Script
	var corrupt_mgr: SaveManager = script_save.new() as SaveManager
	corrupt_mgr.set_path(_saved_path)
	var raw := FileAccess.open(_saved_path, FileAccess.WRITE)
	raw.store_string("{ this is not valid json")
	raw.close()
	var bad: Dictionary = corrupt_mgr.load_state(["living_room"], ["world_alpha"])
	_check(not bool(bad.get("ok", false)), "9. 损坏存档被拒绝而非崩溃", str(bad.get("error", "")))

	# 拒绝未知地点的存档
	raw = FileAccess.open(_saved_path, FileAccess.WRITE)
	raw.store_string(JSON.stringify({
		"magic": "COMET_SAVE", "version": 1,
		"location_id": "nowhere", "world_id": "world_alpha",
		"visited_locations": [], "world_change_records": [],
		"triggered_events": [], "game_clock_minutes": 0.0,
	}))
	raw.close()
	var bad2: Dictionary = corrupt_mgr.load_state(["living_room"], ["world_alpha"])
	_check(not bool(bad2.get("ok", false)), "9. 未知地点存档被拒绝", str(bad2.get("error", "")))

	# 复原，供下一步读档使用
	_check(bool(_save_mgr.save(_build_payload()).get("ok", false)), "9. 恢复有效存档")
	return true


func step_10_load() -> bool:
	# 模拟重新启动：整套 Manager 全部重建
	var script_world := load("res://core/world_manager.gd") as Script
	var script_event := load("res://core/event_manager.gd") as Script
	var script_scene := load("res://core/scene_manager.gd") as Script
	var script_save := load("res://core/save_manager.gd") as Script

	var new_world: WorldManager = script_world.new() as WorldManager
	var new_event: EventManager = script_event.new() as EventManager
	var new_scene: SceneManager = script_scene.new() as SceneManager
	var new_save: SaveManager = script_save.new() as SaveManager

	new_scene.name = "SceneManagerReborn"
	root.add_child(new_scene)
	new_scene.set_container(_container)

	var loader := DataLoader.new()
	var worlds: Dictionary = loader.load_dictionary("res://data/worlds.json")
	var events: Dictionary = loader.load_dictionary("res://data/events.json")
	var transitions: Dictionary = loader.load_dictionary("res://data/world_transitions.json")
	var locs: Dictionary = loader.load_dictionary("res://data/locations.json")

	var errs: Array = []
	new_world.load_from_data(worlds.get("data", {}), errs)
	new_event.load_from_data(events.get("data", {}), transitions.get("data", {}), errs)
	new_scene.load_from_data(locs.get("data", {}), errs)

	var result: Dictionary = new_save.load_state(new_scene.get_location_ids(), new_world.get_world_ids())
	_check(bool(result.get("ok", false)), "9. 重新启动后存档可读取", str(result.get("error", "")))
	if not bool(result.get("ok", false)):
		return true

	var data: Dictionary = result.get("data", {})
	var w_err: Array = []
	new_world.restore({
		"current_world_id": str(data.get("world_id", "")),
		"change_log": data.get("world_change_records", []),
	}, w_err)
	var e_err: Array = []
	new_event.restore({
		"history": data.get("event_history", {}),
		"sequence": data.get("event_sequence", []),
	}, e_err)
	var s_err: Array = []
	new_scene.restore({
		"current_location_id": str(data.get("location_id", "")),
		"visited_locations": data.get("visited_locations", []),
		"visit_stack": data.get("visit_stack", []),
	}, s_err)

	new_scene.world_manager = new_world
	new_scene.event_manager = new_event
	new_scene.interaction_manager = _interaction

	var expected_location: String = str(data.get("location_id", ""))
	var expected_world: String = str(data.get("world_id", ""))
	var expected_changes: int = _world_mgr.get_change_count()

	var entered: bool = new_scene.enter_location(expected_location, false)
	_check(entered, "9. 重新启动后可恢复到存档地点")
	_check(new_scene.get_current_location_id() == expected_location, "9. 恢复地点正确",
			"got=%s expect=%s" % [new_scene.get_current_location_id(), expected_location])
	_check(new_world.get_current_world_id() == expected_world, "9. 恢复世界状态正确",
			"got=%s expect=%s" % [new_world.get_current_world_id(), expected_world])
	_check(new_world.get_change_count() == expected_changes, "9. 世界变化历史一致",
			"%d vs %d" % [new_world.get_change_count(), expected_changes])
	_check(new_event.has_occurred("evt_cross_dark_road"), "9. 事件历史被恢复")

	var inst: Node = new_scene.get_current_instance()
	_check((inst as GameLocation).get_applied_world_id() == expected_world,
			"9. 恢复后场景呈现正确世界",
			"applied=%s" % (inst as GameLocation).get_applied_world_id())

	new_save.delete_save()
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for line in _results:
		print(line)
	print("")
	print("=== RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true
