## DoorConnectionTest — 门级落点与交互距离验证
##
## 对应《第一轮系统整合修复任务书》第七节 A / B。
##
## 用法：
##   godot --headless --script res://tests/door_connection_test.gd
##
## 判定要点：
##   从哪扇门出去，就必须落在对应的室外位置、面朝对应方向；
##   从哪扇门回来，就必须回到对应门内侧。
##   而「落在对应位置」不能用地点级 spawn 蒙对——三扇门的目标地点相同，
##   只有门级落点才可能让三者落点不同。

extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []

var _svc: Node = null
var _main: Node = null
var _rig: PlayerController = null
var _sm: SceneManager = null
var _im: InteractionManager = null

var _steps: Array = []
var _idx: int = 0
var _t_state: int = 0
var _tick_pf: int = 0
var _pf_start: int = 0
var _pf_needed: int = 0

# T10 用的临时对象
var _probe_spot: Node = null
var _probe_wall: Node = null


func _initialize() -> void:
	print("=== COMET door connection test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_t01_front_door"),
		Callable(self, "step_t02_side_door"),
		Callable(self, "step_t03_patio_door"),
		Callable(self, "step_t04_back_inside"),
		Callable(self, "step_t05_no_embed"),
		Callable(self, "step_t06_facing"),
		Callable(self, "step_t07_near_focus"),
		Callable(self, "step_t08_far_no_focus"),
		Callable(self, "step_t09_far_no_activate"),
		Callable(self, "step_t10_through_wall"),
		Callable(self, "step_t11_round_trip"),
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
		_tick_pf = 0
	else:
		if _tick_pf == 0:
			_tick_pf = Engine.get_physics_frames()
		elif Engine.get_physics_frames() - _tick_pf > 300:
			_record(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_t_state = 0
			_pf_needed = 0
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


## 通过交互信号路径激活热点：debug_activate() → 信号 → main 分发
## 注意：此处绕过了距离校验（测试需要从任意位置触发门），
## 玩家路径走的是 activate_focused()，那条路含距离与遮挡判据。
func _use(spot: Node) -> bool:
	if spot == null:
		return false
	return _im.debug_activate(spot)



func _dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ------------------------------------------------------------------ setup

func step_setup() -> bool:
	if _pf_needed == 0 and _svc == null:
		if Engine.get_physics_frames() < 3:
			return false
		_svc = root.get_node_or_null("GameServices")
		if _svc == null:
			_record(false, "setup. GameServices 可用")
			return true
		if _svc.is_ready and _svc.save_manager != null:
			# 先切到本测试专用存档路径，绝不动玩家的正式存档（P0 / BUG-002）
			_svc.save_manager.use_test_path("door_connection")
			_svc.save_manager.delete_save()
		var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
		if packed == null:
			_record(false, "setup. 主场景可加载")
			return true
		_main = packed.instantiate()
		root.add_child(_main)
		return false

	if not _wait_physics(6):
		return false

	_rig = _svc.player_controller as PlayerController
	_sm = _svc.scene_manager
	_im = _svc.interaction_manager
	_check(_rig != null and _sm != null and _im != null, "setup. 三个管理器就绪")

	_sm.enter_location("party_house", false)
	_check(_sm.get_current_location_id() == "party_house", "setup. 进入 party_house")
	return true


# ------------------------------------------------------------------ T01 前门

func step_t01_front_door() -> bool:
	if _t_state == 0:
		var inst: Node = _sm.get_current_instance()
		_check(_find(inst, "FrontDoor") != null, "T01 前门热点存在")
		var dc := _find_ctrl(inst, "FrontDoorGeoController")
		_check(dc != null, "T01 门控制器存在")
		_check(dc != null and not dc.is_open(), "T01 门初始为关闭")
		# 按 E：只开门，不传送
		_use(_find(inst, "FrontDoor"))
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(5):
			return false
		var inst: Node = _sm.get_current_instance()
		var dc := _find_ctrl(inst, "FrontDoorGeoController")
		_check(dc != null and dc.is_open(), "T01 按 E 后门打开")
		_check(_sm.get_current_location_id() == "party_house",
				"T01 开门不直接传送", str(_sm.get_current_location_id()))
		# 门开 → 碰撞禁用（可通行）
		var body := inst.get_node_or_null("Environment/Shared/FrontDoorGeo/FrontDoorGeoPivot/FrontDoorGeoBody")
		_check(body != null and body.collision_layer == 0, "T01 门开时碰撞层禁用")
		_pf_needed = 0
		_t_state = 2
		return false
	return true


func _find_ctrl(root: Node, cname: String) -> Node:
	for c in _walk(root):
		if str(c.name) == cname and c.has_method("is_open"):
			return c
	return null


func step_t02_side_door() -> bool:
	if _t_state == 0:
		_sm.enter_location("party_house", false)
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(5):
			return false
		var inst: Node = _sm.get_current_instance()
		_check(_find(inst, "SideDoor") != null, "T02 侧门热点存在")
		_use(_find(inst, "SideDoor"))
		_t_state = 2
		return false
	if not _wait_physics(5):
		return false
	_check(_sm.get_current_location_id() == "house_exterior", "T02 侧门通向室外")
	var p: Vector3 = _rig.global_position
	_check(_dist(p, Vector3(8.60, 0, 2.00)) < 0.35, "T02 落在侧院",
			"pos=%s 期望≈(8.60, 2.00)" % str(p))
	_check(not _is_embedded(p), "T02 落点未嵌入墙体或建筑", str(p))
	var d_front: float = Vector2(p.x - 0.0, p.z - (-2.60)).length()
	_check(d_front > 3.0, "T02 落点与前门落点明显不同（门级落点生效）",
			"与(0,-2.60)距离=%.2f m" % d_front)
	return true


# ------------------------------------------------------------------ T03 露台门

func step_t03_patio_door() -> bool:
	if _t_state == 0:
		_sm.enter_location("party_house", false)
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(3):
			return false
		var inst: Node = _sm.get_current_instance()
		_check(_find(inst, "PatioDoor") != null, "T03 露台门热点存在")
		_use(_find(inst, "PatioDoor"))
		_t_state = 2
		return false
	if not _wait_physics(3):
		return false

	_check(_sm.get_current_location_id() == "house_exterior", "T03 露台门通向室外")
	var p: Vector3 = _rig.global_position
	# 门级落点 (-4.00, 0.05, 11.00)：房屋后侧
	_check(_dist(p, Vector3(-4.00, 0, 11.00)) < 0.35, "T03 落在后院露台",
			"pos=%s 期望≈(-4.00, 11.00)" % str(p))
	_check(not _is_embedded(p), "T03 落点未嵌入墙体或建筑", str(p))
	return true


# ------------------------------------------------------------------ T04 回屋

func step_t04_back_inside() -> bool:
	if _t_state == 0:
		# 当前已在 house_exterior（T03 之后），直接找回屋门
		var inst: Node = _sm.get_current_instance()
		var door := _find(inst, "DoorToInterior")
		_check(door != null, "T04 回屋门热点存在")
		if door != null:
			_check(str(door.target_location) == "party_house",
					"T04 回屋门指向 party_house（不再指向 living_room）",
					str(door.target_location))
			_check(bool(door.use_target_spawn), "T04 回屋门携带门级落点")
		_use(door)
		_t_state = 1
		return false
	if not _wait_physics(3):
		return false

	_check(_sm.get_current_location_id() == "party_house", "T04 从室外回到新住宅",
			str(_sm.get_current_location_id()))
	var p: Vector3 = _rig.global_position
	_check(_dist(p, Vector3(0, 0, 1.60)) < 0.35, "T04 回到前门内侧",
			"pos=%s 期望≈(0, 1.60)" % str(p))
	_check(not _is_embedded(p), "T04 落点未嵌入墙体", str(p))
	return true


# ------------------------------------------------------------------ T05 不嵌墙

func step_t05_no_embed() -> bool:
	# 逐个落点做形状查询：把玩家放到落点，抬高 6cm 躲开地板接触
	var samples := [
		["前门落点", "house_exterior", Vector3(0.0, 0.05, -2.60)],
		["侧门落点", "house_exterior", Vector3(8.60, 0.05, 2.00)],
		["露台落点", "house_exterior", Vector3(-4.00, 0.05, 11.00)],
		["回屋落点", "party_house", Vector3(0.0, 0.25, 1.60)],
	]
	for s in samples:
		_sm.enter_location(str(s[1]), false)
		if not _wait_physics(2):
			return false
		var inst: Node = _sm.get_current_instance()
		var space: PhysicsDirectSpaceState3D = (inst as Node3D).get_world_3d().direct_space_state
		var shape := CapsuleShape3D.new()
		shape.radius = 0.30
		shape.height = 1.66
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		var pos: Vector3 = s[2]
		q.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.86 + 0.06, 0))
		q.collision_mask = 1
		q.exclude = [_rig.get_rid()]
		var hits: Array = space.intersect_shape(q, 8)
		var names: Array = []
		for h in hits:
			var c = h.get("collider")
			if c != null:
				names.append(str(c.name))
		_check(hits.is_empty(), "T05 %s 不在碰撞体内" % str(s[0]), str(names))
	return true


# ------------------------------------------------------------------ T06 朝向

func step_t06_facing() -> bool:
	# 出口朝向设计值应各不相同，且与空间方向一致。
	# 前门已改为真实门流程（不传送），校验其热点配置的 target_yaw_deg；
	# 侧门/露台门仍走传送，校验玩家实际 yaw。
	var cases := [
		["前门", "party_house", "FrontDoor", 0.0],
		["侧门", "party_house", "SideDoor", -90.0],
		["露台门", "party_house", "PatioDoor", 180.0],
	]
	var yaws: Array = []
	for c in cases:
		_sm.enter_location(str(c[1]), false)
		if not _wait_physics(3):
			return false
		var spot := _find(_sm.get_current_instance(), str(c[2]))
		if spot == null:
			_check(false, "T06 %s 热点不存在" % str(c[0]))
			continue
		var configured: float = float(spot.target_yaw_deg)
		var diff: float = fmod(configured - float(c[3]) + 540.0, 360.0) - 180.0
		_check(absf(diff) < 5.0, "T06 %s 朝向设计值正确" % str(c[0]),
				"配置=%.1f° 期望=%.1f°" % [configured, float(c[3])])
		yaws.append(configured)
	set("_t_state", 0)
	return true


# ------------------------------------------------------------------ T07 近距离聚焦

func step_t07_near_focus() -> bool:
	if _t_state == 0:
		_sm.enter_location("party_house", false)
		_t_state = 1
		return false
	if not _wait_physics(3):
		return false

	var inst: Node = _sm.get_current_instance()
	var spot := _find(inst, "DiningTableSpot")
	if spot == null:
		_check(false, "T07 近距离可聚焦", "未找到 DiningTableSpot")
		return true

	# 站到热点南侧 1.6 m（桌体 z 5.18~7.78，热点在 6.48，故 4.88 在桌外）
	var target: Vector3 = spot.global_position
	_rig.reset_to_spawn(Vector3(target.x, 0.25, target.z - 1.6))
	var dir: Vector3 = (target - _rig.get_camera().global_position).normalized()
	_rig.yaw = atan2(-dir.x, -dir.z)
	_rig.pitch = -asin(clampf(dir.y, -1.0, 1.0))
	_rig._apply_rotation()

	if not _wait_physics(4):
		return false
	# 显式驱动一次焦点更新。
	# headless 下节点的 _process 不保证落在物理帧等待窗口内，若只靠时序，
	# 断言会变成「根本没更新」而不是「判定不通过」——那样的绿灯是假的。
	_im._update_focus()
	var focused: Hotspot = _im.get_focused()
	var d: float = _rig.get_camera().global_position.distance_to(target)
	_check(focused == spot, "T07 近距离 1.6 m 可获得焦点",
			"focused=%s 距离=%.2f 上限=%.1f" % [
				focused.name if focused != null else "null", d, _im.MAX_INTERACT_DISTANCE])
	_check(_im.activate_focused(), "T07 近距离可执行交互")
	return true


# ------------------------------------------------------------------ T08 远距离不聚焦

func step_t08_far_no_focus() -> bool:
	if _t_state == 0:
		_sm.enter_location("party_house", false)
		_t_state = 1
		return false
	if not _wait_physics(3):
		return false

	var inst: Node = _sm.get_current_instance()
	var spot := _find(inst, "DiningTableSpot")
	if spot == null:
		_check(false, "T08 远距离不可聚焦", "未找到热点")
		return true

	# 退到客厅一侧（约 6.3 m），仍在开放空间内、无墙遮挡，只靠距离失效
	var target: Vector3 = spot.global_position
	_rig.reset_to_spawn(Vector3(-5.0, 0.25, target.z + 1.0))
	var dir: Vector3 = (target - _rig.get_camera().global_position).normalized()
	_rig.yaw = atan2(-dir.x, -dir.z)
	_rig.pitch = -asin(clampf(dir.y, -1.0, 1.0))
	_rig._apply_rotation()

	if not _wait_physics(4):
		return false
	_im._update_focus()
	var focused: Hotspot = _im.get_focused()
	var d: float = _rig.get_camera().global_position.distance_to(target)
	_check(focused == null, "T08 远距离 6 m 不可获得焦点（超 2.5 m 上限）",
			"focused=%s 距离=%.2f 上限=%.1f" % [
				focused.name if focused != null else "null", d, _im.MAX_INTERACT_DISTANCE])
	return true


# ------------------------------------------------------------------ T09 远距离不可激活

func step_t09_far_no_activate() -> bool:
	# 承 T08 的远距离状态：直接调 activate_focused 必须失败
	# （防止「只挡提示、不挡执行」的半吊子实现）
	var before := _im.get_focused()
	var ok: bool = _im.activate_focused()
	_check(before == null, "T09 远距离下焦点为空", str(before))
	_check(not ok, "T09 远距离按 E 不执行交互")
	return true


# ------------------------------------------------------------------ T10 隔墙

func step_t10_through_wall() -> bool:
	if _t_state == 0:
		_sm.enter_location("party_house", false)
		_t_state = 1
		return false

	if _t_state == 1:
		if not _wait_physics(3):
			return false
		# 站到客厅空地，面朝 -Z
		_rig.reset_to_spawn(Vector3(-4.0, 0.25, 7.2))
		_rig.yaw = 0.0
		_rig.pitch = 0.0
		_rig._apply_rotation()
		_t_state = 2
		return false

	if _t_state == 2:
		if not _wait_physics(3):
			return false
		var cam_y: float = _rig.get_camera().global_position.y
		var spot := Area3D.new()
		spot.name = "ProbeSpot"
		spot.set_script(load("res://core/hotspot.gd"))
		spot.position = Vector3(-4.0, cam_y, 7.2 - 1.0)
		spot.display_name = "测试目标"
		spot.action_kind = "examine"
		spot.examine_text = "probe"
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.6, 0.6, 0.6)
		cs.shape = bs
		spot.add_child(cs)
		_sm.get_current_instance().add_child(spot)
		var arr: Array = _im.get_hotspots().duplicate()
		arr.append(spot)
		_im.set_hotspots(arr)
		_probe_spot = spot
		_t_state = 3
		return false

	if _t_state == 3:
		if not _wait_physics(5):
			return false
		_im._update_focus()
		_check(_im.get_focused() == _probe_spot, "T10 1 m 无遮挡时可聚焦",
				"focused=%s" % str(_im.get_focused()))
		var wall := StaticBody3D.new()
		wall.name = "ProbeWall"
		wall.collision_layer = 1
		wall.collision_mask = 0
		wall.position = Vector3(-4.0, 0.20 + 1.35, 6.70)
		var wcs := CollisionShape3D.new()
		var wbs := BoxShape3D.new()
		wbs.size = Vector3(3.0, 2.7, 0.12)
		wcs.shape = wbs
		wall.add_child(wcs)
		_sm.get_current_instance().add_child(wall)
		_probe_wall = wall
		_t_state = 4
		return false

	if not _wait_physics(5):
		return false
	_im._update_focus()
	_check(_im.get_focused() == null, "T10 隔墙后同一热点立即失效",
			"focused=%s" % str(_im.get_focused()))
	_check(not _im.activate_focused(), "T10 隔墙不可执行交互")

	if _probe_spot != null:
		_probe_spot.queue_free()
		_probe_spot = null
	if _probe_wall != null:
		_probe_wall.queue_free()
		_probe_wall = null
	return true


# ------------------------------------------------------------------ 工具

func _is_embedded(p: Vector3) -> bool:
	var inst: Node = _sm.get_current_instance()
	if inst == null:
		return true
	var space: PhysicsDirectSpaceState3D = (inst as Node3D).get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.66
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.92, 0))
	q.collision_mask = 1
	q.exclude = [_rig.get_rid()]
	return not space.intersect_shape(q, 4).is_empty()


# ------------------------------------------------------------------ T11 三扇门往返

## 此前只测了"出去"，没测"回来"——侧门与露台门在室外根本没有回程入口，
## 玩家出去后必须绕到正面门廊才能进屋。本步骤补齐三扇门的双向验证。
func step_t11_round_trip() -> bool:
	if _t_state == 0:
		_sm.enter_location("party_house", false)
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(3):
			return false
		var inst: Node = _sm.get_current_instance()
		var side := _find(inst, "SideDoor")
		_check(side != null, "T11 侧门热点存在")
		_use(side)
		_t_state = 2
		return false
	if _t_state == 2:
		if not _wait_physics(3):
			return false
		_check(_sm.get_current_location_id() == "house_exterior", "T11 侧门通向室外")
		var p: Vector3 = _rig.global_position
		_check(_dist(p, Vector3(8.6, 0, 2.0)) < 0.35, "T11 侧门落在侧院", str(p))

		var inst2: Node = _sm.get_current_instance()
		var back := _find(inst2, "SideReturn")
		_check(back != null, "T11 室外存在侧门回程入口")
		_use(back)
		_t_state = 3
		return false
	if _t_state == 3:
		if not _wait_physics(3):
			return false
		_check(_sm.get_current_location_id() == "party_house", "T11 侧门可返回室内",
			str(_sm.get_current_location_id()))
		var p2: Vector3 = _rig.global_position
		_check(_dist(p2, Vector3(5.8, 0, 2.25)) < 0.35, "T11 回到侧门内侧", str(p2))
		_check(not _is_embedded(p2), "T11 侧门内侧落点未嵌入", str(p2))
		var yaw_deg: float = rad_to_deg(_rig.yaw)
		_check(absf(fposmod(yaw_deg - 90.0, 360.0)) < 5.0, "T11 侧门回屋后朝向屋内",
			"yaw=%.1f° 期望≈90°" % yaw_deg)

		var inst3: Node = _sm.get_current_instance()
		var patio := _find(inst3, "PatioDoor")
		_check(patio != null, "T11 露台门热点存在")
		_use(patio)
		_t_state = 4
		return false
	if _t_state == 4:
		if not _wait_physics(3):
			return false
		_check(_sm.get_current_location_id() == "house_exterior", "T11 露台门通向室外")
		var p3: Vector3 = _rig.global_position
		_check(_dist(p3, Vector3(-4.0, 0, 11.0)) < 0.35, "T11 露台门落在后院", str(p3))

		var inst4: Node = _sm.get_current_instance()
		var patio_back := _find(inst4, "PatioReturn")
		_check(patio_back != null, "T11 室外存在露台门回程入口")
		_use(patio_back)
		_t_state = 5
		return false
	if _t_state == 5:
		if not _wait_physics(3):
			return false
		_check(_sm.get_current_location_id() == "party_house", "T11 露台门可返回室内",
			str(_sm.get_current_location_id()))
		var p4: Vector3 = _rig.global_position
		_check(_dist(p4, Vector3(-4.0, 0, 8.6)) < 0.35, "T11 回到露台门内侧", str(p4))
		_check(not _is_embedded(p4), "T11 露台门内侧落点未嵌入", str(p4))
		var yaw2: float = rad_to_deg(_rig.yaw)
		_check(absf(fposmod(yaw2, 360.0)) < 5.0 or absf(fposmod(yaw2, 360.0) - 360.0) < 5.0,
			"T11 露台门回屋后朝向屋内", "yaw=%.1f° 期望≈0°" % yaw2)
		_t_state = 0
	return true


func step_report() -> bool:
	print("")
	for line in _results:
		print(line)
	print("")
	print("=== DOOR RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
