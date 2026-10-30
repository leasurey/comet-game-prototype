# COMET — 版本记录

## v0.1.4 — 第一人称视角升级为鼠标捕获式

### 变更

**视角控制从「按住左键拖动」改为标准 FPS 式捕获控制。**

- 启动后自动捕获鼠标、隐藏系统光标，移动鼠标即转动视角，**无须按住任何键**
- 使用 Godot 原生 `Input.MOUSE_MODE_CAPTURED`，增量由引擎在
  `InputEventMouseMotion.relative` 中给出，不做任何屏幕坐标补偿
- 鼠标移到窗口边缘仍可持续转动
- 水平 yaw 完整 360° 连续；垂直 pitch 保留 ±75° 限位
- `ESC` 释放鼠标并显示光标；释放后点击画面重新捕获
- 退出（Q 键 / UI 按钮 / 关闭窗口）时必定释放鼠标

**节点结构未重建**：仍由 `CameraRig` 负责 yaw、子 `Camera3D` 负责 pitch，
仅替换了输入读取方式。

### 修复：垂直视角灵敏度比水平低约 57 倍

`pitch` 累加的是弧度量级（`像素 × 0.0035`），却在 `_apply_rotation()` 中
按度数使用（`camera.rotation_degrees.x = -pitch`）。
结果：同样移动 1000 像素，水平转约 200°，垂直只转约 3.5°。

**这正是「上下观察体验不足」的直接原因**，不是灵敏度参数偏小。
现已全链路统一为弧度，实测两者比值 = 1.00。

### 新增

- `interact` 输入动作（E 键），在 `GameServices` 中幂等注册
  （已核实项目此前不存在任何输入映射，不会重复定义）
- `tests/fps_input_test.gd`：覆盖 T01–T13，共 29 条断言
- `PlayerController` 新增 `capture_mouse()/release_mouse()/is_mouse_captured()`、
  分别的水平/垂直灵敏度、`_exit_tree()` 自动释放

### 关于 acceptance_test 断言数从 52 变为 53

不是放宽或删除断言：T02 原有断言全部保留（yaw 变化、pitch 变化、±75° 限位），
仅把「模拟按住左键拖动」改为「捕获状态下发送 relative 位移」，
并新增 1 条「鼠标捕获已启用」断言，故总数 +1。

### 兼容性

- 节点结构未变动
- 存档格式未变动（`player_view` 仍为 yaw/pitch 弧度）
- EventManager / WorldManager / 场景布局 / 世界切换 / 整数 tick 均未改动

### 验证

- `tests/fps_input_test.gd`：**PASS=29 FAIL=0**
- `tests/acceptance_test.gd`：**PASS=53 FAIL=0**
- `tests/v2_p0_test.gd`：**PASS=13 FAIL=0**
- 真实窗口（DisplayServer=Windows）：`Input.mouse_mode == MOUSE_MODE_CAPTURED` 已确认

---

## v0.1.3 — 启动脚本与远端同步

### 新增

- `start_game.bat` / `open_editor.bat`：双击式启动脚本。
  两者都用 `%~dp0` 取自身所在目录，**脚本内不出现任何非 ASCII 路径**，
  以避免中文工作区路径在 CMD 下产生编码损坏。Godot 引擎本体位于项目目录之外
  （`<工作区>/tools/Godot/`），不会被打进仓库。

### 说明

- 本次把 v0.1.0 ~ v0.1.2 的全部变更一次性同步到远端仓库。
- V1（第一阶段原型）与 V2（第二阶段地基修复）在**同一工作区**内完成，
  二者是延续关系而非分叉，因此统一落在 `main` 分支，未另开分支。

### 验证（同步前实测）

- `tests/acceptance_test.gd`：**PASS = 52, FAIL = 0**
- `tests/v2_p0_test.gd`：**PASS = 13, FAIL = 0**
- 主场景 headless 运行 200 帧：零 SCRIPT ERROR / ERROR / WARNING

---

## v0.1.2 — 第二阶段地基：三项引擎缺陷修复 + L0 服务落地

这四项改动由一次**实测探针**（`comet-v2-design/verify/probe_v1_issues.gd`）驱动，
而非静态代码审查。每项都先复现、再修复、再复测。

### 修复

**1. 事件 id 校验导致自身存档读不回来（实测复现）**

`EventManager.restore()` 要求历史中的 id 存在于 `events.json` 的定义集合，
但记录的却是 `world_transitions.json` 中的规则 id。
探针构造一条「只在转移表中定义」的规则：它能正常触发并改变世界，
但该存档重建后被 `restore` 拒绝。
现改为**在载入期把转移规则 id 补登记进定义表**，真正未知的 id 仍被拒绝。

**2. 伪随机结果耦合全局事件序列长度（实测复现）**

原实现用 `rule_seed + _sequence.size()` 作随机种子，
于是无关事件的发生次数会改变本规则的取值：
探针中「噪声事件 0 次 → world_beta，3 次 → world_alpha」。
现改为经 `RngService` 取**具名流**，结果只由 `(主种子, 流名, 该流已取次数)` 决定。

**3. `conditional` 的 `requires` 从未被求值（实测复现）**

条件声明了却完全不参与判定：探针中条件要求 `world_beta`、实际 `world_alpha`，
事件照样触发并切换世界。现接入 `ConditionEvaluator`，
采用**谓词白名单**，未登记谓词在**载入期**即报错，不做运行时静默忽略。

**4. 时钟改为动作驱动**

v0.1.1 已消除浮点漂移，但 tick 仍由真实时间推进，
同一操作序列在不同游玩速度下会得到不同 tick，「重放一致性」不成立。
现时钟由玩家动作离散推进（移动、观察），`_process` 只负责把当前值同步到 UI。

### 新增

- `core/time_service.gd` — 整数 tick 时钟，可序列化，无浮点状态
- `core/rng_service.gd` — 具名随机流，计数随存档持久化，可回放
- `core/event_bus.gd` — 只读信号总线，表现层统一订阅入口
- `core/condition_evaluator.gd` — 受限谓词条件求值，含载入期校验
- `tests/v2_p0_test.gd` — 上述能力的回归测试

### 兼容性

- 类名、信号名、`load_from_data()` 签名全部保持不变
- 存档新增 `rng_master_seed` / `rng_counters` / `event_flags` / `phase_id` 字段，
  缺失时按默认值处理，旧档可读
- `new_game()` 新增可选种子参数，不传时使用固定默认种子，默认路径可复现

### 验证

- `tests/acceptance_test.gd`：**PASS = 52, FAIL = 0**（无回归）
- `tests/v2_p0_test.gd`：**PASS = 13, FAIL = 0**
- 隐患探针：**PASS = 5, FAIL = 1**（剩余 1 项为已知未处理项，见 KNOWN_ISSUES）

---

## v0.1.1 — 三项正确性修复

这三个问题由一次独立的代码审查发现，均已修复并通过回归验证。

### 修复

**1. `EventManager.restore()` 的事件 id 校验范围错误**

历史记录里保存的是 `world_transitions.json` 中规则的 id，
但恢复时却拿去 `events.json` 的定义集合里比对。
当前两份数据恰好同 id，所以没有暴露为 bug——但这是巧合，一旦两者分家，
合法存档会被误判为损坏。改为两侧都识别，只拒绝真正未知的 id。

**2. `GameLocation` 的场景回退优先级不明确**

找不到匹配的 `Variant_<world_id>` 时的回退逻辑写得含糊不清，
依赖了循环中的副作用顺序。改为显式两级优先级：
`Variant_default` > 列表中的第一个 variant。行为不变，逻辑可读。

**3. 游戏时钟存在浮点漂移**

原实现为 `_clock_minutes += delta * CLOCK_SCALE`，浮点累加会随帧率不同产生细微漂移，
同一存档在不同设备上恢复后时间不一致。改为**整数 tick 步进**：
累计满 6 秒才推进一个整分钟，存档记录整数刻度，可精确复现。

### 验证

- `tests/acceptance_test.gd`：**PASS = 52, FAIL = 0**（无回归）
- 主场景 headless 运行 200 帧：零 SCRIPT ERROR / ERROR / WARNING

---

## v0.1.0-prototype — 第一阶段技术原型

对应任务书的第一阶段全部要求。

### 新增

**工程与运行时**

- Godot 4.7.2-stable 工程，含 `project.godot` 与唯一 autoload `GameServices`
- 七个职责分离的模块：
  SceneManager / WorldManager / EventManager / InteractionManager /
  PlayerController / UIManager / SaveManager
- 数据层与代码分离：`worlds.json`、`world_transitions.json`、`events.json`、`locations.json`

**场景**

- 三个地点：客厅 `living_room`、房屋外部 `house_exterior`、黑暗区域 `dark_road`
- 全部几何体由 `tools/scene_content.gd` 程序生成，无第三方素材
- 每个地点支持 `Variant_world_alpha` / `Variant_world_beta` 两套表现

**交互**

- 第一人称鼠标拖动环视，水平自由、垂直限制 ±75°
- 射线拾取热点，含墙体遮挡判定（不能隔墙点击）
- 悬停显示对象名称，点击触发交互
- 出口热点切换地点，支持沿返回栈回退
- ESC 退出

**世界状态**

- 地点 id 与世界 id 正交管理
- 进入黑暗区域触发 `fixed` 类型世界转移：`world_alpha → world_beta`
- 切换天然只发生一次，由事件历史保证
- 返回房屋外部后实测产生 7 处可观察差异

**存档**

- 明文 JSON，含地点、世界、访问记录、世界变化记录、事件历史
- 写盘后回读校验；读取时逐字段校验
- 损坏存档、引用未知地点的存档均被拒绝，上层回退到新游戏

**测试**

- `tests/acceptance_test.gd`：覆盖 10 条验收项，52 条断言
- 当前结果 PASS=52 FAIL=0

### 构建过程中的实际修正记录

开发过程中通过实跑发现并修复的问题（保留以供溯源）：

| 问题 | 表现 | 修正 |
| --- | --- | --- |
| `Environment.ambient_source` 不存在 | 4.7 中属性名已变更，赋值静默失败 | 改为 `ambient_light_source` |
| Godot 不支持 `_ = x` 丢弃语法 | 多处 Parse Error | 删除相关语句 |
| `var fallback_node := null` 类型不可推断 | location.gd Parse Error | 显式声明 `var fallback_node: Node = null` |
| `root.owner = root` | 引擎报错 `p_owner == this` | 仅给后代设置 owner |
| 测试例中 `:=` 大量推断失败 | 成员变量无类型导致链式推断失败 | 全部改为显式类型 |
| 射线聚焦滞后一拍 | 切换目标后未重置等待帧数 | 每个目标独立计时 `_aim_ticks` |
| 差异检测失真 | `find_child` 取到隐藏 variant 里的同名节点 | 改为按可见性筛选 |

### 已知限制

见 `docs/KNOWN_ISSUES.md`。其中最关键的一条是：
**画面观感、UI 排版、操作手感尚未经过人工肉眼验证**。
自动化测试证明了机制正确，不等于体验合格。
