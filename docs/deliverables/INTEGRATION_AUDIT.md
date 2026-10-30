# COMET 集成一致性审查（GitHub ↔ 本地工程）

**审查时间**：2026-10-31 03:47
**审查基准**：`035e07f`（v0.4.0 住宅灰盒重建）
**审查性质**：只读。未修改任何代码 / 场景 / JSON / 测试 / 存档结构，未提交，未推送。

**结论标记**：**【代码事实】** 直接读源码 ｜ **【运行实测】** 跑过引擎 ｜ **【推测】** 推理未验证

---

## 一、版本一致性

### 1.1 实测结果

| 项 | 值 | 来源 |
| --- | --- | --- |
| 本地分支 | `main` | 【代码事实】 |
| 本地 HEAD | `035e07fbf47d2854f1193d017298faa294a6a1a6` | 【代码事实】 |
| 工作区 | 干净（无未提交改动） | 【代码事实】 |
| `origin/main` | `035e07f` | 【代码事实】 |
| `git diff HEAD origin/main` | **无差异** | 【代码事实】 |
| 文件数 | 本地 90 / 远端 90 | 【代码事实】 |

> 注：`git ls-remote origin main` 本次因 `OpenSSL: unexpected eof` 失败，属网络抖动。
> 版本判定以已 fetch 到本地的 `origin/main` 引用为准。

### 1.2 `core/player_controller.gd` 核对

| 检查项 | 结果 |
| --- | --- |
| 继承类型 | `class_name PlayerController` / `extends CharacterBody3D` |
| WASD 移动 | **存在**：`move_left/right/forward/back` 经 `Input.get_vector` → `velocity.x/z` → `move_and_slide()` |
| 重力 | `velocity.y -= gravity * delta`，含 `MAX_FALL_SPEED` 截断 |
| 行数 | 228 |
| 本地 blob SHA | `d2453820a8e03c7ba807f3a8802fcfed832cd2d3` |
| 远端 blob SHA | `d2453820a8e03c7ba807f3a8802fcfed832cd2d3` |

**结论：一致，无漏传。实际运行版本包含完整 WASD 移动。** 【代码事实】

### 1.3 差异文件清单

**空。** 不存在漏传、旧文件覆盖、新文件未上传、场景与脚本版本不一致的情况。

---

## 二、交互系统（`core/interaction_manager.gd`）

### 2.1 实测参数

| 项 | 值 | 来源 |
| --- | --- | --- |
| 射线长度 | `RAY_LENGTH := 60.0`（米） | 【代码事实】 |
| 独立最大交互距离 | **不存在** | 【代码事实】 |
| 热点层 | `HOTSPOT_LAYER_MASK := 2`（Area3D） | 【代码事实】 |
| 环境层 | `ENVIRONMENT_LAYER_MASK := 1`（StaticBody3D） | 【代码事实】 |
| 遮挡判定 | 双射线比距离：`dist <= env_distance` | 【代码事实】 |
| 激活距离检查 | **无**。`activate_focused()` 只判断 `is_interactable()` | 【代码事实】 |

### 2.2 调用链

```
每帧 _process → _update_focus()
  ├─ 从相机原点沿 -basis.z 打 60 m
  ├─ env 射线（layer 1 / bodies）→ env_distance
  ├─ spot 射线（layer 2 / areas）→ dist
  └─ 若命中 Hotspot 且 is_interactable 且 dist <= env_distance → set_focused_internal

输入 → scenes/main.gd::_unhandled_input
  ├─ E（ACTION_INTERACT）→ _try_interact() → activate_focused()
  └─ 左键按下
       ├─ 鼠标已捕获 → _try_interact()
       └─ 未捕获 → 仅恢复捕获，不触发交互
```

### 2.3 三个问题

| # | 问题 | 影响 |
| --- | --- | --- |
| I1 | **60 米射线且无最大交互距离** | 站在客厅能聚焦 60 米外门廊的热点，只要在视线内且无遮挡。第一人称近距离交互的体感会崩坏 |
| I2 | **`activate_focused()` 不校验距离** | 即使聚焦时距离合规，激活瞬间玩家已走远也不会被拦 |
| I3 | **左键仍可直接触发交互** | 鼠标捕获状态下点击即交互，与 E 键并存。不算 bug，但需确认是否符合设计 |

**注意**：I1 与 I2 不同。I1 是「能看见就能聚焦」，I2 是「已聚焦的不会因走远而失效」。

### 2.4 改造方案（不实施）

```
1. 新增 MAX_INTERACT_DISTANCE := 2.5（近距交互常规值）
2. _update_focus()：在 dist <= env_distance 之外增加 dist <= MAX_INTERACT_DISTANCE
3. activate_focused()：二次校验
   if origin.distance_to(_focused.global_position) > MAX_INTERACT_DISTANCE: return false
4. 把三个距离参数提到 const，便于按房间尺度调整
```

射线长度本身**不必改**——它同时承担遮挡判定，缩短会让 60 米外的墙不再参与遮挡比较。正确做法是保留 60 m 射线、只加距离闸门。

---

## 三、门与空间连接

### 3.1 实测连接图

```
party_house ──FrontDoor────┐
            ──SideDoor─────┼──→ house_exterior ──DoorToInterior──→ living_room  ← 错误
            ──PatioDoor────┘         │            ──ExitToPartyHouse──→ party_house
                                     └──RoadToDark──→ dark_road
dark_road ──back──→ house_exterior
```

| 门 | 所在场景 | 目标 | 问题 |
| --- | --- | --- | --- |
| FrontDoor | party_house | house_exterior | 与另两扇门共用同一落点 |
| SideDoor | party_house | house_exterior | 同上 |
| PatioDoor | party_house | house_exterior | 同上（露台门本不该通向房屋正门方向） |
| DoorToInterior | house_exterior | **living_room** | **指向旧客厅，不是 party_house** |
| ExitToPartyHouse | house_exterior | party_house | 语义是「另一栋房子」，实际是新宅本体 |
| RoadToDark | house_exterior | dark_road | 正常 |
| back | dark_road | house_exterior | 正常 |

### 3.2 四个结构性问题

| # | 问题 | 说明 |
| --- | --- | --- |
| D1 | **从新宅出去无法正常回来** | 唯一回 `party_house` 的通路是 `ExitToPartyHouse`（"另一栋房子的前门"）。玩家从自家前门出去，必须绕到"别人家"才能回来 |
| D2 | **`DoorToInterior` 通向 `living_room`** | 那是第一阶段遗留的独立客厅，与 `party_house` 无空间关系 |
| D3 | **三扇门共用同一 spawn** | `locations.json` 的 spawn 是**地点级**常量 `house_exterior: [0, 0.3, 0]`。从侧门出去和从前门出去，落到同一个点，且朝向都是 `yaw: 0.0` |
| D4 | **返回靠访问栈而非门口** | `go_back()` 弹出栈顶地点，落到该地点 spawn。若玩家从侧门出去再用"返回"回来，会出现在前门位置 |

### 3.3 关于「不得仅用同一个场景出生点解决所有门的问题」

当前实现正是被禁止的做法。【代码事实】

### 3.4 改造方案（不实施）

需要引入**门级出口定义**，两种可选：

**方案 A：扩展 `locations.json` 的 exits**

```json
"exits": [
  { "target": "house_exterior", "label": "走出前门",
    "exit_id": "front", "spawn_at": [0, 0.0, -0.60], "yaw": 3.14159 }
]
```

对方场景需要能按 `exit_id` 反查落点：`house_exterior` 增加 `"entries": [{ "from": "party_house", "exit_id": "front", "spawn": [...], "yaw": ... }]`。

**方案 B：热点直接携带出/入口 Transform**（改 `Hotspot` 增加字段）

```gdscript
@export var target_spawn: Vector3 = Vector3.ZERO
@export var target_yaw: float = 0.0
```

由 `_on_hotspot_activated` 直接调用 `scene_manager.enter_location_at(target, spawn, yaw)`，绕过地点级 spawn。

**倾向 B**：热点本身就在门口，由它携带落点最直接；不用改 JSON 的 exits 结构，也不依赖 exit_id 字符串配对。

两种方案都需要 `SceneManager` 新增「带落点参数进入」的入口，保留现有 `enter_location` 不动以兼容测试。

---

## 四、黑暗区域

### 4.1 实测状态机

| 项 | 现状 | 来源 |
| --- | --- | --- |
| 进入方式 | 地点切换（`RoadToDark` 热点 → `dark_road` 场景） | 【代码事实】 |
| 触发规则 | `evt_cross_dark_road`：`trigger.kind = enter_location`，`location_id = dark_road` | 【代码事实】 |
| 世界切换时机 | **进入 `dark_road` 的那一刻** | 【代码事实】 |
| 重复触发 | `once: true`，只切一次 | 【代码事实】 |
| 离开方式 | `back` 热点（display_name「原路返回」）→ `house_exterior` | 【代码事实】 |
| 是否连续空间 | **否**，是独立场景 + 热点传送 | 【代码事实】 |

### 4.2 为什么玩家需要点击返回

因为 `dark_road` 是一个**封闭的独立场景**：尽头没有可通行的地理出口，只有 `back` 热点。玩家走到路尽头，只能对着那块"原路返回"按 E。这不是设计选择，是场景结构的必然结果。【代码事实】

### 4.3 与电影逻辑的差距

| 电影 | 当前实现 |
| --- | --- |
| 走进黑暗、走回来、发现不对 | 一踏进黑暗，世界已切换；玩家在黑暗中就已经处于 beta |
| 变化归因于「我可能走错了」 | 变化归因于「我穿过了那条路」 |
| 「原路返回」不可靠 | 「原路返回」是确定性热点，必定回到 `house_exterior` |

**关键差异不是"有没有黑暗区域"，而是"变化发生在哪一刻"。** 【推测】

### 4.4 改造方向（不实施）

| 目标 | 做法 |
| --- | --- |
| 连续空间中的实际穿越 | `dark_road` 不再是独立地点，而是 `house_exterior` 街道西端的地理延伸；走进去只是走远，不换场景 |
| 切换时机 | 从「进入」改为「**返回时**」：玩家从街道西端折返、跨过某个门槛线（`Area3D`）时才触发世界变更 |
| 避免重复触发 | 设 `once` + 状态标记（`EventManager` 已有 `once`），并记录「已穿越」标志；再穿只触发氛围（风声消失、灯不亮），不再切世界 |
| 保留可识别性 | 黑暗段要有参照物（路灯残影、路缘、远处窗光），否则玩家会以为被传送 |

具体可用两个 `Area3D` 门槛：`EnterDark`（设定方向状态）与 `LeaveDark`（判定是否从同一侧返回）。

---

## 五、旧场景依赖关系

### 5.1 四个场景的实际地位

| 场景 | 状态 | 被谁依赖 |
| --- | --- | --- |
| `party_house` | **正式场景**（新宅本体） | `start_location`、`door.target_location`、6 个测试 |
| `house_exterior` | **仍在使用，但与新宅不一致** | `party_house` 三扇门、`dark_road.back`、6 个测试 |
| `dark_road` | **仍在使用**，但结构与电影逻辑不符 | `house_exterior.RoadToDark`、测试 |
| `living_room` | **旧测试场景残留** | `house_exterior.DoorToInterior`、3 个测试 |

### 5.2 `living_room` 的完整依赖清单

| 位置 | 用途 |
| --- | --- |
| `data/locations.json:29,31` | 地点注册 |
| `data/locations.json:67` | `house_exterior` 的 `DoorToInterior` 指向它 |
| `tests/acceptance_test.gd:201` | 断言地点表包含 `living_room` |
| `tests/acceptance_test.gd:556,568` | 存档损坏测试用 `living_room` 作已知地点 |
| `tests/player_movement_test.gd:19,197` | 撞墙测试在该场景执行 |
| `tests/v2_p0_test.gd` ×4 | 事件触发测试用 `enter_location: living_room` |
| `tools/scene_builder.gd:43` | 构建任务 |
| `tools/scene_content.gd:199,474` | 构建函数 + 门外连接 |

**结论：`living_room` 有 8 处依赖，其中 3 个测试文件共 7 处断言直接用它的 id。删除会连带破坏测试，且存档校验（`save_manager` 检查 `known_locations`）会让旧存档失效。** 【代码事实】

### 5.3 `house_exterior` 的尺寸矛盾

| 项 | 值 |
| --- | --- |
| `house_exterior` 的 `HouseBody` | **6.6 × 3.2 × 5.2**（x × y × z） |
| 实际住宅 `party_house` | **13.4 × 9.4** |

从室内走出前门，看到的立面只有实际房子的一半多一点。**玩家会立刻察觉「这不是我刚待的房子」。** 【代码事实】

---

## 六、问题优先级

| 优先级 | 编号 | 问题 | 理由 |
| --- | --- | --- | --- |
| **P0** | D1+D2 | 从新宅出门回不来，回屋门通向旧客厅 | 直接阻断核心动线，玩家会迷路 |
| **P0** | I1+I2 | 交互无最大距离 | 60 米可交互，第一人称体感失效 |
| **P0** | D3+D4 | 三扇门共用 spawn，返回落到错误位置 | 穿门前后位置/朝向不连续 |
| **P1** | D5 | `house_exterior` 立面尺寸与新宅不符 | 出门即出戏 |
| **P1** | K1 | 黑暗区域进入即切世界，且需点击返回 | 与电影核心机制不符 |
| **P2** | L1 | `living_room` 旧场景残留 | 有 8 处依赖，不能贸然删 |
| **P2** | R1 | README 与实际不符 | 文档问题，不影响运行 |

---

## 七、推荐改造顺序

**第 1 步：修通动线（P0，改动最小、收益最大）**

1. `house_exterior.DoorToInterior` 的目标从 `living_room` 改为 `party_house`
2. 为三扇门引入独立落点（方案 B：热点携带 `target_spawn` / `target_yaw`）
3. `SceneManager` 新增 `enter_location_at()`，保留原 `enter_location` 兼容测试

> 做完这步，玩家至少能「出去—回来」闭环。这是当前最痛的体验断点。

**第 2 步：修交互距离（P0，独立、低风险）**

4. `InteractionManager` 加 `MAX_INTERACT_DISTANCE`，聚焦与激活双重校验

**第 3 步：对齐室外立面（P1）**

5. `house_exterior` 的 `HouseBody` 改为 13.4 × 9.4，门洞位置与 `party_house` 前门对齐

**第 4 步：黑暗区域连续化（P1，改动最大，建议最后做）**

6. `dark_road` 并入 `house_exterior` 的地理延伸
7. 切换时机从「进入」改为「返回」
8. 加「已穿越」标志防重复

**第 5 步：清理旧场景（P2，需先解耦测试）**

9. 把 3 个测试对 `living_room` 的依赖改到 `party_house`
10. 再将 `living_room` 从 `locations.json` 摘除（**保留 .tscn 与构建函数，不删文件**）
11. 注意：摘除后旧存档若含 `living_room` 会读档失败，需加迁移或容错

---

## 八、本轮状态

- ✅ 版本一致性、交互系统、门连接、黑暗区域、旧场景依赖全部核实
- ⏸ **未修改任何文件**（本报告为唯一新增产物）
- ⏸ 未提交、未推送
- 等待确认后再实施

**三条最该先看的**：D1+D2（出门回不来）、I1（60 米可交互）、D3（三扇门同一落点）。
