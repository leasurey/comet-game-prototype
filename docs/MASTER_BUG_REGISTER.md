# COMET — Bug 总表（P0 审计）

| 项 | 值 |
| --- | --- |
| 基准 commit | `adf7aa2` |
| 审计分支 | `recovery/master-rebuild` |
| 审计日期 | 2026-10-31 |
| 引擎 | Godot 4.7.2-stable |
| 测试现状 | `[实测]` 8 个测试、273 条断言；连跑 5 次全通过，**首次运行出现 1 次偶发失败**（见 BUG-017） |

**来源标记**：`[代码]` 读源码可判定 · `[实测]` 实际运行得到 · `[计算]` 由数据推算 · `[未验证]` 需运行确认

**状态取值**：`待修` / `已确认未修` / `已修未验证` / `已修已验证` / `非缺陷（设计取舍）`
**本轮为审计阶段，所有条目均为 `待修` 或 `已确认未修`，无一条标记为已修复。**

---

## 一、汇总

| 严重程度 | 数量 | 定义 |
| --- | --- | --- |
| **P0** | 3 | 存档损坏 / 状态丢失 / 数据丢失 |
| **P1** | 6 | 场景连接错误、现实切换不可靠、读档状态错误、软锁 |
| **P2** | 14 | 交互/UI/性能/一致性缺陷，影响体验但不阻断流程 |
| **P3** | 5 | 代码卫生、文档、非关键体验 |
| 合计 | **28** | |

**一句话结论**：架构骨架（三个 Manager 的权威划分、判定与执行分离、门级落点、区域触发穿越）是成立的，**真正的风险集中在"持久化"和"状态生命周期"两块**——P0 三条全部与存档有关。

---

## 二、P0 —— 存档损坏 / 状态丢失

### BUG-001 存档直接覆盖写入，无临时文件、无备份

| 项 | 内容 |
| --- | --- |
| 系统 | `core/save_manager.gd::save` |
| 来源 | `[代码]` `save_manager.gd:51-57`：`FileAccess.open(_path, WRITE)` 直接打开正式存档 |
| 复现步骤 | 保存时强制中断进程（断电 / 任务管理器结束 / 磁盘满） |
| 实际表现 | 正式存档被截断或写一半，原存档内容不可恢复；下次启动 `load_state` 解析失败 → `_start_flow` 回退 `new_game()`，**进度全失** |
| 预期表现 | 先写临时文件 → 回读校验 → `rename` 原子替换 → 保留上一份 `.bak`；任一步失败都不触碰正式存档 |
| 根因 | 缺少 "写临时文件 + 原子替换" 流程；`save()` 虽有回读校验，但校验的是**已被覆盖的文件**，此时原内容已丢失 |
| 影响范围 | 所有存档行为；玩家手动保存、未来自动保存 |
| 修复方案 | 写入 `comet_save.json.tmp` → 校验 magic/JSON → 先 `rename` 现档为 `.bak` → 再 `rename` tmp 为正式档；`.bak` 保留最近一份 |
| 回归测试 | 新增 `save_atomic_test.gd`：① 正常保存后两文件均存在 ② 模拟 tmp 写入失败时正式档字节不变 ③ `.bak` 可被 `load_state` 读出 |
| 状态 | **待修**（P5 工作包） |

### BUG-002 测试套件删除玩家真实存档

| 项 | 内容 |
| --- | --- |
| 系统 | `tests/*.gd` × 5 |
| 来源 | `[代码]` 以下 5 处调用**默认路径**上的删除：<br>`dark_traverse_test.gd:123`、`door_connection_test.gd:136`、`fps_input_test.gd:202`、`party_house_test.gd:129`、`player_movement_test.gd:158` |
| 复现步骤 | ① 正常游玩并保存 ② 运行任意上述测试 ③ 再启动游戏 |
| 实际表现 | `user://comet_save.json` 被删除，玩家进度消失，且**没有任何提示** |
| 预期表现 | 测试只操作独立的临时路径（如 `user://test_save_<pid>.json`），绝不触碰正式存档 |
| 根因 | 测试复用全局 `GameServices.save_manager` 的默认路径；`SaveManager` 支持 `set_path()` 但测试未用 |
| 影响范围 | 开发与验收流程；对玩家而言，只要跑过测试就丢档 |
| 修复方案 | 在 `SaveManager` 增加 `set_path` 之外的测试隔离入口，或所有测试在 setup 中 `set_path("user://_test_<testname>.json")` 并在 teardown 清理；`GameServices` 增加 `using_test_save` 标记，生产路径拒绝删除 |
| 回归测试 | 新增断言：跑完全部测试后，若测试前存在正式存档，测试后其哈希不变 |
| 状态 | **待修**（P0 立即处理，改动小、风险低） |

### BUG-003 读档不恢复玩家位置

| 项 | 内容 |
| --- | --- |
| 系统 | `PlayerController.serialize_view` / `GameServices.continue_game` |
| 来源 | `[代码]` `player_controller.gd:207` 返回 `{"yaw","pitch"}`；`game_services.gd:306-312` 先 `enter_location`（落到地点 spawn）再 `restore_view` |
| 复现步骤 | ① 在聚会房屋主空间走到餐桌旁 ② 保存 ③ 退出并重启（自动读档） |
| 实际表现 | 玩家出现在玄关 spawn `(0, 0.25, 1.6)`，而不是保存时所在位置；朝向正确 |
| 预期表现 | 位置与朝向都应恢复；若位置非法（陷入墙体）才回退 spawn |
| 根因 | 存档结构没有 `player_position` 字段；`continue_game` 依赖 `enter_location` 的 spawn 逻辑 |
| 影响范围 | 每次读档；探索类游戏里这是最刺眼的状态丢失 |
| 修复方案 | payload 增加 `player_position: [x,y,z]`；`continue_game` 在 `enter_location` 之后用 `reset_to_spawn(pos)` 覆盖，并做一次胶囊重叠检测（重叠则回退地点 spawn 并 `push_warning`） |
| 回归测试 | 新增 `save_restore_test.gd`：保存位置 → 读档 → 断言位置误差 < 0.05 m；另测"存档位置在墙内"时回退 spawn |
| 状态 | **待修**（P5 工作包；`docs/KNOWN_ISSUES.md` §0.3 已记录，但按新任务书属必须修复项） |

---

## 三、P1 —— 连接错误 / 现实切换 / 状态污染 / 软锁

### BUG-004 `visit_stack` 从未写入存档，读档后返回栈恒为空

| 项 | 内容 |
| --- | --- |
| 系统 | `GameServices.save_game` / `continue_game` |
| 来源 | `[代码]` payload（`game_services.gd:323-338`）**没有** `visit_stack`；而 `continue_game:282` 读 `data.get("visit_stack", [])` 传给 `scene_manager.restore` |
| 复现步骤 | ① 从 `party_house` 出门到 `house_exterior` ② 保存 ③ 重启读档 ④ 点"返回" |
| 实际表现 | 返回按钮置灰（栈为空），玩家无法沿来路回屋，必须跑到前门热点 |
| 预期表现 | 返回栈随存档恢复，"返回"仍可用 |
| 根因 | 写入端与读取端字段不一致——读取端在等一个永远不存在的键 |
| 影响范围 | 读档后的导航；配合 BUG-021 会放大 |
| 修复方案 | payload 增加 `"visit_stack": scene_manager.serialize().get("visit_stack", [])` |
| 回归测试 | 新增断言：入栈 → 保存 → 读档 → `can_go_back()` 为 true 且 `get_previous_location_id()` 一致 |
| 状态 | **待修**（P5） |

### BUG-005 `new_game` 不清空返回栈与访问记录

| 项 | 内容 |
| --- | --- |
| 系统 | `GameServices.new_game` / `SceneManager` |
| 来源 | `[代码]` `new_game` 重建 `WorldManager`/`EventManager` 并重载数据，但**未调用** `scene_manager.load_from_data()`（只有它才 `_visit_stack.clear()`） |
| 复现步骤 | ① 玩到 `house_exterior`（栈中有 `party_house`）② 点"重新开始" ③ 立即点"返回" |
| 实际表现 | 玩家从新局玄关被"返回"到 `house_exterior`——一个本局从未去过、且世界状态属于上局的地点；`visited_locations` 同样残留，会污染依赖 `visited` 的事件条件 |
| 预期表现 | 新局应从空白状态开始：栈空、访问记录空、时钟归零、朝向归零 |
| 根因 | 状态清理职责分散：`load_from_data` 顺带做清理，`new_game` 却没有走这条路 |
| 影响范围 | "重新开始"功能；任何依赖 `visited` 的事件 |
| 修复方案 | 新增 `SceneManager.reset_session()`（清栈、清访问、清当前地点），`new_game` 显式调用；同时 `player_controller.reset_view()` |
| 回归测试 | 新增：入栈 → `new_game()` → 断言 `can_go_back()==false`、`get_visited_locations().is_empty()` |
| 状态 | **待修**（P1 工作包，属"状态唯一"原则的直接违反） |

### BUG-006 变体缺失时静默回退，无任何警告

| 项 | 内容 |
| --- | --- |
| 系统 | `core/location.gd::apply_world` |
| 来源 | `[代码]` `location.gd:61-65`：未命中 `Variant_<world>` 时依次回退 `Variant_default` → 第一个 variant，**不 push_warning、不返回错误** |
| 复现步骤 | 在 `worlds.json` 增加 `world_gamma`，不修改场景；进入任一地点后切到 gamma |
| 实际表现 | 场景显示默认变体，看起来"正常"，但玩家身处 gamma 却看到 alpha 的陈设——错误被伪装成正常 |
| 预期表现 | 开发环境明确报告"地点 X 缺少 world_gamma 变体"；生产环境可选择回退但必须留日志 |
| 根因 | 回退策略被当作容错实现，没有区分"设计上允许缺省"与"配置漏写" |
| 影响范围 | 任务书 §4.1.4 明确禁止；现实从 2 扩到 3+ 时必然踩中 |
| 修复方案 | `apply_world` 返回 `bool`；未命中时 `push_warning("地点 %s 缺少变体 %s")` 并记录到 `GameServices.degraded_warnings`；`locations.json` 的 `variants` 字段（当前**无人读取**，BUG-016）改为必填校验源 |
| 回归测试 | 新增 `world_variant_test.gd`：构造缺变体地点 → 断言 `apply_world` 返回 false 且产生警告记录 |
| 状态 | **待修**（P3 工作包） |

### BUG-007 侧门与露台门没有对应回屋门

| 项 | 内容 |
| --- | --- |
| 系统 | 场景连接 / `house_exterior` |
| 来源 | `[代码]` `house_exterior` 只有一个 `DoorToInterior`，落点 `(0,0.25,1.6)`（前门内侧）；侧门出到 `(8.6,2.0)`、露台出到 `(-4,11)`，两处附近均无回屋热点。`[实测]` `door_connection_test` 只覆盖"从某门出去"，未覆盖"从该处回来" |
| 复现步骤 | 从侧门离开房屋 → 站在侧院 → 试图回屋 |
| 实际表现 | 必须绕到正面门廊才能进门；露台同理 |
| 预期表现 | 任务书 §3.2："对应返回入口"——每扇门都应有自己的回程入口 |
| 根因 | 第一轮只补了"出去"的方向，回程仍复用单一门 |
| 影响范围 | 空间连续性；玩家会认为"侧门是单向的" |
| 修复方案 | 在 `house_exterior` 侧院与露台各加一个 exit 热点，`target_spawn` 分别落到房屋内侧对应门后（侧门内侧 x≈6.4、露台内侧 x=-4.0, z≈9.2） |
| 回归测试 | `door_connection_test` 增加 3 条往返断言（侧门/露台/前门：出去 → 回来 → 落点误差 < 0.3 m） |
| 状态 | **待修**（P2 工作包） |

### BUG-008 `dark_road` 掉头后无任何出路

| 项 | 内容 |
| --- | --- |
| 系统 | 场景连接 / `dark_road` |
| 来源 | `[代码]` `dark_road` 的 `exits` 为 `[]`；场景内只有尽头 `DarkExit`(z=-20) 一个 portal；出生点 z=4.0，入口方向**无 portal、无墙体**。地面 60×70 覆盖到 z=+15 |
| 复现步骤 | 进入黑暗区域后立刻转身往回走 |
| 实际表现 | 玩家走进空荡的黑暗里，越走越远也没有任何反馈或边界；只能自己意识到要回头走到尽头 |
| 预期表现 | 掉头应能原路返回 `house_exterior`，且**不触发现实变化**（任务书 §4.3 明确要求） |
| 根因 | 只设计了"前进"通路，没有"入口侧出口"；也没有边界墙/引导 |
| 影响范围 | 玩家可能陷入长时间困惑（软锁级体验问题） |
| 修复方案 | 在 z≈+6 加一个 `AutoPortal`（`target_location=house_exterior`，落点 `(0,0.05,-17.5)` 即路口内侧），不携带 `event_keys` → 掉头返回不改变现实 |
| 回归测试 | `dark_traverse_test` 增加：进入 → 转身走出入口 → 断言仍为 `world_alpha`、地点为 `house_exterior` |
| 状态 | **待修**（P3 工作包，改动小、收益大） |

### BUG-009 事件求值失败时仍然切场景，现实静默不一致

| 项 | 内容 |
| --- | --- |
| 系统 | `main._on_portal_entered` |
| 来源 | `[代码]` `main.gd:280-299`：`evaluate()` 的 `errs` 只 `push_warning`，随后无条件 `go_to()` |
| 复现步骤 | 使 `evt_cross_dark_road` 求值失败（如 `to_world` 写成不存在的 id，或数据被改坏） |
| 实际表现 | 玩家穿过黑暗到达街对面，但现实仍是 `world_alpha`——环境毫无变化，而叙事已经暗示"你走错门了" |
| 预期表现 | 要么明确失败并停在原地（`_notify("…")` + 不切场景），要么保证事件成功后再切 |
| 根因 | 错误处理缺失：把"事件失败"当成日志事件而非控制流分支 |
| 影响范围 | 核心叙事机制的可信度 |
| 修复方案 | `_on_portal_entered` 中 `errs` 非空 → 不切场景、`_notify` 明确提示、`push_error`；若 `portal` 声明了必须触发的 `event_keys`，则要求 `fired` 非空 |
| 回归测试 | 新增：注入一个必然失败的 transition → 走过 portal → 断言地点未变且未产生 world 变更 |
| 状态 | **待修**（P3 工作包） |

---

## 四、P2 —— 一致性、交互、UI、性能

| ID | 系统 | 现象 / 复现 | 根因（`[代码]`） | 修复方案 | 状态 |
| --- | --- | --- | --- | --- | --- |
| **BUG-010** | `main` / `EventManager` | 点"重新开始"后，事件触发时**不再弹出文本提示** | `main._bind_services` 只在 `_ready` 连一次 `event_manager.event_triggered`；`new_game()` 用 `EventManager.new()` 换了实例 | 改为监听 `GameServices.event_bus`（或 `new_game` 后重新绑定）；根本解是让 `GameServices` 暴露 `rebind(main)` | 待修 |
| **BUG-011** | `Hotspot` | 凝视任意热点时，场景中**同类材质的所有物体一起发光** | `_apply_emission` 直接改写 `material_override`，而构建器 `_mat()` 按 key 缓存、**全场景共享同一 Material 实例** | 聚焦时对材质 `duplicate()` 后赋值，或改用 `MeshInstance3D.set_instance_shader_parameter` 做逐实例高亮 | 待修 |
| **BUG-012** | `UIManager` / `main` | ① "重新开始"无二次确认，误点即删档 ② 保存没有任何成功/失败反馈（`save_completed` 无人连接） | `ui_manager.gd:201` 直接 emit；`main._on_save_requested` 只调用不显示结果 | 加确认对话框（复用 `OverlayLayer`）；连接 `save_completed` → `set_message` | 待修 |
| **BUG-013** | 工程配置 | 所有 GDScript 警告被全局关闭 | `project.godot` `[debug] gdscript/warnings/enable=false` | 改为 `true`，对确需豁免的告警用 `@warning_ignore` 局部关闭；这可能一次性暴露大量未使用变量等提示，需分批清理 | 待修 |
| **BUG-014** | `EventBus` | 总线只被 emit，**没有任何订阅者** | `event_bus.gd` 4 个信号，全项目仅 `game_services` 转发 | 要么让 UI/表现层真正订阅（替代 BUG-010 的直连），要么删除该层以降低复杂度 | 待修（二选一，需负责人决定） |
| **BUG-015** | 数据 / 事件 | `evt_return_to_house` 定义在 `events.json` 但**无对应转移规则**；`interact` 触发类型**运行时从未被求值**（全项目只有 `enter_location` / `area_enter` 两处调用） | `event_manager.gd:22` 定义 `TRIGGER_INTERACT`，但 `scene_manager`/`main` 均未调用 | 决定是否保留 `interact` 通道：保留则补调用点（检查热点时求值），否则删除常量与死定义 | 待修 |
| **BUG-016** | 数据 | 三处"双份真相"：① `world_transitions.json` 的 `initial_world` 无人读取（真值在 `worlds.json`）② `locations.json` 的 `variants` 无人读取 ③ `locations.json` 的 `exits` 只用于取 label，实际连接由热点自带 | `[代码]` 全项目无 `variants` 读取点；`get_exit_label` 只用 `label` | `variants` 升级为校验源（配合 BUG-006）；`initial_world` 删除或加校验；`exits` 明确标注"仅用于文案"或改为真实数据源 | 待修 |
| **BUG-017** | 测试 | `fps_input_test` 首次运行 `PASS=28 FAIL=1`，随后 4 次连续 `29/0`，**无法复现** | 未定位。已排除"残留存档污染"（构造 `dark_road`+`world_beta` 存档后仍 29/0） | 连续运行 20 次并记录失败项名称；若为物理帧时序，改为显式驱动 `_update_focus()`（该测试已有此模式） | 已确认未修 |
| **BUG-018** | `PlayerController` | 窗口失焦 / 重新获得焦点**完全未处理**：Alt+Tab 后鼠标可能仍处于捕获态，或重新聚焦后视角突然大幅跳动 | `[代码]` 无 `NOTIFICATION_APPLICATION_FOCUS_OUT` 处理 | 失焦 → `release_mouse()`；聚焦 → 不自动捕获（等玩家点击），避免视角跳变 | 待修 |
| **BUG-019** | UI | HUD 无缩放策略，`project.godot` 未配置 `window/stretch/*`；1280×720 之外（854×480 / 640×360）排版**未验证** | `[代码]` 用固定 offset 定位（如 `-372` 的按钮栏） | 配置 `stretch/mode="canvas_items"` + `aspect="keep"`，或改锚点百分比布局；三档分辨率逐档截图验证 | 未验证 |
| **BUG-020** | 音频 | **完全没有音频系统**：无环境音、脚步、开关门、现实切换音效，也无音量/静音 | 项目内无 `AudioStreamPlayer` 节点、无音频资源 | 建立 `AudioService`（总线 + 音量 + 静音）+ 至少 5 个音频事件挂点；素材须原创或合法授权 | 待修（P8） |
| **BUG-021** | `main._start_flow` | 读档失败只提示"存档已损坏"，**不隔离损坏文件** → 每次启动都失败一次再回退新局；且启动**自动读档**，玩家无法选择"新游戏" | `[代码]` `main.gd:81-89` | 失败时把损坏存档重命名为 `.corrupt`；启动流程改为标题页（继续 / 新游戏 / 退出） | 待修（P5/P9） |
| **BUG-022** | 导出 | **未做 Windows 导出验证**：无导出预设、未验证模板/资源路径/JSON 读取/存档写入 | 项目内无 `export_presets.cfg` | 建立导出预设，在目标机完成一次全流程（启动→移动→交互→保存→重启→读档） | 待修（P9） |
| **BUG-023** | `InteractionManager` | `activate(spot)` 是 public 方法且**不做距离校验**，任何脚本可绕过 2.5 m 限制 | `[代码]` `interaction_manager.gd:150` | 降级为 `_activate_internal`，或加 `if Engine.is_editor_hint() or is_test_mode` 守卫；测试改用真实玩家路径 | 待修 |

---

## 五、P3 —— 代码卫生与文档

| ID | 系统 | 现象 | 根因 / 位置 | 修复方案 | 状态 |
| --- | --- | --- | --- | --- | --- |
| **BUG-024** | `SceneManager` | 返回栈只增不减（`A→B→C→B→C…` 会无限增长） | `enter_location` 只 `append`，无去重或上限 | 入栈前若已存在该地点则截断到该位置；或限制栈深 16 | 待修 |
| **BUG-025** | `SaveManager` | 单存档槽、明文 JSON | `DEFAULT_PATH` 固定；无加密 | 先做单槽安全（BUG-001），再加 2–3 槽；明文可接受但需在 KNOWN_ISSUES 说明 | 待修（P5） |
| **BUG-026** | 文档 | README 声称"52 条断言"、ACCEPTANCE 记为 `PASS=52`，**实际 273 条**；README 的"已实现"停在 v0.2.0，缺 v0.3–v0.5 内容 | 文档未随版本更新 | P10 统一重建：README/ACCEPTANCE/ARCHITECTURE/KNOWN_ISSUES 全部对齐当前 commit | 待修（P10） |
| **BUG-027** | 代码卫生 | ① `Hotspot._update_visual_feedback` 的 `factor` 恒为 1.0（死逻辑）② `scene_manager.gd:262` `if world_changed_after_enter: pass` ③ `GameServices.save_game` 同时写 `triggered_events` 与 `event_sequence`（同一份数据） | `[代码]` | 删除死代码与重复字段 | 待修 |
| **BUG-028** | 健壮性 | `AutoPortal` 用 `body.has_method("is_mouse_captured")` 识别玩家；`main` 直接写 `pc.yaw/pitch` 属性 | 鸭子类型耦合 | 引入 `PlayerCharacter` 基类或 `group("player")` 判定；朝向设置走方法 `set_view(yaw, pitch)` | 待修 |

---

## 六、需要项目负责人决定的事项

以下不是缺陷，是**取舍**，但会影响后续工作包的范围：

| # | 事项 | 选项 | 影响 |
| --- | --- | --- | --- |
| D1 | `EventBus` 保留还是删除 | ① 让 UI 订阅它（顺便修 BUG-010）② 删除该层 | 决定 BUG-010 的修法 |
| D2 | 启动流程 | ① 保持"自动读档" ② 加标题页（继续/新游戏） | 影响 P5、P9 |
| D3 | `living_room` 去留 | ① 停用并迁移 3 个测试 ② 保留为独立场景 | 影响 P2 工作包与测试改造量 |
| D4 | 现实数量 | 当前 2 个（alpha/beta），任务书建议 3 个起步 | 影响变体完整性与 BUG-006 的紧迫度 |
| D5 | 音频素材来源 | ① 原创合成（无版权风险，工作量大）② 使用 CC0 素材库 | 影响 P8 |
| D6 | 导出目标 | 仅 Windows x64 单文件，还是含安装包 | 影响 P9 |

---

## 七、不能算作"已修复"的事项（如实声明）

1. **所有 28 条均为待修**，本轮只做审计与文档。
2. `docs/KNOWN_ISSUES.md` §0.3「存档不记录玩家坐标」是**已知限制**而非已解决——按新任务书属必须修（BUG-003）。
3. BUG-017 的偶发失败**未复现**，因此不能写"已修复"，只能写"已确认存在、原因待定位"。
4. 性能数字（`party_house` 60 fps / 89 网格 / 86 静态体 / 5 盏灯、`house_exterior` 60 fps、内存 57 MB、显存 16.4 MB）是 `[实测]` 单次采样，**不是稳态压测**，且未确认运行时使用独显还是核显。
5. 手感和观感（灵敏度、亮度、HUD 可读性、黑暗区域氛围）**本轮未做人工验收**。
