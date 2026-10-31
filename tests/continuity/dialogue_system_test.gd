## ContinuityDialogueSystemTest — 批次 4：对话系统完善
##
## 用法：godot --headless --script res://tests/continuity/dialogue_system_test.gd
##
## D1 文本变体：world 差异、said 二次回复、npc_knows 响应、relationship 响应
## D2 对话进度：首听默认文本 → 二听 said 变体 → 进度入档
## D3 teaches_npc：对话让 NPC 学到事实并影响后续回复
## D4 现实差异：同一话题在不同现实下文本不同

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

var _dm = null
var _kevin: NPC = null


func _initialize() -> void:
	print("=== COMET continuity dialogue system test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_d1_variants"),
		Callable(self, "step_d2_progress"),
		Callable(self, "step_d3_teaches"),
		Callable(self, "step_d4_reality"),
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
		sm.use_test_path("dialogue_sys")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _ticks < 15:
		return false
	_dm = _svc.dialogue_manager
	var npcm = _svc.npc_manager
	if npcm == null or not npcm.is_nav_ready():
		if _ticks > 200:
			_check(false, "setup：NPCManager + nav 就绪")
			return true
		return false
	_kevin = npcm.get_npc("kevin")
	_check(_dm != null and _kevin != null, "setup：DialogueManager + kevin 就绪")
	return _dm != null and _kevin != null


## D1  文本变体解析
func step_d1_variants() -> bool:
	if _t_state == 0:
		var node: Dictionary = _dm.get_node("kevin_greet")
		_check(not node.is_empty(), "D1 kevin_greet 节点存在")
		_check(node.has("variants"), "D1 kevin_greet 有 variants", str(node.has("variants")))
		# 默认（world_alpha，无条件匹配）→ 用基础文本
		var ctx_alpha := {"world": "world_alpha", "said_nodes": [], "npc_knows": [], "relationships": {}}
		var text_alpha: String = _dm.resolve_text(node, ctx_alpha, "world_alpha")
		_check(text_alpha == str(node.get("text", "")), "D1 默认文本（alpha）",
			text_alpha.substr(0, 30))
		# world_beta variant
		var ctx_beta := {"world": "world_beta", "said_nodes": [], "npc_knows": [], "relationships": {}}
		var text_beta: String = _dm.resolve_text(node, ctx_beta, "world_beta")
		_check(text_beta != str(node.get("text", "")), "D1 world_beta 变体生效",
			text_beta.substr(0, 30))
		_check(text_beta.contains("不太一样") or text_beta.contains("一样"), "D1 beta 变体文本正确", text_beta.substr(0, 30))
		# world_gamma variant
		var ctx_gamma := {"world": "world_gamma", "said_nodes": [], "npc_knows": [], "relationships": {}}
		var text_gamma: String = _dm.resolve_text(node, ctx_gamma, "world_gamma")
		_check(text_gamma.contains("不对"), "D1 gamma 变体文本正确", text_gamma.substr(0, 30))
		# said variant（kevin_far_house）
		var node2: Dictionary = _dm.get_node("kevin_far_house")
		var ctx_said := {"world": "world_alpha", "said_nodes": ["kevin_far_house"], "npc_knows": [], "relationships": {}}
		var text_said: String = _dm.resolve_text(node2, ctx_said, "world_alpha")
		_check(text_said.contains("说过"), "D1 said 变体生效（二问回复）", text_said.substr(0, 30))
		# npc_knows variant（mike_dark）
		var node3: Dictionary = _dm.get_node("mike_dark")
		var ctx_know := {"world": "world_alpha", "said_nodes": [], "npc_knows": ["fact_player_told_sticky"], "relationships": {}}
		var text_know: String = _dm.resolve_text(node3, ctx_know, "world_alpha")
		_check(text_know.contains("便签") or text_know.contains("Kevin"), "D1 npc_knows 变体生效",
			text_know.substr(0, 30))
		# relationship variant（lee_dark）
		var node4: Dictionary = _dm.get_node("lee_dark")
		var ctx_trust := {"world": "world_alpha", "said_nodes": [], "npc_knows": [],
			"relationships": {"player": {"trust": 0.5, "familiarity": 0.1}}}
		var text_trust: String = _dm.resolve_text(node4, ctx_trust, "world_alpha")
		_check(text_trust.contains("说实话"), "D1 relationship 变体生效", text_trust.substr(0, 30))
		# 无关系数据 → 默认文本
		var ctx_notrust := {"world": "world_alpha", "said_nodes": [], "npc_knows": [], "relationships": {}}
		var text_notrust: String = _dm.resolve_text(node4, ctx_notrust, "world_alpha")
		_check(text_notrust == str(node4.get("text", "")), "D1 无关系时用默认文本")
		return true
	return false


## D2  对话进度：首听 → 二听 → 入档
func step_d2_progress() -> bool:
	if _t_state == 0:
		_check(not _kevin.has_said("kevin_far_house"), "D2 前置：未说过 kevin_far_house")
		# 首听
		var ctx := {"said_nodes": [], "npc_knows": [], "relationships": {}}
		var heard1: Dictionary = _dm.hear("kevin_far_house", "world_alpha", 0, ctx)
		_check(bool(heard1.get("ok")), "D2 首听成功")
		_check(str(heard1.get("text", "")) == str(heard1.get("base_text", "")),
			"D2 首听用默认文本")
		# 标记 said（模拟 main.gd 的行为）
		_kevin.mark_said("kevin_far_house")
		# 二听（said_nodes 已更新）
		var ctx2 := {"said_nodes": ["kevin_far_house"], "npc_knows": [], "relationships": {}}
		var heard2: Dictionary = _dm.hear("kevin_far_house", "world_alpha", 1, ctx2)
		_check(bool(heard2.get("ok")), "D2 二听成功")
		_check(str(heard2.get("text", "")) != str(heard2.get("base_text", "")),
			"D2 二听用 said 变体")
		_check(str(heard2.get("text", "")).contains("说过"), "D2 二听文本正确",
			str(heard2.get("text", "")).substr(0, 30))
		# 入档
		var rec := _kevin.serialize()
		_check((rec.get("said_nodes", []) as Array).has("kevin_far_house"),
			"D2 said_nodes 入档")
		return true
	return false


## D3  teaches_npc：NPC 从对话中学到事实并影响后续回复
func step_d3_teaches() -> bool:
	if _t_state == 0:
		_check(not _kevin.knows_fact("fact_player_told_sticky"), "D3 前置：Kevin 不知道")
		# kevin_sticky requires fact_sticky_note → 玩家必须先知道
		_svc.cognition.learn("fact_sticky_note", "inspect", "StickyNote", "world_alpha", 0)
		var ctx := {"said_nodes": [], "npc_knows": [], "relationships": {}}
		var heard: Dictionary = _dm.hear("kevin_sticky", "world_alpha", 0, ctx)
		_check(bool(heard.get("ok")), "D3 听到 kevin_sticky")
		var teaches: Array = heard.get("teaches_npc", [])
		_check(teaches.has("fact_player_told_sticky"), "D3 teaches_npc 返回事实", str(teaches))
		# 模拟 main.gd：写入 NPC
		for fid in teaches:
			_kevin.learn_fact(str(fid))
		_check(_kevin.knows_fact("fact_player_told_sticky"), "D3 Kevin 学到事实")
		# NPC 现在知道便签 → mike_dark 的 npc_knows 变体可被触发
		# （mike_dark 的 speaker 是 mike，但 npc_knows 检查的是提供给 _requirements_met 的 npc_context）
		# Kevin 知道后，如果与 Kevin 对话时提供此上下文，mike_dark 的变体会在 resolve 时匹配
		# 这里验证的是 _requirements_met 的 npc_knows 谓词本身
		var ok: bool = _dm._requirements_met(
			{"npc_knows": ["fact_player_told_sticky"]},
			{"npc_knows": ["fact_player_told_sticky"]})
		_check(ok, "D3 npc_knows 谓词：知道 → 满足")
		# teaches_npc 入档
		var rec := _kevin.serialize()
		_check((rec.get("known_facts", []) as Array).has("fact_player_told_sticky"),
			"D3 known_facts 入档")
		return true
	return false


## D4  现实差异：同一话题在不同现实下文本不同
func step_d4_reality() -> bool:
	if _t_state == 0:
		var node: Dictionary = _dm.get_node("laurie_after")
		_check(not node.is_empty(), "D4 laurie_after 节点存在")
		_check(node.has("variants"), "D4 laurie_after 有 variants")
		# world_alpha → 默认文本
		var ctx_a := {"world": "world_alpha", "said_nodes": [], "npc_knows": [], "relationships": {}}
		var text_a: String = _dm.resolve_text(node, ctx_a, "world_alpha")
		_check(text_a == str(node.get("text", "")), "D4 alpha 默认文本")
		# world_beta → 变体
		var ctx_b := {"world": "world_beta", "said_nodes": [], "npc_knows": [], "relationships": {}}
		var text_b: String = _dm.resolve_text(node, ctx_b, "world_beta")
		_check(text_b.contains("不一样"), "D4 beta 变体正确", text_b.substr(0, 30))
		# world_gamma → 变体
		var ctx_g := {"world": "world_gamma", "said_nodes": [], "npc_knows": [], "relationships": {}}
		var text_g: String = _dm.resolve_text(node, ctx_g, "world_gamma")
		_check(text_g.contains("分不清"), "D4 gamma 变体正确", text_g.substr(0, 30))
		_check(text_a != text_b and text_b != text_g and text_a != text_g,
			"D4 三种现实文本各不相同")
		# hear() 集成：world_id 传递正确（需先满足 fact_dark_road 前置）
		_svc.cognition.learn("fact_dark_road", "observe", "dark_road", "world_alpha", 0)
		var heard: Dictionary = _dm.hear("laurie_after", "world_beta", 0, ctx_b)
		_check(bool(heard.get("ok")), "D4 hear 成功")
		_check(str(heard.get("text", "")).contains("不一样"),
			"D4 hear 返回 beta 变体文本", str(heard.get("text", "")).substr(0, 30))
		return true
	return false


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	for line in _lines:
		print(line)
	print("=== DIALOGUE SYSTEM RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null and gs.has_method("shutdown_audio"):
		gs.shutdown_audio()
	await create_timer(0.15).timeout
	quit(1 if _fail > 0 else 0)
	return true
