## HouseLight — 灯光与环境原语
##
## 职责边界：
##   只负责「造一个光源 / 一套环境」，不认识房间用途。
##   何时亮、何时灭由 house_lighting.gd 决定。
##
## 离线构建脚本的一部分，不进入运行时依赖。

class_name HouseLight
extends RefCounted


func omni(parent: Node, node_name: String, pos: Vector3, color: Color, energy: float,
		range_value: float = 10.0, shadows: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = node_name
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_value
	l.shadow_enabled = shadows
	parent.add_child(l)
	return l


func spot(parent: Node, node_name: String, pos: Vector3, rot_deg: Vector3, color: Color,
		energy: float, range_value: float = 12.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.name = node_name
	l.position = pos
	l.rotation_degrees = rot_deg
	l.light_color = color
	l.light_energy = energy
	l.spot_range = range_value
	l.shadow_enabled = false
	parent.add_child(l)
	return l


func sun(parent: Node, node_name: String, yaw: float, pitch: float, color: Color,
		energy: float) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = node_name
	l.rotation_degrees = Vector3(pitch, yaw, 0.0)
	l.light_color = color
	l.light_energy = energy
	l.shadow_enabled = false
	parent.add_child(l)
	return l


## 环境设置。
## 注意 Godot 4.7 的属性名是 ambient_light_source，不是 ambient_source；
## 早期版本写成 ambient_source 会静默失败（已踩过一次）。
func world_env(parent: Node, bg: Color, ambient: Color, fog_enabled: bool = false,
		fog_color: Color = Color(0.03, 0.03, 0.04), fog_density: float = 0.02) -> WorldEnvironment:
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
	return we
