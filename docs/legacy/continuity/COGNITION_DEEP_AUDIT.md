# 认知系统深度审查（COGNITION_DEEP_AUDIT）

**基准**：`recovery/master-rebuild` @ `800beb7`｜只读审查｜证据分级 A/B/C/D（见 NPC_DEEP_AUDIT 文首）。
**核心源码**：`core/cognition_manager.gd`（177 行）；写入点：`scenes/main.gd:479-484`（inspect）、`core/dialogue_manager.gd:97-108`（dialogue）。

---

## 1. 十问逐项（任务第五节 1-10）

| # | 问题 | 结论 | 证据 |
| --- | --- | --- | --- |
| 1 | 认知唯一标识如何生成？ | 两种：①数据目录手写 id（dialogue.json `facts` 22 条，载入 cognition_manager.load_from_data:35）；②inspect 模板 `"fact_inspected_%s" % spot.name`（main.gd:484）。**模板 id 与对话闸门 id 不同命名空间**——后果见 §2 | **A** |
| 2 | 记录来源？ | 是。source_kind/source_id（learn:69-87） | **A**；**B**（cognition_npc_test C2「来源标记为 inspect」） |
| 3 | 区分亲眼检查/听对话/阅读/推断？ | **类型系统上分四类**（inspect/dialogue/observe/infer，:25-28），但**实际只有 2/4 有写入点**（inspect、dialogue）；observe/infer 零调用 [grep]。「听对话」还**不区分亲历与转述**（无 hearsay 字段） | **A** |
| 4 | 记录现实 ID？ | 是。world_id 写入（learn 第 4 参） | **A+B**（C2「记录了所在现实」） |
| 5 | 记录游戏时间？ | 是。tick 字段 | **A** |
| 6 | 未观察自动获得信息？ | **不会**。learn 只在两处被调；世界切换零授予（C1 实测「切换前 0 条→切换后 0 条」）；对话 requires 未满足不可见 | **B**（cognition_npc_test C1/N4，本轮复跑通过） |
| 7 | 世界改变后旧认知被错误覆盖？ | **不会**。世界变更不触碰 _facts；learn 重复学习不覆盖首次来源（:79-80 直接 return false） | **B**（C4） |
| 8 | 区分已确认事实与个人推断？ | **不区分**。retract 可标记推翻（:92-101）但**retract 全项目零调用点** [grep]；infer 无写入点；全部认知压平为 known 布尔+元数据，无置信度/未确认态 | **A** |
| 9 | 正确进入存档？ | 是。save_game 写 `cognition`（serialize:155=known_order+facts 全量） | **A+B**（C5 存档可读回） |
| 10 | 读档完整恢复？ | 是。continue_game:445 调 cognition.restore，逐条恢复含来源/世界/tick/retracted | **B**（C5「认知条数一致」） |

## 2. 关键缺陷：闸门钥匙在真实游玩中不存在（新 CT-019，P1）

**现象** [A+B]：`dialogue.json` 有 5 个节点的 `requires` 依赖 `fact_sticky_note` 或 `fact_dark_road`，但——

1. **没有任何对话节点授予这两个事实**（脚本穷举 grants 集合，20 个可授予事实不含它们）；
2. **inspect 写入的是 `fact_inspected_<热点名>`**（如 `fact_inspected_DiningTableSpot`），与闸门 id 不同名，无法解锁；
3. 事件/穿越/观察路径均无其他 `learn` 调用点（全项目仅 2 处，见文首）。

传播闭包（脚本按 requires/grants 迭代计算）：**29 个对话节点中 9 个在真实游玩中永久不可达**：

```
fact_sticky_note 锁死：kevin_sticky、kevin_number、hugh_sticky
fact_dark_road   锁死：mike_dark、mike_wrong、lee_dark、laurie_after
传递锁死：lee_conclusion（需 fact_lee_deep，唯一授予者 lee_dark）、
          laurie_two（需 fact_laurie_saw_you，唯一授予者 laurie_after）
```

**测试为何没发现** [B]：`cognition_npc_test` N4 与 `dialogue_ui_test` U6 直接 `_svc.cognition.learn("fact_sticky_note", ...)` **手工注入钥匙**再断言解锁——测试验证了闸门机制，却用伪造前提跳过了「钥匙是否可获得」。这正是任务九警告的"使用模拟对象导致真实流程未覆盖"。

**影响**：认知-对话闭环（链路 A）只对 20/29 节点成立；玩家在真实游戏中永远问不出便签与黑路话题。修复见 SUMMARY 优先级。

## 3. 系统连接盘点（任务第五节"特别注意"）

| 连接 | 状态 | 证据 |
| --- | --- | --- |
| Cognition → DialogueManager | ✅ `requires` 经 `_requirements_met`（dialogue_manager.gd:122）读 `cognition.knows` | **A+B**（N4） |
| Cognition → UIManager | ✅ 授予后面板 hint「你了解到…」（main.gd `_show_dialogue_node` hint 组装） | **B**（dialogue_ui_test U4） |
| Cognition → 手机 | ❌ 手机不存在（前轮 CT-011） | **A** |
| WorldManager → Cognition | ✅ 有意零连接（世界变≠玩家知） | **B**（C1） |
| EventManager → Cognition | ❌ 事件 effects 无 grant_fact 类输出（世界迁移是唯一效果） | **A** |
| Cognition → 存档 | ✅ 写读对称（`cognition` 字段） | **B**（C5） |
| ~~`known_facts` 字段~~ | ⚠️ 写而不读的冗余副本（前轮 CT-015） | **A** |

**结论**：认知与客观世界**确实分离**（问题 3 的答案为「是」，且有测试证据）；但认知的**产出入口太窄**（2 个）、**消费出口太少**（对话闸门 + UI 文本），且闸门钥匙断供（CT-019）。

## 4. 前轮 CT-014/015/016 深度确认

- observe/infer 零写入点 →「观察与推断分开」仅停留在类型定义 [A]；
- 无"观察流水"台账，所有认知同构 [A]；
- `inspected_objects` v2 预留字段仍无读写（与物品二级观察 CT-016 同源）[A]。
