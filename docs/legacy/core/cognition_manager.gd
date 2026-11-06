## CognitionManager — 玩家认知（知道什么、怎么知道的）
##
## 职责边界：
##   记录「玩家亲身验证过什么」，与客观世界状态**严格分离**。
##
## 核心原则（任务书 P6 的全部意义）：
##   **世界发生了变化，不代表玩家自动知道。**
##   现实从 alpha 切到 beta，玩家不会因此获得任何新事实；
##   只有玩家亲眼检查物品、亲耳听到对话，事实才进入认知。
##
## 每条认知都带来源，因为「怎么知道的」和「知道什么」一样重要：
##   inspect   —— 亲自检查过某件物品
##   dialogue  —— 从某个角色那里听到
##   observe   —— 亲眼看见过某个现象
##   infer     —— 玩家自己推断出来的（推断可能出错，不等于客观事实）
##
## 与 WorldManager 的关系：
##   WorldManager 说「世界是什么样」，本类说「玩家以为是什么样」。
##   两者可以不一致，而且**不一致正是玩法所在**。

class_name CognitionManager
extends RefCounted

## 来源类型
const SOURCE_INSPECT := "inspect"
const SOURCE_DIALOGUE := "dialogue"
const SOURCE_OBSERVE := "observe"
const SOURCE_INFER := "infer"

var _facts: Dictionary = {}
var _learned_order: Array = []
var _is_ready := false


func load_from_data(dialogue_data: Dictionary, out_error: Array = []) -> bool:
	_facts.clear()
	_learned_order.clear()
	var catalog: Variant = dialogue_data.get("facts", null)
	if typeof(catalog) == TYPE_DICTIONARY:
		for fid in (catalog as Dictionary).keys():
			var entry: Variant = (catalog as Dictionary)[fid]
			_facts[str(fid)] = {
				"label": str((entry as Dictionary).get("label", str(fid))),
				"known": false,
				"source_kind": "",
				"source_id": "",
				"world_id": "",
				"tick": -1,
			}
	_is_ready = true
	return true


func is_ready() -> bool:
	return _is_ready


## 玩家是否已经确认某条事实。
func knows(fact_id: String) -> bool:
	if not _facts.has(fact_id):
		return false
	return bool((_facts[fact_id] as Dictionary).get("known", false))


## 玩家学到一条事实。
##
## repeat_learn 不会覆盖已有来源：先学到的来源更接近"第一次确认"，
## 后续重复听到不应抹掉原始出处。
func learn(fact_id: String, source_kind: String, source_id: String,
		world_id: String = "", tick: int = -1) -> bool:
	if not _facts.has(fact_id):
		# 目录里没有的事实也允许登记（对话数据可能比目录新），
		# 但要补一个最小条目，避免静默丢失。
		_facts[fact_id] = {
			"label": fact_id, "known": false,
			"source_kind": "", "source_id": "", "world_id": "", "tick": -1,
		}
	var entry: Dictionary = _facts[fact_id]
	if bool(entry.get("known", false)):
		return false
	entry["known"] = true
	entry["source_kind"] = source_kind
	entry["source_id"] = source_id
	entry["world_id"] = world_id
	entry["tick"] = tick
	_learned_order.append(fact_id)
	return true


## 玩家意识到某条"事实"是错的。不删除记录，而是标记为已推翻，
## 因为"我曾经以为 X"本身也是剧情信息。
func retract(fact_id: String, reason: String = "") -> bool:
	if not _facts.has(fact_id):
		return false
	var entry: Dictionary = _facts[fact_id]
	if not bool(entry.get("known", false)):
		return false
	entry["known"] = false
	entry["retracted"] = true
	entry["retract_reason"] = reason
	return true


func get_label(fact_id: String) -> String:
	if not _facts.has(fact_id):
		return fact_id
	return str((_facts[fact_id] as Dictionary).get("label", fact_id))


func get_source(fact_id: String) -> Dictionary:
	if not _facts.has(fact_id):
		return {}
	return (_facts[fact_id] as Dictionary).duplicate(true)


## 所有已确认事实的 id，按学到的顺序。
func get_known_facts() -> Array:
	return _learned_order.duplicate(true)


func get_known_labels() -> Array:
	var out: Array = []
	for fid in _learned_order:
		out.append(get_label(str(fid)))
	return out


func get_known_count() -> int:
	return _learned_order.size()


func has_learned_from(source_kind: String) -> bool:
	for fid in _learned_order:
		if str((_facts[fid] as Dictionary).get("source_kind", "")) == source_kind:
			return true
	return false


## 清空（开新局）。
func reset() -> void:
	for fid in _facts.keys():
		var e: Dictionary = _facts[fid]
		e["known"] = false
		e["source_kind"] = ""
		e["source_id"] = ""
		e["world_id"] = ""
		e["tick"] = -1
		e.erase("retracted")
		e.erase("retract_reason")
	_learned_order.clear()


# ---------------------------------------------------------------- 存档

func serialize() -> Dictionary:
	return {
		"known_order": _learned_order.duplicate(true),
		"facts": _facts.duplicate(true),
	}


func restore(data: Dictionary, out_error: Array = []) -> bool:
	var raw_facts: Variant = data.get("facts", null)
	if typeof(raw_facts) != TYPE_DICTIONARY:
		out_error.append("认知存档缺少 facts 字典")
		return false
	# 只恢复目录里已知的 id，外来 id 也接受（向前兼容）
	for fid in (raw_facts as Dictionary).keys():
		_facts[str(fid)] = (raw_facts as Dictionary)[fid].duplicate(true)
	var order: Variant = data.get("known_order", [])
	if typeof(order) == TYPE_ARRAY:
		_learned_order.clear()
		for fid in (order as Array):
			if _facts.has(str(fid)) and bool((_facts[str(fid)] as Dictionary).get("known", false)):
				_learned_order.append(str(fid))
	return true
