# 存档生命周期深度审查（SAVE_LIFECYCLE_AUDIT）

**基准**：`recovery/master-rebuild` @ `800beb7`｜只读审查｜证据分级 A/B/C/D。
**核心源码**：`core/save_manager.gd`（291 行）、`autoload/game_services.gd:496-527`（save_game）、`:375-470`（continue_game）、各 Manager serialize/restore。

---

## 1. 完整状态清单（任务第七节表格）

| 状态 | 当前持有者 | 是否序列化 | 是否恢复 | 是否验证 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 玩家位置 | PlayerController.global_position | ✅ `player_position`（game_services.gd:523 `_serialize_player_position`） | ✅ continue_game:452-460（重叠检测，被占回退 spawn） | **B**（save_migration 27 断言） | |
| 当前现实 | WorldManager | ✅ `world_id` | ✅ 重映射为 current_world_id 进 world_manager.restore(:386-397) | **B**（migration/reality_cycle） | |
| 世界状态（变更史） | WorldManager._change_log | ✅ `world_change_records` | ✅ | **B** | |
| 已知认知 | CognitionManager | ✅ `cognition`（全量 facts+known_order）＋冗余 `known_facts` | ✅ `cognition`；`known_facts` **写而不读** | **B**（C5）；冗余=CT-015 [A] | |
| NPC 位置 | NPCManager._npcs | ✅ `npc_states[].position`（:513 serialize） | ❌ **continue_game 从不调用 npc_manager.restore**（全项目无调用点） | **A**（grep）；写读不对称=CT-003 | |
| NPC 行为 | NPC.state | ✅ npc_states[].state | ❌ 同上 | **A** | |
| NPC 记忆 | 不存在 | ❌ | ❌ | 结构缺失=CT-009 [A] | |
| NPC 关系 | 不存在 | ❌ | ❌ | 同上 | |
| 对话进度 | 不存在（无 said/次数） | ❌ | ❌ | CT-023 [A] | |
| 事件进度 | EventManager（history/sequence/flags/phase） | ✅ `event_history`+`event_sequence`（**同值双写**）+`event_flags`+`phase_id` | ✅（restore:402-420，历史 id 双表校验） | **B**（migration）；双写=CT-006 [A] | |
| 手机信息 | 不存在 | ❌ | ❌ | CT-011 [A] | |

附：玩家朝向 `player_view` ✅写✅读 [B]；`visited_locations`/`visit_stack` ✅✅ [B]；时钟 tick ✅✅；rng master_seed+counters ✅✅；`inspected_objects`/`traversal_state` **仅 v2 迁移默认值，零读写** [A]（CT-006）。

## 2. 保存/读取入口核对（任务第七节"不能只看有没有 serialize/restore"）

**保存入口**：`GameServices.save_game`（:496）组 19 字段 payload → `SaveManager.save`。调用来源：暂停菜单「保存进度」（menu_controller._save_from_pause）、HUD 保存按钮（main `_on_save_requested`）。**无自动存档** [A]。

**读取入口**：`continue_game`（:375）恢复顺序（源码顺序逐行核实）：

```
1  save_manager.load_state（含 magic/version/字段校验）
2  world_manager.restore          ← current_world_id+change_log
3  event_manager.restore          ← history/sequence/flags/phase/rng_counters
4  scene_manager.restore          ← location_id/visited/visit_stack
5  time_service.restore
6  rng_service.set_seed+restore
7  cognition.restore              ← :445
8  scene_manager.enter_location(target, false)   ← :449
     └─ 场景实例化 → main._on_location_entered
          └─ （party_house）npc_manager.spawn_all   ← NPC 在此刻按配置点生成
9  玩家位置覆盖（_is_position_free 检测后 reset_to_spawn）← :452-460
10 restore_view（朝向）
```

**顺序正确性**：世界先于场景 [A]（新场景按恢复的世界渲染）；玩家位置最后覆盖 spawn [A]（顺序对）；认知先于场景（对话闸门在场景内可用）[A]。

**NPC 恢复位置的尖锐问题**（任务点名）：当前**根本没有** NPC restore。若补上，必须放**步骤 8 之后**——因为 spawn_all（步骤 8 内）会无条件按配置点重建实体；放在 8 之前的 restore 会被 spawn 覆盖 [**C**：推断，与 spawn_all 源码（npc_manager.gd:104-147 不读任何外部状态）一致]。这正是"生成前恢复 vs 生成后恢复会产生不同结果"的确切答案：**生成前恢复 = 无效，生成后恢复 = 有效**。

**二次初始化覆盖检查**：new_game 路径 `reset_session`+`cognition.reset`+`_despawn_all` 清场后再 enter_location [A]（session_reset_test [B] 验证"重开不继承上局"）；continue_game 路径无二次覆盖 [A]。

## 3. 容错与机制（任务第七节末段）

| 项 | 结论 | 证据 |
| --- | --- | --- |
| 缺少字段 | v1→v2 迁移补默认（V2_DEFAULTS：player_position/visit_stack/known_facts/inspected_objects/npc_states/traversal_state） | **B**（save_migration_test v1 可读） |
| 旧版本存档 | version 字段+migration | **B** |
| 损坏存档 | `_file_is_valid` 校验 + `quarantine_corrupt` 隔离（continue_game:380-383） | **B**（save_isolation_test 10 断言） |
| 临时文件 | `.tmp` 先写后校验 | **B** |
| 备份 | `.bak` 保留上一份（save_manager.gd:109-118） | **B** |
| 原子性 | tmp→校验→bak→删除旧档→rename→再回读（:83-120 注释与实现一致） | **B** |
| 历史 id 校验 | event restore 拒绝未知事件 id（防半损坏） | **B**（migration） |

## 4. 测试侧存档安全（任务规则 9 专项）

核查全部 22 个测试：直接使用 SaveManager/`save_game`/`load_state` 的 5 个测试（acceptance/cognition_npc/menu_flow/save_isolation/save_migration）**全部先 `use_test_path`** [A]；其余 7 个未调用任何存档 API [A/grep]。**本轮运行的 cognition_npc_test 确认隔离**（use_test_path("cog_npc")），未触碰真实存档。结论：现有测试无覆盖真实存档之虞 [B]（本轮核查+复跑）。

## 5. 缺陷引用

- **CT-003（P1）**：npc_states 写读不对称（本表第 5 行）。
- **CT-006（P2）**：inspected_objects/traversal_state 纯预留；triggered_events/known_facts 冗余双写。
- **CT-023（P3）**：对话进度无档。
- **CT-009（P2）**：NPC 记忆/关系无结构 → 表中两行永远空。
