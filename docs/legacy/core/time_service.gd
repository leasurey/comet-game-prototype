## TimeService — 游戏内单调时钟
##
## 职责边界：
##   只维护「tick」这个整数计数，以及 tick 到显示时间的换算。
##   不关心谁推进了它，也不参与任何规则判定。
##
## 为什么用整数 tick 而不是真实时间：
##   节点式探索没有连续移动，时间是随玩家动作离散推进的。
##   真实时间（delta 累加）会写入不可复现的浮点值，使「同一操作序列重放两次
##   得到一致存档」无法成立。tick 是整数、单调、可存档、可比对。
##
## 继承 RefCounted：不依赖 SceneTree，可在 headless 下直接实例化测试。

class_name TimeService
extends RefCounted

const MINUTES_PER_DAY := 1440

var minutes_per_tick: int = 1
var start_minutes: int = 1360
var tick: int = 0


func configure(p_minutes_per_tick: int, p_start_minutes: int) -> void:
	if p_minutes_per_tick > 0:
		minutes_per_tick = p_minutes_per_tick
	start_minutes = p_start_minutes


func reset() -> void:
	tick = 0


## 推进时钟。steps 必须为正，负数或 0 一律忽略——时间不允许倒流。
func advance(steps: int = 1) -> void:
	if steps <= 0:
		return
	tick += steps


func get_tick() -> int:
	return tick


## 当前 tick 对应的当日分钟数。
func get_clock_minutes() -> int:
	return (start_minutes + tick * minutes_per_tick) % MINUTES_PER_DAY


func get_clock_text() -> String:
	return tick_to_text(tick)


func tick_to_text(target_tick: int) -> String:
	var total: int = (start_minutes + target_tick * minutes_per_tick) % MINUTES_PER_DAY
	var hours: int = total / 60
	var minutes: int = total % 60
	return "%02d:%02d" % [hours, minutes]


func serialize() -> Dictionary:
	return {
		"tick": tick,
		"minutes_per_tick": minutes_per_tick,
		"start_minutes": start_minutes,
	}


## 恢复失败返回 false，调用方应回退到新游戏而不是带病运行。
func restore(state: Dictionary, out_error: Array = []) -> bool:
	if state.is_empty():
		out_error.append("时钟恢复数据为空")
		return false

	var raw_tick: Variant = state.get("tick", null)
	if raw_tick == null or typeof(raw_tick) != TYPE_INT and typeof(raw_tick) != TYPE_FLOAT:
		out_error.append("时钟恢复缺少合法 tick")
		return false
	if int(raw_tick) < 0:
		out_error.append("时钟恢复的 tick 为负数: %d" % int(raw_tick))
		return false

	tick = int(raw_tick)
	if state.has("minutes_per_tick"):
		var mpt := int(state.get("minutes_per_tick", 1))
		if mpt > 0:
			minutes_per_tick = mpt
	if state.has("start_minutes"):
		start_minutes = int(state.get("start_minutes", start_minutes))
	return true
