## PartyHouseTest — 聚会房屋灰盒验证
##
## 用法：
##   godot --headless --script res://tests/party_house_test.gd
##
## 阶段约定（重要）：
##   每个 step 的 _t_state 一律从 0 开始，由 _process 在步骤完成后统一归零。
##   不使用跨步骤的链式编号——那样一旦某步改了 _t_state，后面的步骤会被整段跳过，
##   表现为「测的根本不是目标地点」这种极难发现的假结果。

extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []

var _services: Node = null
var _main: Node = null
var _rig: PlayerController = null
var _camera: Camera3D = null
var _scene_mgr: SceneManager = null
var _world_mgr: WorldManager = null
var _interaction: InteractionManager = null

var _steps: Array = []
var _idx: int = 0
var _ticks: int = 0
var _t_state: int = 0
var _pf_start: int = 0
var _pf_needed: int = 0


func _initialize() -> void:
	print("=== COMET party house test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))
	_build_steps()


func _build_steps() -> void:
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_p01_scene_loaded"),
		Callable(self, "step_p02_spawn_clear"),
		Callable(self, "step_p03_stand"),
		Callable(self, "step_p04_walk_into_rooms"),
		Callable(self, "step_p05_walk_sideways"),
		Callable(self, "step_p06_wall_blocks"),
		Callable(self, "step_p07_hotspots"),
		Callable(self, "step_p07b_raycast"),
		Callable(self, "step_p08_lighting_variants"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	if bool(_steps[_idx].call()):
		_idx += 1
		_ticks = 0
		_pf_needed = 0
		_t_state = 0
	else:
		_ticks += 1
		if _ticks > 900:
			_record(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
			_pf_needed = 0
			_t_state = 0
	return false


func _record(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		_results.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_results.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


func _check(c: bool, label: String, detail: String = "") -> void:
	_record(c, label, detail)


func _wait_pf(n: int) -> bool:
	if _pf_needed == 0:
		_pf_start = Engine.get_physics_frames()
		_pf_needed = n
	if Engine.get_physics_frames() - _pf_start < _pf_needed:
		return false
	_pf_needed = 0
	return true


func _release_moves() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _party_instance() -> Node:
	if _scene_mgr == null:
		return null
	return _scene_mgr.get_current_instance()


# ------------------------------------------------------------------ setup

func step_setup() -> bool:
	if _t_state == 0:
		if Engine.get_physics_frames() < 3:
			return false
		_services = root.get_node_or_null("GameServices")
		if _services == null:
			_check(false, "setup. GameServices 可用")
			return true
		if _services.is_ready and _services.save_manager != null:
			_services.save_manager.delete_save()

		var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
		if packed == null:
			_check(false, "setup. 主场景可加载")
			return true
		_main = packed.instantiate()
		root.add_child(_main)
		_t_state = 1
		return false

	if not _wait_pf(8):
		return false

	_rig = _services.player_controller as PlayerController
	_camera = _rig.get_camera() if _rig != null else null
	_scene_mgr = _services.scene_manager
	_world_mgr = _services.world_manager
	_interaction = _services.interaction_manager
	_check(_rig != null and _camera != null, "setup. 玩家与相机已装配")
	return true


# ------------------------------------------------------------------ P01

func step_p01_scene_loaded() -> bool:
	if _t_state == 0:
		var ok: bool = _scene_mgr.enter_location("party_house", false)
		_check(ok, "P01 可进入聚会房屋")
		_check(_scene_mgr.get_current_location_id() == "party_house",
				"P01 当前地点为聚会房屋",
				"current=%s" % _scene_mgr.get_current_location_id())
		_t_state = 1
		return false

	if not _wait_pf(6):
		return false

	var inst: Node = _party_instance()
	if inst == null:
		_check(false, "P01 场景实例存在")
		return true

	var bodies := 0
	var hotspot_count := 0
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is StaticBody3D:
			bodies += 1
		elif n is Hotspot:
			hotspot_count += 1
		for c in n.get_children():
			stack.append(c)

	_check(bodies >= 40, "P01 场景包含足量静态碰撞体（墙体与家具）",
			"StaticBody3D=%d" % bodies)
	_check(hotspot_count >= 6, "P01 场景包含热点", "热点=%d" % hotspot_count)
	return true


# ------------------------------------------------------------------ P02

func step_p02_spawn_clear() -> bool:
	if _t_state == 0:
		var spawn: Vector3 = _scene_mgr.get_location_spawn("party_house")
		_rig.reset_to_spawn(spawn)
		_rig.velocity = Vector3.ZERO
		_rig.reset_view()
		_t_state = 1
		return false

	if not _wait_pf(10):
		return false

	var space: PhysicsDirectSpaceState3D = _rig.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.72
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	# 排除玩家自身：玩家胶囊也在 layer 1，不排除的话查询必然命中自己。
	q.exclude = [_rig.get_rid()]
	# 抬高 2cm 再检测：玩家站在地板上时胶囊底部必然与地板表面接触，
	# 直接检测会把"正常站立"误判为"重叠"。本断言要查的是有没有嵌进墙或家具。
	q.transform = Transform3D(Basis.IDENTITY, _rig.global_position + Vector3(0, 0.86 + 0.02, 0))
	var hits := space.intersect_shape(q, 8)
	var hit_names: Array = []
	for h in hits:
		var col: Variant = h.get("collider")
		if col != null:
			hit_names.append(str((col as Node).name))
	_check(hits.is_empty(), "P02 出生点未嵌入墙体或家具",
			"重叠数=%d 对象=%s 位置=%s" % [hits.size(), str(hit_names), str(_rig.global_position)])
	return true


# ------------------------------------------------------------------ P03

func step_p03_stand() -> bool:
	if _t_state == 0:
		_t_state = 1
		return false
	if not _wait_pf(20):
		return false
	_check(_rig.is_on_floor(), "P03 玩家能站在房屋地板上",
			"is_on_floor=%s y=%.3f" % [str(_rig.is_on_floor()), _rig.global_position.y])
	_check(absf(_rig.global_position.y) < 0.15, "P03 玩家高度正常（未陷入地板）",
			"y=%.3f" % _rig.global_position.y)
	return true


# ------------------------------------------------------------------ P04

func step_p04_walk_into_rooms() -> bool:
	if _t_state == 0:
		_rig.global_position = Vector3(-0.6, 0.05, 3.2)
		_rig.velocity = Vector3.ZERO
		_rig.reset_view()
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if not _wait_pf(70):
		return false
	_release_moves()
	var z: float = _rig.global_position.z
	_check(z < 1.0, "P04 能从走廊走进房间区（穿过开放通道）",
			"z: 3.200 → %.3f" % z)
	return true


# ------------------------------------------------------------------ P05

func step_p05_walk_sideways() -> bool:
	if _t_state == 0:
		_rig.global_position = Vector3(0.0, 0.05, 3.0)
		_rig.velocity = Vector3.ZERO
		_rig.reset_view()
		Input.action_press("move_left")
		_t_state = 1
		return false
	if not _wait_pf(60):
		return false
	_release_moves()
	var x: float = _rig.global_position.x
	_check(x < -3.5, "P05 沿走廊横向移动到西侧（可通行）", "x: 0.000 → %.3f" % x)
	return true


# ------------------------------------------------------------------ P06

func step_p06_wall_blocks() -> bool:
	if _t_state == 0:
		_rig.global_position = Vector3(0.0, 0.05, 2.0)
		_rig.velocity = Vector3.ZERO
		_rig.reset_view()
		Input.action_press("move_right")
		_t_state = 1
		return false
	if not _wait_pf(90):
		return false
	_release_moves()
	var x: float = _rig.global_position.x
	_check(x < 6.2, "P06 向东移动未穿出外墙", "最终 x=%.3f（外墙内表面 6.4）" % x)
	_check(x > 1.0, "P06 确实向东移动了一段距离", "x=%.3f" % x)
	return true


# ------------------------------------------------------------------ P07

func step_p07_hotspots() -> bool:
	if _t_state == 0:
		_rig.global_position = Vector3(0.0, 0.05, 3.2)
		_rig.velocity = Vector3.ZERO
		_t_state = 1
		return false
	if not _wait_pf(4):
		return false

	var inst: Node = _party_instance()
	var names: Array = []
	for s in (inst as GameLocation).collect_hotspots():
		var sp := s as Hotspot
		if sp.is_interactable():
			names.append(sp.name)

	_check(names.size() >= 6, "P07 可交互热点数量符合预期",
			"%d 个: %s" % [names.size(), str(names)])
	_check(names.has("ExitToExterior"), "P07 前门出口热点存在")
	_check(names.has("DoorToNowhere"), "P07 打不开的门热点存在")
	_check(names.has("BasementDoor"), "P07 地下室门热点存在")
	_check(names.has("Laptop"), "P07 笔记本电脑热点存在")
	return true


func step_p07b_raycast() -> bool:
	if _t_state == 0:
		var inst: Node = _party_instance()
		var target: Hotspot = null
		for s in (inst as GameLocation).collect_hotspots():
			var sp := s as Hotspot
			if sp.name == "Laptop" and sp.is_interactable():
				target = sp
				break
		if target == null:
			_check(false, "P07b 未找到笔记本电脑热点")
			return true

		_rig.global_position = Vector3(-4.0, 0.05, 1.6)
		_rig.velocity = Vector3.ZERO
		_rig.capture_mouse()
		var dir: Vector3 = (target.global_position - _camera.global_position).normalized()
		_rig.yaw = atan2(-dir.x, -dir.z)
		_rig.pitch = -asin(clampf(dir.y, -1.0, 1.0))
		_rig._apply_rotation()
		_t_state = 1
		return false

	if _t_state == 1:
		if not _wait_pf(5):
			return false
		var focused: Hotspot = _interaction.get_focused()
		_check(focused != null and focused.name == "Laptop", "P07b 射向笔记本时正确聚焦",
				"focused=%s" % (focused.name if focused != null else "null"))
		return true
	return true


# ------------------------------------------------------------------ P08

func step_p08_lighting_variants() -> bool:
	if _t_state == 0:
		if not _wait_pf(2):
			return false
		var inst: Node = _party_instance()
		var lamp: Node = inst.find_child("LampLiving", true, false)
		var candle: Node = inst.find_child("CandleNorth", true, false)
		_check(lamp != null, "P08 有电变体含客厅灯", str(lamp != null))
		_check(candle != null, "P08 停电变体含蜡烛", str(candle != null))

		var world_id: String = _world_mgr.get_current_world_id()
		if lamp != null:
			var vis: bool = (lamp as Node3D).is_visible_in_tree()
			_check(vis == (world_id == "world_alpha"), "P08 客厅灯可见性随世界变化",
					"world=%s lamp_visible=%s" % [world_id, str(vis)])
		if candle != null:
			var vis2: bool = (candle as Node3D).is_visible_in_tree()
			_check(vis2 == (world_id == "world_beta"), "P08 蜡烛仅在停电世界可见",
					"world=%s candle_visible=%s" % [world_id, str(vis2)])

		var va: Node = inst.find_child("Variant_world_alpha", true, false)
		var vb: Node = inst.find_child("Variant_world_beta", true, false)
		var na := 0
		var nb := 0
		if va != null:
			for c in va.get_children():
				if c is Light3D:
					na += 1
		if vb != null:
			for c in vb.get_children():
				if c is Light3D:
					nb += 1
		_check(na >= 5 and nb >= 3, "P08 两套灯光相互独立",
				"有电 %d 盏 / 停电 %d 盏" % [na, nb])
		_t_state = 1
	return true


func step_report() -> bool:
	print("")
	for line in _results:
		print(line)
	print("")
	print("=== PARTY HOUSE RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true
