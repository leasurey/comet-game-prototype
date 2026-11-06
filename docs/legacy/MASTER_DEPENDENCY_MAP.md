# COMET — 依赖图与调用链（P0 审计）

| 项 | 值 |
| --- | --- |
| 审计基准 commit | `adf7aa2`（`docs: 八份阶段交付物归入 docs/deliverables/`） |
| 审计分支 | `recovery/master-rebuild`（从 `adf7aa2` 拉出，原始 HEAD 已记录） |
| 引擎 | Godot 4.7.2-stable（`Godot_v4.7.2-stable_win64_console.exe`） |
| 平台 | Windows 10 19045 / i5-7200U / 12 GB / Radeon 530 2 GB |
| 审计方法 | 逐文件通读源码 + 全量测试实跑 + 真实窗口探针（探针已删除） |
| 使用约定 | 本文所有结论标注来源：`[代码]` 读源码得出、`[实测]` 运行得出、`[计算]` 由数据推得、`[未验证]` 需实际运行确认 |

> **本轮不修改任何运行时逻辑。** 唯一新增文件是审计文档本身。

---

## 一、模块职责表

| 文件 | 当前职责 | 实际调用者 | 依赖对象 | 状态 |
| --- | --- | --- | --- | --- |
| `autoload/game_services.gd` | 唯一 autoload：装配各 Manager、注入依赖、暴露新局/读档/存档/导航/时钟 API | `scenes/main.gd`、全部测试 | 全部 Manager + 三个 L0 服务 | 正常，但承担了过多职责（装配 + 存档编排 + 导航 + 时钟） |
| `core/scene_manager.gd` | 地点加载/切换、返回栈、出生点、进入后求值事件 | `game_services`、`main`、测试 | `GameLocation`、`EventManager`、`WorldManager`、`InteractionManager` | 有缺陷：返回栈只增不减；`ok` 恒为 true；残留 `if world_changed_after_enter: pass` 死代码 |
| `core/world_manager.gd` | 当前现实 + 变更历史的唯一权威 | `game_services`、`scene_manager`、`event_manager` | 无 | 正常（`RefCounted`，可 headless 单测） |
| `core/event_manager.gd` | 事件规则求值、历史记录、旗标与阶段 | `scene_manager`、`main`、`game_services` | `WorldManager.apply_transition`、`RngService`、`TimeService`、`SceneManager`、`ConditionEvaluator` | 正常，但 `interact` 触发类型运行时**从未被调用**（见 BUG-014） |
| `core/interaction_manager.gd` | 准星射线、遮挡判定、交互距离、激活派发 | `game_services`、`main`、测试 | `Hotspot`、`Camera3D` | 正常；三类判据齐备 |
| `core/save_manager.gd` | 状态字典写盘/读回/完整性校验 | `game_services`、测试 | 无（依赖倒置） | **有缺陷**：非原子写入、无备份、无迁移（BUG-001） |
| `core/player_controller.gd` | 鼠标捕获视角 + WASD 地面移动 + 重力 | `main.tscn`、测试 | `InputMap` 动作 | 正常；`serialize_view` 只存 yaw/pitch（BUG-003） |
| `core/location.gd` | 地点根节点：按世界切换 `Variant_*` 可见性、收集热点 | `scene_manager`、测试 | `Hotspot` | **有缺陷**：变体缺失静默回退且无警告（BUG-006） |
| `core/hotspot.gd` | 可交互对象声明 + 门级落点 + 世界可见性 | 全部地点构建器 | 无 | 有缺陷：聚焦反馈会改写**共享材质**（BUG-010） |
| `core/auto_portal.gd` | 区域触发式场景连接（走进去即切换） | `main`（连接信号） | 场景构建器 | 正常；玩家识别用鸭子类型（BUG-027） |
| `core/data_loader.gd` | JSON 读取统一入口 | `game_services` | 无 | 正常 |
| `core/event_bus.gd` | 只读信号总线 | `game_services`（仅 emit） | 无 | **无任何订阅者**（BUG-013） |
| `core/time_service.gd` | 整数 tick 时钟 | `game_services`、`event_manager` | 无 | 正常 |
| `core/rng_service.gd` | 具名可持久化随机流 | `game_services`、`event_manager` | 无 | 正常 |
| `core/condition_evaluator.gd` | `requires` 谓词白名单校验与求值 | `event_manager` | 无 | 正常 |
| `core/ui/ui_manager.gd` | HUD 构建与文本更新 | `main` | 无 | 有缺陷：无二次确认、无保存反馈、无缩放策略（BUG-011/019） |
| `scenes/main.gd` | 应用装配 + 输入路由 + 门级落点"挂起—消费" | 主场景 | 全部 Manager、`UIManager` | 有缺陷：只在 `_ready` 连线一次，`new_game` 换掉 `event_manager` 后**连线失效**（BUG-009） |
| `scenes/ui/hud.tscn` | 6 行空壳，实际界面由 `UIManager` 代码构建 | `main.tscn` | 无 | 正常（有意设计） |
| `tools/**` | 离线场景构建，不进运行时 | 手动执行 | 无 | 正常；**改场景必须重建**（`docs/KNOWN_ISSUES.md` §2） |
| `tests/*.gd`（8 个） | headless 自动化测试 | 手动执行 | 全部运行时模块 | 有缺陷：5 个测试删除玩家真实存档（BUG-002） |

---

## 二、状态权威表（谁拥有什么）

> 任务书 §2.1 要求"每类状态必须明确唯一权威管理者"。以下为**当前实际**归属，缺陷一并标出。

| 状态 | 当前权威 | 是否唯一 | 问题 |
| --- | --- | --- | --- |
| 当前现实 ID | `WorldManager._current_world_id` | ✅ 唯一 | 无 |
| 当前地点 ID | `SceneManager._current_location_id` | ✅ 唯一 | 无 |
| 返回栈 | `SceneManager._visit_stack` | ✅ 唯一 | **不存档**（BUG-004）；`new_game` 不清空（BUG-005）；只增不减 |
| 访问记录 | `SceneManager._visited_locations` | ✅ 唯一 | `new_game` 不清空（BUG-005） |
| 玩家位置 | **无人持久化** | ❌ 缺失 | `serialize_view()` 只返回 yaw/pitch（BUG-003） |
| 玩家朝向 | `PlayerController.yaw/pitch` | ✅ 唯一 | 读档后 `enter_location` 会先落 spawn 再套 yaw，位置与朝向不同源 |
| 事件历史 | `EventManager._history/_sequence` | ✅ 唯一 | `restore` 不校验 `sequence` 元素合法性 |
| 世界变更历史 | `WorldManager._change_log` | ✅ 唯一 | 无 |
| 游戏时钟 | `TimeService.tick` | ✅ 唯一 | 无 |
| 随机流计数 | `RngService._counters` | ✅ 唯一 | 无 |
| 旗标 / 阶段 | `EventManager._flags/_phase_id` | ✅ 唯一 | 无 |
| 玩家认知 | **不存在** | ❌ 缺失 | 任务书 §7 要求；存档无 `known_facts`/`inspected_objects` |
| NPC 状态 | **不存在** | ❌ 缺失 | 任务书 §8 要求；存档无 `npc_states` |
| 穿越状态 | **不存在**（靠几何隐式表达） | ⚠️ 隐式 | 无显式状态机；掉头无处理（BUG-008） |
| 存档版本 | `SaveManager.SAVE_VERSION = 1` | ✅ 唯一 | 无迁移机制 |

**结论**：核心三项（现实/地点/事件历史）确实各自唯一，没有出现"两个 Manager 各存一份"的问题——这点比预想的好。真正的缺口是**四类状态根本没有权威**：玩家位置、认知、NPC、穿越。

---

## 三、十二条调用链

标注格式：`入口 → 中间 → 数据来源 → 状态修改者 → 信号 → 结果 / 可能错误`

### 链 1：启动 → 服务初始化 → 主场景

```
main._ready [scenes/main.gd:34]
 → GameServices._ready → _bootstrap [autoload:71]
    → _ensure_input_actions（InputMap 幂等注册 E/WASD）
    → new TimeService / RngService / EventBus
    → new WorldManager / EventManager / SaveManager / SceneManager / InteractionManager
    → add_child(scene_manager, interaction_manager)
    → _inject_services（rng/tick/visit 注入 event_manager）
    → _wire_signals（world/event/scene → event_bus，并连到自身回调）
    → DataLoader.load_dictionary × 4（worlds / events / transitions / locations）
    → world_manager.load_from_data → event_manager.load_from_data → scene_manager.load_from_data
    → is_ready = true; bootstrap_completed.emit()
 → main._bind_services
    → scene_manager.set_container(LocationContainer)
    → 连接 scene_manager.location_entered / location_failed
    → interaction_manager.set_camera + 连接 3 个信号
    → **连接 event_manager.event_triggered**  ← 只此一次（BUG-009）
    → 连接 UI 的 back/save/quit/new_game
 → main._start_flow [main.gd:76]
    → 有存档则 continue_game()，失败则 new_game()
    → _refresh_ui_state
    → await process_frame → capture_mouse
```

**数据来源**：`res://data/*.json`。
**状态修改者**：`_bootstrap` 创建全部对象。
**可能错误**：任一 JSON 缺失/格式错 → `_fail()` → `is_ready=false` → 主场景只显示一条提示，**无重试、无诊断面板**；`bootstrap_failed` 只在 `main` 连接了回调时可见。

### 链 2：新游戏 → 起始地点 → 玩家出生

```
(UI 重新开始) ui.new_game_requested → main._on_new_game_requested [main.gd:321]
 → GameServices.delete_save → new_game() [game_services:216]
    → 重建 WorldManager + EventManager（**其余 Manager 复用**）
    → 重载 worlds/events/transitions
    → 重新 _inject_services + _wire_signals
    → time_service.reset(); rng_service.set_seed()
    → scene_manager.enter_location(start_location, false)
       → _release_current → instantiate party_house.tscn → _refresh_world_presentation
       → interaction_manager.set_hotspots(collect_hotspots())
       → location_entered.emit()
          → main._on_location_entered → player_controller.reset_to_spawn(spawn)
          → main._connect_portals
       → event_manager.evaluate("enter_location", ...)
```

**缺陷**：`SceneManager._visit_stack` 与 `_visited_locations` **不会被清空**（`load_from_data` 才清，而 `new_game` 不调用它）→ 新局继承上局的返回栈与访问记录（BUG-005）。玩家 yaw 也不会重置（`reset_to_spawn` 只改位置）。

### 链 3：玩家移动 → 视角 → 碰撞

```
_input(MouseMotion) → PlayerController._apply_look(relative) [player:127]
  → yaw/pitch 累加 → _apply_rotation（pitch 限位 ±75°，yaw wrapf 到 [-π,π]）
_physics_process(delta) → _apply_gravity → _apply_horizontal_velocity
  → Input.get_vector(4 个动作) → _apply_direction → Basis(UP, yaw) 变换
  → move_and_slide()
```

**数据来源**：`InputMap`（运行时注册）。**状态修改者**：仅 `PlayerController` 自身。
**可能错误**：`Input.get_vector` 依赖动作名存在；若 `_ensure_input_actions` 未跑（如测试直接 new），移动恒为 0——测试中有此风险，已由各测试 setup 断言规避。

### 链 4：准星检测 → 热点聚焦 → E 键交互

```
InteractionManager._process → _update_focus [interaction:62]
  → env 射线（mask=1, bodies）→ env_distance
  → spot 射线（mask=2, areas）→ dist
  → 判据：is_interactable() && dist <= env_distance && dist <= 2.5
  → set_focused_internal → hotspot_focused/unfocused.emit()
     → main._on_hotspot_focused → ui.set_focus_text

main._unhandled_input（E 或捕获态左键）→ _try_interact [main.gd:154]
  → InteractionManager.activate_focused [interaction:135]
     → 二次校验 is_interactable + _within_reach(2.5)
     → hotspot_activated.emit → main._on_hotspot_activated [main.gd:190]
        → action_kind == "exit"  → 设置 _pending_spawn/_pending_yaw_deg → go_to()
        → action_kind == "examine" → ui.set_message + advance_tick
```

**可能错误**：`activate(spot)` 程序化入口**不做距离校验**，注释声明"玩家永远走不到"，但它是 public 方法，任何脚本都能绕过距离限制（BUG 见登记表 P2）。

### 链 5：门 / 出口 → 场景切换 → 对应落点

```
Hotspot.action_kind == "exit" → main._on_hotspot_activated
 → if use_target_spawn: _pending_spawn = spot.target_spawn; _pending_yaw_deg = ...
 → GameServices.go_to(target) [game_services:360]
    → advance_tick(1) → scene_manager.enter_location(target, remember=true)
       → 压栈 previous_id → _release_current → instantiate → apply_world
       → set_hotspots → location_entered.emit
          → main._on_location_entered：消费 _pending_spawn（一次性），否则用地点 spawn
```

**数据来源**：`locations.json` 的 `spawn`（地点级）+ `Hotspot.target_spawn`（门级，构建器写入 `.tscn`）。
**状态修改者**：`SceneManager`（地点/栈）、`main`（挂起值）、`PlayerController`（位置/朝向）。
**已实现的三扇门**（`[代码]` + `[实测] door_connection_test 37/0`）：前门 `(0,-2.6) yaw 0°`、侧门 `(8.6,2.0) yaw -90°`、露台 `(-4,11) yaw 180°`；回屋落点 `(0,0.25,1.6) yaw 180°`。
**缺陷**：侧门与露台门**没有对应的回屋门**，必须绕回前门（BUG-007）。

### 链 6：黑暗区域 → 穿越 → 现实变化

```
玩家走进 house_exterior 的 DarkEntry(Area3D) [z=-19.2]
 → AutoPortal._on_body_entered（需 body 是 CharacterBody3D 且有 is_mouse_captured）
 → player_entered.emit → main._on_portal_entered [main.gd:276]
    → ① 先求值事件：event_manager.evaluate("area_enter", {"area_id": ...})
         本规则 area_id=dark_far_end，故 DarkEntry 阶段不触发
    → ② go_to("dark_road")，落点 (0,0.05,4.0)

玩家走进 DarkExit [z=-20.0]
 → 同样路径，但 event_keys = {"area_id": "dark_far_end"}
 → event_manager.evaluate → 命中 evt_cross_dark_road
    → world_manager.apply_transition(world_beta, "evt_cross_dark_road")
    → _record → event_triggered.emit
 → 再 go_to("house_exterior")，落点 (0,0.05,-24.0)  ← 街对面
```

**关键时序**（`[实测]` 第二轮真实窗口验证）：进入黑暗时 `world=world_alpha`；走出尽头才变 `world_beta`。
**可能错误**：DarkExit 的 `event_kind` 求值在 `go_to` **之前**，若事件求值失败（`errs` 非空），仅 `push_warning`，场景照切——玩家会跨过黑暗但现实没变（**静默不一致**）。

### 链 7：现实变化 → 场景变体刷新

```
world_manager.apply_transition → world_changed.emit
 → game_services._on_world_changed → event_bus.emit（**无人订阅**）
SceneManager 内：enter_location 若因事件改变世界 → _refresh_world_presentation
 → GameLocation.apply_world(world_id)
    → 遍历 Environment 下 `Variant_*` 子节点：命中可见，其余隐藏
    → 无命中 → 回退 Variant_default → 再回退第一个 variant（**无警告**）
    → 遍历全部 Hotspot → hotspot.apply_world(world_id)（visible_only_in_worlds）
```

**缺陷**：变体缺失静默回退（BUG-006）；`apply_world` 失败时不做原子回滚，可能留下"半套新状态"（任务书 §4.1.5）。

### 链 8：事件触发 → 事件历史 → 世界变化记录

```
EventManager.evaluate(kind, ctx, world_mgr, errs) [event:179]
 → snapshot_world（本次求值统一基准）
 → 遍历 _transitions：kind 匹配 → once 检查 → ctx 逐键匹配 → require_from_world
   → ConditionEvaluator.evaluate(requires, base_ctx)
   → _resolve_target_world（fixed / conditional / pseudo_random 具名流）
   → world_mgr.apply_transition → 若实际未变则跳过 → _record → fired.append → emit
```

**保证**：判定与执行分离，历史不会漏记；快照语义使结果不依赖规则数组顺序；`once` 由 `has_occurred` 拦截。
**缺陷**：`interact` 类型运行时无调用点（BUG-014）；`restore` 不校验 `sequence` 元素。

### 链 9：保存 → 写盘 → 完整性验证

```
(UI 保存) → main._on_save_requested → GameServices.save_game [game_services:318]
 → 组装 payload（14 个字段）
 → save_manager.save(payload)
    → 加 magic/version/saved_at_unix
    → JSON.stringify → FileAccess.open(_path, WRITE) → store_string → close
    → 回读 → JSON 解析 → 校验 magic
    → 返回 {ok, bytes}
 → save_completed.emit(ok, msg)  ← **main 未连接该信号，玩家看不到任何反馈**
```

**缺陷**：直接覆盖正式存档，**无临时文件、无备份**（BUG-001）；payload 缺 `visit_stack` 与玩家位置（BUG-003/004）；`triggered_events` 与 `event_sequence` 写的是同一份数据。

### 链 10：读档 → 校验 → 状态恢复

```
GameServices.continue_game [game_services:246]
 → save_manager.load_state(known_locations, known_worlds)
    → 存在性 / JSON / magic / version(>1 拒绝) / location_id / world_id
    → visited_locations 逐项校验 / world_change_records 逐条校验
 → world_manager.restore（校验 change_log 引用）
 → event_manager.restore（校验 history 的 id 可知）
 → scene_manager.restore（校验 current_location_id / visited / visit_stack）  ← visit_stack 恒为空数组
 → time_service.restore（整数 tick）
 → rng_service.restore（master_seed + counters）
 → scene_manager.enter_location(target, false)   ← **玩家被放到地点 spawn**
 → player_controller.restore_view({yaw, pitch}) ← **只有朝向，没有位置**
 → load_completed.emit(true)
```

**缺陷**：位置丢失（BUG-003）；返回栈丢失（BUG-004）；任一 restore 失败只 emit(false)，**不隔离损坏存档**，下次启动重复失败（BUG-021）。

### 链 11：退出 → 输入释放 → 资源清理

```
Q 键 → main._on_quit_requested → _release_mouse() → get_tree().quit()
窗口关闭 → main._notification(NOTIFICATION_WM_CLOSE_REQUEST) → 同样释放后 quit
PlayerController._exit_tree → release_mouse()
```

**缺口**：退出**不自动存档**（设计选择，但 UI 无提示）；窗口失焦 / 重新获得焦点**完全未处理**（BUG-018）。

### 链 12：场景构建器 → 生成 → 运行时加载

```
tools/scene_builder.gd::_initialize [builder]
 → load tools/scene_content.gd 与 tools/house/house_party.gd
 → 每个地点：new Node3D + 挂 location.gd → 调用 assemble_* → 校验非空 → PackedScene.pack() → ResourceSaver.save()
 → 输出 res://scenes/locations/*.tscn

运行时：SceneManager.enter_location → load(scene) → instantiate → 挂到 LocationContainer
```

**约束**：`class_name` 索引依赖 `.godot/global_script_class_cache.cfg`，新增脚本后必须先 `--headless --editor --quit` 生成索引，否则构建器报"Identifier not declared"。
**缺陷**：构建器曾出现"假成功"（pack 成功但场景为空），现已有空节点检测——验证是否存在需读源码 `[代码]` 已确认有检测。

---

## 四、数据流总图

```
                    ┌──────────────── 玩家输入 ────────────────┐
                    │ 鼠标 / WASD / E / ESC / Q / 左键         │
                    └───────────────┬──────────────────────────┘
                                    ▼
                        PlayerController（视角 + 移动）
                        main.gd（输入路由）
                                    │
                                    ▼
                 InteractionManager（射线 / 遮挡 / 2.5 m）
                                    │ hotspot_activated
                                    ▼
                 main._on_hotspot_activated（exit / examine）
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
          SceneManager.enter_location        EventManager.evaluate
             │            │                        │
             │            │                        ▼
             │            │              WorldManager.apply_transition
             │            │                        │ world_changed
             │            ▼                        ▼
             │      GameLocation.apply_world   （唯一权威）
             │      （Variant_* 可见性）
             ▼
      location_entered ──► main（重置玩家到落点）
                       ──► UIManager（地点名 / 返回按钮）
                       ──► GameServices → EventBus（**无人订阅**）

      存档方向：GameServices.save_game ← World/Event/Scene/Player 各自序列化
                GameServices.continue_game → 各自 restore
```

**单向依赖规则（当前实际遵守情况）**：表现层（`main` / `UIManager`）只读状态、不写状态 ✅；`Hotspot` 不修改任何全局状态 ✅；`UIManager` 不调用 `SceneManager` ✅（只发信号）。
**唯一越界**：`main._on_location_entered` 直接写 `player_controller.yaw/pitch`（应为 `reset_to_spawn(pos, yaw)`）。

---

## 五、地点连接图（当前实现）

```
                 ┌──────────────┐
                 │ party_house  │ 13.4 × 9.4，主线场景
                 │  前门 1.6    │
                 │  侧门 1.2    │
                 │  露台门 1.2  │
                 └──┬───┬───┬───┘
        前门(0,-2.6)│   │   │ 侧门(8.6,2.0)  露台(-4,11)
                    ▼   ▼   ▼
                 ┌────────────────┐
                 │ house_exterior │ 门廊 / 车道 / 街道
                 │  回屋门 → party_house (0,0.25,1.6)
                 │  DarkEntry → dark_road        ← 区域触发
                 └────────┬───────┘
                          ▼ 走进（无需按键）
                 ┌────────────────┐
                 │   dark_road    │ z 4.0 → -20.0
                 │  DarkExit      │ 尽头，触发 evt_cross_dark_road
                 └────────┬───────┘
                          ▼ 回到 house_exterior (0,-24)
                 ┌────────────────┐
                 │ house_exterior │ world_beta
                 └────────────────┘

  living_room  ← 独立旧场景，已无运行时入口（仅被 3 个测试引用）
```

**问题**：`living_room` 在 `locations.json` 中仍注册且 `exits` 指向 `house_exterior`，但**没有任何热点或 portal 指向它** → 运行时不可达（死地点）；同时被 `acceptance_test` / `player_movement_test` / `v2_p0_test` 依赖，不能直接删（BUG-023）。

---

## 六、测试对模块的覆盖矩阵

| 模块 | 覆盖测试 | 断言数 | 备注 |
| --- | --- | --- | --- |
| `world_manager` | v2_p0 / acceptance | — | 含 restore 校验 |
| `event_manager` | v2_p0 / acceptance / dark_traverse | — | 含 once 语义、伪随机流 |
| `scene_manager` | acceptance / door_connection / fps_input | — | 栈行为未单独测 |
| `interaction_manager` | door_connection / fps_input | 37 + 29 | 距离与遮挡均覆盖 |
| `player_controller` | fps_input / player_movement | 29 + 34 | |
| `save_manager` | acceptance | — | **只用自定义路径测单槽**，未测原子性与迁移 |
| `location.apply_world` | party_house / acceptance | 54 | **未测变体缺失** |
| `auto_portal` | dark_traverse | 25 | 未测掉头 / 侧面离开 / 重复进入 |
| `ui_manager` | 无 | 0 | **完全无自动化覆盖** |
| 场景几何 | party_house / wall_geometry | 54 + 24 | 连通性用胶囊采样 |

**合计**：`[实测]` 273 条断言，本轮 5 次连跑全部通过；但**首次**运行 `fps_input_test` 出现 1 次失败（`PASS=28 FAIL=1`），随后 4 次连续通过，**未能复现**（BUG-017）。
