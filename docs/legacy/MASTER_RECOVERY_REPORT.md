# COMET — 系统性重整报告

| 项 | 值 |
| --- | --- |
| 依据 | 项目负责人《全项目重整计划》（P0–P10） |
| 分支 | `recovery/master-rebuild` |
| 起点 commit | `adf7aa2`（原始 HEAD） |
| 审计 commit | `64bb26e` |
| 实施 commit | `7eae9d0` → `24e52f2` → `fa01c62` → `d050753` → `05251b6` → `99560c3` → 本文档所在 commit |
| 改动规模 | 33 个文件，+3504 / −685 行 |
| 引擎 | Godot 4.7.2-stable，GL Compatibility |
| 平台 | Windows 10 19045 / i5-7200U / 12 GB / Radeon 530 2 GB |
| 测试 | 13 个测试、**385 条断言**，全部通过 |

---

## 一、项目原始状态

`adf7aa2` 时项目处于「能运行、能走通主循环、但持久化与状态生命周期不可靠」的状态：

- 8 个 headless 测试、273 条断言，表面上全绿。
- 架构骨架成立：`WorldManager` / `SceneManager` / `EventManager` 三者权威划分清晰，
  事件「判定与执行分离」，门级落点走「挂起—消费」，黑暗穿越已改为区域触发。
- 但审计发现 **3 条 P0 全部与存档有关**，其中 2 条会造成玩家数据不可恢复的丢失。

---

## 二、工程审计结果

完整内容见 `docs/MASTER_DEPENDENCY_MAP.md`：20 个模块职责表、**12 条调用链**、地点连接图、数据流总图、测试覆盖矩阵。

关键结论：

1. **三项核心状态确实各自唯一**（现实/地点/事件历史），没有出现"两个 Manager 各存一份"。
2. 真正的缺口是**四类状态根本没有权威**：玩家位置、玩家认知、NPC 状态、穿越状态。
3. `event_bus` 只 emit、**无任何订阅者**，是一层空转的抽象。
4. `interact` 触发类型运行时**从未被求值**；`evt_return_to_house` 是死定义。
5. `EventBus`、`DataLoader`、`ConditionEvaluator` 的引用计数低，但前者确实无人用，后两者靠 `class_name` 静态调用（正常）。

---

## 三、Bug 清单

`docs/MASTER_BUG_REGISTER.md` 登记 28 条：P0×3 / P1×6 / P2×14 / P3×5。

实施后状态（详见该文件第八节）：

| 状态 | 数量 |
| --- | ---: |
| 已修已验证 | 18 |
| 已实现未验证 | 2（事件失败不切场景、失焦释放） |
| 部分修 | 5 |
| 未修 | 3（interact 通道、音频、导出） |

---

## 四、架构调整说明

本轮**没有推倒重来**，只做了四处结构性调整：

1. **新增 `core/data_validator.gd`**（纯静态）
   启动流程从「四份数据各自 load」改为「四份全读出 → 交叉校验 → 再交给各 Manager」。
   理由：跨文件引用错误（variants 指向未知现实、`to_world` 拼错、`area_enter` 漏 `area_id`）
   在原实现里全部不可见，且 `area_enter` 漏 `area_id` 会导致事件**永不触发**却无任何提示。

2. **`SceneManager` 增加会话级 `reset_session()`**
   把「重载地点表顺带清状态」与「只清这一局的会话状态」两个职责分开。
   原实现只有前者，而 `new_game` 不走它，于是新局继承上局的返回栈与访问记录。

3. **`GameLocation.apply_world()` 改为返回 `bool`**
   让"变体缺失"从静默回退变成可判定的失败。

4. **`main` 的事件订阅改走 `event_bus`**
   因为 `new_game` 会重建 `EventManager`，而 `main` 只在 `_ready` 连一次线。

依赖方向没有变：表现层（`main` / `UIManager`）只读状态、只发信号；
`Hotspot` 不碰全局状态；`SaveManager` 仍然通过与游戏规则解耦的 `known_*` 参数工作。

---

## 五、各阶段实施结果

| 工作包 | 内容 | 结果 |
| --- | --- | --- |
| WP-00 | P0 审计 | ✅ 三份文档（Bug 总表 / 依赖图 / 重整计划） |
| WP-01 | 存档隔离 | ✅ 测试不再触碰玩家真档，SHA-256 验证 |
| WP-02 | 状态生命周期 | ✅ `reset_session` + 返回栈去重限深 |
| WP-03 | 数据校验 | ✅ `DataValidator` + 变体缺失显式化 |
| WP-04 | 门与出口 | ✅ 侧门/露台门补回程（含落点与朝向断言） |
| WP-05 | 黑暗区边界 | ✅ 掉头有出路，且不改变现实 |
| WP-06 | 灰盒几何复核 | ⏭ 未单独做（既有 P04 七条路线连通性断言仍在跑） |
| WP-07 | 现实变体完整性 | ✅ 通过 WP-03 的 `apply_world` 返回值 + 校验实现；**未新增第三现实** |
| WP-08 | 事件通道收敛 | ◑ 事件失败不切场景已实现；`interact` 通道未处理 |
| WP-09 | 输入与交互加固 | ✅ 二次确认、保存反馈、失焦释放、`debug_activate` 收口 |
| WP-10 | 存档原子性 | ✅ 五步写入 + `.bak` |
| WP-11 | 存档字段与迁移 | ✅ `player_position` / `visit_stack` + v1→v2 迁移 + 损坏隔离 |
| WP-12 | 玩家认知系统 | ⏭ 未实施（schema 已预留 `known_facts` 等字段） |
| WP-13 | NPC 与对话 | ⏭ 未实施（项目仍无任何导航节点） |
| WP-14 | 视觉与灯光 | ◑ 材质隔离已修；三档分辨率与灯光性能未做 |
| WP-15 | 音频 | ⏭ 未实施 |
| WP-16 | 导出 | ⏭ 未实施（无导出预设） |
| WP-17 | 文档与验收 | ✅ README / ACCEPTANCE / CHANGELOG / Bug 总表均已对齐 |

---

## 六、修改文件清单（33 个）

**新增（6）**
`core/data_validator.gd`、`tests/save_isolation_test.gd`、`tests/session_reset_test.gd`、
`tests/data_integrity_test.gd`、`tests/save_migration_test.gd`、`tests/ui_flow_test.gd`

**运行时核心（9）**
`core/save_manager.gd`（原子写入 / 迁移 / 隔离 / 测试路径）、
`core/scene_manager.gd`（`reset_session` / 栈去重 / 清死代码 / `get_visit_stack_size`）、
`core/location.gd`（`apply_world` 返回 bool + 警告）、
`core/hotspot.gd`（材质逐实例复制）、
`core/interaction_manager.gd`（`debug_activate`）、
`core/ui/ui_manager.gd`（确认面板）、
`autoload/game_services.gd`（校验接入 / 位置与栈入档 / 位置恢复 / 损坏隔离）、
`scenes/main.gd`（总线订阅 / 保存反馈 / 失焦 / portal 失败 / 确认流程）、
`project.godot`（警告开启 / 版本号 / stretch）

**场景构建（1）**
`tools/scene_content.gd`（SideReturn / PatioReturn / DarkBack）

**生成产物（3）**
`scenes/locations/house_exterior.tscn`、`dark_road.tscn`、`party_house.tscn`（重建）

**测试（8）**
`tests/door_connection_test.gd`（37→53）、`tests/dark_traverse_test.gd`（25→31）、
`tests/acceptance_test.gd`（57→59）、`tests/fps_input_test.gd`、`tests/party_house_test.gd`、
`tests/player_movement_test.gd`（改测试路径）、`tests/data_integrity_test.gd`、`tests/save_migration_test.gd`

**文档（6）**
`README.md`、`docs/ACCEPTANCE.md`、`docs/CHANGELOG.md`、`docs/MASTER_BUG_REGISTER.md`（状态更新）、
`docs/MASTER_RECOVERY_REPORT.md`（本文件）、`docs/MASTER_RECOVERY_PLAN.md`

---

## 七、存档迁移说明

**版本 1 → 2。** 变更：

| 新增字段 | 用途 |
| --- | --- |
| `player_position` | `[x, y, z]`，读档恢复到存档点而非地点出生点 |
| `visit_stack` | 返回栈，读档后"返回"按钮仍然可用 |
| `known_facts` / `inspected_objects` | 预留给玩家认知系统（当前恒为空） |
| `npc_states` / `traversal_state` | 预留给 NPC 与穿越状态（当前恒为空） |

**迁移行为**：

- v1 存档照常读入，缺失字段补默认值，**原有进度（地点、现实、事件历史、时钟、朝向）一个字不丢**。
- 迁移后写入 `migrated_from: 1`，便于排查。
- 版本高于 2 的存档直接拒绝（不猜测未来格式）。
- **旧存档的位置会沿用地點出生点**（v1 本来就没有位置），并提示"位置已回退"。
- 读档位置若与墙体/家具重叠（改过布局的旧档），回退 spawn 并 `push_warning`，不让玩家卡进几何。
- 读档失败时损坏文件被移到 `comet_save.json.corrupt`，不再每次启动重复失败。

**测试证据**：`save_migration_test` A9–A15 覆盖迁移，B2–B9 覆盖端到端位置与栈恢复。

---

## 八、测试覆盖情况

| 层 | 测试 | 断言 |
| --- | --- | ---: |
| 单元 | `wall_geometry_test`、`data_integrity_test`、`save_isolation_test` | 56 |
| 存档 | `save_migration_test`、`session_reset_test` | 44 |
| 集成 | `door_connection_test`、`dark_traverse_test`、`party_house_test` | 138 |
| 系统 | `acceptance_test`、`v2_p0_test` | 72 |
| 输入/UI | `fps_input_test`、`player_movement_test`、`ui_flow_test` | 75 |
| **合计** | **13 个** | **385** |

主场景 `--headless --quit-after 200`：0 error / 0 warning（警告已开启）。

**仍未覆盖**：`UIManager` 的排版正确性、真实窗口下的失焦/恢复、三档分辨率、音频（无系统）。

---

## 九、真实窗口测试记录

| 项目 | 实测值 |
| --- | --- |
| DisplayServer | Windows |
| 启动后鼠标 | `captured=true`，`Input.mouse_mode=2 (CAPTURED)` |
| 点「重新开始」 | `confirm_visible=true`，`mouse_mode=0`（已释放），存档**仍存在** |
| 确认后 | 回到 `party_house`，`captured=true`，确认框已关闭，存档被清除 |
| 保存 | `save_exists=true`，界面给出"进度已保存" |
| 帧率 | 57 fps |

> 未做的人工验收：Alt+Tab 反复切换、三档分辨率观感、手感、亮度、音频（无）。

---

## 十、性能数据

审计时（`adf7aa2`）单次采样：

| 项 | party_house | house_exterior |
| --- | --- | --- |
| 平均 FPS | 60.0 | 60.1 |
| 网格数 | 89 | 72 |
| 静态碰撞体 | 86 | 10 |
| 灯光（总数/可见） | 5 / 4 | 5 / 5 |
| 静态内存 | 57.0 MB | — |
| 显存 | 16.4 MB | — |

**注意**：这是单次采样、非稳态压测；**未确认运行时使用 Radeon 530 还是 Intel 核显**；
三档分辨率未测。灯光数量已从 v0.4.0 的 12 盏降到 4–5 盏，这是帧率从 33 回到 60 的原因。

---

## 十一、导出测试结果

**未做。** 项目无 `export_presets.cfg`，未生成独立包，未验证：
`res://data/*.json` 在导出包中能否读取、`.tscn` 资源路径、存档写入路径、图标与窗口配置。

这一项不能凭编辑器内运行成功来推定，必须实际导出后在目标机跑一遍 12 步流程。

---

## 十二、尚未解决的问题

1. **事件失败不切场景**（BUG-009）已实现但未做端到端实测——缺一个"必然失败的转移规则"用例。
2. **失焦释放鼠标**（BUG-018）代码已加，但未真实 Alt+Tab 验证。
3. **HUD 缩放**已配 `canvas_items/keep`，但 854×480、640×360 未人工确认。
4. **`interact` 触发通道**仍是死代码，`evt_return_to_house` 仍无规则（BUG-015）。
5. **`living_room`** 仍是运行时不可达的死地点，被 3 个测试引用，未退役。
6. **单存档槽 + 明文 JSON**（BUG-025）未改。
7. **测试偶发失败**（BUG-017）：已为四处聚焦断言加入显式驱动与 40 帧收敛窗口，失败率下降
   但仍偶发（同一批次 6 次中失败 2 次；手动单跑 5/5 通过），**未定位到具体断言**。
8. **`AutoPortal` 的玩家识别**仍靠 `has_method("is_mouse_captured")` 鸭子类型（BUG-028）。
9. **第三现实 `world_gamma`** 未加，变体完整性目前用 2 个现实验证。
10. **无音频、无 NPC、无认知系统、无导出包**——四个整块能力缺失。

---

## 十三、当前 Git commit

```
99560c3  fix(WP-08/09): 事件通道/二次确认/保存反馈/失焦/材质隔离/警告开启
05251b6  fix(WP-10/11): 存档原子写入/备份/迁移/位置与返回栈
d050753  fix(WP-04/05): 侧门露台门补回程 + 黑暗区掉头有出路
fa01c62  fix(WP-03): 统一数据校验入口 + 变体缺失不再静默
24e52f2  fix(WP-02): 新局真正空白 + 返回栈去重限深
7eae9d0  fix(WP-01): 测试不再删除玩家正式存档
64bb26e  docs: P0 全量工程审计
```

分支 `recovery/master-rebuild`。`main` 仍停在 `adf7aa2`，**未推送 GitHub**。

---

## 十四、最终运行方式

```bash
# 运行游戏（Windows，双击亦可）
D:\新建文件夹\tools\Godot\Godot_v4.7.2-stable_win64.exe --path "D:\新建文件夹\comet-game-prototype"

# 全量测试
cd "D:\新建文件夹\comet-game-prototype"
for t in acceptance_test v2_p0_test fps_input_test player_movement_test party_house_test \
         wall_geometry_test door_connection_test dark_traverse_test save_isolation_test \
         save_migration_test session_reset_test data_integrity_test ui_flow_test; do
  "D:\新建文件夹\tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --script "res://tests/$t.gd"
done
```

操作：移动鼠标环视 · WASD 移动 · E / 左键交互 · ESC 释放鼠标 · Q 退出 · 点画面恢复捕获。

---

## 十五、最终状态表

### 已完成

- 存档原子写入 + `.bak` 备份 + 损坏隔离
- 存档 v1→v2 迁移（位置、返回栈入档）
- 测试与玩家存档彻底隔离（SHA-256 证明）
- 新局状态清理、返回栈去重与限深
- 四份 JSON 交叉校验 + 变体缺失显式失败
- 侧门/露台门回程、黑暗区掉头出口
- 二次确认、保存反馈、事件总线订阅、材质隔离、警告开启
- 13 个测试 385 条断言全绿；主场景零报错

### 已修复但未实机验证

- 事件求值失败时不切场景（有代码，无用例）
- 窗口失焦释放鼠标（有代码，未 Alt+Tab 验证）

### 已实现但存在限制

- HUD 缩放：已配 `canvas_items/keep`，未在 854×480 / 640×360 人工确认
- 损坏存档隔离：已隔离，但启动仍"自动读档 + 静默回退新局"，没有标题页让玩家选择
- 读档位置：位置被占用时回退 spawn，属保护而非精确恢复

### 尚未实现

- 玩家认知系统（`known_facts` 字段已预留，无逻辑）
- NPC 状态与对话（无导航节点，需先做 navmesh 探针）
- 音频系统（无任何声音）
- Windows 导出验证
- 三档分辨率性能与观感验收

### 暂缓实现（需负责人决定）

- 第三现实 `world_gamma`
- `living_room` 退役（需先迁移 3 个测试）
- `interact` 触发通道保留或删除
- 多存档槽

### 需要项目负责人决定

| # | 事项 | 影响 |
| --- | --- | --- |
| D1 | 启动是否加标题页（继续/新游戏/退出） | 当前自动读档，玩家无法选择 |
| D2 | 音频素材来源（原创合成 / CC0） | 阻塞 WP-15 |
| D3 | 导出目标形态（单目录包 / 单文件 / 安装包） | 阻塞 WP-16 |
| D4 | 是否补 `world_gamma` | 影响变体完整性的验证强度 |
| D5 | `living_room` 去留 | 影响测试改造量 |
| D6 | NPC 是否接受"无 navmesh 的最小行为" | 决定 WP-13 的做法 |

---

## 十六、诚实声明

- 本轮**没有**把"未实现"写成"基本完成"。上面状态表里"尚未实现"的五个整块能力确实没有一行代码。
- **385 条断言全绿不等于游戏好玩**。手感、亮度、HUD 可读性、黑暗氛围、空间比例，本轮只做了一次真实窗口的机械验证，没有人的主观判断。
- 性能数字是**单次采样**，不是稳态压测，也没确认用的是独显还是核显。
- BUG-017 的偶发失败仍未定位。已加显式驱动与 40 帧收敛窗口，失败率下降但不为零，
  因此保留"部分修"，不写"已解决"。
- 存档迁移只验证了 v1→v2 的单向路径与自洽性，**没有用真实玩家存档做过迁移演练**（当前 `user://` 下不存在真实存档）。
