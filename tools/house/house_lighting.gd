## HouseLighting — 聚会房屋的两套灯光
##
## 提供两个世界的照明：
##   world_alpha  正常供电：各处电灯亮着，壁炉燃烧
##   world_beta   停电：电灯全灭，仅剩壁炉余烬、蜡烛、窗外月光
##
## 为什么环境（WorldEnvironment）只放一份：
##   WorldEnvironment 不受 Node.visible 控制，两套同时存在会互相覆盖。
##   两个世界的环境基调接近（室内夜晚），差异全部由灯光承担，因此只建一份放进 Shared。
##
## 坐标基于 13.0 × 9.0 m 布局，不引用 HouseParty 类常量（避免 cyclic reference）。

class_name HouseLighting
extends RefCounted

var light: HouseLight = null


func _init(light_lib: HouseLight) -> void:
	light = light_lib


func build(va: Node, vb: Node, shared: Node) -> void:
	# 共享环境：低调的环境光，保证停电时仍能辨认空间轮廓
	light.world_env(shared, Color(0.010, 0.011, 0.016), Color(0.085, 0.085, 0.105))

	# 远处邻居房屋：两个世界都亮着，是「另一个现实」的视觉锚点
	light.omni(shared, "NeighborGlow", Vector3(24.0, 3.2, -16.0),
			Color(0.70, 0.80, 1.0), 1.4, 22.0)

	_build_powered(va)
	_build_blackout(vb)


## 正常供电
func _build_powered(parent: Node) -> void:
	# 客厅落地灯
	light.omni(parent, "LampLiving", Vector3(-2.9, 1.65, -3.6),
			Color(1.00, 0.82, 0.55), 2.6, 9.0)
	# 壁炉火光
	light.omni(parent, "FireLight", Vector3(-5.9, 0.75, -1.8),
			Color(1.00, 0.55, 0.28), 2.0, 6.5)
	# 餐桌吊灯
	light.omni(parent, "DiningPendant", Vector3(0.75, 2.15, -1.8),
			Color(1.00, 0.86, 0.64), 3.0, 9.0)
	# 厨房顶灯
	light.omni(parent, "KitchenLight", Vector3(4.55, 2.3, -2.6),
			Color(0.95, 0.94, 0.88), 2.5, 9.0)
	# 走廊灯
	light.omni(parent, "HallLight", Vector3(-0.5, 2.3, 2.6),
			Color(1.00, 0.86, 0.62), 1.9, 11.0)
	# 门廊灯（从门外照进来）
	light.omni(parent, "PorchLight", Vector3(0.0, 2.35, 5.3),
			Color(1.00, 0.80, 0.50), 1.6, 8.0)
	# 露台门外的光
	light.omni(parent, "PatioLamp", Vector3(-4.0, 2.35, -5.0),
			Color(1.00, 0.78, 0.48), 1.4, 7.0)


## 停电
func _build_blackout(parent: Node) -> void:
	# 壁炉只剩余烬
	light.omni(parent, "FireEmber", Vector3(-5.9, 0.55, -1.8),
			Color(1.00, 0.42, 0.18), 0.75, 4.5)
	# 餐桌上的两支蜡烛
	light.omni(parent, "CandleNorth", Vector3(0.75, 0.95, -2.35),
			Color(1.00, 0.72, 0.40), 0.85, 4.2)
	light.omni(parent, "CandleSouth", Vector3(0.75, 0.95, -1.25),
			Color(1.00, 0.72, 0.40), 0.85, 4.2)
	# 走廊上一支蜡烛
	light.omni(parent, "CandleHall", Vector3(-0.6, 1.05, 2.6),
			Color(1.00, 0.70, 0.40), 0.55, 5.5)
	# 窗外月光
	light.sun(parent, "Moonlight", -30.0, -40.0, Color(0.55, 0.66, 0.95), 0.42)
