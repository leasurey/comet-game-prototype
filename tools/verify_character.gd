## 角色模型导入验证脚本（headless）
##
## 用途：真实加载 assets/models/characters/*.glb，检查：
##   - 能否实例化
##   - 骨架是否存在、骨骼数量
##   - AnimationPlayer 是否含预期动画片段及长度
##   - 网格 AABB 尺寸是否接近真实人体（防止缩放/朝向错误）
##
## 运行：
##   godot --headless --path . --script res://tools/verify_character.gd

extends SceneTree

const DIR := "res://assets/models/characters/"
const EXPECTED := ["idle", "walk", "turn", "talk", "sit", "stand_up"]

var _names: Array = []
var _idx := 0
var _fail := 0
var _pass := 0


func _initialize() -> void:
	var da := DirAccess.open(DIR)
	if da == null:
		print("[FATAL] 目录不存在: %s" % DIR)
		quit(1)
		return
	for f in da.get_files():
		if f.ends_with(".glb"):
			_names.append(f)
	if _names.is_empty():
		print("[FATAL] 目录内无 .glb 文件: %s" % DIR)
		quit(1)
		return
	print("[INFO] 待验证 %d 个模型: %s" % [_names.size(), str(_names)])


func _process(_delta: float) -> bool:
	if _idx >= _names.size():
		print("")
		print("RESULT: PASS=%d FAIL=%d" % [_pass, _fail])
		quit(1 if _fail > 0 else 0)
		return true
	_verify(str(_names[_idx]))
	_idx += 1
	return false


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s %s" % [msg, detail])
	else:
		_fail += 1
		print("  [FAIL] %s %s" % [msg, detail])


func _verify(fname: String) -> void:
	print("")
	print("=== %s ===" % fname)
	var path := DIR + fname
	var packed := load(path)
	if packed == null:
		_check(false, "加载 GLB", path)
		return
	_check(packed is PackedScene, "是 PackedScene")
	var root: Node = (packed as PackedScene).instantiate()
	if root == null:
		_check(false, "实例化")
		return

	# ---- 骨架 ----
	var skel := _find_first(root, "Skeleton3D")
	_check(skel != null, "存在 Skeleton3D")
	var bone_count := 0
	if skel != null:
		bone_count = (skel as Skeleton3D).get_bone_count()
		_check(bone_count >= 15, "骨骼数量充足", "bones=%d" % bone_count)

	# ---- 网格 ----
	var meshes := _find_all(root, "MeshInstance3D")
	_check(meshes.size() >= 1, "存在 MeshInstance3D", "count=%d" % meshes.size())
	var total_aabb := AABB()
	var has_aabb := false
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.mesh.get_aabb()
		if not has_aabb:
			total_aabb = box
			has_aabb = true
		else:
			total_aabb = total_aabb.merge(box)
	if has_aabb:
		var sz := total_aabb.size
		_check(sz.y > 1.4 and sz.y < 2.1, "身高在合理区间", "height=%.3f m" % sz.y)
		_check(sz.x > 0.2 and sz.x < 1.0, "身宽在合理区间", "width=%.3f m" % sz.x)
		_check(total_aabb.position.y > -0.10 and total_aabb.position.y < 0.15,
			"脚底接近原点（不悬空/不陷地）", "min_y=%.3f" % total_aabb.position.y)
		# 朝向：脚尖与鼻子伸向 -Z（Blender +Y 前向 → glTF -Z）。
		# 若 -Z 侧包络明显大于 +Z 侧，说明模型面向 -Z，NPC 侧需旋转 180°。
		var neg := absf(total_aabb.position.z)
		var pos := absf(total_aabb.position.z + sz.z)
		_check(neg > pos, "模型面向 -Z（NPC 侧需 180° 修正）",
			"-Z=%.3f +Z=%.3f" % [neg, pos])

	# ---- 蒙皮 ----
	var skin_found := false
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.skin != null:
			skin_found = true
			break
	_check(skin_found, "网格已绑定蒙皮 Skin")

	# ---- 动画 ----
	var ap := _find_first(root, "AnimationPlayer")
	_check(ap != null, "存在 AnimationPlayer")
	if ap != null:
		var list: PackedStringArray = (ap as AnimationPlayer).get_animation_list()
		var names: Array = []
		for a in list:
			names.append(str(a))
		print("      动画: %s" % str(names))
		var missing: Array = []
		for e in EXPECTED:
			if not names.has(e):
				missing.append(e)
		_check(missing.is_empty(), "六个基础动画齐全", "缺少=%s" % str(missing))
		for e in names:
			var anim: Animation = (ap as AnimationPlayer).get_animation(e)
			_check(anim != null and anim.length > 0.05,
				"动画时长有效: %s" % e, "%.2fs" % (anim.length if anim else 0.0))
		# 关键：动画必须真的驱动骨骼（不是空轨）
		var skeleton_moved := false
		for e in names:
			var anim2: Animation = (ap as AnimationPlayer).get_animation(e)
			if anim2 == null:
				continue
			for t in anim2.get_track_count():
				var tp := anim2.track_get_path(t)
				if String(tp).contains(":"):
					skeleton_moved = true
					break
			if skeleton_moved:
				break
		_check(skeleton_moved, "动画轨道驱动骨骼（非空动画）")

	root.free()
	print("  --- %s done ---" % fname)


func _find_first(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r != null:
			return r
	return null


func _find_all(n: Node, cls: String) -> Array:
	var out: Array = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_all(c, cls))
	return out
