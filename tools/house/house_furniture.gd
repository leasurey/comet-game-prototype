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
	_wing(parent, m_wood, m_cab)
	_small_props(parent)
	# 注意：这里不再添加灯光。房屋已由 house_lighting.gd 提供
	# 双世界灯光（α 供电 / β 停电，共 9 盏变体灯）。
	# 早期在此另加 6 盏常亮灯会导致场景共 15 盏灯、画面严重过曝。


# ------------------------------------------------------------------ 客厅

func _living(parent: Node, m_fabric: Material, m_wood: Material,
		m_stone: Material, m_wood2: Material, m_screen: Material) -> void:
	var h := geom.node(parent, "FurnitureLiving")
	var m_handle := geom.mat("f_handle", Color(0.63, 0.61, 0.57), 0.36, 0.80)
	var m_shade := geom.mat("f_shade", Color(0.88, 0.80, 0.64), 0.95)
	var m_bulb := geom.mat("f_bulb", Color(1.00, 0.94, 0.78), 0.35,
		0.0, Color(1.0, 0.90, 0.70), 1.4)
	var m_art := geom.mat("f_art", Color(0.30, 0.35, 0.42), 0.90)
	var m_rug := geom.mat("f_rug", Color(0.34, 0.30, 0.29), 0.99)

	# 电视柜 + 电视：贴北墙（墙内表面 z=9.30），占 x -6.35 ~ -4.75
	# 刻意西移：露台推拉门在 x=-4.0，电视柜若放 -5.0~-3.4 会正好堵死通往露台的路。
	props.tv_cabinet(h, "TVCabinet", Vector3(-5.55, FLOOR, 8.98),
			Vector3(1.60, 0.52, 0.45), 0.0, m_wood, m_handle)
	props.tv(h, "TV", Vector3(-5.55, FLOOR + 0.93, 9.06), 1.06, 0.60, 0.0,
			m_screen, m_screen)

	# 三人沙发：面朝北（看电视），靠背在南侧
	props.sofa(h, "Sofa3", Vector3(-4.55, FLOOR, 5.35), 2.10, PI, m_fabric)

	# 咖啡桌
	props.coffee_table(h, "CoffeeTable", Vector3(-4.70, FLOOR, 6.55),
			Vector3(1.20, 0.40, 0.70), 0.0, m_wood2)

	# 地毯（纯装饰，无碰撞）
	props.rug(h, "LivingRug", Vector3(-4.70, FLOOR, 6.30),
			Vector2(3.40, 2.80), 0.0, m_rug)

	# 壁炉：贴西墙（墙内表面 x=-6.60），正面朝东（+X）
	props.fireplace(h, "Fireplace", Vector3(-6.34, FLOOR, 7.20), 1.60, -PI * 0.5,
			m_stone,
			geom.mat("f_firebox", Color(0.07, 0.06, 0.055), 0.98),
			geom.mat("f_hearth", Color(0.40, 0.38, 0.36), 0.86))

	# 落地灯：沙发与壁炉之间的角落，不挡主通道
	props.floor_lamp(h, "FloorLamp", Vector3(-3.30, FLOOR, 7.85), 1.45,
			m_shade, m_handle, m_bulb)

	# 西墙挂画（正对沙发）
	props.wall_art(h, "WallArtW", Vector3(-6.56, FLOOR + 1.55, 6.20),
			Vector2(0.80, 1.05), -PI * 0.5, m_wood2, m_art)


# ------------------------------------------------------------------ 餐厅

## 餐桌沿 Z 向摆放，整体东移 0.70。
## 东移原因：玄关洞口在 x=0，正对餐厅。餐桌若居中，西侧餐椅会挡在玩家进屋正前方。
## 东移后整体占 x 0.25~2.40，z 4.63~8.33：正前方 x -0.30~0.30 空出，
## 东侧余 1.00，北侧余 0.87。
func _dining(parent: Node, mat: Material) -> void:
	var h := geom.node(parent, "FurnitureDining")
	var m_handle := geom.mat("f_handle", Color(0.63, 0.61, 0.57), 0.36, 0.80)

	var table_cx := 1.325
	var table_cz := 6.48
	props.table(h, "DiningTable", Vector3(table_cx, FLOOR, table_cz),
			Vector3(1.05, 0.75, 2.60), 0.0, mat)

	# 椅子朝向：正面(-Z) 必须转向餐桌。
	# 西侧 → 朝东(+X) 需 -90°；东侧 → 朝西(-X) 需 +90°；南侧 → 朝北(+Z) 需 180°；北侧 → 朝南 = 0°。
	var seat_z: Array = [5.68, 6.48, 7.28]
	var i := 0
	for z in seat_z:
		props.chair(h, "ChairW%d" % i, Vector3(0.475, FLOOR, z), -PI * 0.5, mat)
		props.chair(h, "ChairE%d" % i, Vector3(2.175, FLOOR, z), PI * 0.5, mat)
		i += 1

	props.chair(h, "ChairS", Vector3(table_cx, FLOOR, 4.855), PI, mat)
	props.chair(h, "ChairN", Vector3(table_cx, FLOOR, 8.105), 0.0, mat)

	# 餐桌上方吊灯（视觉件，实际照明由 house_lighting 提供）
	geom.cyl(h, "PendantCord", 0.008, 0.55, Vector3(table_cx, 2.45, table_cz),
			geom.mat("f_cord", Color(0.10, 0.10, 0.10), 0.7))
	geom.cyl(h, "PendantShade", 0.22, 0.16, Vector3(table_cx, 2.10, table_cz),
			geom.mat("f_pendant", Color(0.82, 0.74, 0.58), 0.9))

	# 北墙挂画
	props.wall_art(h, "WallArtN", Vector3(1.325, FLOOR + 1.60, 9.26),
			Vector2(1.10, 0.72), PI, geom.mat("f_art2", Color(0.22, 0.19, 0.17), 0.9),
			geom.mat("f_art3", Color(0.52, 0.44, 0.36), 0.9))


# ------------------------------------------------------------------ 厨房

## 北段（x 3.40~6.50 / z 3.86~9.20）：L 形台面沿北墙与东墙。
## 南段（x 3.50~6.50 / z 0.20~3.74）：岛台贴东墙，西侧留通道。
func _kitchen(parent: Node, m_cab: Material, m_stone: Material, m_metal: Material) -> void:
	var h := geom.node(parent, "FurnitureKitchen")
	var m_handle := geom.mat("f_handle", Color(0.63, 0.61, 0.57), 0.36, 0.80)
	var m_burner := geom.mat("f_burner", Color(0.13, 0.13, 0.14), 0.55)
	var m_basin := geom.mat("f_basin", Color(0.42, 0.44, 0.46), 0.30, 0.65)
	var m_screen := geom.mat("f_screen", Color(0.10, 0.11, 0.13), 0.30, 0.10)

	# 北墙台面：贴北墙（内表面 z=9.30），正面朝南
	props.base_cabinet(h, "CounterNorth", Vector3(5.35, FLOOR, 8.96),
			Vector3(2.30, 0.92, 0.62), 0.0, m_cab, m_stone, m_handle, 4)

	# 东墙台面：贴东墙（内表面 x=6.60），正面朝西
	props.base_cabinet(h, "CounterEast", Vector3(6.27, FLOOR, 6.23),
			Vector3(4.74, 0.92, 0.62), PI * 0.5, m_cab, m_stone, m_handle, 6)

	# 北墙吊柜
	props.upper_cabinet(h, "UpperNorth", Vector3(5.35, FLOOR + 1.52, 9.14),
			Vector3(2.30, 0.66, 0.34), 0.0, m_cab, m_handle, 3)

	# 灶台（嵌在北墙台面上）
	props.stove(h, "Stove", Vector3(4.62, FLOOR, 8.94), 0.62, 0.0,
			m_cab, m_stone, m_metal, m_burner)

	# 水槽（嵌在北墙台面东侧）
	props.sink(h, "Sink", Vector3(5.98, FLOOR, 8.96), 0.52, 0.42, 0.92, 0.0,
			m_metal, m_basin)

	# 冰箱：靠北墙西端
	props.fridge(h, "Fridge", Vector3(3.80, FLOOR, 8.92), 0.0, m_metal, m_handle)

	# 岛台（厨房南段，贴南墙）：
	# 侧门开在东墙 z=2.00，岛台若占 z 1.40~2.30 会横在通道上；最终贴南墙放置。
	props.island(h, "Island", Vector3(5.55, FLOOR, 0.65),
			Vector3(1.60, 0.92, 0.90), 0.0, m_cab, m_stone, m_handle)


# ------------------------------------------------------------------ 书房

func _study(parent: Node, mat: Material, m_metal: Material) -> void:
	var h := geom.node(parent, "FurnitureStudy")
	var m_handle := geom.mat("f_handle", Color(0.63, 0.61, 0.57), 0.36, 0.80)
	var m_screen := geom.mat("f_screen", Color(0.10, 0.11, 0.13), 0.30, 0.10)

	# 书桌：贴西墙纵向摆放（旋转 90°，桌面 1.40 沿 Z）。
	# 注意：不要横放在房间中部——会把书房走道挤窄，navmesh 被 agent 半径腐蚀后
	# 书房与卫生间的连通性会间歇性失败。
	props.desk(h, "Desk", Vector3(-6.00, FLOOR, 1.40), PI * 0.5, mat, m_handle)
	props.laptop(h, "Laptop", Vector3(-6.00, FLOOR + 0.75, 1.40), PI * 0.5, m_metal, m_screen)

	# 书架：贴南墙（内表面 z=0.30），背面朝墙 → 旋转 180°
	var book_mats: Array = [
		geom.mat("f_book1", Color(0.42, 0.20, 0.16), 0.86),
		geom.mat("f_book2", Color(0.20, 0.28, 0.40), 0.86),
		geom.mat("f_book3", Color(0.26, 0.32, 0.24), 0.86),
		geom.mat("f_book4", Color(0.52, 0.44, 0.30), 0.86),
		geom.mat("f_book5", Color(0.30, 0.26, 0.30), 0.86),
	]
	props.bookshelf(h, "Bookshelf", Vector3(-4.10, FLOOR, 0.52),
			Vector3(1.60, 1.80, 0.36), PI, mat, book_mats)

	# 台灯
	props.floor_lamp(h, "DeskLamp", Vector3(-6.10, FLOOR + 0.75, 2.00), 0.34,
			geom.mat("f_shade", Color(0.88, 0.80, 0.64), 0.95), m_metal,
			geom.mat("f_bulb", Color(1.00, 0.94, 0.78), 0.35,
				0.0, Color(1.0, 0.90, 0.70), 1.4))


# ------------------------------------------------------------------ 玄关与卫生间

func _foyer(parent: Node, mat: Material) -> void:
	var h := geom.node(parent, "FurnitureFoyer")
	var m_handle := geom.mat("f_handle", Color(0.63, 0.61, 0.57), 0.36, 0.80)
	var m_porcelain := geom.mat("f_porcelain", Color(0.86, 0.86, 0.84), 0.28)
	var m_top := geom.mat("f_bath_top", Color(0.55, 0.54, 0.52), 0.55)
	var m_mirror := geom.mat("f_mirror", Color(0.62, 0.66, 0.70), 0.10, 0.85)

	# 鞋柜：贴玄关南侧
	props.cabinet(h, "ShoeCabinet", Vector3(-0.92, FLOOR, 0.80),
			Vector3(0.36, 0.95, 1.00), 0.0, mat)

	# 洗手台：贴卫生间西墙，正面朝东
	props.vanity(h, "Vanity", Vector3(-2.60, FLOOR, 1.15), -PI * 0.5,
			mat, m_top, m_handle, m_mirror)

	# 马桶：贴卫生间西墙，正面朝东。
	# 注意：卫生间门在 z 2.40~3.60，马桶原先摆在 z=3.20 正好堵住门洞，
	# 导致「卫生间→书房」的寻路间歇性失败。移到南端。
	props.toilet(h, "Toilet", Vector3(-2.62, FLOOR, 0.52), -PI * 0.5,
			m_porcelain, m_handle)


# ------------------------------------------------------------------ 西翼（走廊/主卧/浴室/洗衣房）

## 依据：电影确认「走廊连接主空间与卧室/浴室」，但未展示户型细节，
## 房间划分与摆位均为 GAME_LAYOUT 原创设计。
func _wing(parent: Node, m_wood: Material, m_cab: Material) -> void:
	var h := geom.node(parent, "FurnitureWing")
	var m_handle := geom.mat("f_handle", Color(0.63, 0.61, 0.57), 0.36, 0.80)
	var m_sheet := geom.mat("f_sheet", Color(0.60, 0.62, 0.66), 0.96)
	var m_pillow := geom.mat("f_pillow", Color(0.82, 0.82, 0.80), 0.96)
	var m_porcelain := geom.mat("f_porcelain", Color(0.86, 0.86, 0.84), 0.28)
	var m_top := geom.mat("f_bath_top", Color(0.55, 0.54, 0.52), 0.55)
	var m_mirror := geom.mat("f_mirror", Color(0.62, 0.66, 0.70), 0.10, 0.85)
	var m_steel := geom.mat("f_steel", Color(0.66, 0.68, 0.70), 0.32, 0.75)
	var m_glass := geom.mat("f_glass", Color(0.55, 0.62, 0.66), 0.12, 0.20)

	# ---- 主卧（x -11.14~-8.11，z 5.04~9.14）
	# 床靠北墙，床头朝 +Z
	props.bed(h, "Bed", Vector3(-9.70, FLOOR, 8.00), Vector2(1.65, 2.05), 0.0,
			m_wood, m_sheet, m_pillow)
	# 床头柜（床西侧）
	props.nightstand(h, "Nightstand", Vector3(-10.86, FLOOR, 8.72), 0.0, m_wood, m_handle)
	# 衣柜：贴西墙，正面朝东
	props.wardrobe(h, "Wardrobe", Vector3(-10.84, FLOOR, 6.10),
			Vector3(1.20, 2.00, 0.60), -PI * 0.5, m_wood, m_handle)
	# 梳妆台/边柜（贴南墙一侧）
	props.cabinet(h, "BedroomDresser", Vector3(-9.10, FLOOR, 5.30),
			Vector3(1.10, 0.80, 0.42), PI, m_wood)

	# ---- 浴室（x -11.14~-8.11，z 2.58~4.92）
	props.toilet(h, "WingToilet", Vector3(-10.86, FLOOR, 3.30), -PI * 0.5,
			m_porcelain, m_handle)
	props.vanity(h, "WingVanity", Vector3(-10.86, FLOOR, 4.42), -PI * 0.5,
			m_cab, m_top, m_handle, m_mirror)
	# 浴缸（贴北墙）：箱体 + 内胆
	geom.box(h, "BathtubBody", Vector3(1.55, 0.52, 0.72),
		Vector3(-9.10, FLOOR + 0.26, 4.60), m_porcelain)
	geom.box(h, "BathtubInner", Vector3(1.35, 0.20, 0.54),
		Vector3(-9.10, FLOOR + 0.44, 4.60), geom.mat("f_tub_inner", Color(0.74, 0.74, 0.72), 0.30))
	geom.box(h, "BathtubTap", Vector3(0.05, 0.16, 0.05),
		Vector3(-9.80, FLOOR + 0.60, 4.35), m_steel)

	# ---- 洗衣房（x -11.14~-8.11，z 0.26~2.46）
	props.washer(h, "Washer", Vector3(-10.82, FLOOR, 0.72), -PI * 0.5,
			m_cab, m_steel, m_glass)
	props.cabinet(h, "LaundryCabinet", Vector3(-10.86, FLOOR, 1.95),
			Vector3(0.45, 0.90, 0.90), -PI * 0.5, m_cab)


# ------------------------------------------------------------------ 生活小道具

## 杯子、盘子、书籍、装饰物等桌面杂物。
## 让场景有生活痕迹——不是随机堆放，而是按住宅逻辑摆放。
func _small_props(parent: Node) -> void:
	var h := geom.node(parent, "SmallProps")

	var m_cup := geom.mat("p_cup", Color(0.92, 0.90, 0.85), 0.40)
	var m_plate := geom.mat("p_plate", Color(0.88, 0.86, 0.82), 0.30)
	var m_book := geom.mat("p_book", Color(0.55, 0.30, 0.20), 0.70)
	var m_book2 := geom.mat("p_book2", Color(0.25, 0.35, 0.55), 0.70)
	var m_glass := geom.mat("p_glass", Color(0.75, 0.85, 0.90), 0.10, 0.30)
	var m_candle := geom.mat("p_candle", Color(0.95, 0.88, 0.70), 0.60)
	var m_flower := geom.mat("p_flower", Color(0.85, 0.45, 0.55), 0.60)
	var m_vase := geom.mat("p_vase", Color(0.55, 0.65, 0.60), 0.30)
	var m_cloth := geom.mat("p_cloth", Color(0.78, 0.74, 0.68), 0.95)

	# ---- 餐桌桌面（桌面顶 y = FLOOR + 0.75）
	var tbl_y := FLOOR + 0.75
	# 桌旗
	geom.box(h, "TableRunner", Vector3(0.34, 0.006, 2.10),
		Vector3(1.325, tbl_y + 0.003, 6.48), m_cloth)
	# 杯子（每人一位，分东西两侧）
	var cup_spots: Array = [
		Vector3(0.78, 0, 5.72), Vector3(0.78, 0, 6.52), Vector3(0.78, 0, 7.32),
		Vector3(1.87, 0, 5.72), Vector3(1.87, 0, 6.52), Vector3(1.87, 0, 7.32),
	]
	var ci := 0
	for p in cup_spots:
		geom.box(h, "Cup%d" % ci, Vector3(0.075, 0.095, 0.075),
			Vector3(p.x, tbl_y + 0.048, p.z), m_cup)
		ci += 1
	# 盘子
	geom.box(h, "Plate1", Vector3(0.22, 0.015, 0.22), Vector3(1.02, tbl_y + 0.008, 5.95), m_plate)
	geom.box(h, "Plate2", Vector3(0.22, 0.015, 0.22), Vector3(1.62, tbl_y + 0.008, 7.05), m_plate)
	geom.box(h, "Plate3", Vector3(0.22, 0.015, 0.22), Vector3(1.02, tbl_y + 0.008, 7.10), m_plate)
	# 玻璃杯
	geom.box(h, "Glass1", Vector3(0.06, 0.115, 0.06), Vector3(1.52, tbl_y + 0.058, 5.80), m_glass)
	# 花瓶 + 花
	geom.box(h, "Vase", Vector3(0.10, 0.17, 0.10), Vector3(1.325, tbl_y + 0.085, 6.48), m_vase)
	geom.box(h, "Flower", Vector3(0.15, 0.11, 0.15), Vector3(1.325, tbl_y + 0.22, 6.48), m_flower)
	# 蜡烛
	geom.box(h, "TableCandle", Vector3(0.05, 0.09, 0.05),
		Vector3(1.325, tbl_y + 0.045, 5.45), m_candle)

	# ---- 茶几（桌面顶 y = FLOOR + 0.40）
	var ct_y := FLOOR + 0.40
	geom.box(h, "Book1", Vector3(0.16, 0.03, 0.22), Vector3(-4.90, ct_y + 0.015, 6.45), m_book, 0.3)
	geom.box(h, "Book2", Vector3(0.15, 0.025, 0.20), Vector3(-4.88, ct_y + 0.042, 6.47), m_book2, 0.15)
	geom.box(h, "Candle", Vector3(0.06, 0.10, 0.06), Vector3(-4.55, ct_y + 0.05, 6.65), m_candle)
	geom.box(h, "Coaster", Vector3(0.10, 0.008, 0.10), Vector3(-4.42, ct_y + 0.004, 6.35), m_cloth)
	geom.box(h, "Mug", Vector3(0.07, 0.09, 0.07), Vector3(-4.42, ct_y + 0.049, 6.35), m_cup)

	# ---- 厨房台面（台面顶 y = FLOOR + 0.92）
	var kn_y := FLOOR + 0.92
	geom.box(h, "KitchenGlass1", Vector3(0.07, 0.12, 0.07), Vector3(5.35, kn_y + 0.06, 9.02), m_glass)
	geom.box(h, "KitchenPlate1", Vector3(0.24, 0.02, 0.24), Vector3(5.62, kn_y + 0.01, 8.98), m_plate)
	geom.box(h, "KitchenBowl", Vector3(0.14, 0.06, 0.14), Vector3(5.30, kn_y + 0.03, 8.86), m_cup)
	# 砧板
	geom.box(h, "CuttingBoard", Vector3(0.34, 0.025, 0.24), Vector3(5.05, kn_y + 0.013, 8.90), m_book)

	# ---- 书房桌面（桌面顶 y = FLOOR + 0.75）
	var dt_y := FLOOR + 0.75
	geom.box(h, "DeskBook1", Vector3(0.14, 0.03, 0.20), Vector3(-4.72, dt_y + 0.015, 1.28), m_book, 0.2)
	geom.box(h, "DeskPen", Vector3(0.012, 0.012, 0.14), Vector3(-4.95, dt_y + 0.006, 1.42), m_cup, 0.5)
	geom.box(h, "DeskMug", Vector3(0.07, 0.09, 0.07), Vector3(-5.52, dt_y + 0.045, 1.42), m_cup)

	# ---- 玄关：伞架 + 钥匙盘
	geom.box(h, "UmbrellaStand", Vector3(0.12, 0.40, 0.12), Vector3(0.60, FLOOR + 0.20, 0.80), m_vase)
	geom.box(h, "KeyTray", Vector3(0.16, 0.02, 0.12), Vector3(-0.92, FLOOR + 0.96, 0.80), m_cloth)
	geom.box(h, "Keys", Vector3(0.05, 0.01, 0.03), Vector3(-0.94, FLOOR + 0.975, 0.80), m_book)

	# ---- 壁炉台摆件
	geom.box(h, "MantelPhoto", Vector3(0.16, 0.20, 0.02),
		Vector3(-6.34, FLOOR + 1.35, 6.62), m_book2)
	geom.box(h, "MantelCandle", Vector3(0.05, 0.12, 0.05),
		Vector3(-6.34, FLOOR + 1.31, 7.70), m_candle)
