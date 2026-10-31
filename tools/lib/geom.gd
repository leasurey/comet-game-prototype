## HouseGeom — 房屋灰盒的通用几何构建库
##
## 职责边界：
##   只负责「把一个几何意图变成 Godot 节点」，不认识房间、不摆放家具、不读剧情。
##   由 tools/house/*.gd 调用。
##
## 这是离线构建脚本的一部分，不进入运行时依赖。
##
## 为什么单独成文件：
##   scene_content.gd 已承载三个旧场景，若继续堆入整栋房屋会失控；
##   而旧场景必须保持原样以规避回归风险，因此新能力放在独立库里，两边互不引用。
##
## 碰撞约定：
##   collision_layer 固定为 1（静态环境层）。
##   InteractionManager 的遮挡判定读的就是 layer 1，玩家胶囊也与之碰撞。

class_name HouseGeom
extends RefCounted

const WALL_LAYER := 1

var _mats: Dictionary = {}


# ------------------------------------------------------------------ 材质

## 材质按 key 缓存，同一 key 多次调用返回同一实例，避免生成大量重复资源。
func mat(key: String, color: Color, roughness: float = 0.92, metallic: float = 0.0,
		emission: Color = Color(0, 0, 0), emission_energy: float = 1.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission.r > 0.0 or emission.g > 0.0 or emission.b > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_mats[key] = m
	return m


# ------------------------------------------------------------------ 容器与基础体

func node(parent: Node, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	return n


func _basis(rot_y: float, rot_z: float) -> Basis:
	var b := Basis.IDENTITY
	if absf(rot_y) > 0.0001:
		b = b.rotated(Vector3.UP, rot_y)
	if absf(rot_z) > 0.0001:
		b = b.rotated(Vector3(0, 0, 1), rot_z)
	return b


## 纯视觉盒体，不产生碰撞。
func box(parent: Node, node_name: String, size: Vector3, pos: Vector3, mat: Material,
		rot_y: float = 0.0, rot_z: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(_basis(rot_y, rot_z), pos)
	parent.add_child(mi)
	return mi


## 带碰撞的实体盒体（StaticBody3D + BoxShape3D + MeshInstance3D）。
func solid(parent: Node, node_name: String, size: Vector3, pos: Vector3, mat: Material,
		rot_y: float = 0.0, rot_z: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	body.transform = Transform3D(_basis(rot_y, rot_z), pos)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)

	parent.add_child(body)
	return body


func cyl(parent: Node, node_name: String, radius: float, height: float, pos: Vector3,
		mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	mi.transform = Transform3D(Basis.IDENTITY, pos)
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ 带洞口的墙

## 构建一面带洞口的墙。
##
## 这是做房间最关键的原语：整块盒子的墙无法开门窗，直接留缺口又会漏光、玩家能穿出。
## 正确做法是把墙沿长度方向切成若干段：
##
##   axis = "x"（墙沿 X 延伸，厚度在 Z）
##     ┌────┬───────────┬────┐   ← 门楣段（洞口上方）
##     │左段│   洞口     │右段│
##     └────┴───────────┴────┘
##
##   洞口不到顶时（窗），洞口下方还会生成窗台段。
##
## 参数 cfg：
##   axis         "x" 或 "z"，墙的延伸方向
##   center       Vector3，墙段的水平中心（只取 x/z，y 由 base_y 与 height 决定）
##   length       墙长（沿 axis）
##   thickness    墙厚
##   height       墙高
##   base_y       墙底部的 y 坐标，默认 0
##   opening      可选，未提供则生成实心墙
##     offset       洞口中心相对墙中心沿 axis 的偏移
##     width        洞口宽
##     height       洞口高（从洞口底算起）
##     bottom       洞口底距墙底的高度，默认 0（门）
##
## 返回承载所有墙段的 Node3D 容器；每个墙段都是独立的 StaticBody3D。
func wall_with_opening(parent: Node, node_name: String, cfg: Dictionary, mat: Material) -> Node3D:
	var axis := str(cfg.get("axis", "x"))
	var center: Vector3 = cfg.get("center", Vector3.ZERO)
	var length := float(cfg.get("length", 1.0))
	var thickness := float(cfg.get("thickness", 0.2))
	var height := float(cfg.get("height", 2.7))
	var base_y := float(cfg.get("base_y", 0.0))
	# 每端裁剪量（消除墙角 z-fighting）。默认 0——只有外轮廓墙在
	# house_party.gd 中显式传 corner_trim。内墙 T 接头不需要裁剪，
	# 强制裁剪会破坏连通性（navigation_feasibility_test N2/N3）。
	var corner_trim := float(cfg.get("corner_trim", 0.0))

	var holder := node(parent, node_name)

	if not cfg.has("opening"):
		_segment(holder, "Solid", axis, center, -length * 0.5 + corner_trim,
				length - corner_trim * 2.0, base_y, height, thickness, mat)
		return holder

	var op: Dictionary = cfg["opening"]
	var op_offset := float(op.get("offset", 0.0))
	var op_width := float(op.get("width", 0.9))
	var op_height := float(op.get("height", 2.1))
	var op_bottom := float(op.get("bottom", 0.0))

	# 洞口沿墙方向的两端（相对墙中心），受 corner_trim 裁剪
	var open_start := op_offset - op_width * 0.5
	var open_end := op_offset + op_width * 0.5
	var half := length * 0.5 - corner_trim
	var neg_half := -length * 0.5 + corner_trim

	# 左段
	var left_len := open_start - neg_half
	if left_len > 0.0005:
		_segment(holder, "Left", axis, center, neg_half, left_len, base_y, height, thickness, mat)

	# 右段
	var right_len := half - open_end
	if right_len > 0.0005:
		_segment(holder, "Right", axis, center, open_end, right_len, base_y, height, thickness, mat)

	# 洞口上方的过梁（门楣）。洞口通顶时不生成。
	var top_y := op_bottom + op_height
	var lintel_h := height - top_y
	if lintel_h > 0.0005:
		_segment(holder, "Lintel", axis, center, open_start, op_width, base_y + top_y,
				lintel_h, thickness, mat)

	# 洞口下方的窗台。门（bottom=0）时不生成。
	if op_bottom > 0.0005:
		_segment(holder, "Sill", axis, center, open_start, op_width, base_y, op_bottom,
				thickness, mat)

	return holder


## 生成单个墙段。start 与 length 都沿 axis 方向，以墙中心为原点。
func _segment(holder: Node3D, seg_name: String, axis: String, center: Vector3,
		start: float, seg_length: float, bottom_y: float, seg_height: float,
		thickness: float, mat: Material) -> void:
	var mid := start + seg_length * 0.5
	var y := bottom_y + seg_height * 0.5

	if axis == "x":
		solid(holder, seg_name,
				Vector3(seg_length, seg_height, thickness),
				Vector3(center.x + mid, y, center.z), mat)
	else:
		solid(holder, seg_name,
				Vector3(thickness, seg_height, seg_length),
				Vector3(center.x, y, center.z + mid), mat)


# ------------------------------------------------------------------ 门体

## 生成带铰链的真实门体（门板 + 门框 + 把手）。
##
## 门板以铰链侧（hinge_side="left"|"right"）为旋转轴心，
## 通过 Node3D pivot 实现开合动画。门框固定不动。
##
## 参数：
##   pos       门洞中心位置（世界坐标）
##   size      门板尺寸 (width, height, thickness)
##   hinge_side "left" = 左侧铰链（门向右开），"right" = 右侧铰链（门向左开）
##   open_angle 开启角度（度），默认 95°
##
## 返回 {"frame": Node3D, "door_pivot": Node3D}——door_pivot 用于动画旋转。
func door(parent: Node, node_name: String, pos: Vector3, size: Vector3,
		hinge_side: String, mat: Material, frame_mat: Material = null,
		open_angle: float = 95.0, yaw_deg: float = 0.0) -> Dictionary:
	var fm: Material = frame_mat if frame_mat != null else mat
	var holder := node(parent, node_name)
	# 局部坐标构建：holder 定位到门中心并绕 Y 旋转
	holder.position = pos
	holder.rotation.y = deg_to_rad(yaw_deg)

	var w := size.x
	var h := size.y
	var t := size.z

	# 门框（相对门中心）
	var ft := 0.08
	box(holder, "FrameLeft", Vector3(ft, h + 0.06, t + 0.06),
			Vector3(-w * 0.5 - ft * 0.5, 0, 0), fm)
	box(holder, "FrameRight", Vector3(ft, h + 0.06, t + 0.06),
			Vector3(w * 0.5 + ft * 0.5, 0, 0), fm)
	box(holder, "FrameTop", Vector3(w + ft * 2.0, 0.06, t + 0.06),
			Vector3(0, h * 0.5 + 0.03, 0), fm)

	# 铰链轴心（局部）
	var pivot := Node3D.new()
	pivot.name = node_name + "Pivot"
	var pivot_x := -w * 0.5 if hinge_side == "left" else w * 0.5
	pivot.position = Vector3(pivot_x, 0, 0)
	holder.add_child(pivot)

	# 门板碰撞体
	var door_body := StaticBody3D.new()
	door_body.name = node_name + "Body"
	door_body.collision_layer = 0
	door_body.collision_mask = 0
	door_body.set_meta("is_door", true)
	var door_x := (w * 0.5) if hinge_side == "left" else (-w * 0.5)
	door_body.position = Vector3(door_x, 0, 0)
	pivot.add_child(door_body)

	# 门板视觉
	var slab := MeshInstance3D.new()
	slab.name = "DoorSlab"
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, t)
	slab.mesh = bm
	slab.material_override = mat
	door_body.add_child(slab)

	# 碰撞形状
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, t)
	cs.shape = bs
	door_body.add_child(cs)

	# 把手
	var handle_x := door_x + (w * 0.35 if hinge_side == "left" else -w * 0.35)
	box(door_body, "Handle", Vector3(0.04, 0.12, 0.10),
			Vector3(handle_x, 0.0, t * 0.5 + 0.05), fm)

	# 装饰面板
	box(door_body, "PanelTop", Vector3(w * 0.7, h * 0.35, t * 0.4),
			Vector3(door_x, h * 0.25, 0), mat)
	box(door_body, "PanelBottom", Vector3(w * 0.7, h * 0.35, t * 0.4),
			Vector3(door_x, -h * 0.25, 0), mat)

	pivot.rotation.y = 0.0

	# 运行时控制器（局部原点=门中心）
	var controller: Node3D = load("res://core/door_controller.gd").new()
	controller.name = node_name + "Controller"
	holder.add_child(controller)
	controller.position = Vector3.ZERO
	controller.setup(pivot, door_body)

	return {"frame": holder, "door_pivot": pivot, "door_body": door_body, "controller": controller}


# ------------------------------------------------------------------ 房间外壳

## 按矩形房间生成四面墙（可分别指定是否有洞口）。
##
## cfg：
##   center_x, center_z   房间中心
##   size_x, size_z       房间净尺寸（内表面之间）
##   thickness            墙厚（默认 0.2）
##   height               墙高（默认 2.7）
##   base_y               地面 y（默认 0）
##   openings             可选数组，每项：
##     side       "north"|"south"|"east"|"west"
##     offset     沿该墙中心的偏移
##     width / height / bottom
##
## 说明：墙按「内表面尺寸 + 墙厚」外扩，四角会重叠，但重叠不影响碰撞
## （玩家无法进入墙角内部），也不影响视觉。
func room_shell(parent: Node, node_name: String, cfg: Dictionary, mat: Material) -> Node3D:
	var cx := float(cfg.get("center_x", 0.0))
	var cz := float(cfg.get("center_z", 0.0))
	var sx := float(cfg.get("size_x", 4.0))
	var sz := float(cfg.get("size_z", 4.0))
	var t := float(cfg.get("thickness", 0.2))
	var h := float(cfg.get("height", 2.7))
	var by := float(cfg.get("base_y", 0.0))

	var holder := node(parent, node_name)
	var openings: Array = cfg.get("openings", [])

	var by_side := {}
	for o in openings:
		var od: Dictionary = o
		by_side[str(od.get("side", ""))] = od

	# 北墙（z = cz - sz/2 - t/2），沿 X
	_make_side(holder, "North", "x", Vector3(cx, 0, cz - sz * 0.5 - t * 0.5), sx + t * 2.0, t, h, by,
			by_side.get("north", null), mat)
	# 南墙
	_make_side(holder, "South", "x", Vector3(cx, 0, cz + sz * 0.5 + t * 0.5), sx + t * 2.0, t, h, by,
			by_side.get("south", null), mat)
	# 西墙（x = cx - sx/2 - t/2），沿 Z
	_make_side(holder, "West", "z", Vector3(cx - sx * 0.5 - t * 0.5, 0, cz), sz, t, h, by,
			by_side.get("west", null), mat)
	# 东墙
	_make_side(holder, "East", "z", Vector3(cx + sx * 0.5 + t * 0.5, 0, cz), sz, t, h, by,
			by_side.get("east", null), mat)

	return holder


func _make_side(holder: Node3D, side_name: String, axis: String, center: Vector3,
		length: float, thickness: float, height: float, base_y: float,
		opening: Variant, mat: Material) -> void:
	var cfg := {
		"axis": axis,
		"center": center,
		"length": length,
		"thickness": thickness,
		"height": height,
		"base_y": base_y,
	}
	if opening != null:
		var od: Dictionary = opening
		cfg["opening"] = {
			"offset": float(od.get("offset", 0.0)),
			"width": float(od.get("width", 0.9)),
			"height": float(od.get("height", 2.1)),
			"bottom": float(od.get("bottom", 0.0)),
		}
	wall_with_opening(holder, side_name, cfg, mat)
