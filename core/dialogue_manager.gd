## DialogueManager — 数据驱动对话与认知闸门
##
## 职责边界：
##   决定「玩家此刻能听到什么」，并把听到的内容转化为认知。
##   不决定 NPC 该说什么——那是数据；不决定玩家该知道什么——那是玩家的选择。
##
## 两个核心机制：
##   1. requires —— 某些对话只有在玩家已经知道前置事实后才出现。
##      这正是"世界知道 ≠ 玩家知道"的落地：玩家没检查过便签，
##      就不会有人跟他谈便签。
##   2. grants —— 听完这段对话，玩家获得一条认知。
##      认知的来源被记录为 dialogue:<speaker>，可追溯。

class_name DialogueManager
extends RefCounted

var _nodes: Dictionary = {}
var _cognition = null
var _is_ready := false


func set_cognition(cog) -> void:
	_cognition = cog


func load_from_data(dialogue_data: Dictionary, out_error: Array = []) -> bool:
	_nodes.clear()
	var raw: Variant = dialogue_data.get("nodes", null)
	if typeof(raw) != TYPE_ARRAY:
		out_error.append("dialogue.json 缺少 nodes 数组")
		return false
	for n in (raw as Array):
		if typeof(n) != TYPE_DICTIONARY:
			out_error.append("dialogue.json 含非法节点条目")
			return false
		var nid := str((n as Dictionary).get("id", "")).strip_edges()
		if nid.is_empty():
			out_error.append("dialogue.json 有节点缺少 id")
			return false
		if _nodes.has(nid):
			out_error.append("dialogue.json 节点 id 重复: %s" % nid)
			return false
		_nodes[nid] = (n as Dictionary).duplicate(true)
	_is_ready = true
	return true


func is_ready() -> bool:
	return _is_ready


func has_node(node_id: String) -> bool:
	return _nodes.has(node_id)


## 玩家此刻能对某个 NPC 说的话（经过认知闸门过滤）。
## npc_context 可选：{"npc_knows": [...], "relationships": {target: {trust, familiarity}}, "said_nodes": [...]}
## 提供后额外检查 npc_knows / relationship_at_least / said / not_said 条件。
func get_available_for(speaker_id: String, npc_context: Dictionary = {}) -> Array:
	var out: Array = []
	for nid in _nodes.keys():
		var n: Dictionary = _nodes[nid]
		if str(n.get("speaker", "")) != speaker_id:
			continue
		if not _requirements_met(n.get("requires", []), npc_context):
			continue
		out.append(n.duplicate(true))
	return out


## 话题入口：可作为对话起点摆上话题列表的节点。
##
## 判定：当前可用（requires 已满足）**且不被任何节点的 replies.goto 引用**。
## 被 goto 引用的节点是分支应答，只能沿对话树走到——
## 若也列进话题列表，玩家会看到「同一句话既是话题又是回答」的重复入口。
func get_entry_nodes_for(speaker_id: String, npc_context: Dictionary = {}) -> Array:
	var goto_targets := {}
	for nid in _nodes.keys():
		for r in (_nodes[nid] as Dictionary).get("replies", []):
			var g: Variant = (r as Dictionary).get("goto", null)
			if g != null:
				goto_targets[str(g)] = true
	var out: Array = []
	for n in get_available_for(speaker_id, npc_context):
		if not goto_targets.has(str(n.get("id", ""))):
			out.append(n)
	return out


## 取某个节点（用于逐层深入对话）。
func get_node(node_id: String) -> Dictionary:
	if not _nodes.has(node_id):
		return {}
	return (_nodes[node_id] as Dictionary).duplicate(true)


## 解析对话文本：按 variants 优先级选择最匹配的文本变体。
##
## variants 格式：[{"when": {...条件...}, "text": "替换文本"}]
## 条件与 requires 共用谓词白名单，外加 "world" 键（匹配当前现实 id）。
## 取第一个满足条件的 variant；无匹配则用默认 text。
## 依赖 npc_context（npc_knows/relationships/said_nodes）和 world_id。
func resolve_text(node: Dictionary, npc_context: Dictionary = {}, world_id: String = "") -> String:
	var variants_raw: Variant = node.get("variants", null)
	if typeof(variants_raw) != TYPE_ARRAY or (variants_raw as Array).is_empty():
		return str(node.get("text", ""))
	# 构建完整上下文（world 加入 npc_context 供统一谓词使用）
	var ctx := npc_context.duplicate(true)
	ctx["world"] = world_id
	for v in (variants_raw as Array):
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var vd: Dictionary = v
		if _requirements_met(vd.get("when", null), ctx):
			return str(vd.get("text", node.get("text", "")))
	return str(node.get("text", ""))


## 玩家"听到"某段对话：登记认知并返回这段的内容。
## 文本经 resolve_text 解析（variants 按现实/认知/关系/进度选择变体）。
func hear(node_id: String, world_id: String = "", tick: int = -1,
		npc_context: Dictionary = {}) -> Dictionary:
	if not _nodes.has(node_id):
		return {"ok": false, "error": "对话节点不存在: %s" % node_id, "granted": [], "fired": [], "teaches_npc": [], "text": ""}
	var n: Dictionary = _nodes[node_id]
	if not _requirements_met(n.get("requires", []), npc_context):
		return {"ok": false, "error": "前置条件未满足", "granted": [], "fired": [], "teaches_npc": [], "text": ""}

	var granted: Array = []
	var speaker := str(n.get("speaker", ""))
	for fid in (n.get("grants", []) as Array):
		if _cognition != null:
			if _cognition.learn(str(fid), "dialogue", speaker, world_id, tick):
				granted.append(str(fid))
	var fired: Array = []
	for eid in (n.get("fires", []) as Array):
		fired.append(str(eid))
	var teaches_npc: Array = []
	for fid in (n.get("teaches_npc", []) as Array):
		teaches_npc.append(str(fid))
	# 文本变体解析（批次 4）：根据现实/认知/关系/进度选最匹配的文本
	var resolved_text := resolve_text(n, npc_context, world_id)
	return {
		"ok": true,
		"error": "",
		"id": node_id,
		"speaker": speaker,
		"text": resolved_text,
		"base_text": str(n.get("text", "")),
		"replies": (n.get("replies", []) as Array).duplicate(true),
		"granted": granted,
		"fired": fired,
		"teaches_npc": teaches_npc,
	}


## 判断前置条件是否满足。
## 格式一（兼容旧档）：数组 = 全部为玩家已知事实 id。
## 格式二（批次 3）：对象 {"player_knows": [...], "npc_knows": [...],
##   "relationship_at_least": {"target": "player", "trust": 0.3},
##   "said": [...], "not_said": [...]}
func _requirements_met(requires: Variant, npc_context: Dictionary = {}) -> bool:
	if requires == null:
		return true
	# 旧格式：数组
	if typeof(requires) == TYPE_ARRAY:
		if (requires as Array).is_empty():
			return true
		if _cognition == null:
			return false
		for fid in (requires as Array):
			if not _cognition.knows(str(fid)):
				return false
		return true
	# 新格式：对象
	if typeof(requires) != TYPE_DICTIONARY:
		return true
	var req: Dictionary = requires
	if req.is_empty():
		return true

	# world: 只在特定现实下可用（variants 用）
	var world_req: Variant = req.get("world", null)
	if world_req != null:
		var expect := str(world_req)
		var actual := str(npc_context.get("world", ""))
		# 空 actual 表示调用方未提供现实信息，无法匹配 → 不满足
		if expect != actual:
			return false

	# player_knows：玩家认知
	var pk: Variant = req.get("player_knows", [])
	if typeof(pk) == TYPE_ARRAY and not (pk as Array).is_empty():
		if _cognition == null:
			return false
		for fid in (pk as Array):
			if not _cognition.knows(str(fid)):
				return false

	# npc_knows：NPC 认知
	var nk: Variant = req.get("npc_knows", [])
	if typeof(nk) == TYPE_ARRAY and not (nk as Array).is_empty():
		var npc_facts: Variant = npc_context.get("npc_knows", [])
		if typeof(npc_facts) != TYPE_ARRAY:
			return false
		for fid in (nk as Array):
			if not (npc_facts as Array).has(str(fid)):
				return false

	# relationship_at_least: {"target": "player", "trust": 0.3}
	var rel_req: Variant = req.get("relationship_at_least", null)
	if typeof(rel_req) == TYPE_DICTIONARY:
		var target := str((rel_req as Dictionary).get("target", "player"))
		var min_trust := float((rel_req as Dictionary).get("trust", 0.0))
		var rels: Variant = npc_context.get("relationships", {})
		if typeof(rels) != TYPE_DICTIONARY:
			return false
		var rel: Variant = (rels as Dictionary).get(target, null)
		if typeof(rel) != TYPE_DICTIONARY:
			return false
		if float((rel as Dictionary).get("trust", 0.0)) < min_trust:
			return false

	# said: 对话节点已说过
	var said_req: Variant = req.get("said", [])
	if typeof(said_req) == TYPE_ARRAY and not (said_req as Array).is_empty():
		var said: Variant = npc_context.get("said_nodes", [])
		if typeof(said) != TYPE_ARRAY:
			return false
		for nid in (said_req as Array):
			if not (said as Array).has(str(nid)):
				return false

	# not_said: 对话节点未说过
	var ns_req: Variant = req.get("not_said", [])
	if typeof(ns_req) == TYPE_ARRAY and not (ns_req as Array).is_empty():
		var said2: Variant = npc_context.get("said_nodes", [])
		if typeof(said2) == TYPE_ARRAY:
			for nid in (ns_req as Array):
				if (said2 as Array).has(str(nid)):
					return false

	return true


## 某条认知会解锁哪些对话（用于 UI 提示「你了解到了新情况」）。
func nodes_unlocked_by(fact_id: String) -> Array:
	var out: Array = []
	for nid in _nodes.keys():
		var reqs: Variant = (_nodes[nid] as Dictionary).get("requires", [])
		if typeof(reqs) == TYPE_ARRAY and (reqs as Array).has(fact_id):
			out.append(nid)
	return out
