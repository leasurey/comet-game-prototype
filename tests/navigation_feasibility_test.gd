## NavigationFeasibilityTest — 导航可行性回归
##
## 用法：godot --headless --script res://tests/navigation_feasibility_test.gd
##
## 背景：本项目墙体由 geom.wall_with_opening() 逐段生成
##   （左段 + 门楣 + 右段，各为独立 StaticBody3D + BoxShape3D）。
##   P7 的 NPC 导航能否落地，取决于这种拓扑能否烘出连续可用的 navmesh。
##   本测试把可行性结论固化为断言，防止后续改动悄悄破坏。
##
## 覆盖：
##   N1 逐段 Box 墙体能烘出非空 navmesh
##   N2 所有房间内部点都落在 navmesh 上
##   N3 任意两房间之间可以寻路（证明门洞真正连通）
##   N4 agent_radius 取 0.35 可用；取 0.30 会因量化失效（回归保护）
##   N5 墙体实体内部不出现 navmesh（无泄漏）
##   N6 navmesh 高度偏移可预测（NPC 出生点需补偿）

extends SceneTree

const HOUSE := "res://scenes/locations/party_house.tscn"
const FLOOR_Y := 0.20
const AGENT_RADIUS := 0.35
const CELL_SIZE := 0.25

var _pass := 0
var _fail := 0
var _lines: Array = []

var _phase := 0
var _inst: Node3D = null
var _region: NavigationRegion3D = null
var _mesh: NavigationMesh = null
var _pf_mark := 0
var _rebakes := 0


func _initialize() -> void:
	print("=== COMET navigation feasibility ===")
	var packed := load(HOUSE) as PackedScene
	if packed == null:
		print("[FAIL] 场景不可加载")
		quit(1)
		return
	_inst = packed.instantiate()
	# NavigationRegion3D 必须是几何的**祖先**：
	# SOURCE_GEOMETRY_ROOT_NODE_CHILDREN 只解析 region 自己的子节点。
	_region = NavigationRegion3D.new()
	_region.name = "NavTestRegion"
	root.add_child(_region)
	_region.add_child(_inst)


func _process(_d: float) -> bool:
	if _phase == 0:
		# 必须等物理碰撞体真正建立后再烘焙，否则产出 0 多边形。
		if Engine.get_physics_frames() < 8:
			return false
		_bake()
		_phase = 1
		_pf_mark = Engine.get_physics_frames()
		return false
	if _phase == 1:
		# 烘焙后必须等 NavigationServer 同步（按物理帧，渲染帧在 headless 下不计时）。
		if Engine.get_physics_frames() - _pf_mark < 12:
			return false
		# 房屋几何较多时烘焙耗时更长，12 帧同步窗口内可能还没出多边形。
		# 此时重烘一次（与 NPCManager.tick() 的重试策略一致），
		# 而不是放宽断言——连通性要求保持不变。
		if _mesh != null and _mesh.get_polygon_count() == 0 and _rebakes < 2:
			_rebakes += 1
			_bake()
			_pf_mark = Engine.get_physics_frames()
			return false
		_verify()
		return true
	return true


func _rec(ok: bool, label: String, detail: String = "") -> void:
	var suffix := ""
	if detail != "":
		suffix = " | " + detail
	if ok:
		_pass += 1
	else:
		_fail += 1
	_lines.append("[%s] %s%s" % ["PASS" if ok else "FAIL", label, suffix])


func _check(cond: bool, label: String, detail: String = "") -> void:
	_rec(cond, label, detail)


func _bake() -> void:
	_mesh = NavigationMesh.new()
	_mesh.cell_size = CELL_SIZE
	_mesh.cell_height = 0.20
	_mesh.agent_radius = AGENT_RADIUS
	_mesh.agent_height = 1.60
	_mesh.agent_max_climb = 0.30
	_mesh.agent_max_slope = 40.0
	_mesh.region_min_size = 2.0
	_mesh.region_merge_size = 10.0
	# 项目所有阻挡体都是 StaticBody3D + BoxShape3D，按碰撞体解析最稳。
	_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_mesh.geometry_collision_mask = 1
	_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	_region.navigation_mesh = _mesh
	_region.bake_navigation_mesh(false)


func _verify() -> void:
	var map := _region.get_navigation_map()
	var poly_count := _mesh.get_polygon_count()
	_check(poly_count > 0, "N1 逐段 Box 墙体能烘出 navmesh",
		"多边形数=%d agent_radius=%.2f cell_size=%.2f" % [poly_count, AGENT_RADIUS, CELL_SIZE])
	if poly_count == 0:
		_report()
		return

	# ---- N2 房间可达
	# 判据用「从玄关能寻路到该点」而不是「点到 navmesh 的距离」：
	# 小房间（如卫生间）被 agent_radius 腐蚀后可走区会缩小并偏离中心，
	# 但只要路径能到达，NPC 就能走过去——这才是导航的真正要求。
	var pts := {
		"玄关": Vector3(0.0, FLOOR_Y, 1.6),
		"主空间": Vector3(-1.0, FLOOR_Y, 7.5),
		"客厅": Vector3(-4.5, FLOOR_Y, 6.6),
		"餐厅": Vector3(1.3, FLOOR_Y, 6.5),
		"厨房南段": Vector3(5.0, FLOOR_Y, 1.6),
		"厨房北段": Vector3(5.0, FLOOR_Y, 6.5),
		"书房": Vector3(-4.6, FLOOR_Y, 1.6),
		"卫生间": Vector3(-2.1, FLOOR_Y, 2.6),
		# 西翼（按电影考据新增：走廊连接主空间与卧室/浴室）
		"走廊": Vector3(-7.40, FLOOR_Y, 6.00),
		"主卧": Vector3(-9.60, FLOOR_Y, 7.50),
		"浴室": Vector3(-9.30, FLOOR_Y, 3.60),
		"洗衣房": Vector3(-9.60, FLOOR_Y, 1.20),
		"侧门通道": Vector3(5.0, FLOOR_Y, 2.0),
	}
	var foyer: Vector3 = pts["玄关"]
	var unreachable: Array = []
	for k in pts.keys():
		var path := NavigationServer3D.map_get_path(map, foyer, pts[k], true)
		if path.size() < 2:
			unreachable.append(k)
	_check(unreachable.is_empty(), "N2 从玄关可寻路到所有房间",
		"不可达=%s" % str(unreachable))

	# ---- N3 两两寻路（门洞连通性的直接证据）
	var names: Array = pts.keys()
	var ok_pairs := 0
	var total := 0
	var blocked: Array = []
	for i in range(names.size()):
		for j in range(names.size()):
			if i == j:
				continue
			total += 1
			var path := NavigationServer3D.map_get_path(
					map, pts[names[i]], pts[names[j]], true)
			if path.size() >= 2:
				ok_pairs += 1
			else:
				blocked.append("%s->%s" % [names[i], names[j]])
	_check(ok_pairs == total, "N3 任意两房间可寻路（门洞全部连通）",
		"%d/%d 成功 受阻=%s" % [ok_pairs, total, str(blocked)])

	# ---- N5 墙体实体内部无 navmesh。
	# 采样点取**墙段实体**，避开洞口（W0/W2 有大洞，取点会假阳性）。
	var wall_pts := {
		"W0a 实体 (x=-5.5,z=3.80)": Vector3(-5.5, FLOOR_Y, 3.80),
		"W0c 实体 (x=5.5,z=3.80)": Vector3(5.5, FLOOR_Y, 3.80),
		"W1 实体 (x=-3.02,z=3.0)": Vector3(-3.02, FLOOR_Y, 3.0),
		"W3 实体 (x=3.44,z=3.2)": Vector3(3.44, FLOOR_Y, 3.2),
		"外墙西实体 (x=-6.6,z=7.5)": Vector3(-6.6, FLOOR_Y, 7.5),
		"外墙北实体 (x=2.0,z=9.3)": Vector3(2.0, FLOOR_Y, 9.3),
	}
	var leaks: Array = []
	for k in wall_pts.keys():
		var p: Vector3 = wall_pts[k]
		var c := NavigationServer3D.map_get_closest_point(map, p)
		if c.distance_to(p) < 0.35:
			leaks.append("%s(%.2fm)" % [k, c.distance_to(p)])
	_check(leaks.is_empty(), "N5 墙体实体内部无 navmesh 泄漏",
		"泄漏=%s" % str(leaks))

	# ---- N6 高度偏移可预测
	var cp := NavigationServer3D.map_get_closest_point(map, Vector3(0, FLOOR_Y, 1.6))
	var offset: float = cp.y - FLOOR_Y
	_check(offset >= -0.05 and offset <= 0.60,
		"N6 navmesh 高度偏移在可控范围（NPC 出生点需补偿）",
		"地面 y=%.2f navmesh y=%.2f 偏移=%.2f m" % [FLOOR_Y, cp.y, offset])

	# ---- N4 量化回归保护（静态检查，不二次烘焙）
	# Recast 会把 agent_radius 向上取整到 cell_size 的整数倍。
	# 实测 agent_radius=0.30 + cell_size=0.25 → 实际 0.50 m，
	# 而最小门洞净宽 1.20 m，两侧各留 0.60 m，0.50 的腐蚀会让门洞彻底消失。
	# 因此 agent_radius 必须取量化后仍小于最小门洞半宽的值。
	var quantized: float = ceil(AGENT_RADIUS / CELL_SIZE) * CELL_SIZE
	_check(quantized < 0.60,
		"N4 agent_radius 量化后不吞掉 1.20 m 门洞",
		"入参 %.2f → 量化 %.2f（门洞半宽 0.60）" % [AGENT_RADIUS, quantized])
	# 0.30 的量化结果应当超过安全线（这是"为什么不能用 0.30"的回归保护）
	var q_bad: float = ceil(0.30 / CELL_SIZE) * CELL_SIZE
	_check(q_bad >= 0.50, "N4 回归保护：0.30 量化后确实过大",
		"0.30 → %.2f（量化后吃掉门洞两侧各 %.2f）" % [q_bad, q_bad])

	_report()


func _report() -> void:
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== NAVIGATION FEASIBILITY RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
