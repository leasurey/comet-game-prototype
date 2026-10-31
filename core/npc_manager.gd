## NPCManager — NPC 的生成、导航与状态管理
##
## 职责边界：
##   负责「NPC 群体的生命周期」：加载档案、生成实体、烘焙导航、存档恢复。
##   单个 NPC 的行为在 NPC 类里；说什么在 DialogueManager 里。
##
## 导航职责（这是本类存在的主要理由）：
##   NavigationRegion3D 必须是场景几何的**祖先**（见 NAVIGATION_FEASIBILITY.md），
##   所以本类在地点实例之上建 region 并烘焙，而不是让每个 NPC 自己烘。
##
## 时序约束（踩过的坑，必须守住）：
##   烘焙前等 ≥8 物理帧（碰撞体未建立 → 0 多边形）
##   烘焙后等 ≥12 物理帧才能查询（NavigationServer 未同步 → 查询返回空）

class_name NPCManager
extends Node

signal navigation_ready

## 第一阶段：只生成指定 NPC（空=生成全部）
## 垂直切片只出 Kevin，避免方块人出现
@export var spawn_list: Array[String] = []
signal npc_talk_requested(npc_id: String)
## NPC 到达行走目标（CT-021 接线：NPC 行为 → 事件系统）。
signal npc_arrived(npc_id: String, room_id: String)

## 参数取 cell 网格的整数倍，消除 Recast 的量化告警：
##   agent_radius 0.30 / cell_size 0.10 = 3 格（精确）
##   agent_height 1.70 / cell_height 0.10 = 17 格（精确）
##   agent_max_climb 0.30 / cell_height 0.10 = 3 格（精确）
## 更细的 cell 也改善了 1.20 m 门洞处的分辨率。
const AGENT_RADIUS := 0.30
const CELL_SIZE := 0.10
const FLOOR_Y := 0.20
## 导航几何来源分组名。地点实例加入此组后，烘焙会解析它及其全部子节点。
const NAV_SOURCE_GROUP := "nav_source"

## 烘焙与查询的物理帧等待（依据可行性报告）
const BAKE_WAIT_FRAMES := 8
const SYNC_WAIT_FRAMES := 12
## 烘焙出 0 多边形时的重试上限（碰撞体偶发未就绪，重烘即可恢复）
const MAX_BAKE_RETRIES := 2

var _cognition = null
var _dialogue = null
var _characters: Dictionary = {}
var _rooms: Dictionary = {}
var _npcs: Dictionary = {}
var _region: NavigationRegion3D = null
var _nav_ready := false
var _bake_phase := 0
var _bake_retries := 0
var _pf_mark := 0

## 会话级状态快照（CT-003/004 的修复核心）。
##
## 角色在离场时实体照常 free，但状态留在这里；重入时按快照恢复，
## 「出门再回来 NPC 回到出生点」的断裂就此消除。存档读写同样走这张表：
## restore() 先写入本表，spawn_all() 消费本表——因此 restore 在
## spawn 之前或之后调用都正确（旧设计 restore 只写活实体，先于 spawn 调用会被覆盖）。
## 字典结构与 serialize() 条目一致：{id, position, rotation_y, state, target}。
var _session_states: Dictionary = {}
var _pending_container: Node = null

## 当前现实 id（NPC 记忆归档用，由 GameServices 在世界切换时更新）。
var _current_world_id: String = ""

## NPC 逻辑属性（事件 effects 的 npc_state 写入此处）。
## 与实体分离：实体销毁后属性仍在（会话快照机制），入档一并保存。
## 键为 NPC id，值为任意字典（behavior/room/mood 等）。
var _npc_attrs: Dictionary = {}
## 每个 NPC 当前被派往的房间 id（npc_arrived 事件上下文用）。
var _npc_target_room: Dictionary = {}


## 写入 NPC 逻辑属性（合并语义：只覆盖给定键，不删除未提及键）。
func set_npc_attrs(npc_id: String, attrs: Dictionary) -> void:
	if npc_id.is_empty() or attrs.is_empty():
		return
	if not _npc_attrs.has(npc_id):
		_npc_attrs[npc_id] = {}
	var cur: Dictionary = _npc_attrs[npc_id]
	for k in attrs.keys():
		cur[str(k)] = attrs[k]


## 读取 NPC 逻辑属性（返回副本）。
func get_npc_attrs(npc_id: String) -> Dictionary:
	if not _npc_attrs.has(npc_id):
		return {}
	return (_npc_attrs[npc_id] as Dictionary).duplicate(true)


## 全替换式写入（事务回滚用）：丢弃现有属性，完全替换为给定字典。
## 与 set_npc_attrs（合并语义）互补——合并回滚会残留新增键，全替换不会。
func replace_npc_attrs(npc_id: String, attrs: Dictionary) -> void:
	if npc_id.is_empty():
		return
	_npc_attrs[npc_id] = attrs.duplicate(true)


## 更新当前现实 id 并同步到所有在场 NPC（记忆归档用）。
func update_world(world_id: String) -> void:
	_current_world_id = world_id
	for id in _npcs.keys():
		if is_instance_valid(_npcs[id]) and _npcs[id] is NPC:
			(_npcs[id] as NPC).set_current_world(world_id)


func set_cognition(cog) -> void:
	_cognition = cog


func set_dialogue(dlg) -> void:
	_dialogue = dlg


func load_from_data(characters_data: Dictionary, out_error: Array = []) -> bool:
	_characters.clear()
	_rooms.clear()
	var raw_npcs: Variant = characters_data.get("npcs", null)
	if typeof(raw_npcs) != TYPE_ARRAY:
		out_error.append("characters.json 缺少 npcs 数组")
		return false
	for n in (raw_npcs as Array):
		var id := str((n as Dictionary).get("id", "")).strip_edges()
		if id.is_empty():
			out_error.append("characters.json 有角色缺少 id")
			return false
		if _characters.has(id):
			out_error.append("characters.json 角色 id 重复: %s" % id)
			return false
		_characters[id] = (n as Dictionary).duplicate(true)

	var raw_rooms: Variant = characters_data.get("rooms", null)
	if typeof(raw_rooms) == TYPE_DICTIONARY:
		for rid in (raw_rooms as Dictionary).keys():
			_rooms[str(rid)] = ((raw_rooms as Dictionary)[rid] as Dictionary).duplicate(true)
	return true


func get_character_ids() -> Array:
	return _characters.keys()


func get_npc(npc_id: String) -> NPC:
	return _npcs.get(npc_id, null)


func get_all_npcs() -> Array:
	var out: Array = []
	for id in _npcs.keys():
		out.append(_npcs[id])
	return out


func get_all_npc_ids() -> Array:
	return _npcs.keys().duplicate()


func is_nav_ready() -> bool:
	return _nav_ready


## 在给定容器（地点实例）下生成所有 NPC 并烘焙导航。
## container 必须是场景几何所在的节点，region 会挂在它上面成为几何祖先。
func spawn_all(container: Node) -> void:
	# 垂直切片：只生成 spawn_list 中的 NPC（空=全部）
	var to_spawn: Array = []
	if spawn_list.size() > 0:
		for nid in spawn_list:
			if _characters.has(nid):
				to_spawn.append(nid)
	else:
		to_spawn = _characters.keys()
	_despawn_all()
	_pending_container = container
	if container == null:
		return

	# region 必须是几何的祖先：挂在地点实例上，实例的子树就是几何
	_region = NavigationRegion3D.new()
	_region.name = "NPCNavRegion"
	# 先进树：进树后 region 才会分配到导航地图，
	# 也才能在下面设置 map 的 cell 参数。
	container.add_child(_region)

	var mesh := NavigationMesh.new()
	mesh.cell_size = CELL_SIZE
	mesh.cell_height = 0.10
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_height = 1.70
	mesh.agent_max_climb = 0.30
	mesh.agent_max_slope = 40.0
	mesh.region_min_size = 2.0
	mesh.region_merge_size = 10.0
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	# 用分组解析而不是 ROOT_NODE_CHILDREN。
	# 原因：NavigationRegion3D 必须是几何的**祖先**才能用 ROOT_NODE_CHILDREN，
	# 而这里 region 是挂在地点实例之下的（几何是它的兄弟）。
	# 分组模式按 group 名收集节点及其子树，正好覆盖这种情况。
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = NAV_SOURCE_GROUP

	# 必须在**赋 navigation_mesh 之前**把地图的 cell 参数对齐到 mesh。
	# 告警是在 set_navigation_mesh 那一刻发出的，之后再改地图已经晚了。
	var map_rid: RID = _region.get_navigation_map()
	NavigationServer3D.map_set_cell_size(map_rid, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map_rid, 0.10)

	_region.navigation_mesh = mesh
	container.add_to_group(NAV_SOURCE_GROUP)


	for id in to_spawn:
		_spawn_one(str(id), container)
	for id in _npcs.keys():
		(_npcs[id] as NPC).set_current_world(_current_world_id)

	# 会话快照优先于配置出生点（CT-004）：离场前的位置/行为/目标继续。
	for id in _npcs.keys():
		if _session_states.has(id):
			(_npcs[id] as NPC).restore(_session_states[id] as Dictionary)

	_nav_ready = false
	_bake_phase = 1
	# 必须记「此刻」的物理帧号。此前误写 0，等于「引擎启动满 8 帧」——
	# bootstrap 早超 8 帧，烘焙实际紧跟生成立刻跑，撞上物理服务器的
	# 碰撞体注册窗口就烘出 0 多边形（N3 连通性 0/42 的抖动根因）。
	_pf_mark = Engine.get_physics_frames()
	_bake_retries = 0


func _spawn_one(id: String, container: Node) -> void:
	var info: Dictionary = _characters[id]
	var npc := NPC.new()
	npc.setup(id, str(info.get("name", id)), str(info.get("home", "")))
	# 人物外观（P2）：从 characters.json 的 appearance 读取
	var app: Variant = info.get("appearance", null)
	if typeof(app) == TYPE_DICTIONARY:
		var a: Dictionary = app
		npc.setup_appearance(
				Color(a.get("skin", [0.85, 0.72, 0.62])[0], a.get("skin", [0.85, 0.72, 0.62])[1], a.get("skin", [0.85, 0.72, 0.62])[2]),
				Color(a.get("hair", [0.25, 0.18, 0.12])[0], a.get("hair", [0.25, 0.18, 0.12])[1], a.get("hair", [0.25, 0.18, 0.12])[2]),
				Color(a.get("shirt", [0.35, 0.45, 0.65])[0], a.get("shirt", [0.35, 0.45, 0.65])[1], a.get("shirt", [0.35, 0.45, 0.65])[2]),
				Color(a.get("pants", [0.25, 0.25, 0.30])[0], a.get("pants", [0.25, 0.25, 0.30])[1], a.get("pants", [0.25, 0.25, 0.30])[2]))
	# 人物系统：注入行为参数与可游荡房间 + 游荡回调（P0-1：显式注入）
	npc.setup_personality(info.get("traits", []) as Array)
	npc.set_wander_rooms(_rooms.keys())
	npc.wander_callback = npc_wander_to
	# 行为 → 事件（CT-021）：NPC 到达目标时交给上层求值 npc_arrived 事件
	npc.arrived.connect(_on_npc_arrived.bind(id))
	container.add_child(npc)

	# 出生点：优先用角色自带的 spawn（互相错开，避免重叠被物理顶飞），
	# 没有才回退到房间坐标。Y 一律取 FLOOR_Y（navmesh 的 Y 会浮空 0.2~0.4 m）。
	var pos := _room_position(str(info.get("home", "hall")))
	var sp: Variant = info.get("spawn", null)
	if typeof(sp) == TYPE_ARRAY and (sp as Array).size() >= 3:
		var arr: Array = sp
		pos = Vector3(float(arr[0]), FLOOR_Y, float(arr[2]))
	# 出生点同样要吸附：手写坐标可能落在孤立的 navmesh 岛上，
	# 导致 NPC 永远走不出来（路径只生成一半就断）。
	npc.global_position = _snap_to_nav(pos)
	_npcs[id] = npc


func _room_position(room_id: String) -> Vector3:
	if _rooms.has(room_id):
		var r: Dictionary = _rooms[room_id]
		var p: Variant = r.get("position", null)
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
			var arr: Array = p
			return Vector3(float(arr[0]), FLOOR_Y, float(arr[2]))
	# 兜底：玄关
	return Vector3(0.0, FLOOR_Y, 1.6)


func _despawn_all() -> void:
	# 离场快照（CT-004）：实体销毁前把状态留进 _session_states，
	# 同 id 再次 spawn_all 时自动续上（位置/朝向/行为/行走目标）。
	for id in _npcs.keys():
		var n: Node = _npcs[id]
		if is_instance_valid(n) and n is NPC:
			_session_states[id] = (n as NPC).serialize()
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_npcs.clear()
	if _pending_container != null and is_instance_valid(_pending_container):
		if _pending_container.is_in_group(NAV_SOURCE_GROUP):
			_pending_container.remove_from_group(NAV_SOURCE_GROUP)
	_pending_container = null
	if _region != null and is_instance_valid(_region):
		if _region.get_parent() != null:
			_region.get_parent().remove_child(_region)
		_region.free()
	_region = null
	_nav_ready = false
	_bake_phase = 0


## 会话级清空（新局用）：丢弃快照，下一局全员回配置出生点。
func reset_session() -> void:
	_session_states.clear()
	_npc_attrs.clear()
	_npc_target_room.clear()


## 每帧驱动：烘焙时序与 NPC 状态推进。
## 退出清理说明：NPC 与 region 都是场景树节点，退出时随树一起释放，
## 这里**不能**再 queue_free——退出阶段消息队列已不再消化，
## 排队释放反而制造孤儿。只需断开引用，防止脚本成员把它们拖到泄漏名单。
func _exit_tree() -> void:
	_npcs.clear()
	_region = null
	_pending_container = null
	_nav_ready = false
	_bake_phase = 0


func tick() -> void:
	if _bake_phase == 1:
		# 必须等碰撞体真正建立，否则烘焙出 0 个多边形
		if Engine.get_physics_frames() - _pf_mark >= BAKE_WAIT_FRAMES:
			if _region != null:
				_region.bake_navigation_mesh(false)
			_bake_phase = 2
			_pf_mark = Engine.get_physics_frames()
	elif _bake_phase == 2:
		# 必须等 NavigationServer 同步，否则查询返回空
		if Engine.get_physics_frames() - _pf_mark >= SYNC_WAIT_FRAMES:
			# 同步后先验收再宣称就绪：0 多边形说明碰撞体当时没就绪，
			# 直接就绪会让所有寻路静默失败（表现为 NPC 站着不动、
			# 连通性测试 0/42）。重烘几次几乎总能恢复。
			if get_nav_polygon_count() == 0 and _bake_retries < MAX_BAKE_RETRIES:
				_bake_retries += 1
				_bake_phase = 1
				_pf_mark = Engine.get_physics_frames()
				return
			_bake_phase = 0
			_nav_ready = true
			# 恢复快照带来的行走目标是在烘焙完成前设给 agent 的，
			# 那时查不到路径；就绪后统一重发，让被恢复的 NPC 继续走。
			for id in _npcs.keys():
				var n: NPC = _npcs[id]
				if n != null and n.state == NPC.STATE_WALKING and n.has_goal():
					n.move_to(n.get_goal())
			navigation_ready.emit()


## 当前导航网格的多边形数。0 = 烘焙失败/未烘焙，用于验收与诊断。
func get_nav_polygon_count() -> int:
	if _region == null or _region.navigation_mesh == null:
		return 0
	return _region.navigation_mesh.get_polygon_count()


## 让 NPC 走向某个房间。
## 目标点先吸附到 navmesh——房间坐标是设计值，可能落在家具/墙边的不可走区，
## 不吸附会导致「路径只生成一半就断」，表现为 NPC 站着不动。
func send_to_room(npc_id: String, room_id: String) -> bool:
	if not _nav_ready:
		return false
	var npc := get_npc(npc_id)
	if npc == null:
		return false
	_npc_target_room[npc_id] = room_id
	npc.move_to(_snap_to_nav(_room_position(room_id)))
	return true


## 让 NPC 走向一个具体点（先吸附到 navmesh）。
func send_to_point(npc_id: String, point: Vector3) -> bool:
	if not _nav_ready:
		return false
	var npc := get_npc(npc_id)
	if npc == null:
		return false
	_npc_target_room.erase(npc_id)  # 无房间语义
	npc.move_to(_snap_to_nav(Vector3(point.x, FLOOR_Y, point.z)))
	return true


## NPC 自主游荡回调（NPC._process_autonomy 调用）。
## 解析房间坐标并派目标，等价于 send_to_room 但不覆盖 _npc_target_room
## （自主游荡不是"被派任务"，到达后不触发 npc_arrived 事件）。
func npc_wander_to(npc_id: String, room_id: String) -> void:
	if not _nav_ready:
		return
	var npc := get_npc(npc_id)
	if npc == null:
		return
	npc.move_to(_snap_to_nav(_room_position(room_id)))


## NPC 到达行走目标 → 转发为 npc_arrived 信号（供事件系统求值）。
func _on_npc_arrived(npc_id: String) -> void:
	var room := str(_npc_target_room.get(npc_id, ""))
	_npc_target_room.erase(npc_id)
	npc_arrived.emit(npc_id, room)


## 把任意点吸附到 navmesh 上最近的可走点。
## 不做这一步，落在家具/墙边的目标会让寻路返回**半截路径**，
## 表现为「NPC 站着不动」——这是本轮实测踩到的。
func _snap_to_nav(p: Vector3) -> Vector3:
	# 未同步就查询会报 "map query failed because it was made before first
	# map synchronization"。出生时烘焙还没跑，必须直接返回原值。
	if _region == null or not _nav_ready:
		return p
	var snapped := NavigationServer3D.map_get_closest_point(
			_region.get_navigation_map(), p)
	if snapped == Vector3.ZERO:
		return p
	return Vector3(snapped.x, FLOOR_Y, snapped.z)


## 找出此刻离给定位置最近、且可交谈的 NPC。
func find_talkable_near(pos: Vector3, max_dist: float = 2.5) -> NPC:
	var best: NPC = null
	var best_d := max_dist
	for id in _npcs.keys():
		var n: NPC = _npcs[id]
		if n.is_talking():
			continue
		var d := n.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = n
	return best


# ---------------------------------------------------------------- 存档

## 序列化全部 NPC 状态。离场快照也一并输出（CT-003）：
## 玩家在住宅外保存时 npc_states 不再是空表，读档回来进屋即恢复。
## 逻辑属性（_npc_attrs，事件 npc_state 效果写入）随记录一并入档。
func serialize() -> Array:
	var out: Array = []
	var seen := {}
	for id in _npcs.keys():
		if is_instance_valid(_npcs[id]) and _npcs[id] is NPC:
			var rec := (_npcs[id] as NPC).serialize()
			if _npc_attrs.has(id):
				rec["attrs"] = (_npc_attrs[id] as Dictionary).duplicate(true)
			out.append(rec)
			seen[id] = true
	for id in _session_states.keys():
		if not seen.has(id):
			var rec2 := (_session_states[id] as Dictionary).duplicate(true)
			if _npc_attrs.has(id):
				rec2["attrs"] = (_npc_attrs[id] as Dictionary).duplicate(true)
			out.append(rec2)
			seen[id] = true
	# 纯属性记录（NPC 无状态快照但有逻辑属性）也要保存
	for id in _npc_attrs.keys():
		if not seen.has(id):
			out.append({"id": id, "position": null, "rotation_y": 0.0,
				"state": "idle", "target": null,
				"attrs": (_npc_attrs[id] as Dictionary).duplicate(true)})
	return out


## 恢复 NPC 状态（CT-003）。
##
## 双写设计：先落 _session_states（spawn_all 消费），再覆盖活实体（若已在场）。
## 因此 restore 可以在场景生成之前或之后调用，结果一致——
## 旧实现只写活实体，先于 spawn 调用会被无条件重建覆盖。
## 逻辑属性（attrs 字段）写入 _npc_attrs。
func restore(list: Array) -> void:
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var rec := (item as Dictionary).duplicate(true)
		var id := str(rec.get("id", ""))
		if id.is_empty():
			continue
		# 逻辑属性独立恢复
		if rec.has("attrs"):
			var attrs_raw: Variant = rec.get("attrs")
			if typeof(attrs_raw) == TYPE_DICTIONARY:
				_npc_attrs[id] = (attrs_raw as Dictionary).duplicate(true)
			rec.erase("attrs")
		_session_states[id] = rec
		if _npcs.has(id) and is_instance_valid(_npcs[id]) and _npcs[id] is NPC:
			(_npcs[id] as NPC).restore(rec)
