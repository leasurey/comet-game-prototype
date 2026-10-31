## WallGeometryTest — 带洞口墙体原语验证
##
## 用法：
##   godot --headless --script res://tests/wall_geometry_test.gd
##
## 为什么单独测这个：
##   wall_with_opening 是整栋房屋的基础原语。它一旦有缝，
##   玩家会从门框边缘挤出墙外；一旦洞口被堵，房间之间走不通。
##   这两类问题在灰盒阶段极难靠肉眼发现，必须用射线逐点验证。
##
## 验证手段：用物理射线穿过洞口与墙段，以「是否命中」判断碰撞是否连续。

extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []

var _geom = null
var _stage: Node3D = null
var _steps: Array = []
var _idx: int = 0
var _ticks: int = 0

var _wall_node: Node3D = null
var _room_node: Node3D = null


func _initialize() -> void:
	print("=== COMET wall geometry test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))
	var script = load("res://tools/lib/geom.gd")
	_geom = script.new()
	_build_steps()


func _build_steps() -> void:
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_w01_solid_wall"),
		Callable(self, "step_w02_door_wall_segments"),
		Callable(self, "step_w03_window_wall_segments"),
		Callable(self, "step_w04_ray_through_door"),
		Callable(self, "step_w05_ray_hits_wall"),
		Callable(self, "step_w06_lintel_blocks"),
		Callable(self, "step_w07_no_gap"),
		Callable(self, "step_w08_room_shell"),
		Callable(self, "step_w09_room_door_passthrough"),
		Callable(self, "step_w10_capsule_fits_door"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	if bool(_steps[_idx].call()):
		_idx += 1
		_ticks = 0
	else:
		_ticks += 1
		if _ticks > 300:
			_record(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
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


func _wait(frames: int) -> bool:
	if _ticks < frames:
		return false
	return true


## 沿给定方向投射一条射线，返回命中的物体名（无命中返回 "none"）。
func _cast(from: Vector3, to: Vector3, mask: int = 1) -> String:
	var space := _stage.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return "none"
	var c: Variant = hit.get("collider")
	if c == null:
		return "?"
	return str((c as Node).name)


func _count_segments(holder: Node) -> int:
	var n := 0
	for c in holder.get_children():
		if c is StaticBody3D:
			n += 1
	return n


func _segment_names(holder: Node) -> Array:
	var out: Array = []
	for c in holder.get_children():
		if c is StaticBody3D:
			out.append(str(c.name))
	return out


# ------------------------------------------------------------------ setup

func step_setup() -> bool:
	_stage = Node3D.new()
	_stage.name = "WallTestStage"
	root.add_child(_stage)
	_check(true, "setup. 测试舞台创建")
	return true


# ------------------------------------------------------------------ W01~W03 段数

func step_w01_solid_wall() -> bool:
	if _wall_node == null:
		_wall_node = _geom.wall_with_opening(_stage, "WallSolid", {
			"axis": "x",
			"center": Vector3.ZERO,
			"length": 5.0,
			"thickness": 0.2,
			"height": 2.7,
		}, _geom.mat("t_wall", Color(0.7, 0.68, 0.64)))
		if not _wait(3):
			return false
	var n := _count_segments(_wall_node)
	_check(n == 1, "W01 实心墙生成 1 个墙段", "实际 %d 段: %s" % [n, str(_segment_names(_wall_node))])
	return true


func step_w02_door_wall_segments() -> bool:
	# 换一面带门洞的墙（直接挂在同一舞台上，位置挪开避免与上一面重叠）
	_wall_node = _geom.wall_with_opening(_stage, "WallDoor", {
		"axis": "x",
		"center": Vector3(0, 0, 6.0),
		"length": 5.0,
		"thickness": 0.2,
		"height": 2.7,
		"opening": {"offset": 0.0, "width": 1.0, "height": 2.1, "bottom": 0.0},
	}, _geom.mat("t_wall", Color(0.7, 0.68, 0.64)))
	if not _wait(3):
		return false
	var names := _segment_names(_wall_node)
	var has_left := names.has("Left")
	var has_right := names.has("Right")
	var has_lintel := names.has("Lintel")
	var has_sill := names.has("Sill")
	_check(names.size() == 3, "W02 门洞墙生成 3 段（左/右/门楣）",
			"实际 %d 段: %s" % [names.size(), str(names)])
	_check(has_left and has_right and has_lintel, "W02 左段/右段/门楣齐全", str(names))
	_check(not has_sill, "W02 门（bottom=0）不应生成窗台段")
	return true


func step_w03_window_wall_segments() -> bool:
	var win_wall: Node3D = _geom.wall_with_opening(_stage, "WallWindow", {
		"axis": "x",
		"center": Vector3(0, 0, 12.0),
		"length": 5.0,
		"thickness": 0.2,
		"height": 2.7,
		"opening": {"offset": 0.0, "width": 1.4, "height": 1.1, "bottom": 0.9},
	}, _geom.mat("t_wall", Color(0.7, 0.68, 0.64)))
	var names := _segment_names(win_wall)
	_check(names.size() == 4, "W03 窗洞墙生成 4 段（左/右/门楣/窗台）",
			"实际 %d 段: %s" % [names.size(), str(names)])
	_check(names.has("Sill"), "W03 窗洞包含窗台段")
	return true


# ------------------------------------------------------------------ W04~W06 射线

func step_w04_ray_through_door() -> bool:
	if not _wait(4):
		return false
	# 门洞墙在 z=6，洞口 x∈[-0.5,0.5], y∈[0,2.1]
	var hit := _cast(Vector3(0, 1.0, 4.0), Vector3(0, 1.0, 8.0))
	_check(hit == "none", "W04 射线可穿过门洞（无阻挡）", "命中=%s" % hit)
	# 低处（0.3m）也应通透
	var hit_low := _cast(Vector3(0, 0.3, 4.0), Vector3(0, 0.3, 8.0))
	_check(hit_low == "none", "W04 贴近地面处门洞仍通透", "命中=%s" % hit_low)
	return true


func step_w05_ray_hits_wall() -> bool:
	if not _wait(4):
		return false
	# x=-2 落在左段内
	var hit_left := _cast(Vector3(-2.0, 1.0, 4.0), Vector3(-2.0, 1.0, 8.0))
	_check(hit_left != "none", "W05 墙段处射线被阻挡（左段）", "命中=%s" % hit_left)
	# x=2 落在右段内
	var hit_right := _cast(Vector3(2.0, 1.0, 4.0), Vector3(2.0, 1.0, 8.0))
	_check(hit_right != "none", "W05 墙段处射线被阻挡（右段）", "命中=%s" % hit_right)
	return true


func step_w06_lintel_blocks() -> bool:
	if not _wait(4):
		return false
	# 洞口正上方 y=2.4 应被门楣挡住
	var hit := _cast(Vector3(0, 2.4, 4.0), Vector3(0, 2.4, 8.0))
	_check(hit != "none", "W06 门洞上方门楣实体存在（不可穿）", "命中=%s" % hit)
	# 门楣上缘之外（y=2.65）也应有墙体（门楣一直做到 2.7）
	var hit_top := _cast(Vector3(0, 2.65, 4.0), Vector3(0, 2.65, 8.0))
	_check(hit_top != "none", "W06 门楣延伸到墙顶无空隙", "命中=%s" % hit_top)
	return true


func step_w07_no_gap() -> bool:
	if not _wait(2):
		return false
	# 沿洞口左右边界各偏移 3cm 处发射，确保边界处没有「缝」：
	# 洞口内侧应通透，墙侧应阻挡。
	var inside_left := _cast(Vector3(-0.47, 1.5, 4.0), Vector3(-0.47, 1.5, 8.0))
	var inside_right := _cast(Vector3(0.47, 1.5, 4.0), Vector3(0.47, 1.5, 8.0))
	_check(inside_left == "none" and inside_right == "none",
			"W07 洞口内侧边缘通透（无多余碰撞溢出）",
			"左内=%s 右内=%s" % [inside_left, inside_right])

	var outside_left := _cast(Vector3(-0.53, 1.5, 4.0), Vector3(-0.53, 1.5, 8.0))
	var outside_right := _cast(Vector3(0.53, 1.5, 4.0), Vector3(0.53, 1.5, 8.0))
	_check(outside_left != "none" and outside_right != "none",
			"W07 洞口外侧紧邻处有实体（墙段未留缝）",
			"左外=%s 右外=%s" % [outside_left, outside_right])
	return true


# ------------------------------------------------------------------ W08~W09 房间外壳

func step_w08_room_shell() -> bool:
	_room_node = _geom.room_shell(_stage, "TestRoom", {
		"center_x": 40.0,
		"center_z": 0.0,
		"size_x": 6.0,
		"size_z": 5.0,
		"thickness": 0.2,
		"height": 2.7,
		"openings": [
			{"side": "south", "offset": 0.0, "width": 1.0, "height": 2.1, "bottom": 0.0},
		],
	}, _geom.mat("t_wall", Color(0.7, 0.68, 0.64)))
	if not _wait(4):
		return false

	var sides: Array = []
	for c in _room_node.get_children():
		sides.append(str(c.name))
	_check(sides.size() == 4, "W08 房间外壳生成四面墙", str(sides))
	_check(sides.has("North") and sides.has("South") and sides.has("East") and sides.has("West"),
			"W08 四方向墙齐全", str(sides))
	# 南墙应有洞口 → 子节点多于 1 段
	var south: Node = _room_node.get_node_or_null("South")
	var south_segs := _count_segments(south) if south != null else 0
	_check(south_segs >= 2, "W08 南墙按洞口拆分", "南墙段数=%d" % south_segs)
	return true


func step_w09_room_door_passthrough() -> bool:
	if not _wait(4):
		return false
	# 房间 center=(40,0)，size 6x5，墙厚 0.2 → 南墙 z = 0 + 2.5 + 0.1 = 2.6
	# 洞口在南墙中心 x=40
	var through := _cast(Vector3(40, 1.0, 1.0), Vector3(40, 1.0, 4.0))
	_check(through == "none", "W09 房间门洞可穿过", "命中=%s" % through)

	# 北墙处（z = -2.6）应被阻挡
	var north := _cast(Vector3(40, 1.0, -1.0), Vector3(40, 1.0, -4.0))
	_check(north != "none", "W09 无洞口的北墙阻挡", "命中=%s" % north)

	# 门洞旁边的南墙段应阻挡
	var beside := _cast(Vector3(37.5, 1.0, 1.0), Vector3(37.5, 1.0, 4.0))
	_check(beside != "none", "W09 门洞旁的墙段阻挡", "命中=%s" % beside)
	return true


func step_w10_capsule_fits_door() -> bool:
	# 用一个 0.32 半径的球从门洞中心扫过，确认门宽 1.0 足够通过
	var space := _stage.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.32
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	# 门洞中心 (0, 1.0, 6.0)
	q.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 6.0))
	var hits := space.intersect_shape(q, 4)
	_check(hits.is_empty(), "W10 半径 0.32 的球体可置于门洞中央（门宽足够）",
			"重叠数=%d" % hits.size())

	# 门宽 1.0m、球半径 0.32m → 单侧理论余量 (1.0 - 0.64)/2 = 0.18m。
	# 断言取 0.15m（留 3cm 安全余量）：0.18 恰好是接触临界值，直接断言会被接触容差判为碰撞。
	q.transform = Transform3D(Basis.IDENTITY, Vector3(0.15, 1.0, 6.0))
	var hits2 := space.intersect_shape(q, 4)
	_check(hits2.is_empty(), "W10 球体在门洞内偏移 0.15m 仍不碰撞（理论余量 0.18m）",
			"重叠数=%d" % hits2.size())

	# 明确记录设计余量，作为后续门宽选择的依据
	var clearance: float = (1.0 - 0.32 * 2.0) * 0.5
	_check(clearance >= 0.15, "W10 1.0m 门宽对玩家胶囊有足够通行余量",
			"单侧余量 %.3f m（胶囊直径 0.64）" % clearance)
	return true


func step_report() -> bool:
	print("")
	for line in _results:
		print(line)
	print("")
	print("=== WALL GEOMETRY RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
