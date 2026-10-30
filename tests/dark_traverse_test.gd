## DarkTraverseTest — 黑暗区域连续穿越与现实切换时机
##
## 对应用户第二轮任务书第九节 A / B。
##
## 核心验证：
##   走进黑暗 ≠ 现实变化；走出黑暗（到达另一端）= 现实变化。
##   这条时序是第二轮的全部意义——若一进黑暗就切世界，
##   玩家的归因会变成「我穿过了一条路」，而不是「我可能走错了」。
##
## 触发方式：把玩家瞬移到 portal 的检测区，靠物理 body_entered 真实触发，
## 不直接 emit 信号——否则测的是「信号能连上」，不是「走进去会触发」。

extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _results: Array = []

var _svc: Node = null
var _main: Node = null
var _rig: PlayerController = null
var _sm: SceneManager = null
var _wm: WorldManager = null

var _steps: Array = []
var _idx: int = 0
var _t_state: int = 0
var _pf_start: int = 0
var _pf_needed: int = 0
var _tick_pf: int = 0


func _initialize() -> void:
	print("=== COMET dark traverse test ===")
	print("engine: %s" % str(Engine.get_version_info()["string"]))
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_t01_entry_config"),
		Callable(self, "step_t02_walk_into_dark"),
		Callable(self, "step_t03_no_switch_on_enter"),
		Callable(self, "step_t04_reach_far_end"),
		Callable(self, "step_t05_switch_on_exit"),
		Callable(self, "step_t06_once_only"),
		Callable(self, "step_t07_shared_geometry"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_t_state = 0
		_pf_needed = 0
		_tick_pf = 0
	else:
		if _tick_pf == 0:
			_tick_pf = Engine.get_physics_frames()
		elif Engine.get_physics_frames() - _tick_pf > 400:
			_record(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_t_state = 0
			_pf_needed = 0
			_tick_pf = 0
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


func _wait_physics(n: int) -> bool:
	if _pf_needed == 0:
		_pf_needed = n
		_pf_start = Engine.get_physics_frames()
		return false
	return Engine.get_physics_frames() - _pf_start >= _pf_needed


func _walk(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _find(n: Node, t: String) -> Node:
	for c in _walk(n):
		if str(c.name) == t:
			return c
	return null


func _portals(inst: Node) -> Array:
	var out: Array = []
	for c in _walk(inst):
		if c is AutoPortal:
			out.append(c)
	return out


func step_setup() -> bool:
	if _pf_needed == 0 and _svc == null:
		if Engine.get_physics_frames() < 3:
			return false
		_svc = root.get_node_or_null("GameServices")
		if _svc == null:
			_record(false, "setup. GameServices 可用")
			return true
		if _svc.is_ready and _svc.save_manager != null:
			# 先切到本测试专用存档路径，绝不动玩家的正式存档（P0 / BUG-002）
			_svc.save_manager.use_test_path("dark_traverse")
			_svc.save_manager.delete_save()
		var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
		if packed == null:
			_record(false, "setup. 主场景可加载")
			return true
		_main = packed.instantiate()
		root.add_child(_main)
		return false

	if not _wait_physics(6):
		return false

	_rig = _svc.player_controller as PlayerController
	_sm = _svc.scene_manager
	_wm = _svc.world_manager
	_check(_rig != null and _sm != null and _wm != null, "setup. 管理器就绪")

	_sm.enter_location("house_exterior", false)
	_check(_sm.get_current_location_id() == "house_exterior", "setup. 进入室外")
	_check(_wm.get_current_world_id() == "world_alpha", "setup. 初始现实为 alpha",
			str(_wm.get_current_world_id()))
	return true


func step_t01_entry_config() -> bool:
	var inst: Node = _sm.get_current_instance()
	var ps := _portals(inst)
	_check(ps.size() >= 1, "T01 室外存在区域触发点", "count=%d" % ps.size())
	var entry := _find(inst, "DarkEntry")
	_check(entry != null, "T01 DarkEntry 存在")
	if entry != null:
		_check(str(entry.target_location) == "dark_road",
				"T01 DarkEntry 指向黑暗区域", str(entry.target_location))
		_check(bool(entry.use_target_spawn), "T01 DarkEntry 携带门级落点")
	# 旧的按键返回热点必须已移除，否则玩家还能"点一下"穿越
	_check(_find(inst, "RoadToDark") == null, "T01 旧的 RoadToDark 按键入口已移除")
	return true


func step_t02_walk_into_dark() -> bool:
	if _t_state == 0:
		var entry := _find(_sm.get_current_instance(), "DarkEntry")
		if entry == null:
			_check(false, "T02 走进黑暗区域", "未找到 DarkEntry")
			return true
		# 瞬移到检测区内，靠物理 body_entered 真实触发
		_rig.reset_to_spawn(Vector3(entry.global_position.x, 0.05,
				entry.global_position.z))
		_t_state = 1
		return false
	if not _wait_physics(8):
		return false

	_check(_sm.get_current_location_id() == "dark_road", "T02 走进检测区后进入黑暗区域",
			str(_sm.get_current_location_id()))
	var p: Vector3 = _rig.global_position
	_check(Vector2(p.x, p.z).length() < 0.6 or absf(p.z - 4.0) < 1.5,
			"T02 落在黑暗路段起点", "pos=%s" % str(p))
	return true


func step_t03_no_switch_on_enter() -> bool:
	# 这一条是本轮的核心：进入黑暗时现实必须不变
	_check(_wm.get_current_world_id() == "world_alpha",
			"T03 进入黑暗区域时现实不变（关键）",
			str(_wm.get_current_world_id()))
	_check(not _wm.has_ever_changed(), "T03 世界变更历史仍为空")
	return true


func step_t04_reach_far_end() -> bool:
	if _t_state == 0:
		var inst: Node = _sm.get_current_instance()
		var exit_p := _find(inst, "DarkExit")
		_check(exit_p != null, "T04 黑暗尽头存在区域触发点")
		if exit_p == null:
			return true
		_check(str(exit_p.event_kind) == "area_enter",
				"T04 尽头触发事件类型为 area_enter", str(exit_p.event_kind))
		_rig.reset_to_spawn(Vector3(exit_p.global_position.x, 0.05,
				exit_p.global_position.z))
		_t_state = 1
		return false
	if not _wait_physics(8):
		return false
	return true


func step_t05_switch_on_exit() -> bool:
	_check(_sm.get_current_location_id() == "house_exterior",
			"T05 走出黑暗后回到室外场景", str(_sm.get_current_location_id()))
	_check(_wm.get_current_world_id() == "world_beta",
			"T05 走出黑暗后现实切换为 beta（关键）",
			str(_wm.get_current_world_id()))
	_check(_wm.has_ever_changed(), "T05 世界变更历史已记录")
	var p: Vector3 = _rig.global_position
	_check(absf(p.z - (-24.0)) < 1.5, "T05 落在街对面一侧", "pos=%s" % str(p))
	_check(_wm.has_ever_changed() and _wm.get_change_count() >= 1,
			"T05 变更次数 >= 1", str(_wm.get_change_count()))
	return true


func step_t06_once_only() -> bool:
	if _t_state == 0:
		var inst: Node = _sm.get_current_instance()
		var entry := _find(inst, "DarkEntry")
		if entry == null:
			_check(false, "T06 重复穿越不重复切换", "未找到 DarkEntry")
			return true
		_rig.reset_to_spawn(Vector3(entry.global_position.x, 0.05,
				entry.global_position.z))
		_t_state = 1
		return false
	if not _wait_physics(8):
		return false

	_check(_sm.get_current_location_id() == "dark_road",
			"T06 可以再次走进黑暗区域", str(_sm.get_current_location_id()))
	_check(_wm.get_current_world_id() == "world_beta",
			"T06 再次进入不会把现实切回去（once 语义）",
			str(_wm.get_current_world_id()))
	return true


func step_t07_shared_geometry() -> bool:
	if _t_state == 0:
		# T06 结束时人在 dark_road，墙体在 house_exterior 里，先切回去
		_sm.enter_location("house_exterior", false)
		_t_state = 1
		return false
	if not _wait_physics(3):
		return false
	var inst: Node = _sm.get_current_instance()
	# 穿到 beta 之后，墙体仍在 Shared 中且可见
	var shared := _find(inst, "Shared")
	_check(shared != null, "T07 存在 Shared 共享节点")
	if shared != null:
		# house_exterior 的建筑体是 HouseBody 单块实心体，不是 Wall* 分段
		var body := _find(shared, "HouseBody")
		_check(body != null, "T07 建筑主体在换现实后仍存在")
		if body != null:
			_check((body as Node3D).visible, "T07 建筑主体在 beta 现实下仍可见")
		var geo := 0
		for c in _walk(shared):
			if c is StaticBody3D:
				geo += 1
		_check(geo >= 5, "T07 共享碰撞体未被现实切换清空", "static=%d" % geo)
	return true


func step_report() -> bool:
	print("")
	for line in _results:
		print(line)
	print("")
	print("=== DARK TRAVERSE RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true
