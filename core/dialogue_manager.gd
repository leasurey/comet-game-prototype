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
func get_available_for(speaker_id: String) -> Array:
	var out: Array = []
	for nid in _nodes.keys():
		var n: Dictionary = _nodes[nid]
		if str(n.get("speaker", "")) != speaker_id:
			continue
		if not _requirements_met(n.get("requires", [])):
			continue
		out.append(n.duplicate(true))
	return out


## 取某个节点（用于逐层深入对话）。
func get_node(node_id: String) -> Dictionary:
	if not _nodes.has(node_id):
		return {}
	return (_nodes[node_id] as Dictionary).duplicate(true)


## 玩家"听到"某段对话：登记认知并返回这段的内容。
## 返回值含 grants 实际生效了哪些（已知的不重复授予）。
func hear(node_id: String, world_id: String = "", tick: int = -1) -> Dictionary:
	if not _nodes.has(node_id):
		return {"ok": false, "error": "对话节点不存在: %s" % node_id, "granted": []}
	var n: Dictionary = _nodes[node_id]
	if not _requirements_met(n.get("requires", [])):
		return {"ok": false, "error": "前置认知未满足", "granted": []}

	var granted: Array = []
	var speaker := str(n.get("speaker", ""))
	for fid in (n.get("grants", []) as Array):
		if _cognition != null:
			if _cognition.learn(str(fid), "dialogue", speaker, world_id, tick):
				granted.append(str(fid))
	return {
		"ok": true,
		"error": "",
		"id": node_id,
		"speaker": speaker,
		"text": str(n.get("text", "")),
		"replies": (n.get("replies", []) as Array).duplicate(true),
		"granted": granted,
	}


## 判断前置条件是否满足。空条件 = 无条件可用。
func _requirements_met(requires: Variant) -> bool:
	if typeof(requires) != TYPE_ARRAY:
		return true
	if (requires as Array).is_empty():
		return true
	if _cognition == null:
		return false
	for fid in (requires as Array):
		if not _cognition.knows(str(fid)):
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
