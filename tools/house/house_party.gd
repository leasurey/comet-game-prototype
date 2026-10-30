## HouseParty — 聚会房屋的墙体与房间布局
##
## 尺寸：13.0 m × 9.0 m（按用户确认的灰盒尺寸），墙厚 0.2，层高 2.7。
##
## 【重要】以下所有尺寸与房间划分均为**游戏原创**（证据等级 D）。
## 电影从未提供户型图；本布局只依据「这些空间在片中确实存在」这一 A 级事实，
## 加上 8 人聚会与第一人称通行所需的功能尺寸推导得出。
## 详见 docs/SCENE_ARCHAEOLOGY_PARTY_HOUSE.md。
##
## 房间（内表面坐标）：
##   客厅   x -6.4 ~ -1.2   z -4.4 ~ 0.8
##   餐厅   x -1.2 ~  2.7   z -4.4 ~ 0.8
##   厨房   x  2.7 ~  6.4   z -4.4 ~ 0.8
##   走廊   x -6.4 ~  6.4   z  0.8 ~ 4.4
##   卫生间 x  3.8 ~  6.4   z  0.8 ~ 3.0
##   露台   x -6.5 ~ -1.5   z -7.4 ~ -4.5

class_name HouseParty
extends RefCounted

const WALL_H := 2.7
const WALL_T := 0.2

# 外墙中心线
const OUT_X := 6.5
const OUT_Z := 4.5

# 内表面
const IN_X := 6.4
const IN_Z := 4.4

# 房间分界（内表面）
const LIVING_X0 := -6.4
const LIVING_X1 := -1.2
const DINING_X1 := 2.7
const KITCHEN_X1 := 6.4
const ROOM_Z0 := -4.4
const ROOM_Z1 := 0.8
const HALL_Z1 := 4.4

const BATH_X0 := 3.8
const BATH_Z1 := 3.0

const PATIO_X0 := -6.5
const PATIO_X1 := -1.5
const PATIO_Z0 := -7.4

# 关键位置
const FRONT_DOOR := Vector3(0.0, 0.0, 4.5)
const PATIO_DOOR := Vector3(-4.0, 0.0, -4.5)
const SPAWN := Vector3(0.0, 0.05, 3.4)

var geom: HouseGeom = null
var props: HouseProps = null
var light: HouseLight = null


func _init(geom_instance: HouseGeom) -> void:
	geom = geom_instance
	props = HouseProps.new(geom)
	light = HouseLight.new()


## 总装入口。返回各容器节点，供灯光与附属模块使用。
func build(root: Node3D) -> Dictionary:
	var env := geom.node(root, "Environment")
	var shared := geom.node(env, "Shared")
	var va := geom.node(env, "Variant_world_alpha")
	var vb := geom.node(env, "Variant_world_beta")
	var hotspots := geom.node(root, "Hotspots")

	var wall_mat := geom.mat("wall", Color(0.72, 0.70, 0.66), 0.95)
	var floor_mat := geom.mat("floor", Color(0.36, 0.27, 0.19), 0.88)
	var ceil_mat := geom.mat("ceiling", Color(0.66, 0.65, 0.63), 0.95)
	var patio_mat := geom.mat("patio", Color(0.40, 0.39, 0.36), 0.95)

	_build_floor_and_ceiling(shared, floor_mat, ceil_mat)
	_build_outer_walls(shared, wall_mat)
	_build_inner_walls(shared, wall_mat)
	_build_patio(shared, patio_mat)
	_build_outdoor_ground(shared, floor_mat)

	# 家具
	var furniture := HouseFurniture.new(geom, props)
	furniture.populate(shared)

	# 灯光：两套（有电 / 停电）
	var lighting := HouseLighting.new(light)
	lighting.build(va, vb, shared)

	_build_hotspots(hotspots)

	return {
		"environment": env,
		"shared": shared,
		"variant_alpha": va,
		"variant_beta": vb,
		"hotspots": hotspots,
	}


# ------------------------------------------------------------------ 地板

func _build_floor_and_ceiling(parent: Node, floor_mat: Material, ceil_mat: Material) -> void:
	var w := (IN_X + WALL_T) * 2.0
	var d := (IN_Z + WALL_T) * 2.0
	# 地板：顶面 y=0
	geom.solid(parent, "Floor", Vector3(w, 0.2, d), Vector3(0, -0.1, 0), floor_mat)
	# 天花板：底面 y=2.7
	geom.solid(parent, "Ceiling", Vector3(w, 0.2, d), Vector3(0, WALL_H + 0.1, 0), ceil_mat)


# ------------------------------------------------------------------ 外墙

func _build_outer_walls(parent: Node, mat: Material) -> void:
	var span_x := (OUT_X + WALL_T * 0.5) * 2.0

	# 南墙（+Z）：前门 1.0 m
	geom.wall_with_opening(parent, "WallSouth", {
		"axis": "x",
		"center": Vector3(0, 0, OUT_Z),
		"length": span_x,
		"thickness": WALL_T,
		"height": WALL_H,
		"opening": {"offset": 0.0, "width": 1.0, "height": 2.15, "bottom": 0.0},
	}, mat)

	# 北墙（-Z）：露台门 1.4 m，位于 x=-4.0
	geom.wall_with_opening(parent, "WallNorth", {
		"axis": "x",
		"center": Vector3(0, 0, -OUT_Z),
		"length": span_x,
		"thickness": WALL_T,
		"height": WALL_H,
		"opening": {"offset": PATIO_DOOR.x, "width": 1.4, "height": 2.15, "bottom": 0.0},
	}, mat)

	# 西墙（-X）
	geom.wall_with_opening(parent, "WallWest", {
		"axis": "z",
		"center": Vector3(-OUT_X, 0, 0),
		"length": (OUT_Z + WALL_T * 0.5) * 2.0,
		"thickness": WALL_T,
		"height": WALL_H,
	}, mat)

	# 东墙（+X）
	geom.wall_with_opening(parent, "WallEast", {
		"axis": "z",
		"center": Vector3(OUT_X, 0, 0),
		"length": (OUT_Z + WALL_T * 0.5) * 2.0,
		"thickness": WALL_T,
		"height": WALL_H,
	}, mat)


# ------------------------------------------------------------------ 内墙

func _build_inner_walls(parent: Node, mat: Material) -> void:
	# 客厅 | 餐厅（x=-1.2），开放通道 2.8 m
	var mid_z := (ROOM_Z0 + ROOM_Z1) * 0.5
	var room_d := ROOM_Z1 - ROOM_Z0
	geom.wall_with_opening(parent, "WallLivingDining", {
		"axis": "z",
		"center": Vector3(LIVING_X1, 0, mid_z),
		"length": room_d,
		"thickness": WALL_T,
		"height": WALL_H,
		"opening": {"offset": 0.0, "width": 2.8, "height": 2.35, "bottom": 0.0},
	}, mat)

	# 餐厅 | 厨房（x=2.7），开放通道 2.6 m
	geom.wall_with_opening(parent, "WallDiningKitchen", {
		"axis": "z",
		"center": Vector3(DINING_X1, 0, mid_z),
		"length": room_d,
		"thickness": WALL_T,
		"height": WALL_H,
		"opening": {"offset": 0.0, "width": 2.6, "height": 2.35, "bottom": 0.0},
	}, mat)

	# 卫生间西墙（x=3.8），门 0.85 m
	var bath_d := BATH_Z1 - ROOM_Z1
	geom.wall_with_opening(parent, "WallBathWest", {
		"axis": "z",
		"center": Vector3(BATH_X0, 0, (ROOM_Z1 + BATH_Z1) * 0.5),
		"length": bath_d,
		"thickness": WALL_T,
		"height": WALL_H,
		"opening": {"offset": 0.0, "width": 0.85, "height": 2.1, "bottom": 0.0},
	}, mat)

	# 卫生间南墙（z=3.0）
	geom.wall_with_opening(parent, "WallBathSouth", {
		"axis": "x",
		"center": Vector3((BATH_X0 + IN_X) * 0.5, 0, BATH_Z1),
		"length": IN_X - BATH_X0,
		"thickness": WALL_T,
		"height": WALL_H,
	}, mat)


# ------------------------------------------------------------------ 室外

func _build_patio(parent: Node, mat: Material) -> void:
	var w := PATIO_X1 - PATIO_X0
	var d := -OUT_Z - PATIO_Z0
	geom.solid(parent, "PatioFloor",
			Vector3(w, 0.2, d),
			Vector3((PATIO_X0 + PATIO_X1) * 0.5, -0.1, (PATIO_Z0 + (-OUT_Z)) * 0.5), mat)

	# 露台栏杆：三面（北、西、东），高 1.0，厚 0.1
	var rail_h := 1.0
	var rail_t := 0.12
	geom.solid(parent, "PatioRailNorth", Vector3(w, rail_h, rail_t),
			Vector3((PATIO_X0 + PATIO_X1) * 0.5, rail_h * 0.5, PATIO_Z0), mat)
	geom.solid(parent, "PatioRailWest", Vector3(rail_t, rail_h, d),
			Vector3(PATIO_X0, rail_h * 0.5, (PATIO_Z0 + (-OUT_Z)) * 0.5), mat)
	geom.solid(parent, "PatioRailEast", Vector3(rail_t, rail_h, d),
			Vector3(PATIO_X1, rail_h * 0.5, (PATIO_Z0 + (-OUT_Z)) * 0.5), mat)


func _build_outdoor_ground(parent: Node, mat: Material) -> void:
	# 室外地面，与室内同高（灰盒阶段不做台阶，避免额外通行问题）
	geom.solid(parent, "Ground", Vector3(40.0, 0.2, 40.0), Vector3(0, -0.1, 2.0), mat)


# ------------------------------------------------------------------ 热点

func _build_hotspots(parent: Node) -> void:
	_add_exit(parent, "ExitToExterior", Vector3(0, 1.1, 4.42), "前门", "house_exterior",
			Vector3(1.3, 2.4, 0.6))

	_add_examine(parent, "PatioDoor", Vector3(-4.0, 1.1, -4.42), "通向露台的门",
			"玻璃门没锁。外面很静，只有远处的虫鸣。",
			Vector3(1.7, 2.4, 0.6))

	# door to nowhere：原创布点，位于走廊北墙东段
	_add_examine(parent, "DoorToNowhere", Vector3(1.6, 1.05, 0.88), "一扇打不开的门",
			"门把手能转动，但门纹丝不动。门缝后面没有光，也没有风。",
			Vector3(1.2, 2.3, 0.5))

	# 地下室门：只做封闭门，不制作内部
	_add_examine(parent, "BasementDoor", Vector3(-6.35, 1.05, 2.6), "地下室的门",
			"门是锁着的。有人说底下堆着旧家具，但今晚没有下去的理由。",
			Vector3(0.5, 2.3, 1.2))

	_add_examine(parent, "Laptop", Vector3(-5.4, 1.05, 1.6), "一台笔记本电脑",
			"屏幕还亮着，停在一张看不出内容的图上。",
			Vector3(0.8, 0.6, 0.8))

	_add_examine(parent, "Fireplace", Vector3(-6.15, 0.9, -1.8), "壁炉",
			"火还没灭透，余烬偶尔炸开一点火星。",
			Vector3(0.7, 1.8, 2.0))

	_add_examine(parent, "DiningTable", Vector3(0.75, 0.9, -1.8), "餐桌",
			"八个人的餐具已经摆好，蜡烛还没点上。",
			Vector3(1.2, 1.2, 2.4))

	_add_examine(parent, "KitchenIsland", Vector3(4.55, 0.95, -2.6), "厨房岛台",
			"台面上摆着几只杯子和一瓶没开的酒。",
			Vector3(2.2, 1.3, 1.1))


func _add_exit(parent: Node, node_name: String, pos: Vector3, display_name: String,
		target: String, hit_size: Vector3) -> void:
	var spot := Area3D.new()
	spot.name = node_name
	spot.set_script(load("res://core/hotspot.gd"))
	spot.position = pos
	spot.display_name = display_name
	spot.action_kind = "exit"
	spot.target_location = target
	_col(spot, hit_size)
	parent.add_child(spot)


func _add_examine(parent: Node, node_name: String, pos: Vector3, display_name: String,
		text: String, hit_size: Vector3) -> void:
	var spot := Area3D.new()
	spot.name = node_name
	spot.set_script(load("res://core/hotspot.gd"))
	spot.position = pos
	spot.display_name = display_name
	spot.action_kind = "examine"
	spot.examine_text = text
	_col(spot, hit_size)
	parent.add_child(spot)


func _col(spot: Area3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "HitShape"
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	spot.add_child(cs)
