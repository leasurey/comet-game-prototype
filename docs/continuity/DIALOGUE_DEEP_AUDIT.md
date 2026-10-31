# 对话系统深度审查（DIALOGUE_DEEP_AUDIT）

**基准**：`recovery/master-rebuild` @ `800beb7`｜只读审查｜证据分级 A/B/C/D。
**核心源码**：`core/dialogue_manager.gd`（142 行）、`scenes/main.gd:314-425`（对话 UI 流程）、`core/ui/ui_manager.gd`（对话面板）、`data/dialogue.json`（29 节点 / 22 事实）。

---

## 1. 任务第六节逐项

| 问题 | 结论 | 证据 |
| --- | --- | --- |
| 对话数据从哪读？ | `data/dialogue.json`，bootstrap 时 `dialogue_manager.load_from_data`（game_services.gd:197） | **A** |
| NPC 如何选择对话？ | **NPC 不选**。玩家从「话题入口」列表选择（`get_entry_nodes_for`：requires 已满足且不被任何 goto 引用的节点，dialogue_manager.gd:74-92）；NPC 侧无任何选择逻辑 | **A** |
| 前置条件真正生效？ | 是。`_requirements_met`（:122）逐条 `cognition.knows`；未满足节点不进话题列表也不可 hear（hear:82 二次校验） | **B**（N4/U6）＋**A**（但钥匙断供见下） |
| 按玩家认知开放不同回复？ | 只有**节点级**开放（requires），无**回复级**条件（replies 全部无条件显示） | **A** |
| 按当前现实改变对话？ | **不支持**。对话 schema 无 world 字段，`hear` 虽记录 world_id（认知归属）但文本/可用性不随现实变化 | **A** |
| 按 NPC 记忆/关系改变？ | **不支持**（NPC 无记忆/关系，前轮 CT-009） | **A** |
| 玩家选择真正改变状态？ | **改变的只有玩家认知**：goto 分支 → `hear()` → `cognition.learn`（dialogue_manager.gd:88-90）。NPC 状态、世界、事件均不变 | **A+B**（U4 认知授予） |
| 对话结束触发事件？ | **否**。`_close_dialogue`（main.gd:408）只隐藏面板/stop_talking/恢复鼠标，无 `evaluate` 调用 | **A** |
| 新认知可保存？ | 是（cognition 入档，C5 [B]） | **A+B** |
| 场景切换/重开后信号仍有效？ | 是。UI 信号在 `_bind_services` 一次性连接（main.gd:88-96）；new_game 只重建 World/Event Manager，**不重建** dialogue_manager 与 UI 连接，无重复连接/断连 | **A**；**B**（session_reset_test 17 断言） |

## 2. 五大排查项逐条（任务第六节"特别排查"）

| # | 排查项 | 结论 | 证据 |
| --- | --- | --- | --- |
| 1 | 对话显示成功但认知没写入 | **未发现**。`hear` 先校验 requires 再 learn，返回 granted 清单；UI hint 显示 granted（main.gd `_show_dialogue_node`）；重复听取时 learn 返回 false（已知）但仍显示文本——语义正确 | **A+B**（U3/U4） |
| 2 | 认知写入但对话识别不到 | **存在反向变体（CT-019）**：闸门事实无来源，识别逻辑本身无误但钥匙不存在 → 9/29 节点永久锁死 | **A+B** |
| 3 | NPC 状态变了对话仍用旧状态 | **成立**（因 NPC 无状态可读，对话永远"无状态"）：conversation 不读 behavior/emotion/位置 | **A** |
| 4 | 不同现实同一份对话数据 | **成立**。29 节点文本全局唯一，α/β/γ 下同一角色说一样的话 | **A** |
| 5 | 对话选择只改界面不改状态 | **不成立**（此条是好的）：goto+grants 确实改认知并入档。但**未触及**事件/NPC/世界/物品——"状态"面窄 | **A+B** |

## 3. 其他机制事实

- **分支推进**：replies[].goto 链可多层（kevin_greet→far_house→two_houses 实测走通 [B]）；goto=null 结束对话 [B]（U5）。
- **无对话进度状态**：无 said_nodes/次数记录——同一话题可无限重问，`hear` 每次返回同一文本（granted 第二次为空）[A]。任务六"同一个问题不能永远返回同一段回答"**不满足**（P2）。
- **话题入口判定**：`get_entry_nodes_for` 用"不被 goto 引用"识别入口 [A]；12 个入口节点带 `topic` 短标签，缺省回退正文 [A]。
- **交互入口**：E 无热点时 `find_talkable_near(2.5m)`（npc_manager.gd:291）找最近可谈 NPC [A+B]。**对话期间玩家可走开**（输入锁缺失，CT-002 [B] 本轮探针同前轮）。

## 4. 缺陷汇总（本轮）

- **CT-019（P1，A+B）**：9/29 节点因钥匙事实断供不可达（详 COGNITION_DEEP_AUDIT §2）。
- **CT-022（P2，A）**：对话 schema 无现实/记忆/关系/情绪/已说维度——链路 C 的机制层缺失（内容差异属 D，**机制缺失不是 D**）。
- **CT-023（P3，A）**：对话进度（said/次数）无状态无存档（SAVE 表"对话进度"行=无）。
- 既有 CT-002（对话中可移动）维持。
