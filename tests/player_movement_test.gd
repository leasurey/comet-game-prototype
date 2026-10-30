## PlayerMovementTest — WASD 地面移动验收
##
## 用法：
##   godot --headless --script res://tests/player_movement_test.gd
##
## 覆盖任务书第五节的 T01 ~ T16。
##
## 关键做法：
##   1. 使用真实的 main.tscn 实例（含 CharacterBody3D 与碰撞胶囊），
##      而不是手工拼一个没有碰撞的假玩家——否则「能不能站在地板上」根本无法验证。
##   2. 按键通过 Input.action_press()/action_release() 注入，
##      走的是真实的 InputMap → Input.get_vector() → 移动 链路，
##      因此 T01~T05 检验的是键盘映射本身，不只是内部函数。
##   3. 等待使用物理帧计数（Engine.get_physics_frames()），
##      而不是 idle 帧，避免物理帧率与渲染帧率不同导致计量失真。

extends SceneTree

const LOC_KEY := "living_room"

var _pass: int = 0
var _fail: int = 0
var _results: Array = []

var _services: Node = null
var _main: Node = null
var _rig: PlayerController = null
var _camera: Camera3D = null
var _interaction: InteractionManager = null
var _scene_mgr: SceneManager = null

var _steps: Array = []
var _idx: int = 0
var _ticks: int = 0
var _reporting: bool = false

# 步骤内部复位用的临时状态
var _t_state: int = 0

# 物理帧等待
var _pf_start: int = 0
var _pf_needed: int = 0

# 各步骤的中途状态
var _started: bool = false
var _start_pos := Vector3.ZERO
var _mid_pos := Vector3.ZERO
var _t08_start := Vector3.ZERO
var _y_sample1: float = 0.0


func _initialize() -> void:
	print("=== COMET player movement test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))
	print("physics ticks/s: %d" % Engine.physics_ticks_per_second)
	_build_steps()


func _build_steps() -> void:
	_steps = [
		Callable(self, "step_setup"),

		Callable(self, "step_t01_forward"),
		Callable(self, "step_t02_back"),
		Callable(self, "step_t03_strafe"),
		Callable(self, "step_t04_diagonal"),
		Callable(self, "step_t05_diagonal_speed"),
		Callable(self, "step_t06_yaw_changes_direction"),
		Callable(self, "step_t07_pitch_does_not_affect_plane"),
		Callable(self, "step_t08_release_stops"),
		Callable(self, "step_t09_delta_independent"),
		Callable(self, "step_t10_stand_on_floor"),
		Callable(self, "step_t11_wall_blocks"),
		Callable(self, "step_t12_furniture_blocks"),
		Callable(self, "step_t13_after_switch"),
		Callable(self, "step_t14_look_while_moving"),
		Callable(self, "step_t15_raycast_while_moving"),
		Callable(self, "step_t16_after_esc"),

		Callable(self, "step_cleanup"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_pf_needed = 0
		_ticks = 0
	else:
		_ticks += 1
		if _ticks > 900:
			_record(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
			_pf_needed = 0
	return false


func _record(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		_pass += 1
		_results.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_results.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


func _check(cond: bool, label: String, detail: String = "") -> void:
	_record(cond, label, detail)


## 等待指定数量的物理帧。首次调用记录起点，之后每帧比较。
func _wait_physics(frames: int) -> bool:
	if _pf_needed == 0:
		_pf_start = Engine.get_physics_frames()
		_pf_needed = frames
	if Engine.get_physics_frames() - _pf_start < _pf_needed:
		return false
	_pf_needed = 0
	return true


func _reset_player(yaw_deg: float = 0.0) -> void:
	var spawn: Vector3 = _scene_mgr.get_location_spawn(_scene_mgr.get_current_location_id())
	_rig.reset_to_spawn(spawn)
	_rig.velocity = Vector3.ZERO
	_rig.pitch = 0.0
	_rig.yaw = deg_to_rad(yaw_deg)
	_rig._apply_rotation()


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


# ------------------------------------------------------------------ setup

func step_setup() -> bool:
	if _pf_needed == 0 and _started == false:
		if Engine.get_physics_frames() < 3:
			return false
		_services = root.get_node_or_null("GameServices")
		if _services == null:
			_record(false, "setup. GameServices 可用")
			return true

		if _services.is_ready and _services.save_manager != null:
			# 先切到本测试专用存档路径，绝不动玩家的正式存档（P0 / BUG-002）
			_services.save_manager.use_test_path("player_movement")
			_services.save_manager.delete_save()

		var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
		if packed == null:
			_record(false, "setup. 主场景可加载")
			return true
		_main = packed.instantiate()
		root.add_child(_main)
		_started = true
		return false

	if not _wait_physics(6):
		return false

	_rig = _services.player_controller as PlayerController
	_camera = _rig.get_camera() if _rig != null else null
	_interaction = _services.interaction_manager
	_scene_mgr = _services.scene_manager

	_check(_rig != null, "setup. 玩家为 PlayerController(CharacterBody3D)", str(_rig != null))
	_check(_rig is CharacterBody3D, "setup. 玩家具备 CharacterBody3D 物理能力",
			"type=%s" % ("CharacterBody3D" if _rig is CharacterBody3D else "其它"))
	var shape_node := _rig.find_child("Body", true, false)
	_check(shape_node is CollisionShape3D, "setup. 玩家存在碰撞体")
	_check(_camera != null, "setup. 相机已装配")
	_check(absf(_camera.position.y - 1.62) < 0.01, "setup. 观察高度为 1.62",
			"camera.local.y=%.3f" % (_camera.position.y if _camera != null else -1.0))

	# 确认移动动作已注册
	var actions_ok := true
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		if not InputMap.has_action(a):
			actions_ok = false
	_check(actions_ok, "setup. WASD 输入动作已注册")

	# 本测试的撞墙/家具断言绑定的是客厅的实际墙体坐标，
	# 因此必须显式进入客厅，而不是依赖 start_location 的配置值。
	# （v0.3.1 起初始地点改为聚会房屋，若沿用开场地点，T11/T12 会拿客厅的
	#   墙面坐标去判定一个布局完全不同的房间，属于测试前提失效而非功能故障。）
	_scene_mgr.enter_location("living_room", false)
	return true


# ------------------------------------------------------------------ T01/T02

func step_t01_forward() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		_start_pos = _rig.global_position
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if not _wait_physics(10):
		return false
	Input.action_release("move_forward")
	var d: Vector3 = _rig.global_position - _start_pos
	_check(d.z < -0.3, "T01 W 键向前移动（yaw=0 时为 -Z）",
			"delta=(%.3f, %.3f, %.3f)" % [d.x, d.y, d.z])
	_t_state = 0
	return true


func step_t02_back() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		_start_pos = _rig.global_position
		Input.action_press("move_back")
		_t_state = 1
		return false
	if not _wait_physics(10):
		return false
	Input.action_release("move_back")
	var d: Vector3 = _rig.global_position - _start_pos
	_check(d.z > 0.3, "T02 S 键向后移动（+Z）",
			"delta=(%.3f, %.3f, %.3f)" % [d.x, d.y, d.z])
	_t_state = 0
	return true


# ------------------------------------------------------------------ T03

func step_t03_strafe() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		_start_pos = _rig.global_position
		Input.action_press("move_left")
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(10):
			return false
		Input.action_release("move_left")
		var d: Vector3 = _rig.global_position - _start_pos
		_check(d.x < -0.3, "T03 A 键向左移动（-X）",
				"delta=(%.3f, %.3f, %.3f)" % [d.x, d.y, d.z])
		_reset_player(0.0)
		_start_pos = _rig.global_position
		Input.action_press("move_right")
		_t_state = 2
		return false
	if _t_state == 2:
		if not _wait_physics(10):
			return false
		Input.action_release("move_right")
		var d2: Vector3 = _rig.global_position - _start_pos
		_check(d2.x > 0.3, "T03 D 键向右移动（+X）",
				"delta=(%.3f, %.3f, %.3f)" % [d2.x, d2.y, d2.z])
		_t_state = 0
	return true


# ------------------------------------------------------------------ T04/T05

func step_t04_diagonal() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		_start_pos = _rig.global_position
		Input.action_press("move_forward")
		Input.action_press("move_left")
		_t_state = 1
		return false
	if not _wait_physics(10):
		return false
	Input.action_release("move_forward")
	Input.action_release("move_left")
	var d: Vector3 = _rig.global_position - _start_pos
	_check(d.z < -0.2 and d.x < -0.2, "T04 W+A 同时按下可斜向移动",
			"delta=(%.3f, %.3f, %.3f)" % [d.x, d.y, d.z])
	_mid_pos = d
	_t_state = 0
	return true


func step_t05_diagonal_speed() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		_start_pos = _rig.global_position
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(10):
			return false
		Input.action_release("move_forward")
		var single: Vector3 = _rig.global_position - _start_pos
		var single_len: float = _flat(single).length()
		var diag_len: float = _flat(_mid_pos).length()
		var ratio: float = diag_len / maxf(single_len, 0.0001)
		_check(ratio <= 1.06, "T05 斜向速度不超过单方向速度",
				"单向 %.3f m vs 斜向 %.3f m, 比值 %.3f" % [single_len, diag_len, ratio])
		_t_state = 0
	return true


# ------------------------------------------------------------------ T06/T07

func step_t06_yaw_changes_direction() -> bool:
	if _t_state == 0:
		_reset_player(90.0)
		_start_pos = _rig.global_position
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if not _wait_physics(10):
		return false
	Input.action_release("move_forward")
	var d: Vector3 = _rig.global_position - _start_pos
	# yaw=90° 时前方为 -X
	_check(d.x < -0.3 and absf(d.z) < absf(d.x) * 0.5,
			"T06 改变 yaw 后移动方向随之改变（yaw=90° 前进为 -X）",
			"delta=(%.3f, %.3f, %.3f)" % [d.x, d.y, d.z])
	_t_state = 0
	return true


func step_t07_pitch_does_not_affect_plane() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		# 抬头 60°
		_rig.pitch = deg_to_rad(60.0)
		_rig._apply_rotation()
		_start_pos = _rig.global_position
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if not _wait_physics(12):
		return false
	Input.action_release("move_forward")
	var d: Vector3 = _rig.global_position - _start_pos
	# 水平移动应仍在地面平面内：y 变化仅来自贴地修正，应极小；水平距离应与平视时相当
	_check(absf(d.y) < 0.05, "T07 抬头时水平移动仍保持在地面平面内",
			"y 变化=%.4f m" % d.y)
	_check(_flat(d).length() > 0.3, "T07 抬头时水平位移正常",
			"水平位移=%.3f m" % _flat(d).length())
	_t_state = 0
	return true


# ------------------------------------------------------------------ T08

func step_t08_release_stops() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(8):
			return false
		Input.action_release("move_forward")
		_t_state = 2
		return false
	if _t_state == 2:
		if not _wait_physics(3):
			return false
		var v_after: Vector3 = _rig.velocity
		_t08_start = _rig.global_position
		_check(absf(v_after.x) < 0.001 and absf(v_after.z) < 0.001,
				"T08 松开按键后水平速度归零", "velocity=(%.4f, %.4f)" % [v_after.x, v_after.z])
		_t_state = 3
		return false
	if not _wait_physics(8):
		return false
	var drift: float = _flat(_rig.global_position - _t08_start).length()
	_check(drift < 0.02, "T08 松开按键后不再滑行", "漂移=%.4f m" % drift)
	_t_state = 0
	return true


# ------------------------------------------------------------------ T09

func step_t09_delta_independent() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		_start_pos = _rig.global_position
		_pf_start = Engine.get_physics_frames()
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if _t_state == 1:
		var elapsed_frames: int = Engine.get_physics_frames() - _pf_start
		if elapsed_frames < 10:
			return false
		Input.action_release("move_forward")
		var d: Vector3 = _rig.global_position - _start_pos
		var actual: float = _flat(d).length()
		var elapsed_sec: float = float(elapsed_frames) / float(Engine.physics_ticks_per_second)
		var expected: float = _rig.move_speed * elapsed_sec
		var err: float = absf(actual - expected) / maxf(expected, 0.001)
		_check(err < 0.25, "T09 位移符合 speed×delta（与帧率无关）",
				"实测 %.3f m / 理论 %.3f m，误差 %.1f%%（%d 物理帧）" % [
					actual, expected, err * 100.0, elapsed_frames])
		_check(absf(_rig.move_speed - PlayerController.DEFAULT_MOVE_SPEED) < 0.001,
				"T09 移动速度由统一配置常量提供",
				"move_speed=%.2f m/s" % _rig.move_speed)
		_t_state = 0
	return true


# ------------------------------------------------------------------ T10

func step_t10_stand_on_floor() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		_t_state = 1
		return false
	if _t_state == 1:
		# 注意：_wait_physics 成功后会清零计时器，
		# 因此同一步骤内不能连续调用两次，必须分阶段，否则每次都从头计时、永远等不完。
		if not _wait_physics(30):
			return false
		_y_sample1 = _rig.global_position.y
		_t_state = 2
		return false
	if _t_state == 2:
		if not _wait_physics(15):
			return false
		var y2: float = _rig.global_position.y
		var dy: float = absf(_y_sample1 - y2)
		_check(_rig.is_on_floor(), "T10 玩家站在地板上（is_on_floor）")
		_check(dy < 0.005, "T10 玩家不会持续下落",
				"y1=%.4f y2=%.4f delta=%.5f" % [_y_sample1, y2, dy])
		_check(_rig.velocity.y > -0.1, "T10 垂直速度已稳定", "velocity.y=%.4f" % _rig.velocity.y)
		_t_state = 0
	return true


# ------------------------------------------------------------------ T11/T12

func step_t11_wall_blocks() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		Input.action_press("move_right")
		_t_state = 1
		return false
	if not _wait_physics(90):
		return false
	Input.action_release("move_right")
	var x: float = _rig.global_position.x
	# 客厅右墙内表面 x=3.52，胶囊半径 0.32 → 中心不应超过约 3.2。
	# 同时必须验证「确实走到了墙边」：只检查上界会让「根本没动」也判为通过（假阳性）。
	_check(x > 2.80 and x < 3.25, "T11 撞墙时不穿墙（且确实移动到墙边）",
			"起始 x=1.200 → 最终 x=%.3f（墙面 3.52，半径 0.32）" % x)
	_t_state = 0
	return true


func step_t12_furniture_blocks() -> bool:
	if _t_state == 0:
		_reset_player(0.0)
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if not _wait_physics(90):
		return false
	Input.action_release("move_forward")
	var z: float = _rig.global_position.z
	var y: float = _rig.global_position.y
	# 电视柜前面 z=-2.275，玩家半径 0.32 → 中心应停在约 -1.96，
	# 而不是穿过去一直走到后墙 -3.10。同时要求它确实前进了（避免假阳性）。
	_check(z > -2.20 and z < -1.40, "T12 家具等障碍物能够正常阻挡",
			"起始 z=0.800 → 最终 z=%.3f（柜面前沿 -2.275）" % z)
	_check(y < 1.0, "T12 玩家未被挡上家具顶部", "y=%.3f" % y)
	_t_state = 0
	return true


# ------------------------------------------------------------------ T13

func step_t13_after_switch() -> bool:
	if _t_state == 0:
		var ok: bool = _scene_mgr.enter_location("house_exterior", true)
		_check(ok, "T13 可切换到房屋外部")
		# 站到该地点出生点，等落地
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(20):
			return false
		var spawn: Vector3 = _scene_mgr.get_location_spawn("house_exterior")
		var dist: float = _flat(_rig.global_position - spawn).length()
		_check(dist < 0.3, "T13 切换后玩家位于该地点出生点附近", "偏移=%.3f m" % dist)
		_rig.reset_view()
		_start_pos = _rig.global_position
		Input.action_press("move_forward")
		_t_state = 2
		return false
	if _t_state == 2:
		if not _wait_physics(10):
			return false
		Input.action_release("move_forward")
		var d: Vector3 = _rig.global_position - _start_pos
		_check(_flat(d).length() > 0.2, "T13 切换地点后移动功能仍然有效",
				"位移=%.3f m" % _flat(d).length())
		_t_state = 0
	return true


# ------------------------------------------------------------------ T14/T15

func step_t14_look_while_moving() -> bool:
	if _t_state == 0:
		_rig.reset_view()
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(5):
			return false
		var yaw_before: float = _rig.yaw
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(120.0, 0.0)
		_rig._input(motion)
		var changed: bool = absf(_rig.yaw - yaw_before) > 0.0001
		_check(changed, "T14 移动过程中鼠标视角控制正常",
				"yaw delta=%.4f rad" % (_rig.yaw - yaw_before))
		Input.action_release("move_forward")
		_t_state = 0
	return true


func step_t15_raycast_while_moving() -> bool:
	if _t_state == 0:
		if not _wait_physics(6):
			return false
		# 在房屋外部对准 Mailbox 后保持移动键按下，检查射线仍能命中
		var inst: Node = _scene_mgr.get_current_instance()
		var target: Hotspot = null
		for s in (inst as GameLocation).collect_hotspots():
			var sp := s as Hotspot
			if sp.is_interactable() and sp.name == "Mailbox":
				target = sp
				break
		if target == null:
			_record(false, "T15 移动中中心射线交互正常", "未找到 Mailbox")
			return true
		_rig.capture_mouse()
		# 交互距离上限 2.5 m：站到目标前 1.2 m 再测「移动中射线仍能命中」
		_rig.reset_to_spawn(Vector3(target.global_position.x, 0.05,
				target.global_position.z - 1.2))
		var dir: Vector3 = (target.global_position - _camera.global_position).normalized()
		_rig.yaw = atan2(-dir.x, -dir.z)
		_rig.pitch = -asin(clampf(dir.y, -1.0, 1.0))
		_rig._apply_rotation()
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(4):
			return false
		Input.action_release("move_forward")
		var focused: Hotspot = _interaction.get_focused()
		_check(focused != null, "T15 移动中中心射线仍能识别热点",
				"focused=%s" % (focused.name if focused != null else "null"))
		_t_state = 0
	return true


# ------------------------------------------------------------------ T16

func step_t16_after_esc() -> bool:
	if _t_state == 0:
		# ESC 释放鼠标
		_rig.release_mouse()
		_check(not _rig.is_mouse_captured(), "T16 ESC 后鼠标捕获解除")

		# 视角应停止响应
		var yaw_before: float = _rig.yaw
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(200.0, 0.0)
		_rig._input(motion)
		_check(absf(_rig.yaw - yaw_before) < 0.0001, "T16 释放后视角不再响应鼠标",
				"yaw delta=%.5f" % (_rig.yaw - yaw_before))

		# 键盘移动按现有设计仍然有效（移动与鼠标捕获解耦）
		_reset_player(0.0)
		_start_pos = _rig.global_position
		Input.action_press("move_forward")
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_physics(10):
			return false
		Input.action_release("move_forward")
		var d: Vector3 = _rig.global_position - _start_pos
		_check(_flat(d).length() > 0.2, "T16 释放鼠标后键盘移动仍有效（符合设计）",
				"位移=%.3f m" % _flat(d).length())

		# 点击画面应能恢复捕获
		if _main != null:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			_main._unhandled_input(click)
			_check(_rig.is_mouse_captured(), "T16 点击画面恢复鼠标捕获")
		_t_state = 0
	return true


# ------------------------------------------------------------------ 收尾

func step_cleanup() -> bool:
	_release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for line in _results:
		print(line)
	print("")
	print("=== MOVEMENT RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true
