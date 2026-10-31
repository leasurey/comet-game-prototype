## SaveIsolationTest — 证明测试不会删除玩家正式存档
##
## 背景（P0 / BUG-002）：
##   修复前 5 个测试对默认路径调用 delete_save()，跑一次测试就删掉玩家进度。
##   本测试用一个"假正式存档"验证隔离确实成立，而不是只靠人工记得改路径。
##
## 用法：godot --headless --script res://tests/save_isolation_test.gd

extends SceneTree

const DEFAULT_PATH := "user://comet_save.json"

var _pass := 0
var _fail := 0
var _lines: Array = []


func _initialize() -> void:
	print("=== COMET save isolation test ===")

	var sm := SaveManager.new()
	_check(sm.is_default_path(), "初始路径就是默认存档路径")

	# 造一个"玩家正式存档"
	var probe := {
		"location_id": "party_house",
		"world_id": "world_alpha",
		"visited_locations": [],
		"world_change_records": [],
		"triggered_events": [],
		"event_history": {},
		"event_sequence": [],
		"game_clock_ticks": 0,
		"player_view": {"yaw": 0.0, "pitch": 0.0},
	}
	var saved := sm.save(probe)
	_check(bool(saved.get("ok", false)), "正式存档写入成功", str(saved.get("error", "")))
	var hash_before := _hash_file(DEFAULT_PATH)
	_check(hash_before != "", "正式存档可读取并计算指纹")

	# 切到测试路径后删除
	sm.use_test_path("isolation_probe")
	var test_path := sm.get_path()
	_check(test_path != DEFAULT_PATH, "use_test_path 切到了不同路径", test_path)
	_check(test_path.begins_with("user://_test_"), "测试路径带 _test_ 前缀", test_path)

	sm.delete_save()
	_check(not FileAccess.file_exists(test_path), "测试路径被删除")
	_check(FileAccess.file_exists(DEFAULT_PATH), "正式存档仍然存在（核心断言）")

	var hash_after := _hash_file(DEFAULT_PATH)
	_check(hash_before == hash_after, "正式存档内容零变化",
		"before=%s after=%s" % [hash_before.substr(0, 12), hash_after.substr(0, 12)])

	# 再确认：在测试路径上写入不会影响正式档
	var r2 := sm.save(probe)
	_check(bool(r2.get("ok", false)), "测试路径可独立写入")
	_check(_hash_file(DEFAULT_PATH) == hash_before, "测试写入后正式档仍零变化")
	sm.delete_save()

	# 清理：删掉本测试造的正式存档，避免污染后续
	sm.set_path(DEFAULT_PATH)
	sm.delete_save()

	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== SAVE ISOLATION RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		_lines.append("[PASS] %s%s" % [label, (" | " + detail) if detail != "" else ""])
	else:
		_fail += 1
		_lines.append("[FAIL] %s%s" % [label, (" | " + detail) if detail != "" else ""])


func _hash_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	# 存档是文本 JSON，取文本再转字节：
	# Godot 4.7 的 FileAccess 没有 get_as_buffer()，用错 API 会让哈希恒为空，
	# 进而使"内容零变化"这类断言变成空值对比的假阳性。
	var text := f.get_as_text()
	f.close()
	if text.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()
