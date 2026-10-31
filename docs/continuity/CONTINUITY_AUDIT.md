# COMET 连贯性审计报告（第一阶段）

**审计对象**：`recovery/master-rebuild` @ `800beb7`（工作分支 `recovery/continuity-integration`，内容一致）
**审计日期**：2026-10-31
**性质**：只读审计。本阶段未修改任何运行时代码。
**方法**：完整读取 core/、scenes/、autoload/、data/、tests/ 源码与数据（非依据 README 或旧报告），辅以一次性行为探针（用后即删）。

**证据等级标记**：

| 标记 | 含义 |
| --- | --- |
| **[S]** | 源码事实：直接读自当前提交的代码/数据 |
| **[T]** | 测试结果：现有自动化测试或本轮一次性探针的实测输出 |
| **[D]** | 设计推断：依据源码结构推理，未直接观测 |
| **[U]** | 未验证：缺少证据（含全部真实窗口体验项） |

---

## 0. 总体结论（一段话）

各个系统**单独看都是真实实现且有测试覆盖**，但它们围绕「世界状态」的协作有四处结构性断裂：
**① 输入锁定缺失**（暂停/对话期间玩家仍可行走，[T] 实测）；
**② NPC 状态生命周期断裂**（存档写了 npc_states 但读档不恢复；离开场景即重置）；
**③ 事件只连了世界切换一条输出线**（interact 触发器、物品/NPC/音频的事件响应都未接线，且有死数据）；
**④ 信息系统（手机）完全不存在**，认知系统已建成但只被对话/查看两个入口消费。
无 P0 级「无法继续/坏档」缺陷；最严重的是 4 个 P1 连贯性缺陷。

---

## 1. 玩家行动链（任务 3.1）

链路定义：输入 → PlayerController → 移动/跳跃 → 碰撞 → 交互检测 → 交互执行 → 事件系统 → 世界状态 → UI 反馈 → 音频反馈 → 存档。

| # | 检查项 | 结论 | 证据 |
| --- | --- | --- | --- |
| 1 | WASD 移动 | 正常。Input.get_vector 归一化，斜向不加速；仅用 yaw 计算方向 | [S] player_controller.gd；[T] player_movement_test 34 断言 |
| 2 | 鼠标视角 | 正常。捕获后 relative 增量，yaw 环绕收敛，pitch ±75°，全弧度 | [S]；[T] fps_input_test 29 断言 |
| 3 | 跳跃 | 正常。0.12s 输入缓冲，仅地面可跳，初速 4.8（≈0.64m，可过门槛不可上台） | [S]；[T] player_jump_test 26 断言 |
| 4 | 落地 | 正常。landed 信号带冲击速度，落地状态 0.12s | [S]；[T] jump test |
| 5 | 碰撞 | 正常。玩家 layer2/mask1，NPC layer4 不挡玩家与门口 | [S]；[T] movement test T12 挡断言、party_house 54 断言 |
| 6 | 交互距离 | 2.5 m 上限 + 激活时二次校验（防走开后隔空交互） | [S] interaction_manager.gd |
| 7 | 隔墙错误交互 | 有遮挡判定（环境射线距 ≤ 热点距才允许）；全部热点可正常聚焦 | [S]；[T] acceptance_test 聚焦组 |
| 8 | 场景切换位置/朝向 | 门级落点（target_spawn/target_yaw_deg）按「从哪扇门进」落位；无门级数据回退地点 spawn | [S] main.gd pending 机制、house_party.gd；[T] door_connection_test 53 断言 |
| 9 | **暂停锁定** | **不合格**。暂停只停 UI 计时器，不停世界：Main.process_mode=ALWAYS 被全体子节点继承，PlayerController 每帧直接轮询 WASD。**实测暂停菜单打开时按 W 仍移动** | [T] 本轮探针：paused=true, can_process=true, moved=true；[S] process_mode 继承 |
| 10 | **对话锁定** | **不合格**。对话面板只在 `_unhandled_input` 拦截 E/点击，WASD 由 `_physics_process` 轮询不受控，可边对话边走开；NPC 还在原地对着空气说话 | [S] main.gd + player_controller.gd；`input_enabled` 全项目无任何置 false 的调用点 [S/grep] |
| 11 | 手机界面锁定 | **无从验证**：手机系统不存在（TAB 仅注册了输入动作） | [S/grep] core/scenes 无 phone 实现 |
| 12 | 读档后玩家状态 | 位置/朝向/速度恢复正确；胶囊重叠检测防嵌墙；读档走 enter_location→spawn→覆盖为存档坐标 | [S] game_services.continue_game；[T] save_migration 27 断言 |
| 13 | 重复保存同一状态 | **存在**：`known_facts` 与 `cognition` 双写同一事实集合；`triggered_events` 与 `event_sequence` 同值双写。读档只消费 cognition/event_sequence，另两份是死数据 | [S] game_services.save_game payload 对照 continue_game |

**行动链中间件的意图表达**（进度 6「事件是否合理反馈」的基础）：交互后有 toast 提示 + 音效（查看/开门），但没有世界状态层面的反馈（物品状态不变、NPC 不反应）——见 §2。

---

## 2. 世界状态链（任务 3.2）

链路定义：事件触发 → 世界状态改变 → 场景表现改变 → 物品状态改变 → NPC 状态改变 → 玩家可观察信息改变 → 存档更新。

| # | 检查项 | 结论 | 证据 |
| --- | --- | --- | --- |
| 1 | 事件是否只记录不改世界 | **改世界是真的**：evaluate→apply_transition 是世界唯一变更入口，且有历史记录 | [S] event_manager/world_manager；[T] reality_cycle_test 19 断言 |
| 2 | 事件的「其余输出线」 | **未接线**：事件不改物品、不改 NPC、不改音频（除 world_changed→reality_shift 音效一条）。场景表现只到 Variant 切换 + 热点可见性 | [S] 全项目唯一 evaluate 调用点只有 2 处 |
| 3 | 场景切换后旧状态保留 | **不保留**：场景实例 queue_free，动态状态无处安放。NPC 有 serialize 但每次进屋重生到配置点（见 CT-004） | [S] scene_manager._release_current |
| 4 | 不同现实是否共享不该共享的状态 | 世界隔离正确：变体节点按 world_id 隔离，热点 visible_only_in_worlds 按世界过滤，认知记录 world_id 归属 | [S] location.gd、hotspot.gd、cognition_manager.gd |
| 5 | 事件重复触发 | 三条 dark_far_end 规则都 once=false（有意循环），靠 require_from_world 保证按 α→β→γ→α 顺序，错序不触发 | [S] world_transitions.json；[T] dark_traverse_test 31 断言 |
| 6 | 事件中途离开场景 | 事件求值是同步原子操作；求值失败时**不切场景**（防「人过去了现实没变」） | [S] main._on_portal_entered |
| 7 | 重新进入场景恢复 | 按当前世界重新 apply_world + 热点可见性正确；但 NPC/动态物件不恢复（同 #3） | [S]；[T] session_reset_test 17 断言（仅会话级） |
| 8 | 存档与当前场景一致 | 存档写 location_id/world_id/cognition/npc_states 一致快照；**读档不消费 npc_states**（CT-003） | [S] save payload vs continue_game |

**事件数据现状**（[S] data/）：
- `events.json` 仅 2 条定义：`evt_cross_dark_road`、`evt_return_to_house`。
- `world_transitions.json` 仅 3 条转移（全部是 dark_far_end 循环）。
- `evt_return_to_house` **没有任何转移规则引用它**，永不触发（CT-005）。
- trigger.kind=`interact` 在 EventManager 中已实现，但**全项目没有一处对 interact 求值**（CT-005）。

---

## 3. 玩家认知与线索链（任务第五节）

**现状判定：认知系统是真实现，但只是「半个信息系统的地基」。**

已实现 [S+T]：
- 事实目录（dialogue.json `facts`，22 条）+ learn/knows/retract，重复学习不覆盖首次来源（cognition_npc_test C4）。
- 来源四分类定义：inspect / dialogue / observe / infer；实际写入点只有 **inspect（查看物品）与 dialogue（对话授予）2/4**。
- 每条事实记录 world_id、tick、source_kind、source_id（跨现实归属正确）。
- 对话 `requires` 闸门读取玩家认知（没查过便签就听不到便签话题）——N4 断言覆盖。
- 存档恢复认知（C5），新局清空（C6）。

对照任务五要求的缺口：

| 要求 | 现状 | 等级 |
| --- | --- | --- |
| 只有观察到的信息才成为已知事实 | ✅ 成立：learn 只由 inspect/dialogue 写入，世界切换不授予（C1 断言） | [T] |
| 亲听对话 vs 他听对话区分 | ❌ 无区分：dialogue 来源只记 speaker，无「谁在场/转述」维度 | [S] |
| 观察与推断分开 | ⚠️ 类型上分开（observe/infer 已定义），**实际没有任何代码产生 observe/infer 来源**；也无独立的观察流水/推断台账，全部压平为 known 布尔+元数据 | [S] |
| 未确认猜测不当事实 | ⚠️ infer 语义有注释声明「推断可能出错」，retract 可推翻，但无「置信度/未确认」状态 | [S] |
| 跨现实信息归属 | ✅ 记录 world_id | [T] |
| 读档不丢已知信息 | ✅ C5 断言 | [T] |
| 手机不自动获得线索 | 无手机（恒成立但无意义） | — |
| 对话选项读取已知信息 | ✅ requires 闸门 | [T] |
| 不做成布尔值集合 | ❌ 结构仍是「已知/未知」布尔 + 辅助元数据；无「事实/观察记录/推断」三本账 | [S] |
| 照片等特殊信息需真正观察到 | ❌ 物品没有「内部信息」层：examine 只产出一条整件物品事实（fact_inspected_<名字>），无法表达「看到照片里的数字」这种二级观察 | [S] main.gd examine 分支 |

**预留字段如实登记**：存档 v2 的 `inspected_objects`、`traversal_state` 只在迁移默认值里出现，**没有任何读写方**（[S/grep]）。`known_facts` 写入但读档不用（被 cognition 取代）。

---

## 4. NPC 与人物连续性（任务第六节）

**现状判定：NPC 是「会走路的档案+对话机」，任务六要求的人物层（记忆/关系/情绪/知情）全部未实现。**

已有 [S+T]：
- 7 个角色档案（characters.json），navmesh 寻路、分离转向避让（对向错车不重叠）、逐帧状态（idle/walking/talking）。
- 位置/朝向/状态**可序列化**（npc_manager.serialize → 存档 npc_states）。
- 对话受玩家认知闸门控制。

缺口（对照任务六）：

| 要求 | 现状 | 等级 |
| --- | --- | --- |
| 唯一身份 | ✅ id + name + home | [S] |
| 当前地点/现实/行为 | ⚠️ 行为状态有（idle/walking/talking）；地点/现实不记录在 NPC 身上（隐含于所在场景） | [S] |
| 当前目标/交流对象 | ❌ 无（_target 私有瞬时值，不入档） | [S] |
| 情绪/关系 | ❌ 无任何字段 | [S/grep] |
| 已知信息/个人记忆 | ❌ 无 NPC 侧知识；对话不读 NPC 知情 | [S] |
| 事件参与记录 | ❌ 无 | [S] |
| 行为连续性（6.1） | **不合格**：离开场景 `_despawn_all` 即销毁；再进屋按配置出生点重生。**存档写了 npc_states 但 continue_game 从不调用 npc_manager.restore()**（[S/grep] 无调用点）——读档后 NPC 全员回到初始位 | [S] |
| 人物认知（6.2） | ❌ 无 per-NPC 信息面 | [S] |
| 对话连续性（6.3） | ⚠️ 只读「玩家已知事实」一项；不读当前事件/现实/关系/情绪/交流记录。同一问题永远同一回答（文本静态），仅「能不能问到」随认知变化 | [S] dialogue_manager.gd |

另：`npc_manager.npc_talk_requested` 信号声明后**从未 emit、无人订阅**（[S/grep]，死信号）。

---

## 5. 手机、物品与线索整合（任务第七节）

**手机系统不存在。** 全项目唯一痕迹是 `game_services._ensure_input_actions()` 注册了 `phone`=TAB 键（[S/grep] core/scenes 无任何 phone 实现/界面/数据）。任务第七节的 7 项验证全部**无从验证（未实现）**。

物品侧现状：
- 可查看热点（餐桌/壁炉/厨房台面/书桌/信箱/车/玻璃碎片等）有 examine 文本 + inspect 认知（fact_inspected_*）。
- 无物品状态（被移动/被使用/被替换）、无照片/纸张/电脑这类「内容型物品」、无与事件的物品联动。对话文本里提到的「干掉的杯子/椅子换位」**只是台词**，没有任何物品状态或观察记录支撑（[S] 无对应数据/代码）。
- 检查物品→认知记录→对话闸门这条**细链路是通的**（测试 A 的核心可先行验证的部分）。

---

## 6. 音频与状态整合（任务第八节）

已有 AudioManager（真实实现，非占位）：9 类 AudioStreamPlayer、分类音量×总音量、设置持久化、退出清理。

| 要求连接 | 现状 | 等级 |
| --- | --- | --- |
| 移动→脚步 | ✅ 按步距 1.3m 触发，停下即停 | [S+T] audio_system_test |
| 跳跃/落地→音效 | ✅ jumped/landed 信号接线 | [S+T] |
| **地面材质→脚步** | ❌ 硬编码 `play_footstep("wood")`（game_services:305）；carpet/outdoor 素材已合成但**无调用** | [S] |
| 开门→门音效 | ✅ exit 热点激活时 play_door_open | [S] |
| **靠近/远离 NPC 声音** | ❌ 无。全部播放器是 2D（AudioStreamPlayer），无 3D 空间衰减、无 NPC 语音素材 | [S/grep] |
| 场景变化→环境音 | ✅ set_ambience 按室内/室外切换循环音 | [S] |
| **停电事件→电器声停** | ❌ 无停电事件（数据中不存在），电器音效亦不存在 | [S] |
| 现实切换→异常音 | ✅ world_changed→play_reality_shift | [S+T] |
| **手机 UI 音** | ❌ 无手机 | — |
| **事件音效** | ⚠️ 仅现实切换有；其他事件无独立声音反馈 | [S] |
| UI 音效（点击/确认/取消） | ❌ **定义了未接线**：play_ui_click/confirm/cancel 无任何调用点，菜单与对话按钮静音 | [S/grep] |
| 停止移动脚步即停 | ✅ 步距触发天然满足 | [T] |
| 场景卸载旧音频停 | ✅ 环境音随类别复用播放器，切换覆盖；退出清理 shutdown | [T] |
| 同事件不重复放音 | ✅（音效由单次动作驱动） | [S] |
| 音频设置持久化 | ✅ settings.json | [S+T] |
| 空间音频真实窗口测试 | ❌ 无空间音频实现，无真实窗口测试 | [U] |

---

## 7. 移动、跳跃与场景连续性（任务第九节）

已测 [T]：行走/奔跑/跳跃/落地/家具碰撞（T12 挡断）/门口出生点/场景切换/读档位置恢复。
跳跃负面清单逐项 [S]：穿墙——胶囊+碰撞无穿透路径；越界——室外边界有碰撞（wall_geometry/party_house 测试）；卡家具——与家具同层碰撞可滑出（0.2 贴边滑行已知特性）；**跳出导航区域——无防护但影响仅限 NPC 寻路，玩家不受限**；切场景残留垂直速度——`reset_to_spawn` 清零 velocity ✓；读档悬空——位置重叠检测+落地状态 ✓；落地音效——landed 信号 ✓。
未覆盖 [U]：楼梯（当前灰盒无楼梯）、真实窗口手感、真实窗口门槛/边缘穿越。

---

## 8. 整体体验连续性（任务第十节，17 步走查）

| 步骤 | 状态 | 证据 |
| --- | --- | --- |
| 1 启动→主菜单 | ✅ | [T] ui_layout_test（屏内/命中/接线） |
| 2 进入住宅 | ✅ | [T] L3 点击进 party_house |
| 3 自由移动 | ✅ | [T] movement/jump |
| 4 与 NPC 交流 | ✅ 面板/分支/授予 | [T] dialogue_ui_test 26 断言；⚠️ 可走开（CT-002） |
| 5 检查物品 | ✅ examine+认知 | [T] acceptance/cognition |
| 6 使用手机 | ❌ 不存在 | [S] |
| 7 触发事件 | ✅ 穿黑暗切现实 | [T] dark_traverse/reality_cycle |
| 8-10 离开房间→室外→黑暗 | ✅ 三扇门+AutoPortal | [T] ui_layout L5/L6、door_connection |
| 11 进入不同现实 | ✅ α→β→γ 循环 | [T] reality_cycle |
| 12 与人物再次交流 | ⚠️ 能聊，但人物不记得任何事（无记忆） | [S] |
| 13 返回住宅 | ✅ | [T] |
| 14 保存 | ✅ 原子写 | [T] save_isolation |
| 15-16 退出重启→读档 | ✅ 位置/认知/世界恢复；❌ NPC 不恢复 | [T] save_migration；[S] CT-003 |
| 17 状态连续性总检 | ⚠️ 主线连续，NPC/物品/手机层断裂 | 本报告 |

**玩家是否知道自己为什么来这里**：开场 toast 仅一句氛围文本（"屋子里很安静…"），无目标指引——剧情未定稿故不判缺陷，记为 [U] 待叙事阶段。
**现实切换是否让玩家理解发生了什么**：三条 log 文案 + 环境变体差异，需要真实窗口确认可辨识度 [U]。

---

## 9. 真实窗口验证状态（任务规则 13/14）

本轮为只读审计，**未执行真实窗口走查**。已有的真实窗口证据仅限历史记录（v0.3.1 帧率采样、UI 布局坍塌修复后的用户实测反馈）。以下结论目前只有 headless/源码支撑，第二阶段验收前必须真实窗口复验：

- 暂停/对话期间移动（本轮探针为 headless，[T] 已实测行为，真实窗口待复验）
- 对话面板观感、7 处现实差异可辨识度、明暗平衡、鼠标手感
- 音频空间感（无实现）
- 17 步完整体验走查（需按任务十二记录步骤/截图/日志）

---

## 10. 结论索引

- 缺陷清单见 `CONTINUITY_BUG_REGISTER.md`（CT-001…CT-018）。
- 系统连接与状态归属见 `SYSTEM_CONNECTION_MAP.md` / `STATE_OWNERSHIP_MAP.md`。
- 修复与设计规范见 `CONTINUITY_RECOVERY_PLAN.md`。
