# 系统连接图（SYSTEM_CONNECTION_MAP）

**基准**：`recovery/master-rebuild` @ `800beb7`｜只读审计产物｜证据标记同 `CONTINUITY_AUDIT.md`。

---

## 1. 模块清单与职责（实际源码为准）

| 模块 | 基类 | 职责（源码事实 [S]） | 对外信号 |
| --- | --- | --- | --- |
| GameServices（autoload） | Node | 唯一装配点：bootstrap 各 Manager、注入依赖、转发信号上总线、新局/读档/存档编排、游戏时钟 | bootstrap_completed/failed、save_completed、load_completed |
| WorldManager | RefCounted | 当前世界唯一权威；apply_transition 唯一变更入口 | world_changed |
| EventManager | RefCounted | 触发判定（enter_location/interact/area_enter）+ 历史/旗标/阶段 | event_triggered |
| SceneManager | Node | 地点加载/切换/返回栈/访问记录 | location_entered、location_failed |
| InteractionManager | Node | 准星聚焦（射线+距离+遮挡）、激活派发 | hotspot_focused/unfocused/activated |
| SaveManager | RefCounted | 原子写盘/读回校验/v1→v2 迁移/损坏隔离 | — |
| PlayerController | CharacterBody3D | 视角+移动+跳跃+步距脚步 | jumped、landed、movement_state_changed、footstep |
| GameLocation | Node3D | 地点根节点；按 world_id 切 Variant 子树 | — |
| Hotspot | Area3D | 交互对象声明（kind/target/文本/世界可见性） | focus_changed |
| AutoPortal | Area3D | 走入式场景连接 + 事件触发（黑暗穿越） | player_entered |
| UIManager | CanvasLayer | HUD/对话面板/确认框/消息；只发 UI 意图信号 | back/save/quit/new_game、dialogue_* |
| MenuController | Control | 主菜单/暂停/设置界面 | new_game/continue/resume/main_menu/quit |
| DialogueManager | RefCounted | 认知闸门过滤对话、分支 goto、授予事实 | — |
| CognitionManager | RefCounted | 玩家认知事实（来源/归属/推翻） | — |
| NPCManager | Node | NPC 生成/烘焙导航/行走派发/序列化 | navigation_ready、npc_talk_requested（死） |
| NPC | CharacterBody3D | 单个 NPC 行走/交谈状态 | arrived、state_changed |
| AudioManager | Node | 分类播放/音量/环境循环/退出清理 | — |
| SettingsManager | RefCounted | 设置持久化与应用 | — |
| TimeService / RngService / EventBus | RefCounted | tick 时钟 / 具名随机流 / 只读信号总线 | tick_advanced 等 |

---

## 2. 信号总线连接（谁发、谁收）[S]

```
WorldManager.world_changed ──┬─→ GameServices._on_world_changed ──→ EventBus.world_changed
                             └─→ GameServices: play_reality_shift()

EventManager.event_triggered ─┬─→ GameServices._on_event_triggered ─→ EventBus.event_triggered
                              └─→（GameServices 转发后 main 只订阅总线）

SceneManager.location_entered ─┬─→ GameServices → EventBus.location_entered
                               └─→ main._on_location_entered（落位/热点重连/NPC生成/环境音）
SceneManager.location_failed ───→ main._on_location_failed

InteractionManager.hotspot_focused/unfocused → main（HUD 提示）
InteractionManager.hotspot_activated        → main（examine/exit 分支）
AutoPortal.player_entered                   → main（先事件后切场景）
PlayerController.jumped/landed/footstep     → GameServices → AudioManager
UIManager.*_requested / dialogue_*          → main
```

观察：
- 总线只转发三种事件（world/event/location），认知与 NPC 的变化**没有总线出口**——UI 只能主动查询。
- `EventManager.event_triggered` 同时被 GameServices 直连**和**经总线订阅的风险已由注释规避（main 只连总线）[S]。
- `npc_manager.npc_talk_requested` 无发射无订阅（CT-010）。

---

## 3. 关键调用链 [S]

**进入地点**：`GameServices.go_to → SceneManager.enter_location →（加载场景→apply_world→collect_hotspots→location_entered→EventManager.evaluate(enter_location)→若世界变→再 apply_world）`；main 响应 location_entered：门级落点/重连 portal/NPC spawn 或 despawn/环境音。

**黑暗穿越**：`AutoPortal.body_entered → main._on_portal_entered →（EventManager.evaluate(area_enter)→世界可能变）→ GameServices.go_to(target)`。事件失败不切场景（防状态撕裂）✓。

**交互**：`InteractionManager._process 每帧射线聚焦 → E/左键 → activate_focused（距离二次校验）→ main._on_hotspot_activated：examine（认知+文案+tick）或 exit（落点挂起→go_to）`。

**对话**：`E 无热点 → npc_manager.find_talkable_near → main._start_dialogue → UIManager 话题面板 → hear()（授予认知）→ 分支 goto → 关闭`。

**存档**：`GameServices.save_game 组装 19 字段 payload → SaveManager.save（tmp→校验→bak→rename）`；**读档**：continue_game 逐 Manager restore（世界/事件/场景/时钟/随机/认知）→ enter_location → 位置覆盖。

---

## 4. 任务 3.3 九问

1. **每个系统负责什么**：见 §1。
2. **状态最终解释权**：见 `STATE_OWNERSHIP_MAP.md`（多数清晰；NPC 动态状态与物品状态无权威归属，因为没有持有者）。
3. **谁可以修改该状态**：世界仅经 WorldManager.apply_transition（唯一入口 ✓）；玩家位置的写入方有 3 个（main 落位、continue_game 恢复、reset_to_spawn），互斥时序依赖「挂起—消费」约定 [S]。
4. **如何订阅变化**：world/event/location 走 EventBus；其余（认知/NPC/对话）无订阅通道，消费者直接查 Manager [S]。
5. **重复状态**：
   - `known_facts` ⊂ `cognition`（双写，读档只认 cognition）；
   - `triggered_events` ≡ `event_sequence`（双写同值）；
   - `GameLocation.applied_world_id` 是 WorldManager 当前世界的缓存（由 _refresh_world_presentation 重刷，未验证缓存失效在所有路径都覆盖 [D]）；
   - PlayerController `_mouse_captured` 与 Input.mouse_mode 双份（有意，headless 可测）[S]。
6. **循环依赖**：无。Manager 层互相不引用（EventManager 通过注入的 world_mgr/visit_provider 弱依赖）；main→GameServices→Manager 单向 [S]。
7. **场景卸载残留引用**：`_release_current` 会 set_hotspots([])（顺带清焦点）+ queue_free 实例 ✓；AutoPortal 信号连接随实例销毁 ✓；**NPC 被 _despawn_all 主动 free** ✓ 无泄漏（22 测试退出零泄漏 [T]）。
8. **信号重复连接**：各 connect 均带 is_connected 守卫或一对一绑定；new_game 重建 world/event Manager 后 _wire_signals 重连 ✓ [S]。portal 逐场景重连（旧实例已销毁）✓。
9. **多系统同时修改玩家位置/现实/事件**：
   - 现实：仅 WorldManager ✓；
   - 事件：仅 EventManager ✓；
   - **玩家位置：main._on_location_entered 与 continue_game 都调 reset_to_spawn**，靠「continue_game 先 enter_location 再覆盖坐标」的顺序保证正确，无显式所有权声明（隐患：未来第三个写入方易踩序）[S]。

---

## 5. 断开的连接（汇总，详见 BUG_REGISTER）

| 断点 | 现象 | 编号 |
| --- | --- | --- |
| 输入锁 ↔ 暂停/对话 | 移动不被锁 | CT-001/002 |
| 读档 ↔ NPC 状态 | npc_states 只写不读 | CT-003 |
| 场景生命周期 ↔ NPC 行为 | 离场即重置 | CT-004 |
| interact 触发器 ↔ 事件 | 从不求值；evt_return_to_house 死数据 | CT-005 |
| UI 音效 ↔ 界面动作 | 定义未接线 | CT-007 |
| 脚步 ↔ 地面材质 | 硬编码 wood | CT-008 |
| NPC ↔ 记忆/关系/情绪/知情 | 全部缺失 | CT-009 |
| 手机 ↔ 一切 | 系统不存在 | CT-011 |
| NPC 语音 ↔ 空间位置 | 无 3D 音频 | CT-012 |
| observe/infer 来源 ↔ 游戏入口 | 无写入点 | CT-014 |
