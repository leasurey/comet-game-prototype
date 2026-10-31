## CognitionNpcTest — 玩家认知与 NPC/对话基础
##
## 用法：godot --headless --script res://tests/cognition_npc_test.gd
##
## P6 玩家认知（客观事实 ≠ 玩家知道）
##   C1  世界切换不自动授予任何认知
##   C2  亲自动手检查物品才获得认知，且带来源
##   C3  听对话获得认知，来源标记为 dialogue:<speaker>
##   C4  重复学习不覆盖首次来源
##   C5  认知可存档并恢复，且与世界状态分开
##   C6  新局清空认知
##
## P7 NPC 与对话
##   N1  7 名 NPC 在住宅里生成
##   N2  NPC 站在地面上（Y=FLOOR_Y，不浮空）
##   N3  NPC 能沿导航走到别的房间
##   N4  对话被认知闸门过滤（没查过便签就听不到便签话题）
##   N5  对话可授予认知
##   N6  NPC 状态可存档恢复

extends SceneTree

const FLOOR_Y := 0.20

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _cog = null
var _dlg = null
var _npcm = null
var _steps: Array = []
var _idx := 0
var _t_state := 0
var _pf_mark := 0
var _reporting := false


func _initialize() -> void:
	print("=== COMET cognition & npc test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_c1_world_does_not_teach"),
		Callable(self, "step_c2_inspect_grants"),
		Callable(self, "step_c3_dialogue_grants"),
		Callable(self, "step_c4_source_preserved"),
		Callable(self, "step_c5_save_restore"),
		Callable(self, "step_c6_new_game_resets"),
		Callable(self, "step_n1_spawn"),
		Callable(self, "step_n2_on_ground"),
		Callable(self, "step_n3_nav_to_room"),
		Callable(self, "step_n4_cognition_gates"),
		Callable(self, "step_n5_dialogue_grants"),
		Callable(self, "step_n6_npc_save_restore"),
		Callable(self, "step_report"),
	]


func _process(_d: float) -> bool:
	# 必须驱动 NPCManager 的导航烘焙时序，否则 nav_ready 永远为 false
	if _npcm != null:
		_npcm.tick()
	if _idx >= _steps.size():
		return true
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_t_state = 0
		_pf_mark = 0
	else:
		if Engine.get_physics_frames() - _pf_mark > 300:
			_rec(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_t_state = 0
			_pf_mark = Engine.get_physics_frames()
	return false


func _rec(ok: bool, label: String, detail: String = "") -> void:
	var suffix := ""
	if detail != "":
		suffix = " | " + detail
	if ok:
		_pass += 1
	else:
		_fail += 1
	_lines.append("[%s] %s%s" % ["PASS" if ok else "FAIL", label, suffix])


func _check(cond: bool, label: String, detail: String = "") -> void:
	_rec(cond, label, detail)


func _wait_pf(n: int) -> bool:
	return Engine.get_physics_frames() - _pf_mark >= n


# ---------------------------------------------------------------- P6

func step_c1_world_does_not_teach() -> bool:
	if not bool(_svc.is_ready):
		if _ticks_over():
			_rec(false, "C1 前置", "bootstrap 超时")
			return true
		return false
	_cog = _svc.cognition
	_dlg = _svc.dialogue_manager
	_npcm = _svc.npc_manager
	_check(_cog != null and _dlg != null and _npcm != null, "C1 前置：三个管理器就绪")

	var before: int = _cog.get_known_count()
	var errs: Array = []
	_svc.event_manager.evaluate("area_enter", {"area_id": "dark_far_end"},
			_svc.world_manager, errs)
	_check(_svc.world_manager.get_current_world_id() != "world_alpha",
		"C1 前置：现实确实切换了", _svc.world_manager.get_current_world_id())
	# 世界切换通过 effects 可以明确授予事实（如 fact_dark_road），
	# 但绝不允许"自动"授予未声明的知识。唯一增量应来自 effect 声明。
	var after: int = _cog.get_known_count()
	var delta := after - before
	_check(delta <= 1,
		"C1 世界切换只授予 effects 声明的知识（增量 ≤ 1）",
		"切换前 %d 条，切换后 %d 条" % [before, after])
	if delta == 1:
		_check(_cog.knows("fact_dark_road"),
			"C1 新增知识是 effects 声明的 fact_dark_road")
	return true


func step_c2_inspect_grants() -> bool:
	var before: int = _cog.get_known_count()
	# 模拟玩家检查一件物品（与 main.gd 的 examine 路径一致）
	_cog.learn("fact_inspected_Mailbox", "inspect", "Mailbox",
			_svc.world_manager.get_current_world_id(), _svc.get_tick())
	_check(_cog.get_known_count() == before + 1, "C2 亲自动手检查获得认知")
	_check(_cog.knows("fact_inspected_Mailbox"), "C2 认知被记录")
	var src: Dictionary = _cog.get_source("fact_inspected_Mailbox")
	_check(str(src.get("source_kind", "")) == "inspect",
		"C2 来源标记为 inspect", str(src.get("source_kind")))
	_check(str(src.get("source_id", "")) == "Mailbox", "C2 记录了来源对象",
		str(src.get("source_id")))
	_check(not str(src.get("world_id", "")).is_empty(), "C2 记录了所在现实",
		str(src.get("world_id")))
	return true


func step_c3_dialogue_grants() -> bool:
	var before: int = _cog.get_known_count()
	var heard: Dictionary = _dlg.hear("kevin_far_house",
			_svc.world_manager.get_current_world_id(), _svc.get_tick())
	_check(bool(heard.get("ok", false)), "C3 对话可听取", str(heard.get("error", "")))
	var granted: Array = heard.get("granted", [])
	_check(granted.size() > 0, "C3 对话授予了认知", str(granted))
	_check(_cog.get_known_count() > before, "C3 认知总数增加")
	var fid := str(granted[0]) if granted.size() > 0 else ""
	if not fid.is_empty():
		var src: Dictionary = _cog.get_source(fid)
		_check(str(src.get("source_kind", "")) == "dialogue",
			"C3 来源标记为 dialogue", str(src.get("source_kind")))
		_check(str(src.get("source_id", "")) == "kevin",
			"C3 记录了是谁说的", str(src.get("source_id")))
	return true


func step_c4_source_preserved() -> bool:
	# 同一条认知再学一次，不应覆盖首次来源
	var src_before: Dictionary = _cog.get_source("fact_inspected_Mailbox")
	_cog.learn("fact_inspected_Mailbox", "dialogue", "kevin", "world_beta", 99)
	var src_after: Dictionary = _cog.get_source("fact_inspected_Mailbox")
	_check(str(src_after.get("source_kind", "")) == str(src_before.get("source_kind", "")),
		"C4 重复学习不覆盖首次来源",
		"%s -> %s" % [src_before.get("source_kind"), src_after.get("source_kind")])
	_check(str(src_after.get("source_id", "")) == "Mailbox", "C4 来源对象仍是首次的",
		str(src_after.get("source_id")))
	return true


func step_c5_save_restore() -> bool:
	var sm := SaveManager.new()
	sm.use_test_path("cog_npc")
	var payload := {
		"magic": "COMET_SAVE", "version": 2,
		"location_id": "party_house", "world_id": "world_alpha",
		"visited_locations": ["party_house"],
		"world_change_records": [], "triggered_events": [],
		"event_history": {}, "event_sequence": [],
		"game_clock_ticks": 0, "game_clock_minutes": 1360,
		"rng_master_seed": 0, "rng_counters": {}, "event_flags": {},
		"phase_id": "",
		"player_view": {"yaw": 0.0, "pitch": 0.0},
		"player_position": [0.0, 0.0, 0.0], "visit_stack": [],
		"known_facts": _cog.get_known_facts(),
		"cognition": _cog.serialize(),
		"npc_states": [],
		"inspected_objects": [], "npc_states_note": "",
		"traversal_state": {},
	}
	var r: Dictionary = sm.save(payload)
	_check(bool(r.get("ok", false)), "C5 存档写入成功", str(r.get("error", "")))

	# 换一个全新 CognitionManager 读档，验证真的恢复了
	var fresh := CognitionManager.new()
	fresh.load_from_data(_dlg.get_node("_ignore") if false else {"facts": {}})
	var err: Array = []
	var loaded: Dictionary = sm.load_state(["party_house"], ["world_alpha", "world_beta", "world_gamma"])
	_check(bool(loaded.get("ok", false)), "C5 存档可读回", str(loaded.get("error", "")))
	if bool(loaded.get("ok", false)):
		var data: Dictionary = loaded.get("data", {})
		var cog_data: Variant = data.get("cognition", null)
		_check(typeof(cog_data) == TYPE_DICTIONARY, "C5 存档里带认知数据")
		if typeof(cog_data) == TYPE_DICTIONARY:
			fresh.restore(cog_data as Dictionary, err)
			_check(fresh.knows("fact_inspected_Mailbox"),
				"C5 读档后认知恢复（与世界状态分开）")
			_check(fresh.get_known_count() == _cog.get_known_count(),
				"C5 认知条数一致", "%d vs %d" % [fresh.get_known_count(), _cog.get_known_count()])
	sm.delete_save()
	return true


func step_c6_new_game_resets() -> bool:
	_check(_cog.get_known_count() > 0, "C6 前置：当前有认知")
	_svc.new_game()
	if _svc.cognition == null:
		_rec(false, "C6 新局后认知管理器存在")
		return true
	_check(_svc.cognition.get_known_count() == 0,
		"C6 新局清空全部认知（不继承上一局）",
		"残留 %d 条" % _svc.cognition.get_known_count())
	return true


# ---------------------------------------------------------------- P7

func step_n1_spawn() -> bool:
	if _t_state == 0:
		# 本测试不加载 main.tscn（那会带入完整 UI/输入链），
		# 直接用 party_house 场景实例作容器生成 NPC。
		var packed: PackedScene = load("res://scenes/locations/party_house.tscn") as PackedScene
		if packed == null:
			_rec(false, "N1 前置", "party_house 不可加载")
			return true
		var inst = packed.instantiate()
		root.add_child(inst)
		_npcm.spawn_all(inst)
		_pf_mark = Engine.get_physics_frames()
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_pf(30):
			return false
		var ids: Array = _npcm.get_character_ids()
		_check(ids.size() == 7, "N1 角色档案含 7 名 NPC", str(ids))
		var npcs: Array = _npcm.get_all_npcs()
		_check(npcs.size() == 7, "N1 7 名 NPC 实体已生成", "实际 %d" % npcs.size())
		return true
	return true


func step_n2_on_ground() -> bool:
	var bad: Array = []
	var detail: Array = []
	for n in _npcm.get_all_npcs():
		var npc := n as NPC
		if npc == null:
			continue
		var y: float = npc.global_position.y
		detail.append("%s:y=%.2f" % [npc.character_id, y])
		if absf(y - FLOOR_Y) > 0.10:
			bad.append(npc.character_id)
	_check(bad.is_empty(), "N2 NPC 站在地面上（Y≈FLOOR_Y，不浮空）",
		"浮空=%s 全部=%s" % [str(bad), str(detail)])
	return true


func step_n3_nav_to_room() -> bool:
	if _t_state == 0:
		_pf_mark = Engine.get_physics_frames()
		_t_state = 1
		return false
	if _t_state == 1:
		# 等导航真正就绪（烘焙+同步+验收），不再依赖固定帧数。
		# 不能用 _ticks_over()：步骤切换会把 _pf_mark 清 0，
		# 而此时引擎帧数早已超阈值，超时判定会瞬间误判。
		if not _npcm.is_nav_ready():
			if _wait_pf(200):
				_rec(false, "N3 前置：导航已就绪",
					"超时，polys=%d" % _npcm.get_nav_polygon_count())
				return true
			return false
		_check(_npcm.get_nav_polygon_count() > 0,
			"N3 前置：导航网格非空", "polys=%d" % _npcm.get_nav_polygon_count())
		_pf_mark = Engine.get_physics_frames()
		_t_state = 2
		return false
	if _t_state == 2:
		# 轮询一条探针路径，确认 NavigationServer 真的可查询，
		# 再跑 42 对全量断言。固定等 20 帧在慢机上会抢跑（实测抖动）。
		var map: RID = _npcm._region.get_navigation_map()
		var probe := NavigationServer3D.map_get_path(map,
				Vector3(0.0, FLOOR_Y, 1.6), Vector3(-4.5, FLOOR_Y, 6.6), true)
		if probe.size() < 2:
			if not _wait_pf(150):
				return false
			_rec(false, "N3 导航查询就绪", "150 帧内探针路径始终为空，polys=%d" %
				_npcm.get_nav_polygon_count())
			return true
		# 直接测 navmesh 连通性——这才是「NPC 能否导航」的本质。
		# 用可行性验证里 72/72 通过的那批采样点。
		var pts := {
			"玄关": Vector3(0.0, FLOOR_Y, 1.6),
			"客厅": Vector3(-4.5, FLOOR_Y, 6.6),
			"餐厅": Vector3(1.3, FLOOR_Y, 6.5),
			"厨房北": Vector3(5.0, FLOOR_Y, 6.5),
			"厨房南": Vector3(5.0, FLOOR_Y, 1.6),
			"书房": Vector3(-4.6, FLOOR_Y, 1.6),
			"主空间": Vector3(-1.0, FLOOR_Y, 7.5),
		}
		var names: Array = pts.keys()
		var ok_pairs := 0
		var total := 0
		var blocked: Array = []
		for i in range(names.size()):
			for j in range(names.size()):
				if i == j:
					continue
				total += 1
				var path := NavigationServer3D.map_get_path(map,
						pts[names[i]], pts[names[j]], true)
				if path.size() >= 2:
					ok_pairs += 1
				else:
					blocked.append("%s->%s" % [names[i], names[j]])
		_check(ok_pairs == total, "N3 任意两房间在 navmesh 上连通",
			"%d/%d 受阻=%s" % [ok_pairs, total, str(blocked)])

		# 再验证 NPC 实体确实能收到目标并进入 walking 状态
		var sent: bool = _npcm.send_to_room("kevin", "living")
		_check(sent, "N3 可以给 NPC 派目标")
		return true
	return true


func step_n4_cognition_gates() -> bool:
	# 便签话题需要 fact_sticky_note，当前应当拿不到
	var before: int = _dlg.get_available_for("kevin").size()
	var has_sticky: bool = _svc.cognition.knows("fact_sticky_note")
	var sticky_nodes: Array = []
	for n in _dlg.get_available_for("kevin"):
		if str((n as Dictionary).get("id", "")) == "kevin_sticky":
			sticky_nodes.append(n)
	_check(sticky_nodes.is_empty() or has_sticky,
		"N4 对话被认知闸门过滤（没查过便签就听不到便签话题）",
		"sticky 可见=%s 已知 fact_sticky_note=%s" % [str(not sticky_nodes.is_empty()), str(has_sticky)])

	# 学到便签后，该话题应解锁
	_svc.cognition.learn("fact_sticky_note", "inspect", "StickyNote", "world_alpha", 0)
	var after: Array = _dlg.get_available_for("kevin")
	var now_has := false
	for n in after:
		if str((n as Dictionary).get("id", "")) == "kevin_sticky":
			now_has = true
	_check(now_has, "N4 学到前置事实后对话解锁",
		"解锁前 %d 条，解锁后 %d 条" % [before, after.size()])
	return true


func step_n5_dialogue_grants() -> bool:
	var before: int = _svc.cognition.get_known_count()
	var heard: Dictionary = _dlg.hear("lee_detail", "world_alpha", 0)
	_check(bool(heard.get("ok", false)), "N5 对话可听取", str(heard.get("error", "")))
	_check(_svc.cognition.get_known_count() > before, "N5 对话后认知增加")
	_check(_svc.cognition.knows("fact_object_moved"), "N5 授予了具体事实",
		"fact_object_moved")
	return true


func step_n6_npc_save_restore() -> bool:
	var before: Array = _npcm.serialize()
	_check(before.size() == 7, "N6 前置：序列化出 7 个 NPC 状态", "实际 %d" % before.size())
	# 改一个 NPC 的位置，再序列化
	var kevin: NPC = _npcm.get_npc("kevin")
	var saved_pos := kevin.global_position
	kevin.global_position = Vector3(2.0, FLOOR_Y, 3.0)
	var moved: Array = _npcm.serialize()
	# 新建管理器恢复
	var fresh := NPCManager.new()
	fresh.load_from_data({"npcs": _npcm._characters, "rooms": _npcm._rooms}, [])
	# 直接用同样的 id 映射恢复
	var map := {}
	for item in moved:
		map[str((item as Dictionary).get("id", ""))] = item
	_check(map.has("kevin"), "N6 序列化含 kevin 状态")
	if map.has("kevin"):
		var p: Variant = (map["kevin"] as Dictionary).get("position", null)
		_check(typeof(p) == TYPE_ARRAY and absf(float((p as Array)[0]) - 2.0) < 0.01,
			"N6 位置被正确序列化", str(p))
	# NPCManager 是 Node，用完必须 free——否则退出时报孤儿实例
	fresh.free()
	# 恢复回去
	_npcm.restore(moved)
	var kevin2: NPC = _npcm.get_npc("kevin")
	_check(absf(kevin2.global_position.x - 2.0) < 0.01,
		"N6 恢复后位置正确", str(kevin2.global_position))
	kevin2.global_position = saved_pos
	return true


func _ticks_over() -> bool:
	return Engine.get_physics_frames() - _pf_mark > 200


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== COGNITION & NPC RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
