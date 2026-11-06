## SettingsManager — 玩家设置的单一权威与持久化
## 设置与游戏存档分离：删档/重开不会重置玩家的操作与音量偏好。

class_name SettingsManager
extends RefCounted

const DEFAULT_PATH := "user://comet_settings.json"
const DEFAULTS := {
	"sensitivity_x": 0.0035,
	"sensitivity_y": 0.0035,
	"invert_y": false,
	"master_volume": 0.8,
	"music_volume": 0.55,
	"ambience_volume": 0.7,
	"sfx_volume": 0.8,
	"voice_volume": 0.85,
	"resolution": "1280x720",
	"fullscreen": false,
	"max_fps": 60,
}

var values: Dictionary = DEFAULTS.duplicate(true)
var _path: String = DEFAULT_PATH


func set_path(path: String) -> void:
	if not path.is_empty():
		_path = path


func get_path() -> String:
	return _path


func load_settings() -> bool:
	values = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(_path):
		return false
	var text := FileAccess.get_file_as_string(_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("设置文件损坏，已使用默认值: %s" % _path)
		return false
	for key in DEFAULTS.keys():
		if (parsed as Dictionary).has(key):
			values[key] = (parsed as Dictionary)[key]
	_sanitize()
	return true


func save_settings() -> bool:
	_sanitize()
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_error("设置写入失败: %s" % _path)
		return false
	file.store_string(JSON.stringify(values, "\t"))
	file.close()
	return true


func set_value(key: String, value: Variant, persist: bool = true) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = value
	_sanitize()
	if persist:
		save_settings()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func apply(player: Node = null, apply_display: bool = true) -> void:
	if player != null:
		player.sensitivity_x = float(values["sensitivity_x"])
		player.sensitivity_y = float(values["sensitivity_y"])
		player.invert_y = bool(values["invert_y"])
	# headless 下不限帧：自动化测试依赖「渲染帧尽可能快跑」，
	# 一旦被 max_fps 卡住，所有基于帧计数的等待都会变慢并出现时序抖动。
	if DisplayServer.get_name() == "headless":
		return
	Engine.max_fps = int(values["max_fps"])
	if not apply_display:
		return
	var parts: PackedStringArray = str(values["resolution"]).split("x")
	if parts.size() == 2:
		DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if bool(values["fullscreen"])
		else DisplayServer.WINDOW_MODE_WINDOWED)


func _sanitize() -> void:
	values["sensitivity_x"] = clampf(float(values["sensitivity_x"]), 0.0002, 0.02)
	values["sensitivity_y"] = clampf(float(values["sensitivity_y"]), 0.0002, 0.02)
	for key in ["master_volume", "music_volume", "ambience_volume", "sfx_volume", "voice_volume"]:
		values[key] = clampf(float(values[key]), 0.0, 1.0)
	if str(values["resolution"]) not in ["1280x720", "854x480", "640x360"]:
		values["resolution"] = "1280x720"
	values["max_fps"] = int(values["max_fps"])
	if int(values["max_fps"]) not in [0, 30, 60, 120]:
		values["max_fps"] = 60
