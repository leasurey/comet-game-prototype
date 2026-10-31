## Hotspot — 场景中的可交互对象
##
## 这是 InteractionManager 唯一认识的节点类型。
## 热点本身不含任何剧情逻辑，只负责声明「我是什么」「点了之后要做什么」，
## 具体由 InteractionManager 派发给 SceneManager / UI 处理。
##
## visible_only_in_worlds 为空数组时表示在所有世界都可见；
## 非空时，只有当前世界 id 在列表内才显示并可交互。

class_name Hotspot
extends Area3D

signal focus_changed(hotspot: Hotspot, focused: bool)

@export var display_name: String = ""
@export var prompt: String = "查看"
@export var action_kind: String = "examine"
@export var target_location: String = ""
@export var examine_text: String = ""
@export var visible_only_in_worlds: Array = []

## 亲自检查本物品时额外授予的语义事实 id（CT-019）。
##
## inspect 默认只写 fact_inspected_<热点名>（如 fact_inspected_StudyDesk），
## 而对话闸门使用语义 id（如 fact_sticky_note）——两者不同名导致
## 「门上的便签」这类话题在真实游玩中永远无法解锁。
## 非空时，examine 会同时写入本字段指定的事实，把「亲眼看到」与
## 「对话可引用」接通。留空则行为与旧版完全一致。
@export var grants_fact: String = ""

## 二级观察点（CT-016）：检查物品时可产生多条子观察。
## 格式：[{"text": "屏幕上有几个数字", "fact_id": "obs_screen_digits", "hearsay": false}]
## text: 观察内容；fact_id: 可选，非空时同时授予玩家认知事实；
## hearsay: true = 转述（从别人那听来），false = 亲眼所见。
## examine 处理链会为每条 observe 写入 CognitionManager 的 observations 账本。
@export var observes: Array = []

## exit 热点的门级落点。
##
## 地点级 spawn 只能回答「这个场景从哪儿开始」，回答不了「玩家是从哪扇门进来的」。
## 前门、侧门、露台门若共用地点 spawn，出去一律落在同一点、同一朝向，
## 穿门前后就没有空间连续性可言。
##
## use_target_spawn 为 true 时，进入 target_location 后由热点携带的
## target_spawn / target_yaw_deg 决定位置与朝向；为 false 时沿用地点 spawn。
@export var use_target_spawn: bool = false
@export var target_spawn: Vector3 = Vector3.ZERO
@export var target_yaw_deg: float = 0.0

## 关联的门控制器节点名（三级：门热点 → 门控制器 → 过槛切换）。
## 非空时，exit 热点不再直接传送，而是开门等待玩家实际跨过门槛。
@export var door_name: String = ""

var _focused: bool = false
var _shape_ready: bool = false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	_ensure_collision_shape()


## 若场景中没有显式给出碰撞体，自动补一个球形区域，
## 保证「看得见就一定点得到」，避免热点成为哑对象。
func _ensure_collision_shape() -> void:
	if _shape_ready:
		return
	for child in get_children():
		if child is CollisionShape3D:
			_shape_ready = true
			return

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = _estimate_radius()
	shape.shape = sphere
	shape.name = "AutoShape"
	add_child(shape)
	_shape_ready = true


func _estimate_radius() -> float:
	var aabb := _local_aabb()
	var size := aabb.size
	if size.x <= 0.001 and size.y <= 0.001 and size.z <= 0.001:
		return 0.35
	return clampf(max(size.x, max(size.y, size.z)) * 0.6, 0.25, 1.6)


func _local_aabb() -> AABB:
	var combined := AABB()
	var found := false
	for child in get_children():
		if child is VisualInstance3D:
			var box: AABB = (child as VisualInstance3D).get_aabb()
			if not found:
				combined = box
				found = true
			else:
				combined = combined.merge(box)
	if not found:
		combined = AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))
	return combined


func is_focused() -> bool:
	return _focused


func set_focused(value: bool) -> void:
	if _focused == value:
		return
	_focused = value
	_update_visual_feedback()
	focus_changed.emit(self, value)


func _update_visual_feedback() -> void:
	# 悬停反馈刻意做得很轻：只轻微提亮自发光，不使用描边或跳动图标，
	# 以免破坏「热点不过度突出」的影片基调。
	_apply_emission(1.0)


## 给本热点的可见子网格设置/取消自发光。
##
## 关键点：**必须逐实例复制材质**。
## 场景构建器 tools/lib/geom.gd 与 tools/scene_content.gd 的 _mat() 按 key 缓存材质，
## 全场景大量网格共用同一个 StandardMaterial3D 实例。若直接改这个实例，
## 凝视一个门把手会让所有共用该材质的物体一起发光。
## 复制后用 meta 标记，保证只复制一次——否则每次聚焦都新建材质，数量会无限增长。
func _apply_emission(scale_factor: float) -> void:
	for child in get_children():
		if not (child is GeometryInstance3D):
			continue
		var gi := child as GeometryInstance3D
		var mat: StandardMaterial3D = null
		if gi.material_override is StandardMaterial3D:
			mat = gi.material_override as StandardMaterial3D
		else:
			mat = StandardMaterial3D.new()

		if not mat.has_meta("comet_own"):
			mat = mat.duplicate() as StandardMaterial3D
			mat.set_meta("comet_own", true)
			gi.material_override = mat

		mat.emission_enabled = _focused
		mat.emission = Color(1.0, 0.88, 0.62) * (0.22 * scale_factor)


## 热点的显示与否由世界状态驱动，而不是随机决定。
func apply_world(world_id: String) -> void:
	if visible_only_in_worlds.is_empty():
		visible = true
		return
	visible = visible_only_in_worlds.has(world_id)
	# 不可见的热点必须同时失去碰撞能力，防止出现空气墙式的隐形交互
	monitorable = visible
	collision_layer = 2 if visible else 0
	if not visible:
		set_focused(false)


func is_interactable() -> bool:
	if not is_instance_valid(self):
		return false
	if not is_inside_tree():
		return false
	# 使用 is_visible_in_tree 而非 visible：父级 variant 被隐藏时也必须判定为不可交互
	return visible and is_visible_in_tree()


func get_hint_text() -> String:
	if display_name.is_empty():
		return ""
	return "%s" % display_name
