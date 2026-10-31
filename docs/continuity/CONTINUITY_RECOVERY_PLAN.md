# 连贯性恢复方案（CONTINUITY_RECOVERY_PLAN）

**基准**：`recovery/master-rebuild` @ `800beb7`｜第一阶段交付物。**未实施**——待用户审查批准后进入第二阶段。
**配套**：`CONTINUITY_AUDIT.md`（现状）｜`SYSTEM_CONNECTION_MAP.md`｜`STATE_OWNERSHIP_MAP.md`｜`CONTINUITY_BUG_REGISTER.md`（CT-001…018）。

---

## 1. 修复队列（按任务九优先级）

原则：**先修多系统共同依赖的根**，不搞多脚本同款临时判断（任务规则）。

### 批次 1｜输入锁根治理（CT-001、CT-002）——一个根，两个症状

- **方案**：GameServices 增加 `InputLock`（引用计数）：`lock(owner)/unlock(owner)`，任一持有者存在时 PlayerController 跳过移动/视角/跳跃（`input_enabled` 由锁派生，保留原变量兼容测试）。暂停菜单、对话面板、（未来）手机各持有锁。
- **不做**：给每个覆盖层各写一遍 `if paused or if dialogue...`。
- **验收**：新测试「pause 时按前进 30 帧坐标不变；dialogue 同」；真实窗口复验。
- **风险**：ESC 路径需保证锁不残留（菜单/对话异常关闭时 unlock，用 owner 令牌防错还）。

### 批次 2｜NPC 状态生命周期（CT-003、CT-004、CT-013 前半）

- **方案**：NPCManager 引入**快照/恢复**统一语义：
  1. `snapshot_states()`——离场/存档共用同一结构（现 serialize 已接近）；
  2. `suspend()`——离场时快照入内存（实体照常 free）；
  3. `resume(container)`——入场时 spawn 后按快照恢复（位置/朝向/行为/行走目标）；
  4. `continue_game` 在 spawn_all 后调用 `restore(npc_states)`（修 CT-003）。
- 同时建立 `location_states` 袋（CT-013）：`{location_id: {npc: [...], items: {...}}}`，为物品状态预留，入档字段与 v2 预留 `inspected_objects/traversal_state` 对齐或明确 reserved。
- **验收**：测试 B 全绿；存档往返断言「写入字段必有消费者」。

### 批次 3｜事件输出线补全（CT-005、CT-016 半、CT-006）

- `hotspot_activated` 后 `evaluate("interact", {...})`（激活成功才求值；求值失败不阻断交互反馈，但要 push_warning）。
- evt_return_to_house：补 transition 或标注 explicitly_disabled（**不删除**，任务规则 6）。
- examine 支持子观察点 `observes[]`（CT-016），写 observe 来源认知。
- 存档字段收敛（CT-006/015）：停止写 triggered_events/known_facts（读兼容保留一版）。

### 批次 4｜反馈层（CT-007、CT-008、CT-017）

- UI 音效接线（一处装饰器）；脚步材质（footstep 带 surface 参数 + 地面标 meta）；变体缺失警告 + 静态校验。

### 批次 5｜人物与信息层（CT-009、CT-010、CT-011、CT-014）——先设计后实现

- NPC 知情/记忆/关系/情绪最小结构 + 对话双侧谓词（设计见 §5/§6）。
- 最小手机（只读台账）。
- 认知三本账升级（facts/observations/inferences）。

### 批次 6｜空间音频与真实窗口验收（CT-012、CT-018）

- 3D 播放器改造 + 17 步真实窗口走查归档。

**P0**：本轮无。若批次 1/2 实施中发现坏档类问题就地升级。

---

## 2. 状态归属规范（目标，任务 4.1）

唯一权威一览（目标态；与现状差异标注）：

| 状态 | 唯一权威 | 其他系统的合法缓存 |
| --- | --- | --- |
| 当前地点 | SceneManager | UI 时钟旁显示（订阅信号） |
| 玩家位置/朝向 | PlayerController | **落点决策**归 main（pending spawn），但写入必须经 `reset_to_spawn/restore_view` 唯一入口 |
| 当前现实 | WorldManager | GameLocation.applied_world_id（世界变更信号失效） |
| 穿越状态 | **新建 TraversalState**（事件系统内或独立）：第几次穿越、上次穿越 tick | 手机只读 |
| 事件进度 | EventManager | 手机时间线只读 |
| 物品状态 | **location_states[loc].items**（新建） | 场景呈现层 |
| NPC 位置/行为/目标 | NPCManager（快照制） | — |
| NPC 记忆/关系/情绪 | NPCManager（per-NPC，入 npc_states） | 对话系统只读 |
| 玩家认知 | CognitionManager（三本账） | 对话 requires、手机只读 |
| 手机信息 | **不设独立权威**：手机是认知/事件/关系的**视图**，自身只存「已读标记」 | — |
| 音频环境 | AudioManager（派生态，不入档） | — |
| 存档状态 | SaveManager | — |

缓存规则：允许缓存，必须在对应权威的信号/回调里失效；禁止缓存参与判定（只能展示）。

---

## 3. 事件规范（任务 4.2）

统一事件条目（JSON schema，兼容现有 fields，新增字段向后兼容）：

```json
{
  "id": "唯一ID",
  "type": "fixed | conditional | pseudo_random",
  "trigger": {"kind": "enter_location | interact | area_enter", "...键值": "..."},
  "requires": {"all": ["谓词白名单..."]},
  "prerequisites": ["前置事件ID（须在 event_history 出现）"],
  "participants": ["npc_id"],
  "world_context": "any | world_alpha | ...",
  "location": "any | party_house | ...",
  "effects": [
    {"kind": "world_transition", "to_world": "world_beta"},
    {"kind": "set_flag", "name": "...", "value": true},
    {"kind": "npc_state", "npc": "kevin", "set": {"behavior": "wander", "room": "kitchen"}},
    {"kind": "item_state", "loc": "party_house", "item": "cup", "set": {"moved": true}},
    {"kind": "grant_fact", "fact": "...", "source": "observe"},
    {"kind": "audio", "cue": "reality_shift"},
    {"kind": "log", "text": "玩家可读的叙述"}
  ],
  "repeatable": false,
  "persistent": true,
  "save": true
}
```

约束（对应任务 4.2/4.3）：
- effects 不得只发文字：`log` 必须与至少一个状态类 effect 同在（data_validator 静态检查）。
- `once/require_from_world` 语义沿用现有实现（已测）。
- 失败处理：任一 effect 失败 → 记入 out_error、世界类 effect **不生效**、状态类 effect 回滚到执行前快照（事务式：先应用前快照可丢弃）。

## 4. 状态更新顺序规范（任务 4.3）

事件执行固定顺序（防止「UI 显示完成但世界没变」等撕裂）：

```
1. 事件求值（快照语义，沿用）
2. 状态类 effects（世界→物品→NPC→认知→穿越状态）— 全部成功才继续
3. 派生表现：GameLocation.apply_world / 热点可见性 / NPC resume
4. 音频 cue（world_changed 等信号触发，不再由业务代码直接播）
5. UI 反馈（log 文案、认知提示、手机时间线）
6. 存档标记 dirty（不立即写盘；写盘只由玩家保存触发）
```

现实切换专属顺序（现状已正确，固化为规范）：**先事件（切世界）→ 后切场景**（AutoPortal 注释即此约定，保持）。

---

## 5. 玩家认知链设计（任务第五节）

三本账（升级 CognitionManager，v2 兼容读）：

| 账 | 内容 | 写入 | 不变式 |
| --- | --- | --- | --- |
| observations | 「我看到/听到什么」原始记录（带来源/世界/tick） | observe/inspect/dialogue（区分亲历/转述字段 `hearsay: bool`） | 只增不改；retract 不删观察 |
| facts | 「我确认什么」（可由观察推导或直接授予） | learn（显式确认） | retract 标记推翻保留历史 |
| inferences | 「我猜测什么」（置信度 high/low） | infer 入口（对话选项/手机标注） | **不得作为 requires 的硬条件**；可提供软提示 |

- 对话 requires 只认 facts；inferences 只影响对话文本变体（"你是说……"类回应）。
- 照片类二级观察（CT-016）：hotspot.observes[] 产生子观察+可选 fact。
- 手机展示：observations/facts/inferences 三栏，只读。

## 6. NPC 连续性设计（任务第六节）

per-NPC 状态结构（入 npc_states）：

```json
{
  "id": "kevin", "loc": "party_house", "world": "world_beta",
  "behavior": "wander|talk|idle", "goal": {"kind": "goto", "room": "kitchen"},
  "talking_to": null, "emotion": "calm|uneasy|...",
  "known_facts": ["..."], "memory": [{"tick": 12, "event": "...", "about": "player"}],
  "relationship": {"player": 0.2}, "said_nodes": ["kevin_greet"],
  "pos": [...], "rot_y": 0.0
}
```

- **行为连续性**：suspend/resume（批次 2）；恢复行走目标需重新吸附 navmesh。
- **人物认知**：NPC 只对 `known_facts`（由事件 effects/同场对话/玩家行为授予）反应；不同现实用 `world` 字段分槽记忆。
- **对话连续性**：requires 扩展 `player_knows / npc_knows / relationship_at_least / not_said / said`；文本支持 `variants[{when, text}]`；`said_nodes` 记录已发生节点（同问题二问给不同回答或明确「我说过了」）。

## 7. 手机设计（任务第七节）

最小手机（先只读，杜绝「开手机得线索」）：

- TAB 打开/关闭（持有输入锁）；三个页签：**事实台账 / 事件时间线 / 联系人**。
- 数据源：CognitionManager（facts/observations/inferences）、EventManager.sequence、NPC relationship。
- 现实差异：手机壁纸/时间戳随 world_id 变化；同一事实在不同现实的观察分组显示（数据已有 world_id）。
- 存档：仅存 `phone.read_marks`（哪些条目已读），入 `location_states` 之外的独立小字段或并入 cognition payload。
- 验证点对应任务 7 的 1-7 条（测试见 §8）。

## 8. 测试计划（任务十二）

新建 `tests/continuity/`（headless）+ `tests/continuity/real_window/`（人工记录模板）：

| 用例 | 覆盖 |
| --- | --- |
| input_lock_test | CT-001/002：暂停/对话时移动与视角锁定 |
| npc_lifecycle_test | CT-003/004：读档恢复、离场-重入连续 |
| event_effects_test | CT-005：interact 求值、effects 事务与失败回滚 |
| save_contract_test | CT-006：写读字段对称、reserved 声明 |
| audio_state_test | CT-007/008：UI 音接线、surface 脚步参数 |
| phone_consistency_test | CT-011：学事实→手机出现、不学→不出现、读档保持 |
| multi_system_test | 任务十二「多系统联动」 |

**测试 A（物品线索闭环）**：检查书桌（observe 子观察「屏幕上的数字」）→ 认知 observations+fact → 对话中出现引用该数字的选项 → 手机台账出现该观察 → 存读档后全部仍在 → 对话选项仍引用。前置=真实行走+交互（不用瞬移直接改内部状态）。
**测试 B（NPC 行为闭环）**：派 kevin 走向厨房（真实 move_to）→ 玩家离场（enter_location）→ 回场 → kevin 位置/行为/目标连续 → 与之对话一次 → 二问同题回答不同 → 存读档后 said_nodes 仍在。
**测试 C（现实切换闭环）**：真实走入 dark_far_end → 世界变 α→β → 环境变体、异常音 cue、（批次 5 后）NPC 记忆分槽、手机时间线新增 → 返回住宅 → 保存 → 重启读档 → 全部一致。

**真实窗口记录格式**（每用例）：步骤表 / 截图（关键帧）/ 会话日志 / 结论（通过/失败/观察备注）。

## 9. 移动与场景连续性检查（任务第九节，第二阶段执行）

- headless 已覆盖项保持回归；新增：门槛/门框边缘、深色区边界、家具尖角卡位的手感走查（真实窗口）。
- 跳跃负面清单复测：穿墙/越界/卡家具/导航外/垂直速度残留/读档悬空/落地音（多数已有断言，补真实窗口观察）。

## 10. 进入第二阶段的条件与停止点

1. 用户审查本恢复方案（含批次顺序、状态归属表、事件 schema）并确认/调整；
2. 确认后按批次 1→6 逐批实施：每批「相关测试→全量回归→真实窗口→更新 BUG_REGISTER→commit→汇报」；
3. 不一次性改所有模块；每批之间可叫停；
4. 全部批次完成后产出 `CONTINUITY_FINAL_REPORT.md`（任务十四的 10 问 + 六级结论标注）。

**剧情边界**：全程不写电影主线；测试事件/NPC 一律标注 `*_test` 数据命名空间，与正式内容隔离。
