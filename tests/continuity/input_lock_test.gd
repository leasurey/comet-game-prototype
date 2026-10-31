## ContinuityInputLockTest — CT-001/002 输入锁
##
## 用法：godot --headless --script res://tests/continuity/input_lock_test.gd
##
## L1 暂停菜单打开时玩家不能移动（真实 Input.action_press 路径）
## L2 关闭暂停后恢复移动
## L3 对话面板打开时玩家不能移动，且 NPC/世界冻结
## L4 关闭对话后恢复移动
##
## 权威机制：世界子树 PAUSABLE + get_tree().paused（暂停菜单与对话共用）。
## 修复前实测：paused=true 按 W 仍移动（探针 moved=true）。

extends SceneTree

const MOVE_FRAMES := 20
const MIN_MOVE := 0.05

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _main = null
var _pc = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false


func _initialize() -> void:
	print("=== COMET continuity input lock test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_l1_pause_locks"),
		Callable(self, "step_l2_resume_unlocks"),
		Callable(self, "step_l3_dialogue_locks"),
		Callable(self, "step_l4_dialogue_unlocks"),
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
		if _ticks > 400:
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
		sm.use_test_path("input_lock")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _ticks < 12:
		return false
	_pc = _svc.player_controller
	_check(_pc != null, "setup. 玩家控制器就绪")
	return true


## 按住前进 frames 帧并记录水平位移量（真实 Input.action_press 路径）。
var _walk_delta := 0.0
var _walk_done := false

func _walk_async(frames: int) -> void:
	var p0: Vector3 = _pc.global_position
	Input.action_press("move_forward")
	for i in range(frames):
		await process_frame
	Input.action_release("move_forward")
	_walk_delta = p0.distance_to(_pc.global_position)
	_walk_done = true


func step_l1_pause_locks() -> bool:
	if _t_state == 0:
		_main._open_pause()
		_t_state = 1
		return false
	if _t_state == 1:
		_check(paused, "L1 暂停菜单打开时树处于暂停态")
		_check(not _pc.can_process(), "L1 玩家物理在暂停时被冻结（PAUSABLE 生效）",
			"process_mode=%d" % _pc.process_mode)
		_walk_done = false
		_walk_async(MOVE_FRAMES)
		_t_state = 2
		return false
	if _t_state == 2:
		if not _walk_done:
			return false
		_t_state = 3
	if _t_state == 3:
		_check(_walk_delta < MIN_MOVE, "L1 暂停时按 W 不移动",
		"位移=%.3f m" % _walk_delta)
	return true


func step_l2_resume_unlocks() -> bool:
	if _t_state == 0:
		_main._close_pause()
		_t_state = 1
		return false
	if _ticks < 3:
		return false
	if _t_state == 1:
		_check(not paused, "L2 关闭暂停后树恢复运行")
		_check(_pc.can_process(), "L2 玩家物理恢复")
		_walk_done = false
		_walk_async(MOVE_FRAMES)
		_t_state = 2
		return false
	if _t_state == 2:
		if not _walk_done:
			return false
		_t_state = 3
	if _t_state == 3:
		_check(_walk_delta > MIN_MOVE, "L2 恢复后按 W 可移动",
		"位移=%.3f m" % _walk_delta)
	return true


var _dlg_npc: NPC = null

func step_l3_dialogue_locks() -> bool:
	if _t_state == 0:
		_dlg_npc = NPC.new()
		_dlg_npc.setup("kevin", "Kevin", "kitchen")
		root.add_child(_dlg_npc)
		_main._start_dialogue(_dlg_npc)
		_t_state = 1
		return false
	if _t_state == 1:
		_check(paused, "L3 对话打开时树处于暂停态（与暂停菜单同机制）")
		_check(not _pc.can_process(), "L3 对话时玩家物理冻结")
		_check(not _dlg_npc.can_process(), "L3 对话时 NPC 物理冻结（世界不被走开）")
		_walk_done = false
		_walk_async(MOVE_FRAMES)
		_t_state = 2
		return false
	if _t_state == 2:
		if not _walk_done:
			return false
		_t_state = 3
	if _t_state == 3:
		_check(_walk_delta < MIN_MOVE, "L3 对话时按 W 不移动",
		"位移=%.3f m" % _walk_delta)
	return true


func step_l4_dialogue_unlocks() -> bool:
	if _t_state == 0:
		_main._close_dialogue()
		_t_state = 1
		return false
	if _ticks < 3:
		return false
	if _t_state == 1:
		_check(not paused, "L4 关闭对话后树恢复运行")
		_walk_done = false
		_walk_async(MOVE_FRAMES)
		_t_state = 2
		return false
	if _t_state == 2:
		if not _walk_done:
			return false
		_t_state = 3
	if _t_state == 3:
		_check(_walk_delta > MIN_MOVE, "L4 恢复后按 W 可移动",
		"位移=%.3f m" % _walk_delta)
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== INPUT LOCK RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
