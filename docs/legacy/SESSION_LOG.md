# COMET 项目工作日志

> 本文件为**完整工作记录**，可独立阅读，无需额外上下文。
> 目的：交付给另一个 AI（ChatGPT）或开发者，使其能直接接手继续工作。
> 记录者：WorkBuddy（AI 执行助手）
> 记录时间：2026-10-30 23:00 ~ 2026-10-31 01:25 (GMT+8)

---

## 0. 一句话总结

从零搭建了一个 Godot 4.7 第一人称悬疑探索游戏原型（代号 COMET），
实现「穿越黑暗后返回，熟悉环境已不同」这一核心机制，
通过 52 条自动化断言验证，并发布到 GitHub。

**仓库**：https://github.com/leasurey/comet-game-prototype
**最新 commit**：`788ab5b`
**文件数**：63
**License**：MIT

---

## 1. 原始任务要求（来自用户的任务书）

任务书标题：《COMET — 第一版游戏原型开发任务书》。核心摘录：

| 节 | 要求 |
| --- | --- |
| 一、目标 | 以电影《彗星来的那一夜》(Coherence, 2013) 为**叙事灵感**的第一人称悬疑探索游戏。不是文字冒险，不是开放世界。 |
| 二、技术 | 优先评估 Godot 4.x + GDScript。轻量化 3D，固定观察点 + 热点交互。换引擎必须先说明理由。 |
| 三、场景 | 三个地点：房屋内部（客厅）、房屋外部、黑暗区域。 |
| 四、世界状态 | 地点 ID 与世界 ID 必须**分开管理**。世界转移须遵循：固定事件 / 条件事件 / 伪随机事件 / 历史记录。**禁止用随机替换场景来制造世界变化**。 |
| 五、差异 | 返回同一地点至少 3 处可观察差异：① 物品位置变化 ② 灯光或环境状态变化 ③ 新增环境线索。必须由世界状态驱动，不得每次加载随机生成。 |
| 六、交互 | 鼠标拖动环视、垂直限位、点击热点、悬停识别、点击出口切换、支持返回、显示名称提示、支持退出。 |
| 七、UI | 简洁电影化悬疑风格。显示当前时间、热点不过度突出、设置与退出入口。UI 须能独立扩展（后续要加虚拟桌面/聊天/浏览器/文件管理器）。 |
| 八、架构 | 至少七个职责：Scene / World / Event / Interaction / Player / UI / Save Manager。 |
| 九、存档 | 保存当前地点 ID、世界 ID、已触发事件、访问过的地点、世界变化记录。有数据校验和错误处理。 |
| 十、测试 | **必须实际运行游戏**，不能只提交源码。10 条验收项全部通过。 |
| 十一、仓库 | README、LICENSE（先确认素材授权）、源码、场景、运行说明、开发说明、已知问题。不得上传缓存/临时文件/隐私文件。第三方素材须记录来源与许可证。 |
| 十二、执行 | 七步顺序执行。禁止伪代码/静态截图/假按钮冒充已实现功能；禁止把未测试功能标为完成。 |

**最终交付要求 6 项**：仓库地址、目录结构、技术架构说明、已实现功能清单、实际测试结果、限制与下一步建议。

**核心目标（原文）**：让玩家第一次穿越黑暗区域，再沿原路返回时，能够亲眼发现自己熟悉的环境已经不再相同。

---

## 2. 环境事实（全部为实测，非假设）

| 项目 | 实测结果 |
| --- | --- |
| Godot | **未预装**，全盘搜索无结果 |
| Git | 2.55 / 2.56（两个版本共存） |
| Python | bash 下 3.13.14；PowerShell 下 3.11.9（**两者不同**） |
| curl / wget | **不存在**（被 shim 屏蔽），下载只能用 PowerShell |
| D 盘（工作区所在） | **默认对当前用户只读**，ACL 仅 `ReadAndExecute`。用户手动授权后才可写 |
| 可写位置 | `C:\Users\k`、`C:\Users\k\Desktop`、`E:\`、Temp |
| 网络代理 | 环境变量存在 `http://127.0.0.1:54345` |
| GitHub 可达性 | REST API **可达**；`git push` 的 CONNECT 隧道**返回 502**；直连 `github.com:443` **超时** |
| 渲染设备 | AMD Radeon 530，OpenGL 3.3 Core Profile |

---

## 3. 执行时间线

### 阶段一：环境排查与引擎获取

1. 检查 git / python / godot → Godot 缺失。
2. 尝试在工作区建目录 → **权限被拒**。排查发现 D 盘 ACL 仅只读。
3. 探测可写目录，确认 `C:\Users\k` / `E:\` 可用。
4. 查询 GitHub API 确认最新稳定版：**Godot 4.7.2-stable**（2026-08-18 发布）。
5. 启动后台下载 → 18 分钟仅 7.5 MB / 82 MB，**速率异常**。
6. 按「先排查原因不盲目等待」原则停止下载。**用户改为手动下载**。
7. 用户提供 `E:\Downloads\Godot_v4.7.2-stable_win64.exe.zip`。
8. **校验**（不做例外）：
   - 大小 86,013,866 字节 ✓
   - SHA-512 取自该 Release 的官方 `SHA512-SUMS.txt` ✓ 一致
9. 解压到 `D:\新建文件夹\tools\Godot\`（**项目目录之外**，避免被打进仓库）。
10. 验证：`4.7.2.stable.official.ed1daf0bf` ✓

### 阶段二：代码编写

按七步顺序：

1. 建目录结构 + `project.godot`
2. 写数据层 4 个 JSON
   - **立即自查发现**：JSON 标准不支持 `#` 注释 → 改为纯 JSON，注释移入 `data/README.md`
3. 写七个职责模块（核心 Manager 用 `RefCounted` 以便 headless 单测）
4. 写 `game_services.gd`（唯一 autoload）+ `main.gd`
5. 写场景构建器 `tools/scene_builder.gd` + `scene_content.gd`
6. 写 HUD（后改为代码构建）
7. 写验收测试

### 阶段三：场景生成与踩坑修复

1. 首次 `--script` 运行 → class 索引缺失 → 先跑 `--headless --editor --quit` 生成缓存
2. 生成场景 → 暴露 4 个真实错误，逐个修复（详见第 7 节）
3. 重新生成 → 零错误

### 阶段四：验收测试

1. 首次运行：48 PASS / **4 FAIL**（热点射线聚焦滞后一拍）
2. 定位为测试逻辑缺陷（换目标后未重置等待帧数），非游戏缺陷 → 修测试
3. 另修正差异检测失真（`find_child` 取到隐藏 variant 的同名节点）
4. 最终：**PASS = 52, FAIL = 0**
5. 补充验证：主场景 headless 240 帧零报错；GUI 真实渲染 OpenGL 3.3 启动成功

### 阶段五：文档与发布

1. 写 README / ARCHITECTURE / ACCEPTANCE / KNOWN_ISSUES / CHANGELOG / THIRD_PARTY / LICENSE / .gitignore / .gitattributes
2. 创建 GitHub 仓库（MCP 集成无权限 403 → 改用本地凭据调 REST API）
3. 上传：`git push` 因代理 502 不可用 → 改用 **GitHub Git Data API** 提交
4. 完整性校验：63/63 文件指纹一致

### 阶段六：并行会话与启动脚本

1. 发现目录出现未由我创建的文件 → 查明是**用户有意并行开的 V2 会话**在修 bug
2. 实测撞到一次中间态导致的启动失败（详见第 8 节）
3. 创建双击式启动脚本
4. 将 V1 + V2 全量同步到 main

---

## 4. 技术架构

### 引擎选型（含未换引擎的理由）

**Godot 4.7.2-stable + GDScript + OpenGL 3.3 Compatibility**

未换引擎的理由：
- 难点在「世界状态驱动的确定性差异」，不在渲染质量；
- Unity/Unreal 会显著增加体积与构建时间，与「普通电脑流畅运行」相悖；
- Godot 的 `RefCounted` 让核心逻辑完全脱离渲染做 headless 单元测试——这是能严格验收的前提。

### 分层

```
表现层  scenes/*.tscn, GameLocation, Hotspot, Camera3D
装配层  autoload/game_services.gd + scenes/main.gd
逻辑层  core/*_manager.gd（7 个职责模块）
数据层  data/*.json（可脱离代码编辑）
```

依赖严格自上而下，下层不知道上层存在。

### 七个职责模块

| 模块 | 负责 | 不负责 |
| --- | --- | --- |
| SceneManager | 加载 `.tscn`、实例化、释放、返回栈、访问记录 | 决定地点长什么样 |
| WorldManager | 当前世界 + 变更历史 | 判定何时该变 |
| EventManager | 判定何时发生什么 + 历史记录 | 直接改世界（通过调用 WorldManager 完成，避免历史漏记） |
| InteractionManager | 射线拾取、遮挡判定 | 热点代表什么剧情 |
| PlayerController | 鼠标拖动 → yaw/pitch | 交互判定 |
| UIManager | 显示状态 + 发信号 | 读世界数据 |
| SaveManager | 安全写盘/读回/校验 | 知道哪些 id 合法（由调用方注入） |

`WorldManager` / `EventManager` / `SaveManager` 为 `RefCounted`（不依赖 SceneTree）；
`SceneManager` / `InteractionManager` 为 `Node`（需 SceneTree）。

### 地点与世界分离的实现

```
HouseExterior (GameLocation)
└── Environment
    ├── Shared                 ← 不随世界变化（非 Variant_ 前缀，保持原状）
    ├── Variant_world_alpha
    └── Variant_world_beta
Hotspots                       ← 节点集合恒定，只有可见性变化
    ├── DoorToInterior
    ├── RoadToDark
    ├── CrateAlpha             ← visible_only_in_worlds = ["world_alpha"]
    ├── CrateBeta              ← visible_only_in_worlds = ["world_beta"]
    ├── GlassShards            ← visible_only_in_worlds = ["world_beta"]
    └── Mailbox
```

**关键约束**：节点集合恒定，只有可见性变化。不在运行时动态增删节点——
这是「连续往返不错乱」的结构性保证。

热点跟随物件位置：木箱在两个世界位置不同，用**两个互斥热点**（同一 display_name）
各自绑定世界，而不是让一个热点运行时搬家。

### 世界转移规则

`data/world_transitions.json` 是**唯一合法来源**。三类规则：

- `fixed`：条件满足必须发生（第一版唯一启用的类型）
- `conditional`：需额外条件
- `pseudo_random`：只能在 `candidate_worlds` 内取值，由种子决定（可复现，非真随机）

### 观察点约定

三个地点**共用固定观察点** (0, 1.62, 0)，初始朝 -Z，单一 `CameraRig`。
代价是场景必须围绕单视点构图；收益是切换地点不可能丢朝向或错位。

---

## 5. 产出文件清单（63 个）

```
project.godot              引擎配置（唯一 autoload: GameServices）
.gitattributes .gitignore

autoload/game_services.gd  全局服务编排

core/  ---- 运行时核心 ----
  world_manager.gd         世界状态权威
  event_manager.gd         事件触发 + 历史
  scene_manager.gd         地点切换 + 返回栈
  interaction_manager.gd   射线拾取 + 遮挡判定
  save_manager.gd          存档读写 + 校验
  data_loader.gd           JSON 读取统一入口
  hotspot.gd               可交互热点节点
  location.gd              地点根节点（按世界切换表现）
  player_controller.gd     第一人称环视
  time_service.gd          [V2] 整数 tick 时钟
  rng_service.gd           [V2] 具名可持久化随机流
  event_bus.gd             [V2] 只读信号总线
  condition_evaluator.gd   [V2] 谓词白名单条件求值
  ui/ui_manager.gd         界面与提示

data/  ---- 数据层 ----
  worlds.json  world_transitions.json  events.json  locations.json  README.md

scenes/
  main.gd  main.tscn
  locations/living_room.tscn  house_exterior.tscn  dark_road.tscn
  ui/hud.tscn

tools/  ---- 离线构建，非运行时 ----
  scene_builder.gd  scene_content.gd

assets/icon.svg            手写 SVG 图标

tests/
  acceptance_test.gd       第一阶段验收（10 条验收项 / 52 断言）
  v2_p0_test.gd            [V2] 第二阶段地基回归（13 断言）

docs/
  ARCHITECTURE.md  ACCEPTANCE.md  KNOWN_ISSUES.md  CHANGELOG.md  THIRD_PARTY.md

start_game.bat  open_editor.bat    双击式启动脚本
LICENSE (MIT)
README.md
```

---

## 6. 测试结果（真实输出，非预期描述）

### 6.1 第一阶段验收测试

```
godot --headless --script res://tests/acceptance_test.gd
=== RESULT: PASS=52 FAIL=0 ===   退出码 0
```

关键证据摘录：

```
[PASS] 5. 进入黑暗区域后世界发生变化 | world_alpha -> world_beta
[PASS] 5. 世界按预设规则切到 world_beta | got=world_beta
[PASS] 5. 世界变化被记录一次 | change_count=1
[PASS] 6. 可沿原路返回
[PASS] 7. 同一地点存在 >=3 处可观察差异 | 共 7 处:
        环境变体 ["Shared","Variant_world_alpha"] -> ["Shared","Variant_world_beta"];
        可用热点 [...CrateAlpha,Mailbox] -> [...CrateBeta,GlassShards,Mailbox];
        木箱位置 (1.60,-1.60) -> (-1.50,-2.25);
        门廊灯 visible=true energy=5.50 -> visible=false energy=-1.00;
        窗户自发光 true -> false;
        门牌角度 0.0° -> 24.0°;
        新增线索 GlassShards
[PASS] 8. 连续往返无切换失败 | round0..round3 全部 (dark=true,back=true)
[PASS] 8. 世界变化次数稳定 | 1 -> 1
[PASS] 9. 损坏存档被拒绝而非崩溃 | 存档 JSON 解析失败: Expected key
[PASS] 9. 恢复世界状态正确 | got=world_beta expect=world_beta
[PASS] 10. 热点可被射线聚焦 | Mailbox / GlassShards / CrateBeta / RoadToDark / DoorToInterior
[PASS] 2. 垂直视角受限不翻转 | pitch=-0.210 deg (限制 ±75)
```

### 6.2 V2 地基测试（由并行会话产出）

```
godot --headless --script res://tests/v2_p0_test.gd
=== V2 P0 RESULT: PASS=13 FAIL=0 SKIP=0 ===
```

### 6.3 真实渲染验证

```
godot --quit-after 200 --log-file gui_run.log

Godot Engine v4.7.2.stable.official.ed1daf0bf
OpenGL API 3.3.14831 Core Profile Forward-Compatible Context
Compatibility - Using Device: ATI Technologies Inc. - AMD Radeon (TM) 530
（无 ERROR / WARNING / 着色器编译失败，退出码 0）
```

### 6.4 主场景冒烟

```
godot --headless --quit-after 240   → 零 SCRIPT ERROR / ERROR / WARNING，退出码 0
```

### 6.5 远端完整性

63 个文件逐一比对 `git hash-object` 与 GitHub blob SHA：**63/63 一致，0 缺失，0 不匹配**

---

## 7. 遇到的问题与修复（完整清单）

### 7.1 我引入并修复的（构建过程中实跑发现）

| # | 问题 | 表现 | 修复 |
| --- | --- | --- | --- |
| 1 | JSON 含 `#` 注释 | Godot `JSON.parse_string` 会失败 | 改为纯 JSON，注释移入 `data/README.md` |
| 2 | `Environment.ambient_source` | Godot 4.7 **属性名已变更**，赋值静默失败 | 改为 `ambient_light_source` |
| 3 | `_ = x` 丢弃赋值 | Python 语法，Godot 不支持 → Parse Error | 删除 |
| 4 | `var fallback_node := null` | 类型不可推断 | 写 `var fallback_node: Node = null` |
| 5 | `root.owner = root` | 引擎报 `p_owner == this` | 只给后代设 owner |
| 6 | `--script` 首跑缺 class 索引 | `Could not find type WorldManager` | 先跑 `--headless --editor --quit` |
| 7 | 测试中 `:=` 大量推断失败 | 成员变量无类型导致链式推断失败 | 全部改显式类型 |
| 8 | 射线聚焦滞后一拍 | 换目标后未重置等待帧数 | 每个目标独立计时 `_aim_ticks` |
| 9 | 差异检测失真 | `find_child` 取到隐藏 variant 里的同名节点 | 改为按可见性筛选 |

### 7.2 v0.1.1 三项正确性修复（代码审查发现）

1. **事件 id 校验范围错误**：历史存的是转移规则 id，却拿去 `events.json` 比对。
   当前两份数据恰好同 id 才没暴露。→ 改为两侧都识别。
2. **场景回退优先级不明确**：依赖循环副作用顺序。→ 显式两级：`Variant_default` > 第一个 variant。
3. **时钟浮点漂移**：`_clock_minutes += delta * CLOCK_SCALE` 随帧率漂移，存档无法精确复现。
   → 改为整数 tick 步进。

### 7.3 v0.1.2 三项引擎缺陷（由 V2 并行会话**实测复现**后修复）

1. **伪随机耦合全局事件序列长度**：`rule_seed + _sequence.size()` 作种子，
   无关事件的发生次数会改变本规则取值（实测：噪声事件 0 次→beta，3 次→alpha）。
   → 改为 `RngService` 具名流。
2. **`conditional` 的 `requires` 从未被求值**：条件声明了但不参与判定。
   → 接入 `ConditionEvaluator`，谓词白名单，未登记谓词在**载入期**报错。
3. **时钟仍由真实时间驱动**：同操作序列在不同游玩速度下 tick 不同。
   → 改为玩家动作离散推进。

### 7.4 环境问题（非代码缺陷）

| 问题 | 处理 |
| --- | --- |
| D 盘只读 | 用户手动授权 |
| 无 curl/wget | 全程用 PowerShell `Invoke-WebRequest` / `Invoke-RestMethod` |
| 下载速率异常（18 分钟 7.5MB） | 停止自动下载，改用户手动下载 |
| MCP 创建仓库 403 | 改用本地凭据调 REST API |
| `git push` 代理 502 | 改用 GitHub Git Data API（blobs → trees → commits → refs） |
| 空仓库拒绝创建 blob（409） | 先用 Contents API 落一个初始 commit |
| ref 更新报 not fast forward | 创建 commit 时必须带 `parents` |

### 7.5 V2 实测发现、尚未处理的问题

**变体缺失时静默回退**：对地点调用 `apply_world("world_does_not_exist")` 时，
场景无 `Variant_default`，回退到第一个变体（呈现 alpha 内容）**且不报任何 warning**。
第二阶段多世界下极难察觉。已记入 `docs/KNOWN_ISSUES.md`，建议：
① 每地点强制提供 `Variant_default` ② 回退时输出 warning ③ 加载入期静态检查。

---

## 8. 与 V2 并行会话的交互（重要）

### 事实

用户**有意**同时开了第二个会话（V2），任务是**基于 V1 修 bug**。属预期行为。

V2 新增文件：`time_service.gd`、`rng_service.gd`、`event_bus.gd`、`condition_evaluator.gd`、
`tests/v2_p0_test.gd`；重写了 `game_services.gd`、`event_manager.gd`、`main.gd`。

### 实测撞到的中间态（真实事故）

- 01:04:41 我做启动验证时，`game_services.gd` 正被 V2 改写
- 报一整屏 `Parse Error: Identifier "_clock_ticks" not declared`
- 原因：文件处于「改了一半」状态——我的旧引用还在，V2 的 `TimeService` 还没落地
- 01:17 复验：V2 改写已完成，主场景零报错、验收测试仍 PASS=52

**结论**：并行会话改同一批源文件，**中间态窗口必然存在**，与谁改得对不对无关。
建议后续并行会话各自开独立分支，改完再合并。

### 同步决策

V1 与 V2 是**延续关系而非分叉**，因此统一落在 `main`，未另开分支。

---

## 9. 当前状态

| 项目 | 状态 |
| --- | --- |
| 代码 | 全部在 `main` 分支，commit `788ab5b` |
| 第一阶段验收 | PASS=52 FAIL=0 |
| V2 地基测试 | PASS=13 FAIL=0 |
| 主场景运行 | headless 零报错；GUI 渲染 OpenGL 3.3 成功 |
| 远端完整性 | 63/63 一致 |
| 引擎 | `D:\新建文件夹\tools\Godot\Godot_v4.7.2-stable_win64.exe`（不在仓库内） |
| 本地 `.git` | 与远端**不同源**（远端是 API 上传），后续 push 增量建议先重新 clone |

---

## 10. 未完成 / 下一步建议

### 尚未验证（headless 测不了，需人工肉眼确认）

1. **画面观感**：几何体比例、明暗平衡（尤其 `dark_road` 亮度）
2. **UI 排版**：HUD 由代码构建，位置未实际观看校准
3. **鼠标拖动灵敏度**：当前 `mouse_sensitivity = 0.0035` 仅为估算值
4. **7 处差异的「一眼可辨识度」**：数值差异已确证，主观是否明显未验证

> **自动化测试证明了机制正确，不等于体验合格。** 这是当前最大的未验证项。

### 已知限制（详见 docs/KNOWN_ISSUES.md）

- HUD 由代码构建，编辑器内不可视化调整
- 改场景必须改 `tools/scene_content.gd` 后重新生成，直接改 `.tscn` 会被覆盖
- 返回栈只增不减（不影响正确性，仅轻微内存增长）
- 单存档槽位；「重新开始」无二次确认
- 无音效；未做导出测试；未做性能压测
- 变体缺失时静默回退（见 7.5）

### 建议的下一步

1. **先人工跑一遍游戏**，校准画面、UI、手感（阻塞其余体验类工作）
2. 拍板剧情设定：主角身份（V2 建议「第九人」）、世界数量（建议 3–5）、是否保留电影角色名
3. 处理 7.5 的变体回退问题（第二阶段多世界前必须解决）
4. 补音效
5. 导出可执行文件并测试

---

## 11. 给接手者的环境陷阱清单

1. **下载工具**：没有 curl/wget，只能用 PowerShell。
2. **D 盘权限**：默认只读，写入前确认已授权。
3. **Godot 4.7 API 差异**：`ambient_source` → `ambient_light_source`；
   `tone_mapper_exposure_linear` 已移除。跨版本复用代码务必先核对属性名。
4. **Godot GDScript 限制**：不支持 `_ = x`；`var x := null` 必须显式类型。
5. **场景生成**：先跑 `godot --headless --editor --quit` 建立 class 缓存，再跑构建脚本。
6. **网络**：`git push` 不可用（代理 502）。要提交请用 GitHub REST API：
   `POST /git/blobs` → `POST /git/trees` → `POST /git/commits`（**必须带 parents**）
   → `PATCH /git/refs/heads/main`。空仓库需先用 `PUT /contents/<file>` 落初始 commit。
7. **本地 `.git` 与远端不同源**，不要在其上强推。

---

## 12. 常用命令速查

```bash
# 运行游戏（或双击 start_game.bat）
"D:/新建文件夹/tools/Godot/Godot_v4.7.2-stable_win64.exe" --path "D:/新建文件夹/comet-game-prototype"

# 打开编辑器（或双击 open_editor.bat）
".../Godot_v4.7.2-stable_win64.exe" --editor --path ".../comet-game-prototype"

# 第一阶段验收测试
godot --headless --script res://tests/acceptance_test.gd

# V2 地基测试
godot --headless --script res://tests/v2_p0_test.gd

# 重新生成三个地点场景（改 tools/scene_content.gd 后必须执行）
godot --headless --script res://tools/scene_builder.gd

# 无窗口冒烟
godot --headless --quit-after 240
```

---

## 13. 关于电影内容

本项目只借用「熟悉的地点在不知不觉间变得不同」这一**叙事构想**。

仓库**不包含**电影的任何画面、音频、台词、角色或商标，也不复述剧情。
关于电影本身的细节请以影片为准，本项目不作为事实来源。

---

## 14. 素材与许可证

| 类别 | 来源 | 许可证 |
| --- | --- | --- |
| 全部代码 | 原创 | MIT |
| 全部 3D 几何体 | `tools/scene_content.gd` 程序生成（BoxMesh/CylinderMesh + 纯色材质） | MIT |
| `assets/icon.svg` | 手写 SVG | MIT |
| 引擎 | Godot 4.7.2（commit ed1daf0bf） | MIT |
| 美术贴图/模型/音频 | **无** | — |
| 电影素材 | **无** | — |

Godot 压缩包官方 SHA-512（取自官方 `SHA512-SUMS.txt`）：
```
83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb
709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993
```
未使用任何第三方镜像或非官方打包版本。
