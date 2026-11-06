## SessionResetTest — 「重新开始」必须回到真正空白的状态，返回栈不无限增长
##
## 对应缺陷（P1）：
##   BUG-005 new_game 不清空返回栈与访问记录 → 新局继承上局，一按返回就退回上局地点
##   BUG-024 返回栈只增不减 → A→B→C→B→C 会把同一地点压很多层
##
## 用法：godot --headless --script res://tests/session_reset_test.gd

extends SceneTree

var _svc: Node = null
var _sm = null
var _wm = null
var _rig = null

var _steps: Array = []
var _idx: int = 0
var _ticks: int = 0
var _t_state: int = 0
var _pass: int = 0
var _fail: int = 0
var _lines: Array = []


func _initialize() -> void:
	print("=== COMET session reset test ===")
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_stack_grows"),
		Callable(self, "step_stack_dedupes"),
		Callable(self, "step_new_game_clears"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_ticks = 0
	else:
		_ticks += 1
		if _ticks > 180:
			_check(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
	return false


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		_lines.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_lines.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


func _wait(n: int) -> bool:
	return _ticks >= n


func step_setup() -> bool:
	if _svc == null:
		_svc = root.get_node_or_null("GameServices")
		if _svc == null:
			_check(false, "setup. GameServices 可用")
			return true
		if _svc.is_ready and _svc.save_manager != null:
			_svc.save_manager.use_test_path("session_reset")
			_svc.save_manager.delete_save()
		var packed := load("res://scenes/main.tscn") as PackedScene
		var inst := packed.instantiate()
		root.add_child(inst)
		return false
	if not _wait(8):
		return false

	_sm = _svc.scene_manager
	_wm = _svc.world_manager
	_rig = _svc.player_controller
	_check(_sm != null and _wm != null and _rig != null, "setup. 服务已装配")
	_check(_sm.get_current_location_id() == _sm.get_start_location_id(),
		"setup. 开局在起始地点", _sm.get_current_location_id())
	return true


## 正常前进应当记录来路
func step_stack_grows() -> bool:
	_sm.enter_location("house_exterior", true)
	if not _wait(3):
		return false
	_check(_sm.can_go_back(), "入栈. 离开起始地点后有返回目标")
	_check(_sm.get_previous_location_id() == "party_house",
		"入栈. 来路正确", _sm.get_previous_location_id())

	_sm.enter_location("dark_road", true)
	if not _wait(3):
		return false
	var depth: int = _sm.get_visit_stack_size()
	_check(depth == 2, "入栈. 连续两次前进后栈深为 2", "depth=%d" % depth)
	return true


## 来回折返不应无限堆栈
func step_stack_dedupes() -> bool:
	_sm.enter_location("house_exterior", true)
	_sm.enter_location("dark_road", true)
	_sm.enter_location("house_exterior", true)
	_sm.enter_location("dark_road", true)
	_sm.enter_location("house_exterior", true)
	if not _wait(4):
		return false
	var depth: int = _sm.get_visit_stack_size()
	# 无去重时这里会是 7 层（起点1 + 六次前进）；去重后应稳定在 3 层以内
	_check(depth <= 3, "去重. 五次折返后栈深不增长", "depth=%d" % depth)
	_check(depth <= _sm.MAX_BACK_STACK, "上限. 栈深不超过 MAX_BACK_STACK",
		"depth=%d limit=%d" % [depth, _sm.MAX_BACK_STACK])
	return true


## 重新开始 = 真空白
##
## 注意：本步骤必须先制造"脏"状态、再调用 new_game、再等待、最后断言。
## 早期写法把这三段写在同一帧里，等待期间整段会被重复执行，
## 于是 new_game() 被连调多次，前置断言在第二次就失败——这是测试自己的缺陷。
func step_new_game_clears() -> bool:
	if _t_state == 0:
		# 先制造"脏"状态：有访问记录、有返回栈、有时钟推进、有视角偏移
		_svc.advance_tick(5)
		_rig.yaw = 1.2
		_rig.pitch = 0.3
		_rig._apply_rotation()
		_check(_sm.get_visited_locations().size() > 0, "前置. 重置前存在访问记录",
			"count=%d" % _sm.get_visited_locations().size())
		_check(_sm.can_go_back(), "前置. 重置前返回栈非空",
			"depth=%d" % _sm.get_visit_stack_size())
		_check(_svc.get_tick() > 0, "前置. 重置前时钟已推进", "tick=%d" % _svc.get_tick())
		_svc.new_game()
		_t_state = 1
		return false

	if not _wait(6):
		return false

	_check(_sm.get_current_location_id() == _sm.get_start_location_id(),
		"重置. 回到起始地点", _sm.get_current_location_id())
	_check(not _sm.can_go_back(), "重置. 返回栈已清空",
		"depth=%d" % _sm.get_visit_stack_size())
	_check(_sm.get_visited_locations().size() == 1,
		"重置. 访问记录只剩当前地点",
		str(_sm.get_visited_locations()))
	_check(_wm.get_current_world_id() == _wm.get_initial_world_id(),
		"重置. 现实回到初始值", _wm.get_current_world_id())
	_check(_svc.get_tick() == 0, "重置. 时钟归零", "tick=%d" % _svc.get_tick())
	_check(absf(_rig.yaw) < 0.0001 and absf(_rig.pitch) < 0.0001,
		"重置. 视角归零", "yaw=%.4f pitch=%.4f" % [_rig.yaw, _rig.pitch])
	_check(_wm.get_change_count() == 0, "重置. 世界变更历史为空",
		"count=%d" % _wm.get_change_count())
	_t_state = 0
	return true


func step_report() -> bool:
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== SESSION RESET RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
