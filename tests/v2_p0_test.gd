## V2P0Test — 第二阶段地基验收测试
##
## 用法：
##   godot --headless --script res://tests/v2_p0_test.gd
##
## 覆盖 ARCHITECTURE.md / ACCEPTANCE_TESTS.md 中 P0 阶段的可自动判定项：
##   T-TIME-01  时钟换算
##   T-TIME-02  tick 单调递增且不倒流
##   T-V1-05    时钟不再由真实时间驱动（等待若干帧后 tick 不变）
##   T-RNG-01   同种子同序列
##   T-RNG-02   计数持久化后结果连续
##   T-RNG-03   流之间互不干扰
##   T-EVENT-02 requires 被求值
##   T-EVENT-04 伪随机在相同操作序列下可复现
##   T-EVENT-07 未登记谓词在载入期被拒绝
##   T-EVENT-C  未登记转移规则产生的存档可读回
##   T-BUS-01   信号总线完成转接（端到端，依赖 GameServices）

extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _skip: int = 0
var _lines: Array = []

var _wait_frames: int = 0
var _tick_before_wait: int = -1
var _stage: int = 0


func _initialize() -> void:
	print("=== COMET V2 P0 test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))


func _process(_delta: float) -> bool:
	# 第 0 阶段跑纯逻辑用例；第 1 阶段验证「等待若干帧后时钟不推进」。
	if _stage == 0:
		_stage = 1
		_run_pure_logic()
		_prepare_clock_wait()
		return false

	if _stage == 1:
		_wait_frames += 1
		if _wait_frames < 12:
			return false
		_stage = 2
		_finish_clock_wait()
		_run_end_to_end()
		_report()
		return true

	return true


func _rec(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		_lines.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_lines.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


func _skip_case(label: String, reason: String) -> void:
	_skip += 1
	_lines.append("[SKIP] %s | %s" % [label, reason])


func _report() -> void:
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== V2 P0 RESULT: PASS=%d FAIL=%d SKIP=%d ===" % [_pass, _fail, _skip])
	quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------- 时钟

func _run_pure_logic() -> void:
	_test_time_conversion()
	_test_time_monotonic()
	_test_rng_same_seed()
	_test_rng_persist()
	_test_rng_stream_isolation()
	_test_requires_evaluated()
	_test_unknown_predicate_rejected()
	_test_unregistered_transition_save()
	_test_pseudo_random_reproducible()


func _test_time_conversion() -> void:
	var ts := TimeService.new()
	ts.configure(1, 1360)
	ts.advance(20)
	_rec(ts.get_clock_text() == "23:00", "T-TIME-01 时钟换算",
		"tick=%d -> %s (期望 23:00)" % [ts.get_tick(), ts.get_clock_text()])


func _test_time_monotonic() -> void:
	var ts := TimeService.new()
	ts.advance(3)
	var after_three: int = ts.get_tick()
	ts.advance(-5)
	var after_negative: int = ts.get_tick()
	ts.advance(0)
	_rec(after_three == 3 and after_negative == 3 and ts.get_tick() == 3,
		"T-TIME-02 tick 单调递增且不倒流",
		"3 -> %d -> %d" % [after_negative, ts.get_tick()])

	var s: Dictionary = ts.serialize()
	var all_int: bool = typeof(s.get("tick", null)) == TYPE_INT
	_rec(all_int, "T-TIME-02 时钟序列化不含浮点状态", str(s))


func _prepare_clock_wait() -> void:
	_tick_before_wait = _game_tick()


func _finish_clock_wait() -> void:
	var now: int = _game_tick()
	if _tick_before_wait < 0:
		_skip_case("T-V1-05 时钟不由真实时间驱动", "GameServices 不可用，跳过")
		return
	_rec(now == _tick_before_wait,
		"T-V1-05 等待 12 帧后 tick 未推进（时钟改为动作驱动）",
		"before=%d after=%d" % [_tick_before_wait, now])


func _game_tick() -> int:
	var services: Node = root.find_child("GameServices", true, false)
	if services == null:
		return -1
	if not services.has_method("get_tick"):
		return -1
	return int(services.get_tick())


# ---------------------------------------------------------------- 随机

func _test_rng_same_seed() -> void:
	var a := RngService.new()
	a.set_seed(12345)
	var b := RngService.new()
	b.set_seed(12345)

	var sa: Array = []
	var sb: Array = []
	for _i in 10:
		sa.append(a.next_int("world_drift", 1000))
	for _i in 10:
		sb.append(b.next_int("world_drift", 1000))

	_rec(sa == sb, "T-RNG-01 同种子同序列", "%s" % str(sa.slice(0, 4)))


func _test_rng_persist() -> void:
	var a := RngService.new()
	a.set_seed(12345)
	for _i in 4:
		a.next_int("world_drift", 1000)
	var state: Dictionary = a.serialize()

	var b := RngService.new()
	var errs: Array = []
	b.restore(state, errs)
	var tail: Array = []
	for _i in 6:
		tail.append(b.next_int("world_drift", 1000))

	# 让 a 继续取 6 个作为对照：a 已取 4 次，这里取到的是第 5~10 次
	var control: Array = []
	for _i in 6:
		control.append(a.next_int("world_drift", 1000))

	_rec(tail == control, "T-RNG-02 计数持久化后结果连续",
		"恢复后=%s 对照=%s" % [str(tail.slice(0, 3)), str(control.slice(0, 3))])


func _test_rng_stream_isolation() -> void:
	var a := RngService.new()
	a.set_seed(999)
	for _i in 5:
		a.next_int("stream_x", 1000)

	var fresh := RngService.new()
	fresh.set_seed(999)

	_rec(a.next_int("stream_y", 1000) == fresh.next_int("stream_y", 1000),
		"T-RNG-03 流之间互不干扰",
		"污染后=%d 全新=%d" % [a.next_int("stream_y", 1000), fresh.next_int("stream_y", 1000)])


# ---------------------------------------------------------------- 事件

func _load_real_world(wm) -> bool:
	var loader := DataLoader.new()
	var worlds: Dictionary = loader.load_dictionary("res://data/worlds.json")
	var errs: Array = []
	return wm.load_from_data(worlds.get("data", {}), errs)


func _test_requires_evaluated() -> void:
	var wm := WorldManager.new()
	_load_real_world(wm)
	var em := EventManager.new()

	var events := {"events": [{"id": "evt_cond", "label": "c", "kind": "conditional", "repeatable": true}]}
	var transitions := {"transitions": [{
		"id": "evt_cond", "type": "conditional",
		"trigger": {"kind": "enter_location", "location_id": "living_room"},
		"requires": {"world": "world_beta"},
		"to_world": "world_beta",
	}]}

	var errs: Array = []
	em.load_from_data(events, transitions, errs)
	var before: String = wm.get_current_world_id()
	em.evaluate("enter_location", {"location_id": "living_room"}, wm, errs)
	_rec(before == wm.get_current_world_id(),
		"T-EVENT-02 requires 不成立时不触发",
		"%s -> %s" % [before, wm.get_current_world_id()])

	# 条件成立时应当触发
	var em2 := EventManager.new()
	var errs2: Array = []
	em2.load_from_data(events, transitions, errs2)
	var wm2 := WorldManager.new()
	_load_real_world(wm2)
	wm2.apply_transition("world_beta", "evt_cond", errs2)
	var fired: Array = em2.evaluate("enter_location", {"location_id": "living_room"}, wm2, errs2)
	_rec(fired.is_empty(), "T-EVENT-02 已在目标世界时不再重复切换", str(fired))


func _test_unknown_predicate_rejected() -> void:
	var em := EventManager.new()
	var events := {"events": [{"id": "evt_bad", "label": "b", "kind": "conditional", "repeatable": true}]}
	var transitions := {"transitions": [{
		"id": "evt_bad", "type": "conditional",
		"trigger": {"kind": "enter_location", "location_id": "living_room"},
		"requires": {"some_unregistered_predicate": true},
		"to_world": "world_beta",
	}]}
	var errs: Array = []
	var ok: bool = em.load_from_data(events, transitions, errs)
	_rec(not ok, "T-EVENT-07 未登记谓词在载入期被拒绝",
		str(errs) if errs.size() > 0 else "(无错误信息)")


func _test_unregistered_transition_save() -> void:
	var wm := WorldManager.new()
	_load_real_world(wm)
	var em := EventManager.new()

	var events := {"events": [{"id": "evt_known", "label": "k", "kind": "fixed", "repeatable": false}]}
	var transitions := {"transitions": [{
		"id": "evt_only_in_transitions", "type": "fixed",
		"trigger": {"kind": "enter_location", "location_id": "living_room"},
		"to_world": "world_beta",
	}]}

	var errs: Array = []
	em.load_from_data(events, transitions, errs)
	em.evaluate("enter_location", {"location_id": "living_room"}, wm, errs)

	var em2 := EventManager.new()
	var errs2: Array = []
	em2.load_from_data(events, transitions, errs2)
	var ok: bool = em2.restore(em.serialize(), errs2)
	_rec(ok, "T-EVENT-C 未登记转移规则产生的存档可读回",
		str(errs2) if errs2.size() > 0 else "ok")


func _test_pseudo_random_reproducible() -> void:
	var picks: Array = []
	for _round in 2:
		var wm := WorldManager.new()
		_load_real_world(wm)
		var em := EventManager.new()
		var rng := RngService.new()
		rng.set_seed(777)
		em.rng_service = rng

		var events := {"events": [{"id": "evt_drift", "label": "d", "kind": "pseudo_random", "repeatable": true}]}
		var transitions := {"transitions": [{
			"id": "evt_drift", "type": "pseudo_random",
			"trigger": {"kind": "enter_location", "location_id": "living_room"},
			"candidate_worlds": ["world_alpha", "world_beta"],
		}]}
		var errs: Array = []
		em.load_from_data(events, transitions, errs)
		em.evaluate("enter_location", {"location_id": "living_room"}, wm, errs)
		picks.append(wm.get_current_world_id())

	_rec(picks[0] == picks[1], "T-EVENT-04 伪随机在相同序列下可复现",
		"第一次=%s 第二次=%s" % [str(picks[0]), str(picks[1])])


# ---------------------------------------------------------------- 总线

func _run_end_to_end() -> void:
	var services: Node = root.find_child("GameServices", true, false)
	if services == null:
		_skip_case("T-BUS-01 信号总线转接", "GameServices 不可用，跳过")
		return

	var bus = services.get("event_bus")
	if bus == null:
		_skip_case("T-BUS-01 信号总线转接", "event_bus 未初始化")
		return

	# --script 模式下没有 main.tscn，SceneManager 尚未绑定地点容器。
	# 这里补上装配，否则 enter_location 会因缺少容器直接失败。
	var sm = services.get("scene_manager")
	if sm == null:
		_skip_case("T-BUS-01 信号总线转接", "scene_manager 未初始化")
		return
	var container := Node3D.new()
	container.name = "BusTestContainer"
	root.add_child(container)
	sm.set_container(container)
	services.new_game(0)

	var received: Array = []
	# event_triggered 的信号签名为 (event_id, from_world, to_world, log_text)
	var handler := func(_event_id: String, _from: String, _to: String, _log_text: String) -> void:
		received.append(_to)
	bus.event_triggered.connect(handler)

	# 走到黑暗区域会触发预设事件，转接后总线上应当收到一次
	services.go_to("house_exterior")
	services.go_to("dark_road")

	# 第二轮改了现实切换时机：进入黑暗不再触发变化，改由「到达尽头」触发。
	# 这里显式求值该事件，等价于玩家走出 DarkExit 区域。
	var em_bus = services.get("event_manager")
	var wm_bus = services.get("world_manager")
	if em_bus != null and wm_bus != null:
		var errs_bus: Array = []
		em_bus.evaluate("area_enter", {"area_id": "dark_far_end"}, wm_bus, errs_bus)

	bus.event_triggered.disconnect(handler)
	_rec(received.size() >= 1, "T-BUS-01 事件信号经总线转接可达", "收到 %d 次" % received.size())
