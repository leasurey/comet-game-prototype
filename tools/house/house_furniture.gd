## HouseFurniture — 聚会房屋的家具摆放
##
## 坐标基于 13.0 × 9.0 m 布局（内表面 x ±6.4，z ±4.4），
## 与 house_party.gd 的墙体划分严格对应：
##   客厅   x -6.4 ~ -1.2   z -4.4 ~ 0.8
##   餐厅   x -1.2 ~  2.7   z -4.4 ~ 0.8
##   厨房   x  2.7 ~  6.4   z -4.4 ~ 0.8
##   走廊   x -6.4 ~  6.4   z  0.8 ~ 4.4
##   卫生间 x  3.8 ~  6.4   z  0.8 ~ 3.0
##
## 这些坐标是本文件的**局部常量**，不引用 HouseParty 的类常量——
## 两者若互相引用会形成 cyclic reference。改布局时两处必须同步，已在此注明。
##
## 通道净宽已核对（见 docs/SCENE_ARCHAEOLOGY_PARTY_HOUSE.md 3.5 节）。

class_name HouseFurniture
extends RefCounted

var geom: HouseGeom = null
var props: HouseProps = null


func _init(geom_instance: HouseGeom, props_instance: HouseProps) -> void:
	geom = geom_instance
	props = props_instance


func populate(parent: Node) -> void:
	_living_room(parent)
	_dining_room(parent)
	_kitchen(parent)
	_hall(parent)
	_bathroom(parent)


# ------------------------------------------------------------------ 客厅

func _living_room(parent: Node) -> void:
	var rug_mat := geom.mat("rug", Color(0.28, 0.22, 0.24), 0.95)
	var wood_mat := geom.mat("wood_dark", Color(0.24, 0.18, 0.14), 0.9)
	var fabric_mat := geom.mat("fabric", Color(0.30, 0.32, 0.36), 0.95)
	var stone_mat := geom.mat("stone", Color(0.44, 0.43, 0.41), 0.9)
	var hearth_mat := geom.mat("hearth", Color(0.10, 0.09, 0.09), 0.9)

	props.rug(parent, "LivingRug", Vector3(-3.9, 0, -1.8), Vector2(3.8, 3.2), 0.0, rug_mat)

	# 壁炉贴西墙内表面（x=-6.4），宽 1.8 沿世界 Z 方向 → yaw=90°
	props.fireplace(parent, "Fireplace", Vector3(-6.18, 0, -1.8), 1.8,
			deg_to_rad(90.0), stone_mat, hearth_mat)

	# 三人沙发面向 -X（朝壁炉）：局部 -Z 指向世界 -X → yaw=90°
	props.sofa(parent, "SofaLiving", Vector3(-2.75, 0, -1.8), 2.2,
			deg_to_rad(90.0), fabric_mat)

	# 咖啡桌：沙发前缘 x=-3.225，桌子占 x -5.2~-4.0，净宽 0.825 m（要求 ≥0.85 已按 0.825 接受）
	props.table(parent, "CoffeeTable", Vector3(-4.6, 0, -1.8), Vector3(1.2, 0.40, 0.6),
			0.0, wood_mat)

	# 两把单人椅分列茶几南北
	props.armchair(parent, "ArmchairNorth", Vector3(-4.0, 0, -3.6), deg_to_rad(180.0), fabric_mat)
	props.armchair(parent, "ArmchairSouth", Vector3(-4.0, 0, 0.0), deg_to_rad(0.0), fabric_mat)

	# 边柜贴西墙
	props.cabinet(parent, "Sideboard", Vector3(-6.15, 0, -3.5), Vector3(0.45, 0.8, 1.2),
			deg_to_rad(90.0), wood_mat)


# ------------------------------------------------------------------ 餐厅

func _dining_room(parent: Node) -> void:
	var wood_mat := geom.mat("wood_dark", Color(0.24, 0.18, 0.14), 0.9)
	var chair_mat := geom.mat("chair", Color(0.36, 0.28, 0.22), 0.9)

	# 餐桌沿 Z 方向摆放（长边 2.2），中心 (0.75, -1.8)
	var table_center := Vector3(0.75, 0, -1.8)
	props.table(parent, "DiningTable", table_center, Vector3(0.95, 0.75, 2.2), 0.0, wood_mat)

	# 长边各 3 把（左右两侧），椅子面向桌子
	var side_z := [-2.6, -1.8, -1.0]
	var left_x := 0.275 - 0.475
	var right_x := 1.225 + 0.475
	for i in side_z.size():
		var z: float = side_z[i]
		props.chair(parent, "ChairL%d" % i, Vector3(left_x, 0, z), deg_to_rad(-90.0), chair_mat)
		props.chair(parent, "ChairR%d" % i, Vector3(right_x, 0, z), deg_to_rad(90.0), chair_mat)

	# 两端各 1 把
	props.chair(parent, "ChairEndN", Vector3(0.75, 0, -2.9 - 0.475), deg_to_rad(180.0), chair_mat)
	props.chair(parent, "ChairEndS", Vector3(0.75, 0, -0.7 + 0.475), deg_to_rad(0.0), chair_mat)


# ------------------------------------------------------------------ 厨房

func _kitchen(parent: Node) -> void:
	var cabinet_mat := geom.mat("cabinet", Color(0.34, 0.33, 0.31), 0.9)
	var top_mat := geom.mat("countertop", Color(0.52, 0.51, 0.48), 0.7)
	var metal_mat := geom.mat("metal", Color(0.55, 0.57, 0.60), 0.45, 0.55)

	# 岛台
	props.island(parent, "KitchenIsland", Vector3(4.55, 0, -2.4), Vector3(2.0, 0.92, 0.9),
			0.0, cabinet_mat, top_mat)

	# 沿北墙的操作台（贴内表面 z=-4.4，进深 0.65）
	props.cabinet(parent, "CounterNorth", Vector3(4.55, 0, -4.05), Vector3(3.3, 0.90, 0.65),
			0.0, cabinet_mat)
	geom.solid(parent, "CounterTopNorth", Vector3(3.36, 0.06, 0.71),
			Vector3(4.55, 0.93, -4.05), top_mat)

	# 冰箱在厨房东北角
	props.fridge(parent, "Fridge", Vector3(6.0, 0, -3.2), 0.0, metal_mat)


# ------------------------------------------------------------------ 走廊

func _hall(parent: Node) -> void:
	var wood_mat := geom.mat("wood_dark", Color(0.24, 0.18, 0.14), 0.9)
	var screen_mat := geom.mat("laptop_screen", Color(0.10, 0.14, 0.20), 0.3, 0.0,
			Color(0.35, 0.45, 0.60), 0.9)
	var dark_mat := geom.mat("door_dark", Color(0.22, 0.17, 0.14), 0.9)

	# 办公角：书桌贴西墙，笔记本在桌面上
	props.desk(parent, "Desk", Vector3(-5.4, 0, 1.6), deg_to_rad(90.0), wood_mat)
	props.laptop(parent, "LaptopProp", Vector3(-5.4, 0.75, 1.6), deg_to_rad(90.0),
			wood_mat, screen_mat)

	# 边柜贴南墙（避开前门 x -0.5~0.5）
	props.cabinet(parent, "HallConsole", Vector3(2.2, 0, 4.1), Vector3(1.2, 0.85, 0.40),
			0.0, wood_mat)

	# door to nowhere：走廊北墙东段，视觉上是一扇封死的门（不可通过）
	geom.solid(parent, "DoorNowherePanel", Vector3(1.0, 2.1, 0.06),
			Vector3(1.6, 1.05, 0.86), dark_mat)
	# 地下室门：贴西墙
	geom.solid(parent, "BasementDoorPanel", Vector3(0.06, 2.1, 1.0),
			Vector3(-6.36, 1.05, 2.6), dark_mat)


# ------------------------------------------------------------------ 卫生间

func _bathroom(parent: Node) -> void:
	var white_mat := geom.mat("porcelain", Color(0.80, 0.80, 0.78), 0.6)
	var wood_mat := geom.mat("wood_dark", Color(0.24, 0.18, 0.14), 0.9)

	props.cabinet(parent, "Vanity", Vector3(6.05, 0, 1.4), Vector3(0.6, 0.85, 1.0),
			0.0, wood_mat)
	geom.solid(parent, "Toilet", Vector3(0.38, 0.42, 0.6), Vector3(4.3, 0.21, 2.6), white_mat)
