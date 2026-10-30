## DataIntegrityTest — 数据层校验与变体完整性
##
## 对应缺陷：
##   BUG-006 变体缺失静默回退（现改为返回 false + 警告）
##   BUG-016 locations.variants / transitions 交叉引用无人校验
##
## 覆盖两类检查：
##   A. DataValidator 对**真实数据**必须通过；对 6 类构造错误必须全部拦下
##   B. 每个地点声明的 variants，在场景里必须真的有对应 Variant_* 节点
##
## 用法：godot --headless --script res://tests/data_integrity_test.gd

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []


func _initialize() -> void:
	print("=== COMET data integrity test ===")
	_check_real_data()
	_check_negative_cases()
	_check_scene_variants()
	_check_apply_world()
	_report()


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		_lines.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_lines.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


func _load(name: String) -> Dictionary:
	var r := DataLoader.load_dictionary("res://data/%s.json" % name)
	if not bool(r.get("ok", false)):
		_check(false, "载入 data/%s.json" % name, str(r.get("error", "")))
		return {}
	return r.get("data", {})


# ------------------------------------------------------------------ A1 真实数据

func _check_real_data() -> void:
	var worlds := _load("worlds")
	var events := _load("events")
	var transitions := _load("world_transitions")
	var locations := _load("locations")
	if worlds.is_empty() or locations.is_empty():
		return

	var report := DataValidator.validate(worlds, events, transitions, locations)
	var errs: Array = report.get("errors", [])
	_check(bool(report.get("ok", false)), "真实数据通过交叉校验",
		"errors=%s" % str(errs))
	for e in errs:
		_lines.append("    · " + str(e))


# ------------------------------------------------------------------ A2 负例

func _base() -> Array:
	var worlds := {"initial_world": "w_a", "worlds": [
		{"id": "w_a", "origin": ""}, {"id": "w_b", "origin": "w_a"}]}
	var events := {"events": [{"id": "e1"}]}
	var transitions := {"transitions": [{
		"id": "t1", "type": "fixed",
		"trigger": {"kind": "area_enter", "area_id": "far"},
		"to_world": "w_b"}]}
	var locations := {"start_location": "loc_a", "locations": [
		{"id": "loc_a", "scene": "res://x.tscn", "spawn": {"position": [0, 0, 0]},
			"variants": ["w_a", "w_b"], "exits": [{"target": "loc_b"}]},
		{"id": "loc_b", "scene": "res://y.tscn", "spawn": {"position": [1, 0, 2]},
			"variants": ["w_a"], "exits": []}]}
	return [worlds, events, transitions, locations]


func _expect_fail(label: String, mutate: Callable, keyword: String) -> void:
	var b := _base()
	var worlds: Dictionary = b[0]
	var events: Dictionary = b[1]
	var transitions: Dictionary = b[2]
	var locations: Dictionary = b[3]
	mutate.call(worlds, events, transitions, locations)
	var report := DataValidator.validate(worlds, events, transitions, locations)
	var errs: Array = report.get("errors", [])
	var hit := false
	for e in errs:
		if str(e).find(keyword) >= 0:
			hit = true
			break
	_check(not bool(report.get("ok", true)) and hit,
		"负例被拦下: " + label, "命中关键字=%s errors=%s" % [keyword, str(errs)])


func _check_negative_cases() -> void:
	# 基线本身必须通过，否则后面的负例没有意义
	var b := _base()
	var base_report := DataValidator.validate(b[0], b[1], b[2], b[3])
	_check(bool(base_report.get("ok", false)), "负例基线数据本身合法",
		str(base_report.get("errors", [])))

	_expect_fail("variants 指向未定义现实",
		func(_w, _e, _t, l): (l["locations"][0] as Dictionary)["variants"] = ["w_a", "w_gamma"],
		"未定义现实")

	_expect_fail("transitions.to_world 未定义",
		func(_w, _e, t, _l): (t["transitions"][0] as Dictionary)["to_world"] = "w_ghost",
		"to_world 未定义")

	_expect_fail("area_enter 缺 area_id",
		func(_w, _e, t, _l): (t["transitions"][0] as Dictionary)["trigger"] = {"kind": "area_enter"},
		"缺少 area_id")

	_expect_fail("exits 指向未定义地点",
		func(_w, _e, _t, l): (l["locations"][0] as Dictionary)["exits"] = [{"target": "loc_ghost"}],
		"未定义地点")

	_expect_fail("地点 id 重复",
		func(_w, _e, _t, l): (l["locations"] as Array).append((l["locations"] as Array)[0]),
		"地点 id 重复")

	_expect_fail("initial_world 未定义",
		func(w, _e, _t, _l): (w as Dictionary)["initial_world"] = "w_nowhere",
		"initial_world 未定义")


# ------------------------------------------------------------------ B 场景变体

func _check_scene_variants() -> void:
	var locations := _load("locations")
	var list: Array = locations.get("locations", [])
	for entry in list:
		var loc: Dictionary = entry
		var lid := str(loc.get("id", ""))
		var path := str(loc.get("scene", ""))
		if not ResourceLoader.exists(path):
			_check(false, "场景存在: " + lid, path)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			_check(false, "场景可加载: " + lid, path)
			continue
		var inst := packed.instantiate()
		var env := inst.find_child("Environment", false, false)
		var found: Array = []
		if env != null:
			for c in env.get_children():
				var n := str(c.name)
				if n.begins_with("Variant_"):
					found.append(n.substr(8))
		var declared: Array = loc.get("variants", [])
		var missing: Array = []
		for v in declared:
			if not found.has(str(v)):
				missing.append(str(v))
		_check(missing.is_empty(), "变体齐备: " + lid,
			"声明=%s 实际=%s 缺=%s" % [str(declared), str(found), str(missing)])
		inst.free()


# ------------------------------------------------------------------ C 运行时行为

func _check_apply_world() -> void:
	var packed := load("res://scenes/locations/party_house.tscn") as PackedScene
	if packed == null:
		_check(false, "apply_world 前置: 场景可加载")
		return
	var inst := packed.instantiate()
	inst.set_location_id("party_house")

	var ok_alpha: bool = inst.apply_world("world_alpha")
	_check(ok_alpha, "apply_world 命中已知现实时返回 true")
	_check(inst.get_applied_world_id() == "world_alpha", "apply_world 记录了当前现实")

	var ok_ghost: bool = inst.apply_world("world_gamma")
	_check(not ok_ghost, "apply_world 缺变体时返回 false（不再静默）")
	_check(inst.get_applied_world_id() == "world_gamma",
		"缺变体时仍记录请求的现实，便于定位")

	# 共享几何不得被隐藏：Environment 下非 Variant_ 的节点必须保持 visible
	var env := inst.find_child("Environment", false, false)
	if env != null:
		var shared_visible := 0
		var shared_total := 0
		for c in env.get_children():
			if str(c.name).begins_with("Variant_"):
				continue
			shared_total += 1
			if (c as Node3D).visible:
				shared_visible += 1
		_check(shared_total == 0 or shared_visible == shared_total,
			"共享节点在切换现实后仍可见",
			"%d/%d" % [shared_visible, shared_total])

	inst.free()


func _report() -> void:
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== DATA INTEGRITY RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
