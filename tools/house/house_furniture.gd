## HouseFurniture — 聚会住宅家具占位
##
## 坐标基于第三轮核验的 13.4 × 9.4 布局（docs/deliverables/MAP_REVIEW_ROUND3.md），
## 与 house_party.gd 的墙体划分严格对应：
##   客厅     x -6.50 ~ -1.00   z 3.86 ~ 9.20
##   餐厅     x -1.00 ~  3.40   z 3.86 ~ 9.20
##   厨房北段 x  3.40 ~  6.50   z 3.86 ~ 9.20
##   厨房南段 x  3.50 ~  6.50   z 0.20 ~ 3.74
##   玄关     x -1.14 ~  3.38   z 0.20 ~ 3.74
##   书房     x -6.50 ~ -3.02   z 0.20 ~ 3.74
##   卫生间   x -2.90 ~ -1.26   z 0.20 ~ 3.74
##
## 这些是**局部常量**，不引用 HouseParty 的类常量——互相引用会形成 cyclic reference。
##
## 三处修正（第三轮 2.6 节）已落实：
##   1 取消单人扶手椅（与茶几只剩 0.20 m，玩家不可通过）
##   2 餐桌整体南移，使北侧通道 ≥0.87
##   3 餐桌改沿 Z 向摆放，东侧留出 1.70 m 通往厨房
##
## 家具尺寸为设计值，非电影实测。

class_name HouseFurniture
extends RefCounted

const FLOOR := 0.20

var geom: HouseGeom = null
var props: HouseProps = null


func _init(geom_instance: HouseGeom, props_instance: HouseProps) -> void:
	geom = geom_instance
	props = props_instance


func populate(parent: Node) -> void:
	var m_wood := geom.mat("f_wood", Color(0.36, 0.27, 0.19), 0.88)
	var m_fabric := geom.mat("f_fabric", Color(0.28, 0.30, 0.34), 0.96)
	var m_wood2 := geom.mat("f_wood2", Color(0.44, 0.36, 0.27), 0.86)
	var m_stone := geom.mat("f_stone", Color(0.50, 0.49, 0.46), 0.80)
	var m_metal := geom.mat("f_metal", Color(0.52, 0.54, 0.56), 0.45, 0.55)
	var m_cab := geom.mat("f_cab", Color(0.40, 0.34, 0.28), 0.90)
	var m_screen := geom.mat("f_screen", Color(0.10, 0.11, 0.13), 0.30, 0.10)

	_living(parent, m_fabric, m_wood, m_stone, m_wood2, m_screen)
	_dining(parent, m_wood2)
	_kitchen(parent, m_cab, m_stone, m_metal)
	_study(parent, m_wood, m_metal)
	_foyer(parent, m_cab)
	_small_props(parent)
	# 注意：这里不再添加灯光。房屋已由 house_lighting.gd 提供
	# 双世界灯光（α 供电 / β 停电，共 9 盏变体灯）。
	# 早期在此另加 6 盏常亮灯会导致场景共 15 盏灯、画面严重过曝。


# ------------------------------------------------------------------ 客厅

func _living(parent: Node, m_fabric: Material, m_wood: Material,
		m_stone: Material, m_wood2: Material, m_screen: Material) -> void:
	var h := geom.node(parent, "FurnitureLiving")

	# 电视柜：贴北墙 z=9.20，占 x -6.35 ~ -4.75
	# 刻意西移：露台推拉门在 x=-4.0，电视柜若放 -5.0~-3.4 会正好堵死通往露台的路。
	props.cabinet(h, "TVCabinet", Vector3(-5.55, FLOOR, 8.975),
			Vector3(1.60, 0.45, 0.45), 0.0, m_wood)
	props.cabinet(h, "TV", Vector3(-5.55, FLOOR + 0.45, 8.98),
			Vector3(1.05, 0.62, 0.09), 0.0, m_screen)

	# 三人沙发：面朝北（看电视），靠背在南侧。占 x -5.60~-3.50，z 4.875~5.825
	props.sofa(h, "Sofa3", Vector3(-4.55, FLOOR, 5.35), 2.10, PI, m_fabric)

	# 咖啡桌：x -5.30~-4.10，z 6.20~6.90
	props.table(h, "CoffeeTable", Vector3(-4.70, FLOOR, 6.55),
			Vector3(1.20, 0.40, 0.70), 0.0, m_wood2)

	# 地毯：无碰撞装饰
	props.rug(h, "LivingRug", Vector3(-4.70, FLOOR, 6.30),
			Vector2(3.40, 2.80), 0.0, m_stone)

	# 壁炉：贴西墙 x=-6.50，凸出 0.44
	props.cabinet(h, "Fireplace", Vector3(-6.28, FLOOR, 7.20),
			Vector3(0.44, 1.15, 1.60), 0.0, m_stone)


# ------------------------------------------------------------------ 餐厅

## 餐桌沿 Z 向摆放（修正 3），并整体东移 0.70。
## 东移的原因：玄关洞口在 x=0，正对餐厅。餐桌若居中摆放，西侧餐椅会正好挡在
## 玩家进屋的正前方（实测 x=0 处 z=5.04~5.20 被挡）。
## 东移后整体占 x 0.25~2.40，z 4.63~8.33：
##   正前方 x -0.30~0.30 空出，东侧余 2.40~3.40 = 1.00，北侧余 0.87
func _dining(parent: Node, mat: Material) -> void:
	var h := geom.node(parent, "FurnitureDining")

	var table_cx := 1.325
	var table_cz := 6.48
	props.table(h, "DiningTable", Vector3(table_cx, FLOOR, table_cz),
			Vector3(1.05, 0.75, 2.60), 0.0, mat)

	var seat_z: Array = [5.68, 6.48, 7.28]
	var i := 0
	for z in seat_z:
		props.chair(h, "ChairW%d" % i, Vector3(0.475, FLOOR, z), -PI * 0.5, mat)
		props.chair(h, "ChairE%d" % i, Vector3(2.175, FLOOR, z), PI * 0.5, mat)
		i += 1

	props.chair(h, "ChairS", Vector3(table_cx, FLOOR, 4.855), PI, mat)
	props.chair(h, "ChairN", Vector3(table_cx, FLOOR, 8.105), 0.0, mat)


# ------------------------------------------------------------------ 厨房

## 北段（x 3.40~6.50 / z 3.86~9.20）：L 台面沿北墙与东墙，通道 2.50 m。
## 南段（x 3.50~6.50 / z 0.20~3.74）：岛台贴东墙，西侧留 1.25 m 通道。
##
## 3.10 m 宽的北段若同时塞台面(0.6) + 通道(1.4) + 岛台(0.9) 只剩 0.20 m 余量，
## 因此岛台放到更宽的南段，避免制造过不去的窄缝。这是刻意的取舍，非遗漏。
func _kitchen(parent: Node, m_cab: Material, m_stone: Material, m_metal: Material) -> void:
	var h := geom.node(parent, "FurnitureKitchen")

	props.cabinet(h, "CounterNorth", Vector3(5.35, FLOOR, 8.90),
			Vector3(2.30, 0.90, 0.60), 0.0, m_cab)
	props.cabinet(h, "CounterEast", Vector3(6.20, FLOOR, 6.23),
			Vector3(0.60, 0.90, 4.74), 0.0, m_cab)
	props.fridge(h, "Fridge", Vector3(3.80, FLOOR, 8.85), 0.0, m_metal)

	# 岛台（厨房南段，贴东墙并贴南墙）：x 4.75~6.35，z 0.20~1.10
	# 两次修正的由来：侧门开在东墙 z=2.00，岛台最初占 z 1.40~2.30 直接横在通道上；
	# 南移到 z 1.00~1.90 后，玩家通行带（z 1.70~2.30）仍与岛台北边重叠。
	# 最终贴南墙放置，z 1.10~3.74 整段让开，侧门通道彻底畅通。
	props.island(h, "Island", Vector3(5.55, FLOOR, 0.65),
			Vector3(1.60, 0.92, 0.90), 0.0, m_cab, m_stone)


# ------------------------------------------------------------------ 书房

func _study(parent: Node, mat: Material, m_metal: Material) -> void:
	var h := geom.node(parent, "FurnitureStudy")

	# 书桌：贴西墙，占 x -6.30~-4.70，z 0.70~1.70
	props.table(h, "Desk", Vector3(-5.50, FLOOR, 1.20),
			Vector3(0.80, 0.75, 1.00), 0.0, mat)
	props.cabinet(h, "Laptop", Vector3(-5.50, FLOOR + 0.75, 1.20),
			Vector3(0.34, 0.03, 0.24), 0.0, m_metal)

	# 书架：贴南墙 z=0.20
	props.cabinet(h, "Bookshelf", Vector3(-4.10, FLOOR, 0.42),
			Vector3(1.60, 1.80, 0.36), 0.0, mat)


# ------------------------------------------------------------------ 玄关与卫生间

func _foyer(parent: Node, mat: Material) -> void:
	var h := geom.node(parent, "FurnitureFoyer")

	props.cabinet(h, "ShoeCabinet", Vector3(-0.92, FLOOR, 0.80),
			Vector3(0.36, 0.95, 1.00), 0.0, mat)

	props.cabinet(h, "Vanity", Vector3(-2.62, FLOOR, 0.95),
			Vector3(0.50, 0.85, 1.00), 0.0, mat)
	props.cabinet(h, "Toilet", Vector3(-2.62, FLOOR, 3.20),
			Vector3(0.48, 0.42, 0.60), 0.0, mat)

# ------------------------------------------------------------------ 生活小道具

## 杯子、盘子、书籍、装饰物等桌面杂物。
## 让灰盒场景有生活痕迹——不是随机堆放，而是按住宅逻辑摆放。
func _small_props(parent: Node) -> void:
	var h := geom.node(parent, "SmallProps")

	# 材质
	var m_cup := geom.mat("cup", Color(0.92, 0.90, 0.85), 0.4)
	var m_plate := geom.mat("plate", Color(0.88, 0.86, 0.82), 0.3)
	var m_book := geom.mat("book", Color(0.55, 0.30, 0.20), 0.7)
	var m_book2 := geom.mat("book2", Color(0.25, 0.35, 0.55), 0.7)
	var m_glass := geom.mat("glass", Color(0.75, 0.85, 0.90), 0.1, 0.3)
	var m_candle := geom.mat("candle", Color(0.95, 0.88, 0.70), 0.6)
	var m_flower := geom.mat("flower", Color(0.85, 0.45, 0.55), 0.6)
	var m_vase := geom.mat("vase", Color(0.55, 0.65, 0.60), 0.3)

	# ---- 餐厅桌面（table_cx=1.325, table_cz=6.48, 桌面 y≈0.95）
	var tbl_y := FLOOR + 0.77  # 桌面顶
	# 三个杯子（不同位置）
	geom.box(h, "Cup1", Vector3(0.08, 0.10, 0.08), Vector3(1.1, tbl_y + 0.05, 6.2), m_cup)
	geom.box(h, "Cup2", Vector3(0.08, 0.10, 0.08), Vector3(1.6, tbl_y + 0.05, 6.7), m_cup)
	geom.box(h, "Cup3", Vector3(0.08, 0.10, 0.08), Vector3(1.4, tbl_y + 0.05, 6.4), m_cup)
	# 两个盘子
	geom.box(h, "Plate1", Vector3(0.22, 0.02, 0.22), Vector3(1.0, tbl_y + 0.01, 6.5), m_plate)
	geom.box(h, "Plate2", Vector3(0.22, 0.02, 0.22), Vector3(1.7, tbl_y + 0.01, 6.3), m_plate)
	# 玻璃杯
	geom.box(h, "Glass1", Vector3(0.06, 0.12, 0.06), Vector3(1.5, tbl_y + 0.06, 6.1), m_glass)

	# ---- 客厅茶几（x≈-4.70, z≈6.55, 顶面 y≈FLOOR+0.38）
	var ct_y := FLOOR + 0.40
	geom.box(h, "Book1", Vector3(0.16, 0.03, 0.22), Vector3(-4.90, ct_y + 0.015, 6.45), m_book, 0.3)
	geom.box(h, "Book2", Vector3(0.15, 0.025, 0.20), Vector3(-4.88, ct_y + 0.042, 6.47), m_book2, 0.15)
	geom.box(h, "Candle", Vector3(0.06, 0.10, 0.06), Vector3(-4.55, ct_y + 0.05, 6.65), m_candle)

	# ---- 厨房台面（CounterNorth y≈FLOOR+0.90）
	var kn_y := FLOOR + 0.91
	geom.box(h, "KitchenGlass1", Vector3(0.07, 0.12, 0.07), Vector3(5.1, kn_y + 0.06, 8.7), m_glass)
	geom.box(h, "KitchenPlate1", Vector3(0.24, 0.02, 0.24), Vector3(5.5, kn_y + 0.01, 8.9), m_plate)
	geom.box(h, "KitchenBowl", Vector3(0.14, 0.06, 0.14), Vector3(5.8, kn_y + 0.03, 8.8), m_cup)

	# ---- 书房桌面（Desk y≈FLOOR+0.75）
	var dt_y := FLOOR + 0.77
	geom.box(h, "DeskBook1", Vector3(0.14, 0.03, 0.20), Vector3(-5.80, dt_y + 0.015, 1.05), m_book, 0.2)
	geom.box(h, "DeskPen", Vector3(0.015, 0.015, 0.14), Vector3(-5.35, dt_y + 0.008, 1.30), m_cup, 0.5)

	# ---- 花瓶（餐桌上，聚会感）
	geom.box(h, "Vase", Vector3(0.10, 0.16, 0.10), Vector3(1.325, tbl_y + 0.08, 6.48), m_vase)
	geom.box(h, "Flower", Vector3(0.14, 0.10, 0.14), Vector3(1.325, tbl_y + 0.21, 6.48), m_flower)

	# ---- 门旁小物件（玄关）
	geom.box(h, "UmbrellaStand", Vector3(0.12, 0.40, 0.12), Vector3(0.60, FLOOR + 0.20, 0.80), m_vase)
