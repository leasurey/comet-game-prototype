# NPC 深度审查（NPC_DEEP_AUDIT）

**基准**：`recovery/master-rebuild` @ `800beb7`（任务书所记 `8cd11db` 为其祖先，已过时；执行前已现场核实分支/HEAD）
**分支**：`recovery/continuity-integration`｜**性质**：只读审查，未改运行时代码
**证据分级**：A=源码证实｜B=测试证实｜C=推断未验证｜D=剧情未完成无法验证

相关源码：`core/npc.gd`（247 行）、`core/npc_manager.gd`（320 行）、`data/characters.json`、`scenes/main.gd`（生成/对话入口）、`autoload/game_services.gd`（存档编排）。

---

## 1. 生命周期（任务 4.1）

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| 什么条件生成？ | 仅当进入 `party_house`：`main._on_location_entered`（scenes/main.gd:447-451）调用 `npc_manager.spawn_all(inst)`；其他地点调用 `_despawn_all()` | **A** |
| 离开地点后？ | **销毁**（free 实体）。`_despawn_all`（core/npc_manager.gd:187）remove_child + free | **A** |
| 返回地点时恢复？ | **不恢复**。`spawn_all`（:104）先 `_despawn_all` 再按 `characters.json` 的 spawn 坐标重建，全员回出生点 idle | **A** |
| 重复生成/重复信号连接？ | 无重复累积：spawn_all 先清场；NPC._ready 每次 add_to_group("npcs")，free 后自动离组；**NPC 无任何外部 connect**（无重复连接风险，但也说明信号无人用，见 §2） | **A** |
| 会话内状态快照？ | `serialize()`（:307）只产出 `{id, position, rotation_y, state}`，**不含目标/记忆/关系**；且该快照只在存档瞬间调用，同会话离场-重入不经过它 | **A** |

**判定**：生命周期是「生成→销毁→按配置重建」，没有 suspend/resume 语义。任务 4.1 的"返回地点是否恢复原来状态"——**否**（P1，即 CT-004）。

## 2. 行为（任务 4.2）

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| 真实自主行为？ | **没有**。移动 API `send_to_room`（npc_manager.gd:254）/`send_to_point`（:270）在 core/scenes/autoload 中**零调用点**，只有测试调用。游戏流程里 NPC 站在出生点不动（walk 模拟仅在收到目标后存在） | **A**（grep 全项目调用链） |
| 状态机？ | 有三态 idle/walking/talking（npc.gd:28-30），切换由 move_to/stop/start_talking 驱动 | **A**；**B**（cognition_npc_test N3「可以给 NPC 派目标」仅断言 API 接受目标） |
| 行为切换条件 | 纯外部命令。无内部决策、无随机游走、无日程 | **A** |
| 现实/事件/玩家行为影响？ | **无**。世界变更信号无 NPC 订阅者（game_services._on_world_changed 只播音效）；事件 effects 不含 npc 类效果；玩家动作不改变 NPC | **A** |
| 固定路径？ | 连固定路径都没有——navmesh 寻路能力就绪（42/42 连通，**B**），但无人给目标 | **A+B** |

**判定**：任务 4.2 的答案是「引擎能力就绪 + 行为大脑缺失」。`arrived`/`state_changed` 信号有 emit 无 connect（**A**，死信号 CT-021）。

## 3. 记忆与关系（任务 4.3）

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| 独立角色记忆？ | **不存在**。NPC 类无记忆字段；npc_states 无 memory 子结构 | **A** |
| 记录对玩家认知/关系？ | **不存在**。无 relationship/emotion 字段（grep 全项目零命中） | **A** |
| 不同现实不同状态？ | **不能**。NPC 不持有 world_id，世界切换对 NPC 无任何作用 | **A** |
| 记住事件？ | 否 | **A** |
| 持久化机制？ | 只有位置/朝向/行为三字段入档（且读档不消费，见 §4） | **A** |

**判定**：记忆/关系是**空壳**（连预留结构都没有，不是"有字段未用"）。属 CT-009；本审查确认其深度为"零实现"，剧情内容缺失属 D 类，但**结构缺失本身是 A 类代码事实**。

## 4. 场景恢复专项（任务 4.4，含"保存了什么、丢了什么"）

调用关系（实测调用链）：

```
进入 party_house：SceneManager.enter_location → location_entered → main._on_location_entered
  → npc_manager.spawn_all(container)          [npc_manager.gd:104]
      → _despawn_all() → 建 NavigationRegion → 烘焙 → _spawn_one×7（配置点+吸附）

离开：main._on_location_entered（非住宅分支）→ _despawn_all()   [main.gd:451]

存档：GameServices.save_game → npc_manager.serialize()          [game_services.gd:513]
读档：GameServices.continue_game → …世界/事件/场景/时钟/随机/认知 restore…
      → enter_location（触发 spawn_all）→ 玩家位置覆盖
      ※ npc_manager.restore() 全项目无调用点                        [A/grep]
```

逐项回答：

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| 离场后位置保存？ | **否**（同会话）；存档瞬间的坐标会写入 npc_states | **A** |
| 目标/移动状态/行为保存？ | 目标（_target/_has_target）**不入 serialize**；state 入 | **A**（npc.gd:180-186 serialize 字段） |
| 重生后继续之前行为？ | 否，回 idle 出生点 | **A** |
| 只存位置状态、丢目标记忆关系？ | **正是**。serialize = {id, position, rotation_y, state} 四字段 | **A** |

**恢复顺序的尖锐问题**（任务七点名）：`npc_manager.restore()` 若被调用，必须在 `enter_location`（内部会 spawn_all）**之后**——否则 spawn 会覆盖恢复值。当前根本没有 restore 调用，因此"生成前/后恢复"都未实现；**若在 continue_game 中先 restore 再 enter_location，restore 的坐标会被 spawn_all 重建实体时丢弃**（spawn_all 不读任何外部状态）[**C**：推断，未实测，但与 spawn_all 源码一致]。方案必须写明顺序：enter_location → spawn_all → restore 覆盖。

## 5. 本审查新发现

- **CT-020（P2，A）NPC 零自主行为**：移动 API 无游戏侧调用者。
- **CT-021（P2，A）NPC 死接线**：`arrived`/`state_changed` 有发无收；`npc_talk_requested`（前轮 CT-010）同族。
- 既有 **CT-003**（读档不恢复 npc_states）与 **CT-004**（离场即重置）维持成立，本轮补充了精确行号与调用链。
