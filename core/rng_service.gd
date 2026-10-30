## RngService — 具名、可持久化、可回放的随机流
##
## 职责边界：
##   提供随机数，仅此而已。不理解规则，不认识世界。
##
## 核心约定（这是本作可复现性的基石）：
##   1. 结果只由三元组 (master_seed, stream_name, draw_index) 决定。
##   2. draw_index 按流独立计数，并随存档持久化。
##   3. 因此读档后同一条流的「下一次取值」与存档前完全一致。
##
## 全项目禁止直接使用 RandomNumberGenerator 或 randi()。
## 原因：V1 早期把伪随机种子写成「规则种子 + 全局事件序列长度」，
## 导致无关事件的发生次数会改变伪随机结果——实测已复现该问题。

class_name RngService
extends RefCounted

var master_seed: int = 0
var _counters: Dictionary = {}


func set_seed(value: int) -> void:
	master_seed = value
	_counters.clear()


func reset_counters() -> void:
	_counters.clear()


## 取 [0, max_exclusive) 内的整数。
func next_int(stream_name: String, max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = _stream_seed(stream_name)
	var value: int = rng.randi() % max_exclusive
	_bump(stream_name)
	return value


## 取 [0, 1) 内的浮点数。
func next_float(stream_name: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = _stream_seed(stream_name)
	var value := rng.randf()
	_bump(stream_name)
	return value


## 按权重从 items 中取一项，返回其索引。
## weights 为空或长度不符时退化为均匀取值。
func pick_weighted(stream_name: String, items: Array, weights: Array = []) -> int:
	if items.is_empty():
		return -1
	if weights.size() != items.size():
		return next_int(stream_name, items.size())

	var total := 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return next_int(stream_name, items.size())

	var roll := next_int(stream_name, total)
	var acc := 0
	for i in items.size():
		acc += int(weights[i])
		if roll < acc:
			return i
	return items.size() - 1


func get_counters() -> Dictionary:
	return _counters.duplicate(true)


func get_draw_count(stream_name: String) -> int:
	return int(_counters.get(stream_name, 0))


func serialize() -> Dictionary:
	return {
		"master_seed": master_seed,
		"counters": _counters.duplicate(true),
	}


func restore(state: Dictionary, out_error: Array = []) -> bool:
	if state.is_empty():
		out_error.append("随机流恢复数据为空")
		return false

	var raw_counters: Variant = state.get("counters", {})
	if typeof(raw_counters) != TYPE_DICTIONARY:
		out_error.append("随机流 counters 格式错误")
		return false

	for key in (raw_counters as Dictionary).keys():
		var value: Variant = (raw_counters as Dictionary)[key]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			out_error.append("随机流计数非法: %s" % str(key))
			return false
		if int(value) < 0:
			out_error.append("随机流计数为负: %s" % str(key))
			return false

	master_seed = int(state.get("master_seed", 0))
	_counters = (raw_counters as Dictionary).duplicate(true)
	return true


# ---------------------------------------------------------------- 内部

func _stream_seed(stream_name: String) -> int:
	var index: int = int(_counters.get(stream_name, 0))
	var combined: int = master_seed * 1000003 + abs(hash(stream_name)) + index * 7919
	return abs(combined)


func _bump(stream_name: String) -> void:
	_counters[stream_name] = int(_counters.get(stream_name, 0)) + 1
