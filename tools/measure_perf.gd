## 目标机性能实测
##
## 用法：godot --path . --resolution 1280x720 --script res://tools/measure_perf.gd
##
## 说明：本机 GPU 即目标机型的 Radeon 530（见启动日志）。
## 在三个典型机位各采样一段时间，记录平均/最低 FPS 与 draw call。
## 不做任何"预估"，只报实际采样值。

extends SceneTree

const SAMPLE_SECONDS := 6.0
const WARMUP_SECONDS := 3.0

var _svc = null
var _main = null
var _pc = null
var _phase := 0
var _t := 0.0
var _frames := 0
var _fps_min := 999.0
var _fps_sum := 0.0
var _samples := 0
var _results: Array = []

var _spots := [
	{"name": "玄关", "pos": Vector3(0.0, 0.20, 1.60), "yaw": PI},
	{"name": "客厅", "pos": Vector3(-2.55, 0.20, 5.10), "yaw": PI * 1.35},
	{"name": "厨房", "pos": Vector3(3.85, 0.20, 6.55), "yaw": PI * 0.82},
]


func _initialize() -> void:
	print("=== COMET 性能实测 ===")
	var rs := RenderingServer.get_video_adapter_name()
	print("[GPU] %s | %s" % [rs, RenderingServer.get_video_adapter_vendor()])
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FATAL] GameServices 不可用")
		quit(1)
		return
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _process(delta: float) -> bool:
	if _phase == 0:
		_t += delta
		if _t < 0.15:
			return false
		_main._on_menu_new_game_confirmed()
		_phase = 1
		_t = 0.0
		return false

	if _phase == 1:
		_pc = _svc.player_controller
		if _pc == null:
			return false
		_t += delta
		if _t < WARMUP_SECONDS:
			return false
		_phase = 2
		_t = 0.0
		_start_sample(0)
		return false

	if _phase >= 2:
		_t += delta
		_frames += 1
		var fps := Engine.get_frames_per_second()
		if fps > 0:
			_fps_sum += float(fps)
			_samples += 1
			if float(fps) < _fps_min:
				_fps_min = float(fps)
		# 保持机位
		var idx: int = _phase - 2
		if idx >= _spots.size():
			_report()
			return true
		var spot: Dictionary = _spots[idx]
		_pc.global_position = spot["pos"]
		_pc.velocity = Vector3.ZERO
		_pc.yaw = spot["yaw"]
		if _pc.has_method("_apply_rotation"):
			_pc._apply_rotation()
		if _t >= SAMPLE_SECONDS:
			_finish_sample()
			_phase += 1
			_t = 0.0
			if _phase - 2 >= _spots.size():
				_report()
				return true
			_start_sample(_phase - 2)
		return false

	return false


func _start_sample(_i: int) -> void:
	_frames = 0
	_fps_sum = 0.0
	_fps_min = 999.0
	_samples = 0


func _finish_sample() -> void:
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var avg := _fps_sum / float(max(_samples, 1))
	_results.append({
		"spot": str(_spots[_phase - 2]["name"]),
		"avg": snappedf(avg, 0.1),
		"min": snappedf(_fps_min, 0.1),
		"draw_calls": dc,
		"objects": objs,
	})


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _report() -> void:
	print("")
	for r in _results:
		print("[PERF] %s  avg=%.1f fps  min=%.1f fps  draw_calls=%d  objects=%d"
			% [r["spot"], r["avg"], r["min"], r["draw_calls"], r["objects"]])
	var total_nodes := _count_nodes(_main)
	print("[PERF] 场景节点总数: %d" % total_nodes)
	print("")
