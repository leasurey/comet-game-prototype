## SceneContent — 三个地点的实际内容
##
## 由 tools/scene_builder.gd 调用，产出可被 Godot 编辑器直接打开的标准 .tscn。
## 本文件是离线构建脚本，不属于游戏运行时代码。
##
## 构图前提：
##   观察点固定在 (0, 1.62, 0)，初始朝向 -Z。所有内容围绕这个视点摆放。
##
## 世界差异的总原则（务必遵守）：
##   差异必须写在对应的 Variant_world_* 节点里，或由热点的 visible_only_in_worlds 控制。
##   绝不允许用一个「每次加载随机决定」的方式制造差异。

class_name SceneContent
extends RefCounted

const S_HOTSPOT := "res://core/hotspot.gd"

var _mats: Dictionary = {}


# ------------------------------------------------------------------ helpers

func _mat(key: String, color: Color, roughness: float = 0.92, metallic: float = 0.0,
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


func _n(parent: Node, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	return n


func _box(parent: Node, node_name: String, size: Vector3, pos: Vector3, mat: Material,
		rot_y: float = 0.0, rot_z: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	var basis := Basis.IDENTITY
	if absf(rot_y) > 0.0001:
		basis = basis.rotated(Vector3.UP, rot_y)
	if absf(rot_z) > 0.0001:
		basis = basis.rotated(Vector3(0, 0, 1), rot_z)
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	return mi


## 生成「带碰撞的实体盒」：StaticBody3D 内含 MeshInstance3D 与 BoxShape3D。
##
## 与 _box() 的区别：_box 只产生可见几何，玩家可以穿过去；
## _solid 产生的几何同时具备 layer 1 的静态碰撞，玩家会被阻挡、可以站在上面。
##
## 注意：碰撞体与网格使用同一尺寸、同一旋转，因此视觉上与碰撞边界完全一致，
## 不会出现「看起来还有空隙却撞上」或「穿进模型一半」的情况。
func _solid(parent: Node, node_name: String, size: Vector3, pos: Vector3, mat: Material,
		rot_y: float = 0.0, rot_z: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0

	var basis := Basis.IDENTITY
	if absf(rot_y) > 0.0001:
		basis = basis.rotated(Vector3.UP, rot_y)
	if absf(rot_z) > 0.0001:
		basis = basis.rotated(Vector3(0, 0, 1), rot_z)
	body.transform = Transform3D(basis, pos)

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


func _cyl(parent: Node, node_name: String, radius: float, height: float, pos: Vector3,
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


func _omni(parent: Node, node_name: String, pos: Vector3, color: Color, energy: float,
		range_value: float = 12.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.shadow_enabled = false
	parent.add_child(light)
	return light


func _sun(parent: Node, node_name: String, yaw: float, pitch: float, color: Color,
		energy: float) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = node_name
	light.rotation_degrees = Vector3(pitch, yaw, 0.0)
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = false
	parent.add_child(light)
	return light


func _world_env(parent: Node, bg: Color, ambient: Color, fog_enabled: bool = false,
		fog_color: Color = Color(0.03, 0.03, 0.04), fog_density: float = 0.02) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_sky_contribution = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = fog_enabled
	if fog_enabled:
		env.fog_light_color = fog_color
		env.fog_density = fog_density
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)


func _spot(parent: Node, node_name: String, pos: Vector3, display_name: String,
		action_kind: String, examine_text: String, target: String = "",
		worlds: Array = []) -> Area3D:
	var spot := Area3D.new()
	spot.name = node_name
	spot.set_script(load(S_HOTSPOT))
	spot.position = pos
	spot.display_name = display_name
	spot.action_kind = action_kind
	spot.examine_text = examine_text
	spot.target_location = target
	spot.visible_only_in_worlds = worlds.duplicate()
	parent.add_child(spot)
	return spot


## 给热点加显式碰撞盒。先加此再加热点入树，Hotspot 就不会再生成自动碰撞体。
func _col(spot: Area3D, size: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "HitShape"
	cs.position = offset
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	spot.add_child(cs)


## 把热点带入树。必须在所有子节点（碰撞体、外壳）加完之后调用。
func _commit(parent: Node, spot: Area3D) -> Area3D:
	if spot.get_parent() == null:
		parent.add_child(spot)
	return spot


# ================================================================== 1. 客厅

func assemble_living_room(root: Node3D) -> void:
	var env := _n(root, "Environment")
	var shared := _n(env, "Shared")
	var va := _n(env, "Variant_world_alpha")
	var vb := _n(env, "Variant_world_beta")
	var hotspots := _n(root, "Hotspots")

	var m_wall := _mat("lr_wall", Color(0.70, 0.67, 0.61))
	var m_floor := _mat("lr_floor", Color(0.40, 0.30, 0.21))
	var m_ceil := _mat("lr_ceil", Color(0.60, 0.58, 0.55))
	var m_carpet := _mat("lr_carpet", Color(0.34, 0.23, 0.25))
	var m_sofa := _mat("lr_sofa", Color(0.27, 0.29, 0.33))
	var m_wood := _mat("lr_wood", Color(0.23, 0.17, 0.13))
	var m_metal := _mat("lr_metal", Color(0.52, 0.54, 0.57), 0.42, 0.6)
	var m_frame := _mat("lr_frame", Color(0.17, 0.14, 0.11))
	var m_photo := _mat("lr_photo", Color(0.74, 0.70, 0.62), 0.8, 0.0, Color(0.70, 0.66, 0.58), 0.28)
	var m_lamp := _mat("lr_lamp", Color(1.0, 0.80, 0.48), 0.5, 0.0, Color(1.0, 0.78, 0.45), 2.2)
	var m_tv_body := _mat("lr_tv_body", Color(0.12, 0.12, 0.13))
	var m_tv_on := _mat("lr_tv_on", Color(0.10, 0.12, 0.15), 0.3, 0.0, Color(0.30, 0.42, 0.55), 0.9)
	var m_tv_off := _mat("lr_tv_off", Color(0.04, 0.04, 0.05), 0.35)
	var m_door := _mat("lr_door", Color(0.30, 0.21, 0.15))
	var m_knob := _mat("lr_knob", Color(0.62, 0.55, 0.35), 0.35, 0.8)

	# ---- 房间外壳（不随世界变化）
	_solid(shared, "Floor", Vector3(7.2, 0.12, 6.2), Vector3(0, -0.06, 0), m_floor)
	_solid(shared, "Ceiling", Vector3(7.2, 0.12, 6.2), Vector3(0, 2.76, 0), m_ceil)
	_solid(shared, "WallBack", Vector3(7.2, 2.7, 0.16), Vector3(0, 1.35, -3.10), m_wall)
	_solid(shared, "WallFront", Vector3(7.2, 2.7, 0.16), Vector3(0, 1.35, 3.10), m_wall)
	_solid(shared, "WallLeft", Vector3(0.16, 2.7, 6.2), Vector3(-3.60, 1.35, 0), m_wall)
	_solid(shared, "WallRight", Vector3(0.16, 2.7, 6.2), Vector3(3.60, 1.35, 0), m_wall)
	_box(shared, "Rug", Vector3(3.4, 0.04, 2.6), Vector3(-0.3, 0.02, -1.2), m_carpet)

	# ---- 家具
	_solid(shared, "SofaBase", Vector3(2.3, 0.42, 0.95), Vector3(-1.35, 0.24, -0.55), m_sofa)
	_solid(shared, "SofaBack", Vector3(2.3, 0.62, 0.20), Vector3(-1.35, 0.62, -0.95), m_sofa)
	_box(shared, "SofaArmL", Vector3(0.22, 0.62, 0.95), Vector3(-2.38, 0.50, -0.55), m_sofa)
	_box(shared, "SofaArmR", Vector3(0.22, 0.62, 0.95), Vector3(-0.32, 0.50, -0.55), m_sofa)
	_solid(shared, "TableTop", Vector3(1.3, 0.07, 0.75), Vector3(-0.30, 0.40, -1.25), m_wood)
	_solid(shared, "TableBase", Vector3(1.0, 0.36, 0.50), Vector3(-0.30, 0.22, -1.25), m_wood)
	_solid(shared, "TVCabinet", Vector3(2.4, 0.55, 0.55), Vector3(0, 0.28, -2.55), m_wood)
	_box(shared, "TVBody", Vector3(1.64, 0.98, 0.10), Vector3(0, 1.10, -2.58), m_tv_body)
	_box(shared, "LampPole", Vector3(0.06, 1.45, 0.06), Vector3(2.25, 0.72, -1.75), m_metal)
	_cyl(shared, "LampShade", 0.24, 0.32, Vector3(2.25, 1.52, -1.75), m_lamp)
	_solid(shared, "ShelfBody", Vector3(0.44, 1.85, 1.70), Vector3(3.05, 0.92, -0.40), m_wood)
	_box(shared, "ShelfBoard", Vector3(0.46, 0.04, 1.72), Vector3(3.05, 1.30, -0.40), m_wood)

	# ---- 灯光（两版一致，保证「客厅变化」只体现在物件与屏幕）
	_omni(shared, "RoomFill", Vector3(0.0, 2.30, 0.0), Color(0.95, 0.88, 0.80), 0.45, 16.0)
	_omni(shared, "LampLight", Vector3(2.25, 1.52, -1.75), Color(1.0, 0.76, 0.44), 3.0, 9.0)

	# ---- 差异一：书架上的相框。alpha 正面朝房间，beta 背面朝房间。
	var frame_pos := Vector3(3.05, 1.62, -0.40)
	var pa := _n(va, "PhotoFrame")
	pa.transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, deg_to_rad(-90.0)), frame_pos)
	_box(pa, "FrameBody", Vector3(0.30, 0.36, 0.05), Vector3.ZERO, m_frame)
	_box(pa, "PhotoFace", Vector3(0.25, 0.31, 0.02), Vector3(0, 0, 0.036), m_photo)

	var pb := _n(vb, "PhotoFrame")
	pb.transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, deg_to_rad(90.0)), frame_pos)
	_box(pb, "FrameBody", Vector3(0.30, 0.36, 0.05), Vector3.ZERO, m_frame)
	_box(pb, "PhotoFace", Vector3(0.25, 0.31, 0.02), Vector3(0, 0, 0.036), m_photo)

	# ---- 差异二：电视屏幕。alpha 有微光（还开着），beta 彻底黑掉。
	_box(va, "TVScreen", Vector3(1.48, 0.84, 0.03), Vector3(0, 1.10, -2.515), m_tv_on)
	_box(vb, "TVScreen", Vector3(1.48, 0.84, 0.03), Vector3(0, 1.10, -2.515), m_tv_off)

	_world_env(root, Color(0.020, 0.020, 0.026), Color(0.17, 0.16, 0.15))

	# ---- 热点
	# 前门：位于前墙，玩家需要转身才能发现，这样能自然体会到「可以环视」
	var door := Area3D.new()
	door.name = "FrontDoor"
	door.set_script(load(S_HOTSPOT))
	door.position = Vector3(0, 1.15, 2.95)
	door.display_name = "前门"
	door.action_kind = "exit"
	door.examine_text = ""
	door.target_location = "house_exterior"
	_box(door, "DoorPanel", Vector3(1.10, 2.15, 0.12), Vector3.ZERO, m_door)
	_box(door, "DoorFrameTop", Vector3(1.24, 0.10, 0.18), Vector3(0, 1.16, 0.0), m_wood)
	_box(door, "DoorKnob", Vector3(0.07, 0.07, 0.10), Vector3(0.40, 0.0, 0.09), m_knob)
	_col(door, Vector3(1.4, 2.4, 0.5))
	hotspots.add_child(door)

	var tv := Area3D.new()
	tv.name = "Television"
	tv.set_script(load(S_HOTSPOT))
	tv.position = Vector3(0, 1.10, -2.55)
	tv.display_name = "那台没有声音的电视"
	tv.action_kind = "examine"
	tv.examine_text = "画面里是一片缓慢移动的光点。没有声音，也没有节目。"
	_col(tv, Vector3(1.8, 1.2, 0.5))
	hotspots.add_child(tv)

	var pf := Area3D.new()
	pf.name = "PhotoFrameSpot"
	pf.set_script(load(S_HOTSPOT))
	pf.position = frame_pos
	pf.display_name = "书架上的相框"
	pf.action_kind = "examine"
	pf.examine_text = "一张压在玻璃下的旧合影。你记得它一直面朝房间放着。"
	_col(pf, Vector3(0.5, 0.55, 0.5))
	hotspots.add_child(pf)

	var lamp := Area3D.new()
	lamp.name = "FloorLamp"
	lamp.set_script(load(S_HOTSPOT))
	lamp.position = Vector3(2.25, 1.20, -1.75)
	lamp.display_name = "落地灯"
	lamp.action_kind = "examine"
	lamp.examine_text = "灯罩边缘有一圈长期烘烤留下的黄痕。"
	_col(lamp, Vector3(0.7, 1.9, 0.7))
	hotspots.add_child(lamp)


# ============================================================ 2. 房屋外部

func assemble_house_exterior(root: Node3D) -> void:
	var env := _n(root, "Environment")
	var shared := _n(env, "Shared")
	var va := _n(env, "Variant_world_alpha")
	var vb := _n(env, "Variant_world_beta")
	var hotspots := _n(root, "Hotspots")

	var m_ground := _mat("he_ground", Color(0.23, 0.22, 0.19))
	var m_house := _mat("he_house", Color(0.58, 0.54, 0.49))
	var m_roof := _mat("he_roof", Color(0.19, 0.18, 0.19))
	var m_path := _mat("he_path", Color(0.33, 0.31, 0.27))
	var m_porch := _mat("he_porch", Color(0.35, 0.31, 0.27))
	var m_win_glow := _mat("he_win_glow", Color(0.92, 0.72, 0.44), 0.5, 0.0, Color(1.0, 0.72, 0.38), 1.4)
	var m_win_dark := _mat("he_win_dark", Color(0.045, 0.05, 0.065), 0.4)
	var m_tree := _mat("he_tree", Color(0.085, 0.115, 0.095))
	var m_trunk := _mat("he_trunk", Color(0.13, 0.10, 0.08))
	var m_crate := _mat("he_crate", Color(0.44, 0.35, 0.26))
	var m_metal_dark := _mat("he_metal", Color(0.28, 0.30, 0.32), 0.6, 0.5)
	var m_glass := _mat("he_glass", Color(0.36, 0.66, 0.80), 0.22, 0.1, Color(0.22, 0.48, 0.62), 1.0)
	var m_signboard := _mat("he_signboard", Color(0.74, 0.72, 0.66))
	var m_porch_bulb := _mat("he_bulb_on", Color(1.0, 0.84, 0.55), 0.4, 0.0, Color(1.0, 0.80, 0.48), 2.4)
	var m_porch_bulb_off := _mat("he_bulb_off", Color(0.14, 0.14, 0.15), 0.75)

	# —— 室外空间序列（车道 / 街道 / 街对面）所需材质
	var m_driveway := _mat("he_driveway", Color(0.26, 0.25, 0.23), 0.95)
	var m_asphalt := _mat("he_asphalt", Color(0.085, 0.088, 0.095), 0.88)
	var m_lane := _mat("he_lane", Color(0.52, 0.50, 0.42), 0.8)
	var m_curb := _mat("he_curb", Color(0.38, 0.36, 0.33), 0.9)
	var m_far_house := _mat("he_far_house", Color(0.13, 0.13, 0.15), 0.94)
	var m_far_win := _mat("he_far_win", Color(0.95, 0.76, 0.46), 0.5, 0.0, Color(1.0, 0.74, 0.42), 1.6)
	var m_car := _mat("he_car", Color(0.16, 0.17, 0.21), 0.42, 0.45)
	var m_car_glass := _mat("he_car_glass", Color(0.05, 0.06, 0.08), 0.18, 0.10)
	var m_tire := _mat("he_tire", Color(0.075, 0.075, 0.085), 0.98)
	var m_lamp_post := _mat("he_lamp_post", Color(0.19, 0.19, 0.21), 0.68, 0.40)
	var m_lamp_on := _mat("he_lamp_on", Color(1.0, 0.86, 0.58), 0.4, 0.0, Color(1.0, 0.78, 0.46), 2.2)
	var m_lamp_off := _mat("he_lamp_off", Color(0.12, 0.12, 0.13), 0.8)

	# ---- 地形与房屋主体（不随世界变化）
	# 地面需要覆盖车道、横向街道与街对面的房屋，因此由 40x40 扩到 56x60
	_solid(shared, "Ground", Vector3(56.0, 0.2, 60.0), Vector3(0, -0.10, -12.0), m_ground)

	# ---- 室外空间序列：门廊 → 台阶 → 车道 → 街道 → 黑暗路段
	# 这条轴线与玩家出门朝向一致（门廊朝 -Z），一路直走即可抵达黑暗区域，
	# 与影片中人物离开房子、穿过车道、走上街道、再走向没有灯那段路的动线对应。
	_box(shared, "Driveway", Vector3(6.4, 0.08, 9.6), Vector3(0, 0.01, -6.80), m_driveway)
	_box(shared, "Street", Vector3(44.0, 0.06, 6.5), Vector3(0, 0.02, -15.00), m_asphalt)
	_box(shared, "LaneCenter", Vector3(44.0, 0.02, 0.12), Vector3(0, 0.055, -15.00), m_lane)
	# 路缘在「车道口」和「黑暗路段口」两处断开，否则玩家会被那圈凸起挡住
	_box(shared, "CurbNearL", Vector3(18.8, 0.16, 0.24), Vector3(-12.60, 0.07, -11.70), m_curb)
	_box(shared, "CurbNearR", Vector3(18.8, 0.16, 0.24), Vector3(12.60, 0.07, -11.70), m_curb)
	_box(shared, "CurbFarL", Vector3(20.2, 0.16, 0.24), Vector3(-11.90, 0.07, -18.30), m_curb)
	_box(shared, "CurbFarR", Vector3(20.2, 0.16, 0.24), Vector3(11.90, 0.07, -18.30), m_curb)
	# 街道对面通往黑暗区域的路段：没有任何照明，与亮着灯的街道形成对比
	_box(shared, "DarkRoadMouth", Vector3(3.4, 0.08, 12.0), Vector3(0, 0.02, -24.00), m_path)

	# ---- 街对面那栋房子：影片里始终亮着窗的「别人的房子」
	_solid(shared, "FarHouse", Vector3(7.2, 3.6, 6.2), Vector3(-10.50, 1.80, -27.00), m_far_house)
	_box(shared, "FarHouseRoof", Vector3(8.0, 0.32, 7.0), Vector3(-10.50, 3.72, -27.00), m_roof)
	_box(shared, "FarWindowL", Vector3(1.15, 0.95, 0.06), Vector3(-12.20, 1.85, -23.85), m_far_win)
	_box(shared, "FarWindowR", Vector3(1.15, 0.95, 0.06), Vector3(-8.80, 1.85, -23.85), m_far_win)
	_omni(shared, "FarWindowGlow", Vector3(-10.50, 1.85, -23.40), Color(1.0, 0.78, 0.45), 1.6, 10.0)

	# ---- 停在车道上的车：影片中人物曾出门检查车辆
	# 车必须靠右侧停放，把 x≈0 这条主通路整条让出来。
	# 实测教训：车宽 1.8、最初停在 x=1.55 时，与玩家路径只剩 33cm 余量，
	# 玩家蹭上车身后会被 move_and_slide 一路滑到离轴线 4.3m 的草地上。
	_solid(shared, "CarBody", Vector3(1.76, 0.58, 4.20), Vector3(2.10, 0.40, -6.10), m_car)
	_solid(shared, "CarRoof", Vector3(1.58, 0.52, 2.10), Vector3(2.10, 0.95, -6.30), m_car)
	_box(shared, "CarGlassFront", Vector3(1.50, 0.34, 0.10), Vector3(2.10, 0.97, -5.24), m_car_glass)
	_box(shared, "CarGlassBack", Vector3(1.50, 0.34, 0.10), Vector3(2.10, 0.97, -7.36), m_car_glass)
	_box(shared, "WheelFL", Vector3(0.18, 0.54, 0.54), Vector3(1.24, 0.27, -4.68), m_tire)
	_box(shared, "WheelFR", Vector3(0.18, 0.54, 0.54), Vector3(2.96, 0.27, -4.68), m_tire)
	_box(shared, "WheelRL", Vector3(0.18, 0.54, 0.54), Vector3(1.24, 0.27, -7.52), m_tire)
	_box(shared, "WheelRR", Vector3(0.18, 0.54, 0.54), Vector3(2.96, 0.27, -7.52), m_tire)

	# ---- 街道照明：灯柱本体固定，灯头亮度随世界变化
	# 影片的停电是全区域的，所以 beta 世界里连路灯也熄灭，只剩月光。
	_cyl(shared, "LampPostA", 0.09, 4.8, Vector3(-8.00, 2.40, -18.55), m_lamp_post)
	_box(shared, "LampArmA", Vector3(1.30, 0.10, 0.10), Vector3(-7.40, 4.72, -18.55), m_lamp_post)
	_cyl(shared, "LampPostB", 0.09, 4.8, Vector3(8.00, 2.40, -18.55), m_lamp_post)
	_box(shared, "LampArmB", Vector3(1.30, 0.10, 0.10), Vector3(7.40, 4.72, -18.55), m_lamp_post)

	_box(va, "LampHeadA", Vector3(0.34, 0.16, 0.34), Vector3(-6.80, 4.62, -18.55), m_lamp_on)
	_omni(va, "StreetLightA", Vector3(-6.80, 4.45, -18.55), Color(1.0, 0.74, 0.40), 4.5, 26.0)
	_box(va, "LampHeadB", Vector3(0.34, 0.16, 0.34), Vector3(6.80, 4.62, -18.55), m_lamp_on)
	_omni(va, "StreetLightB", Vector3(6.80, 4.45, -18.55), Color(1.0, 0.74, 0.40), 4.5, 26.0)

	_box(vb, "LampHeadA", Vector3(0.34, 0.16, 0.34), Vector3(-6.80, 4.62, -18.55), m_lamp_off)
	_box(vb, "LampHeadB", Vector3(0.34, 0.16, 0.34), Vector3(6.80, 4.62, -18.55), m_lamp_off)

	# ---- 建筑立面：与 party_house 的 13.4 × 9.4 外轮廓严格对齐
	# 旧立面是 6.6 × 5.2，玩家从室内走出去会看到一栋只有实际尺寸一半的房子。
	# 现在 HouseBody 直接占 x -6.70~6.70 / z 0.00~9.40，前墙落在 z=0，
	# 与 party_house 的前门平面重合，穿门前后看到的是同一栋建筑。
	_solid(shared, "HouseBody", Vector3(13.4, 3.2, 9.4), Vector3(0, 1.60, 4.70), m_house)
	_box(shared, "Roof", Vector3(14.2, 0.35, 10.2), Vector3(0, 3.38, 4.70), m_roof)

	# 门廊：z -2.20 ~ 0，顶面 0.10（比室内地面 0.20 低一级）
	_solid(shared, "PorchFloor", Vector3(5.6, 0.30, 2.2), Vector3(0, -0.05, -1.10), m_porch)

	# 前墙上两扇窗，嵌在墙体内（墙面 z=0，墙厚 0.20）
	_box(shared, "WindowFrameL", Vector3(1.44, 1.20, 0.12), Vector3(-3.50, 1.85, -0.02), m_roof)
	_box(shared, "WindowFrameR", Vector3(1.44, 1.20, 0.12), Vector3(3.50, 1.85, -0.02), m_roof)

	# 门廊灯罩：挂在前门上方、门外一侧
	_box(shared, "PorchFixture", Vector3(0.26, 0.26, 0.26), Vector3(0, 2.52, -0.22), m_metal_dark)

	# 树：固定在几个坐标上，不使用随机，保证每次构建结果完全一致
	var tree_positions: Array = [
		Vector3(-6.5, 0.0, -2.0), Vector3(-8.2, 0.0, -7.5), Vector3(-7.0, 0.0, -13.0),
		Vector3(6.8, 0.0, -3.5), Vector3(8.6, 0.0, -9.0), Vector3(7.2, 0.0, -15.0),
		# 最后两棵原在 (-5.5,3.5) / (5.8,4.2)，房屋扩到 13.4×9.4 后会落在室内，移到两侧
		Vector3(-9.5, 0.0, 3.5), Vector3(9.8, 0.0, 4.2),
	]
	for i in tree_positions.size():
		var p: Vector3 = tree_positions[i]
		var height := 5.0 + float(i % 3) * 0.8
		_cyl(shared, "Trunk%d" % i, 0.22, height, Vector3(p.x, height * 0.5, p.z), m_trunk)
		_box(shared, "Crown%d" % i, Vector3(3.0, 2.6, 3.0), Vector3(p.x, height + 0.6, p.z), m_tree)

	# 月光：两个世界的强弱与色温不同，这是「灯光变化」的一部分
	_sun(va, "MoonlightAlpha", -35.0, -42.0, Color(0.62, 0.70, 0.92), 0.35)
	_sun(vb, "MoonlightBeta", -35.0, -42.0, Color(0.52, 0.64, 0.98), 0.85)

	# ---- 差异二（灯光）：alpha 门廊灯亮着、窗户透出暖光；beta 门廊灯熄灭、窗户全黑
	_box(va, "PorchBulb", Vector3(0.18, 0.18, 0.18), Vector3(0, 2.52, -0.22), m_porch_bulb)
	_omni(va, "PorchLight", Vector3(0.0, 2.45, -0.55), Color(1.0, 0.78, 0.46), 5.5, 16.0)
	_box(va, "WindowPaneL", Vector3(1.28, 1.04, 0.04), Vector3(-3.50, 1.85, -0.04), m_win_glow)
	_box(va, "WindowPaneR", Vector3(1.28, 1.04, 0.04), Vector3(3.50, 1.85, -0.04), m_win_glow)
	_omni(va, "WindowSpill", Vector3(-3.50, 1.80, -0.40), Color(1.0, 0.72, 0.40), 1.2, 7.0)

	_box(vb, "PorchBulb", Vector3(0.18, 0.18, 0.18), Vector3(0, 2.52, -0.22), m_porch_bulb_off)
	_box(vb, "WindowPaneL", Vector3(1.28, 1.04, 0.04), Vector3(-3.50, 1.85, -0.04), m_win_dark)
	_box(vb, "WindowPaneR", Vector3(1.28, 1.04, 0.04), Vector3(3.50, 1.85, -0.04), m_win_dark)

	# ---- 差异一（物品位置）：木箱从右侧正立，变成左侧倾倒
	var crate_a := _n(va, "Crate")
	_solid(crate_a, "CrateBody", Vector3(0.78, 0.58, 0.62), Vector3(1.60, 0.29, -1.60), m_crate, deg_to_rad(-14.0))
	_solid(crate_a, "CrateLid", Vector3(0.82, 0.06, 0.66), Vector3(1.60, 0.58, -1.60), m_crate, deg_to_rad(-14.0))

	var crate_b := _n(vb, "Crate")
	_solid(crate_b, "CrateBody", Vector3(0.78, 0.58, 0.62), Vector3(-1.55, 0.26, -2.30), m_crate, deg_to_rad(22.0), deg_to_rad(38.0))
	_solid(crate_b, "CrateLid", Vector3(0.82, 0.06, 0.66), Vector3(-1.42, 0.55, -2.10), m_crate, deg_to_rad(22.0), deg_to_rad(38.0))

	# ---- 差异三（新增线索）：beta 的台阶旁多出一滩碎玻璃，alpha 完全没有
	var glass := _n(vb, "GlassShards")
	_box(glass, "Shard1", Vector3(0.16, 0.02, 0.22), Vector3(-0.45, 0.21, -1.10), m_glass, deg_to_rad(18.0))
	_box(glass, "Shard2", Vector3(0.12, 0.02, 0.16), Vector3(-0.18, 0.21, -1.32), m_glass, deg_to_rad(-42.0))
	_box(glass, "Shard3", Vector3(0.10, 0.02, 0.13), Vector3(-0.62, 0.21, -1.38), m_glass, deg_to_rad(64.0))
	_box(glass, "Shard4", Vector3(0.09, 0.02, 0.11), Vector3(-0.30, 0.21, -0.92), m_glass, deg_to_rad(-8.0))

	# ---- 差异四（门牌歪斜）：同一个门牌，beta 里歪了
	_box(va, "HouseNumber", Vector3(0.34, 0.22, 0.03), Vector3(0.86, 1.92, -0.13), m_signboard)
	_box(vb, "HouseNumber", Vector3(0.34, 0.22, 0.03), Vector3(0.86, 1.92, -0.13), m_signboard, 0.0, deg_to_rad(24.0))

	_world_env(root, Color(0.016, 0.018, 0.028), Color(0.13, 0.14, 0.19))

	# ---- 热点
	# 回屋的门：位于房子立面，玩家需要转身才能看到
	var door := Area3D.new()
	door.name = "DoorToInterior"
	door.set_script(load(S_HOTSPOT))
	# 门位于前墙 z=0 外表面一侧，与 party_house 的前门洞（x=0，宽 1.60）对齐
	door.position = Vector3(0, 1.15, -0.05)
	door.display_name = "前门"
	door.action_kind = "exit"
	# 修正：原先指向 living_room（第一阶段遗留的独立客厅）。
	# 玩家从新住宅前门出去，回来却进了另一个客厅，动线彻底断掉。
	# 现在直接回到 party_house 的前门内侧，朝向 +Z（面朝屋内）。
	door.target_location = "party_house"
	door.use_target_spawn = true
	door.target_spawn = Vector3(0.0, 0.25, 1.60)
	door.target_yaw_deg = 180.0
	_box(door, "DoorPanel", Vector3(1.10, 2.15, 0.12), Vector3.ZERO, m_metal_dark)
	_col(door, Vector3(1.6, 2.4, 0.5))
	hotspots.add_child(door)

	# 黑暗区域入口：改为区域触发（AutoPortal），走进去即进入，不再需要按 E。
	# 位置仍是街道西端 z=-19.20，动线「门廊 → 车道 → 横穿街道 → 走进黑暗」不变。
	# 用 portal 而不是 hotspot 的原因：黑暗穿越必须是「走过去」，按键那一刻就不是穿越了。
	var dark_entry := Area3D.new()
	dark_entry.name = "DarkEntry"
	dark_entry.set_script(load("res://core/auto_portal.gd"))
	dark_entry.position = Vector3(0, 1.10, -19.20)
	dark_entry.portal_id = "dark_entry"
	dark_entry.target_location = "dark_road"
	dark_entry.use_target_spawn = true
	dark_entry.target_spawn = Vector3(0.0, 0.05, 4.0)
	dark_entry.target_yaw_deg = 0.0
	_box(dark_entry, "SignPost", Vector3(0.10, 1.40, 0.10), Vector3(-0.55, 0.20, 0.0), m_metal_dark)
	_box(dark_entry, "SignBoard", Vector3(0.90, 0.34, 0.05), Vector3(-0.10, 0.72, 0.0), m_signboard)
	_col(dark_entry, Vector3(2.4, 2.4, 1.2))
	shared.add_child(dark_entry)

	# 车道上的车：影片中人物曾出门绕到车边检查
	var car_spot := Area3D.new()
	car_spot.name = "ParkedCar"
	car_spot.set_script(load(S_HOTSPOT))
	car_spot.position = Vector3(2.10, 0.95, -6.10)
	car_spot.display_name = "停在车道上的车"
	car_spot.action_kind = "examine"
	car_spot.examine_text = "车门锁着，钥匙在屋里。仪表盘上那点微光还亮着，说明电瓶没断。"
	_col(car_spot, Vector3(2.2, 1.8, 4.6))
	hotspots.add_child(car_spot)

	# 街对面始终亮着窗的房子：影片里那个「另一扇亮着的窗」
	var far_spot := Area3D.new()
	far_spot.name = "FarHouseWindow"
	far_spot.set_script(load(S_HOTSPOT))
	far_spot.position = Vector3(-10.50, 1.85, -23.70)
	far_spot.display_name = "街对面亮着窗的房子"
	far_spot.action_kind = "examine"
	far_spot.examine_text = "同一排的房子，同样的窗。那扇窗里的灯一直没灭过，而这一片已经停电了。"
	_col(far_spot, Vector3(5.0, 2.4, 1.0))
	hotspots.add_child(far_spot)

	# 木箱：位置随世界变化，因此按世界各放一个热点，互斥显示
	var crate_spot_a := Area3D.new()
	crate_spot_a.name = "CrateAlpha"
	crate_spot_a.set_script(load(S_HOTSPOT))
	crate_spot_a.position = Vector3(1.60, 0.45, -1.60)
	crate_spot_a.display_name = "一只木箱"
	crate_spot_a.action_kind = "examine"
	crate_spot_a.examine_text = "装杂物用的旧木箱，盖子合得很严。"
	crate_spot_a.visible_only_in_worlds = ["world_alpha"]
	_col(crate_spot_a, Vector3(1.0, 0.9, 1.0))
	hotspots.add_child(crate_spot_a)

	var crate_spot_b := Area3D.new()
	crate_spot_b.name = "CrateBeta"
	crate_spot_b.set_script(load(S_HOTSPOT))
	crate_spot_b.position = Vector3(-1.50, 0.42, -2.25)
	crate_spot_b.display_name = "一只木箱"
	crate_spot_b.action_kind = "examine"
	crate_spot_b.examine_text = "同一只木箱。它刚才不在这个位置，而且现在是倒着的。"
	crate_spot_b.visible_only_in_worlds = ["world_beta"]
	_col(crate_spot_b, Vector3(1.2, 0.9, 1.2))
	hotspots.add_child(crate_spot_b)

	# 碎玻璃：初始世界不存在，穿越后才有
	var shard := Area3D.new()
	shard.name = "GlassShards"
	shard.set_script(load(S_HOTSPOT))
	shard.position = Vector3(-0.40, 0.30, -1.20)
	shard.display_name = "一地的碎玻璃"
	shard.action_kind = "examine"
	shard.examine_text = "蓝色的碎片散在台阶旁。屋子里没有少任何一只杯子。"
	shard.visible_only_in_worlds = ["world_beta"]
	_col(shard, Vector3(1.1, 0.5, 1.1))
	hotspots.add_child(shard)

	# 邮箱：两个世界都在，用于锚定「这里确实是同一个地方」
	var mailbox := Area3D.new()
	mailbox.name = "Mailbox"
	mailbox.set_script(load(S_HOTSPOT))
	mailbox.position = Vector3(2.55, 1.15, -1.30)
	mailbox.display_name = "邮箱"
	mailbox.action_kind = "examine"
	mailbox.examine_text = "空的。今天没有人来送信。"
	_box(mailbox, "Post", Vector3(0.10, 1.20, 0.10), Vector3(0, -0.60, 0), m_trunk)
	_box(mailbox, "Box", Vector3(0.42, 0.30, 0.58), Vector3.ZERO, m_metal_dark)
	_col(mailbox, Vector3(0.8, 1.6, 0.9))
	hotspots.add_child(mailbox)

	# 通往「另一栋房子」的入口。
	# 叙事上这是一栋与本宅几乎一样的房子——影片的核心设定正是「同一栋房子的不同版本」。
	# 灰盒阶段它的内部由 tools/house/ 单独构建，不在本文件里。
	# 注：这里原有一个 ExitToPartyHouse 热点（display_name「另一栋房子的前门」），
	# 它是在 party_house 尚无正式回屋入口时加的桥接：从室外走向"另一栋房子"其实会
	# 回到 party_house 本身，语义是错的。
	# 现在 DoorToInterior 已直接通向 party_house 并携带门级落点，桥接不再需要，
	# 故移除。未来若加入真正的邻宅 neighbor_house，应新建热点指向它，而不是复用它。


# ============================================================== 3. 黑暗区域

func assemble_dark_road(root: Node3D) -> void:
	var env := _n(root, "Environment")
	var shared := _n(env, "Shared")
	var va := _n(env, "Variant_world_alpha")
	var vb := _n(env, "Variant_world_beta")
	var hotspots := _n(root, "Hotspots")

	var m_ground := _mat("dr_ground", Color(0.115, 0.115, 0.108))
	var m_road := _mat("dr_road", Color(0.235, 0.228, 0.212))
	var m_tree := _mat("dr_tree", Color(0.045, 0.062, 0.052))
	var m_trunk := _mat("dr_trunk", Color(0.062, 0.052, 0.045))
	var m_pole := _mat("dr_pole", Color(0.11, 0.11, 0.12))
	var m_signboard := _mat("dr_signboard", Color(0.30, 0.29, 0.27))
	var m_puddle := _mat("dr_puddle", Color(0.10, 0.17, 0.24), 0.12, 0.35, Color(0.20, 0.38, 0.52), 0.35)
	var m_far := _mat("dr_far", Color(0.16, 0.19, 0.24), 0.5, 0.0, Color(0.28, 0.36, 0.46), 0.5)

	# ---- 地形与道路
	_solid(shared, "Ground", Vector3(60.0, 0.2, 70.0), Vector3(0, -0.10, -20.0), m_ground)
	_box(shared, "Road", Vector3(3.4, 0.08, 46.0), Vector3(0, 0.02, -18.0), m_road)
	_box(shared, "RoadEdgeL", Vector3(0.30, 0.14, 46.0), Vector3(-1.85, 0.04, -18.0), m_tree)
	_box(shared, "RoadEdgeR", Vector3(0.30, 0.14, 46.0), Vector3(1.85, 0.04, -18.0), m_tree)

	# ---- 两侧树林（固定坐标，不使用随机）
	var left_trees: Array = [-2.0, -6.5, -11.0, -16.5, -22.0, -28.0]
	var right_trees: Array = [-3.5, -8.0, -13.5, -19.0, -25.0, -31.0]
	for i in left_trees.size():
		var z: float = left_trees[i]
		var x: float = -3.6 - float(i % 3) * 1.1
		var h: float = 6.0 + float(i % 4) * 0.7
		_cyl(shared, "TrunkL%d" % i, 0.26, h, Vector3(x, h * 0.5, z), m_trunk)
		_box(shared, "CrownL%d" % i, Vector3(3.6, 3.2, 3.6), Vector3(x, h + 1.0, z), m_tree)
	for i in right_trees.size():
		var z2: float = right_trees[i]
		var x2: float = 3.6 + float(i % 3) * 1.1
		var h2: float = 6.2 + float(i % 4) * 0.7
		_cyl(shared, "TrunkR%d" % i, 0.26, h2, Vector3(x2, h2 * 0.5, z2), m_trunk)
		_box(shared, "CrownR%d" % i, Vector3(3.6, 3.2, 3.6), Vector3(x2, h2 + 1.0, z2), m_tree)

	# ---- 电线杆：一路延伸进黑暗
	var poles: Array = [-4.0, -12.0, -20.0, -28.0]
	for i in poles.size():
		var pz: float = poles[i]
		_cyl(shared, "Pole%d" % i, 0.13, 7.0, Vector3(-2.6, 3.5, pz), m_pole)
		_box(shared, "Crossarm%d" % i, Vector3(1.50, 0.12, 0.14), Vector3(-2.6, 6.7, pz), m_pole)

	# ---- 灯光：只有很弱的月光，营造「看不清远处」的压迫感
	_sun(shared, "Moonlight", -25.0, -38.0, Color(0.50, 0.60, 0.90), 0.42)
	_omni(shared, "PlayerPool", Vector3(0, 1.20, 0.5), Color(0.55, 0.62, 0.80), 0.55, 9.0)

	# ---- 远方一点微光：暗示这条路确实通向别处
	_box(shared, "FarGlow", Vector3(2.60, 0.60, 0.06), Vector3(0, 0.55, -36.0), m_far)

	# ---- alpha：干燥的路面；beta：路面上出现一滩积水，反光明显
	_box(vb, "Puddle1", Vector3(1.60, 0.02, 2.30), Vector3(-0.35, 0.07, -3.20), m_puddle, deg_to_rad(8.0))
	_box(vb, "Puddle2", Vector3(1.10, 0.02, 1.60), Vector3(0.55, 0.07, -6.40), m_puddle, deg_to_rad(-14.0))
	_box(vb, "Puddle3", Vector3(0.90, 0.02, 1.30), Vector3(-0.70, 0.07, -9.10), m_puddle, deg_to_rad(22.0))

	_world_env(root, Color(0.008, 0.010, 0.016), Color(0.07, 0.08, 0.12), true,
			Color(0.020, 0.024, 0.034), 0.055)

	# ---- 热点
	# 原路返回：位于玩家背后，必须转身才能找到
	# 黑暗尽头：走出这段路即完成穿越。
	# 这里同时做两件事：切到街对面、触发现实变化（规则见 world_transitions.json），
	# 顺序由 main.gd 保证——先求值事件（换现实），再切场景，避免闪一帧旧世界。
	var dark_exit := Area3D.new()
	dark_exit.name = "DarkExit"
	dark_exit.set_script(load("res://core/auto_portal.gd"))
	dark_exit.position = Vector3(0, 1.10, -20.0)
	dark_exit.portal_id = "dark_far_end"
	dark_exit.target_location = "house_exterior"
	dark_exit.use_target_spawn = true
	dark_exit.target_spawn = Vector3(0.0, 0.05, -24.0)
	dark_exit.target_yaw_deg = 0.0
	dark_exit.event_kind = "area_enter"
	dark_exit.event_keys = {"area_id": "dark_far_end"}
	_col(dark_exit, Vector3(3.4, 2.6, 2.0))
	shared.add_child(dark_exit)

	var sign := Area3D.new()
	sign.name = "RoadSign"
	sign.set_script(load(S_HOTSPOT))
	sign.position = Vector3(1.95, 1.45, -2.60)
	sign.display_name = "一块路牌"
	sign.action_kind = "examine"
	sign.examine_text = "牌面上的字被磨掉了，只剩下几道浅浅的划痕。"
	_box(sign, "SignPost", Vector3(0.09, 1.50, 0.09), Vector3(0, -0.75, 0), m_pole)
	_box(sign, "SignBoard", Vector3(0.62, 0.44, 0.05), Vector3.ZERO, m_signboard)
	_col(sign, Vector3(0.9, 1.8, 0.6))
	hotspots.add_child(sign)

	var deep := Area3D.new()
	deep.name = "DeeperIntoDark"
	deep.set_script(load(S_HOTSPOT))
	deep.position = Vector3(0, 0.95, -11.0)
	deep.display_name = "更深的黑暗"
	deep.action_kind = "examine"
	deep.examine_text = "再往前就什么都看不见了。今晚不该走那么远。"
	_col(deep, Vector3(3.4, 2.2, 1.0))
	hotspots.add_child(deep)

	var puddle := Area3D.new()
	puddle.name = "PuddleSpot"
	puddle.set_script(load(S_HOTSPOT))
	puddle.position = Vector3(-0.35, 0.20, -3.20)
	puddle.display_name = "积水"
	puddle.action_kind = "examine"
	puddle.examine_text = "路面洼处积着水，映着天光。来的时候这里是干的。"
	puddle.visible_only_in_worlds = ["world_beta"]
	_col(puddle, Vector3(2.0, 0.6, 2.6))
	hotspots.add_child(puddle)
