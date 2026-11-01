## ContinuityOpeningFlowTest — 序章 P0→P3 真实流程
##
## 用法：godot --headless --script res://tests/continuity/opening_flow_test.gd
##
## 存在意义：序章此前只有设计文档，代码里没有任何阶段推进。
## 本测试按「玩家真实走位 + 真实对话开关」驱动阶段机，而不是直接调阶段切换函数，
## 以便验证：区域触发、对话完成触发、停留计时、停电效果都真的生效。
##
## O1 新开局：序章运行中，停在 p0_arrival，并给出目标文字
## O2 走进客厅区域 → 自动进入 p1_living
## O3 与 Kevin 完成一次对话 → 自动进入 p2_dining
## O4 在餐桌区停留足够时间 → 自动进入 p3_blackout
## O5 停电真的生效：市电灯被调暗（记录前后能量）
## O6 走到前门 → 序章结束，交给主循环

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _main = null
var _pc = null
var _opening = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false

var _dim_before := -1.0


func _initialize() -> void:
	print("=== COMET continuity opening flow test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_o1_start"),
		Callable(self, "step_o2_enter_living"),
		Callable(self, "step_o3_talk_kevin"),
		Callable(self, "step_o4_dwell_dining"),
		Callable(self, "step_o5_blackout"),
		Callable(self, "step_o6_finish"),
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
		if _ticks > 20000:
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
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	if _ticks < 6:
		return false
	if _t_state == 1:
		# 等同点击菜单「开始新游戏」
		_main._on_menu_new_game_confirmed()
		_t_state = 2
		_ticks = 0
		return false
	if _ticks < 30:
		return false
	_pc = _svc.player_controller
	_opening = _main.get_node_or_null("OpeningDirector")
	_check(_pc != null, "setup. 玩家就绪")
	_check(_opening != null, "setup. 序章导演已创建")
	if _opening == null:
		return true
	# 记录停电前的市电灯能量
	_dim_before = _sum_electric_energy()
	_check(_dim_before > 1.0, "setup. 停电前市电灯是亮的",
		"合计能量=%.2f" % _dim_before)
	return true


func _collect_lights(n: Node, out: Array) -> void:
	if n is OmniLight3D:
		out.append(n)
	for c in n.get_children():
		_collect_lights(c, out)


const ELECTRIC_KEYS := ["LivingLamp", "DiningLamp", "KitchenLamp", "FoyerLamp", "StudyLight"]


func _sum_electric_energy() -> float:
	if _svc.scene_manager == null:
		return 0.0
	var inst: Node = _svc.scene_manager.get_current_instance()
	if inst == null:
		return 0.0
	var lights: Array = []
	_collect_lights(inst, lights)
	var total := 0.0
	for l in lights:
		var ol := l as OmniLight3D
		var nm := str(ol.name)
		for k in ELECTRIC_KEYS:
			if nm.begins_with(k):
				total += ol.light_energy
				break
	return total


func step_o1_start() -> bool:
	if _opening == null:
		return true
	_check(_opening.is_running(), "O1 序章进行中")
	_check(_opening.get_phase_id() == "p0_arrival", "O1 起始阶段为 p0_arrival",
		_opening.get_phase_id())
	_check(not _opening.get_objective().is_empty(), "O1 有目标文字",
		_opening.get_objective())
	return true


func step_o2_enter_living() -> bool:
	if _opening == null:
		return true
	if _t_state == 0:
		# 玩家真实走到客厅入口
		_pc.global_position = Vector3(0.0, 0.20, 4.75)
		_pc.velocity = Vector3.ZERO
		_t_state = 1
		return false
	if _ticks < 10:
		return false
	_check(_opening.get_phase_id() == "p1_living", "O2 走进客厅后进入 p1_living",
		_opening.get_phase_id())
	_check(_opening.get_objective().contains("Kevin"), "O2 目标指向 Kevin",
		_opening.get_objective())
	return true


func step_o3_talk_kevin() -> bool:
	if _opening == null:
		return true
	var kevin: NPC = _svc.npc_manager.get_npc("kevin")
	if _t_state == 0:
		_check(kevin != null, "O3 Kevin 在场")
		if kevin == null:
			return true
		# 走到 Kevin 身边再触发对话（真实交互距离）
		_pc.global_position = kevin.global_position + Vector3(1.0, 0.0, 0.9)
		_pc.velocity = Vector3.ZERO
		_t_state = 1
		return false
	if _ticks < 6:
		return false
	if _t_state == 1:
		_main._start_dialogue(kevin)
		_t_state = 2
		_ticks = 0
		return false
	if _ticks < 12:
		return false
	if _t_state == 2:
		# 关闭对话（与玩家点「结束对话」走同一函数）
		_main._close_dialogue()
		_t_state = 3
		_ticks = 0
		return false
	if _ticks < 8:
		return false
	_check(_opening.get_phase_id() == "p2_dining", "O3 与 Kevin 对话后进入 p2_dining",
		_opening.get_phase_id())
	return true


func step_o4_dwell_dining() -> bool:
	if _opening == null:
		return true
	if _t_state == 0:
		_pc.global_position = Vector3(1.33, 0.20, 6.20)
		_pc.velocity = Vector3.ZERO
		_t_state = 1
		return false
	# 保持站位，等停留计时（opening.json 配置 4 秒）。
	# 注意：无头模式帧率很高，不能用帧数估算秒数，只能等阶段真的变化。
	if _opening.get_phase_id() == "p3_blackout":
		_check(true, "O4 餐桌区停留后进入 p3_blackout")
		return true
	return false


func step_o5_blackout() -> bool:
	if _opening == null:
		return true
	var after := _sum_electric_energy()
	_check(after < _dim_before * 0.2, "O5 停电后市电灯能量大幅下降",
		"前=%.2f 后=%.2f" % [_dim_before, after])
	# 认知事实应被写入
	var knows := false
	if _svc.cognition != null:
		knows = _svc.cognition.knows("obs_power_out")
	_check(knows, "O5 停电写入玩家认知事实 obs_power_out")
	return true


func step_o6_finish() -> bool:
	if _opening == null:
		return true
	if _t_state == 0:
		_pc.global_position = Vector3(0.0, 0.20, 1.55)
		_pc.velocity = Vector3.ZERO
		_t_state = 1
		return false
	if _ticks < 12:
		return false
	_check(not _opening.is_running(), "O6 走到前门后序章结束")
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== OPENING FLOW RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
