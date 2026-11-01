## 真实运行截图抓取（需要图形上下文，不能用 --headless）
##
## 用法：
##   godot --path . --resolution 1280x720 --script res://tools/capture_screenshots.gd
##
## 说明：本脚本启动真实 main.tscn，移动第一人称玩家到指定位置，
## 等若干帧让渲染完成后保存 viewport 图像。截图来自实际游戏渲染管线，
## 不是编辑器场景视图，也不是 Blender 离线渲染。

extends SceneTree

const OUT_DIR := "D:/新建文件夹/comet-game-prototype/docs/art/screenshots/"
const FRAME_WAIT := 12

var _svc = null
var _main = null
var _pc = null
var _shots: Array = []
var _idx := 0
var _phase := 0
var _wait := 0
var _started := false
var _inited := false
var _saved := 0
var _failed := 0


func _initialize() -> void:
	print("=== COMET screenshot capture ===")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FATAL] GameServices 不可用")
		quit(1)
		return
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	# 玩家入场后再排队截图
	_build_shot_list()


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if d.length() < 0.001:
		return 0.0
	return atan2(-d.x, -d.z)


func _build_shot_list() -> void:
	var foyer := Vector3(0.55, 0.20, 3.05)
	var living_pos := Vector3(-2.55, 0.20, 5.10)
	var dining_pos := Vector3(1.30, 0.20, 3.95)
	var kitchen_pos := Vector3(3.85, 0.20, 6.55)
	var door_pos := Vector3(0.30, 0.20, 3.20)

	_shots = [
		{"file": "01_foyer_to_living", "pos": foyer,
			"look": Vector3(-1.6, 1.45, 7.4), "pitch": 2.0},
		{"file": "02_living_room", "pos": living_pos,
			"look": Vector3(-5.2, 1.2, 6.9), "pitch": 6.0},
		{"file": "03_dining_table", "pos": dining_pos,
			"look": Vector3(1.325, 0.95, 6.48), "pitch": 12.0},
		{"file": "04_kitchen", "pos": kitchen_pos,
			"look": Vector3(5.8, 1.1, 8.7), "pitch": 6.0},
		{"file": "05_front_door_closed", "pos": door_pos,
			"look": Vector3(0.0, 1.2, 0.10), "pitch": 0.0},
		{"file": "06_door_open", "pos": door_pos,
			"look": Vector3(0.0, 1.2, 0.10), "pitch": 0.0, "open_door": true},
		# 西翼（按电影考据新增：走廊连接主空间与卧室/浴室）
		{"file": "12_hallway", "pos": Vector3(-7.35, 0.20, 4.60),
			"look": Vector3(-8.05, 1.5, 8.20), "pitch": 2.0},
		{"file": "13_bedroom", "pos": Vector3(-8.60, 0.20, 6.10),
			"look": Vector3(-9.90, 1.0, 8.40), "pitch": 6.0},
		{"file": "14_bathroom", "pos": Vector3(-8.55, 0.20, 3.10),
			"look": Vector3(-10.70, 1.0, 3.90), "pitch": 4.0},
	]


func _process(_d: float) -> bool:
	if _idx >= _shots.size():
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		print("[PERF] draw_calls=%d objects=%d" % [dc, objs])
		print("[DONE] saved=%d failed=%d" % [_saved, _failed])
		quit(0 if _failed == 0 else 1)
		return true

	if not _inited:
		# 走真实 UI「开始新游戏」回调（等同点击菜单按钮），而不是测试专用入口
		if _started == false:
			_wait += 1
			if _wait < 8:
				return false
			if _main.has_method("_on_menu_new_game_confirmed"):
				_main._on_menu_new_game_confirmed()
			_started = true
			_wait = 0
			return false
		_pc = _svc.player_controller
		if _pc == null:
			return false
		if _svc.npc_manager == null or not _svc.npc_manager.is_nav_ready():
			return false
		# 等 NPC 全部落地
		_wait += 1
		if _wait < 20:
			return false
		_append_npc_shots()
		_inited = true
		return false

	var shot: Dictionary = _shots[_idx]

	if _phase == 0:
		var pos: Vector3 = shot["pos"]
		_pc.global_position = pos
		_pc.velocity = Vector3.ZERO
		_pc.yaw = _yaw_to(pos, shot["look"])
		_pc.pitch = deg_to_rad(float(shot.get("pitch", 0.0)))
		if _pc.has_method("_apply_rotation"):
			_pc._apply_rotation()
		if bool(shot.get("open_door", false)):
			_open_front_door()
		if shot.has("dialogue"):
			var npc: NPC = _svc.npc_manager.get_npc(str(shot["dialogue"]))
			if npc != null and _main.has_method("_start_dialogue"):
				_main._start_dialogue(npc)
		_phase = 1
		_wait = 0
		return false

	if _phase == 1:
		# 每帧维持位置（防止物理把玩家推走）
		var pos2: Vector3 = shot["pos"]
		_pc.global_position = pos2
		_pc.velocity = Vector3.ZERO
		_wait += 1
		if _wait < FRAME_WAIT:
			return false
		_snap(str(shot["file"]))
		_phase = 0
		_wait = 0
		_idx += 1
		return false

	return false


## 依据实际生成的 NPC，补拍「多人聚会」与「与 Kevin 交谈」两张。
func _append_npc_shots() -> void:
	var npcm = _svc.npc_manager
	var kevin: NPC = npcm.get_npc("kevin")
	if kevin != null:
		var kp := kevin.global_position
		# 站在 Kevin 正前方 1.5m，平视他的脸
		var offset := Vector3(0.9, 0.0, 1.35)
		var cam_pos := kp + offset
		cam_pos.y = 0.20
		_shots.append({"file": "07_kevin_closeup", "pos": cam_pos,
			"look": kp + Vector3(0, 0.15, 0), "pitch": 4.0})
		# 交谈：走真实的 _start_dialogue 路径（与按 E 相同）
		_shots.append({"file": "08_kevin_dialogue", "pos": cam_pos,
			"look": kp + Vector3(0, 0.15, 0), "pitch": 4.0, "dialogue": "kevin"})
	print("[INFO] 截图队列共 %d 张" % _shots.size())


func _open_front_door() -> void:
	var inst: Node = _svc.scene_manager.get_current_instance()
	if inst == null:
		return
	for c in _walk(inst):
		if str(c.name).begins_with("FrontDoorGeo") and c.has_method("try_open"):
			if not c.is_open():
				c.set_player(_pc)
				c.try_open()
			return


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _snap(tag: String) -> void:
	# 触发一次同步绘制，确保取到最新一帧
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
	print("[OK] %s (%dx%d)" % [path, img.get_width(), img.get_height()])
