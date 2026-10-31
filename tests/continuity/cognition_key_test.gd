## ContinuityCognitionKeyTest — CT-019 认知钥匙断供修复
##
## 用法：godot --headless --script res://tests/continuity/cognition_key_test.gd
##
## K1 亲眼检查门上的便签（真实 examine 处理链）→ fact_sticky_note 入认知
## K2 便签话题 kevin_sticky 解锁（对话闸门吃到真实钥匙）
## K3 穿越黑路尽头（真实 AutoPortal 处理链）→ fact_dark_road 入认知（observe）
## K4 黑路话题 mike_dark 解锁
## K5 来源标注正确（inspect / observe），世界切换不自动授予
##
## 修复前：这两个 gate 事实全项目无人授予，9/29 对话节点永久锁死；
## 旧测试手工 cognition.learn 注入钥匙掩盖断供——本测试一律走真实入口
## （hotspot_activated / portal_entered 的真实 handler），禁止手工 learn。

extends SceneTree

var _pass := 0
var _fail := 0
var _lines: Array = []
var _svc = null
var _main = null
var _steps: Array = []
var _idx := 0
var _ticks := 0
var _t_state := 0
var _reporting := false


func _initialize() -> void:
	print("=== COMET continuity cognition key test ===")
	_svc = root.get_node_or_null("GameServices")
	if _svc == null:
		print("[FAIL] GameServices 不可用")
		quit(1)
		return
	_steps = [
		Callable(self, "step_setup"),
		Callable(self, "step_k1_k2_sticky_note"),
		Callable(self, "step_k3_k4_dark_road"),
		Callable(self, "step_k5_sources"),
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
		if _ticks > 400:
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


func _find_hotspot(n: Node, hname: String) -> Hotspot:
	for c in n.get_children():
		if c is Hotspot and c.name == hname:
			return c as Hotspot
		var f := _find_hotspot(c, hname)
		if f != null:
			return f
	return null


func _find_portal(n: Node, pid: String) -> AutoPortal:
	for c in n.get_children():
		if c is AutoPortal and (c as AutoPortal).portal_id == pid:
			return c as AutoPortal
		var f := _find_portal(c, pid)
		if f != null:
			return f
	return null


func _has_entry(speaker: String, node_id: String) -> bool:
	for n in _svc.dialogue_manager.get_entry_nodes_for(speaker):
		if str((n as Dictionary).get("id", "")) == node_id:
			return true
	return false


func step_setup() -> bool:
	if _t_state == 0:
		var sm = _svc.save_manager
		sm.use_test_path("cognition_key")
		sm.delete_save()
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_t_state = 1
		return false
	return _ticks >= 12


func step_k1_k2_sticky_note() -> bool:
	_check(not _svc.cognition.knows("fact_sticky_note"), "K1 前置：初始不知道便签")
	_check(not _has_entry("kevin", "kevin_sticky"), "K2 前置：便签话题锁定")
	var inst = _svc.scene_manager.get_current_instance()
	var spot := _find_hotspot(inst, "StickyNote")
	_check(spot != null, "K1 便签热点存在（场景已含）")
	if spot == null:
		return true
	_check(spot.grants_fact == "fact_sticky_note", "K1 便签热点声明语义事实",
		spot.grants_fact)
	# 真实交互处理链（debug_activate 是测试钩子，走的仍是 hotspot_activated
	# → main._on_hotspot_activated 的正式派发路径；不直接调 cognition.learn）
	_svc.interaction_manager.debug_activate(spot)
	_check(_svc.cognition.knows("fact_sticky_note"), "K1 亲眼检查后知道便签（真实链路）")
	_check(_svc.cognition.knows("fact_inspected_StickyNote"), "K1 inspect 事实照常写入")
	_check(_has_entry("kevin", "kevin_sticky"), "K2 便签话题解锁")
	return true


func step_k3_k4_dark_road() -> bool:
	_check(not _svc.cognition.knows("fact_dark_road"), "K3 前置：初始不知道黑路")
	_check(not _has_entry("mike", "mike_dark"), "K4 前置：黑路话题锁定")
	# 真实场景链：进屋外 → 进黑路 → 触发尽头 portal（真实 handler）
	_svc.go_to("house_exterior")
	_svc.go_to("dark_road")
	var inst = _svc.scene_manager.get_current_instance()
	var portal := _find_portal(inst, "dark_far_end")
	_check(portal != null, "K3 黑路尽头 portal 存在")
	if portal == null:
		return true
	_main._on_portal_entered(portal)
	_check(_svc.cognition.knows("fact_dark_road"), "K3 穿越黑路后知道黑路（真实链路）")
	_check(_has_entry("mike", "mike_dark"), "K4 黑路话题解锁")
	# 穿越应已切现实（副产物一致性）
	_check(_svc.get_current_world_id() != "world_alpha",
		"K3 穿越伴随现实切换", _svc.get_current_world_id())
	return true


func step_k5_sources() -> bool:
	var s1: Dictionary = _svc.cognition.get_source("fact_sticky_note")
	_check(str(s1.get("source_kind", "")) == "inspect", "K5 便签来源=inspect",
		str(s1.get("source_kind")))
	var s2: Dictionary = _svc.cognition.get_source("fact_dark_road")
	_check(str(s2.get("source_kind", "")) == "observe", "K5 黑路来源=observe",
		str(s2.get("source_kind")))
	return true


func step_report() -> bool:
	if _reporting:
		return true
	_reporting = true
	print("")
	for l in _lines:
		print(l)
	print("")
	print("=== COGNITION KEY RESULT: PASS=%d FAIL=%d ===" % [_pass, _fail])
	var gs = root.get_node_or_null("GameServices")
	if gs != null:
		gs.shutdown_audio()
	quit(1 if _fail > 0 else 0)
	return true
