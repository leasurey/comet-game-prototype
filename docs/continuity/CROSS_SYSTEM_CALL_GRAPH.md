# 跨系统调用链（CROSS_SYSTEM_CALL_GRAPH）

**基准**：`recovery/master-rebuild` @ `800beb7`｜只读审查｜证据分级 A/B/C/D。
四条链路按任务第八节要求逐条展开：入口函数 → 实际调用顺序 → 状态持有者 → 数据传递 → 关键条件 → 游戏效果 → 已知缺陷 → 验证方式。**断点明说，不用假设补全。**

---

## 链路 A：玩家观察 → 认知 → 对话

**入口函数**：`main._on_hotspot_activated(spot)`（scenes/main.gd:453，examine 分支）→ 稍后 `main._try_interact()`（:314）→ `_start_dialogue(npc)`（:333）。

**实际调用顺序** [A]：

```
InteractionManager.activate_focused → hotspot_activated.emit
→ main._on_hotspot_activated（"examine"）
    → audio_manager.play_examine()
    → cognition.learn("fact_inspected_%s" % spot.name, "inspect", spot.name, world_id, tick)   [:484]
    → _notify(examine 文本) → advance_tick(1)
……（玩家走到 NPC 旁按 E）……
→ main._try_interact → npc_manager.find_talkable_near(pos, 2.5)     [npc_manager.gd:291]
→ main._start_dialogue
    → dialogue_manager.get_entry_nodes_for(speaker)                  [dialogue_manager.gd:74]
         └─ _requirements_met → cognition.knows(每个 requires)        [:122]
    → ui.show_dialogue_topics →（玩家点话题）
→ main._show_dialogue_node → dialogue_manager.hear(node_id, world_id, tick)   [:97]
    → cognition.learn(grants…, "dialogue", speaker)                  [:88-90]
    → ui.show_dialogue_line（含「你了解到」hint）
```

**状态持有者**：认知=CognitionManager；话题过滤=DialogueManager（只读认知）；面板=UIManager。
**数据传递**：fact_id 字符串（requires/grants）；`granted` 数组回传 UI。
**关键条件**：`requires` 全满足才可见/可听；learn 幂等（已知不覆盖）。
**游戏效果**：新话题入口出现（如学了 fact_sticky_note 才见便签话题）；面板 hint 提示新知。

**已知缺陷**：
1. **CT-019（P1）**：`fact_sticky_note`/`fact_dark_road` 无任何授予者（对话 grants 无、inspect 命名不同），**9/29 节点永久锁死**——链路 A 对便签/黑路支线**在真实游玩中断裂** [A+脚本闭包]。
2. inspect 产出的 `fact_inspected_*` 与对话 requires 的 id 空间不通（模板无映射）[A]。
3. 对话无"已说"状态，重复话题文本恒同 [A]。

**验证方式**：既有 B 级证据=cognition_npc_test C2/N4、dialogue_ui_test U3/U4（但 N4/U6 用手工 learn 注入钥匙，**不覆盖获取端**）。缺口验证=INTEGRATION_TEST_PLAN 测试 1（改造：钥匙必须由真实 inspect/事件产生）。

---

## 链路 B：NPC 行为/对话 → 世界事件 → 玩家反馈

**入口函数**：**不存在**。逐段核实：

```
NPC 侧：send_to_room/send_to_point 无游戏调用者（grep 零命中）→ NPC 不产生任何行为事件  [A]
对话侧：_close_dialogue（main.gd:408）不调用 event_manager.evaluate                     [A]
事件唯一入口：SceneManager.enter_location（enter_location 触发）与 main._on_portal_entered
             （area_enter 触发）→ 都由**玩家移动**驱动                                  [A]
TRIGGER_INTERACT：EventManager 可解析，但全项目无 evaluate("interact", …) 调用点          [A]
```

**结论：链路 B 当前完全断开**（不是半成品，是没有入口）。唯一近似路径是「玩家自己走入黑暗 → area_enter 事件 → 世界变 → 环境/异常音反馈」——那是玩家驱动，不是 NPC/对话驱动。
**游戏效果**：无。
**已知缺陷**：CT-020（NPC 零自主行为）、CT-005（interact 触发器死接线）、CT-022（对话无事件效果）。
**验证方式**：无任何测试覆盖（也没有可测的入口）。INTEGRATION_TEST_PLAN 测试 2 依赖批次 3 修复后才能落地。

---

## 链路 C：现实切换 → NPC 状态 → 对话变化

**入口函数**：`AutoPortal._on_body_entered` → `main._on_portal_entered`（:479 附近）→ `EventManager.evaluate("area_enter",…)` → `WorldManager.apply_transition` → `world_changed` 信号。

**实际调用顺序** [A]：

```
evaluate → apply_transition（world_alpha→beta，require_from_world 保证顺序）
→ world_changed.emit → GameServices._on_world_changed
    → event_bus.world_changed + play_reality_shift（异常音 ✓）
→ main 切场景（go_to）→ SceneManager.enter_location → apply_world(beta) 重刷变体 ✓
```

**断点在第二跳**：world_changed 的订阅者只有 GameServices（音效+总线）——**NPC 没有订阅者、无 per-world 状态槽、对话数据无 world 维度** [A]。同一角色在 α/β/γ 下行为与台词完全一致。
**游戏效果**：环境变体、异常音、log 文案 ✓（**B**：reality_cycle_test 19 断言）；NPC/对话 ✗。
**已知缺陷**：CT-022（对话 schema 无现实维度——机制缺失属 A 类；"具体各现实说什么"属 D 剧情内容）、CT-009（NPC 无分现实记忆）。
**验证方式**：现实循环本身 B 级已验证；NPC/对话差异无从验证（缺机制，非缺测试）。设计见 INTEGRATION_TEST_PLAN 测试 3。

---

## 链路 D：存档 → 完整恢复 → 继续游戏

**入口函数**：`GameServices.save_game`（:496）/ `continue_game`（:375）。调用顺序见 SAVE_LIFECYCLE_AUDIT §2（十步恢复序列，逐行核实）。

**实际效果对照**：

| 恢复项 | 结果 | 证据 |
| --- | --- | --- |
| 世界/现实 | ✅ | **B** |
| 事件历史/旗标/阶段/随机流 | ✅ | **B** |
| 地点/返回栈/访问记录 | ✅ | **B** |
| 时钟 | ✅ | **B** |
| 玩家位置/朝向 | ✅（含嵌墙回退） | **B** |
| 认知（含来源/现实/tick） | ✅ | **B**（C5） |
| NPC 位置/行为 | ❌ **断点**：写入 npc_states 但 restore 零调用（spawn_all 重建覆盖） | **A** |
| NPC 记忆/关系 | ❌ 无结构 | **A** |
| 对话进度 | ❌ 无结构 | **A** |
| 手机 | ❌ 不存在 | **A** |

**恢复顺序关键事实** [A+C]：NPC 若补 restore 必须在 `enter_location`（内含 spawn_all）**之后**执行；放之前会被无条件重建覆盖（推断 C，依据 spawn_all 不读外部状态）。
**验证方式**：既有 save_migration/save_isolation/cognition C5 为 B 级正证；NPC 项为 A 级负证（grep 无调用点）。INTEGRATION_TEST_PLAN 测试 4 补全。

---

## 断点总览

| 链路 | 状态 | 断点 |
| --- | --- | --- |
| A 观察→认知→对话 | **部分通** | 9/29 节点钥匙断供（CT-019）；inspect id 与闸门 id 命名不通 |
| B NPC/对话→事件→反馈 | **全断** | 无 NPC 行为入口、无 interact 求值、对话无事件效果 |
| C 现实→NPC→对话 | **半断** | 前半（世界/音画）通，后半（NPC/对话）无机制 |
| D 存档→恢复 | **半通** | 世界/认知/玩家通，NPC/对话进度/手机断 |
