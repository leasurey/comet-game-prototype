## SaveMigrationTest — 存档原子性、v1→v2 迁移、损坏隔离、位置与返回栈恢复
##
## 对应缺陷：
##   BUG-001 直接覆盖写，中途失败即永久损坏且无备份
##   BUG-003 读档不恢复玩家位置
##   BUG-004 visit_stack 从未写入存档
##   BUG-021 损坏存档不隔离，每次启动重复失败
##
## 分两部分：
##   A. SaveManager 独立验证（迁移 / 原子 / 隔离），不依赖场景树
##   B. 端到端：真实主场景 → 移动 → 保存 → 挪开 → 读档 → 位置与返回栈恢复
##
## 用法：godot --headless --script res://tests/save_migration_test.gd

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []

var _svc: Node = null
var _rig = null
var _sm = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _saved_pos := Vector3.ZERO


func _initialize() -> void:
	print("=== COMET save migration test ===")
	_part_a()
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_save_at"),
		Callable(self, "step_load_at"),
		Callable(self, "step_report"),
	]


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		_lines.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_lines.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


# ------------------------------------------------------------------ A 独立验证

func _part_a() -> void:
	var sm := SaveManager.new()
	sm.use_test_path("migrate_a")

	var state := {
		"location_id": "party_house",
		"world_id": "world_alpha",
		"visited_locations": ["party_house"],
		"world_change_records": [],
		"triggered_events": [],
		"event_history": {},
		"event_sequence": [],
		"game_clock_ticks": 3,
		"player_view": {"yaw": 0.2, "pitch": 0.1},
	}

	# --- 原子性：连续保存两次，应产生 .bak 且不残留 .tmp
	var r1 := sm.save(state)
	_check(bool(r1.get("ok", false)), "A1 首次保存成功", str(r1.get("error", "")))
	var r2 := sm.save(state)
	_check(bool(r2.get("ok", false)), "A2 二次保存成功", str(r2.get("error", "")))
	_check(FileAccess.file_exists(sm.backup_path()), "A3 二次保存生成备份 .bak")
	_check(not FileAccess.file_exists(sm.get_path() + ".tmp"), "A4 无残留 .tmp")
	_check(FileAccess.file_exists(sm.get_path()), "A5 正式存档存在")

	var loaded := sm.load_state(["party_house"], ["world_alpha"])
	_check(bool(loaded.get("ok", false)), "A6 正式存档可读", str(loaded.get("error", "")))
	_check(int((loaded.get("data", {}) as Dictionary).get("version", 0)) == 2,
		"A7 写入版本为 2")

	var bak := SaveManager.new()
	bak.set_path(sm.backup_path())
	var bak_loaded := bak.load_state(["party_house"], ["world_alpha"])
	_check(bool(bak_loaded.get("ok", false)), "A8 备份文件本身可读")

	# --- v1 迁移
	var v1 := {
		"magic": "COMET_SAVE", "version": 1,
		"location_id": "party_house", "world_id": "world_alpha",
		"visited_locations": ["party_house"],
		"world_change_records": [],
		"triggered_events": [], "event_history": {}, "event_sequence": [],
		"game_clock_ticks": 7,
		"player_view": {"yaw": 0.4, "pitch": 0.1},
	}
	var v1_path := "user://_test_migrate_v1.json"
	var f := FileAccess.open(v1_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()

	var v1_sm := SaveManager.new()
	v1_sm.set_path(v1_path)
	var m := v1_sm.load_state(["party_house"], ["world_alpha"])
	_check(bool(m.get("ok", false)), "A9 v1 存档可被读入", str(m.get("error", "")))
	var md: Dictionary = m.get("data", {})
	_check(int(md.get("version", 0)) == 2, "A10 迁移后版本升到 2", "version=%d" % int(md.get("version", 0)))
	_check(int(md.get("migrated_from", -1)) == 1, "A11 记录了来源版本")
	_check(md.has("player_position") and (md["player_position"] as Array).is_empty(),
		"A12 v1 无位置字段 → 补空数组（沿用 spawn）")
	_check(md.has("visit_stack"), "A13 补上 visit_stack 字段")
	_check(int(md.get("game_clock_ticks", 0)) == 7, "A14 迁移不丢原有进度")
	_check((md.get("player_view", {}) as Dictionary).has("yaw"), "A15 迁移保留朝向")
	v1_sm.delete_save()

	# --- 损坏隔离
	var bad_sm := SaveManager.new()
	bad_sm.use_test_path("migrate_bad")
	var bf := FileAccess.open(bad_sm.get_path(), FileAccess.WRITE)
	bf.store_string("{ 这不是合法 JSON")
	bf.close()
	var bad := bad_sm.load_state([], [])
	_check(not bool(bad.get("ok", true)), "A16 损坏存档被拒绝")
	var moved := bad_sm.quarantine_corrupt()
	_check(not moved.is_empty(), "A17 损坏存档可被隔离", moved)
	_check(not FileAccess.file_exists(bad_sm.get_path()), "A18 隔离后原路径已清空")
	if not moved.is_empty():
		var cf := FileAccess.open(moved, FileAccess.WRITE)
		if cf != null:
			cf.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(moved))

	sm.delete_save()


# ------------------------------------------------------------------ B 端到端

func step_setup() -> bool:
	if _svc == null:
		_svc = root.get_node_or_null("GameServices")
		if _svc == null:
			_check(false, "B. GameServices 可用")
			return true
		if _svc.is_ready and _svc.save_manager != null:
			_svc.save_manager.use_test_path("save_migration")
			_svc.save_manager.delete_save()
		root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
		return false
	if _ticks < 8:
		return false
	_rig = _svc.player_controller
	_sm = _svc.scene_manager
	_check(_rig != null and _sm != null, "B1 服务已装配")
	return true


func step_save_at() -> bool:
	if _t_state == 0:
		_sm.enter_location("house_exterior", true)
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 4:
			return false
		# 车道上的一点空地
		_saved_pos = Vector3(0.5, 0.05, -5.0)
		_rig.reset_to_spawn(_saved_pos)
		_rig.yaw = 0.8
		_rig.pitch = -0.2
		_rig._apply_rotation()
		_t_state = 2
		return false
	if _t_state == 2:
		if _ticks < 3:
			return false
		var ok: bool = _svc.save_game()
		_check(ok, "B2 保存成功")
		# 显式标 Variant：JSON.parse_string 的返回类型是 Variant，
		# 用 := 会触发 "inferred from Variant" 警告（本项目把该警告当错误处理）。
		var payload: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(_svc.save_manager.get_path()))
		_check(typeof(payload) == TYPE_DICTIONARY, "B3 存档可解析")
		if typeof(payload) == TYPE_DICTIONARY:
			var pp: Array = (payload as Dictionary).get("player_position", [])
			_check(pp.size() == 3, "B4 存档写入 player_position", str(pp))
			_check(not ((payload as Dictionary).get("visit_stack", []) as Array).is_empty(),
				"B5 存档写入 visit_stack",
				str((payload as Dictionary).get("visit_stack", [])))
		_t_state = 0
		return true
	return true


func step_load_at() -> bool:
	if _t_state == 0:
		# 把玩家挪到别处，证明读档确实把它放回原处
		_rig.reset_to_spawn(Vector3(-2.0, 0.05, -14.0))
		_rig.yaw = -1.5
		_rig._apply_rotation()
		_t_state = 1
		return false
	if _t_state == 1:
		if _ticks < 3:
			return false
		var ok: bool = _svc.continue_game()
		_check(ok, "B6 读档成功")
		_t_state = 2
		return false
	if _t_state == 2:
		if _ticks < 6:
			return false
		var p: Vector3 = _rig.global_position
		_check(Vector2(p.x, p.z).distance_to(Vector2(_saved_pos.x, _saved_pos.z)) < 0.35,
			"B7 位置恢复到存档点", "pos=%s 期望≈%s" % [str(p), str(_saved_pos)])
		_check(absf(rad_to_deg(_rig.yaw) - rad_to_deg(0.8)) < 8.0,
			"B8 朝向恢复到存档点", "yaw=%.1f°" % rad_to_deg(_rig.yaw))
		_check(_sm.can_go_back(), "B9 返回栈随存档恢复",
			"depth=%d" % _sm.get_visit_stack_size())
		_t_state = 0
		return true
	return true


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return false
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_ticks = 0
		_t_state = 0
	else:
		_ticks += 1
		if _ticks > 200:
			_check(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_ticks = 0
	return false


func step_report() -> bool:
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== SAVE MIGRATION RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true
