## GameLogger — 结构化游戏日志（供 AI 诊断用）
##
## 输出 JSONL 格式到指定路径，每行一个 JSON 对象。
## ChatGPT 等 AI 工具可逐行解析，感知游戏运行状态、玩家行为、
## NPC 状态、事件触发、错误等信息，从而诊断问题。
##
## 使用方式：
##   GameLogger.log_event("player_moved", {"from": "living", "to": "kitchen"})
##   GameLogger.log_error("navmesh bake failed", {"detail": "0 polygons"})
##   GameLogger.log_state()  # 记录完整快照
##
## 文件位置在 _ready 中设置，首次写入时自动创建。

extends Node

## 日志文件路径（绝对路径，ChatGPT 直接读取）。
const LOG_PATH := "D:/新建文件夹/game_log.jsonl"

## 单条日志最大长度（截断超长字段防止文件膨胀）。
const MAX_FIELD_LEN := 500

var _file: FileAccess = null
var _session_start: String = ""
var _log_count: int = 0
var _max_logs_per_session: int = 2000  # 防止无限增长


func _ready() -> void:
	_session_start = _timestamp()
	_open_log()
	log_event("session_start", {
		"engine": "Godot %s" % Engine.get_version_info().get("string", "?"),
		"path": LOG_PATH,
	})


## 记录一条事件日志。
func log_event(event_type: String, data: Dictionary = {}) -> void:
	_write_line({
		"ts": _timestamp(),
		"type": event_type,
		"data": _truncate_dict(data),
	})


## 记录错误日志。
func log_error(msg: String, data: Dictionary = {}) -> void:
	_write_line({
		"ts": _timestamp(),
		"type": "ERROR",
		"msg": msg,
		"data": _truncate_dict(data),
	})


## 记录警告日志。
func log_warn(msg: String, data: Dictionary = {}) -> void:
	_write_line({
		"ts": _timestamp(),
		"type": "WARN",
		"msg": msg,
		"data": _truncate_dict(data),
	})


## 记录当前完整游戏状态快照。
## 调用时应从 GameServices 获取数据。
func log_state(game_services: Node) -> void:
	if game_services == null:
		return
	var state := {}
	# 世界状态
	if game_services.world_manager != null:
		state["world"] = game_services.world_manager.get_current_world_id()
	# 地点
	if game_services.scene_manager != null:
		state["location"] = game_services.scene_manager.get_current_location_id()
	# 事件
	if game_services.event_manager != null:
		state["events_fired"] = game_services.event_manager.get_sequence().size()
		state["event_flags"] = game_services.event_manager.get_history().get("flags", {}).keys()
	# 认知
	if game_services.cognition != null:
		state["player_facts"] = game_services.cognition.get_known_count()
		state["player_observations"] = game_services.cognition.get_observation_count()
		state["player_inferences"] = game_services.cognition.get_inference_count()
	# NPC
	if game_services.npc_manager != null:
		var npc_states: Array = []
		for nid in game_services.npc_manager.get_all_npc_ids():
			var npc = game_services.npc_manager.get_npc(nid)
			if npc == null:
				continue
			npc_states.append({
				"id": nid,
				"pos": [round(npc.global_position.x * 100) / 100.0,
						round(npc.global_position.y * 100) / 100.0,
						round(npc.global_position.z * 100) / 100.0],
				"state": npc.state,
				"behavior": npc.behavior,
				"memory_count": npc.memory.size(),
				"known_facts": npc.known_facts.size(),
				"said_nodes": npc.said_nodes.size(),
			})
		state["npcs"] = npc_states
	# 玩家
	if game_services.player_controller != null:
		var pc = game_services.player_controller
		state["player_pos"] = [round(pc.global_position.x * 100) / 100.0,
				round(pc.global_position.y * 100) / 100.0,
				round(pc.global_position.z * 100) / 100.0]
		state["player_yaw"] = round(rad_to_deg(pc.yaw) * 10) / 10.0
	# 保存
	if game_services.save_manager != null:
		state["has_save"] = game_services.save_manager.has_save()
	# Tick
	if game_services.has_method("get_tick"):
		state["tick"] = game_services.get_tick()
	# FPS
	state["fps"] = Engine.get_frames_per_second()

	log_event("game_state", state)


## 记录玩家交互行为。
func log_interaction(target: String, action: String, result: String = "") -> void:
	log_event("player_interaction", {
		"target": target,
		"action": action,
		"result": result,
	})


## 记录对话事件。
func log_dialogue(speaker: String, node_id: String, text_preview: String = "") -> void:
	log_event("dialogue", {
		"speaker": speaker,
		"node_id": node_id,
		"preview": text_preview.substr(0, 100),
	})


## 记录世界/现实切换。
func log_world_switch(from_id: String, to_id: String, reason: String = "") -> void:
	log_event("world_switch", {
		"from": from_id,
		"to": to_id,
		"reason": reason,
	})


## 记录场景切换。
func log_location_change(from_id: String, to_id: String, method: String = "door") -> void:
	log_event("location_change", {
		"from": from_id,
		"to": to_id,
		"method": method,
	})


## 记录存读档操作。
func log_save(action: String, success: bool, detail: String = "") -> void:
	log_event("save_%s" % action, {
		"success": success,
		"detail": detail,
	})


## 记录性能信息（每帧可调用，但建议节流到每秒 1 次）。
func log_performance() -> void:
	log_event("performance", {
		"fps": Engine.get_frames_per_second(),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
	})


## 手动写入一行原始 JSON（测试用）。
func log_raw(json_text: String) -> void:
	_write_raw(json_text + "\n")


# ------------------------------------------------------------------ 内部

func _open_log() -> void:
	if _file != null:
		_file.close()
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)  # 每次会话覆盖
	if _file == null:
		push_warning("GameLogger: 无法打开日志文件 %s (err=%d)" % [
			LOG_PATH, FileAccess.get_open_error()])


func _write_line(obj: Dictionary) -> void:
	if _file == null:
		return
	if _log_count >= _max_logs_per_session:
		return  # 超过上限不再写入（防止文件无限增长）
	_file.store_line(JSON.stringify(obj))
	_file.flush()  # 立即写入磁盘，AI 可实时读取
	_log_count += 1


func _write_raw(text: String) -> void:
	if _file == null:
		return
	_file.store_string(text)
	_file.flush()


func _timestamp() -> String:
	return Time.get_datetime_string_from_system(true)  # ISO 8601 UTC


func _truncate_dict(data: Dictionary) -> Dictionary:
	var out := {}
	for k in data.keys():
		var v: Variant = data[k]
		if typeof(v) == TYPE_STRING and (v as String).length() > MAX_FIELD_LEN:
			out[str(k)] = (v as String).substr(0, MAX_FIELD_LEN) + "..."
		elif typeof(v) == TYPE_ARRAY and (v as Array).size() > 20:
			out[str(k)] = (v as Array).slice(0, 20)  # 截断长数组
		else:
			out[str(k)] = v
	return out


func _exit_tree() -> void:
	log_event("session_end", {"log_count": _log_count})
	if _file != null:
		_file.close()
		_file = null
