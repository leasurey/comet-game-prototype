## HouseProps — 家具构建库
##
## 职责边界：
##   只负责「造一件家具」，不知道它放在哪个房间、属于哪个世界。
##   具体摆放由 tools/house/house_furniture.gd 决定。
##
## 设计取向（第二轮重写）：
##   1. 每件家具 = 1 个不可见碰撞体 + 若干纯视觉构件。
##      碰撞体是整件家具的「footprint」，不与视觉细节一一对应，
##      这样既保证玩家撞得到家具，又不会让 navmesh 被碎小零件污染。
##   2. 所有构件在 holder 的**局部坐标**里摆放，朝向由 holder.rotation.y 统一给出。
##      （旧实现把 yaw 传给每个 box，但 geom.box 的 yaw 只旋转盒子自身、
##        不旋转它的偏移量 —— 于是 facing_yaw≠0 的家具其实没有朝向目标。
##        这是餐椅/沙发看起来位置错乱的真实原因。）
##   3. 材质从主材质派生明暗变体，按 (材质, 系数) 缓存，避免材质爆炸。
##
## 局部坐标约定：家具「正面」朝 -Z，背面朝 +Z，与 Godot 默认朝向一致。
##
## 离线构建脚本的一部分，不进入运行时依赖。

class_name HouseProps
extends RefCounted

var geom: HouseGeom = null

## 派生素材缓存：key = "材质实例id|系数"
var _tone_cache: Dictionary = {}


func _init(geom_instance: HouseGeom) -> void:
	geom = geom_instance


# ------------------------------------------------------------------ 内部工具

## 派生明暗变体（用于坐垫比框架亮一点、台面比柜体亮一点这类层次）。
func _tone(mat: Material, factor: float) -> Material:
	if not (mat is StandardMaterial3D):
		return mat
	var key := "%d|%.2f" % [mat.get_instance_id(), factor]
	if _tone_cache.has(key):
		return _tone_cache[key]
	var base := mat as StandardMaterial3D
	var d: StandardMaterial3D = base.duplicate()
	d.albedo_color = Color(
		clampf(base.albedo_color.r * factor, 0.0, 1.0),
		clampf(base.albedo_color.g * factor, 0.0, 1.0),
		clampf(base.albedo_color.b * factor, 0.0, 1.0),
		base.albedo_color.a)
	_tone_cache[key] = d
	return d


## 不可见碰撞体：只挡人，不显示。
func _collider(parent: Node, node_name: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = HouseGeom.WALL_LAYER
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)
	return body


## 四根腿（居中于 ±inset 的四个角）。
func _legs(holder: Node, prefix: String, hx: float, hz: float, height: float,
		thickness: float, mat: Material) -> void:
	var i := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			geom.box(holder, "%s%d" % [prefix, i],
				Vector3(thickness, height, thickness),
				Vector3(sx * hx, height * 0.5, sz * hz), mat)
			i += 1


## 柜门拉手（细长条）。facing = -1 表示装在 -Z 面。
func _handle(holder: Node, node_name: String, pos: Vector3, mat: Material,
		horizontal: bool = false) -> void:
	var size := Vector3(0.02, 0.16, 0.02) if not horizontal else Vector3(0.16, 0.02, 0.02)
	geom.box(holder, node_name, size, pos, mat)


## 一排抽屉门板（沿局部 X 均分）。
func _doors(holder: Node, prefix: String, count: int, total_w: float,
		h: float, y: float, z: float, thickness: float, mat: Material,
		handle_mat: Material) -> void:
	var w := total_w / float(count)
	for i in count:
		var cx := -total_w * 0.5 + w * (float(i) + 0.5)
		geom.box(holder, "%s%d" % [prefix, i], Vector3(w * 0.94, h, thickness),
			Vector3(cx, y, z), mat)
		# 门缝两侧的拉手
		var hx := cx + (w * 0.28 if i % 2 == 0 else -w * 0.28)
		_handle(holder, "%sH%d" % [prefix, i],
			Vector3(hx, y, z - thickness * 0.5 - 0.012), handle_mat)


# ------------------------------------------------------------------ 客厅

## 沙发：底座 + 座垫(分离) + 靠背 + 靠垫 + 扶手 + 收纳腿。
## length 沿局部 X，depth 沿局部 Z（正面朝 -Z）。
func sofa(parent: Node, node_name: String, pos: Vector3, length: float,
		facing_yaw: float, mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var depth := 0.94
	var seat_h := 0.42
	var back_h := 0.84
	var arm_w := 0.20
	var inner := length - arm_w * 2.0
	var m_frame := _tone(mat, 0.86)
	var m_cushion := _tone(mat, 1.10)
	var m_piping := _tone(mat, 0.72)

	_collider(holder, "Collider", Vector3(length, back_h, depth),
		Vector3(0, back_h * 0.5, 0))

	# 底座（软包箱体）
	geom.box(holder, "Base", Vector3(inner, 0.30, depth - 0.06),
		Vector3(0, 0.26, 0), m_frame)
	# 短腿
	_legs(holder, "Leg", length * 0.5 - 0.10, depth * 0.5 - 0.10, 0.11, 0.05, m_piping)

	# 座垫：按人数分 3 段
	var n := 3
	var cw := inner / float(n) - 0.012
	for i in n:
		var cx := -inner * 0.5 + (inner / float(n)) * (float(i) + 0.5)
		geom.box(holder, "SeatCushion%d" % i, Vector3(cw, 0.15, depth - 0.16),
			Vector3(cx, seat_h - 0.02, -0.02), m_cushion)
		# 垫子前沿的一点点翻边
		geom.box(holder, "SeatLip%d" % i, Vector3(cw, 0.03, 0.04),
			Vector3(cx, seat_h - 0.08, -depth * 0.5 + 0.09), m_piping)

	# 靠背箱体 + 靠垫
	geom.box(holder, "BackFrame", Vector3(inner, back_h - 0.30, 0.16),
		Vector3(0, 0.30 + (back_h - 0.30) * 0.5, depth * 0.5 - 0.08), m_frame)
	for i in n:
		var cx2 := -inner * 0.5 + (inner / float(n)) * (float(i) + 0.5)
		geom.box(holder, "BackCushion%d" % i, Vector3(cw, back_h - 0.46, 0.13),
			Vector3(cx2, 0.52, depth * 0.5 - 0.22), m_cushion)

	# 扶手
	geom.box(holder, "ArmL", Vector3(arm_w, 0.34, depth),
		Vector3(-length * 0.5 + arm_w * 0.5, back_h - 0.17, 0), m_frame)
	geom.box(holder, "ArmR", Vector3(arm_w, 0.34, depth),
		Vector3(length * 0.5 - arm_w * 0.5, back_h - 0.17, 0), m_frame)
	geom.box(holder, "ArmTopL", Vector3(arm_w + 0.02, 0.05, depth + 0.02),
		Vector3(-length * 0.5 + arm_w * 0.5, back_h + 0.02, 0), m_cushion)
	geom.box(holder, "ArmTopR", Vector3(arm_w + 0.02, 0.05, depth + 0.02),
		Vector3(length * 0.5 - arm_w * 0.5, back_h + 0.02, 0), m_cushion)

	holder.position = pos
	holder.rotation.y = facing_yaw
	return holder


## 单人扶手椅。
func armchair(parent: Node, node_name: String, pos: Vector3, facing_yaw: float,
		mat: Material) -> Node3D:
	return sofa(parent, node_name, pos, 0.92, facing_yaw, mat)


## 茶几：台面 + 下层隔板 + 四腿。size = (长, 高, 宽)。
func coffee_table(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var top_h := 0.05
	var leg_h := size.y - top_h
	var m_top := mat
	var m_body := _tone(mat, 0.82)

	_collider(holder, "Collider", size, Vector3(0, size.y * 0.5, 0))
	geom.box(holder, "Top", Vector3(size.x, top_h, size.z),
		Vector3(0, leg_h + top_h * 0.5, 0), m_top)
	# 台面下沿
	geom.box(holder, "Apron", Vector3(size.x - 0.10, 0.05, size.z - 0.10),
		Vector3(0, leg_h - 0.02, 0), m_body)
	# 下层隔板
	geom.box(holder, "Shelf", Vector3(size.x - 0.12, 0.03, size.z - 0.12),
		Vector3(0, 0.14, 0), m_body)
	_legs(holder, "Leg", size.x * 0.5 - 0.07, size.z * 0.5 - 0.07, leg_h, 0.05, m_body)

	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 电视柜：柜体 + 三扇门 + 拉手 + 短腿。
func tv_cabinet(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, mat: Material, handle_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var leg_h := 0.10
	var body_h := size.y - leg_h
	var m_body := mat
	var m_door := _tone(mat, 1.12)

	_collider(holder, "Collider", size, Vector3(0, size.y * 0.5, 0))
	geom.box(holder, "Body", Vector3(size.x, body_h, size.z),
		Vector3(0, leg_h + body_h * 0.5, 0), m_body)
	_doors(holder, "Door", 3, size.x - 0.02, body_h - 0.06, leg_h + body_h * 0.5,
		-size.z * 0.5 - 0.008, 0.018, m_door, handle_mat)
	_legs(holder, "Leg", size.x * 0.5 - 0.08, size.z * 0.5 - 0.08, leg_h, 0.05, m_body)

	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 电视机：面板 + 边框 + 底座。面向 -Z。
func tv(parent: Node, node_name: String, pos: Vector3, width: float,
		height: float, yaw: float, bezel_mat: Material, screen_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.box(holder, "Panel", Vector3(width, height, 0.05), Vector3(0, 0, 0), bezel_mat)
	geom.box(holder, "Screen", Vector3(width - 0.05, height - 0.05, 0.012),
		Vector3(0, 0, -0.032), screen_mat)
	geom.box(holder, "StandNeck", Vector3(0.12, 0.10, 0.10), Vector3(0, -height * 0.5 - 0.05, 0.02), bezel_mat)
	geom.box(holder, "StandBase", Vector3(0.46, 0.025, 0.22), Vector3(0, -height * 0.5 - 0.10, 0.02), bezel_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 壁炉：台体 + 壁炉台 + 炉膛 + 炉栅 + 炉前地砖。
func fireplace(parent: Node, node_name: String, pos: Vector3, width: float,
		yaw: float, mat: Material, chamber_mat: Material, hearth_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var m_mantel := _tone(mat, 1.14)
	var m_pillar := _tone(mat, 0.94)

	_collider(holder, "Collider", Vector3(width, 1.30, 0.42), Vector3(0, 0.65, 0))
	# 左右立柱
	geom.box(holder, "PillarL", Vector3(0.22, 1.15, 0.40),
		Vector3(-width * 0.5 + 0.11, 0.575, 0), m_pillar)
	geom.box(holder, "PillarR", Vector3(0.22, 1.15, 0.40),
		Vector3(width * 0.5 - 0.11, 0.575, 0), m_pillar)
	# 门楣
	geom.box(holder, "Lintel", Vector3(width - 0.44, 0.30, 0.40),
		Vector3(0, 1.00, 0), m_pillar)
	# 壁炉台
	geom.box(holder, "Mantel", Vector3(width + 0.18, 0.09, 0.48),
		Vector3(0, 1.20, 0), m_mantel)
	# 炉膛（深色内凹）
	geom.box(holder, "Chamber", Vector3(width - 0.46, 0.78, 0.10),
		Vector3(0, 0.45, -0.19), chamber_mat)
	geom.box(holder, "Grate", Vector3(width - 0.62, 0.07, 0.10),
		Vector3(0, 0.10, -0.20), m_mantel)
	# 炉前石台
	geom.box(holder, "Hearth", Vector3(width + 0.10, 0.04, 0.34),
		Vector3(0, 0.02, -0.30), hearth_mat)

	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 地毯：底色 + 内边框（两层，避免近共面闪烁）。
func rug(parent: Node, node_name: String, pos: Vector3, size: Vector2,
		yaw: float, mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var m_border := _tone(mat, 0.78)
	geom.box(holder, "Field", Vector3(size.x, 0.016, size.y), Vector3(0, 0.012, 0), mat)
	geom.box(holder, "Border", Vector3(size.x - 0.16, 0.018, size.y - 0.16),
		Vector3(0, 0.014, 0), m_border)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


# ------------------------------------------------------------------ 餐厅

## 餐桌：台面 + 裙板 + 四腿。
func table(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var top_h := 0.06
	var leg_h := size.y - top_h
	var m_top := _tone(mat, 1.08)
	var m_body := _tone(mat, 0.88)

	_collider(holder, "Collider", size, Vector3(0, size.y * 0.5, 0))
	geom.box(holder, "Top", Vector3(size.x, top_h, size.z),
		Vector3(0, leg_h + top_h * 0.5, 0), m_top)
	# 裙板（台面下方一圈）
	geom.box(holder, "ApronX", Vector3(size.x - 0.06, 0.09, 0.03),
		Vector3(0, leg_h - 0.05, size.z * 0.5 - 0.10), m_body)
	geom.box(holder, "ApronX2", Vector3(size.x - 0.06, 0.09, 0.03),
		Vector3(0, leg_h - 0.05, -size.z * 0.5 + 0.10), m_body)
	geom.box(holder, "ApronZ", Vector3(0.03, 0.09, size.z - 0.06),
		Vector3(size.x * 0.5 - 0.10, leg_h - 0.05, 0), m_body)
	geom.box(holder, "ApronZ2", Vector3(0.03, 0.09, size.z - 0.06),
		Vector3(-size.x * 0.5 + 0.10, leg_h - 0.05, 0), m_body)
	_legs(holder, "Leg", size.x * 0.5 - 0.09, size.z * 0.5 - 0.09, leg_h, 0.07, m_body)

	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 餐椅：四条锥腿 + 座面 + 软垫 + 后腿延伸成靠背 + 横撑。
func chair(parent: Node, node_name: String, pos: Vector3, facing_yaw: float,
		mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var seat_h := 0.45
	var m_frame := mat
	var m_pad := _tone(mat, 1.12)

	# footprint 碰撞体：到座面高度，避免玩家从椅面下穿过
	_collider(holder, "Collider", Vector3(0.46, seat_h + 0.06, 0.48),
		Vector3(0, (seat_h + 0.06) * 0.5, 0))

	# 前腿
	geom.box(holder, "LegFL", Vector3(0.045, seat_h, 0.045), Vector3(-0.19, seat_h * 0.5, -0.19), m_frame)
	geom.box(holder, "LegFR", Vector3(0.045, seat_h, 0.045), Vector3(0.19, seat_h * 0.5, -0.19), m_frame)
	# 后腿（延伸到靠背高度）
	geom.box(holder, "LegBL", Vector3(0.045, 0.92, 0.045), Vector3(-0.19, 0.46, 0.19), m_frame)
	geom.box(holder, "LegBR", Vector3(0.045, 0.92, 0.045), Vector3(0.19, 0.46, 0.19), m_frame)
	# 座面 + 软垫
	geom.box(holder, "Seat", Vector3(0.46, 0.045, 0.46), Vector3(0, seat_h - 0.022, 0), m_frame)
	geom.box(holder, "SeatPad", Vector3(0.40, 0.035, 0.40), Vector3(0, seat_h + 0.017, 0), m_pad)
	# 靠背：上横撑 + 中间一块背板
	geom.box(holder, "BackTop", Vector3(0.42, 0.07, 0.045), Vector3(0, 0.90, 0.19), m_frame)
	geom.box(holder, "BackPanel", Vector3(0.38, 0.26, 0.035), Vector3(0, 0.73, 0.19), m_frame)
	# 侧向横撑
	geom.box(holder, "StretcherL", Vector3(0.035, 0.03, 0.34), Vector3(-0.19, 0.14, 0), m_frame)
	geom.box(holder, "StretcherR", Vector3(0.035, 0.03, 0.34), Vector3(0.19, 0.14, 0), m_frame)

	holder.position = pos
	holder.rotation.y = facing_yaw
	return holder


# ------------------------------------------------------------------ 厨房

## 底柜 + 台面 + 挡水板 + 柜门。size = (长, 高, 深)。
func base_cabinet(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, body_mat: Material, top_mat: Material, handle_mat: Material,
		door_count: int = 3) -> Node3D:
	var holder := geom.node(parent, node_name)
	var toe := 0.10
	var top_h := 0.04
	var body_h := size.y - toe - top_h
	var m_body := body_mat
	var m_door := _tone(body_mat, 1.10)

	_collider(holder, "Collider", size, Vector3(0, size.y * 0.5, 0))
	# 踢脚（内缩）
	geom.box(holder, "ToeKick", Vector3(size.x, toe, size.z - 0.08),
		Vector3(0, toe * 0.5, 0.04), _tone(body_mat, 0.6))
	# 柜体
	geom.box(holder, "Body", Vector3(size.x, body_h, size.z),
		Vector3(0, toe + body_h * 0.5, 0), m_body)
	# 柜门
	_doors(holder, "Door", door_count, size.x - 0.02, body_h - 0.05,
		toe + body_h * 0.5, -size.z * 0.5 - 0.008, 0.018, m_door, handle_mat)
	# 台面（略微外挑）
	geom.box(holder, "CounterTop", Vector3(size.x + 0.02, top_h, size.z + 0.03),
		Vector3(0, size.y - top_h * 0.5, -0.01), top_mat)
	# 挡水（靠墙侧 +Z）
	geom.box(holder, "Backsplash", Vector3(size.x, 0.12, 0.02),
		Vector3(0, size.y + 0.06, size.z * 0.5 - 0.01), top_mat)

	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 吊柜（挂在墙上的上柜）。pos 给的是柜体**底面**中心。
func upper_cabinet(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, body_mat: Material, handle_mat: Material,
		door_count: int = 2) -> Node3D:
	var holder := geom.node(parent, node_name)
	var m_body := body_mat
	var m_door := _tone(body_mat, 1.10)

	geom.box(holder, "Body", Vector3(size.x, size.y, size.z),
		Vector3(0, size.y * 0.5, 0), m_body)
	_doors(holder, "Door", door_count, size.x - 0.02, size.y - 0.05,
		size.y * 0.5, -size.z * 0.5 - 0.008, 0.018, m_door, handle_mat)
	# 底部灯带槽
	geom.box(holder, "LightRail", Vector3(size.x - 0.04, 0.02, 0.05),
		Vector3(0, 0.02, -size.z * 0.5 + 0.03), _tone(body_mat, 0.65))

	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 水槽：台面开槽 + 盆体 + 龙头 + 把手。
func sink(parent: Node, node_name: String, pos: Vector3, width: float,
		depth: float, counter_h: float, yaw: float, steel_mat: Material,
		basin_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	# 盆体（比台面低，用深色体块表现内凹）
	geom.box(holder, "Basin", Vector3(width, 0.20, depth),
		Vector3(0, counter_h - 0.12, 0), basin_mat)
	geom.box(holder, "Rim", Vector3(width + 0.04, 0.02, depth + 0.04),
		Vector3(0, counter_h + 0.005, 0), steel_mat)
	# 龙头
	geom.cyl(holder, "FaucetBase", 0.028, 0.05,
		Vector3(0, counter_h + 0.025, depth * 0.5 - 0.03), steel_mat)
	geom.cyl(holder, "FaucetStem", 0.018, 0.24,
		Vector3(0, counter_h + 0.14, depth * 0.5 - 0.03), steel_mat)
	geom.box(holder, "FaucetArm", Vector3(0.03, 0.03, 0.14),
		Vector3(0, counter_h + 0.25, depth * 0.5 - 0.10), steel_mat)
	geom.box(holder, "TapL", Vector3(0.06, 0.02, 0.02),
		Vector3(-0.10, counter_h + 0.03, depth * 0.5 - 0.03), steel_mat)
	geom.box(holder, "TapR", Vector3(0.06, 0.02, 0.02),
		Vector3(0.10, counter_h + 0.03, depth * 0.5 - 0.03), steel_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 灶台：灶面 + 四个灶眼 + 烤箱门 + 旋钮。
func stove(parent: Node, node_name: String, pos: Vector3, width: float,
		yaw: float, body_mat: Material, top_mat: Material, steel_mat: Material,
		burner_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var h := 0.90
	geom.box(holder, "Body", Vector3(width, h, 0.62), Vector3(0, h * 0.5, 0), body_mat)
	geom.box(holder, "Cooktop", Vector3(width, 0.03, 0.62),
		Vector3(0, h + 0.015, 0), top_mat)
	# 四个灶眼
	for i in 4:
		var bx := (-0.17 if i % 2 == 0 else 0.17)
		var bz := (-0.14 if i < 2 else 0.14)
		geom.cyl(holder, "Burner%d" % i, 0.085, 0.012,
			Vector3(bx, h + 0.035, bz), burner_mat)
		geom.cyl(holder, "BurnerCap%d" % i, 0.035, 0.02,
			Vector3(bx, h + 0.045, bz), steel_mat)
	# 烤箱门
	geom.box(holder, "OvenDoor", Vector3(width - 0.06, 0.46, 0.02),
		Vector3(0, 0.40, -0.32), steel_mat)
	geom.box(holder, "OvenGlass", Vector3(width - 0.16, 0.30, 0.012),
		Vector3(0, 0.40, -0.335), _tone(burner_mat, 1.4))
	geom.box(holder, "OvenHandle", Vector3(width - 0.14, 0.025, 0.03),
		Vector3(0, 0.60, -0.35), steel_mat)
	# 旋钮
	for i in 4:
		var kx := -0.21 + 0.14 * float(i)
		geom.cyl(holder, "Knob%d" % i, 0.018, 0.02,
			Vector3(kx, 0.70, -0.32), burner_mat)

	_collider(holder, "Collider", Vector3(width, h, 0.62), Vector3(0, h * 0.5, 0))
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 冰箱：箱体 + 上下两扇门 + 长拉手 + 底脚。
func fridge(parent: Node, node_name: String, pos: Vector3, yaw: float,
		mat: Material, handle_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var w := 0.78
	var h := 1.86
	var d := 0.72
	var m_door := _tone(mat, 1.06)

	_collider(holder, "Collider", Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	geom.box(holder, "Body", Vector3(w, h, d), Vector3(0, h * 0.5, 0), _tone(mat, 0.94))
	# 冷冻室门（上 32%）与冷藏室门（下 68%）
	var split := h * 0.66
	geom.box(holder, "DoorTop", Vector3(w - 0.02, h - split - 0.03, 0.03),
		Vector3(0, split + (h - split) * 0.5, -d * 0.5 - 0.012), m_door)
	geom.box(holder, "DoorBottom", Vector3(w - 0.02, split - 0.03, 0.03),
		Vector3(0, split * 0.5, -d * 0.5 - 0.012), m_door)
	# 拉手（竖向长条，装在门缝两侧）
	geom.box(holder, "HandleTop", Vector3(0.025, 0.30, 0.035),
		Vector3(w * 0.5 - 0.10, split + 0.22, -d * 0.5 - 0.035), handle_mat)
	geom.box(holder, "HandleBottom", Vector3(0.025, 0.42, 0.035),
		Vector3(w * 0.5 - 0.10, split - 0.28, -d * 0.5 - 0.035), handle_mat)
	# 底脚
	geom.box(holder, "FootL", Vector3(0.06, 0.04, 0.06), Vector3(-w * 0.5 + 0.08, 0.02, -d * 0.5 + 0.09), _tone(mat, 0.5))
	geom.box(holder, "FootR", Vector3(0.06, 0.04, 0.06), Vector3(w * 0.5 - 0.08, 0.02, -d * 0.5 + 0.09), _tone(mat, 0.5))

	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 厨房岛台：柜体 + 石材台面挑边 + 柜门。
func island(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, body_mat: Material, top_mat: Material,
		handle_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var top_h := 0.05
	var body_h := size.y - top_h
	_collider(holder, "Collider", size, Vector3(0, size.y * 0.5, 0))
	geom.box(holder, "Body", Vector3(size.x, body_h, size.z),
		Vector3(0, body_h * 0.5, 0), body_mat)
	_doors(holder, "Door", 2, size.x - 0.04, body_h - 0.06, body_h * 0.5,
		-size.z * 0.5 - 0.008, 0.02, _tone(body_mat, 1.10), handle_mat)
	geom.box(holder, "Top", Vector3(size.x + 0.10, top_h, size.z + 0.10),
		Vector3(0, body_h + top_h * 0.5, 0), top_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


# ------------------------------------------------------------------ 书房

## 书桌：台面 + 抽屉柜 + 拉手。
func desk(parent: Node, node_name: String, pos: Vector3, yaw: float,
		mat: Material, handle_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var w := 1.40
	var d := 0.68
	var h := 0.75
	var top_h := 0.05
	_collider(holder, "Collider", Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	geom.box(holder, "Top", Vector3(w, top_h, d), Vector3(0, h - top_h * 0.5, 0), _tone(mat, 1.08))
	# 左侧抽屉柜
	geom.box(holder, "Pedestal", Vector3(0.42, h - top_h, d - 0.06),
		Vector3(-w * 0.5 + 0.23, (h - top_h) * 0.5, 0), mat)
	for i in 3:
		var dy := 0.16 + 0.19 * float(i)
		geom.box(holder, "Drawer%d" % i, Vector3(0.36, 0.16, 0.02),
			Vector3(-w * 0.5 + 0.23, dy, -d * 0.5 + 0.02), _tone(mat, 1.12))
		geom.box(holder, "DrawerHandle%d" % i, Vector3(0.14, 0.02, 0.025),
			Vector3(-w * 0.5 + 0.23, dy, -d * 0.5 - 0.005), handle_mat)
	# 右侧两腿
	geom.box(holder, "LegR1", Vector3(0.05, h - top_h, 0.05),
		Vector3(w * 0.5 - 0.10, (h - top_h) * 0.5, -d * 0.5 + 0.10), mat)
	geom.box(holder, "LegR2", Vector3(0.05, h - top_h, 0.05),
		Vector3(w * 0.5 - 0.10, (h - top_h) * 0.5, d * 0.5 - 0.10), mat)
	# 背板
	geom.box(holder, "Modesty", Vector3(w - 0.46, 0.34, 0.02),
		Vector3(0.12, h - 0.24, d * 0.5 - 0.10), _tone(mat, 0.94))
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 书架：两侧板 + 若干层隔板 + 背板 + 一排书。
func bookshelf(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, mat: Material, book_mats: Array) -> Node3D:
	var holder := geom.node(parent, node_name)
	var side := 0.035
	var shelves := 4
	var m_back := _tone(mat, 0.78)

	_collider(holder, "Collider", size, Vector3(0, size.y * 0.5, 0))
	geom.box(holder, "Back", Vector3(size.x, size.y, 0.02),
		Vector3(0, size.y * 0.5, size.z * 0.5 - 0.012), m_back)
	geom.box(holder, "SideL", Vector3(side, size.y, size.z),
		Vector3(-size.x * 0.5 + side * 0.5, size.y * 0.5, 0), mat)
	geom.box(holder, "SideR", Vector3(side, size.y, size.z),
		Vector3(size.x * 0.5 - side * 0.5, size.y * 0.5, 0), mat)
	geom.box(holder, "TopPanel", Vector3(size.x, 0.03, size.z),
		Vector3(0, size.y - 0.015, 0), mat)
	geom.box(holder, "BottomPanel", Vector3(size.x, 0.05, size.z),
		Vector3(0, 0.025, 0), mat)

	var usable := size.y - 0.08
	for s in shelves:
		var sy := 0.05 + usable * (float(s) + 1.0) / float(shelves + 1)
		geom.box(holder, "Shelf%d" % s, Vector3(size.x - side * 2.0, 0.025, size.z - 0.04),
			Vector3(0, sy, 0), mat)
		# 一排书：用确定性分布，避免每次重建位置不同
		var bw := 0.030
		var n := int((size.x - 0.10) / bw)
		for b in n:
			if (b + s) % 5 == 3:
				continue  # 留些空隙
			var bx := -size.x * 0.5 + 0.06 + bw * (float(b) + 0.5)
			var bh := 0.16 + 0.045 * float((b * 7 + s * 3) % 4)
			var book_mat: Material = book_mats[(b + s * 2) % book_mats.size()]
			geom.box(holder, "Book%d_%d" % [s, b], Vector3(bw * 0.82, bh, size.z * 0.62),
				Vector3(bx, sy + 0.013 + bh * 0.5, 0.01), book_mat)

	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 笔记本：机身 + 屏幕 + 转轴。
func laptop(parent: Node, node_name: String, pos: Vector3, yaw: float,
		mat: Material, screen_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.box(holder, "Base", Vector3(0.34, 0.016, 0.24), Vector3(0, 0.008, 0), mat)
	geom.box(holder, "Keyboard", Vector3(0.30, 0.004, 0.14), Vector3(0, 0.017, 0.02), _tone(mat, 0.55))
	geom.box(holder, "Lid", Vector3(0.34, 0.22, 0.012), Vector3(0, 0.12, -0.12), mat)
	geom.box(holder, "Screen", Vector3(0.31, 0.19, 0.006), Vector3(0, 0.12, -0.115), screen_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


# ------------------------------------------------------------------ 装饰

## 窗帘：帘杆 + 两片帘布（用多条竖褶表现布料）。
func curtain(parent: Node, node_name: String, pos: Vector3, width: float,
		height: float, yaw: float, rod_mat: Material, cloth_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.cyl(holder, "Rod", 0.016, width + 0.30, Vector3(0, height + 0.04, 0), rod_mat)
	# Godot 的 CylinderMesh 是竖直的，帘杆需要横躺 → 用细长方盒代替更稳
	geom.box(holder, "RodFix", Vector3(width + 0.30, 0.028, 0.028),
		Vector3(0, height + 0.04, 0), rod_mat)
	var panels := 2
	var pw := width * 0.36
	for p in panels:
		var cx := -width * 0.5 + pw * 0.5 if p == 0 else width * 0.5 - pw * 0.5
		# 每片帘布用 4 条竖褶，宽窄交替，形成布褶感
		for f in 4:
			var fx := cx - pw * 0.5 + pw * (float(f) + 0.5) / 4.0
			var thick := 0.035 if f % 2 == 0 else 0.055
			geom.box(holder, "Fold%d_%d" % [p, f], Vector3(pw / 4.0, height, thick),
				Vector3(fx, height * 0.5, 0.0 + 0.01 * float(f % 2)), cloth_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 挂画 / 照片：外框 + 画心。
func wall_art(parent: Node, node_name: String, pos: Vector3, size: Vector2,
		yaw: float, frame_mat: Material, art_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.box(holder, "Frame", Vector3(size.x, size.y, 0.035), Vector3(0, 0, 0), frame_mat)
	geom.box(holder, "Canvas", Vector3(size.x - 0.07, size.y - 0.07, 0.012),
		Vector3(0, 0, -0.022), art_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 台灯（落地灯 / 桌面灯）。height 为灯杆高度。
func floor_lamp(parent: Node, node_name: String, pos: Vector3, height: float,
		shade_mat: Material, metal_mat: Material, light_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.cyl(holder, "Base", 0.16, 0.03, Vector3(0, 0.015, 0), metal_mat)
	geom.cyl(holder, "Pole", 0.018, height, Vector3(0, height * 0.5, 0), metal_mat)
	# 灯罩：上窄下宽的锥体近似（两段圆柱）
	geom.cyl(holder, "ShadeTop", 0.13, 0.02, Vector3(0, height + 0.20, 0), shade_mat)
	geom.cyl(holder, "Shade", 0.17, 0.22, Vector3(0, height + 0.09, 0), shade_mat)
	geom.cyl(holder, "Bulb", 0.09, 0.10, Vector3(0, height + 0.04, 0), light_mat)
	holder.position = pos
	return holder


## 床头柜 / 边几：柜体 + 一扇门 + 台面。
func nightstand(parent: Node, node_name: String, pos: Vector3, yaw: float,
		mat: Material, handle_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var size := Vector3(0.46, 0.55, 0.40)
	_collider(holder, "Collider", size, Vector3(0, size.y * 0.5, 0))
	geom.box(holder, "Body", Vector3(size.x, size.y - 0.03, size.z),
		Vector3(0, (size.y - 0.03) * 0.5, 0), mat)
	geom.box(holder, "Top", Vector3(size.x + 0.03, 0.03, size.z + 0.03),
		Vector3(0, size.y - 0.015, 0), _tone(mat, 1.10))
	geom.box(holder, "Drawer", Vector3(size.x - 0.08, 0.18, 0.02),
		Vector3(0, size.y - 0.16, -size.z * 0.5 - 0.008), _tone(mat, 1.12))
	geom.box(holder, "Knob", Vector3(0.05, 0.05, 0.03),
		Vector3(0, size.y - 0.16, -size.z * 0.5 - 0.025), handle_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 通用柜体：实心柜 + 一扇门 + 拉手（洁具、鞋柜、边柜等复用）。
func cabinet(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	_collider(holder, "Collider", size, Vector3(0, size.y * 0.5, 0))
	geom.box(holder, "Body", size, Vector3(0, size.y * 0.5, 0), mat)
	geom.box(holder, "Door", Vector3(size.x * 0.92, size.y * 0.86, 0.018),
		Vector3(0, size.y * 0.5, -size.z * 0.5 - 0.008), _tone(mat, 1.12))
	geom.box(holder, "Handle", Vector3(0.02, 0.12, 0.02),
		Vector3(size.x * 0.36, size.y * 0.5, -size.z * 0.5 - 0.028), _tone(mat, 0.55))
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 马桶：底座 + 座圈 + 水箱 + 冲水扳手。正面朝 -Z。
func toilet(parent: Node, node_name: String, pos: Vector3, yaw: float,
		mat: Material, steel_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	_collider(holder, "Collider", Vector3(0.40, 0.78, 0.66), Vector3(0, 0.39, 0))
	# 底座
	geom.box(holder, "Base", Vector3(0.30, 0.34, 0.46), Vector3(0, 0.17, -0.06), mat)
	# 座体
	geom.box(holder, "Bowl", Vector3(0.38, 0.16, 0.50), Vector3(0, 0.42, -0.06), mat)
	geom.box(holder, "Seat", Vector3(0.36, 0.03, 0.46), Vector3(0, 0.51, -0.06), _tone(mat, 1.10))
	# 水箱
	geom.box(holder, "Tank", Vector3(0.40, 0.34, 0.18), Vector3(0, 0.62, 0.20), mat)
	geom.box(holder, "TankLid", Vector3(0.42, 0.03, 0.20), Vector3(0, 0.80, 0.20), _tone(mat, 1.10))
	geom.box(holder, "Flush", Vector3(0.06, 0.02, 0.02), Vector3(0.12, 0.81, 0.13), steel_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 洗手台：台盆柜 + 台面 + 盆体 + 龙头 + 镜子。正面朝 -Z。
func vanity(parent: Node, node_name: String, pos: Vector3, yaw: float,
		body_mat: Material, top_mat: Material, steel_mat: Material,
		mirror_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var w := 0.60
	var d := 0.48
	var h := 0.84
	_collider(holder, "Collider", Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	geom.box(holder, "Body", Vector3(w, h - 0.06, d), Vector3(0, (h - 0.06) * 0.5, 0), body_mat)
	geom.box(holder, "Door", Vector3(w - 0.06, h - 0.18, 0.018),
		Vector3(0, (h - 0.06) * 0.5, -d * 0.5 - 0.008), _tone(body_mat, 1.12))
	geom.box(holder, "Top", Vector3(w + 0.03, 0.05, d + 0.03), Vector3(0, h - 0.02, 0), top_mat)
	# 盆
	geom.box(holder, "Basin", Vector3(w * 0.66, 0.06, d * 0.62),
		Vector3(0, h + 0.01, -0.02), _tone(top_mat, 0.55))
	# 龙头
	geom.cyl(holder, "Faucet", 0.016, 0.16, Vector3(0, h + 0.10, d * 0.34), steel_mat)
	geom.box(holder, "Spout", Vector3(0.024, 0.024, 0.10),
		Vector3(0, h + 0.17, d * 0.24), steel_mat)
	# 镜子（贴墙侧 +Z）
	geom.box(holder, "Mirror", Vector3(w * 0.9, 0.70, 0.02),
		Vector3(0, h + 0.46, d * 0.5 - 0.02), mirror_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


# ------------------------------------------------------------------ 卧室与洗衣

## 双人床：床架 + 床垫 + 被子 + 枕头 + 床头板。床头朝局部 +Z。
func bed(parent: Node, node_name: String, pos: Vector3, size: Vector2,
		yaw: float, frame_mat: Material, sheet_mat: Material,
		pillow_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var w := size.x      # 宽（局部 X）
	var l := size.y      # 长（局部 Z）
	var frame_h := 0.26
	var matt_h := 0.20
	var m_sheet := _tone(sheet_mat, 1.06)
	_collider(holder, "Collider", Vector3(w, frame_h + matt_h, l),
		Vector3(0, (frame_h + matt_h) * 0.5, 0))
	# 床架
	geom.box(holder, "Frame", Vector3(w, frame_h, l), Vector3(0, frame_h * 0.5, 0), frame_mat)
	_legs(holder, "Leg", w * 0.5 - 0.10, l * 0.5 - 0.10, frame_h, 0.06, _tone(frame_mat, 0.8))
	# 床垫
	geom.box(holder, "Mattress", Vector3(w - 0.06, matt_h, l - 0.06),
		Vector3(0, frame_h + matt_h * 0.5, 0), m_sheet)
	# 被子（覆盖靠脚一端 2/3）
	var duvet_l := l * 0.66
	geom.box(holder, "Duvet", Vector3(w - 0.02, 0.10, duvet_l),
		Vector3(0, frame_h + matt_h + 0.04, -l * 0.5 + duvet_l * 0.5 + 0.02), sheet_mat)
	# 枕头两个
	var pw := (w - 0.16) * 0.5
	for i in 2:
		var px := -w * 0.25 + w * 0.5 * float(i)
		geom.box(holder, "Pillow%d" % i, Vector3(pw * 0.9, 0.12, 0.34),
			Vector3(px + w * 0.02 * (1 if i == 0 else -1),
				frame_h + matt_h + 0.06, l * 0.5 - 0.24), pillow_mat)
	# 床头板
	geom.box(holder, "Headboard", Vector3(w + 0.06, 0.72, 0.06),
		Vector3(0, frame_h + 0.36, l * 0.5 + 0.03), _tone(frame_mat, 0.9))
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 衣柜：柜体 + 两扇长门 + 拉手。门朝局部 -Z。
func wardrobe(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, mat: Material, handle_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	_collider(holder, "Collider", size, Vector3(0, size.y * 0.5, 0))
	geom.box(holder, "Body", size, Vector3(0, size.y * 0.5, 0), mat)
	geom.box(holder, "Cornice", Vector3(size.x + 0.04, 0.06, size.z + 0.04),
		Vector3(0, size.y - 0.03, 0), _tone(mat, 1.10))
	var dw := size.x * 0.5 - 0.02
	for i in 2:
		var dx := -size.x * 0.25 + size.x * 0.5 * float(i)
		geom.box(holder, "Door%d" % i, Vector3(dw, size.y - 0.14, 0.02),
			Vector3(dx, size.y * 0.5 - 0.04, -size.z * 0.5 - 0.01), _tone(mat, 1.10))
		var hx := dx + (dw * 0.34 if i == 0 else -dw * 0.34)
		geom.box(holder, "Handle%d" % i, Vector3(0.02, 0.22, 0.03),
			Vector3(hx, size.y * 0.5, -size.z * 0.5 - 0.03), handle_mat)
	holder.position = pos
	holder.rotation.y = yaw
	return holder


## 洗衣机：箱体 + 圆形舱门 + 控制面板。门朝局部 -Z。
func washer(parent: Node, node_name: String, pos: Vector3, yaw: float,
		mat: Material, steel_mat: Material, glass_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var w := 0.60
	var h := 0.85
	var d := 0.60
	_collider(holder, "Collider", Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	geom.box(holder, "Body", Vector3(w, h, d), Vector3(0, h * 0.5, 0), mat)
	geom.box(holder, "Door", Vector3(0.40, 0.40, 0.03), Vector3(0, 0.42, -d * 0.5 - 0.015), steel_mat)
	geom.box(holder, "Glass", Vector3(0.30, 0.30, 0.02), Vector3(0, 0.42, -d * 0.5 - 0.03), glass_mat)
	geom.box(holder, "Panel", Vector3(w - 0.06, 0.12, 0.02), Vector3(0, h - 0.10, -d * 0.5 - 0.012), _tone(steel_mat, 0.8))
	for i in 3:
		geom.cyl(holder, "Knob%d" % i, 0.016, 0.02,
			Vector3(-0.16 + 0.16 * float(i), h - 0.10, -d * 0.5 - 0.03), _tone(steel_mat, 0.6))
	holder.position = pos
	holder.rotation.y = yaw
	return holder
