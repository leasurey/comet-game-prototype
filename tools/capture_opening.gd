## 序章实拍截图：走真实流程 P0 → P3（含停电）
##
## 用法：godot --path . --resolution 1280x720 --script res://tools/capture_opening.gd
##
## 说明：不是直接调用「切换到某阶段」，而是像玩家一样移动、对话、等待，
## 只在阶段自然推进后截图。停电镜头必须真的由停留计时触发。

extends SceneTree

const OUT_DIR := "D:/新建文件夹/comet-game-prototype/docs/art/screenshots/"

var _svc = null
var _main = null
var _pc = null
var _opening = null
var _phase := 0
var _wait := 0
var _saved := 0
var _failed := 0


func _initialize() -> void:
	print("=== COMET opening capture ===")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FATAL] GameServices 不可用")
		quit(1)
		return
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _process(_d: float) -> bool:
	if _phase == 0:
		_wait += 1
		if _wait < 8:
			return false
		_main._on_menu_new_game_confirmed()
		_phase = 1
		_wait = 0
		return false

	if _phase == 1:
		_pc = _svc.player_controller
		_opening = _main.get_node_or_null("OpeningDirector")
		if _pc == null or _opening == null:
			_wait += 1
			if _wait % 60 == 0:
				print("[DBG] wait pc=%s opening=%s loc=%s" % [
					_pc != null, _opening != null, _svc.get_current_location_id()])
			return false
		# 面朝屋内（+Z 方向）：yaw = PI，否则默认朝向正对前门板
		_pc.yaw = PI
		_pc.pitch = deg_to_rad(1.0)
		if _pc.has_method("_apply_rotation"):
			_pc._apply_rotation()
		# 若有 NPC 正走到镜头前，把机位往东挪开再拍（否则会拍到一个后脑勺）
		for n in _svc.npc_manager.get_all_npcs():
			if n.global_position.distance_to(_pc.global_position) < 1.15:
				_pc.global_position = Vector3(1.15, 0.20, 1.85)
				_pc.velocity = Vector3.ZERO
				break
		_wait += 1
		if _wait < 12:
			return false
		_snap("09_opening_p0_arrival")
		_phase = 2
		_wait = 0
		return false

	if _phase == 2:
		# 走进客厅
		_pc.global_position = Vector3(-0.2, 0.20, 5.05)
		_pc.velocity = Vector3.ZERO
		_pc.yaw = atan2(-(-4.6 - _pc.global_position.x), -(6.6 - _pc.global_position.z))
		_pc.pitch = deg_to_rad(2.0)
		if _pc.has_method("_apply_rotation"):
			_pc._apply_rotation()
		_wait += 1
		if _wait < 25:
			return false
		_snap("10_opening_p1_living")
		_phase = 3
		_wait = 0
		return false

	if _phase == 3:
		# 与 Kevin 完成一次真实对话（P1 的完成条件）
		var kevin: NPC = _svc.npc_manager.get_npc("kevin")
		if kevin == null:
			print("[FAIL] 找不到 kevin")
			quit(1)
			return true
		if _wait == 0:
			_pc.global_position = kevin.global_position + Vector3(1.0, 0.0, 0.9)
			_pc.velocity = Vector3.ZERO
			_pc.yaw = atan2(-(kevin.global_position.x - _pc.global_position.x),
				-(kevin.global_position.z - _pc.global_position.z))
			if _pc.has_method("_apply_rotation"):
				_pc._apply_rotation()
		_wait += 1
		if _wait == 8:
			_main._start_dialogue(kevin)
		if _wait < 30:
			return false
		_main._close_dialogue()
		_phase = 4
		_wait = 0
		return false

	if _phase == 4:
		# 走到餐桌区，等停留计时自然触发停电
		_pc.global_position = Vector3(1.33, 0.20, 5.20)
		_pc.velocity = Vector3.ZERO
		_pc.yaw = atan2(-(1.33 - 1.33), -(7.6 - 5.20))
		_pc.pitch = deg_to_rad(4.0)
		if _pc.has_method("_apply_rotation"):
			_pc._apply_rotation()
		if _opening.get_phase_id() == "p3_blackout":
			_wait += 1
			if _wait < 20:
				return false
			_snap("11_opening_p3_blackout")
			print("[DONE] saved=%d failed=%d" % [_saved, _failed])
			quit(0 if _failed == 0 else 1)
			return true
		return false

	return false


func _snap(tag: String) -> void:
	RenderingServer.force_draw(true)
	var tex := root.get_texture()
	if tex == null:
		print("[FAIL] 无 viewport 纹理: %s" % tag)
		_failed += 1
		return
	var img := tex.get_image()
	if img == null:
		print("[FAIL] 取图像失败: %s" % tag)
		_failed += 1
		return
	var path := OUT_DIR + tag + ".png"
	var err := img.save_png(path)
	if err != OK:
		print("[FAIL] 保存失败 %s err=%d" % [path, err])
		_failed += 1
		return
	_saved += 1
	print("[OK] %s  phase=%s" % [path, _opening.get_phase_id() if _opening else "?"])
