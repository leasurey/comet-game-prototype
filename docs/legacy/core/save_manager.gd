## SaveManager — 游戏状态的持久化与恢复
##
## 职责边界：
##   只负责把「状态字典」安全写盘、安全读回、并对读回的数据做完整性校验。
##   不了解游戏规则：哪些 id 合法由调用方通过 known_* 参数注入（依赖倒置），
##   这样 SaveManager 可以在没有 WorldManager 的情况下独立测试。
##
## 错误处理原则：
##   任何读取失败、JSON 解析失败、字段缺失、类型不符、id 越界，
##   都必须返回结构化的错误而不是抛异常或崩溃；调用方据此回退到新游戏。

class_name SaveManager
extends RefCounted

const MAGIC := "COMET_SAVE"
## 版本 2：新增 player_position / visit_stack / known_facts 等字段，并提供 v1→v2 迁移。
## 版本 1 的存档仍然可以读入，缺失字段补默认值，原有进度不丢。
const SAVE_VERSION := 2
const DEFAULT_PATH := "user://comet_save.json"

## v2 新增字段的默认值。迁移时逐项补齐，避免调用方到处写 data.get(k, 默认)。
const V2_DEFAULTS := {
	"player_position": [],
	"visit_stack": [],
	"known_facts": {},
	"inspected_objects": {},
	"npc_states": {},
	"traversal_state": {},
}

var _path: String = DEFAULT_PATH
var last_error: String = ""


func set_path(path: String) -> void:
	if path.is_empty():
		return
	_path = path


## 测试专用：切到独立的临时存档路径，永不触碰正式存档。
##
## 为什么必须存在这个入口：
##   此前 5 个测试直接对**默认路径**调用 delete_save()，
##   跑一次测试就会删掉玩家的真实进度，且没有任何提示。
##   靠"每个测试记得先 set_path"不可靠（已经漏过一次），
##   因此提供语义明确的 test 路径，名字本身就写着用途。
##
## tag 会做文件名净化，避免不同测试互相覆盖。
func use_test_path(tag: String) -> void:
	var safe := tag.strip_edges()
	if safe.is_empty():
		safe = "default"
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " ", "."]:
		safe = safe.replace(ch, "_")
	_path = "user://_test_%s.json" % safe


func is_default_path() -> bool:
	return _path == DEFAULT_PATH


func get_path() -> String:
	return _path


func has_save() -> bool:
	return FileAccess.file_exists(_path)


## 写入存档。state 必须已由各 Manager 序列化完成。
##
## 写入顺序（这是数据安全的核心，不能简化）：
##   1. 写 _path.tmp
##   2. 回读校验 tmp（能解析 + magic 正确）
##   3. 把现有正式档复制为 _path.bak（保留上一份可恢复进度）
##   4. 删除正式档，把 tmp 重命名为正式档
##   5. 再次回读正式档确认
## 任一步失败都返回错误，且**不会留下半截正式档**。
##
## 早期实现直接 open(_path, WRITE) 覆盖：写到一半断电/崩溃时原档已被截断，
## 而"写完后回读校验"校验的是已经被覆盖的文件——发现损坏时好数据早就没了。
func save(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return _err("拒绝写入空状态")

	var payload: Dictionary = state.duplicate(true)
	payload["magic"] = MAGIC
	payload["version"] = SAVE_VERSION
	payload["saved_at_unix"] = int(Time.get_unix_time_from_system())

	var json_text := JSON.stringify(payload, "\t")
	if json_text.is_empty():
		return _err("状态序列化失败")

	var tmp_path := _path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		var code := FileAccess.get_open_error()
		return _err("无法写入临时文件: %s (错误码 %d)" % [tmp_path, code])
	file.store_string(json_text)
	file.close()

	# 2. 校验临时文件确实可被解析
	if not _file_is_valid(tmp_path):
		_remove_file(tmp_path)
		return _err("临时文件校验失败，正式存档未被修改")

	# 3. 备份现有正式档
	if FileAccess.file_exists(_path):
		var bak := _path + ".bak"
		_remove_file(bak)
		var copy_err := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(_path),
			ProjectSettings.globalize_path(bak))
		if copy_err != OK:
			_remove_file(tmp_path)
			return _err("无法备份现有存档，已中止写入（错误码 %d）" % copy_err)
		# 4. 移除旧档后再重命名，避免 Windows 上 rename 到已存在文件失败
		if not _remove_file(_path):
			_remove_file(tmp_path)
			return _err("无法替换正式存档")

	var rename_err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp_path),
		ProjectSettings.globalize_path(_path))
	if rename_err != OK:
		return _err("临时文件重命名为正式存档失败（错误码 %d）" % rename_err)

	# 5. 最终确认
	if not _file_is_valid(_path):
		return _err("存档写入后校验失败: %s" % _path)

	return {"ok": true, "error": "", "path": _path, "bytes": json_text.length()}


## 把损坏的存档移到 .corrupt，避免每次启动都失败一次再回退新局。
## 返回新路径；没有可隔离的文件时返回空字符串。
func quarantine_corrupt() -> String:
	if not FileAccess.file_exists(_path):
		return ""
	var dst := _path + ".corrupt"
	_remove_file(dst)
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(_path),
		ProjectSettings.globalize_path(dst))
	if err != OK:
		return ""
	return dst


func backup_path() -> String:
	return _path + ".bak"


func _file_is_valid(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var raw := f.get_as_text()
	f.close()
	if raw.strip_edges().is_empty():
		return false
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return false
	if typeof(parser.data) != TYPE_DICTIONARY:
		return false
	return str((parser.data as Dictionary).get("magic", "")) == MAGIC


func _remove_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


## 读取并校验存档。
## known_locations / known_worlds 用于拦截引用了已删除内容的旧存档。
func load_state(known_locations: Array, known_worlds: Array) -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {"ok": false, "error": "存档不存在", "data": {}}

	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		var code := FileAccess.get_open_error()
		return {"ok": false, "error": "无法打开存档: 错误码 %d" % code, "data": {}}

	var raw := file.get_as_text()
	file.close()

	if raw.strip_edges().is_empty():
		return {"ok": false, "error": "存档文件为空", "data": {}}

	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return {"ok": false, "error": "存档 JSON 解析失败: %s" % parser.get_error_message(), "data": {}}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "存档根节点不是对象", "data": {}}

	var data: Dictionary = parser.data

	var magic := str(data.get("magic", ""))
	if magic != MAGIC:
		return {"ok": false, "error": "存档标识不匹配: %s" % magic, "data": {}}

	var version := int(data.get("version", -1))
	if version <= 0:
		return {"ok": false, "error": "存档缺少合法 version 字段", "data": {}}
	if version > SAVE_VERSION:
		return {"ok": false, "error": "存档版本 %d 高于当前支持的 %d" % [version, SAVE_VERSION], "data": {}}

	var location_id := str(data.get("location_id", ""))
	if location_id.is_empty():
		return {"ok": false, "error": "存档缺少 location_id", "data": {}}
	if known_locations.size() > 0 and not known_locations.has(location_id):
		return {"ok": false, "error": "存档中的地点已不存在: %s" % location_id, "data": {}}

	var world_id := str(data.get("world_id", ""))
	if world_id.is_empty():
		return {"ok": false, "error": "存档缺少 world_id", "data": {}}
	if known_worlds.size() > 0 and not known_worlds.has(world_id):
		return {"ok": false, "error": "存档中的世界已不存在: %s" % world_id, "data": {}}

	var visited_raw: Variant = data.get("visited_locations", [])
	if typeof(visited_raw) != TYPE_ARRAY:
		return {"ok": false, "error": "visited_locations 格式错误", "data": {}}
	for loc in (visited_raw as Array):
		if known_locations.size() > 0 and not known_locations.has(str(loc)):
			return {"ok": false, "error": "存档访问记录含未知地点: %s" % str(loc), "data": {}}

	var events_raw: Variant = data.get("triggered_events", [])
	if typeof(events_raw) != TYPE_ARRAY:
		return {"ok": false, "error": "triggered_events 格式错误", "data": {}}

	var world_changes_raw: Variant = data.get("world_change_records", [])
	if typeof(world_changes_raw) != TYPE_ARRAY:
		return {"ok": false, "error": "world_change_records 格式错误", "data": {}}
	for rec in (world_changes_raw as Array):
		if typeof(rec) != TYPE_DICTIONARY:
			return {"ok": false, "error": "world_change_records 含非法条目", "data": {}}
		var d: Dictionary = rec
		var w_from := str(d.get("from", ""))
		var w_to := str(d.get("to", ""))
		if known_worlds.size() > 0:
			if not known_worlds.has(w_from) or not known_worlds.has(w_to):
				return {"ok": false, "error": "世界变化记录引用未知世界: %s -> %s" % [w_from, w_to], "data": {}}

	return {"ok": true, "error": "", "data": _migrate(data, version)}


## 版本迁移：把旧存档补齐到当前版本，**不丢任何已有进度**。
##
## 原则：
##   1. 只补缺失字段，不覆盖已有值。
##   2. 记录 migrated_from，便于日志与排查。
##   3. 无法识别的更高版本在 load_state 里已被拒绝，不会走到这里。
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	if from_version >= SAVE_VERSION:
		return out

	if from_version < 2:
		for key in V2_DEFAULTS.keys():
			if not out.has(key):
				out[key] = (V2_DEFAULTS[key] as Variant).duplicate(true) \
					if typeof(V2_DEFAULTS[key]) in [TYPE_ARRAY, TYPE_DICTIONARY] \
					else V2_DEFAULTS[key]
		# v1 只存了 yaw/pitch，没有位置；留空数组表示"沿用地点出生点"
		if not out.has("player_position"):
			out["player_position"] = []

	out["migrated_from"] = from_version
	out["version"] = SAVE_VERSION
	return out


func delete_save() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {"ok": true, "error": "", "note": "存档不存在，无需删除"}
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	if err != OK:
		return {"ok": false, "error": "删除存档失败: 错误码 %d" % err}
	return {"ok": true, "error": ""}


func _err(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": message, "path": _path, "bytes": 0}
