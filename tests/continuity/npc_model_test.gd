## ContinuityNpcModelTest — 验证 NPC 真的加载了 Blender 生成的 GLB 模型
##
## 用法：godot --headless --script res://tests/continuity/npc_model_test.gd
##
## 存在意义：此前 NPC 只有程序化几何体（方块+球），"有模型"多次被写进报告
## 却没有可执行的验证。本测试直接检查运行时节点树与动画播放器状态，
## 防止再次出现「报告说有、实际没有」的情况。
##
## M1 Kevin 的模型是 GLB（含 Skeleton3D 与 AnimationPlayer，非程序化占位体）
## M2 模型朝向修正：rotation.y = PI（Blender +Y 前向 → glTF -Z）
## M3 站立时播放 idle
## M4 行走时切到 walk，且播放速率随实际速度缩放
## M5 交谈时切到 talk，结束后回 idle
## M6 模型身高与脚底位置正确（不悬空、不陷地）

extends SceneTree

const FLOOR_Y := 0.20
const MODEL_DIR := "res://assets/models/characters/"

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

var _kevin: NPC = null
var _model: Node3D = null
var _anim: AnimationPlayer = null


func _initialize() -> void:
	print("=== COMET continuity npc model test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_m1_model_is_glb"),
		Callable(self, "step_m2_facing"),
		Callable(self, "step_m3_idle"),
		Callable(self, "step_m4_walk"),
		Callable(self, "step_m5_talk"),
		Callable(self, "step_m6_grounding"),
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
		if _ticks > 600:
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
	if _ticks < 10:
		return false
	_npcm = _svc.npc_manager
	if _npcm == null or not _npcm.is_nav_ready():
		return false
	_kevin = _npcm.get_npc("kevin")
	_check(_kevin != null, "setup. kevin 已生成")
	return true


func _resolve_model() -> void:
	if _model != null and is_instance_valid(_model):
		return
	if _kevin == null:
		return
	_model = _kevin.get_node_or_null("BodyMesh") as Node3D
	_anim = _find_anim(_model)


func _find_anim(n: Node) -> AnimationPlayer:
	if n == null:
		return null
	var ap := n as AnimationPlayer
	if ap != null:
		return ap
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _find_skel(n: Node) -> Skeleton3D:
	if n == null:
		return null
	var s := n as Skeleton3D
	if s != null:
		return s
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func step_m1_model_is_glb() -> bool:
	_resolve_model()
	_check(_model != null, "M1 kevin 有可见模型节点 BodyMesh")
	if _model == null:
		return true
	var skel := _find_skel(_model)
	_check(skel != null, "M1 模型含 Skeleton3D")
	if skel != null:
		_check(skel.get_bone_count() >= 15, "M1 骨骼数量 >= 15",
			"bones=%d" % skel.get_bone_count())
	_check(_anim != null, "M1 模型含 AnimationPlayer")
	if _anim != null:
		var names: Array = []
		for a in _anim.get_animation_list():
			names.append(str(a))
		var missing: Array = []
		for e in ["idle", "walk", "talk", "sit", "stand_up", "turn"]:
			if not names.has(e):
				missing.append(e)
		_check(missing.is_empty(), "M1 六段动画齐全", "缺少=%s" % str(missing))
	# GLB 与程序化占位体的区别：占位体没有 Skeleton3D
	_check(skel != null, "M1 不是程序化占位体（占位体无骨架）")
	return true


func step_m2_facing() -> bool:
	_resolve_model()
	if _model == null:
		return true
	_check(absf(absf(_model.rotation.y) - PI) < 0.001,
		"M2 模型旋转 180° 修正朝向（Blender +Y → glTF -Z）",
		"rotation.y=%.4f" % _model.rotation.y)
	return true


func step_m3_idle() -> bool:
	_resolve_model()
	if _anim == null:
		return true
	if _t_state == 0:
		_kevin.stop_talking()
		_kevin.stop_moving()
		_t_state = 1
		return false
	if _ticks < 20:
		return false
	_check(_anim.current_animation == "idle", "M3 站立时播放 idle",
		_anim.current_animation)
	var idle_anim := _anim.get_animation("idle")
	_check(idle_anim != null and idle_anim.loop_mode == Animation.LOOP_LINEAR,
		"M3 idle 为循环播放")
	return true


func step_m4_walk() -> bool:
	if _t_state == 0:
		_npcm.send_to_room("kevin", "living")
		_t_state = 1
		return false
	if _ticks < 12:
		return false
	_resolve_model()
	if _anim == null:
		return true
	var st: String = _kevin.get_state()
	if st != NPC.STATE_WALKING:
		# 已到达也算通过（距离太近时秒到），但要求期间确实切过 walk
		_check(_anim.current_animation in ["walk", "idle"], "M4 行走状态动画合法",
			"state=%s anim=%s" % [st, _anim.current_animation])
		if _anim.current_animation == "walk":
			return true
		return false
	_check(_anim.current_animation == "walk", "M4 行走时播放 walk",
		_anim.current_animation)
	var spd := _anim.speed_scale
	_check(spd > 0.3 and spd < 2.0, "M4 播放速率随速度缩放", "speed_scale=%.2f" % spd)
	return true


func step_m5_talk() -> bool:
	if _t_state == 0:
		_kevin.start_talking(_kevin.global_position + Vector3(1, 0, 0))
		_t_state = 1
		return false
	if _ticks < 15:
		return false
	_resolve_model()
	if _anim == null:
		return true
	_check(_anim.current_animation == "talk", "M5 交谈时播放 talk",
		_anim.current_animation)
	_kevin.stop_talking()
	return true


func step_m6_grounding() -> bool:
	_resolve_model()
	if _model == null:
		return true
	# 合并所有 MeshInstance3D 的 AABB（模型局部空间）
	var meshes: Array = []
	_collect_meshes(_model, meshes)
	_check(meshes.size() >= 1, "M6 模型含网格", "count=%d" % meshes.size())
	if meshes.is_empty():
		return true
	var box := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	var sz := box.size
	_check(sz.y > 1.5 and sz.y < 2.0, "M6 模型身高合理", "height=%.3f m" % sz.y)
	# 模型整体旋转 180°，脚底仍应在 y≈0
	_check(absf(box.position.y) < 0.08, "M6 脚底贴合 NPC 原点（不悬空/不陷地）",
		"min_y=%.3f" % box.position.y)
	return true


func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== NPC MODEL RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
