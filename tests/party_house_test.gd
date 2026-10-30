## PartyHouseTest — 聚会住宅灰盒验证（13.4 × 9.4 布局）
##
## 用法：
##   godot --headless --script res://tests/party_house_test.gd
##
## 对应 docs/MAP_REVIEW_ROUND3.md 的坐标表。
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
var _scene_mgr: SceneManager = null
var _world_mgr: WorldManager = null

var _steps: Array = []
var _idx: int = 0
var _ticks: int = 0
var _t_state: int = 0
var _pf_start: int = 0
var _pf_needed: int = 0
# 超时用物理帧计时，而不是渲染帧：headless 不限帧率，渲染帧可能在 0.1 秒内
# 就累积几百，用它判超时会把正常步骤误杀（实测踩过）。
var _tick_pf: int = 0

const FLOOR_Y := 0.20
const SPAWN := Vector3(0.0, 0.25, 1.60)


func _initialize() -> void:
	print("=== COMET party house test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))
	_build_steps()


func _build_steps() -> void:
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_p01_spawn"),
		Callable(self, "step_p02_not_embedded"),
		Callable(self, "step_p03_on_floor"),
		Callable(self, "step_p04_connectivity"),
		Callable(self, "step_p05_hotspots"),
		Callable(self, "step_p06_walls"),
		Callable(self, "step_p07_furniture"),
		Callable(self, "step_p08_lighting"),
		Callable(self, "step_p09_variants"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_t_state = 0
		_pf_needed = 0
		_ticks = 0
		_tick_pf = 0
	else:
		_ticks += 1
		if _tick_pf == 0:
			_tick_pf = Engine.get_physics_frames()
		elif Engine.get_physics_frames() - _tick_pf > 300:
			_record(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_t_state = 0
			_ticks = 0
			_tick_pf = 0
	return false


func _record(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		_results.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_results.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


func _check(cond: bool, label: String, detail: String = "") -> void:
	_record(cond, label, detail)


func _wait_physics(n: int) -> bool:
	if _pf_needed == 0:
		_pf_needed = n
		_pf_start = Engine.get_physics_frames()
		return false
	return Engine.get_physics_frames() - _pf_start >= _pf_needed


func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _find(n: Node, target: String) -> Node:
	for c in _walk(n):
		if str(c.name) == target:
			return c
	return null


func step_setup() -> bool:
	if _pf_needed == 0 and _services == null:
		if Engine.get_physics_frames() < 3:
			return false
		_services = root.get_node_or_null("GameServices")
		if _services == null:
			_record(false, "setup. GameServices 可用")
			return true
		if _services.is_ready and _services.save_manager != null:
			_services.save_manager.delete_save()
		var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
		if packed == null:
			_record(false, "setup. 主场景可加载")
			return true
		_main = packed.instantiate()
		root.add_child(_main)
		return false

	if not _wait_physics(6):
		return false

	_rig = _services.player_controller as PlayerController
	_scene_mgr = _services.scene_manager
	_world_mgr = _services.world_manager

	_check(_rig != null, "setup. 玩家为 PlayerController")
	_check(_scene_mgr != null, "setup. SceneManager 可用")
	_check(_world_mgr != null, "setup. WorldManager 可用")

	var ok: bool = _scene_mgr.enter_location("party_house", false)
	_check(ok, "setup. 可进入聚会房屋")
	return true


func step_p01_spawn() -> bool:
	if not _wait_physics(4):
		return false
	var p: Vector3 = _rig.global_position
	var d: float = p.distance_to(SPAWN)
	_check(d < 0.10, "P01 出生点在玄关设计位置",
			"pos=%s 期望=%s 偏差=%.3f" % [str(p), str(SPAWN), d])
	_check(_scene_mgr.get_current_location_id() == "party_house",
			"P01 当前地点为 party_house", str(_scene_mgr.get_current_location_id()))
	return true


func step_p02_not_embedded() -> bool:
	var inst: Node = _scene_mgr.get_current_instance()
	var space: PhysicsDirectSpaceState3D = (inst as Node3D).get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.66
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, _rig.global_position + Vector3(0, 0.86 + 0.06, 0))
	q.collision_mask = 1
	q.exclude = [_rig.get_rid()]
	var hits: Array = space.intersect_shape(q, 8)
	var names: Array = []
	for h in hits:
		var c = h.get("collider")
		if c != null:
			names.append(str(c.name))
	_check(hits.is_empty(), "P02 出生点未嵌入墙体或家具", "重叠=%s" % str(names))
	return true


func step_p03_on_floor() -> bool:
	if _t_state == 0:
		if not _wait_physics(20):
			return false
		_t_state = 1
		return false
	var y: float = _rig.global_position.y
	_check(_rig.is_on_floor(), "P03 玩家站在地板上")
	_check(absf(y - FLOOR_Y) < 0.08, "P03 玩家高度与室内地面一致",
			"y=%.3f 期望=%.2f" % [y, FLOOR_Y])
	_check(_rig.velocity.y > -0.2, "P03 垂直速度已稳定", "vy=%.3f" % _rig.velocity.y)
	return true


func step_p04_connectivity() -> bool:
	var inst: Node = _scene_mgr.get_current_instance()
	var space: PhysicsDirectSpaceState3D = (inst as Node3D).get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.66

	var routes := [
		["玄关→主空间", [Vector3(0, 1.10, 1.6), Vector3(0, 1.10, 4.3)]],
		["主空间→书房", [Vector3(0, 1.10, 4.3), Vector3(-4.2, 1.10, 4.4), Vector3(-4.2, 1.10, 2.0)]],
		["主空间→厨房南段", [Vector3(0, 1.10, 4.22), Vector3(4.10, 1.10, 4.30), Vector3(4.10, 1.10, 2.00)]],
		["玄关→卫生间", [Vector3(1.1, 1.10, 1.2), Vector3(-0.1, 1.10, 2.4), Vector3(-1.8, 1.10, 3.0)]],
		["玄关→前门外", [Vector3(0, 1.10, 1.6), Vector3(0, 1.10, -0.8)]],
		["侧通道→侧门外", [Vector3(2.4, 1.10, 2.0), Vector3(7.2, 1.10, 2.0)]],
		["客厅→露台", [Vector3(-4.0, 1.10, 8.0), Vector3(-4.0, 1.10, 10.2)]],
	]

	for r in routes:
		var label: String = r[0]
		var pts: Array = r[1]
		var blocked := 0
		var first := ""
		for i in range(pts.size() - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var steps := int(a.distance_to(b) / 0.15)
			for s in range(steps + 1):
				var p := a.lerp(b, float(s) / float(max(steps, 1)))
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = shape
				q.transform = Transform3D(Basis.IDENTITY, p)
				q.collision_mask = 1
				q.exclude = [_rig.get_rid()]
				if not space.intersect_shape(q, 4).is_empty():
					blocked += 1
					if first == "":
						first = "%.2f,%.2f" % [p.x, p.z]
		_check(blocked == 0, "P04 %s 可通行" % label,
				"受阻 %d 处，首处 %s" % [blocked, first])
	return true


func step_p05_hotspots() -> bool:
	var inst: Node = _scene_mgr.get_current_instance()
	var ids: Array = []
	for c in _walk(inst):
		if c is Hotspot:
			ids.append(str(c.name))

	var required := ["FrontDoor", "SideDoor", "PatioDoor",
			"DiningTableSpot", "FireplaceSpot", "KitchenCounter", "StudyDesk"]
	for r in required:
		_check(ids.has(r), "P05 热点 %s 存在" % r, str(ids))

	var front: Node = _find(inst, "FrontDoor")
	if front != null:
		_check(str(front.target_location) == "house_exterior",
				"P05 前门指向室外场景", str(front.target_location))
	var side: Node = _find(inst, "SideDoor")
	if side != null:
		_check(str(side.target_location) == "house_exterior",
				"P05 侧门指向室外场景", str(side.target_location))
	_check(ids.size() >= 7, "P05 热点数量不少于 7", "count=%d" % ids.size())
	return true


func step_p06_walls() -> bool:
	if _t_state == 0:
		# 起点必须避开所有家具：(-2.5, 8.5) 在客厅东北空地，
		# 西行路径上只有西外墙。原先用 (-4.0, 6.0) 会撞在咖啡桌边角上，
		# 玩家被 move_and_slide 沿桌边推向东侧，看起来像「没往西走」。
		_rig.reset_to_spawn(Vector3(-2.5, FLOOR_Y + 0.05, 8.5))
		_rig.yaw = deg_to_rad(90.0)
		_rig.pitch = 0.0
		_rig._apply_rotation()
		Input.action_press("move_forward")
		_t_state = 1
		return false

	if not _wait_physics(90):
		return false
	Input.action_release("move_forward")
	var x: float = _rig.global_position.x
	_check(x < -5.0, "P06 向西确实移动到了墙边", "x=%.3f" % x)
	_check(x > -6.30, "P06 向西未穿出外墙", "x=%.3f（内表面 -6.50，半径 0.32）" % x)
	return true


func step_p07_furniture() -> bool:
	var inst: Node = _scene_mgr.get_current_instance()
	var wanted := ["Sofa3", "CoffeeTable", "TVCabinet", "DiningTable",
			"ChairW0", "ChairE2", "ChairN", "ChairS",
			"CounterNorth", "CounterEast", "Fridge", "Island",
			"Desk", "Bookshelf", "Fireplace"]
	for w in wanted:
		_check(_find(inst, w) != null, "P07 家具 %s 已生成" % w)

	_check(_find(inst, "Armchair") == null, "P07 单人椅已按第三轮修正 1 取消")
	return true


func step_p08_lighting() -> bool:
	var inst: Node = _scene_mgr.get_current_instance()
	var va: Node = _find(inst, "Variant_world_alpha")
	var vb: Node = _find(inst, "Variant_world_beta")
	_check(va != null, "P08 存在 alpha 变体节点")
	_check(vb != null, "P08 存在 beta 变体节点")

	var la := 0
	var lb := 0
	if va != null:
		for c in _walk(va):
			if c is OmniLight3D:
				la += 1
	if vb != null:
		for c in _walk(vb):
			if c is OmniLight3D:
				lb += 1

	_check(la >= 4, "P08 有电变体含 4 盏以上灯", "alpha=%d" % la)
	_check(lb >= 1, "P08 停电变体含蜡烛", "beta=%d" % lb)
	_check(_find(inst, "Candle") != null, "P08 蜡烛节点存在")
	_check(la != lb, "P08 两套灯光相互独立", "有电 %d 盏 / 停电 %d 盏" % [la, lb])
	return true


func step_p09_variants() -> bool:
	var inst: Node = _scene_mgr.get_current_instance()
	var va: Node = _find(inst, "Variant_world_alpha")
	var vb: Node = _find(inst, "Variant_world_beta")
	_check(va != null and vb != null, "P09 两个世界变体节点齐备")

	var shared: Node = _find(inst, "Shared")
	_check(shared != null, "P09 存在 Shared 共享节点")
	if shared != null:
		var has_wall := false
		for c in _walk(shared):
			if str(c.name).begins_with("Wall"):
				has_wall = true
				break
		_check(has_wall, "P09 墙体位于 Shared 中（不随现实消失）")
	return true


func step_report() -> bool:
	print("")
	for line in _results:
		print(line)
	print("")
	print("=== PARTY HOUSE RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true
