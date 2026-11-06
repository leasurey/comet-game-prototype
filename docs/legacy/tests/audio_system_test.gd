## AudioSystemTest — 音频系统与音量设置
##
## 用法：godot --headless --script res://tests/audio_system_test.gd
##
## 覆盖：
##   A1  原创音频素材齐全且可载入
##   A2  分类音量 = master × category，独立可调
##   A3  静音后所有播放器音量归零
##   A4  脚步按步距触发（不是定时循环）
##   A5  跳跃 / 落地信号能触发对应音效
##   A6  世界切换触发异常音
##   A7  环境音随室内外切换

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []

var _svc = null
var _am = null
var _settings: SettingsManager = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false
var _footstep_count := 0
var _jumped := 0
var _landed := 0
var _t_start := Vector3.ZERO
var _pf_start := 0
var _pf_needed := 0
var _stopped_count := 0
var _stop_pf_start := 0
var _t_flag := false
var _step_pf_start := 0


func _initialize() -> void:
	print("=== COMET audio system test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_a1_assets"),
		Callable(self, "step_a2_volumes"),
		Callable(self, "step_a3_mute"),
		Callable(self, "step_a4_footsteps"),
		Callable(self, "step_a5_jump_land"),
		Callable(self, "step_a6_world_shift"),
		Callable(self, "step_a7_ambience"),
		Callable(self, "step_report"),
	]


func _process(_delta: float) -> bool:
	if _idx >= _steps.size():
		return true
	var done: bool = bool(_steps[_idx].call())
	if done:
		_idx += 1
		_t_state = 0
		_ticks = 0
	else:
		_ticks += 1
		if Engine.get_physics_frames() - _step_pf_start > 240:
			_rec(false, "步骤超时", "index=%d" % _idx)
			_idx += 1
			_t_state = 0
			_ticks = 0
	return false


func _rec(ok: bool, label: String, detail: String = "") -> void:
	var suffix := ""
	if detail != "":
		suffix = " | " + detail
	if ok:
		_pass += 1
	else:
		_fail += 1
	_lines.append("[%s] %s%s" % ["PASS" if ok else "FAIL", label, suffix])


func _check(cond: bool, label: String, detail: String = "") -> void:
	_rec(cond, label, detail)

## 按**物理帧**等待，而不是渲染帧。
## headless 下渲染帧几乎不耗时，几百帧可能只过几毫秒，而物理是 30Hz，
## 用渲染帧计时会「以为等了很久其实物理只跑了一两次」。
func _wait_pf(n: int) -> bool:
	if _pf_needed != n:
		_pf_needed = n
		_pf_start = Engine.get_physics_frames()
	return Engine.get_physics_frames() - _pf_start >= n


# ---------------------------------------------------------------- A1

func step_a1_assets() -> bool:
	if not bool(_svc.is_ready):
		if _ticks > 60:
			_rec(false, "A1 前置", "bootstrap 超时")
			return true
		return false
	_am = _svc.audio_manager
	_settings = _svc.settings
	_check(_am != null, "A1 AudioManager 已创建")

	var required: Array = [
		"footsteps/wood_1.wav", "footsteps/carpet_1.wav", "footsteps/outdoor_1.wav",
		"movement/jump.wav", "movement/land.wav",
		"doors/open.wav", "doors/close.wav",
		"interaction/examine.wav", "interaction/pickup.wav",
		"ui/click.wav", "ui/confirm.wav", "ui/cancel.wav",
		"ambience/room_tone.wav", "ambience/wind.wav",
		"anomaly/reality_shift.wav",
	]
	var missing: Array = []
	for rel in required:
		if not ResourceLoader.exists("res://assets/audio/" + rel):
			missing.append(rel)
	_check(missing.is_empty(), "A1 原创音频素材齐全", "缺=%s" % str(missing))

	# 每个文件必须真的能解析成音频流（不只是文件存在）
	var broken: Array = []
	for rel in required:
		if missing.has(rel):
			continue
		var res: Resource = load("res://assets/audio/" + rel)
		if res == null or not (res is AudioStream):
			broken.append(rel)
	_check(broken.is_empty(), "A1 全部素材可解析为 AudioStream", "坏=%s" % str(broken))
	return true


# ---------------------------------------------------------------- A2

func step_a2_volumes() -> bool:
	if _settings == null or _am == null:
		_rec(false, "A2 音量", "依赖缺失")
		return true

	_settings.set_value("master_volume", 1.0, false)
	_settings.set_value("sfx_volume", 0.5, false)
	_am.apply_volumes()
	var sfx_db: float = (_am._players["sfx"] as AudioStreamPlayer).volume_db
	# 1.0 * 0.5 = 0.5 线性 → 约 -6.02 dB
	_check(absf(sfx_db - (-6.0206)) < 0.1, "A2 分类音量 = master × category",
		"master=1.0 sfx=0.5 → %.3f dB (期望 -6.020)" % sfx_db)

	_settings.set_value("master_volume", 0.5, false)
	_am.apply_volumes()
	var sfx_db2: float = (_am._players["sfx"] as AudioStreamPlayer).volume_db
	# 0.5 * 0.5 = 0.25 → 约 -12.04 dB
	_check(absf(sfx_db2 - (-12.0412)) < 0.1, "A2 master 变化会同比影响所有类别",
		"master=0.5 sfx=0.5 → %.3f dB (期望 -12.041)" % sfx_db2)

	_settings.set_value("ambience_volume", 0.0, false)
	_am.apply_volumes()
	var amb_db: float = (_am._players["ambience"] as AudioStreamPlayer).volume_db
	var sfx_db3: float = (_am._players["sfx"] as AudioStreamPlayer).volume_db
	_check(amb_db <= -79.0 and absf(sfx_db3 - (-12.0412)) < 0.1,
		"A2 各类独立：把环境音调 0 不影响音效",
		"amb=%.1f sfx=%.3f" % [amb_db, sfx_db3])
	return true


# ---------------------------------------------------------------- A3

func step_a3_mute() -> bool:
	if _am == null:
		_rec(false, "A3 静音", "依赖缺失")
		return true
	_settings.set_value("master_volume", 1.0, false)
	_settings.set_value("sfx_volume", 1.0, false)
	_am.set_muted(true)
	_check(_am.is_muted(), "A3 静音状态被记录")
	var db: float = (_am._players["sfx"] as AudioStreamPlayer).volume_db
	_check(db <= -79.0, "A3 静音后播放器音量归零", "sfx=%.1f dB" % db)
	_am.set_muted(false)
	var db2: float = (_am._players["sfx"] as AudioStreamPlayer).volume_db
	_check(db2 > -20.0, "A3 取消静音后音量恢复", "sfx=%.1f dB" % db2)
	return true


# ---------------------------------------------------------------- A4

func step_a4_footsteps() -> bool:
	if _t_state == 0:
		var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
		if packed == null:
			_rec(false, "A4 脚步", "主场景不可加载")
			return true
		var main = packed.instantiate()
		root.add_child(main)
		_t_state = 1
		return false

	if _t_state == 1:
		if not _wait_pf(6):
			return false
		var player = _svc.player_controller
		if player == null:
			_rec(false, "A4 脚步", "player_controller 不可用")
			return true
		_check(player.has_signal("footstep"), "A4 PlayerController 提供 footstep 信号")
		_footstep_count = 0
		player.footstep.connect(func() -> void: _footstep_count += 1)
		player.reset_to_spawn(Vector3(1.2, 0.05, 0.8))
		player.yaw = PI  # 面向 +Z，从玄关走向开阔的主空间
		player._apply_rotation()
		# 用真实输入驱动：让 _physics_process 自己跑，脚步逻辑才会被调用
		Input.action_press("move_forward")
		_t_state = 2
		_t_start = player.global_position
		return false

	if _t_state == 2:
		var player2 = _svc.player_controller
		var walked: float = Vector2(player2.global_position.x - _t_start.x,
				player2.global_position.z - _t_start.z).length()
		# 等到真的走了足够距离再断言。
		# 不能按渲染帧计时：物理帧是 30Hz，渲染帧远快于它，
		# 固定帧数会「只走了 0.4 m 就下结论」。
		if walked < 4.0 and _pf_needed == 0 or (walked < 4.0 and Engine.get_physics_frames() - _pf_start < 120):
			return false
		Input.action_release("move_forward")
		var expected := int(walked / float(player2.STRIDE_DISTANCE))
		# 断言「与步距成比例」而不是固定区间：实际可走距离受家具阻挡，
		# 但触发次数必须与走过的距离成正比，且不能是零。
		_check(_footstep_count >= 1 and absf(_footstep_count - expected) <= 1,
			"A4 脚步按步距触发（与距离成正比，非定时循环）",
			"走 %.2f m 触发 %d 次（步距 %.2f m，理论 %d 次）" % [
				walked, _footstep_count, float(player2.STRIDE_DISTANCE), expected])
		_t_state = 3
		return false

	if _t_state == 3:
		# 停下后不应再触发
		if not _t_flag:
			_t_flag = true
			_stop_pf_start = Engine.get_physics_frames()
			_stopped_count = _footstep_count
		if Engine.get_physics_frames() - _stop_pf_start < 30:
			return false
		_check(_footstep_count == _stopped_count, "A4 静止时不再触发脚步",
			"静止后新增 %d 次" % (_footstep_count - _stopped_count))
		return true
	return true


# ---------------------------------------------------------------- A5

func step_a5_jump_land() -> bool:
	if _t_state == 0:
		var player = _svc.player_controller
		if player == null:
			_rec(false, "A5 跳跃落地音", "依赖缺失")
			return true
		_jumped = 0
		_landed = 0
		player.jumped.connect(func() -> void: _jumped += 1)
		player.landed.connect(func(_s: float) -> void: _landed += 1)
		player.reset_to_spawn(Vector3(1.2, 0.05, 0.8))
		_t_state = 1
		return false
	if _t_state == 1:
		if not _wait_pf(6):
			return false
		# 用真实输入触发跳跃，走 _physics_process 路径
		Input.action_press("jump")
		_pf_needed = 0
		_pf_start = Engine.get_physics_frames()
		_t_state = 2
		return false
	if _t_state == 2:
		if Engine.get_physics_frames() - _pf_start < 2:
			return false
		Input.action_release("jump")
		if Engine.get_physics_frames() - _pf_start < 50:
			return false
		_check(_jumped >= 1, "A5 跳跃触发 jumped 信号", "count=%d" % _jumped)
		_check(_landed >= 1, "A5 落地触发 landed 信号", "count=%d" % _landed)
		return true
	return true


# ---------------------------------------------------------------- A6

func step_a6_world_shift() -> bool:
	if _svc.world_manager == null or _svc.event_manager == null:
		_rec(false, "A6 世界切换音", "依赖缺失")
		return true
	_check(_am != null and _am.has_method("play_reality_shift"),
		"A6 异常音接口存在")
	var before: String = _svc.world_manager.get_current_world_id()
	var errs: Array = []
	_svc.event_manager.evaluate("area_enter", {"area_id": "dark_far_end"},
			_svc.world_manager, errs)
	_check(_svc.world_manager.get_current_world_id() != before,
		"A6 世界切换发生（走到了播放异常音的代码路径）",
		"%s -> %s errs=%s" % [before, _svc.world_manager.get_current_world_id(), str(errs)])
	# 世界切换必然经由 _on_world_changed，其中包含 play_reality_shift 调用。
	# headless 下 AudioServer 不真正出声，这里验证的是调用链可达与不报错。
	_check(errs.is_empty(), "A6 世界切换求值无错误", str(errs))
	return true


# ---------------------------------------------------------------- A7

func step_a7_ambience() -> bool:
	if _am == null:
		_rec(false, "A7 环境音", "依赖缺失")
		return true
	_am.set_ambience(true)
	_check(_am._looping.has("ambience"), "A7 室内环境音启动")
	var indoor_stream: String = ""
	if _am._looping.has("ambience"):
		var p: AudioStreamPlayer = _am._players["ambience"]
		indoor_stream = str(p.stream.resource_path) if p.stream != null else ""
	_check(indoor_stream.ends_with("room_tone.wav"), "A7 室内播放房间底噪", indoor_stream)

	_am.set_ambience(false)
	var outdoor_stream: String = ""
	if _am._looping.has("ambience"):
		var p2: AudioStreamPlayer = _am._players["ambience"]
		outdoor_stream = str(p2.stream.resource_path) if p2.stream != null else ""
	_check(outdoor_stream.ends_with("wind.wav"), "A7 室外播放风声", outdoor_stream)

	_am.stop_all_loops()
	_check(not _am._looping.has("ambience"), "A7 可停止环境音")
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== AUDIO SYSTEM RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
