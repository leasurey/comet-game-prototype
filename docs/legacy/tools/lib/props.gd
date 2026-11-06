## HouseProps — 家具体块原语
##
## 职责边界：
##   只负责「造一件家具」，不知道它放在哪个房间、属于哪个世界。
##   具体摆放由 tools/house/house_furniture.gd 决定。
##
## 设计取向：
##   灰盒阶段全部用基础几何体拼装，不追求外形准确，只追求
##   ① 体块尺寸合理 ② 碰撞体与视觉一致 ③ 能挡住玩家。
##
## 离线构建脚本的一部分，不进入运行时依赖。

class_name HouseProps
extends RefCounted

var geom: HouseGeom = null


func _init(geom_instance: HouseGeom) -> void:
	geom = geom_instance


## 沙发。length 沿「横向」（局部 X），depth 沿「面向方向」（局部 Z）。
## pos 是沙发底面中心；facing_yaw 为朝向（0 表示面向 -Z）。
func sofa(parent: Node, node_name: String, pos: Vector3, length: float,
		facing_yaw: float, mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var depth := 0.95
	var seat_h := 0.42
	var back_h := 0.82

	geom.solid(holder, "Seat", Vector3(length, seat_h, depth),
			Vector3(0, seat_h * 0.5, 0), mat, facing_yaw)
	# 靠背在「后方」（局部 +Z）
	geom.solid(holder, "Back", Vector3(length, back_h, 0.22),
			Vector3(0, back_h * 0.5, depth * 0.5 - 0.11), mat, facing_yaw)
	# 两侧扶手
	geom.solid(holder, "ArmL", Vector3(0.22, 0.62, depth),
			Vector3(-length * 0.5 + 0.11, 0.31, 0), mat, facing_yaw)
	geom.solid(holder, "ArmR", Vector3(0.22, 0.62, depth),
			Vector3(length * 0.5 - 0.11, 0.31, 0), mat, facing_yaw)

	holder.position = pos
	return holder


## 单人扶手椅。
func armchair(parent: Node, node_name: String, pos: Vector3, facing_yaw: float,
		mat: Material) -> Node3D:
	return sofa(parent, node_name, pos, 0.95, facing_yaw, mat)


## 餐桌 / 任意桌面。size = (长, 高, 宽)。
func table(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var top_h := 0.07
	var leg_h := size.y - top_h
	var leg_inset := 0.12

	geom.solid(holder, "Top", Vector3(size.x, top_h, size.z),
			Vector3(0, leg_h + top_h * 0.5, 0), mat, yaw)
	# 四条腿，碰撞用，避免玩家钻进桌底
	var lx := size.x * 0.5 - leg_inset
	var lz := size.z * 0.5 - leg_inset
	for i in 4:
		var sx := -lx if i % 2 == 0 else lx
		var sz := -lz if i < 2 else lz
		geom.solid(holder, "Leg%d" % i, Vector3(0.08, leg_h, 0.08),
				Vector3(sx, leg_h * 0.5, sz), mat, yaw)

	holder.position = pos
	return holder


## 餐椅。座高 0.45，靠背到 0.9。
func chair(parent: Node, node_name: String, pos: Vector3, facing_yaw: float,
		mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.solid(holder, "Seat", Vector3(0.45, 0.06, 0.45), Vector3(0, 0.44, 0), mat, facing_yaw)
	geom.solid(holder, "Back", Vector3(0.45, 0.45, 0.05),
			Vector3(0, 0.68, 0.20), mat, facing_yaw)
	# 椅腿合并为一个矮台，避免四根细腿产生缝隙卡人
	geom.solid(holder, "Base", Vector3(0.40, 0.41, 0.40), Vector3(0, 0.205, 0), mat, facing_yaw)
	holder.position = pos
	return holder


## 橱柜 / 边柜 / 操作台（无腿的实心柜体）。
func cabinet(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.solid(holder, "Body", size, Vector3(0, size.y * 0.5, 0), mat, yaw)
	holder.position = pos
	return holder


## 厨房岛台：柜体 + 台面（台面比柜体宽出一点，视觉上像石材台面）。
func island(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		yaw: float, body_mat: Material, top_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	var top_h := 0.06
	geom.solid(holder, "Body", Vector3(size.x, size.y - top_h, size.z),
			Vector3(0, (size.y - top_h) * 0.5, 0), body_mat, yaw)
	geom.solid(holder, "Top", Vector3(size.x + 0.06, top_h, size.z + 0.06),
			Vector3(0, size.y - top_h * 0.5, 0), top_mat, yaw)
	holder.position = pos
	return holder


## 冰箱：一个实心高柜。
func fridge(parent: Node, node_name: String, pos: Vector3, yaw: float,
		mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.solid(holder, "Body", Vector3(0.75, 1.85, 0.72), Vector3(0, 0.925, 0), mat, yaw)
	holder.position = pos
	return holder


## 壁炉：炉膛 + 壁炉台，正面朝向局部 -Z。
func fireplace(parent: Node, node_name: String, pos: Vector3, width: float,
		yaw: float, mat: Material, hearth_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.solid(holder, "Body", Vector3(width, 1.20, 0.35), Vector3(0, 0.60, 0), mat, yaw)
	geom.solid(holder, "Mantel", Vector3(width + 0.20, 0.10, 0.45),
			Vector3(0, 1.25, 0), mat, yaw)
	# 炉膛开口（用深色体块表示，不真的挖洞，灰盒够用）
	geom.box(holder, "Chamber", Vector3(width * 0.6, 0.75, 0.06),
			Vector3(0, 0.55, -0.19), hearth_mat, yaw)
	holder.position = pos
	return holder


## 书桌 / 办公桌。
func desk(parent: Node, node_name: String, pos: Vector3, yaw: float,
		mat: Material) -> Node3D:
	return table(parent, node_name, pos, Vector3(1.4, 0.75, 0.7), yaw, mat)


## 笔记本（桌面上的小方块，用于标识办公角）。
func laptop(parent: Node, node_name: String, pos: Vector3, yaw: float,
		mat: Material, screen_mat: Material) -> Node3D:
	var holder := geom.node(parent, node_name)
	geom.box(holder, "Base", Vector3(0.34, 0.02, 0.24), Vector3(0, 0.01, 0), mat, yaw)
	geom.box(holder, "Screen", Vector3(0.34, 0.22, 0.015),
			Vector3(0, 0.12, -0.12), screen_mat, yaw)
	holder.position = pos
	return holder


## 地毯（纯视觉，无碰撞，避免绊人）。
func rug(parent: Node, node_name: String, pos: Vector3, size: Vector2,
		yaw: float, mat: Material) -> MeshInstance3D:
	return geom.box(parent, node_name, Vector3(size.x, 0.02, size.y),
			pos + Vector3(0, 0.011, 0), mat, yaw)
