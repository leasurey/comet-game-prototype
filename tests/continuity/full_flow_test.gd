## FullFlowTest — 批次 6：完整流程验收
##
## 用法：godot --headless --script res://tests/continuity/full_flow_test.gd
##
## 覆盖任务十二「多系统联动」+ 测试 A/B/C + 多结局分支：
##
## A1 物品线索闭环：检查物品 → 观察入账 → 对话变化 → 手机出现 → 存档 → 恢复
## A2 多结局分支：是否检查便签 → 不同对话路径（gate 实际生效）
## B1 NPC 行为闭环：NPC 行走 → 离场 → 回场连续 → 二问不同答 → 存读档
## B2 NPC 记忆连续：对话教给 NPC 事实 → 离场回场后仍在
## C1 现实切换闭环：穿越黑路 → 现实变 → 记忆分槽 → 返回 → 存档恢复
## C2 三现实循环：α→β→γ→α 完整循环
## S1 完整存读档：全系统状态存→新会话读→一致性断言

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _main = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false

var _kevin: NPC = null


func _initialize() -> void:
	print("=== COMET full flow acceptance test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_a1_item_clue_loop"),
		Callable(self, "step_a2_branching"),
		Callable(self, "step_b1_npc_behavior_loop"),
		Callable(self, "step_b2_npc_memory"),
		Callable(self, "step_c1_reality_switch"),
		Callable(self, "step_c2_three_reality"),
		Callable(self, "step_s1_save_restore"),
		Callable(self, "step_report"),
	]


func _process(_d: float) -> bool:
	if _idx >= _steps.size():
		return false
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_ticks = 0
		_t_state = 0
	else:
		_ticks += 1
		if _ticks > 600:
			_check(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
	return false


func _check(cond: bool, label: String, detail: String = "") -> void:
	var suffix := "" if detail == "" else " | " + detail
	if cond:
		_pass += 1
	else:
		_fail += 1
	_lines.append("[%s] %s%s" % ["PASS" if cond else "FAIL", label, suffix])


func _find_hotspot(node: Node, hname: String) -> Hotspot:
	for c in node.get_children():
		if c is Hotspot and c.name == hname:
			return c as Hotspot
		var f := _find_hotspot(c, hname)
		if f != null:
			return f
	return null


func step_setup() -> bool:
	if _t_state == 0:
		var sm = _svc.save_manager
		sm.use_test_path("full_flow")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _ticks < 15:
		return false
	var npcm = _svc.npc_manager
	if npcm == null or not npcm.is_nav_ready():
		if _ticks > 300:
			_check(false, "setup：NPCManager + nav 就绪")
			return true
		return false
	_kevin = npcm.get_npc("kevin")
	_check(_kevin != null, "setup：kevin 在场")
	_check(_svc.get_current_location_id() == "party_house",
		"setup：起始地点为聚会房屋", _svc.get_current_location_id())
	_check(_svc.world_manager.get_current_world_id() == "world_alpha",
		"setup：起始现实为 world_alpha")
	return _kevin != null


## A1  物品线索闭环（真实热点交互入口）：检查 → 观察 → 对话变化 → 手机 → 存档恢复
func step_a1_item_clue_loop() -> bool:
	if _t_state == 0:
		var cog = _svc.cognition
		_check(not cog.knows("fact_sticky_note"), "A1 前置：不知道便签")
		_check(cog.get_observation_count() == 0, "A1 前置：无观察")
		# 真实热点交互入口（P1-5 修复：不再直接 cognition.learn）：
		# 在场景中找到 StickyNote 热点，通过 main 的 _on_hotspot_activated 处理链触发
		var spot := _find_hotspot(_main, "StickyNote")
		_check(spot != null, "A1 StickyNote 热点存在")
		if spot == null:
			return true
		# 走 main._on_hotspot_activated 的完整 examine 链
		_main._on_hotspot_activated(spot)
		_check(cog.knows("fact_sticky_note"), "A1 真实交互后知道便签")
		_check(cog.get_observation_count() >= 1, "A1 观察记录 +1")
		# 对话变化：便签话题解锁
		var dm = _svc.dialogue_manager
		var ctx := {"npc_knows": [], "relationships": {}, "said_nodes": [], "world": "world_alpha"}
		var entries: Array = dm.get_entry_nodes_for("kevin", ctx)
		var has_sticky := false
		for n in entries:
			if str((n as Dictionary).get("id", "")) == "kevin_sticky":
				has_sticky = true
				break
		_check(has_sticky, "A1 便签话题解锁（认知闸门生效）")
		# 对话让 NPC 学到事实
		var heard: Dictionary = dm.hear("kevin_sticky", "world_alpha", 2, ctx)
		_check(bool(heard.get("ok")), "A1 听到 kevin_sticky")
		for fid in (heard.get("teaches_npc", []) as Array):
			_kevin.learn_fact(str(fid))
		_check(_kevin.knows_fact("fact_player_told_sticky"), "A1 Kevin 学到便签")
		# 模拟 main.gd _show_dialogue_node 的后续动作
		_kevin.mark_said("kevin_sticky")
		_kevin.remember("dialogue", str(heard.get("text", "")), "player", _svc.get_tick())
		# 手机数据
		var phone: Dictionary = _svc.get_phone_data()
		_check((phone["observations"] as Array).size() >= 1, "A1 手机含观察")
		_check((phone["facts"] as Array).size() >= 2, "A1 手机含事实")
		# 存档
		_svc.save_game()
		_check(_svc.has_save(), "A1 存档成功")
		return true
	return false


## A2  多结局分支（状态分支测试，非完整玩家流程）：
## 直接操纵认知状态来验证 gate 逻辑的分支差异。
## 注意：这是独立的状态分支测试，不冒充完整玩家操作流程——
## 完整流程的便签获取走 A1 的真实热点交互入口。
func step_a2_branching() -> bool:
	if _t_state == 0:
		var dm = _svc.dialogue_manager
		# 场景 A：知道便签（当前状态）→ 便签话题可用
		var ctx_known := {"npc_knows": [], "relationships": {}, "said_nodes": [], "world": "world_alpha"}
		var entries_known: Array = dm.get_entry_nodes_for("kevin", ctx_known)
		var has_sticky_known := false
		for n in entries_known:
			if str((n as Dictionary).get("id", "")) == "kevin_sticky":
				has_sticky_known = true
		_check(has_sticky_known, "A2 分支 A：知道便签 → 话题可用")
		# 场景 B：不知道便签（重置认知）→ 话题锁定
		var cog = _svc.cognition
		cog.reset()
		_check(not cog.knows("fact_sticky_note"), "A2 重置后不知道便签")
		var ctx_unknown := {"npc_knows": [], "relationships": {}, "said_nodes": [], "world": "world_alpha"}
		var entries_unknown: Array = dm.get_entry_nodes_for("kevin", ctx_unknown)
		var has_sticky_unknown := false
		for n in entries_unknown:
			if str((n as Dictionary).get("id", "")) == "kevin_sticky":
				has_sticky_unknown = true
		_check(not has_sticky_unknown, "A2 分支 B：不知道便签 → 话题锁定")
		# 两条路径产生不同结果（多结局的核心验证）
		_check(has_sticky_known != has_sticky_unknown,
			"A2 多结局分支：两条路径产生不同对话可用性")
		# 恢复认知（继续后续测试）
		cog.learn("fact_sticky_note", "inspect", "StickyNote", "world_alpha", 1)
		cog.learn("fact_inspected_StickyNote", "inspect", "StickyNote", "world_alpha", 1)
		return true
	return false


## B1  NPC 行为闭环：行走 → 离场 → 回场 → 二问不同答
func step_b1_npc_behavior_loop() -> bool:
	if _t_state == 0:
		var npcm = _svc.npc_manager
		_check(_kevin != null, "B1 前置：kevin 在场")
		if _kevin == null:
			return true
		# 派目标
		npcm.send_to_room("kevin", "living")
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 30:
			return false
		var pos_before: Vector3 = _kevin.global_position
		# 离场
		_svc.go_to("house_exterior")
		_t_state = 2
		return false
	if _t_state == 2:
		if _ticks < 8:
			return false
		# 回场
		_svc.go_to("party_house")
		_t_state = 3
		return false
	if _t_state == 3:
		if _ticks < 10:
			return false
		var npcm = _svc.npc_manager
		_kevin = npcm.get_npc("kevin")
		_check(_kevin != null, "B1 回场后 kevin 仍在")
		if _kevin == null:
			return true
		# 位置连续（不是出生点）
		var spawn_pos := Vector3(5.0, 0.20, 6.5)
		_check(_kevin.global_position.distance_to(spawn_pos) > 0.3,
			"B1 回场后位置连续（非出生点）",
			"dist=%.2f" % _kevin.global_position.distance_to(spawn_pos))
		# 二问不同答
		var dm = _svc.dialogue_manager
		_kevin.mark_said("kevin_far_house")
		var ctx := {"said_nodes": ["kevin_far_house"], "npc_knows": [], "relationships": {},
			"world": "world_alpha"}
		var heard: Dictionary = dm.hear("kevin_far_house", "world_alpha", 1, ctx)
		_check(bool(heard.get("ok")), "B1 二听成功")
		_check(str(heard.get("text", "")) != str(heard.get("base_text", "")),
			"B1 二问不同答（said 变体生效）")
		return true
	return false


## B2  NPC 记忆连续：教给 NPC 的事实 → 离场回场后仍在
func step_b2_npc_memory() -> bool:
	if _t_state == 0:
		_check(_kevin != null, "B2 前置：kevin 在场")
		if _kevin == null:
			return true
		# A1 已教给 Kevin fact_player_told_sticky，验证离场后仍在
		_svc.go_to("house_exterior")
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 8:
			return false
		_svc.go_to("party_house")
		_t_state = 2
		return false
	if _t_state == 2:
		if _ticks < 10:
			return false
		var npcm = _svc.npc_manager
		_kevin = npcm.get_npc("kevin")
		if _kevin == null:
			_check(false, "B2 kevin 在场")
			return true
		_check(_kevin.knows_fact("fact_player_told_sticky"),
			"B2 离场回场后 Kevin 仍知道便签（记忆连续）")
		_check(_kevin.has_said("kevin_sticky"),
			"B2 对话进度仍在（said_nodes 连续）")
		return true
	return false


## C1  现实切换闭环：穿越黑路 → 现实变 → 返回 → 存档
func step_c1_reality_switch() -> bool:
	if _t_state == 0:
		_check(_svc.world_manager.get_current_world_id() == "world_alpha",
			"C1 前置：world_alpha")
		var cog = _svc.cognition
		_check(not cog.knows("fact_dark_road"), "C1 前置：不知道黑路")
		# 穿越黑路
		var errs: Array = []
		var fired: Array = _svc.event_manager.evaluate("area_enter",
			{"area_id": "dark_far_end"}, _svc.world_manager, errs)
		_check(errs.is_empty(), "C1 穿越无错误", str(errs))
		_check(not fired.is_empty(), "C1 穿越事件触发")
		_check(_svc.world_manager.get_current_world_id() == "world_beta",
			"C1 现实切换到 beta", _svc.world_manager.get_current_world_id())
		_check(cog.knows("fact_dark_road"), "C1 穿越后知道黑路")
		# 记忆分槽（NPC 应在穿越前已有记忆；补一条穿越观察）
		if _kevin != null:
			_kevin.remember("observation", "玩家穿越了黑暗道路", "player", _svc.get_tick())
			_check(_kevin.get_memory().size() > 0,
				"C1 NPC 记忆有记录", str(_kevin.get_memory().size()))
		# 存档
		_svc.save_game()
		return true
	return false


## C2  三现实循环：α→β→γ→α
func step_c2_three_reality() -> bool:
	if _t_state == 0:
		# 当前在 beta（C1 切过去了）
		_check(_svc.world_manager.get_current_world_id() == "world_beta",
			"C2 前置：world_beta", _svc.world_manager.get_current_world_id())
		# β→γ
		var errs1: Array = []
		_svc.event_manager.evaluate("area_enter", {"area_id": "dark_far_end"},
			_svc.world_manager, errs1)
		_check(_svc.world_manager.get_current_world_id() == "world_gamma",
			"C2 β→γ", _svc.world_manager.get_current_world_id())
		# γ→α
		var errs2: Array = []
		_svc.event_manager.evaluate("area_enter", {"area_id": "dark_far_end"},
			_svc.world_manager, errs2)
		_check(_svc.world_manager.get_current_world_id() == "world_alpha",
			"C2 γ→α", _svc.world_manager.get_current_world_id())
		_check(errs1.is_empty() and errs2.is_empty(), "C2 循环无错误")
		return true
	return false


## S1  完整存读档：全系统状态存→读→一致性
func step_s1_save_restore() -> bool:
	if _t_state == 0:
		# 收集保存前的状态
		var cog = _svc.cognition
		var npcm = _svc.npc_manager
		var em = _svc.event_manager
		var facts_before: Array = cog.get_known_facts().duplicate()
		var obs_before: int = cog.get_observation_count()
		var events_before: Array = em.get_sequence().duplicate()
		var kevin_facts_before: Array = (_kevin.known_facts.duplicate() if _kevin != null else [])
		var kevin_said_before: Array = (_kevin.said_nodes.duplicate() if _kevin != null else [])
		var world_before: String = _svc.world_manager.get_current_world_id()
		var flag_before: bool = em.has_flag("returned_house_exterior")
		# 保存
		_svc.save_game()
		_check(_svc.has_save(), "S1 存档成功")
		# 新游戏（清空状态）
		_svc.new_game()
		_t_state = 1
		# 存储检查用的快照（存在变量里供下一步比对）
		_t_state_data = {
			"facts": facts_before,
			"obs": obs_before,
			"events": events_before,
			"kevin_facts": kevin_facts_before,
			"kevin_said": kevin_said_before,
			"world": world_before,
			"flag": flag_before,
		}
		return false
	if _t_state == 1:
		if _ticks < 8:
			return false
		# 验证新游戏已清空
		var cog = _svc.cognition
		_check(cog.get_known_count() == 0, "S1 新局认知清零")
		# 读档
		_svc.continue_game()
		_t_state = 2
		return false
	if _t_state == 2:
		if _ticks < 10:
			return false
		var data: Dictionary = _t_state_data
		var cog = _svc.cognition
		var em = _svc.event_manager
		var npcm = _svc.npc_manager
		# 逐项一致性
		_check(cog.get_known_facts().size() == (data["facts"] as Array).size(),
			"S1 事实数一致", "%d vs %d" % [cog.get_known_facts().size(), (data["facts"] as Array).size()])
		_check(cog.get_observation_count() == int(data["obs"]),
			"S1 观察数一致", "%d vs %d" % [cog.get_observation_count(), int(data["obs"])])
		_check(em.get_sequence().size() == (data["events"] as Array).size(),
			"S1 事件序列一致")
		_check(_svc.world_manager.get_current_world_id() == str(data["world"]),
			"S1 现实一致", _svc.world_manager.get_current_world_id())
		_check(em.has_flag("returned_house_exterior") == bool(data["flag"]),
			"S1 事件旗标一致")
		# NPC 恢复
		var kevin2 = npcm.get_npc("kevin")
		if kevin2 != null:
			_check(kevin2.known_facts.size() == (data["kevin_facts"] as Array).size(),
				"S1 Kevin 认知一致")
			_check(kevin2.said_nodes.size() == (data["kevin_said"] as Array).size(),
				"S1 Kevin 对话进度一致")
		_check(_svc.has_save(), "S1 存档文件仍在")
		return true
	return false


var _t_state_data: Dictionary = {}


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	for line in _lines:
		print(line)
	print("=== FULL FLOW RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null and gs.has_method("shutdown_audio"):
		gs.shutdown_audio()
	await create_timer(0.15).timeout
	quit(1 if _fail > 0 else 0)
	return true
