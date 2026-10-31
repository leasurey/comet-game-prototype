## ContinuityNpcCharacterTest — 批次 3：NPC 人物系统
##
## 用法：godot --headless --script res://tests/continuity/npc_character_test.gd
##
## P1 记忆：remember 入档、get_memory 按现实过滤、序列化恢复
## P2 关系：adjust_relationship 裁剪、get_trust、序列化恢复
## P3 自主行为：游荡定时器触发 move_to、说话时挂起
## P4 对话连续性：said_nodes 记录、said/not_said 谓词、teaches_npc
## P5 现实差异：不同 world 的记忆分槽、跨现实通用记忆
## P6 关系闸门：relationship_at_least 谓词

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
	print("=== COMET continuity NPC character test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_p1_memory"),
		Callable(self, "step_p2_relationships"),
		Callable(self, "step_p3_autonomy"),
		Callable(self, "step_p4_dialogue"),
		Callable(self, "step_p5_reality"),
		Callable(self, "step_p6_rel_gate"),
		Callable(self, "step_p7_attrs_rollback"),
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
		if _ticks > 500:
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


func step_setup() -> bool:
	if _t_state == 0:
		var sm = _svc.save_manager
		sm.use_test_path("npc_character")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _ticks < 15:
		return false
	var npcm = _svc.npc_manager
	if npcm == null or not npcm.is_nav_ready():
		if _ticks > 200:
			_check(false, "setup：NPCManager + nav 就绪")
			return true
		return false
	_kevin = npcm.get_npc("kevin")
	_check(_kevin != null, "setup：kevin 在场")
	return _kevin != null


## P1  记忆：记录、读取、序列化
func step_p1_memory() -> bool:
	if _t_state == 0:
		_check(_kevin != null, "P1 前置：kevin 可用")
		if _kevin == null:
			return true
		_check(_kevin.memory.is_empty(), "P1 前置：记忆为空")
		_kevin.set_current_world("world_alpha")
		_kevin.remember("dialogue", "玩家问了我关于便签的事", "player", 1)
		_kevin.remember("event", "有人穿越了黑暗道路", "player", 2)
		_check(_kevin.memory.size() == 2, "P1 记忆记录成功", str(_kevin.memory.size()))
		var all_mem: Array = _kevin.get_memory()
		_check(all_mem.size() == 2, "P1 get_memory 返回全部")
		var alpha_mem: Array = _kevin.get_memory("world_alpha")
		_check(alpha_mem.size() == 2, "P1 get_memory(world_alpha) 过滤正确")
		var beta_mem: Array = _kevin.get_memory("world_beta")
		_check(beta_mem.size() == 0, "P1 get_memory(world_beta) 无该现实记忆")
		# 序列化 → 恢复
		var rec := _kevin.serialize()
		_check(rec.has("memory"), "P1 序列化含 memory")
		_check((rec["memory"] as Array).size() == 2, "P1 序列化记忆数正确")
		_check(rec.has("known_facts"), "P1 序列化含 known_facts")
		_check(rec.has("said_nodes"), "P1 序列化含 said_nodes")
		_check(rec.has("relationships"), "P1 序列化含 relationships")
		return true
	return false


## P2  关系：调整、裁剪、序列化
func step_p2_relationships() -> bool:
	if _t_state == 0:
		_check(_kevin.get_trust("player") == 0.0, "P2 前置：信任 0")
		_kevin.adjust_relationship("player", 0.3, 0.1)
		_check(absf(_kevin.get_trust("player") - 0.3) < 0.01, "P2 信任 +0.3")
		var rel := _kevin.get_relationship("player")
		_check(absf(float(rel.get("familiarity", 0.0)) - 0.1) < 0.01, "P2 熟悉度 +0.1")
		# 裁剪到 [-1, 1]
		_kevin.adjust_relationship("player", 1.0, 0.0)
		_check(_kevin.get_trust("player") <= 1.0, "P2 信任上限裁剪", str(_kevin.get_trust("player")))
		_kevin.adjust_relationship("player", -3.0, 0.0)
		_check(_kevin.get_trust("player") >= -1.0, "P2 信任下限裁剪", str(_kevin.get_trust("player")))
		# NPC-NPC 关系
		_kevin.adjust_relationship("beth", 0.5, 0.3)
		_check(absf(_kevin.get_trust("beth") - 0.5) < 0.01, "P2 NPC 间关系")
		return true
	return false


## P3  自主行为：游荡定时器驱动移动
func step_p3_autonomy() -> bool:
	if _t_state == 0:
		_check(_kevin != null, "P3 前置：kevin 可用")
		if _kevin == null:
			return true
		_check(_kevin.wander_interval > 0.0, "P3 游荡间隔已设置", str(_kevin.wander_interval))
		# 验证 personality 影响游荡频率
		var npcm = _svc.npc_manager
		var info: Dictionary = npcm._characters.get("kevin", {})
		var traits: Array = info.get("traits", [])
		# Kevin 没有 restless → 间隔应为默认 10.0
		_check(_kevin.wander_interval == 10.0, "P3 默认游荡间隔 10s", str(_kevin.wander_interval))
		# 让 NPC 空闲足够长时间，验证自主行为会触发
		# 测试加速：临时缩短游荡间隔到 0.3s（实测 ~18 物理帧）
		_kevin.wander_interval = 0.3
		_t_state = 1
		return false
	if _t_state == 1:
		# 等游荡间隔过去（NPC 可能已经走开）
		if _ticks < 60:
			return false
		# P0-1 修复验证：NPC 实际位置变化（不只是 behavior 标记）
		_check(_kevin.behavior == "wander" or _kevin.state == "walking",
			"P3 自主游荡行为触发",
			"behavior=%s state=%s" % [_kevin.behavior, _kevin.state])
		# 验证 wander_callback 已注入（P0-1：不再依赖 get_parent）
		_check(_kevin.wander_callback.is_valid(),
			"P3 wander_callback 已注入")
		# 验证 NPC 实际发生了位移（或在行走中）
		var moved: bool = _kevin.state == "walking" or _kevin.has_goal()
		_check(moved, "P3 NPC 实际位移/行走中（非仅 behavior 标记）",
			"state=%s has_goal=%s" % [_kevin.state, str(_kevin.has_goal())])
		# 说话时自主行为挂起
		_kevin.start_talking(Vector3(1, 0, 1))
		_check(_kevin.state == "talking", "P3 说话状态")
		_check(_kevin.behavior != "wander" or _kevin.state != "walking",
			"P3 说话时游荡挂起")
		_kevin.stop_talking()
		return true
	return false


## P4  对话连续性：said_nodes、said/not_said 谓词、teaches_npc
func step_p4_dialogue() -> bool:
	if _t_state == 0:
		var dm = _svc.dialogue_manager
		_check(_kevin.has_said("kevin_sticky") == false, "P4 前置：未说过 kevin_sticky")
		_kevin.mark_said("kevin_sticky")
		_check(_kevin.has_said("kevin_sticky"), "P4 mark_said 生效")
		# said/not_said 谓词测试
		var ok1: bool = dm._requirements_met({"not_said": ["kevin_sticky"]},
				{"said_nodes": ["kevin_sticky"]})
		_check(not ok1, "P4 not_said 谓词：已说过 → 不满足")
		var ok2: bool = dm._requirements_met({"said": ["kevin_sticky"]},
				{"said_nodes": ["kevin_sticky"]})
		_check(ok2, "P4 said 谓词：已说过 → 满足")
		var ok3: bool = dm._requirements_met({"not_said": ["never_said"]},
				{"said_nodes": ["kevin_sticky"]})
		_check(ok3, "P4 not_said 谓词：未说过 → 满足")
		# teaches_npc：NPC 学到新事实
		_check(not _kevin.knows_fact("fact_player_told_sticky"), "P4 前置：NPC 不知道")
		_kevin.learn_fact("fact_player_told_sticky")
		_check(_kevin.knows_fact("fact_player_told_sticky"), "P4 teaches_npc 授予事实")
		var rec := _kevin.serialize()
		_check((rec.get("known_facts", []) as Array).has("fact_player_told_sticky"),
			"P4 known_facts 入档")
		_check((rec.get("said_nodes", []) as Array).has("kevin_sticky"),
			"P4 said_nodes 入档")
		return true
	return false


## P5  现实差异：记忆分槽
func step_p5_reality() -> bool:
	if _t_state == 0:
		# 在 world_alpha 记忆基础上，在 world_beta 记一条
		_kevin.set_current_world("world_beta")
		_kevin.remember("observation", "这里的灯颜色不对", "", 3)
		_check(_kevin.memory.size() == 3, "P5 新记忆已记录", str(_kevin.memory.size()))
		var alpha_mem: Array = _kevin.get_memory("world_alpha")
		var beta_mem: Array = _kevin.get_memory("world_beta")
		_check(alpha_mem.size() == 2, "P5 world_alpha 记忆数", str(alpha_mem.size()))
		_check(beta_mem.size() == 1, "P5 world_beta 记忆数", str(beta_mem.size()))
		# 跨现实通用记忆（world 为空）
		_kevin.set_current_world("")
		_kevin.remember("player_action", "玩家反复进出屋子", "player", 4)
		var all_mem: Array = _kevin.get_memory()
		_check(all_mem.size() == 4, "P5 含通用记忆共 4 条", str(all_mem.size()))
		var alpha2: Array = _kevin.get_memory("world_alpha")
		_check(alpha2.size() == 3, "P5 通用记忆在任何现实可见", str(alpha2.size()))
		return true
	return false


## P6  关系闸门：relationship_at_least 谓词
func step_p6_rel_gate() -> bool:
	if _t_state == 0:
		var dm = _svc.dialogue_manager
		# trust 0.3（P2 设过，但 P2 的 -3.0 裁剪后是 -1.0）
		# 重设到 0.5
		_kevin.adjust_relationship("player", 1.5, 0.0)  # -1.0 + 1.5 = 0.5
		_check(absf(_kevin.get_trust("player") - 0.5) < 0.01, "P6 前置：trust = 0.5",
			str(_kevin.get_trust("player")))
		var ctx := {
			"relationships": {"player": {"trust": _kevin.get_trust("player"), "familiarity": 0.1}},
		}
		# trust >= 0.3 → 满足
		var ok1: bool = dm._requirements_met({"relationship_at_least": {"target": "player", "trust": 0.3}}, ctx)
		_check(ok1, "P6 relationship_at_least 0.3 满足")
		# trust >= 0.8 → 不满足
		var ok2: bool = dm._requirements_met({"relationship_at_least": {"target": "player", "trust": 0.8}}, ctx)
		_check(not ok2, "P6 relationship_at_least 0.8 不满足")
		# 无关系数据 → 不满足
		var ok3: bool = dm._requirements_met({"relationship_at_least": {"target": "player", "trust": 0.0}},
				{"relationships": {}})
		_check(not ok3, "P6 无关系数据 → 不满足")
		# 序列化恢复
		var rec := _kevin.serialize()
		_check(rec.has("relationships"), "P6 relationships 入档")
		var rel_dict: Dictionary = rec.get("relationships", {})
		_check(rel_dict.has("player"), "P6 player 关系入档")
		return true
	return false


## P7  NPC 属性事务回滚（P0-3 修复验证）：全替换式恢复，字典必须完全一致
func step_p7_attrs_rollback() -> bool:
	if _t_state == 0:
		var npcm = _svc.npc_manager
		# 设定初始属性
		npcm.replace_npc_attrs("kevin", {"mood": "calm", "room": "kitchen", "note": "initial"})
		var before: Dictionary = npcm.get_npc_attrs("kevin")
		_check(before.size() == 3, "P7 前置：3 个属性", str(before))
		# 模拟事件效果的事务：新增 key + 修改 key，然后回滚
		# 这正是 EventManager._apply_stateful_effect 的 npc_state 分支行为
		var old_attrs: Dictionary = npcm.get_npc_attrs("kevin").duplicate(true)
		# set_npc_attrs 合并写入（新增 new_key，修改 mood）
		npcm.set_npc_attrs("kevin", {"mood": "uneasy", "new_key": "added"})
		var mid: Dictionary = npcm.get_npc_attrs("kevin")
		_check(mid.size() == 4, "P7 事务中：4 个属性（1 新增 + 1 修改）", str(mid))
		_check(str(mid.get("mood", "")) == "uneasy", "P7 事务中：mood 已修改")
		# 回滚：全替换（P0-3 修复的关键）
		npcm.replace_npc_attrs("kevin", old_attrs)
		var after: Dictionary = npcm.get_npc_attrs("kevin")
		# 断言字典完全一致（不是子集，不是合并）
		_check(after.size() == before.size(),
			"P7 回滚后属性数完全一致", "%d vs %d" % [after.size(), before.size()])
		var exact_match := true
		for k in before.keys():
			if not after.has(str(k)) or str(after[str(k)]) != str(before[str(k)]):
				exact_match = false
		for k in after.keys():
			if not before.has(str(k)):
				exact_match = false
		_check(exact_match, "P7 回滚后字典与执行前完全一致",
			"before=%s after=%s" % [str(before), str(after)])
		_check(not after.has("new_key"), "P7 回滚后新增键已删除")
		return true
	return false


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	for line in _lines:
		print(line)
	print("=== NPC CHARACTER RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null and gs.has_method("shutdown_audio"):
		gs.shutdown_audio()
	await create_timer(0.15).timeout
	quit(1 if _fail > 0 else 0)
	return true
