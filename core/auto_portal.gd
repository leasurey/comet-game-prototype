## AutoPortal — 区域触发式场景连接
##
## 与 Hotspot 的区别：
##   Hotspot 需要玩家对准并按键（显式交互）；
##   AutoPortal 只要玩家走进去就触发（地理到达）。
##
## 为什么需要它：
##   黑暗区域的穿越必须是「走过去」而不是「点一下」。用热点做入口时，
##   玩家走到路口还得按键，那一刻就已经不是穿越体验了。
##
## 触发顺序（由 main.gd 执行）：
##   1. 先按 event_kind / event_keys 求值事件（可能因此切换现实）
##   2. 再切场景并落到 target_spawn / target_yaw_deg
##   先切世界后切场景，新场景加载时就能按新现实呈现，避免闪一帧旧世界。

class_name AutoPortal
extends Area3D

signal player_entered(portal: AutoPortal)

@export var portal_id: String = ""

## 目标地点；留空表示本 portal 只触发事件、不切场景。
@export var target_location: String = ""
@export var use_target_spawn: bool = false
@export var target_spawn: Vector3 = Vector3.ZERO
@export var target_yaw_deg: float = 0.0

## 事件触发。event_kind 为空表示不求值。
## event_keys 会与规则里的 trigger 逐键比对，例如 {"area_id": "dark_far_end"}。
@export var event_kind: String = ""
@export var event_keys: Dictionary = {}

## 冷却时间（秒）：防止玩家在触发区边缘来回抖动造成连续切换。
@export var cooldown_sec: float = 1.0

var _cooling: bool = false


func _ready() -> void:
	# 关键：先关闭检测，等两帧再开。
	#
	# 原因（实测踩到）：enter_location 把新场景加入树的那一刻，玩家还停在
	# 上一场景的坐标上，要等 location_entered 信号之后才会被放到新落点。
	# 如果此时就开着 monitoring，新场景里恰好位于旧坐标附近的 portal 会立刻
	# 触发一次，玩家会被连续踢出——表现为「刚进黑暗就立刻出来了」。
	monitoring = false
	body_entered.connect(_on_body_entered)
	_enable_later()


func _enable_later() -> void:
	var t := get_tree()
	if t == null:
		monitoring = true
		return
	await t.physics_frame
	await t.physics_frame
	if is_inside_tree():
		monitoring = true


func _on_body_entered(body: Node) -> void:
	if _cooling:
		return
	# 只认玩家：AutoPortal 不应被 NPC 或掉落物触发
	if not (body is CharacterBody3D):
		return
	if not body.has_method("is_mouse_captured"):
		return
	_cooling = true
	player_entered.emit(self)
	# 用场景树计时器而非 await，避免节点在切换过程中被释放导致协程悬挂
	var t := get_tree()
	if t != null:
		await t.create_timer(cooldown_sec).timeout
	_cooling = false
