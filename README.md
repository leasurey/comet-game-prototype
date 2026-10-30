# COMET — 第一阶段游戏原型

一个以电影《彗星来的那一夜》（Coherence, 2013）为**叙事灵感**的第一人称悬疑探索原型。

> **本阶段的唯一核心目标：**
> 让玩家第一次穿越黑暗区域，再沿原路返回时，能够亲眼发现自己熟悉的环境已经不再相同。

这不是文字冒险游戏，也不是开放世界 3D 游戏。核心玩法是：站在固定观察点上环视四周，
点击场景中的热点在不同地点之间移动；当你穿越某段黑暗之后，同一个地点会以不同的面貌迎接你。

---

## 一、技术路线

| 项目 | 选择 | 理由 |
| --- | --- | --- |
| 引擎 | **Godot 4.7.2-stable**（commit `ed1daf0bf`） | 轻量、开源、MIT、GDScript 上手快、导出体积小 |
| 语言 | **GDScript** | 与 Godot 深度集成，无需 .NET 运行时 |
| 渲染 | **OpenGL 3.3 Compatibility** 后端 | 对集显与老旧机型友好，实测可在 AMD Radeon 530 上流畅启动 |
| 移动方式 | 固定观察点 + 热点点击 | 符合原型目标，避免在第一阶段引入角色控制与物理开销 |
| 素材 | 全部程序生成的基础几何体 | 零第三方素材，彻底规避授权问题 |

在实测机器上验证过的渲染信息：

```
OpenGL API 3.3.14831 Core Profile Forward-Compatible Context
Compatibility - Using Device: ATI Technologies Inc. - AMD Radeon (TM) 530
```

### 为什么没有使用其他引擎

任务书允许更换技术路线，但要求说明理由。经评估后**保持 Godot**，理由：
- 第一阶段的难点在「世界状态驱动的确定性差异」，不在于渲染质量，Godot 的表达能力完全够用；
- Unity / Unreal 会显著增加工程体积与构建时间，与「普通电脑流畅运行」的目标相悖；
- Godot 的场景树与 `RefCounted` 让核心逻辑可以脱离渲染做 headless 单元测试，这对验收至关重要。

---

## 二、运行方式

### 前置条件

1. 下载 Godot **4.7.2-stable** 标准版（**不要**下载 mono 版本，那是 C# 专用）：
   https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip
2. 解压得到 `Godot_v4.7.2-stable_win64.exe`。

### 命令行运行

在项目根目录执行：

```bash
# 直接运行（Windows）
"C:/path/to/Godot_v4.7.2-stable_win64.exe" --path "D:/新建文件夹/comet-game-prototype"

# 也可以用 Godot 编辑器打开 project.godot 后按 F5 运行
```

### 首次使用提示

首次用编辑器打开时会出现「项目未导入」，这是正常的。选择 **Import**，
Godot 会生成 `.godot/` 缓存目录（已在 `.gitignore` 中排除）。

### 操作方式

启动后**自动捕获鼠标**（光标隐藏），直接移动鼠标即可转动视角，无须按住任何键。

| 操作 | 说明 |
| --- | --- |
| **W / A / S / D** | 前后左右移动。斜向速度已归一化，不会比单向更快 |
| **移动鼠标** | 环视四周。水平 360° 连续，垂直限制 ±75° |
| **E 键 / 鼠标左键** | 与屏幕中心准星所指的热点交互 |
| **ESC** | 释放鼠标并显示光标（此时可操作界面） |
| **Q 键** | 退出游戏 |
| **释放后点击画面** | 重新捕获鼠标（这次点击不会触发交互） |
| **返回按钮** | 沿来路返回上一个地点 |
| **保存按钮** | 保存当前进度 |
| **重新开始** | 清除存档并开新局 |

开局地点是**聚会房屋**（玩家身份 Emily 所在的那栋房子）。室外动线为
**门廊 → 车道 → 街道 → 没有灯的那段路**，一路直走即可抵达黑暗区域。

> 界面按钮需要先按 `ESC` 释放鼠标才能点击——这是有意设计，
> 避免镜头控制与界面操作抢占同一份鼠标输入。

---

## 三、目录结构

```
comet-game-prototype/
│
├── project.godot                  引擎工程配置（含 autoload 声明）
│
├── autoload/
│   └── game_services.gd           唯一的全局服务编排层
│
├── core/                          ---------- 运行时核心 ----------
│   ├── world_manager.gd           世界状态权威：当前世界 + 变更历史
│   ├── event_manager.gd           事件触发判定 + 历史记录
│   ├── scene_manager.gd           地点加载与切换、返回栈
│   ├── interaction_manager.gd     射线拾取热点、遮挡判定
│   ├── save_manager.gd            存档读写与完整性校验
│   ├── data_loader.gd             JSON 读取统一入口
│   ├── hotspot.gd                 可交互热点节点
│   ├── location.gd                地点根节点：按世界 id 切换表现
│   ├── player_controller.gd       第一人称环视
│   └── ui/
│       └── ui_manager.gd          界面与提示
│
├── data/                          ---------- 数据层（与代码分离）----------
│   ├── worlds.json                世界定义
│   ├── world_transitions.json     世界转移规则（世界变化的唯一合法来源）
│   ├── events.json                事件定义
│   ├── locations.json             地点、出口、支持的变体
│   └── README.md                  各字段含义说明
│
├── scenes/
│   ├── main.gd / main.tscn        主场景：装配各模块
│   ├── locations/
│   │   ├── living_room.tscn       客厅
│   │   ├── house_exterior.tscn    房屋外部
│   │   └── dark_road.tscn         黑暗区域
│   └── ui/
│       └── hud.tscn               界面根节点
│
├── tools/                         ---------- 离线构建脚本 ----------
│   ├── scene_builder.gd           场景构建驱动器
│   └── scene_content.gd           三个地点的实际内容
│
├── assets/
│   └── icon.svg                   项目图标（手写 SVG）
│
├── tests/
│   └── acceptance_test.gd        headless 验收测试（10 项验收条目）
│
├── docs/
│   ├── ARCHITECTURE.md            技术架构说明
│   ├── ACCEPTANCE.md              实际测试结果
│   ├── KNOWN_ISSUES.md            已知问题
│   ├── CHANGELOG.md               版本记录
│   └── THIRD_PARTY.md             第三方素材与许可证
│
├── LICENSE                        MIT
└── README.md
```

---

## 四、核心机制：地点与世界分离

地点 id 与世界 id 是**两个正交维度**。

- `house_entrance` 始终是 `house_entrance`，无论处于哪个世界；
- 决定它长什么样的，是当前的 `world_alpha` 还是 `world_beta`。

每个地点场景内有一组 `Variant_<world_id>` 节点，`GameLocation.apply_world()` 按当前世界
切换它们的显示；热点的出现与否由 `visible_only_in_worlds` 声明。

**明确禁止**用「每次加载随机决定」来制造差异。所有变化都必须能在
`data/world_transitions.json` 里找到对应规则，参见 `docs/ARCHITECTURE.md`。

### 本次实现的世界差异

穿越黑暗区域（`dark_road`）会触发一次 `fixed` 类型的世界转移：`world_alpha → world_beta`。
返回房屋外部后，实际可观察到 **7 处**差异（任务书要求至少 3 处）：

| # | 差异 | alpha | beta |
| --- | --- | --- | --- |
| 1 | 环境变体切换 | `Variant_world_alpha` 显示 | `Variant_world_beta` 显示 |
| 2 | 可用热点集合变化 | 有 `CrateAlpha` | 有 `CrateBeta` 与 `GlassShards` |
| 3 | **物品位置** — 木箱 | (1.60, -1.60) 正立 | (-1.50, -2.25) 倾倒 |
| 4 | **灯光** — 门廊灯 | 亮，`energy=5.50` | 熄灭（不可见） |
| 5 | **灯光** — 窗户自发光 | 开启（透出暖光） | 关闭（全黑） |
| 6 | **新增线索** — 碎玻璃 | 不存在 | 台阶旁出现蓝色碎片，可交互 |
| 7 | 门牌角度 | 0° | 倾斜 24° |

客厅另有两处低成本差异（相框正面/背面、电视屏幕开/关），用于强化「回来后不对劲」的感受。

---

## 五、如何验证它真的能跑

### 运行验收测试

```bash
godot --headless --script res://tests/acceptance_test.gd
```

覆盖任务书第十节全部 10 条验收项，共 **52 条断言**。当前状态：**PASS=52 FAIL=0**。
完整输出见 `docs/ACCEPTANCE.md`。

### 重新生成场景（修改场景内容后）

```bash
godot --headless --script res://tools/scene_builder.gd
```

### 无窗口运行主场景（快速冒烟）

```bash
godot --headless --quit-after 240
```

---

## 六、当前开发进度

### 已完成（第一阶段）

- [x] Godot 4.7.2 工程搭建，目录分层
- [x] 七个职责分离的模块（Scene / World / Event / Interaction / Player / UI / Save）
- [x] 三个地点的轻量化 3D 场景
- [x] 第一人称鼠标捕获式环视 + 垂直限位（v0.1.4 由拖动式升级）
- [x] WASD 地面自由移动 + 重力 + 碰撞（v0.2.0）
- [x] 热点射线拾取、悬停提示、点击交互
- [x] 地点切换与返回栈
- [x] 世界状态系统（固定事件驱动，一次确定性切换）
- [x] 地点 × 世界的差异表现（实测 7 处）
- [x] 存档 / 读档 / 数据校验 / 错误处理
- [x] headless 验收测试，52 条断言全通过
- [x] 真实渲染路径验证（OpenGL 3.3 Compatibility）

### 未完成 / 下一阶段建议

- [ ] 完整《Coherence》剧情线（第一阶段刻意只做机制，不复述电影）
- [ ] 伪随机事件的实际启用（架构通路已实现，当前未启用）
- [ ] 虚拟桌面、聊天软件、浏览器、文件管理器等 UI 浮层（挂载点 `register_overlay()` 已预留）
- [ ] 音效与氛围音设计
- [ ] 多周目、多分支世界
- [ ] 热点悬停的视觉反馈目前只有轻微自发光，尚未加入更明确的提示

详见 `docs/KNOWN_ISSUES.md`。

---

## 七、关于电影内容

本项目只是借用了「**熟悉的地点在不知不觉间变得不同**」这一叙事构想。

仓库内**不包含**电影的任何画面、音频、台词、角色或商标，也不复述其剧情。
任何关于电影本身的细节都请以影片内容为准，本项目不作为事实来源。

---

## 八、许可证

本项目代码采用 **MIT License**，详见 `LICENSE`。

不含任何第三方美术或音频素材；Godot 引擎自身为 MIT 许可证。
完整说明见 `docs/THIRD_PARTY.md`。
