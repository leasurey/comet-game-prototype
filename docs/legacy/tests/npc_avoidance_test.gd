## NpcAvoidanceTest — NPC 动态避让与多 agent 寻路性能
##
## 用法：godot --headless --script res://tests/npc_avoidance_test.gd
##
## A1  两个 NPC 对向而行不重叠（分离转向避让生效，最小间距 > 0.60 m）
## A2  避让不阻碍到达：双方都走到对方起点
## A3  7 个 agent 同时派目标/寻路的耗时在预算内（回归护栏）
## A4  碰撞层约定不变：NPC 只碰环境（layer 1），不与玩家（layer 2）碰撞
##
## 背景：胶囊半径 0.28，两 NPC 不重叠需保持 ≥ 0.56 m；
## 无避让时两具身体会互相穿过（最小间距 ≈ 0）。
## 行为是确定性的：对向相逢实测最小间距稳定 0.74 m（5 轮复测一致），
## 故判据取 0.60 —— 既守住「胶囊不重叠」，又留 0.14 m 余量。

extends SceneTree

const FLOOR_Y := 0.20
const A1_MIN_DIST := 0.60
const A1_TIMEOUT_PF := 600
const A3_SEND_BUDGET_USEC := 100000   # 7 次派目标合计 100 ms（实际 ~1-3 ms）
const A3_PATH_BUDGET_USEC := 50000    # 7 次寻路查询合计 50 ms
const A3_TICK_BUDGET_USEC := 2000     # NPCManager.tick 平均每帧 2 ms

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _npcm = null
var _steps: Array = []
var _idx := 0
var _t_state := 0
var _pf_mark := 0
var _reporting := false

# A1 状态
var _min_dist := 999.0
var _kevin: NPC = null
var _beth: NPC = null
var _kevin_target := Vector3.ZERO
var _beth_target := Vector3.ZERO
var _last_pf := -1
# A3 tick 开销采样
var _t_tick_total := 0
var _t_tick_frames := 0


func _initialize() -> void:
	print("=== COMET npc avoidance & multi-agent perf test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_boot"),
		Callable(self, "step_a1_head_on"),
		Callable(self, "step_a3_multi_agent_perf"),
		Callable(self, "step_a4_layers"),
		Callable(self, "step_report"),
	]


func _process(_d: float) -> bool:
	if _npcm != null:
		_npcm.tick()
	if _idx >= _steps.size():
		return true
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_t_state = 0
		_pf_mark = 0
	return false


func _rec(ok: bool, label: String, detail: String = "") -> void:
	var suffix := "" if detail == "" else " | " + detail
	if ok:
		_pass += 1
	else:
		_fail += 1
	_lines.append("[%s] %s%s" % ["PASS" if ok else "FAIL", label, suffix])


func _check(cond: bool, label: String, detail: String = "") -> void:
	_rec(cond, label, detail)


func _wait_pf(n: int) -> bool:
	return Engine.get_physics_frames() - _pf_mark >= n


# ---------------------------------------------------------------- 步骤

func step_boot() -> bool:
	if not bool(_svc.is_ready):
		if Engine.get_physics_frames() > 400:
			_rec(false, "前置 bootstrap", "超时")
			return true
		return false
	_npcm = _svc.npc_manager
	var packed: PackedScene = load("res://scenes/locations/party_house.tscn") as PackedScene
	if packed == null:
		_rec(false, "前置", "party_house 不可加载")
		return true
	var inst = packed.instantiate()
	root.add_child(inst)
	_npcm.spawn_all(inst)
	_pf_mark = Engine.get_physics_frames()
	_t_state = 1
	_steps.insert(1, Callable(self, "step_nav_ready"))
	return true


func step_nav_ready() -> bool:
	if not _npcm.is_nav_ready():
		if _wait_pf(300):
			_rec(false, "前置：导航就绪", "超时 polys=%d" % _npcm.get_nav_polygon_count())
			return true
		return false
	_check(_npcm.get_nav_polygon_count() > 0,
		"前置：导航网格非空", "polys=%d" % _npcm.get_nav_polygon_count())
	return true


func step_a1_head_on() -> bool:
	if _t_state == 0:
		_kevin = _npcm.get_npc("kevin")
		_beth = _npcm.get_npc("beth")
		if _kevin == null or _beth == null:
			_rec(false, "A1 前置", "kevin/beth 实体缺失")
			return true
		# 对向而行：厨房北（kevin 出生）↔ 厨房南（beth 出生），同一直线走廊
		_kevin_target = _beth.global_position
		_beth_target = _kevin.global_position
		_min_dist = 999.0
		_last_pf = -1
		_npcm.send_to_point("kevin", _kevin_target)
		_npcm.send_to_point("beth", _beth_target)
		_pf_mark = Engine.get_physics_frames()
		_t_state = 1
		return false
	if _t_state == 1:
		var pf := Engine.get_physics_frames()
		if pf != _last_pf:
			_last_pf = pf
			var d := _kevin.global_position.distance_to(_beth.global_position)
			if d < _min_dist:
				_min_dist = d
		var kevin_done := _kevin.global_position.distance_to(_kevin_target) < 1.0
		var beth_done := _beth.global_position.distance_to(_beth_target) < 1.0
		if kevin_done and beth_done:
			_check(_min_dist > A1_MIN_DIST,
				"A1 对向而行不重叠（动态避让生效）",
				"最小间距 %.2f m（无避让时会穿过≈0）" % _min_dist)
			_check(kevin_done, "A2 避让不阻碍到达：kevin 到位",
				"距目标 %.2f m" % _kevin.global_position.distance_to(_kevin_target))
			_check(beth_done, "A2 避让不阻碍到达：beth 到位",
				"距目标 %.2f m" % _beth.global_position.distance_to(_beth_target))
			return true
		if _wait_pf(A1_TIMEOUT_PF):
			_check(_min_dist > A1_MIN_DIST,
				"A1 对向而行不重叠（动态避让生效）",
				"最小间距 %.2f m（超时）" % _min_dist)
			_rec(false, "A2 双方到达", "超时：kevin %.2f m, beth %.2f m" % [
				_kevin.global_position.distance_to(_kevin_target),
				_beth.global_position.distance_to(_beth_target)])
			return true
		return false
	return true


func step_a3_multi_agent_perf() -> bool:
	if _t_state == 0:
		# 7 个 agent 同时派目标（含 navmesh 吸附 + 路径查询）
		var rooms := ["living", "dining", "kitchen", "study", "foyer", "living", "dining"]
		var ids: Array = _npcm.get_character_ids()
		var t0 := Time.get_ticks_usec()
		var sent := 0
		for i in range(ids.size()):
			if _npcm.send_to_room(str(ids[i]), rooms[i % rooms.size()]):
				sent += 1
		var send_usec := Time.get_ticks_usec() - t0
		_check(sent == ids.size(), "A3 7 个 agent 同时可派目标", "成功 %d/%d" % [sent, ids.size()])
		_check(send_usec < A3_SEND_BUDGET_USEC,
			"A3 同时派目标耗时在预算内", "%d us（预算 %d）" % [send_usec, A3_SEND_BUDGET_USEC])

		# 7 次纯寻路查询（map_get_path）的合计耗时
		var map: RID = _npcm._region.get_navigation_map()
		var pts := [
			Vector3(0.0, FLOOR_Y, 1.6), Vector3(-4.5, FLOOR_Y, 6.6),
			Vector3(1.3, FLOOR_Y, 6.5), Vector3(5.0, FLOOR_Y, 6.5),
			Vector3(5.0, FLOOR_Y, 1.6), Vector3(-4.6, FLOOR_Y, 1.6),
			Vector3(-1.0, FLOOR_Y, 7.5),
		]
		var t1 := Time.get_ticks_usec()
		var ok_paths := 0
		for i in range(pts.size()):
			var path := NavigationServer3D.map_get_path(map, pts[i], pts[(i + 1) % pts.size()], true)
			if path.size() >= 2:
				ok_paths += 1
		var path_usec := Time.get_ticks_usec() - t1
		_check(ok_paths == pts.size(), "A3 7 次寻路查询全部成功", "%d/7" % ok_paths)
		_check(path_usec < A3_PATH_BUDGET_USEC,
			"A3 寻路查询耗时在预算内", "%d us（预算 %d）" % [path_usec, A3_PATH_BUDGET_USEC])

		# NPCManager.tick 在 7 个 agent 走动下的平均每帧开销
		_pf_mark = Engine.get_physics_frames()
		_t_tick_total = 0
		_t_tick_frames = 0
		_t_state = 1
		return false
	if _t_state == 1:
		var t := Time.get_ticks_usec()
		_npcm.tick()
		_t_tick_total += Time.get_ticks_usec() - t
		_t_tick_frames += 1
		if _wait_pf(60):
			var avg := _t_tick_total / maxi(_t_tick_frames, 1)
			_check(avg < A3_TICK_BUDGET_USEC,
				"A3 tick 平均每帧开销在预算内", "%d us/帧（预算 %d，样本 %d）" % [
					avg, A3_TICK_BUDGET_USEC, _t_tick_frames])
			return true
		return false
	return true


func step_a4_layers() -> bool:
	var npc: NPC = _npcm.get_npc("kevin")
	if npc == null:
		_rec(false, "A4 前置", "kevin 缺失")
		return true
	_check(npc.collision_layer == 4, "A4 NPC 在 layer 4", str(npc.collision_layer))
	_check(npc.collision_mask == 1,
		"A4 NPC 只与环境碰撞（不与玩家 layer2 / 其他 NPC 互撞）",
		str(npc.collision_mask))
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== NPC AVOIDANCE RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
