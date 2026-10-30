## PlayerJumpTest — 跳跃、落地、奔跑与移动状态验收
## 用法：godot --headless --script res://tests/player_jump_test.gd
## 使用真实 main.tscn 与物理碰撞，不直接修改玩家 Y 坐标伪造跳跃。

extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []
var _services: Node = null
var _main: Node = null
var _rig: PlayerController = null
var _sm: SceneManager = null
var _steps: Array = []
var _idx: int = 0
var _ticks: int = 0
var _t_state: int = 0
var _pf_start: int = 0
var _pf_needed: int = 0
var _jumped: int = 0
var _landed: int = 0
var _start_y: float = 0.0
var _max_y: float = -999.0
var _walk_distance: float = 0.0
var _run_distance: float = 0.0
var _measure_start := Vector3.ZERO
var _measure_frames: int = 0


func _initialize() -> void:
	print("=== COMET player jump test ===")
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_ground_jump"),
		Callable(self, "step_apex_and_landing"),
		Callable(self, "step_no_double_jump"),
		Callable(self, "step_jump_collision"),
		Callable(self, "step_run_speed"),
		Callable(self, "step_release_stop"),
		Callable(self, "step_switch_resets"),
		Callable(self, "step_look_during_jump"),
		Callable(self, "step_cleanup"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	if _rig != null:
		_max_y = maxf(_max_y, _rig.global_position.y)
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_t_state = 0
		_pf_needed = 0
		_ticks = 0
	else:
		_ticks += 1
		if _ticks > 1200:
			_record(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_t_state = 0
			_ticks = 0
	return false


func _record(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_results.append("[%s] %s%s" % ["PASS" if ok else "FAIL", label,
			(" | " + detail) if detail != "" else ""])


func _check(ok: bool, label: String, detail: String = "") -> void:
	_record(ok, label, detail)


func _wait(frames: int) -> bool:
	if _pf_needed == 0:
		_pf_start = Engine.get_physics_frames()
		_pf_needed = frames
	if Engine.get_physics_frames() - _pf_start < _pf_needed:
		return false
	_pf_needed = 0
	return true


func _release() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "run", "jump"]:
		Input.action_release(a)


func _reset(pos: Vector3 = Vector3(0.0, 0.25, 4.2)) -> void:
	_release()
	_rig.reset_to_spawn(pos)
	_rig.reset_view()
	_max_y = pos.y


func step_setup() -> bool:
	if _t_state == 0:
		_services = root.get_node_or_null("GameServices")
		if _services == null:
			_check(false, "setup. GameServices 可用")
			return true
		if _services.is_ready and _services.save_manager != null:
			_services.save_manager.use_test_path("player_jump")
			_services.save_manager.delete_save()
		var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
		_main = packed.instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if not _wait(10):
		return false
	_rig = _services.player_controller as PlayerController
	_sm = _services.scene_manager
	_check(_rig != null and _rig is CharacterBody3D, "setup. 真实物理玩家已装配")
	_check(InputMap.has_action("jump"), "setup. Space 跳跃动作已注册")
	_check(InputMap.has_action("run"), "setup. Shift 奔跑动作已注册")
	_check(InputMap.has_action("phone"), "setup. 手机快捷键已注册")
	if _rig != null:
		_rig.jumped.connect(func() -> void: _jumped += 1)
		_rig.landed.connect(func(_speed: float) -> void: _landed += 1)
	return true


func step_ground_jump() -> bool:
	if _t_state == 0:
		_reset()
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait(20):
			return false
		_check(_rig.is_on_floor(), "J01 起跳前玩家站在地面")
		_start_y = _rig.global_position.y
		_max_y = _start_y
		_rig.request_jump()
		_t_state = 2
		return false
	if not _wait(4):
		return false
	_check(_rig.global_position.y > _start_y + 0.08, "J01 地面跳跃产生真实上升",
			"y %.3f -> %.3f" % [_start_y, _rig.global_position.y])
	_check(_jumped == 1, "J01 跳跃信号只触发一次", "jumped=%d" % _jumped)
	_check(_rig.movement_state == "jumping", "J01 上升状态为 jumping", _rig.movement_state)
	return true


func step_apex_and_landing() -> bool:
	if _t_state == 0:
		_t_state = 1
		return false
	if _t_state == 1:
		if _rig.is_on_floor() or _ticks > 100:
			_t_state = 2
		return false
	var height: float = _max_y - _start_y
	_check(height > 0.45 and height < 0.85, "J02 跳跃高度受住宅尺度约束",
			"max_height=%.3f m" % height)
	_check(_rig.is_on_floor(), "J02 跳跃后正常落地")
	_check(_landed >= 1, "J02 落地信号触发", "landed=%d" % _landed)
	_check(_rig.movement_state in ["landing", "idle"], "J02 落地后状态恢复", _rig.movement_state)
	_check(absf(_rig.global_position.y - _start_y) < 0.12, "J02 落地没有陷入地板",
			"y=%.3f start=%.3f" % [_rig.global_position.y, _start_y])
	return true


func step_no_double_jump() -> bool:
	if _t_state == 0:
		_reset()
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait(15):
			return false
		_rig.request_jump()
		_t_state = 2
		return false
	if _t_state == 2:
		if not _wait(5):
			return false
		var before: int = _jumped
		for i in 8:
			_rig.request_jump()
		_t_state = 3
		return false
	if not _wait(5):
		return false
	_check(_jumped == 2, "J03 空中连续按键不能二段跳", "jumped=%d" % _jumped)
	_check(_rig.global_position.y < _start_y + 1.0, "J03 没有获得无限空中推进",
			"y=%.3f" % _rig.global_position.y)
	return true


func step_jump_collision() -> bool:
	if _t_state == 0:
		_sm.enter_location("party_house", false)
		_reset(Vector3(-5.6, 0.25, 6.4))
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait(15):
			return false
		_rig.request_jump()
		Input.action_press("move_left")
		_t_state = 2
		return false
	if not _wait(35):
		return false
	_release()
	_check(_rig.global_position.x > -6.45, "J04 跳跃仍受墙体碰撞约束",
			"x=%.3f" % _rig.global_position.x)
	_check(_rig.is_on_floor(), "J04 撞墙后仍能落地")
	return true


func step_run_speed() -> bool:
	if _t_state == 0:
		_reset()
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait(15):
			return false
		_measure_start = _rig.global_position
		_measure_frames = Engine.get_physics_frames()
		Input.action_press("move_forward")
		_t_state = 2
		return false
	if _t_state == 2:
		if not _wait(20):
			return false
		_walk_distance = Vector2(_rig.global_position.x - _measure_start.x,
				_rig.global_position.z - _measure_start.z).length()
		_release()
		_reset()
		_t_state = 3
		return false
	if _t_state == 3:
		if not _wait(15):
			return false
		_measure_start = _rig.global_position
		Input.action_press("move_forward")
		Input.action_press("run")
		_t_state = 4
		return false
	if not _wait(20):
		return false
	_run_distance = Vector2(_rig.global_position.x - _measure_start.x,
			_rig.global_position.z - _measure_start.z).length()
	_release()
	_check(_walk_distance > 0.5, "J05 普通行走产生位移", "walk=%.2f" % _walk_distance)
	_check(_run_distance > _walk_distance * 1.3, "J05 Shift 明显提高移动速度",
			"walk=%.2f run=%.2f" % [_walk_distance, _run_distance])
	return true


func step_release_stop() -> bool:
	if not _wait(4):
		return false
	_check(Vector2(_rig.velocity.x, _rig.velocity.z).length() < 0.05,
			"J06 松开 WASD/Shift 后立即停止",
			"speed=%.3f" % Vector2(_rig.velocity.x, _rig.velocity.z).length())
	_check(_rig.movement_state in ["idle", "landing"], "J06 停止后状态为 idle", _rig.movement_state)
	return true


func step_switch_resets() -> bool:
	if _t_state == 0:
		_rig.request_jump()
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait(3):
			return false
		_sm.enter_location("house_exterior", false)
		_t_state = 2
		return false
	if not _wait(12):
		return false
	_check(_sm.get_current_location_id() == "house_exterior", "J07 跳跃中可正常切换地点")
	_check(_rig.movement_state != "jumping", "J07 切场景不残留跳跃状态", _rig.movement_state)
	_check(_rig.global_position.y > -1.0, "J07 切场景后没有掉出地图", "y=%.3f" % _rig.global_position.y)
	return true


func step_look_during_jump() -> bool:
	if _t_state == 0:
		_sm.enter_location("party_house", false)
		_reset()
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait(15):
			return false
		_rig.capture_mouse()
		_rig.request_jump()
		var before: float = _rig.yaw
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(120, -10000)
		_rig._input(motion)
		_t_state = 2
		return false
	if not _wait(4):
		return false
	_check(absf(_rig.yaw) > 0.01, "J08 跳跃中水平视角正常")
	_check(_rig.pitch >= -PlayerController.MAX_PITCH_RADIANS - 0.001,
			"J08 跳跃中垂直限位仍有效", "pitch=%.3f" % _rig.pitch)
	return true


func step_cleanup() -> bool:
	_release()
	if _services != null and _services.save_manager != null:
		_services.save_manager.delete_save()
	return true


func step_report() -> bool:
	for line in _results:
		print(line)
	print("=== JUMP RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true
