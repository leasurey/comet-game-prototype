# COMET — 总体架构（MASTER_ARCHITECTURE）

> 本文件描述**当前实际代码**的架构，与 `core/`、`autoload/`、`data/` 逐一对齐。
> 标注规则：`[代码]` 从源码读取；`[设计]` 设计约定；`[缺失]` 目标应存在但当前未实现。
> 与 `MASTER_DEPENDENCY_MAP.md`（调用链细节）互补，本文件偏重分层与职责边界。

---

## 1. 概览

| 项 | 值 | 来源 |
| --- | --- | --- |
| 引擎 | Godot 4.7.2-stable | `[代码]` project.godot `features` |
| 渲染 | GL Compatibility（OpenGL 3.3 前向） | `[代码]` `renderer/rendering_method="gl_compatibility"` |
| 主场景 | `res://scenes/main.tscn` | `[代码]` |
| 版本 | 0.6.0 | `[代码]` |
| 唯一 autoload | `GameServices` | `[代码]` |
| 物理频率 | 30 ticks/s | `[代码]` `physics_ticks_per_second=30` |
| GDScript 警告 | 开启（当错误处理） | `[代码]` `gdscript/warnings/enable=true` |
| 分支 | `recovery/master-rebuild` | `[代码]` git |
| 地点数 | 4（party_house / living_room / house_exterior / dark_road） | `[代码]` locations.json |
| 现实数 | 2（world_alpha / world_beta） | `[代码]` worlds.json |

**核心定位**：一个「以电影《Coherence》为叙事参考」的第一人称悬疑原型。当前是**可运行的灰盒垂直切片**——自由移动 + 中心射线交互 + 门级场景连接 + 黑暗区域穿越驱动的现实切换 + 可靠存档，但**尚未**具备完整叙事、NPC、音频、手机、多结局等成品的量级。

---

## 2. 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│ 表现层（场景节点）                                              │
│   scenes/main.tscn + main.gd     装配、输入路由、信号桥接      │
│   scenes/locations/*.tscn        4 个地点（GameLocation 实例）│
│   scenes/ui/hud.tscn             UI 根（ui_manager 代码构建） │
└──────────────────────────┬──────────────────────────────────┘
                           │ 调用（单向向下）
┌──────────────────────────▼──────────────────────────────────┐
│ 编排层（唯一 autoload）                                        │
│   GameServices                    启动/bootstrap/new_game/    │
│                                   save/continue/时钟/服务注入 │
└──────────────────────────┬──────────────────────────────────┘
                           │ 依赖注入（不跨模块直连）
┌──────────────────────────▼──────────────────────────────────┐
│ 核心域层（core/）                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ SceneManager │  │ WorldManager│  │ EventManager │          │
│  │ 地点/返回栈  │  │ 当前现实    │  │ 事件判定+历史│          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ SaveManager │  │ DataValidator│ │ DataLoader  │          │
│  │ 原子读写迁移 │  │ 交叉校验     │  │ 文件读取     │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │Interaction  │  │PlayerCtl    │  │Hotspot/     │          │
│  │Manager 射线 │  │CharacterBody│  │Location/    │          │
│  │             │  │+视角        │  │AutoPortal   │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│  L0 服务：EventBus / TimeService / RngService / ConditionEvaluator │
│  UI：ui_manager.gd                                            │
└──────────────────────────┬──────────────────────────────────┘
                           │ 只读
┌──────────────────────────▼──────────────────────────────────┐
│ 数据层（data/，纯 JSON，不包含逻辑）                           │
│   worlds.json / locations.json / world_transitions.json / events.json │
└─────────────────────────────────────────────────────────────┘
```

**依赖方向规则** `[设计]`：上层可调用下层；域层之间不跨模块直连，统一经 `GameServices` 注入引用。`EventManager` 判定结果只交给 `WorldManager` 执行，判定与执行分离。

---

## 3. 模块职责表

| 模块 | 负责 | 不负责 | 谁调用它 | 它调用谁 | 状态 |
| --- | --- | --- | --- | --- | --- |
| `GameServices` | 启动编排、服务注入、new_game/save/continue/go_to、整数 tick 时钟 | 不直接改世界/事件细节 | main.gd | 全部 Manager | `[代码]` 正常 |
| `SceneManager` | 地点加载、`enter_location`、返回栈（去重+上限16）、spawn、`reset_session` | 不管理世界/事件 | GameServices、main、测试 | DataLoader、EventManager(注入) | `[代码]` 正常 |
| `WorldManager` | 当前现实 ID、变更历史、`apply_transition` | 不判定事件（只执行） | EventManager、GameServices | 无 | `[代码]` 正常 |
| `EventManager` | 事件定义/触发白名单/`evaluate`/历史 | 不直接改世界（交给 WorldManager） | SceneManager、main、测试 | WorldManager、ConditionEvaluator | `[代码]` 正常 |
| `SaveManager` | 原子写入、v1→v2 迁移、损坏隔离、测试路径 | 不负责序列化内容 | GameServices | DataLoader | `[代码]` 正常 |
| `DataValidator` | 四份 JSON 交叉校验 | 不读文件（纯静态） | GameServices、测试 | 无 | `[代码]` 正常 |
| `InteractionManager` | 相机中心射线、2.5m 距离、遮挡判定、focus/activate | 不处理门/场景切换 | main、测试 | Hotspot | `[代码]` 正常 |
| `PlayerController` | `CharacterBody3D`：WASD、yaw/pitch、重力、reset/restore/serialize_view | 不判热点 | main、测试 | 无 | `[代码]` 正常 |
| `Hotspot` | 热点交互、材质隔离聚焦 | 不执行剧情 | InteractionManager、main | 无 | `[代码]` 正常 |
| `GameLocation` | `apply_world` 变体切换（返回 bool）、热点收集 | 不生成场景 | SceneManager | Hotspot | `[代码]` 正常 |
| `AutoPortal` | 走进 Area3D 触发（换场景/触发事件），首两帧防误触发 | 不按键交互 | main（连信号） | 无 | `[代码]` 正常 |
| `EventBus` | 跨模块信号总线 | 无业务逻辑 | GameServices 持有 | 无 | `[代码]` 已接 UI 订阅 |
| `TimeService` | 整数 tick 时钟（替代浮点） | — | GameServices | 无 | `[代码]` 正常 |
| `RngService` | 种子化伪随机 | — | GameServices | 无 | `[代码]` 正常 |
| `ConditionEvaluator` | 事件条件谓词求值 | — | EventManager | 无 | `[代码]` 正常 |
| `UIManager` | HUD 代码构建、确认框、信号 | 不改世界数据 | main | 无 | `[代码]` 正常 |

---

## 4. 唯一状态权威（Single Source of Truth）

| 状态 | 唯一权威 | 说明 | 状态 |
| --- | --- | --- | --- |
| 当前现实 ID | `WorldManager` | 场景节点不自行决定现实变化 | `[代码]` 已统一 |
| 当前地点 ID | `SceneManager` | 返回栈与 visited 同源 | `[代码]` 已统一 |
| 玩家位置/朝向 | `PlayerController` | 存档经 `serialize_view` + `player_position` | `[代码]` 已统一 |
| 事件历史 | `EventManager` | 与 `WorldManager.change_count` 分离 | `[代码]` 已统一 |
| 存档内容 | `GameServices.save_game` 单一聚合点 | 各 Manager 只 `serialize()` | `[代码]` 已统一 |
| 玩家认知 | — | **未实现**（存档 schema 有 `known_facts` 字段但无写入逻辑） | `[缺失]` |
| NPC 状态 | — | **未实现** | `[缺失]` |

---

## 5. 数据 Schema（4 份 JSON）

| 文件 | 结构 | 要点 |
| --- | --- | --- |
| `worlds.json` | `initial_world` + `worlds[]` | 2 个现实，加一条即扩展，数量未写死 |
| `locations.json` | `start_location` + `locations[]` | 每地点含 `spawn.position/yaw`、`exits[]`、`variants[]`、`scene` |
| `world_transitions.json` | `transitions[]` | 1 条规则：`evt_cross_dark_road`，trigger=`area_enter:dark_far_end`，alpha→beta，`once:true` |
| `events.json` | `events[]` | 2 条：`evt_cross_dark_road`、`evt_return_to_house`（后者无转移规则，见 Bug 表 BUG-015） |

---

## 6. 场景结构

```
main.tscn (Node3D, main.gd)
├── LocationContainer
├── CameraRig (CharacterBody3D, PlayerController)   ← yaw + 移动 + 重力
│   ├── Body (CollisionShape3D, 胶囊 r0.32 h1.72)
│   └── Camera3D (local y=1.62)                     ← pitch + 渲染
└── HUD (CanvasLayer, ui_manager.gd)

4 个地点场景，均含：
  Shared（不随世界变化：墙/地/共享几何）
  Environment（Variant_<world_id> 节点，随现实切换显隐）
  Hotspots（Area3D）
```

**场景由 `tools/` 离线构建**（非手写 `.tscn`）：`scene_builder.gd` 驱动 → `scene_content.gd`（3 个旧场景）或 `house/house_party.gd`（party_house）+ `lib/{geom,light,props}.gd` 生成。改场景必须改构建源码再重建，不直接改产物。

---

## 7. 测试体系（13 个，385 条断言）

分层：

| 层 | 测试 | 断言数 |
| --- | --- | --- |
| 单元（纯逻辑） | wall_geometry(24) · data_integrity(22) · save_isolation(10) · session_reset(17) · save_migration(27) | 100 |
| 集成（装配真实场景） | acceptance(59) · v2_p0(13) · door_connection(53) · dark_traverse(31) · ui_flow(12) | 168 |
| 玩法/输入 | fps_input(29) · player_movement(34) · party_house(54) | 117 |

均为 `--headless --script res://tests/*.gd` 可独立运行；存档类测试经 `use_test_path()` 隔离，不碰玩家正式存档。

---

## 8. 相对「完整游戏」的架构缺口（`[缺失]`）

以下系统在本任务书的最终目标中必须存在，但当前**完全没有对应模块**：

| 目标系统 | 现状 | 对应阶段 |
| --- | --- | --- |
| 主菜单 / 标题页 | 无（启动自动读档，无选择） | P11 |
| 暂停菜单 / 设置持久化 | 无（无灵敏度/音量/分辨率配置） | P11/P3 |
| 跳跃 / 蹲伏 / 奔跑 | 无（仅 WASD 行走） | P3 |
| 完整音频（AudioManager + 总线） | 无（零音频资源） | P9 |
| NPC（8 人）行为 / 导航 | 无（全文无 NavigationRegion3D/NavigationAgent3D） | P7 |
| 对话系统 | 无 | P7 |
| 玩家认知系统 | 仅 schema 占位字段，无逻辑 | P7 |
| 手机系统 | 无 | P8 |
| 多存档槽 | 单槽 | P6 |
| 多结局 / 剧情事件图 | 无 | P11 |
| Windows 导出 | 无 `export_presets.cfg` | P13 |

---

## 9. 结论

当前架构具备清晰的分层与唯一状态权威，`[代码]` 层面的 28 条已知 Bug 已有 18 条修复并验证（详见 `MASTER_BUG_REGISTER.md`）。但它仍是**灰盒垂直切片**，距离本任务书「从主菜单到结局的完整游戏」还差第 8 节所列的整套叙事/音频/NPC/流程系统——这些属于后续 P3–P13 阶段，需在 P0 审计确认后另行规划。
