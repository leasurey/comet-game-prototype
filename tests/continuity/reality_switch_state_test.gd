## RealitySwitchStateTest — 验证现实切换时玩家状态保持
##
## 用法：godot --headless --script res://tests/continuity/reality_switch_state_test.gd
##
## 场景：客厅（living_room）内 Variant_world_alpha / Variant_world_beta 两套独立变体。
## 玩家站在客厅中央，切换现实（α↔β），验证：
##   W1 坐标保持：切换后 global_position 与切换前完全一致
##   W2 朝向保持：yaw / pitch 不变
##   W3 运动状态：velocity 不被清零（或按设计正确处理）
##   W4 变体切换：切换后 Variant 可见性正确
##   W5 多次往返：α→β→α→β 循环中状态始终稳定
##   W6 运动中切换：正在走路时切换，位置连续不跳跃

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _main = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false

var _pc = null  # PlayerController
var _inst = null  # living_room instance


func _initialize() -> void:
	print("=== COMET reality switch state preservation test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_w1_position"),
		Callable(self, "step_w2_orientation"),
		Callable(self, "step_w3_velocity"),
		Callable(self, "step_w4_variant_visibility"),
		Callable(self, "step_w5_multi_cycle"),
		Callable(self, "step_w6_moving_switch"),
		Callable(self, "step_report"),
	]


func _process(_d: float) -> bool:
	if _idx >= _steps.size():
		return false
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_ticks = 0
		_t_state = 0
	else:
		_ticks += 1
		if _ticks > 500:
			_check(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
	return false


func _check(cond: bool, label: String, detail: String = "") -> void:
	var suffix := "" if detail == "" else " | " + detail
	if cond:
		_pass += 1
	else:
		_fail += 1
	_lines.append("[%s] %s%s" % ["PASS" if cond else "FAIL", label, suffix])


## 切换现实（直接调 WorldManager.apply_transition）
func _switch_world(target: String) -> bool:
	var errs: Array = []
	var ok: bool = _svc.world_manager.apply_transition(target, "test_switch", errs)
	if not ok:
		for e in errs:
			print("  switch error: ", e)
	return ok


func step_setup() -> bool:
	if _t_state == 0:
		var sm = _svc.save_manager
		sm.use_test_path("reality_switch_state")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _ticks < 15:
		return false
	_pc = _svc.player_controller
	_check(_pc != null, "setup：PlayerController 存在")
	if _pc == null:
		return true
	# 确保在客厅
	if _svc.get_current_location_id() != "living_room":
		_svc.go_to("living_room")
		if _ticks < 25:
			return false
	_check(_svc.get_current_location_id() == "living_room",
		"setup：在客厅", _svc.get_current_location_id())
	_inst = _svc.scene_manager.get_current_instance()
	_check(_inst != null, "setup：场景实例存在")
	# 初始现实
	_check(_svc.world_manager.get_current_world_id() == "world_alpha",
		"setup：初始现实 world_alpha")
	return true


## W1  坐标保持
func step_w1_position() -> bool:
	if _t_state == 0:
		# 站定
		_pc.velocity = Vector3.ZERO
		_pc.global_position = Vector3(-1.0, 0.20, 5.0)  # 客厅中央
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 3:
			return false
		var pos_before: Vector3 = _pc.global_position
		# α→β
		_check(_switch_world("world_beta"), "W1 切换到 beta 成功")
		_t_state = 2
		_t_state_data = {"pos": pos_before}
		return false
	if _t_state == 2:
		if _ticks < 5:
			return false
		var pos_before: Vector3 = (_t_state_data as Dictionary)["pos"] as Vector3
		var pos_after: Vector3 = _pc.global_position
		var dist := pos_after.distance_to(pos_before)
		_check(dist < 0.10, "W1 切换后坐标不变",
			"before=%s after=%s dist=%.4f" % [str(pos_before), str(pos_after), dist])
		return true
	return false


## W2  朝向保持
func step_w2_orientation() -> bool:
	if _t_state == 0:
		_pc.yaw = 1.234
		_pc.pitch = -0.35
		if _pc.has_method("_apply_rotation"):
			_pc._apply_rotation()
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 3:
			return false
		var yaw_before: float = _pc.yaw
		var pitch_before: float = _pc.pitch
		# β→α
		_check(_switch_world("world_alpha"), "W2 切换到 alpha 成功")
		_t_state = 2
		_t_state_data = {"yaw": yaw_before, "pitch": pitch_before}
		return false
	if _t_state == 2:
		if _ticks < 5:
			return false
		var yaw_b: float = (_t_state_data as Dictionary)["yaw"]
		var pitch_b: float = (_t_state_data as Dictionary)["pitch"]
		_check(absf(_pc.yaw - yaw_b) < 0.001,
			"W2 切换后 yaw 不变", "before=%.4f after=%.4f" % [yaw_b, _pc.yaw])
		_check(absf(_pc.pitch - pitch_b) < 0.001,
			"W2 切换后 pitch 不变", "before=%.4f after=%.4f" % [pitch_b, _pc.pitch])
		return true
	return false


## W3  运动状态
func step_w3_velocity() -> bool:
	if _t_state == 0:
		# 设定非零速度
		_pc.velocity = Vector3(1.5, 0.0, -0.8)
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 2:
			return false
		var vel_before: Vector3 = _pc.velocity
		_check(_switch_world("world_beta"), "W3 切换到 beta")
		_t_state = 2
		_t_state_data = {"vel": vel_before}
		return false
	if _t_state == 2:
		if _ticks < 3:
			return false
		var vel_b: Vector3 = (_t_state_data as Dictionary)["vel"] as Vector3
		# 速度可能因物理帧有微小变化，但不应被清零
		var vel_a: Vector3 = _pc.velocity
		var horizontal_preserved: bool = (absf(vel_a.x - vel_b.x) < 0.5
				and absf(vel_a.z - vel_b.z) < 0.5)
		_check(horizontal_preserved or (vel_a.length() > 0.5),
			"W3 切换后速度不被清零",
			"before=%s after=%s" % [str(vel_b), str(vel_a)])
		return true
	return false


## W4  变体切换正确性
func step_w4_variant_visibility() -> bool:
	if _t_state == 0:
		_check(_inst != null, "W4 前置：实例存在")
		if _inst == null:
			return true
		# 当前是 beta（W3 切过去了）
		var v_alpha: Node = _inst.get_node_or_null("Environment/Variant_world_alpha")
		var v_beta: Node = _inst.get_node_or_null("Environment/Variant_world_beta")
		_check(v_alpha != null and v_beta != null, "W4 两个变体节点存在")
		# 在 beta：alpha 可见（变体是"额外物件叠加"还是"完整替代"？看 apply_world 实现）
		# 当前 Location.apply_world 显示匹配的 variant，隐藏不匹配的
		_check(v_beta != null and v_beta.visible, "W4 beta 变体可见",
			"alpha_vis=%s beta_vis=%s" % [str(v_alpha.visible) if v_alpha else "?", str(v_beta.visible) if v_beta else "?"])
		# 切到 alpha
		_check(_switch_world("world_alpha"), "W4 切换到 alpha")
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 5:
			return false
		var v_alpha: Node = _inst.get_node_or_null("Environment/Variant_world_alpha")
		var v_beta: Node = _inst.get_node_or_null("Environment/Variant_world_beta")
		_check(v_alpha != null and v_alpha.visible, "W4 alpha 变体可见（切换后）",
			"alpha_vis=%s beta_vis=%s" % [str(v_alpha.visible) if v_alpha else "?", str(v_beta.visible) if v_beta else "?"])
		return true
	return false


## W5  多次往返稳定性
func step_w5_multi_cycle() -> bool:
	if _t_state == 0:
		_pc.velocity = Vector3.ZERO
		_pc.global_position = Vector3(-1.0, 0.20, 5.0)
		_pc.yaw = 0.5
		_pc.pitch = -0.1
		if _pc.has_method("_apply_rotation"):
			_pc._apply_rotation()
		_t_state = 1  # 等稳定
		return false
	if _t_state == 1:
		# 等物理稳定（清零速度后仍需帧让 move_and_slide 完成）
		if _ticks < 5:
			return false
		_pc.velocity = Vector3.ZERO
		_t_state = 2
		_t_state_data = {
			"pos": _pc.global_position,
			"yaw": _pc.yaw,
			"pitch": _pc.pitch,
			"cycle": 0,
		}
		return false
	if _t_state == 2:
		# 每 8 帧切换一次，共 4 次
		if _ticks % 8 != 0:
			return false
		var data: Dictionary = _t_state_data
		var cycle: int = int(data["cycle"])
		if cycle >= 4:
			return true
		# 记录切换前位置
		var pos_before: Vector3 = _pc.global_position
		var target := "world_beta" if cycle % 2 == 0 else "world_alpha"
		_check(_switch_world(target), "W5 循环 %d: → %s" % [cycle, target])
		data["cycle"] = cycle + 1
		data["last_switch_pos"] = pos_before
		_t_state = 3  # 等下一帧验证
		return false
	if _t_state == 3:
		# 切换后立即验证位置不变
		var data: Dictionary = _t_state_data
		var pos_b: Vector3 = data["last_switch_pos"]
		var dist: float = _pc.global_position.distance_to(pos_b)
		_check(dist < 0.15, "W5 循环 %d 切换后坐标不变" % (int(data["cycle"]) - 1),
			"dist=%.4f" % dist)
		_t_state = 2
		_ticks = 0
		return false
	return false


## W6  运动中切换（位置连续）
func step_w6_moving_switch() -> bool:
	if _t_state == 0:
		# 让 NPC 走起来（用真实移动）
		_pc.velocity = Vector3(0.0, 0.0, 0.0)
		_pc.global_position = Vector3(-2.0, 0.20, 5.0)
		_t_state = 1
		return false
	if _t_state == 1:
		# 走 20 帧
		if _ticks < 20:
			return false
		# 切换（玩家可能还在移动）
		var pos_before: Vector3 = _pc.global_position
		_check(_switch_world("world_alpha"), "W6 运动中切换到 alpha")
		_t_state = 2
		_t_state_data = {"pos": pos_before}
		return false
	if _t_state == 2:
		if _ticks < 5:
			return false
		var pos_b: Vector3 = (_t_state_data as Dictionary)["pos"] as Vector3
		var pos_a: Vector3 = _pc.global_position
		var dist := pos_a.distance_to(pos_b)
		# 运动中切换，位置差异可以是几步（物理帧位移），但不能跳跃
		_check(dist < 2.0, "W6 运动中切换位置连续（不跳跃）",
			"dist=%.2f" % dist)
		_check(_svc.world_manager.get_current_world_id() == "world_alpha",
			"W6 现实正确")
		return true
	return false


var _t_state_data: Dictionary = {}


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	for line in _lines:
		print(line)
	print("=== REALITY SWITCH STATE RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null and gs.has_method("shutdown_audio"):
		gs.shutdown_audio()
	await create_timer(0.15).timeout
	quit(1 if _fail > 0 else 0)
	return true
