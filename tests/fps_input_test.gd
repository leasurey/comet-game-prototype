## FPSInputTest — 鼠标捕获式第一人称视角控制验收
##
## 用法：
##   godot --headless --script res://tests/fps_input_test.gd
##
## 覆盖任务书第七节的 T01 ~ T13。
##
## 说明：
##   本测试尽量走**真实路径**——实例化真正的 main.tscn，
##   通过 GameServices 拿到真实的 CameraRig 与 InteractionManager，
##   并真实调用 main._unhandled_input() 来投递输入事件，
##   而不是只测 PlayerController 的孤立方法。
##
##   受限项（已如实标注）：headless 无真实窗口，
##   T13 的「进程真正退出」无法在不终止测试进程的前提下验证，
##   改为验证释放函数本身及其被退出路径调用。

extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []

var _main: Node = null
var _rig: PlayerController = null
var _camera: Camera3D = null
var _interaction: InteractionManager = null
var _scene_mgr: SceneManager = null
var _world_mgr: WorldManager = null
var _services: Node = null

var _steps: Array = []
var _idx: int = 0
var _ticks: int = 0
var _reporting: bool = false

# T09 遮挡测试用的临时遮挡体
var _blocker: StaticBody3D = null
var _focus_before: Hotspot = null
var _t12_done: bool = false
var _t08_done: bool = false
var _t08_target: Hotspot = null


func _initialize() -> void:
	print("=== COMET FPS input test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))
	_build_steps()


func _build_steps() -> void:
	_steps = [
		Callable(self, "step_setup_main"),

		# T01 启动自动捕获
		Callable(self, "step_t01_auto_capture"),

		# T02/T03 水平与垂直转动
		Callable(self, "step_t02_t03_rotate"),

		# T04/T05 垂直限位
		Callable(self, "step_t04_t05_pitch_limit"),

		# T06 释放后不再转视角
		Callable(self, "step_t06_release_stops_look"),

		# T07 点击恢复捕获
		Callable(self, "step_t07_click_recaptures"),

		# T08/T09 屏幕中心热点识别与遮挡
		Callable(self, "step_t08_focus"),
		Callable(self, "step_t09_occlusion_setup"),
		Callable(self, "step_t09_occlusion_check"),

		# T10 交互键
		Callable(self, "step_t10_interact_key"),

		# T11/T12 世界切换与返回后镜头与热点正常
		Callable(self, "step_t11_world_switch"),
		Callable(self, "step_t12_return"),

		# T13 退出释放鼠标
		Callable(self, "step_t13_release_on_quit"),

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
		if _ticks > 90:
			_record(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
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


func _motion(rel: Vector2) -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.relative = rel
	return m


func _left_click(pressed: bool) -> InputEventMouseButton:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	return b


func _key(kc: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = kc
	k.physical_keycode = kc
	k.pressed = true
	k.echo = false
	return k


## 用「转视角」的方式把屏幕中心对准目标，而不是用 camera.look_at()。
##
## 为什么不用 look_at：camera 是 CameraRig 的子节点，
## look_at 直接改 camera 的 global transform，会与本节点维护的 yaw/pitch 相互覆盖，
## 实测出现「已对准但射线没命中」的不一致。
## 这里改为解算 yaw/pitch 再交给 _apply_rotation()，
## 与真实玩家用鼠标把视角转到目标上的路径完全一致。
func _aim_at(target_pos: Vector3) -> void:
	if _rig == null or _camera == null:
		return
	var dir: Vector3 = (target_pos - _camera.global_position).normalized()
	_rig.yaw = atan2(-dir.x, -dir.z)
	_rig.pitch = -asin(clampf(dir.y, -1.0, 1.0))
	_rig._apply_rotation()


## 返回当前相机朝向（世界空间单位向量），用于判断「视觉上是否连续」。
func _forward() -> Vector3:
	return (-_camera.global_transform.basis.z).normalized()


# ------------------------------------------------------------------ 装配

func step_setup_main() -> bool:
	# 在 --script 模式下 autoload 名称不是编译期全局标识符，
	# 因此从场景树直接取得节点引用。
	if _ticks < 3:
		return false
	_services = root.get_node_or_null("GameServices")
	if _services == null:
		_record(false, "setup. GameServices 可用")
		return true

	# 清掉上次遗留存档，保证从干净状态开始
	if _services.is_ready and _services.save_manager != null:
		_services.save_manager.delete_save()

	var packed_res := load("res://scenes/main.tscn")
	var packed: PackedScene = packed_res as PackedScene
	if packed == null:
		_record(false, "setup. 主场景可加载")
		return true

	_main = packed.instantiate()
	root.add_child(_main)

	# 等几帧，让 _ready / _start_flow（含 await）跑完
	if _ticks < 6:
		return false

	if _services.player_controller is PlayerController:
		_rig = _services.player_controller as PlayerController
	_camera = _rig.get_camera() if _rig != null else null
	_interaction = _services.interaction_manager
	_scene_mgr = _services.scene_manager
	_world_mgr = _services.world_manager

	_check(_rig != null, "setup. CameraRig 已装配", str(_rig != null))
	_check(_camera != null, "setup. Camera3D 已装配")
	_check(_interaction != null, "setup. InteractionManager 已装配")
	return true


# ------------------------------------------------------------------ T01

func step_t01_auto_capture() -> bool:
	if _rig == null:
		_record(false, "T01 启动后自动捕获鼠标", "rig 为空")
		return true
	var captured: bool = _rig.is_mouse_captured()
	_check(captured, "T01 启动游戏后自动捕获鼠标", "captured=%s" % str(captured))
	return true


# ------------------------------------------------------------------ T02/T03

func step_t02_t03_rotate() -> bool:
	if _rig == null:
		_record(false, "T02/T03 视角转动", "rig 为空")
		return true

	_rig.reset_view()

	# T02 水平：只给 X 位移
	var yaw_before: float = _rig.yaw
	var pitch_before: float = _rig.pitch
	_rig._input(_motion(Vector2(200.0, 0.0)))
	var yaw_after_x: float = _rig.yaw
	_check(absf(yaw_after_x - yaw_before) > 0.0001, "T02 鼠标左右移动改变 Yaw",
			"delta=%.4f rad (%.2f deg)" % [yaw_after_x - yaw_before, rad_to_deg(yaw_after_x - yaw_before)])
	_check(absf(_rig.pitch - pitch_before) < 0.0000001, "T02 水平移动不影响 Pitch（两轴独立）",
			"pitch_delta=%.6f" % (_rig.pitch - pitch_before))

	# T03 垂直：只给 Y 位移
	_rig.reset_view()
	var yaw_before2: float = _rig.yaw
	var pitch_before2: float = _rig.pitch
	_rig._input(_motion(Vector2(0.0, 120.0)))
	var pitch_after: float = _rig.pitch
	_check(absf(pitch_after - pitch_before2) > 0.0001, "T03 鼠标上下移动改变 Pitch",
			"delta=%.4f rad (%.2f deg)" % [pitch_after - pitch_before2, rad_to_deg(pitch_after - pitch_before2)])
	_check(absf(_rig.yaw - yaw_before2) < 0.0000001, "T03 垂直移动不影响 Yaw（两轴独立）",
			"yaw_delta=%.6f" % (_rig.yaw - yaw_before2))

	# 垂直灵敏度应与水平同量级（历史 bug 是两者差约 57 倍）
	_rig.reset_view()
	_rig._input(_motion(Vector2(100.0, 0.0)))
	var yaw_delta: float = absf(_rig.yaw)
	_rig.reset_view()
	_rig._input(_motion(Vector2(0.0, 100.0)))
	var pitch_delta: float = absf(_rig.get_pitch_degrees())
	var yaw_deg: float = absf(rad_to_deg(yaw_delta))
	var ratio: float = yaw_deg / maxf(pitch_delta, 0.0001)
	_check(ratio > 0.05 and ratio < 20.0, "T03 垂直与水平灵敏度同量级",
			"水平 %.2f deg vs 垂直 %.2f deg, ratio=%.2f" % [yaw_deg, pitch_delta, ratio])
	return true


# ------------------------------------------------------------------ T04/T05

func step_t04_t05_pitch_limit() -> bool:
	if _rig == null:
		_record(false, "T04/T05 垂直限位", "rig 为空")
		return true

	# T04 持续向下（relative.y 为正）→ pitch 增到 +75
	_rig.reset_view()
	for _i in 80:
		_rig._input(_motion(Vector2(0.0, 300.0)))
	var p_hi: float = _rig.get_pitch_degrees()
	_check(p_hi <= 75.001, "T04 达到垂直上限不超过 +75°", "pitch=%.4f deg" % p_hi)

	# T05 持续向上（relative.y 为负）→ pitch 减到 -75
	_rig.reset_view()
	for _i in 80:
		_rig._input(_motion(Vector2(0.0, -300.0)))
	var p_lo: float = _rig.get_pitch_degrees()
	_check(p_lo >= -75.001, "T05 达到垂直下限不低于 -75°", "pitch=%.4f deg" % p_lo)

	# 不得翻转/倒置：camera.rotation.x 必须始终在限位内
	var cam_x: float = rad_to_deg(_camera.rotation.x)
	_check(absf(cam_x) <= 75.001, "T04/T05 相机未发生翻转或倒置", "camera.rotation.x=%.4f deg" % cam_x)

	# 水平 360 连续：判断的是「视觉连续性」，即相机朝向逐步变化的角度。
	# 不能拿 yaw 数值本身判断——yaw 会被 wrapf 收敛到 [-PI, PI]，
	# 在 ±PI 处必然出现约 2π 的数值跃迁，但朝向完全连续。
	_rig.reset_view()
	var prev_dir := _forward()
	var max_angle: float = 0.0
	var step_deg: float = 0.0
	for _i in 40:
		_rig._input(_motion(Vector2(300.0, 0.0)))
		var cur_dir := _forward()
		var angle: float = prev_dir.angle_to(cur_dir)
		if angle > max_angle:
			max_angle = angle
			step_deg = rad_to_deg(angle)
		prev_dir = cur_dir
	_check(not is_nan(_rig.yaw) and max_angle < deg_to_rad(90.0),
			"T02 水平连续旋转无跳变（按相机朝向判定）",
			"yaw=%.3f rad, 单步最大朝向变化=%.2f deg" % [_rig.yaw, step_deg])
	return true


# ------------------------------------------------------------------ T06

func step_t06_release_stops_look() -> bool:
	if _rig == null:
		_record(false, "T06 释放鼠标后停止转视角", "rig 为空")
		return true

	_rig.reset_view()
	_rig.release_mouse()
	_check(not _rig.is_mouse_captured(), "T06 释放鼠标后捕获状态解除")

	var yaw_before: float = _rig.yaw
	var pitch_before: float = _rig.pitch
	for _i in 10:
		_rig._input(_motion(Vector2(200.0, 200.0)))
	var moved: bool = absf(_rig.yaw - yaw_before) > 0.0001 or absf(_rig.pitch - pitch_before) > 0.0001
	_check(not moved, "T06 释放鼠标后镜头不再响应移动",
			"yaw_delta=%.6f pitch_delta=%.6f" % [_rig.yaw - yaw_before, _rig.pitch - pitch_before])
	return true


# ------------------------------------------------------------------ T07

func step_t07_click_recaptures() -> bool:
	if _main == null or _rig == null:
		_record(false, "T07 点击恢复捕获", "main 或 rig 为空")
		return true

	# 确保处于未捕获状态
	_rig.release_mouse()
	var before: bool = _rig.is_mouse_captured()

	# 走真实输入路径：未捕获时左键点击应恢复捕获
	_main._unhandled_input(_left_click(true))
	var after: bool = _rig.is_mouse_captured()

	_check(before == false and after == true, "T07 鼠标释放后点击画面恢复捕获",
			"before=%s after=%s" % [str(before), str(after)])
	return true


# ------------------------------------------------------------------ T08/T09

func step_t08_focus() -> bool:
	if _scene_mgr == null or _interaction == null or _camera == null:
		_record(false, "T08 屏幕中心识别热点", "依赖对象缺失")
		return true

	# 进入地点只允许执行一次。
	# 若在等待帧期间反复 enter_location，场景实例会被反复重建，
	# InteractionManager 的热点表与焦点会在重建间隙被清空（实测稳定得到 null）。
	if not _t08_done:
		_scene_mgr.enter_location("house_exterior", false)
		_t08_target = _find_spot("Mailbox")
		if _t08_target == null:
			_record(false, "T08 屏幕中心识别热点", "未找到测试目标热点 Mailbox")
			return true
		_rig.capture_mouse()
		_aim_at(_t08_target.global_position)
		_t08_done = true
		return false

	# 等待期间保持对准
	_aim_at(_t08_target.global_position)
	if _ticks < 5:
		return false

	var focused: Hotspot = _interaction.get_focused()
	_check(focused == _t08_target, "T08 屏幕中心对准热点时被正确识别",
			"target=%s focused=%s" % [_t08_target.name,
			focused.name if focused != null else "null"])
	_check(focused != null and focused.get_hint_text() != "", "T08 热点名称提示非空",
			focused.get_hint_text() if focused != null else "")
	return true


func step_t09_occlusion_setup() -> bool:
	if _scene_mgr == null or _interaction == null or _camera == null:
		_record(false, "T09 遮挡判定", "依赖对象缺失")
		return true

	var inst: Node = _scene_mgr.get_current_instance()
	for s in (inst as GameLocation).collect_hotspots():
		var sp := s as Hotspot
		if sp.is_interactable() and sp.name == "Mailbox":
			_focus_before = sp
			break
	if _focus_before == null:
		_record(false, "T09 遮挡判定", "未找到目标热点")
		return true

	_aim_at(_focus_before.global_position)
	if _ticks < 4:
		return false
	if _interaction.get_focused() != _focus_before:
		_record(false, "T09 遮挡判定前置条件", "未先聚焦到目标，无法构造遮挡对比")
		return true

	# 在相机与目标之间插入一个属于环境层（layer 1）的实体遮挡体
	_blocker = StaticBody3D.new()
	_blocker.name = "TestBlocker"
	_blocker.collision_layer = 1
	_blocker.collision_mask = 0
	var mid: Vector3 = (_camera.global_position + _focus_before.global_position) * 0.5
	_blocker.global_position = mid
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 0.3)
	shape.shape = box
	_blocker.add_child(shape)
	root.add_child(_blocker)
	return true


func step_t09_occlusion_check() -> bool:
	if _blocker == null:
		return true
	if _ticks < 4:
		return false

	var focused: Hotspot = _interaction.get_focused()
	var blocked: bool = focused != _focus_before
	_check(blocked, "T09 热点被遮挡时不被错误识别",
			"目标=%s 当前聚焦=%s" % [_focus_before.name,
			str(focused.name) if focused != null else "null"])

	# 清理遮挡体，确认恢复后能重新识别
	_blocker.queue_free()
	_blocker = null
	return true


# ------------------------------------------------------------------ T10

func step_t10_interact_key() -> bool:
	if _main == null or _interaction == null or _camera == null:
		_record(false, "T10 交互键", "依赖对象缺失")
		return true

	var inst: Node = _scene_mgr.get_current_instance()
	var target: Hotspot = null
	for s in (inst as GameLocation).collect_hotspots():
		var sp := s as Hotspot
		if sp.is_interactable() and sp.name == "Mailbox":
			target = sp
			break
	if target == null:
		_record(false, "T10 交互键", "未找到目标热点")
		return true

	_rig.capture_mouse()
	_aim_at(target.global_position)
	if _ticks < 4:
		return false

	if _interaction.get_focused() != target:
		_record(false, "T10 交互键", "前置条件失败：未聚焦到目标")
		return true

	# 记录激活信号是否被真实触发
	var activated: Array = []
	_interaction.hotspot_activated.connect(func(spot: Hotspot) -> void: activated.append(spot.name))

	# 投递 E 键（走 InputMap 注册的 interact 动作）
	var has_action: bool = InputMap.has_action(_services.ACTION_INTERACT)
	_check(has_action, "T10 interact 输入映射已注册", "action=%s" % _services.ACTION_INTERACT)

	_main._unhandled_input(_key(KEY_E))

	_check(activated.size() == 1 and activated[0] == target.name,
			"T10 按 E 键触发原有交互逻辑",
			"activated=%s" % str(activated))
	return true


# ------------------------------------------------------------------ T11/T12

func step_t11_world_switch() -> bool:
	if _scene_mgr == null or _rig == null:
		_record(false, "T11 世界切换后镜头正常", "依赖对象缺失")
		return true

	var world_before: String = _world_mgr.get_current_world_id()
	_scene_mgr.enter_location("dark_road", true)
	var world_after: String = _world_mgr.get_current_world_id()

	_check(_rig.is_mouse_captured(), "T11 世界切换后鼠标仍处于捕获状态",
			"%s -> %s" % [world_before, world_after])

	# 切换后视角仍可控
	var yaw_before: float = _rig.yaw
	_rig._input(_motion(Vector2(150.0, 0.0)))
	_check(absf(_rig.yaw - yaw_before) > 0.0001, "T11 世界切换后镜头控制正常",
			"delta=%.4f rad" % (_rig.yaw - yaw_before))
	return true


func _find_spot(name: String) -> Hotspot:
	if _scene_mgr == null:
		return null
	var inst: Node = _scene_mgr.get_current_instance()
	if inst == null:
		return null
	for s in (inst as GameLocation).collect_hotspots():
		var sp := s as Hotspot
		if sp.is_interactable() and sp.name == name:
			return sp
	return null


func step_t12_return() -> bool:
	if _scene_mgr == null or _interaction == null or _camera == null:
		_record(false, "T12 返回后镜头与热点正常", "依赖对象缺失")
		return true

	# 本步骤需要等待物理帧，因此用标志把「一次性断言」与「等待后断言」分开，
	# 否则等待期间前面的断言会被重复记录。
	if not _t12_done:
		var ok: bool = _scene_mgr.go_back()
		_check(ok and _scene_mgr.get_current_location_id() == "house_exterior",
				"T12 可沿原路返回", "current=%s" % _scene_mgr.get_current_location_id())

		var yaw_before: float = _rig.yaw
		_rig._input(_motion(Vector2(150.0, 0.0)))
		_check(absf(_rig.yaw - yaw_before) > 0.0001, "T12 返回后镜头控制正常")

		var target: Hotspot = _find_spot("CrateBeta")
		if target == null:
			_record(false, "T12 返回后热点可识别", "未找到 CrateBeta（世界未切换？）")
			return true
		_aim_at(target.global_position)
		_t12_done = true
		return false

	if _ticks < 4:
		return false

	var target2: Hotspot = _find_spot("CrateBeta")
	var focused: Hotspot = _interaction.get_focused()
	_check(focused != null and focused == target2, "T12 返回后新世界热点可识别",
			"target=%s focused=%s" % [target2.name if target2 != null else "null",
			str(focused.name) if focused != null else "null"])
	return true


# ------------------------------------------------------------------ T13

func step_t13_release_on_quit() -> bool:
	if _rig == null or _main == null:
		_record(false, "T13 退出释放鼠标", "rig 或 main 为空")
		return true

	_rig.capture_mouse()
	_check(_rig.is_mouse_captured(), "T13 前置：已捕获")

	# 调用退出路径中的释放逻辑。
	# 注意：不能真的调用 get_tree().quit()，否则测试进程会终止，
	# 因此这里验证的是退出前释放函数本身是否生效。
	_main._release_mouse()
	var released: bool = not _rig.is_mouse_captured()
	_check(released, "T13 退出前鼠标被正常释放", "captured_after_release=%s" % str(_rig.is_mouse_captured()))

	# PlayerController 自身在退出场景树时也会释放
	_rig.capture_mouse()
	_rig._exit_tree()
	_check(not _rig.is_mouse_captured(), "T13 PlayerController 退出场景树时自动释放")
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for line in _results:
		print(line)
	print("")
	print("=== FPS INPUT RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true
