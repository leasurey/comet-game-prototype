## HouseParty — 聚会住宅灰盒
##
## 依据：docs/deliverables/MAP_REVIEW_ROUND3.md（第三轮核验，commit 781c0c6）
##
## 坐标约定（世界坐标，前门朝 -Z）：
##   外轮廓  x -6.70 ~ 6.70   z 0.00 ~ 9.40   13.4 × 9.4 = 125.96 m²
##   室内地面 y = 0.20，层高 2.7（天花底面 2.90）
##   外墙 0.20 / 内墙 0.12
##
## 房间（净尺寸，按墙心线推导）：
##   书房      x -6.50~-3.02  z 0.20~3.74
##   卫生间    x -2.90~-1.26  z 0.20~3.74
##   玄关+侧门 x -1.14~ 3.38  z 0.20~3.74
##   厨房南段  x  3.50~ 6.50  z 0.20~3.74
##   主空间    x -6.50~ 6.50  z 3.86~9.20  （客厅/餐厅/厨房北段，无内墙）
##
## 本文件只建外壳（地板/天花/墙/门洞）。家具与灯光在后续阶段接入。

extends RefCounted

const WALL_H := 2.7
const WALL_T_OUT := 0.2
const WALL_T_IN := 0.12
const FLOOR_Y := 0.20

const OUT_X := 6.7
const OUT_Z0 := 0.0
const OUT_Z1 := 9.4
const OUT_Z_MID := 4.7
const OUT_D := 9.4

const IN_Z0 := 0.2
const IN_Z1 := 9.2

const W0_Z := 3.80
const W1_X := -2.96
const W2_X := -1.20
const W3_X := 3.44
const SOUTH_N := 3.74
const SOUTH_Z_MID := 1.97

const SPAWN := Vector3(0.0, FLOOR_Y + 0.05, 1.60)

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
	var vc := geom.node(env, "Variant_world_gamma")
	var hotspots := geom.node(root, "Hotspots")

	var wall_mat := geom.mat("wall", Color(0.72, 0.70, 0.66), 0.95)
	var floor_mat := geom.mat("floor", Color(0.36, 0.27, 0.19), 0.88)
	var ceil_mat := geom.mat("ceiling", Color(0.66, 0.65, 0.63), 0.95)
	var door_mat := geom.mat("door", Color(0.42, 0.32, 0.24), 0.85)

	_build_floor_and_ceiling(shared, floor_mat, ceil_mat)
	_build_outer_walls(shared, wall_mat)
	_build_inner_walls(shared, wall_mat)
	_build_door_panels(shared, door_mat)
	_build_outdoor(shared, floor_mat)

	# 家具占位（阶段 2）
	var furniture := HouseFurniture.new(geom, props)
	furniture.populate(shared)

	# 阶段 1 只给一个基础环境，保证能看清结构。
	# 两套灯光按世界变体分开：alpha 有电（四盏吸顶），beta 停电（只剩餐桌上一支蜡烛）。
	# 这是既有世界系统的最小配合，不涉及现实切换系统的开发。
	light.world_env(shared, Color(0.03, 0.03, 0.04), Color(0.30, 0.30, 0.33))

	light.omni(va, "LivingLamp", Vector3(-4.50, 2.55, 6.60), Color(1.0, 0.90, 0.74), 2.0, 9.0)
	light.omni(va, "DiningLamp", Vector3(1.30, 2.55, 6.60), Color(1.0, 0.90, 0.74), 2.0, 9.0)
	light.omni(va, "KitchenLamp", Vector3(5.00, 2.55, 6.60), Color(1.0, 0.94, 0.82), 1.8, 9.0)
	light.omni(va, "FoyerLamp", Vector3(0.00, 2.50, 1.50), Color(1.0, 0.88, 0.70), 1.2, 7.0)

	# beta：全屋停电。只留餐桌上一支蜡烛，用来让玩家察觉「这里已经不是原来那栋房子」。
	light.omni(vb, "Candle", Vector3(1.325, 1.00, 6.48), Color(1.0, 0.72, 0.40), 0.9, 5.0)

	# gamma：电灯亮着，但颜色发冷，而且停电时才该有的蜡烛同时也亮着。
	# 这个「不该同时成立」的组合是给玩家的第三层线索：不是没电，也不是正常。
	# 另外玄关灯刻意熄灭，制造不对称。
	light.omni(vc, "LivingLamp", Vector3(-4.50, 2.55, 6.60), Color(0.72, 0.82, 1.00), 2.0, 9.0)
	light.omni(vc, "DiningLamp", Vector3(1.30, 2.55, 6.60), Color(0.72, 0.82, 1.00), 2.0, 9.0)
	light.omni(vc, "KitchenLamp", Vector3(5.00, 2.55, 6.60), Color(0.78, 0.86, 1.00), 1.8, 9.0)
	light.omni(vc, "Candle", Vector3(1.325, 1.00, 6.48), Color(1.0, 0.72, 0.40), 0.9, 5.0)

	_build_hotspots(hotspots)

	return {
		"environment": env,
		"shared": shared,
		"variant_alpha": va,
		"variant_beta": vb,
		"variant_gamma": vc,
		"hotspots": hotspots,
	}


# ------------------------------------------------------------------ 地板与天花

func _build_floor_and_ceiling(parent: Node, floor_mat: Material, ceil_mat: Material) -> void:
	var w := OUT_X * 2.0
	# 地板：顶面 y = 0.20
	geom.solid(parent, "Floor", Vector3(w, 0.2, OUT_D),
			Vector3(0, FLOOR_Y - 0.1, OUT_Z_MID), floor_mat)
	# 天花板：底面 y = 0.20 + 2.7 = 2.90
	geom.solid(parent, "Ceiling", Vector3(w, 0.2, OUT_D),
			Vector3(0, FLOOR_Y + WALL_H + 0.1, OUT_Z_MID), ceil_mat)


# ------------------------------------------------------------------ 外墙

func _build_outer_walls(parent: Node, mat: Material) -> void:
	# 前墙（-Z，前门所在）：门洞 1.60，中心 x=0
	geom.wall_with_opening(parent, "WallFront", {
		"axis": "x",
		"center": Vector3(0, 0, OUT_Z0),
		"length": OUT_X * 2.0,
		"thickness": WALL_T_OUT,
		"height": WALL_H,
		"base_y": FLOOR_Y,
		"opening": {"offset": 0.0, "width": 1.6, "height": 2.1, "bottom": 0.0},
	}, mat)

	# 后墙（+Z）：露台推拉门 1.80，中心 x=-4.0
	geom.wall_with_opening(parent, "WallBack", {
		"axis": "x",
		"center": Vector3(0, 0, OUT_Z1),
		"length": OUT_X * 2.0,
		"thickness": WALL_T_OUT,
		"height": WALL_H,
		"base_y": FLOOR_Y,
		"opening": {"offset": -4.0, "width": 1.8, "height": 2.1, "bottom": 0.0},
	}, mat)

	# 西墙（-X）：无洞口
	geom.wall_with_opening(parent, "WallWest", {
		"axis": "z",
		"center": Vector3(-OUT_X, 0, OUT_Z_MID),
		"length": OUT_D,
		"thickness": WALL_T_OUT,
		"height": WALL_H,
		"base_y": FLOOR_Y,
	}, mat)

	# 东墙（+X）：侧门 1.20，中心 z=2.00
	# 该墙中心 z=4.70，故洞口相对偏移 = 2.00 - 4.70 = -2.70
	geom.wall_with_opening(parent, "WallEast", {
		"axis": "z",
		"center": Vector3(OUT_X, 0, OUT_Z_MID),
		"length": OUT_D,
		"thickness": WALL_T_OUT,
		"height": WALL_H,
		"base_y": FLOOR_Y,
		"opening": {"offset": -2.70, "width": 1.2, "height": 2.1, "bottom": 0.0},
	}, mat)


# ------------------------------------------------------------------ 内墙

## W0 横墙（z = 3.80）在核验报告里是一条，但它需要两个洞口：
## 玄关→主空间 1.60、厨房南北连通 3.00。
## wall_with_opening 每次只处理一个洞口，因此按房间边界拆成三段生成。
## 拆段的位置刻意选在墙体本身（x = -1.14 / 3.38 / 3.50），
## 不新增任何墙体，也不改变任何房间净尺寸。
func _build_inner_walls(parent: Node, mat: Material) -> void:
	# W0a：书房 + 卫生间北墙，x -6.50 ~ -1.14（长 5.36，中心 -3.82）
	#      书房门 1.20，中心 x = -4.20 → offset = -0.38
	geom.wall_with_opening(parent, "WallW0a", {
		"axis": "x",
		"center": Vector3(-3.82, 0, W0_Z),
		"length": 5.36,
		"thickness": WALL_T_IN,
		"height": WALL_H,
		"base_y": FLOOR_Y,
		"opening": {"offset": -0.38, "width": 1.2, "height": 2.1, "bottom": 0.0},
	}, mat)

	# W0b：玄关北墙，x -1.14 ~ 3.38（长 4.52，中心 1.12）
	#      玄关→主空间洞口 1.60，中心 x = 0 → offset = -1.12
	geom.wall_with_opening(parent, "WallW0b", {
		"axis": "x",
		"center": Vector3(1.12, 0, W0_Z),
		"length": 4.52,
		"thickness": WALL_T_IN,
		"height": WALL_H,
		"base_y": FLOOR_Y,
		"opening": {"offset": -1.12, "width": 1.6, "height": 2.1, "bottom": 0.0},
	}, mat)

	# W0c：厨房南段与主空间之间，x 3.50 ~ 6.50（长 3.00，中心 5.00）
	#      洞口 3.00 与段等宽 → 只剩门楣，等于全开
	geom.wall_with_opening(parent, "WallW0c", {
		"axis": "x",
		"center": Vector3(5.00, 0, W0_Z),
		"length": 3.00,
		"thickness": WALL_T_IN,
		"height": WALL_H,
		"base_y": FLOOR_Y,
		"opening": {"offset": 0.0, "width": 3.0, "height": 2.2, "bottom": 0.0},
	}, mat)

	# W1：书房 | 卫生间，x = -2.96，z 0.20 ~ 3.74（长 3.54，中心 z 1.97）
	geom.wall_with_opening(parent, "WallW1", {
		"axis": "z",
		"center": Vector3(W1_X, 0, SOUTH_Z_MID),
		"length": 3.54,
		"thickness": WALL_T_IN,
		"height": WALL_H,
		"base_y": FLOOR_Y,
	}, mat)

	# W2：卫生间 | 玄关，x = -1.20
	#     卫生间门 1.20，中心 z = 3.00 → offset = 3.00 - 1.97 = 1.03
	geom.wall_with_opening(parent, "WallW2", {
		"axis": "z",
		"center": Vector3(W2_X, 0, SOUTH_Z_MID),
		"length": 3.54,
		"thickness": WALL_T_IN,
		"height": WALL_H,
		"base_y": FLOOR_Y,
		"opening": {"offset": 1.03, "width": 1.2, "height": 2.1, "bottom": 0.0},
	}, mat)

	# W3：侧门通道 | 厨房南段，x = 3.44
	# 必须在 z=2.00 处开门洞，否则「侧门通道」到不了侧门——侧门开在东外墙 x=6.70，
	# 而那道外墙属于厨房南段一侧。若 W3 实心，去侧门就得绕主空间→W0c→厨房南段，
	# 与「侧门是从玄关侧直接出去的一条通路」这一设计意图不符。
	# 洞口 1.20，中心 z=2.00 → offset = 2.00 - 1.97 = 0.03
	geom.wall_with_opening(parent, "WallW3", {
		"axis": "z",
		"center": Vector3(W3_X, 0, SOUTH_Z_MID),
		"length": 3.54,
		"thickness": WALL_T_IN,
		"height": WALL_H,
		"base_y": FLOOR_Y,
		"opening": {"offset": 0.03, "width": 1.2, "height": 2.1, "bottom": 0.0},
	}, mat)


# ------------------------------------------------------------------ 门板

## 门板只是视觉占位，不带碰撞（碰撞由墙体洞口两侧的实墙负责）。
## 位置刻意避开通行带，避免挡住唯一通路。
func _build_door_panels(parent: Node, mat: Material) -> void:
	# 前门：贴在前墙内侧，向屋内开 90°，贴在洞口西侧墙上
	geom.box(parent, "FrontDoorPanel", Vector3(0.09, 2.05, 1.50),
			Vector3(-0.82, FLOOR_Y + 1.03, 0.30), mat)
	# 侧门：贴在东墙内侧
	geom.box(parent, "SideDoorPanel", Vector3(0.09, 2.05, 1.10),
			Vector3(OUT_X - 0.20, FLOOR_Y + 1.03, 2.68), mat)


# ------------------------------------------------------------------ 室外过渡区

## 门洞是通的，玩家完全可以在不按交互键的情况下直接走出去。
## 如果场景里门外没有地面，玩家会立刻掉进虚空（实测前进 5 秒后 y = -25.1）。
## 因此在房屋四周铺一层缓冲地面，并在前门外做门廊、后门外做露台、东侧做侧院，
## 让「走出去但还没传送」这个中间状态有落脚点。
func _build_outdoor(parent: Node, mat: Material) -> void:
	var patio_mat := geom.mat("outdoor", Color(0.40, 0.39, 0.36), 0.95)

	# 缓冲地面：顶面 y = 0.00，覆盖房屋四周并延伸到街道一带。
	# 范围 40 × 30（x -20~20，z -17~13）。实测教训：最初只铺 28×22 时，
	# 玩家从玄关一直朝前门方向走会在 z≈-7 处走出地面边缘并坠落（y 一路掉到 -67）。
	geom.solid(parent, "OutdoorGround", Vector3(40.0, 0.2, 30.0),
			Vector3(0, -0.1, -2.0), patio_mat)

	# 门廊：顶面 y = 0.10，前门外 z -2.2 ~ 0（室外比室内低一级台阶）
	geom.solid(parent, "Porch", Vector3(5.6, 0.3, 2.2),
			Vector3(0, -0.05, -1.1), patio_mat)

	# 露台：顶面 y = 0.20，与室内齐平，后门外 z 9.4 ~ 11.4
	geom.solid(parent, "Patio", Vector3(5.5, 0.2, 2.0),
			Vector3(-4.0, 0.1, 10.4), patio_mat)

	# 侧院：顶面 y = 0.20，东侧门外 x 6.7 ~ 9.6
	geom.solid(parent, "SideYard", Vector3(2.9, 0.2, 3.4),
			Vector3(8.15, 0.1, 1.8), patio_mat)


# ------------------------------------------------------------------ 热点

func _build_hotspots(parent: Node) -> void:
	# 三扇门各自携带门级落点与朝向。落点全部落在 house_exterior 场景的
	# 地面（顶面 y=0）上，且避开该场景的建筑、车、路缘：
	#   前门  → 车道口 (0, -2.6)，朝 -Z（朝前院/车道）
	#   侧门  → 房屋东侧 (8.6, 2.0)，朝 +X（朝东）
	#   露台  → 后院 (-4.0, 11.0)，朝 +Z（朝后院深处）
	# 朝向换算：PlayerController 的 forward 为 -Z，故 yaw=0 面朝 -Z，
	# yaw=-90° 面朝 +X，yaw=180° 面朝 +Z。
	_add_exit(parent, "FrontDoor", Vector3(0.0, FLOOR_Y + 0.95, 0.0),
			"前门", "house_exterior",
			Vector3(0.0, 0.05, -2.60), 0.0)

	_add_exit(parent, "SideDoor", Vector3(OUT_X - 0.15, FLOOR_Y + 0.95, 2.0),
			"侧门", "house_exterior",
			Vector3(8.60, 0.05, 2.00), -90.0)

	_add_exit(parent, "PatioDoor", Vector3(-4.0, FLOOR_Y + 0.95, OUT_Z1 - 0.15),
			"通往后院的推拉门", "house_exterior",
			Vector3(-4.00, 0.05, 11.00), 180.0)

	# 建筑内的可查看对象（灰盒阶段只有骨架，文字先描述结构而非陈设）
	# 注意：餐桌热点必须浮在桌面之上。原位置 (1.0, y=0.85, 6.5) 正好落在桌体内部
	# （桌体 x 0.80~1.85 / z 5.18~7.78 / 桌面顶 0.95），射线会先命中桌子而无法聚焦。
	_add_examine(parent, "DiningTableSpot", Vector3(1.325, FLOOR_Y + 0.95, 6.48),
			"餐桌的位置", "长桌上还留着杯子的水痕。八把椅子，有一把被推得离桌很远。")
	_add_examine(parent, "FireplaceSpot", Vector3(-5.0, FLOOR_Y + 0.95, 9.0),
			"壁炉", "壁炉是冷的。灰烬很平，像是很久没有人用过。")
	_add_examine(parent, "KitchenCounter", Vector3(6.2, FLOOR_Y + 0.85, 6.2),
			"厨房台面", "台面上有一圈没擦干净的水渍，是杯子被拿走时留下的。")
	_add_examine(parent, "StudyDesk", Vector3(-4.6, FLOOR_Y + 0.75, 1.2),
			"书桌", "桌上摊着一台开着的笔记本电脑，屏幕的光映在墙上。")

	# 门上的便签（CT-019 的钥匙之一）：对话闸门 fact_sticky_note 必须
	# 由亲眼检查授予，否则「问门上的便签」话题在真实游玩中永远锁死。
	# 位置在前门内侧，距玄关出生点 (0, 0.25, 1.6) 约 1.4 m，交互距离内。
	_add_examine(parent, "StickyNote", Vector3(0.55, FLOOR_Y + 0.95, 0.55),
			"门上的便签",
			"一张便签贴在门上，上面手写着一个数字：4。你不记得自己贴过它，也不认得这个笔迹。",
			"fact_sticky_note")


func _add_exit(parent: Node, node_name: String, pos: Vector3,
		display_name: String, target: String,
		spawn_pos: Vector3, spawn_yaw_deg: float) -> void:
	var spot := Area3D.new()
	spot.name = node_name
	spot.set_script(load("res://core/hotspot.gd"))
	spot.position = pos
	spot.display_name = display_name
	spot.action_kind = "exit"
	spot.target_location = target
	spot.use_target_spawn = true
	spot.target_spawn = spawn_pos
	spot.target_yaw_deg = spawn_yaw_deg
	_col(spot, Vector3(1.2, 2.2, 0.8))
	parent.add_child(spot)


func _add_examine(parent: Node, node_name: String, pos: Vector3,
		display_name: String, text: String, grants: String = "") -> void:
	var spot := Area3D.new()
	spot.name = node_name
	spot.set_script(load("res://core/hotspot.gd"))
	spot.position = pos
	spot.display_name = display_name
	spot.action_kind = "examine"
	spot.examine_text = text
	spot.grants_fact = grants
	_col(spot, Vector3(1.4, 1.6, 1.4))
	parent.add_child(spot)


func _col(spot: Area3D, size: Vector3) -> void:
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	spot.add_child(shape_node)
