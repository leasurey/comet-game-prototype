## ConditionEvaluator — 受限谓词条件求值
##
## 职责边界：
##   只回答「这组条件在当前上下文下是否成立」。不知道条件用在哪，也不改写状态。
##
## 为什么用白名单而不是通用表达式：
##   通用 DSL 解释器会带来解析、优先级、错误恢复等一整套复杂度，
##   而本作的条件种类是有限的。白名单还能在**载入期**就发现拼写错误，
##   而不是等到运行时静默失配。
##
## 未知谓词一律视为错误：宁可拒绝载入，也不要静默忽略一个条件。
##
## 继承 RefCounted，全部静态方法，无状态。

class_name ConditionEvaluator
extends RefCounted

const MAX_DEPTH := 2

## 上下文 ctx 的可选字段：
##   world_id      String   当前世界
##   phase_id      String   当前阶段
##   tick          int      当前 tick
##   flags         Dictionary  旗标表（缺失视为空）
##   visited       Array    已访问地点 id 列表（缺失视为空）
##   event_history Dictionary 事件历史（event_id -> {count, ...}，缺失视为空）


## 载入期校验。发现未知谓词或超深嵌套即返回 false。
static func validate(condition: Variant, out_error: Array, path: String = "requires", depth: int = 0) -> bool:
	if condition == null or (typeof(condition) == TYPE_DICTIONARY and (condition as Dictionary).is_empty()):
		return true
	if typeof(condition) != TYPE_DICTIONARY:
		out_error.append("%s 必须是对象" % path)
		return false
	if depth > MAX_DEPTH:
		out_error.append("%s 嵌套超过 %d 层" % [path, MAX_DEPTH])
		return false

	var cond: Dictionary = condition
	for key_variant in cond.keys():
		var key: String = str(key_variant)
		match key:
			"world", "phase":
				pass
			"flag":
				if not cond.has("eq"):
					out_error.append("%s.flag 缺少 eq" % path)
					return false
			"flag_gte", "flag_lte":
				if not cond.has("value"):
					out_error.append("%s.%s 缺少 value" % [path, key])
					return false
			"event_occurred":
				if str(cond[key]).is_empty():
					out_error.append("%s.event_occurred 不能为空" % path)
					return false
			"event_count_gte":
				if not cond.has("value"):
					out_error.append("%s.event_count_gte 缺少 value" % path)
					return false
			"visited":
				pass
			"tick_gte", "tick_lte":
				if not cond.has("value"):
					out_error.append("%s.%s 缺少 value" % [path, key])
					return false
			"not":
				if not validate(cond[key], out_error, path + ".not", depth + 1):
					return false
			"all", "any":
				var sub: Variant = cond[key]
				if typeof(sub) != TYPE_ARRAY:
					out_error.append("%s.%s 必须是数组" % [path, key])
					return false
				for i in (sub as Array).size():
					if not validate((sub as Array)[i], out_error, "%s.%s[%d]" % [path, key, i], depth + 1):
						return false
			_:
				out_error.append("%s 使用了未登记的谓词: %s" % [path, key])
				return false
	return true


## 运行期求值。上下文缺失的字段按「空」处理，不抛异常。
static func evaluate(condition: Variant, ctx: Dictionary) -> bool:
	if condition == null:
		return true
	if typeof(condition) != TYPE_DICTIONARY:
		return false
	var cond: Dictionary = condition
	if cond.is_empty():
		return true

	var flags: Dictionary = ctx.get("flags", {}) as Dictionary
	var visited: Array = ctx.get("visited", []) as Array
	var history: Dictionary = ctx.get("event_history", {}) as Dictionary
	var world_id: String = str(ctx.get("world_id", ""))
	var phase_id: String = str(ctx.get("phase_id", ""))
	var tick: int = int(ctx.get("tick", 0))

	for key_variant in cond.keys():
		var key: String = str(key_variant)
		var expected: Variant = cond[key]
		var ok := true

		match key:
			"world":
				if typeof(expected) == TYPE_ARRAY:
					ok = (expected as Array).has(world_id)
				else:
					ok = str(expected) == world_id
			"phase":
				ok = str(expected) == phase_id
			"flag":
				ok = _same(flags.get(str(cond.get("flag", "")), null), cond.get("eq", null))
			"flag_gte":
				ok = _to_int(flags.get(str(expected), 0)) >= _to_int(cond.get("value", 0))
			"flag_lte":
				ok = _to_int(flags.get(str(expected), 0)) <= _to_int(cond.get("value", 0))
			"event_occurred":
				ok = history.has(str(expected))
			"event_count_gte":
				var rec: Variant = history.get(str(expected), null)
				var count := 0
				if typeof(rec) == TYPE_DICTIONARY:
					count = int((rec as Dictionary).get("count", 0))
				ok = count >= _to_int(cond.get("value", 0))
			"visited":
				ok = visited.has(str(expected))
			"tick_gte":
				ok = tick >= _to_int(cond.get("value", 0))
			"tick_lte":
				ok = tick <= _to_int(cond.get("value", 0))
			"not":
				ok = not evaluate(expected, ctx)
			"all":
				if typeof(expected) != TYPE_ARRAY:
					return false
				for sub in (expected as Array):
					if not evaluate(sub, ctx):
						ok = false
						break
			"any":
				if typeof(expected) != TYPE_ARRAY:
					return false
				ok = false
				for sub in (expected as Array):
					if evaluate(sub, ctx):
						ok = true
						break
			_:
				# 未登记谓词：载入期本应拦截，运行到这里说明数据被绕过校验
				return false

		if not ok:
			return false

	return true


static func _same(actual: Variant, expected: Variant) -> bool:
	if actual == null and expected == null:
		return true
	if actual == null or expected == null:
		return false
	if typeof(actual) == TYPE_BOOL or typeof(expected) == TYPE_BOOL:
		return bool(actual) == bool(expected)
	if typeof(actual) == TYPE_STRING or typeof(expected) == TYPE_STRING:
		return str(actual) == str(expected)
	return actual == expected


static func _to_int(value: Variant) -> int:
	if typeof(value) == TYPE_BOOL:
		return 1 if bool(value) else 0
	return int(value)
