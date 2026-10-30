## GameServices — 全局服务编排
##
## 这是唯一的 autoload。它不做业务逻辑，只负责：
##   1. 在系统启动时按顺序 bootstrap 各 Manager 并注入依赖；
##   2. 把「加载数据 / 开新局 / 读档 / 存档 / 导航」整理成稳定 API 暴露给 main；
##   3. 维护游戏内时钟。
##
## 之所以不把 Manager 各自注册为 autoload：
##   让它们成为这里持有与装配的普通对象，依赖关系显式可见，
##   后续替换实现或加单元测试都不需要改工程配置。

extends Node

signal bootstrap_completed
signal bootstrap_failed(reason: String)
signal save_completed(ok: bool, message: String)
signal load_completed(ok: bool, message: String)

const CLOCK_SCALE := 1.0 / 6.0
const START_CLOCK_MINUTES := 1360

const PATH_WORLDS := "res://data/worlds.json"
const PATH_TRANSITIONS := "res://data/world_transitions.json"
const PATH_EVENTS := "res://data/events.json"
const PATH_LOCATIONS := "res://data/locations.json"

var world_manager: WorldManager = null
var event_manager: EventManager = null
var save_manager: SaveManager = null
var scene_manager: SceneManager = null
var interaction_manager: InteractionManager = null

var player_controller = null
var ui = null

var is_ready: bool = false
var bootstrap_error: String = ""

var _clock_minutes: float = float(START_CLOCK_MINUTES)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_bootstrap()


func _process(delta: float) -> void:
	if not is_ready:
		return
	_clock_minutes += delta * CLOCK_SCALE
	if ui != null and ui.has_method("set_clock"):
		ui.set_clock(get_clock_text())


func _bootstrap() -> void:
	var errors: Array = []

	world_manager = WorldManager.new()
	event_manager = EventManager.new()
	save_manager = SaveManager.new()
	scene_manager = SceneManager.new()
	interaction_manager = InteractionManager.new()

	scene_manager.name = "SceneManager"
	interaction_manager.name = "InteractionManager"
	add_child(scene_manager)
	add_child(interaction_manager)

	scene_manager.world_manager = world_manager
	scene_manager.event_manager = event_manager
	scene_manager.interaction_manager = interaction_manager

	var worlds_result := DataLoader.load_dictionary(PATH_WORLDS)
	if not bool(worlds_result.get("ok", false)):
		_fail(str(worlds_result.get("error", "未知错误")))
		return
	if not world_manager.load_from_data(worlds_result.get("data", {}), errors):
		_fail(errors[0] if errors.size() > 0 else "世界数据载入失败")
		return

	var events_result := DataLoader.load_dictionary(PATH_EVENTS)
	if not bool(events_result.get("ok", false)):
		_fail(str(events_result.get("error", "未知错误")))
		return
	var transitions_result := DataLoader.load_dictionary(PATH_TRANSITIONS)
	if not bool(transitions_result.get("ok", false)):
		_fail(str(transitions_result.get("error", "未知错误")))
		return
	errors.clear()
	if not event_manager.load_from_data(events_result.get("data", {}), transitions_result.get("data", {}), errors):
		_fail(errors[0] if errors.size() > 0 else "事件数据载入失败")
		return

	var locations_result := DataLoader.load_dictionary(PATH_LOCATIONS)
	if not bool(locations_result.get("ok", false)):
		_fail(str(locations_result.get("error", "未知错误")))
		return
	errors.clear()
	if not scene_manager.load_from_data(locations_result.get("data", {}), errors):
		_fail(errors[0] if errors.size() > 0 else "地点数据载入失败")
		return

	is_ready = true
	bootstrap_completed.emit()


func _fail(reason: String) -> void:
	is_ready = false
	bootstrap_error = reason
	push_error("COMET bootstrap failed: %s" % reason)
	bootstrap_failed.emit(reason)


# ---------------------------------------------------------------- 新局 / 读档

func new_game() -> bool:
	if not is_ready:
		return false
	world_manager = WorldManager.new()
	var errors: Array = []
	var worlds_result := DataLoader.load_dictionary(PATH_WORLDS)
	if not world_manager.load_from_data(worlds_result.get("data", {}), errors):
		return false

	event_manager = EventManager.new()
	var events_result := DataLoader.load_dictionary(PATH_EVENTS)
	var transitions_result := DataLoader.load_dictionary(PATH_TRANSITIONS)
	if not event_manager.load_from_data(events_result.get("data", {}), transitions_result.get("data", {}), errors):
		return false

	scene_manager.world_manager = world_manager
	scene_manager.event_manager = event_manager
	_clock_minutes = float(START_CLOCK_MINUTES)
	return scene_manager.enter_location(scene_manager.get_start_location_id(), false)


func continue_game() -> bool:
	if not is_ready:
		load_completed.emit(false, "服务尚未就绪")
		return false

	var result := save_manager.load_state(scene_manager.get_location_ids(), world_manager.get_world_ids())
	if not bool(result.get("ok", false)):
		load_completed.emit(false, str(result.get("error", "读档失败")))
		return false

	var data: Dictionary = result.get("data", {})

	var world_errors: Array = []
	var world_state := {
		"current_world_id": str(data.get("world_id", "")),
		"change_log": (data.get("world_change_records", []) as Array).duplicate(true),
	}
	if not world_manager.restore(world_state, world_errors):
		load_completed.emit(false, world_errors[0] if world_errors.size() > 0 else "世界状态恢复失败")
		return false

	var event_errors: Array = []
	var event_state := {
		"history": data.get("event_history", {}),
		"sequence": data.get("event_sequence", []),
	}
	if not event_manager.restore(event_state, event_errors):
		load_completed.emit(false, event_errors[0] if event_errors.size() > 0 else "事件历史恢复失败")
		return false

	var scene_errors: Array = []
	var scene_state := {
		"current_location_id": str(data.get("location_id", "")),
		"visited_locations": data.get("visited_locations", []),
		"visit_stack": data.get("visit_stack", []),
	}
	if not scene_manager.restore(scene_state, scene_errors):
		load_completed.emit(false, scene_errors[0] if scene_errors.size() > 0 else "地点恢复失败")
		return false

	_clock_minutes = float(data.get("game_clock_minutes", float(START_CLOCK_MINUTES)))

	var target := str(data.get("location_id", scene_manager.get_start_location_id()))
	if not scene_manager.enter_location(target, false):
		load_completed.emit(false, "恢复地点失败: %s" % target)
		return false

	if player_controller != null and player_controller.has_method("restore_view"):
		player_controller.restore_view(data.get("player_view", {}))

	load_completed.emit(true, "已恢复到 %s" % scene_manager.get_location_name(target))
	return true


func save_game() -> bool:
	if not is_ready:
		save_completed.emit(false, "服务尚未就绪")
		return false

	var payload := {
		"location_id": scene_manager.get_current_location_id(),
		"world_id": world_manager.get_current_world_id(),
		"visited_locations": scene_manager.get_visited_locations(),
		"world_change_records": world_manager.get_change_log(),
		"triggered_events": event_manager.get_sequence(),
		"event_history": event_manager.get_history(),
		"event_sequence": event_manager.get_sequence(),
		"game_clock_minutes": _clock_minutes,
		"player_view": player_controller.serialize_view() if player_controller != null and player_controller.has_method("serialize_view") else {},
	}

	var result := save_manager.save(payload)
	var ok := bool(result.get("ok", false))
	save_completed.emit(ok, result.get("error", "") if not ok else "已保存进度")
	return ok


func delete_save() -> bool:
	if not is_ready:
		return false
	return bool(save_manager.delete_save().get("ok", false))


# ---------------------------------------------------------------- 导航 API

func has_save() -> bool:
	if not is_ready:
		return false
	return save_manager.has_save()


func go_to(location_id: String) -> bool:
	if not is_ready:
		return false
	return scene_manager.enter_location(location_id, true)


func go_back() -> bool:
	if not is_ready:
		return false
	return scene_manager.go_back()


func get_current_location_id() -> String:
	if not is_ready:
		return ""
	return scene_manager.get_current_location_id()


func get_current_world_id() -> String:
	if not is_ready:
		return ""
	return world_manager.get_current_world_id()


# ---------------------------------------------------------------- 时钟

func get_clock_minutes() -> float:
	return _clock_minutes


func get_clock_text() -> String:
	var total := int(_clock_minutes) % 1440
	var hours: int = total / 60
	var minutes: int = total % 60
	return "%02d:%02d" % [hours, minutes]


## 世界已经发生过变化的次数，用于 UI 或测试判定。
func get_world_change_count() -> int:
	if not is_ready:
		return 0
	return world_manager.get_change_count()
