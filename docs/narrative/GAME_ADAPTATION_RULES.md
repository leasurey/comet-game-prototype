# COMET 互动叙事改编规则

## 1. 改编目标

把《Coherence》的悬疑结构转化为第一人称互动叙事。保留八人聚会、彗星异常、多现实错位、社交关系崩解、身份选择等核心主题；允许玩家改变调查顺序、信息传播、人物信任和最终结果。

玩家角色是 Emily，不是全知导演。

## 2. 三层真相模型

1. **世界事实 World Fact**：客观发生了什么，包含现实 ID、人物实例 ID、事件时间。
2. **角色知识 Character Knowledge**：每个 NPC 知道什么、如何知道、是否相信。
3. **玩家认知 Player Cognition**：Emily 亲眼看到、听到、读到或推断出什么。

示例：世界事实是一张便条来自某现实分支；Hugh 只知道自己写过便条；Emily 看到两张相同便条，“存在多个现实”仍是她的推断。

## 3. 剧情事件概念数据契约

以下是设计契约，不是当前代码 schema。WorkBuddy 必须先做字段适配。

| 字段 | 用途 |
|---|---|
| `event_id` | 稳定唯一 ID |
| `title` | 内部名称 |
| `source_anchor` | 电影阶段 T00–T21 或 G |
| `adaptation_type` | A_KEEP、B_EXPAND、C_BRANCH、D_ORIGINAL |
| `trigger` | 触发类型与条件 |
| `participants` | 角色原型/实例条件 |
| `world_effects` | 世界、场景、物品、现实变化 |
| `npc_effects` | NPC 经历、知识、信念、关系、行为变化 |
| `player_information` | 玩家可获得信息、来源、确定性 |
| `dialogue_unlocks` | 话题解锁条件 |
| `followups` | 后续事件和分支 |
| `failure_recovery` | 错过、延迟、冲突和软锁恢复 |
| `save_requirements` | 持久化状态与恢复要求 |
| `audio_visual_feedback` | 场景、动画、声音、UI 反馈 |
| `test_cases` | 正常、边界、重复触发、读档测试 |
| `evidence_level` | F/S/I/G/TBD |

## 4. 触发类型建议

`LOCATION_ENTERED`、`HOTSPOT_INSPECTED`、`DIALOGUE_COMPLETED`、`DIALOGUE_CHOICE`、`NPC_STATE_CHANGED`、`WORLD_TRANSITION`、`ITEM_STATE_CHANGED`、`TIME_WINDOW_REACHED`、`PLAYER_KNOWLEDGE_CHANGED`、`COMPOSITE_CONDITION`。

最终落地必须映射到当前 EventManager 支持的明确 ID，不能把自然语言当唯一条件。

## 5. 分支设计

分支可改变谁知道信息、NPC 是否愿意交谈、NPC 位置/行为、线索发现时机、人物参与和结局条件。只改变台词、不影响世界的选择应标为“表现分支”。

## 6. 关键线索容错

主线事实不应只有一个不可逆获取点。可以通过亲自检查、听角色描述、在别处发现副本等方式获得相近信息，但来源必须分别记录。不能将 hearsay 自动升级成 inspect。

## 7. NPC 对话条件

重要对话至少考虑 NPC 实例身份、经历、知识、信念、与 Emily 的关系、当前现实/场景、Emily 已知内容、NPC 是否愿意透露。不要只做“有 fact 就解锁固定台词”。

## 8. 存档要求

凡是影响后续剧情的状态必须保存：事件触发记录、现实 ID/变化历史、物品状态、Emily 认知来源与确定性、NPC 实例/经历/知识/信念/关系/行为、关键选择、必要的对话进度。新增字段需版本迁移和旧档兼容。

## 9. 防软锁

- 可错过的关键线索应有补偿来源。
- 玩家未观察到的事实不得自动授予。
- 关键 NPC 暂时不可用时应有替代信息路径或合理等待机制。
- 场景卸载/重载、读档不能造成事件重复执行或状态倒退。
- 现实切换不能清空 NPC 个人经历。

## 10. 节奏

正常聚会与人物关系 → 通讯/停电异常 → 不一致线索 → 多现实假说 → 规则与身份验证 → 社交关系崩解 → Emily 探索其他现实 → 选择与结局。

## 11. 验收

剧情事件只有在真实流程可触发、玩家信息来源正确、NPC 反应可解释、世界变化可观察、保存恢复正确、重复触发安全、自动化测试覆盖核心因果链、WorkBuddy/用户完成本地 Godot 验证后，才算完成。