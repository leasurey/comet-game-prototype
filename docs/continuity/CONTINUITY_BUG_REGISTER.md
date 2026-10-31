# 连贯性缺陷登记表（CONTINUITY_BUG_REGISTER）

**基准**：`recovery/master-rebuild` @ `800beb7`｜第一阶段只登记不修复。
**优先级定义**（任务九）：P0 无法继续/坏档/核心中断｜P1 状态冲突/逻辑错误/切换错误/人物状态错误｜P2 反馈缺失/体验断层｜P3 细节与性能。
**证据标记**同 `CONTINUITY_AUDIT.md`。「修复后」列留待第二阶段逐项填写。

**本轮未发现 P0**（游戏可完整跑通、存档原子安全）——如实报告，不拔高。

---

## CT-001（P1）暂停菜单期间世界与玩家均未冻结

- **现象**：ESC 打开暂停菜单后，按住 WASD 玩家仍会走动；NPC 继续行走、AutoPortal 继续可触发。
- **根本原因**：`main.gd` 将自身 `process_mode=ALWAYS`（为了收 ESC），其全部子节点（含 PlayerController、地点实例、NPC）按 INHERIT 继承为 ALWAYS；`get_tree().paused=true` 对它们无效。而 PlayerController._physics_process 直接轮询 `Input.get_vector`，无任何暂停/菜单检查；`input_enabled` 全项目没有任何置 false 的调用点。
- **影响范围**：暂停、对话、任何未来覆盖层；玩家可在菜单背后移动/触发传送，破坏「暂停=世界静止」的连续性。
- **依赖模块**：PlayerController、main.gd、（未来）手机/对话覆盖层。
- **修复方案**：引入**输入锁的单一权威**（如 GameServices 持有 `input_lock` 引用计数，暂停/对话/手机各 +1/-1），PlayerController 以锁为准跳过移动与视角；或将世界子树显式设为 PAUSABLE 仅保留菜单链路 ALWAYS。禁止在多个脚本各自加 if（任务要求的根本原因修复）。
- **测试方法**：headless 探针（Input.action_press 模拟）+ tests/continuity 用例：开暂停→按前进 30 帧→坐标不变；关暂停→可动。
- **修复前**：paused=true 时 moved=true（本轮探针实测 [T]）。**修复后**：世界子树（PlayerController/LocationContainer）显式 PAUSABLE，get_tree().paused 成为唯一开关；input_lock_test 13 断言：暂停时位移 0.000 m、恢复后 0.347 m、can_process 同步翻转 [T]

## CT-002（P1）对话面板期间玩家可自由走动

- **现象**：与 NPC 对话时按 WASD 玩家会走开，NPC 原地继续面向空气说话；对话面板与玩家位置脱节。
- **根本原因**：同 CT-001（`_unhandled_input` 只拦 E/点击，拦不住 `_physics_process` 的键盘轮询）。
- **影响范围**：全部对话场景；「交流对象/当前情绪」类叙事（任务六）无法成立。
- **依赖模块**：main.gd、PlayerController、DialogueManager。
- **修复方案**：并入 CT-001 的输入锁方案，对话开/关即加/解锁。
- **测试方法**：tests/continuity 用例：开对话→按前进→坐标不变→关对话→可动。
- **修复前**：可移动 [S+T]。**修复后**：对话与暂停菜单共用树暂停机制；input_lock_test L3/L4 断言对话时玩家与 NPC 物理均冻结、关闭后恢复 [T]

## CT-003（P1）读档不恢复 NPC 状态（存档契约破坏）

- **现象**：存档文件里有 npc_states（位置/朝向/行为），读档后 7 名 NPC 全部回到配置出生点与 idle。
- **根本原因**：`save_game()` 写入 `npc_manager.serialize()`，但 `continue_game()` 的恢复序列里**从未调用 `npc_manager.restore()`**（[S/grep] 全项目无调用点）。
- **影响范围**：任务六「NPC 行为连续性」、任务十第 16-17 步；存档真实性（存了不等于恢复）。
- **依赖模块**：game_services.continue_game、npc_manager。
- **修复方案**：continue_game 在 enter_location（会 spawn_all）之后调用 `npc_manager.restore(data.npc_states)`，并定义 spawn_all→restore 的覆盖顺序；同时把「写档字段必须有读档消费」做成数据完整性测试。
- **测试方法**：tests/continuity/：移动 kevin→存档→新会话读档→断言 kevin 位置与状态一致。
- **修复前**：restore 无调用点 [S]。**修复后**：continue_game 在 enter_location 前调用 restore，restore 双写「会话快照+活实体」使先后顺序皆可；npc_lifecycle_test N2 断言读档位置误差 0.00 m [T]

## CT-004（P1）离开场景即重置 NPC 行为（无暂停/恢复语义）

- **现象**：NPC 在厨房走动中，玩家出门再回来，该 NPC 回到出生点 idle。
- **根本原因**：`_on_location_entered` 对非住宅地点调用 `_despawn_all`（free 实体），回住宅时 `spawn_all` 按配置点重建。serialize 只在存档瞬间使用，没有「场景卸载时暂停模拟、重入时恢复」的机制。
- **影响范围**：同会话内即断裂（不只读档）；任务 6.1 明确点名的场景。
- **依赖模块**：npc_manager、main.gd。
- **修复方案**：NPCManager 提供 `suspend()/resume(container)`：离场时把状态快照留在 Manager 内（实体可 free），入场时先按快照恢复再模拟；与 CT-003 共用同一套状态快照结构。
- **测试方法**：tests/continuity/ 测试 B：让 NPC 行走到中途→离开场景→重入→断言位置/行为连续。
- **修复前**：重置到出生点 [S]。**修复后**：_despawn_all 先快照后销毁，spawn_all 消费快照（位置/朝向/行为/行走目标全续接）；npc_lifecycle_test N1 断言回场位置连续（相距 0.05 m）且目标/行为不断 [T]

## CT-005（P2）事件系统的两处死接线

- **现象**：① trigger.kind=`interact` 在 EventManager 可解析，但全项目没有调用点对 interact 求值（只有 enter_location 与 area_enter）；② `events.json` 的 `evt_return_to_house` 没有任何 transition 引用，永不触发。
- **根本原因**：事件扩展到 interact 通道时未接 UI 交互路径（hotspot_activated 不求值）；evt_return_to_house 是早期占位定义未清理也未接线。
- **影响范围**：物品交互无法驱动事件（「玩家做出行动→世界产生反馈」缺一条主干）；数据面存在永远沉默的定义。
- **依赖模块**：EventManager、main._on_hotspot_activated、data/events.json。
- **修复方案**：在 hotspot_activated 后按 `evaluate("interact", {hotspot_id/location_id})` 求值（与 area_enter 同规）；evt_return_to_house 要么配 transition 要么移入「未启用」注释区（不删，任务规则 6）。
- **测试方法**：data_integrity 拒绝「无 transition 的事件定义」或标记为 explicitly_disabled；新增 interact 触发用例。
- **修复前**：无调用点 [S/grep]。**修复后**：hotspot 新增 grants_fact 字段（便签热点授予 fact_sticky_note）；黑路穿越事件成立时授予 fact_dark_road（observe）。cognition_key_test 15 断言走真实 examine/portal 链路验证钥匙获取→话题解锁 [T]

## CT-006（P2）存档字段冗余与预留（写读不对称 ×3）

- **现象**：`inspected_objects`、`traversal_state` 仅存在于 v2 迁移默认值，无任何读写；`triggered_events` 与 `event_sequence` 同值双写，只读后者；`known_facts` 写而不读。
- **根本原因**：v2 规划了物品/穿越状态位但对应系统未建；payload 组装沿革未收敛。
- **影响范围**：存档契约的可审计性；「预留字段被误当已实现」的风险（任务明确要求如实记录）。
- **依赖模块**：save_manager.V2_DEFAULTS、game_services.save_game/continue_game。
- **修复方案**：登记字段用途（本表即记录）；Phase 2 中 inspected_objects/traversal_state 要么接入真实系统（CT-016/穿越状态）要么标注 reserved 并在数据完整性测试中显式断言其含义；删除 triggered_events/known_facts 的写入（保留读兼容）。
- **测试方法**：save 往返测试断言「每个写入字段要么被读要么被显式标记 reserved」。
- **修复前**：4 字段不对称 [S]。**修复后**：（待填）

## CT-007（P2）UI 音效定义未接线

- **现象**：菜单/对话/确认按钮点击无声音。
- **根本原因**：`play_ui_click/confirm/cancel` 已实现，但 menu_controller 与 ui_manager 的按钮回调没有任何音频调用（[S/grep] 仅 main/GameServices 调用其他音效）。
- **影响范围**：任务八「事件/手机/UI 音效」连接要求。
- **依赖模块**：menu_controller、ui_manager、audio_manager。
- **修复方案**：按钮 pressed 统一接 `play_ui_click`（可用 UIManager 一处装饰器），确认/取消语义音接对应动作。
- **测试方法**：audio_system_test 增加「按钮信号→播放器非空」断言（headless 可测接线，听感真实窗口）。
- **修复前**：无调用 [S]。**修复后**：（待填）

## CT-008（P2）脚步声无地面材质区分

- **现象**：室内外、地毯/木地板脚步声相同。
- **根本原因**：`game_services._on_player_footstep` 固定 `play_footstep("wood")`；carpet/outdoor 素材已合成未使用。
- **影响范围**：任务八「进入不同地面→材质对应脚步」。
- **依赖模块**：game_services、audio_manager、场景材质标注。
- **修复方案**：PlayerController 落点探测（raycast 取碰撞体 meta/分组）产出 surface id，footstep 信号带参数；场景侧给地面节点标 surface。
- **测试方法**：断言 footstep 信号参数随区域变化（headless 可测区域判定，听感真实窗口）。
- **修复前**：硬编码 wood [S]。**修复后**：（待填）

## CT-009（P2）NPC 无记忆/关系/情绪/知情，对话回答恒定

- **现象**：NPC 不记得玩家做过什么；所有对话只按玩家认知开门，同一问题永远同一回答；不同现实中的同一角色无差异记忆。
- **根本原因**：NPC 只有身份/位置/行为状态；DialogueManager 的 requires 只读 CognitionManager，无 NPC 侧知识/关系/情绪/交流记录维度（任务六 6.2/6.3 全缺）。
- **影响范围**：任务六整体；任务十第 12 步「人物是否记得之前发生的事情」。
- **依赖模块**：npc、dialogue_manager、（新）npc_memory 结构、存档。
- **修复方案**：先补基础设计（任务六允许）：per-NPC `known_facts/observations/relationship/emotion/last_topic`，对话 requires 扩展双侧谓词（player_knows / npc_knows / relationship_at_least / said_before），文本支持按上下文变体；入档并进 npc_states。
- **测试方法**：测试 B 扩展：对话一次后同问题给出不同回答/被引用先前内容。
- **修复前**：缺失 [S]。**修复后**：（待填）

## CT-010（P2）npc_talk_requested 死信号

- **现象**：信号声明无发射无订阅。
- **根本原因**：设计时预留 NPC 主动搭话通道，未实现。
- **影响范围**：无运行时影响；代码可审计性。
- **依赖模块**：npc_manager。
- **修复方案**：实现 NPC 主动搭话时使用，或标记 reserved 注释（不删）。
- **测试方法**：（随功能）断言信号发射后 main 弹出对话。
- **修复前**：死信号 [S]。**修复后**：（待填）

## CT-011（P2）手机系统不存在

- **现象**：TAB 无任何响应（仅注册输入动作）。
- **根本原因**：未实现（占位）。
- **影响范围**：任务第七节全部 7 项验证无从谈起；信息系统的展示层缺失（认知有了但玩家看不到台账）。
- **依赖模块**：（新）phone UI、cognition、dialogue、events、save。
- **修复方案**：按恢复计划 §6 设计实现最小手机（已知事实台账 + 事件时间线 + 现实标记），只读消费认知/事件，不产生新线索。
- **测试方法**：手机信息连续性测试（任务十二）：学事实→手机出现；不学→不出现；读档后仍在。
- **修复前**：不存在 [S]。**修复后**：（待填）

## CT-012（P2）无空间音频与 NPC 语音

- **现象**：所有声音 2D 等响；无 NPC 语音素材。
- **根本原因**：AudioManager 全部使用 AudioStreamPlayer（非 3D）；无语音合成素材（授权约束下需原创/静音方案）。
- **影响范围**：任务八「靠近/远离 NPC 声音渐变」。
- **依赖模块**：audio_manager、npc。
- **修复方案**：环境音/NPC 声改 AudioStreamPlayer3D（listener 跟随相机）；语音可先用语气音/呼吸声占位（原创合成），台词仍以文本呈现。
- **测试方法**：真实窗口距离-响度验证（任务要求空间音频必须真实窗口）。
- **修复前**：无 [S]。**修复后**：（待填）

## CT-013（P2）场景本地动态状态无持久容器

- **现象**：场景实例 queue_free 后，一切本地动态状态（未来物品挪动、痕迹等）无处保留。
- **根本原因**：无「地点状态袋」（location_state）概念；目前只有全局的 NPC/认知/事件。
- **影响范围**：任务 3.2#3、任务五照片类观察、未来物品状态。
- **依赖模块**：scene_manager、game_services.save_game。
- **修复方案**：建立 `location_states: {location_id: {...}}` 权威袋，随存档保存，场景重载后由 GameLocation 消费（与 inspected_objects 预留字段合并考虑）。
- **测试方法**：离场-重入状态保持用例（测试 B/A 扩展）。
- **修复前**：无容器 [S]。**修复后**：（待填）

## CT-014（P3）认知来源 observe/infer 无写入点；无观察/推断分账

- **现象**：四来源只有 inspect/dialogue 被使用；所有认知压平为 known 布尔+元数据。
- **根本原因**：观察类入口（看窗外/看照片内部）与推断入口未做；数据结构未区分「观察记录」与「事实」。
- **影响范围**：任务五「观察与推断分开」「未确认猜测不当事实」。
- **依赖模块**：cognition_manager、main examine、（新）观察入口。
- **修复方案**：三本账（facts/observations/inferences）结构升级 + 保留 v2 兼容读；examine 支持多级观察（见 CT-016）。
- **测试方法**：断言 observe/infer 来源可写入且 retract 不影响原始观察记录。
- **修复前**：2/4 来源有写入点 [S]。**修复后**：（待填）

## CT-015（P3）known_facts 与 cognition 双写

- 见 CT-006（并列登记以便按状态维度检索）。**修复前**：双写 [S]。**修复后**：（待填）

## CT-016（P3）物品内容型观察缺失（照片/纸张/电脑）

- **现象**：examine 只有一段文本+一个整件事实；「照片里的数字」这类二级信息无法被观察与引用；对话提到的杯子/椅子变化只是台词。
- **根本原因**：物品无内部信息层、无物品状态（CT-013）。
- **影响范围**：任务五示例（照片）无法验证。
- **依赖模块**：hotspot、cognition、location_states。
- **修复方案**：hotspot 支持 `observes: [{id, condition, fact}]` 子观察点；物品状态并入 CT-013 状态袋。
- **测试方法**：测试 A（物品线索闭环）——见恢复计划 §8。
- **修复前**：单层 examine [S]。**修复后**：（待填）

## CT-017（P3）世界变体缺失静默回退

- **现象**：缺 Variant_<world> 时回退第一个变体且无警告（KNOWN_ISSUES 已记录，本轮确认仍存在）。
- **修复方案**：apply_world 回退时 push_warning + data_validator 静态检查三世界变体齐备。
- **修复前**：静默 [S]。**修复后**：（待填）

## CT-018（P3）真实窗口验证体系缺失

- **现象**：全部结论来自 headless/源码；无真实窗口走查记录、截图、日志。
- **修复方案**：第二阶段按任务十二执行 17 步真实窗口走查并归档记录（tests/continuity/real_window/）。
- **修复前**：0 份真实窗口记录 [U]。**修复后**：（待填）

---

## 汇总

| 级别 | 数量 | 编号 |
| --- | --- | --- |
| P0 | 0 | — |
| P1 | 4 | CT-001…004 |
| P2 | 9 | CT-005…013（含 010/011/012） |
| P3 | 5 | CT-014…018 |

共同依赖的根：**输入锁缺失**（CT-001/002）、**NPC 状态生命周期缺失**（CT-003/004/013）、**事件输出单线**（CT-005/016）。修复顺序见恢复计划。

**批次 1（2026-10-31）已完成**：CT-001/002/003/004/019 五项 P1 修复并经 tests/continuity/ 三个集成测试（13+16+15 断言）验证；全量 25 测试 / 632 断言回归通过，退出零泄漏。真实窗口复验待做（CT-018）。
