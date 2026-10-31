## ContinuityNpcLifecycleTest — CT-003/004 NPC 生命周期与存档恢复
##
## 用法：godot --headless --script res://tests/continuity/npc_lifecycle_test.gd
##
## N1 NPC 行走到中途，玩家离场再回场：位置/行为/目标连续（会话快照）
## N2 保存→读档：NPC 位置与行走目标恢复（restore 双写快照+活实体）
## N3 旧档（无 target 字段）恢复：walking 状态归一为 idle，不产生僵死状态
## N4 新局清空快照：全员回配置出生点
##
## 修复前：离场即重置（CT-004）；npc_states 写而不读（CT-003）。

extends SceneTree

const FLOOR_Y := 0.20

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _main = null
var _npcm = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false

# N1/N2 采样
var _kevin: NPC = null
var _pos_mid = Vector3.ZERO
var _pos_before_save = Vector3.ZERO


func _initialize() -> void:
	print("=== COMET continuity npc lifecycle test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_n1_leave_reenter"),
		Callable(self, "step_n2_save_restore"),
		Callable(self, "step_n3_legacy_no_target"),
		Callable(self, "step_n4_new_game_resets"),
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


func step_setup() -> bool:
	if _t_state == 0:
		var sm = _svc.save_manager
		sm.use_test_path("npc_lifecycle")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _ticks < 10:
		return false
	_npcm = _svc.npc_manager
	if _t_state == 1:
		if _npcm == null or not _npcm.is_nav_ready():
			if _ticks > 300:
				print("DIAG timeout: bake_phase=", _npcm._bake_phase if _npcm else -1,
					" pf_mark=", _npcm._pf_mark if _npcm else -1,
					" pf=", Engine.get_physics_frames(),
					" polys=", _npcm.get_nav_polygon_count() if _npcm else -1,
					" npcs=", _npcm.get_all_npcs().size() if _npcm else -1,
					" loc=", _svc.get_current_location_id())
				return true
			return false
		_kevin = _npcm.get_npc("kevin")
		_check(_kevin != null, "setup. kevin 已在住宅内生成")
		return true
	return true


func step_n1_leave_reenter() -> bool:
	if _t_state == 0:
		# 真实行走：派目标并等他走到中途。
		# 注意不能派去 kitchen——那是 kevin 自己的出生点（秒到即 idle）。
		var sent: bool = _npcm.send_to_room("kevin", "living")
		_check(sent, "N1 可派发行走目标")
		_t_state = 1
		return false
	if _t_state == 1:
		_kevin = _npcm.get_npc("kevin")
		if _kevin == null:
			_check(false, "N1 前置：kevin 存在")
			return true
		var departed: float = _kevin.global_position.distance_to(Vector3(5.0, FLOOR_Y, 6.5))
		# 轮询取样：等他真正走离出生点再记录，比固定等 N tick 稳
		if departed < 0.35:
			if _ticks > 240:
				_check(false, "N1 前置：kevin 走离出生点",
					"240 tick 内只走了 %.2f m" % departed)
				return true
			return false
		_pos_mid = _kevin.global_position
		_check(_kevin.state == NPC.STATE_WALKING, "N1 前置：kevin 行走中",
			_kevin.state)
		_check(true, "N1 前置：已离开配置出生点",
			"偏移 %.2f m @ %s" % [departed, str(_pos_mid)])
		# 离场（非住宅 → 快照 + 销毁）
		_svc.go_to("house_exterior")
		_t_state = 2
		return false
	if _t_state == 2:
		if _ticks < 6:
			return false
		_check(_npcm.get_all_npcs().is_empty(), "N1 离场后实体已销毁")
		_svc.go_to("party_house")
		_t_state = 3
		return false
	if _t_state == 3:
		if _ticks < 6:
			return false
		_kevin = _npcm.get_npc("kevin")
		if _kevin == null:
			_check(false, "N1 回场后 kevin 重新生成")
			return true
		var d: float = _kevin.global_position.distance_to(_pos_mid)
		_check(d < 0.8, "N1 回场后位置连续（快照恢复）",
			"离场前=%s 回场后=%s 相距=%.2f" % [str(_pos_mid), str(_kevin.global_position), d])
		_check(_kevin.global_position.distance_to(Vector3(5.0, FLOOR_Y, 6.5)) > 0.35,
			"N1 未被重置回配置出生点", str(_kevin.global_position))
		_check(_kevin.has_goal(), "N1 行走目标随快照续接")
		_check(_kevin.state == NPC.STATE_WALKING, "N1 行为状态续接", _kevin.state)
		return true
	return true


func step_n2_save_restore() -> bool:
	if _t_state == 0:
		_pos_before_save = _kevin.global_position
		var ok: bool = _svc.save_game()
		_check(ok, "N2 保存成功（npc_states 含行走目标）")
		# 走远一点再读档，确保恢复真的发生
		_svc.go_to("house_exterior")
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 6:
			return false
		var ok: bool = _svc.continue_game()
		_check(ok, "N2 读档成功")
		_t_state = 2
		return false
	if _t_state == 2:
		if _ticks < 8:
			return false
		_kevin = _npcm.get_npc("kevin")
		if _kevin == null:
			_check(false, "N2 读档后 kevin 存在")
			return true
		var d: float = _kevin.global_position.distance_to(_pos_before_save)
		_check(d < 0.3, "N2 读档后 NPC 位置恢复（CT-003）",
			"存档=%s 恢复=%s 相距=%.2f" % [str(_pos_before_save), str(_kevin.global_position), d])
		return true
	return true


func step_n3_legacy_no_target() -> bool:
	# 旧档条目无 target 字段：walking 应归一 idle，不能留下无目标的行走状态
	var n := NPC.new()
	n.setup("legacy", "Legacy", "hall")
	root.add_child(n)
	n.restore({
		"id": "legacy",
		"position": [1.0, FLOOR_Y, 2.0],
		"rotation_y": 0.5,
		"state": "walking",
	})
	_check(n.state != NPC.STATE_WALKING or n.has_goal(),
		"N3 旧档 walking 无 target 时归一为 idle（不留僵死状态）", n.state)
	_check(n.global_position.distance_to(Vector3(1.0, FLOOR_Y, 2.0)) < 0.05,
		"N3 旧档位置恢复", str(n.global_position))
	n.free()
	return true


func step_n4_new_game_resets() -> bool:
	if _t_state == 0:
		_svc.new_game()
		_t_state = 1
		return false
	if _ticks < 10:
		return false
	_kevin = _npcm.get_npc("kevin")
	if _kevin == null:
		_check(false, "N4 新局后 kevin 存在")
		return true
	_check(_kevin.global_position.distance_to(Vector3(5.0, FLOOR_Y, 6.5)) < 0.6,
		"N4 新局清空快照：kevin 回配置出生点", str(_kevin.global_position))
	_check(not _kevin.has_goal(), "N4 新局无残留行走目标")
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== NPC LIFECYCLE RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
