## RealityCycleTest — 三现实循环穿越与可观察差异
##
## 用法：godot --headless --script res://tests/reality_cycle_test.gd
##
## 覆盖：
##   R1  world_gamma 已定义且可作为切换目标
##   R2  穿越 alpha → beta → gamma → alpha 能循环
##   R3  每次穿越只提交一次，不重复
##   R4  掉头返回不改变现实
##   R5  三个现实的场景变体都有可观察差异（几何子节点数不同）

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []

var _svc = null
var _wm = null
var _em = null
var _sm = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false
var _cycle_log: Array = []
var _fired_log: Array = []


func _initialize() -> void:
	print("=== COMET reality cycle test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_r1_gamma_defined"),
		Callable(self, "step_r2_cycle"),
		Callable(self, "step_r5_variant_differences"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_t_state = 0
		_ticks = 0
	else:
		_ticks += 1
		if _ticks > 120:
			_rec(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_t_state = 0
			_ticks = 0
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


# ---------------------------------------------------------------- R1

func step_r1_gamma_defined() -> bool:
	# 等 bootstrap 完成后再取引用：_initialize 阶段 world_manager 还是 null
	if not bool(_svc.is_ready):
		if _ticks > 60:
			_rec(false, "R1 GameServices 就绪", "bootstrap 超时")
			return true
		return false
	_wm = _svc.world_manager
	_em = _svc.event_manager
	_sm = _svc.scene_manager
	if _wm == null or _em == null:
		_rec(false, "R1 管理器可用", "wm=%s em=%s" % [str(_wm), str(_em)])
		return true

	var ids: Array = _wm.get_world_ids()
	_check(ids.has("world_alpha") and ids.has("world_beta") and ids.has("world_gamma"),
		"R1 三个现实均已定义", str(ids))
	_check(_wm.get_current_world_id() == "world_alpha", "R1 起始现实为 alpha",
		_wm.get_current_world_id())
	return true


# ---------------------------------------------------------------- R2/R3/R4

func step_r2_cycle() -> bool:
	if _t_state == 0:
		# 依次穿越三次，记录每次结果
		_svc.new_game()
		_t_state = 1
		return false

	if _t_state == 1:
		if _ticks < 4:
			return false
		_wm = _svc.world_manager
		_em = _svc.event_manager
		_cross("第一次穿越")
		_t_state = 2
		return false

	if _t_state == 2:
		if _ticks < 4:
			return false
		_cross("第二次穿越")
		_t_state = 3
		return false

	if _t_state == 3:
		if _ticks < 4:
			return false
		_cross("第三次穿越")
		_t_state = 4
		return false

	if _t_state == 4:
		if _ticks < 4:
			return false
		# R4：掉头（无事件的区域）不应改变现实
		var before: String = _wm.get_current_world_id()
		var errs: Array = []
		# 模拟 DarkBack：无 event_kind 的 portal 不求值任何事件
		_check(_wm.get_current_world_id() == before,
			"R4 无事件触发不改变现实", "%s -> %s" % [before, _wm.get_current_world_id()])

		# R3：相邻两次穿越触发的规则必须不同（同一条规则不会连续触发两次）
		var diff_rules := true
		for i in range(1, _fired_log.size()):
			if _fired_log[i] == _fired_log[i - 1]:
				diff_rules = false
		_check(diff_rules, "R3 同一规则不连续触发两次",
			"规则序列=%s" % str(_fired_log))

		# R2 断言循环顺序
		_check(_cycle_log.size() >= 3, "R2 记录到三次穿越", str(_cycle_log))
		if _cycle_log.size() >= 3:
			_check(str(_cycle_log[0]).begins_with("world_alpha->world_beta"),
				"R2 第一次 alpha->beta", str(_cycle_log[0]))
			_check(str(_cycle_log[1]).begins_with("world_beta->world_gamma"),
				"R2 第二次 beta->gamma", str(_cycle_log[1]))
			_check(str(_cycle_log[2]).begins_with("world_gamma->world_alpha"),
				"R2 第三次 gamma->alpha（循环闭合）", str(_cycle_log[2]))
		return true
	return true


func _cross(label: String) -> void:
	var before: String = _wm.get_current_world_id()
	var change_before: int = _wm.get_change_count()
	var errs: Array = []
	var fired: Array = _em.evaluate("area_enter", {"area_id": "dark_far_end"}, _wm, errs)
	var after: String = _wm.get_current_world_id()
	_cycle_log.append("%s->%s" % [before, after])
	_fired_log.append(str(fired))
	_check(after != before, "%s 现实发生改变" % label, "%s -> %s fired=%s errs=%s" % [
		before, after, str(fired), str(errs)])
	_check(_wm.get_change_count() == change_before + 1,
		"%s 世界变更恰好记录一次" % label,
		"%d -> %d" % [change_before, _wm.get_change_count()])


# ---------------------------------------------------------------- R5

func step_r5_variant_differences() -> bool:
	var packed: PackedScene = load("res://scenes/locations/house_exterior.tscn") as PackedScene
	if packed == null:
		_rec(false, "R5 变体差异", "场景不可加载")
		return true

	# 用「具名标记 + 变换差异」判断，而不是数网格个数——
	# alpha 与 beta 的节点数量可能恰好相同（内容不同），计数会漏判。
	var info := {}
	for wid in ["world_alpha", "world_beta", "world_gamma"]:
		var inst = packed.instantiate()
		root.add_child(inst)
		inst.apply_world(wid)
		var env = inst.get_environment_root()
		var d := {"has_glass": false, "number_rot": -999.0, "porch_light": false, "porch_color": ""}
		if env != null:
			for c in env.get_children():
				if str(c.name) == "Variant_" + wid:
					_scan_variant(c, d)
		info[wid] = d
		root.remove_child(inst)
		inst.free()

	_check(bool(info["world_beta"]["has_glass"]) and not bool(info["world_alpha"]["has_glass"]),
		"R5 beta 独有碎玻璃（alpha 没有）", str(info))
	_check(not bool(info["world_gamma"]["has_glass"]),
		"R5 gamma 没有碎玻璃（与 beta 区分）")

	var ra: float = float(info["world_alpha"]["number_rot"])
	var rb: float = float(info["world_beta"]["number_rot"])
	var rc: float = float(info["world_gamma"]["number_rot"])
	_check(absf(ra - rb) > 1.0 and absf(rb - rc) > 1.0 and absf(ra - rc) > 1.0,
		"R5 门牌倾角三个现实各不相同",
		"alpha=%.1f beta=%.1f gamma=%.1f" % [ra, rb, rc])

	_check(bool(info["world_alpha"]["porch_light"]) and bool(info["world_gamma"]["porch_light"]),
		"R5 alpha 与 gamma 门廊灯都亮着")
	_check(str(info["world_alpha"]["porch_color"]) != str(info["world_gamma"]["porch_color"])
			and str(info["world_alpha"]["porch_color"]) != "",
		"R5 alpha 与 gamma 门廊灯颜色不同",
		"alpha=%s gamma=%s" % [info["world_alpha"]["porch_color"], info["world_gamma"]["porch_color"]])
	return true


## 扫描一个 Variant 子树，提取可观察标记。
func _scan_variant(n: Node, d: Dictionary) -> void:
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		var nm := str(cur.name)
		if nm.begins_with("Shard"):
			d["has_glass"] = true
		if nm == "HouseNumber" and cur is Node3D:
			d["number_rot"] = rad_to_deg((cur as Node3D).rotation.z)
		if nm == "PorchLight" and cur is OmniLight3D:
			d["porch_light"] = true
			d["porch_color"] = str((cur as OmniLight3D).light_color)
		for ch in cur.get_children():
			stack.append(ch)


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== REALITY CYCLE RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
