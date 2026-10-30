# COMET 第一轮系统整合修复报告

**基准**：`f9f5db5`（集成一致性审查）
**本轮范围**：门出入口、门级落点、交互距离、室外立面
**未做**：黑暗区域连续穿越、现实切换、NPC（属第二轮）

---

## 一、修改文件清单

| 文件 | 改动 |
| --- | --- |
| `core/hotspot.gd` | 新增 `use_target_spawn` / `target_spawn` / `target_yaw_deg` |
| `core/interaction_manager.gd` | 新增 `MAX_INTERACT_DISTANCE = 2.5`，聚焦与激活双重校验 |
| `scenes/main.gd` | 新增 `_pending_spawn` 挂起机制；exit 分支写入、`_on_location_entered` 消费 |
| `tools/house/house_party.gd` | 三扇门携带各自落点与朝向；餐桌热点位置上移 |
| `tools/scene_content.gd` | `DoorToInterior` 改指 `party_house` + 落点；立面改 13.4×9.4；移除旧桥接热点；窗/门牌/灯/树位置对齐 |
| `data/locations.json` | `house_exterior` 出口目标改 `party_house`；spawn 改到门廊外 |
| `tests/door_connection_test.gd` | **新增** 37 条断言 |
| `tests/acceptance_test.gd` / `fps_input_test.gd` / `player_movement_test.gd` | 聚焦测试站位改为走近热点 |
| `scenes/locations/*.tscn` | 构建器重新生成 |

未改动：`SceneManager`、`EventManager`、`WorldManager`、`SaveManager`、`PlayerController`、`scene_builder.gd`。

---

## 二、任务 A：修复返回入口

`house_exterior` 的 `DoorToInterior`：

```
改前：target = "living_room"   显示名「回屋的门」
改后：target = "party_house"   显示名「前门」+ 门级落点 (0, 0.25, 1.60) yaw 180°
```

同时移除 `ExitToPartyHouse`。它是在 `party_house` 尚无正式回屋入口时加的桥接——玩家走向「另一栋房子的前门」其实会回到自己家，语义是错的。`DoorToInterior` 现在直接通向新住宅，桥接不再需要。

`living_room` **未删除**，仅不再被新住宅引用。它的 8 处依赖（数据、3 个测试、构建器）全部保留。

---

## 三、任务 B：门级落点

### 3.1 数据结构

采用「热点携带落点」，而非给 `SceneManager` 加参数：

```gdscript
# core/hotspot.gd
@export var use_target_spawn: bool = false
@export var target_spawn: Vector3 = Vector3.ZERO
@export var target_yaw_deg: float = 0.0
```

```gdscript
# scenes/main.gd —— 挂起—消费
_on_hotspot_activated(exit):
    if spot.use_target_spawn: _pending_spawn = spot.target_spawn; _pending_yaw_deg = ...
    go_to(target)

_on_location_entered:
    if _pending_spawn != null: reset_to_spawn(_pending_spawn); 设 yaw; 清空
    else: reset_to_spawn(地点 spawn)      # 读档 / go_back / 首次开局
```

**为什么这样做**：`enter_location()` 的签名与所有既有调用（`go_back`、读档、6 个测试文件）完全不变，`go_back` 的地点栈机制也没有被触碰。

### 3.2 三扇门的实际坐标与朝向

| 门 | 门位置（室内） | 目标 | 落点 | 朝向 | 朝向含义 |
| --- | --- | --- | --- | --- | --- |
| 前门 FrontDoor | (0, 1.15, 0) | house_exterior | (0, 0.05, −2.60) | 0° | 面朝 −Z（前院/车道） |
| 侧门 SideDoor | (6.55, 1.15, 2.0) | house_exterior | (8.60, 0.05, 2.00) | −90° | 面朝 +X（东侧院） |
| 露台门 PatioDoor | (−4.0, 1.15, 9.25) | house_exterior | (−4.00, 0.05, 11.00) | 180° | 面朝 +Z（后院深处） |
| 回屋门 DoorToInterior | (0, 1.15, −0.05) | party_house | (0, 0.25, 1.60) | 180° | 面朝 +Z（屋内） |

朝向换算依据：`PlayerController` 的 forward 为 −Z，故 yaw=0 面朝 −Z、−90° 面朝 +X、180° 面朝 +Z。

落点全部落在 `house_exterior` 的地面（顶面 y=0）上，且避开该场景的建筑、车、路缘。

### 3.3 互通性

三个出口都通向 `house_exterior`，回来时统一走 `DoorToInterior`（前门）。**这是当前建筑只有一个回屋入口的现实**——侧门/露台门外没有独立的回屋门，玩家要从侧院绕回前门。

这不是遗漏：真正的多入口需要室外侧门与后门，属第二轮/后续。

---

## 四、任务 C：交互距离

| 项 | 值 |
| --- | --- |
| 射线长度 | 60.0 m（**保留**，它同时承担遮挡判定） |
| 最大交互距离 | **2.5 m**（设计初值，未按手感调过） |
| 计算基准 | 相机 `global_position` 到热点 `global_position` |

三处生效点：

1. `_update_focus()`：`dist <= env_distance` 之外增加 `dist <= MAX_INTERACT_DISTANCE`（不满足则不显示提示）
2. `activate_focused()`：二次校验 `_within_reach()`，不满足则清空焦点并返回 false（**防止「提示已消失但仍能隔空按 E」**）
3. 玩家入口只有 `activate_focused()` 一条（E 键与左键都经 `_try_interact`），因此双入口都被覆盖

`activate()`（程序化接口）刻意不校验距离，供测试使用——玩家路径永远到不了这里，这条边界在代码注释里写明。

---

## 五、任务 D：室外立面

| 项 | 改前 | 改后 |
| --- | --- | --- |
| `HouseBody` | 6.6 × 3.2 × 5.2，中心 z 4.20 | **13.4 × 3.2 × 9.4**，中心 z 4.70 |
| `Roof` | 7.4 × 0.35 × 6.0 | 14.2 × 0.35 × 10.2 |
| 前墙 | z = 1.6 | **z = 0**（与 party_house 前门平面重合） |
| 门廊 | z −0.75~1.85 | **z −2.20~0**，顶面 0.10 |
| 台阶 | StepA / StepB | **删除**（门廊直接下到地面，一级 0.10） |
| 窗 | (±2.15, 1.65, 1.55) | (±3.50, 1.85, −0.02)，嵌在前墙 |
| 门牌 | z 1.50 | z −0.13 |
| 门廊灯 | z 1.30 | z −0.22 |
| 树 | 两棵原在 (−5.5,3.5)/(5.8,4.2) | 移到 (−9.5,3.5)/(9.8,4.2)（原位置会落进扩大的室内） |

未拉伸：宽度 13.4 与高度 3.2 都按实际建筑取值，屋顶仅为出檐 0.4。

---

## 六、测试结果

```
door_connection_test     PASS=37  FAIL=0   （新增）
party_house_test         PASS=54  FAIL=0
wall_geometry_test       PASS=24  FAIL=0
player_movement_test     PASS=34  FAIL=0
fps_input_test           PASS=29  FAIL=0
acceptance_test          PASS=57  FAIL=0
v2_p0_test               PASS=13  FAIL=0
                         —— 248 条断言，0 失败
主场景 headless 200 帧：0 error / 0 warning
```

`door_connection_test` 覆盖：三扇门落点互不相同、回屋目标正确、落点不嵌墙、三扇门朝向互不相同、近距可聚焦、远距不聚焦、远距不可激活、隔墙不可交互。

### 测试过程中修正的三处测试自身问题

| 问题 | 现象 | 修法 |
| --- | --- | --- |
| 焦点断言依赖时序 | headless 下节点 `_process` 不保证落在等待窗口内，读到的是「没更新」而非「判定不通过」 | 断言前显式调用 `_update_focus()` |
| 站位离热点过远 | 三条旧测试沿用「远距离也能聚焦」的假设，加了 2.5 m 上限后全部失败 | 改为走近热点；用四方向探测避开热点碰撞盒（车、邮箱的盒子比 1.2 m 大） |
| `DiningTableSpot` 嵌在桌体内 | 热点原位置 (1.0, 0.85, 6.5) 落在桌体内部（桌面顶 0.95），射线先命中桌子 | 上移到 (1.325, 1.15, 6.48)，浮在桌面上方 |

**没有通过降低断言强度来换取通过。** 248 条断言总数比上一轮（212）多 36 条。

---

## 七、真实窗口验收

`DisplayServer = Windows`，AMD Radeon 530，OpenGL 3.3 Compatibility。

```
起点(玄关)   (0.0, 0.2, 1.6) yaw=0
前门出去     (0.0, 0.000391, -2.6) yaw=0    地点=house_exterior
前门回来     (0.0, 0.2, 1.6) yaw=-180       地点=party_house
侧门出去     (8.6, 0.000391, 2.0) yaw=-90   地点=house_exterior
侧门回来     (0.0, 0.2, 1.6) yaw=-180       地点=party_house
露台出去     (-4.0, 0.000391, 11.0) yaw=-180 地点=house_exterior
露台回来     (0.0, 0.2, 1.6) yaw=-180       地点=party_house
近距交互     focused=DiningTableSpot 距离=1.75
远距交互     focused=null            距离=6.44
fps=39
```

三扇门落点各不相同、朝向各异、往返均正确；近距聚焦、远距失效；无位置或朝向突变（室内恒为 (0, 0.2, 1.6)，室外按门区分）。

---

## 八、未解决与未实测

| # | 项 | 说明 |
| --- | --- | --- |
| 1 | **侧门/露台门外没有独立回屋门** | 玩家要从侧院/后院绕回前门。真正的多入口需要室外侧门与后门，属后续 |
| 2 | 2.5 m 交互距离未按手感调过 | 设计初值，需实际玩后判断偏紧还是偏松 |
| 3 | `living_room` 仍是可进入地点 | 仅不再被新住宅引用；它自己的 `exits` 仍指 `house_exterior` |
| 4 | 楼梯/台阶简化 | 室内 0.20 → 门廊 0.10 → 地面 0 的两级高差由碰撞自然处理，未做台阶模型 |
| 5 | GUI 探针曾误判为崩溃 | 实为探针 `_process` 写成 `return true` 导致 SceneTree 立即退出，与本轮功能无关 |

---

## 九、兼容性说明

| 项 | 状态 |
| --- | --- |
| 旧地点切换 | `enter_location` 签名与行为未变，`go_back` 未触碰 |
| `living_room` | 保留，测试与存档校验仍能识别 |
| 旧存档 | 若 `location_id = living_room` 仍可读取；若存的是 `house_exterior`，出生点从 (0,0.3,0) 变为 (0,0.05,−2.6)——旧存档会落在门廊外而非墙内，属改善 |
| 存档 schema | **未改动** |
