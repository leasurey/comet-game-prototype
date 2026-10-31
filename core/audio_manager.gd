## AudioManager — 音频播放与音量管理
##
## 职责边界：
##   负责「把哪个声音、以多大音量、放在哪个位置播出来」。
##   不决定什么时候该播什么——那由 PlayerController / main / 事件系统调用。
##
## 音量模型：
##   最终线性音量 = master_volume × category_volume。
##   每类一个 AudioStreamPlayer，音量由 SettingsManager 驱动，
##   因此不需要自定义 bus 布局即可实现分类独立调节。
##
## 素材约定：
##   assets/audio/ 下全部为程序合成的原创音频（见 docs/audio/ 的来源说明），
##   不含任何第三方或电影原声。

class_name AudioManager
extends Node

const AUDIO_ROOT := "res://assets/audio"

## 类别 → 设置里的音量键
const CATEGORY_KEYS := {
	"sfx": "sfx_volume",
	"ui": "sfx_volume",
	"footsteps": "sfx_volume",
	"movement": "sfx_volume",
	"doors": "sfx_volume",
	"interaction": "sfx_volume",
	"ambience": "ambience_volume",
	"music": "music_volume",
	"anomaly": "sfx_volume",
}

var _settings = null
var _players: Dictionary = {}
var _looping: Dictionary = {}
var _muted: bool = false
var _rng := RandomNumberGenerator.new()
var _footstep_variants := 3


func _ready() -> void:
	_rng.randomize()
	# 每类一个常驻播放器，避免一次性节点频繁创建销毁
	for cat in ["sfx", "ui", "footsteps", "movement", "doors", "interaction",
			"ambience", "music", "anomaly"]:
		var p := AudioStreamPlayer.new()
		p.name = "Cat_%s" % cat
		p.bus = "Master"
		add_child(p)
		_players[cat] = p


func bind_settings(settings) -> void:
	_settings = settings
	apply_volumes()


## 把设置里的线性音量映射到播放器（含 master 总控）。
func apply_volumes() -> void:
	if _settings == null:
		return
	var master := float(_settings.get_value("master_volume"))
	for cat in _players.keys():
		var key: String = CATEGORY_KEYS.get(cat, "sfx_volume")
		var cat_vol := float(_settings.get_value(key))
		var linear := master * cat_vol
		(_players[cat] as AudioStreamPlayer).volume_db = _linear_to_db(linear)


func set_muted(value: bool) -> void:
	_muted = value
	for cat in _players.keys():
		(_players[cat] as AudioStreamPlayer).volume_db = _linear_to_db(0.0 if _muted else 1.0) * 0.0
	apply_volumes()
	if _muted:
		for cat in _players.keys():
			(_players[cat] as AudioStreamPlayer).volume_db = -80.0


func is_muted() -> bool:
	return _muted


func _linear_to_db(linear: float) -> float:
	if linear <= 0.0001:
		return -80.0
	return 20.0 * log(linear) / log(10.0)


## 载入并缓存一个音频流。文件不存在时返回 null（调用方不必判错，静默跳过）。
func _get_stream(rel_path: String) -> AudioStream:
	# 不做常驻缓存：这些 WAV 都很小（平均 20 KB），重复 load 的开销可忽略，
	# 而缓存会在退出时把资源引用一直持有到最后，产生「resources still in use」。
	var full := "%s/%s" % [AUDIO_ROOT, rel_path]
	if not ResourceLoader.exists(full):
		push_warning("AudioManager: 缺少音频 %s" % full)
		return null
	var res: Resource = load(full)
	return res as AudioStream


## 播放一次性音效。
func play_one(rel_path: String, category: String = "sfx", volume_offset_db: float = 0.0) -> void:
	if _muted:
		return
	var stream := _get_stream(rel_path)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players.get(category, _players["sfx"])
	p.stream = stream
	p.volume_db = _linear_to_db(_category_linear(category)) + volume_offset_db
	p.play()


## 播放循环环境音。同一类别同时只保留一条循环。
##
## 复用 _players 里的常驻播放器，而不是每次新建 AudioStreamPlayer。
## 原因（实测踩到）：动态创建的节点在退出时来不及释放，
## 退出日志会报「2 ObjectDB instances were leaked / resources still in use」。
func play_loop(rel_path: String, category: String = "ambience") -> void:
	var stream := _get_stream(rel_path)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2
	var p: AudioStreamPlayer = _players.get(category, _players["ambience"])
	if p.stream == stream and p.playing:
		return  # 已在播同一段，不重启
	p.stream = stream
	p.volume_db = _linear_to_db(_category_linear(category))
	if not p.playing:
		p.play()
	_looping[category] = true


func stop_loop(category: String) -> void:
	if _looping.has(category):
		var p: AudioStreamPlayer = _players.get(category, _players["ambience"])
		if p != null and p.playing:
			p.stop()
		_looping.erase(category)


func stop_all_loops() -> void:
	for cat in _looping.keys().duplicate():
		stop_loop(cat)


## 退出时把循环停掉并断开资源引用，避免「退出时资源仍在使用」。
func _exit_tree() -> void:
	for cat in _looping.keys().duplicate():
		stop_loop(cat)
	# 必须把 stream 置空：否则播放器仍持有 AudioStream 引用，
	# 退出时会报「resources still in use」。
	for cat in _players.keys():
		var p: AudioStreamPlayer = _players[cat]
		if is_instance_valid(p):
			p.stop()
			p.stream = null


func _category_linear(category: String) -> float:
	if _settings == null:
		return 0.8
	var master := float(_settings.get_value("master_volume"))
	var key: String = CATEGORY_KEYS.get(category, "sfx_volume")
	return master * float(_settings.get_value(key))


# ---------------------------------------------------------------- 语义化入口

func play_footstep(surface: String = "wood") -> void:
	var variant := _rng.randi_range(1, _footstep_variants)
	var folder := "wood"
	if surface == "carpet":
		folder = "carpet"
	elif surface == "outdoor":
		folder = "outdoor"
	play_one("footsteps/%s_%d.wav" % [folder, variant], "footsteps", -6.0)


func play_jump() -> void:
	play_one("movement/jump.wav", "movement", -3.0)


func play_land() -> void:
	play_one("movement/land.wav", "movement", -2.0)


func play_door_open() -> void:
	play_one("doors/open.wav", "doors")


func play_door_close() -> void:
	play_one("doors/close.wav", "doors")


func play_examine() -> void:
	play_one("interaction/examine.wav", "interaction", -8.0)


func play_ui_click() -> void:
	play_one("ui/click.wav", "ui", -10.0)


func play_ui_confirm() -> void:
	play_one("ui/confirm.wav", "ui", -8.0)


func play_ui_cancel() -> void:
	play_one("ui/cancel.wav", "ui", -8.0)


func play_reality_shift() -> void:
	play_one("anomaly/reality_shift.wav", "anomaly", -2.0)


func set_ambience(indoor: bool) -> void:
	if indoor:
		play_loop("ambience/room_tone.wav", "ambience")
	else:
		play_loop("ambience/wind.wav", "ambience")
