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

## 日志文件路径。user://logs/ 是 Godot 标准用户数据目录。
## 同时写一份到项目根目录供 ChatGPT 直接读取。
var LOG_PATH := "D:/新建文件夹/game_log.jsonl"
var _user_log_path := "user://logs/game_log.jsonl"

## 单条日志最大长度（截断超长字段防止文件膨胀）。
const MAX_FIELD_LEN := 500

var _file: FileAccess = null
var _user_file: FileAccess = null
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
		# 修复：event_manager 的 flags 在 _flags 字典中（通过 set_flag 设置）。
		# get_history() 返回事件历史，不是 flags。用 serialize() 的 flags 字段。
		var em_ser: Dictionary = game_services.event_manager.serialize()
		state["event_flags"] = (em_ser.get("flags", {}) as Dictionary).keys()
		state["event_phase"] = game_services.event_manager.get_phase() if game_services.event_manager.has_method("get_phase") else ""
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
			# 诊断改进：区分 memory（经历记忆）和 known_facts（学到的事实）。
			# 两者是不同系统——memory 由 remember() 填充，known_facts 由 teach/learn_fact 填充。
			var last_mem: Dictionary = {}
			if npc.memory.size() > 0:
				var lm: Dictionary = npc.memory[npc.memory.size() - 1]
				last_mem = {
					"kind": str(lm.get("kind", "")),
					"content": str(lm.get("content", "")).substr(0, 50),
					"source": str(lm.get("about", "")),
					"world": str(lm.get("world", "")),
				}
			npc_states.append({
				"id": nid,
				"pos": [round(npc.global_position.x * 100) / 100.0,
						round(npc.global_position.y * 100) / 100.0,
						round(npc.global_position.z * 100) / 100.0],
				"state": npc.state,
				"behavior": npc.behavior,
				"memory_count": npc.memory.size(),
				"last_memory": last_mem,
				"known_facts_count": npc.known_facts.size(),
				"known_facts": npc.known_facts.duplicate(),
				"said_nodes_count": npc.said_nodes.size(),
				"trust_player": round(npc.get_trust("player") * 100) / 100.0,
				"familiarity_player": round(npc.get_relationship("player").get("familiarity", 0.0) * 100) / 100.0,
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


## 记录对话事件（简单版，向后兼容）。
func log_dialogue(speaker: String, node_id: String, text_preview: String = "") -> void:
	log_event("dialogue", {
		"speaker": speaker,
		"node_id": node_id,
		"preview": text_preview.substr(0, 100),
	})


## 记录完整对话上下文（批次审查版）。
## text 必须是 hear() 返回的已解析文本（经 variants 处理后），
## 不得从静态 JSON 读取——最终显示内容可能因条件不同而不同。
func log_dialogue_full(speaker: String, node_id: String, text: String,
		world: String, location: String, tick: int) -> void:
	log_event("dialogue", {
		"speaker": speaker,
		"node_id": node_id,
		"dialogue_text": text,
		"world": world,
		"location": location,
		"tick": tick,
		"session_id": _session_start,
	})


## 记录事件触发（专用事件日志，区分于 game_state 的统计数字）。
## effects_applied: 实际生效的 effect 描述列表。
func log_event_trigger(event_id: String, trigger_reason: String,
		world_before: String, world_after: String,
		location: String, tick: int,
		effects_applied: Array = []) -> void:
	log_event("event_trigger", {
		"event_id": event_id,
		"trigger_reason": trigger_reason,
		"world_before": world_before,
		"world_after": world_after,
		"location": location,
		"tick": tick,
		"effects_applied": effects_applied,
	})


## 记录世界/现实切换（含切换前后的完整玩家状态）。
func log_world_switch(from_id: String, to_id: String, reason: String = "",
		player_state_before: Dictionary = {}, player_state_after: Dictionary = {}) -> void:
	log_event("world_switch", {
		"from": from_id,
		"to": to_id,
		"reason": reason,
		"player_before": player_state_before,
		"player_after": player_state_after,
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
	if _user_file != null:
		_user_file.close()
	# 主日志（用户指定路径）
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file == null:
		push_warning("GameLogger: 无法打开日志文件 %s (err=%d)" % [
			LOG_PATH, FileAccess.get_open_error()])
	# 备份到 user://logs/（Godot 标准目录）
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("logs"):
		dir.make_dir("logs")
	_user_file = FileAccess.open(_user_log_path, FileAccess.WRITE)
	if _user_file == null:
		push_warning("GameLogger: 无法打开备用日志 %s" % _user_log_path)


func _write_line(obj: Dictionary) -> void:
	if _file == null:
		return
	if _log_count >= _max_logs_per_session:
		if _log_count == _max_logs_per_session:
			push_warning("GameLogger: 日志条数达到上限 %d，后续记录被丢弃" % _max_logs_per_session)
		return
	var line := JSON.stringify(obj)
	_file.store_line(line)
	_file.flush()
	_log_count += 1
	# 同步写到 user://logs/（保留会话完整性）
	if _user_file != null:
		_user_file.store_line(line)
		_user_file.flush()


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
	if _user_file != null:
		_user_file.close()
		_user_file = null
