# 状态归属图（STATE_OWNERSHIP_MAP）

**基准**：`recovery/master-rebuild` @ `800beb7`｜只读审计产物（现状归属，目标规范见 `CONTINUITY_RECOVERY_PLAN.md` §2）。
**证据标记**同 `CONTINUITY_AUDIT.md`。

图例：**权威**=最终解释权所在；**写入方**=允许修改的调用点；**缓存**=副本及其失效方式；**入档**=是否进存档、读档是否消费。

---

## 1. 任务 4.1 状态清单现状

| 状态 | 当前权威 | 写入方 | 订阅/消费 | 入档 | 重复/风险 |
| --- | --- | --- | --- | --- | --- |
| 当前地点 | SceneManager._current_location_id | enter_location（唯一） | main（HUD）、EventManager（上下文） | ✅ 写+读 | 无 |
| 玩家位置 | PlayerController.global_position | main 落位（reset_to_spawn）、continue_game 恢复、reset_to_spawn 本体 | — | ✅ 写 player_position + 读 | ⚠️ 3 写入方靠时序互斥（见连接图 §4.9） |
| 玩家朝向 | PlayerController.yaw/pitch | 鼠标输入、门级落点、restore_view、reset_view | serialize_view | ✅ 写+读 | 无 |
| 当前现实 | WorldManager._current_world_id | apply_transition（唯一） | SceneManager 重刷表现、AudioManager（异常音）、Cognition 归属、对话文本 | ✅ 写+读 | ⚠️ GameLocation.applied_world_id 是缓存 |
| 穿越状态 | **无持有者** | — | — | ❌ v2 预留字段 `traversal_state` 从未读写 [S] | 状态缺失（CT-006） |
| 事件进度 | EventManager（history/sequence/flags/phase） | evaluate/_record/set_flag/set_phase | 条件求值、UI 提示 | ✅ 写+读 | ⚠️ triggered_events 与 event_sequence 双写同值（CT-006） |
| 物品状态 | **无持有者** | — | — | ❌ v2 预留 `inspected_objects` 从未读写 | 状态缺失；examine 只产生认知，不产生物品状态（CT-006/016） |
| NPC 位置 | NPCManager._npcs[*].global_position | spawn_all 出生吸附、行走模拟、serialize/restore | 寻路 | ⚠️ 写 npc_states / **读=否** | CT-003：写读不对称 |
| NPC 行为状态 | NPC.state（idle/walking/talking） | move_to/stop/start_talking | 对话判定 is_talking | ⚠️ 同上写读不对称 | CT-003/004 |
| NPC 记忆 | **不存在** | — | — | ❌ | CT-009 |
| 人物关系 | **不存在** | — | — | ❌ | CT-009 |
| 玩家认知 | CognitionManager._facts/_learned_order | learn（inspect/dialogue 两入口）、retract、reset | 对话闸门 requires、UI「你了解到」 | ✅ 写 cognition + 读；⚠️ known_facts 副本写而不读 | CT-015 冗余 |
| 手机信息 | **不存在** | — | — | ❌ | CT-011 |
| 音频环境状态 | AudioManager._looping（哪类在循环） | set_ambience/play_loop/stop_loop | — | ❌ 不入档（重进场景重建，合理） | 无 |
| 存档状态 | SaveManager._path + has_save | save/delete/quarantine/use_test_path | 主菜单「继续」可用性 | 自身即持久 | 无 |

---

## 2. 缓存与失效机制登记 [S]

| 缓存 | 位置 | 更新时机 | 失效机制 | 风险 |
| --- | --- | --- | --- | --- |
| applied_world_id | GameLocation | apply_world 调用时 | 世界变更后由 SceneManager._refresh_world_presentation 重刷 | 场景外发生世界变更后再入场景会重新 apply ✓；同场景内变更已覆盖（enter_location 的事件求值后二次刷新）✓ |
| _mouse_captured | PlayerController | capture/release_mouse | 与 Input.mouse_mode 双写同步 | headless 权威、真机以 Input 为准 [D] |
| InteractionManager._focused | 每帧射线 | _process | set_hotspots 时清空 | 无 |
| _looping | AudioManager | play_loop/stop_loop | 显式 stop | 无 |
| _visited_locations / _visit_stack | SceneManager | enter_location | reset_session（新局） | 已修过「新局继承」缺陷，有 session_reset_test 守护 [T] |

---

## 3. 「多写者」与「写读不对称」专项（本图最重要的两张清单）

### 3.1 多写者（需要所有权声明或收敛）

1. **玩家位置**：main._on_location_entered / continue_game / reset_to_spawn。收敛方案见恢复计划 §2。
2. **玩家鼠标捕获**：main（capture/release）与 PlayerController._exit_tree（release）双入口——语义安全（幂等）但应声明。
3. **NPC 字典内容**：spawn_all/_despawn_all/restore 三处改动 _npcs 生命周期。

### 3.2 写读不对称（存档契约破坏）

| 字段 | 写 | 读 | 判定 |
| --- | --- | --- | --- |
| npc_states | ✅ save_game | ❌ continue_game 从不调用 restore | **损坏**（CT-003） |
| known_facts | ✅ | ❌（被 cognition 取代） | 冗余（CT-015） |
| triggered_events | ✅ | ❌（=event_sequence，后者被读） | 冗余（CT-006） |
| inspected_objects | ❌（仅迁移默认 {}） | ❌ | 预留（CT-006） |
| traversal_state | ❌（仅迁移默认 {}） | ❌ | 预留（CT-006） |
