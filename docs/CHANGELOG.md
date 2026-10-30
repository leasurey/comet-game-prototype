# COMET — 版本记录

## v0.4.0 — 住宅灰盒重建（13.4 × 9.4）与性能验收

按第三轮核验报告的坐标表重建聚会住宅，替换 v0.3.0 的 13×9 初版灰盒。

### 建筑

- 外轮廓 13.4 × 9.4 m，层高 2.7，外墙 0.20 / 内墙 0.12
- 房间：书房、卫生间、玄关+侧门通道、厨房南段、主空间（客厅/餐厅/厨房北段开放无墙）
- 八个门洞按通行情形分级：主要通道 1.60（前门/玄关洞口），房间门 1.20，厨房连通 3.00
- 室外：门廊 y 0.10、露台 y 0.20、侧院 y 0.20、缓冲地面 y 0.00
- 产出 86 个静态碰撞体、89 个网格、7 个热点

### 家具（15 类占位）

沙发、咖啡桌、电视柜、电视、壁炉、地毯、餐桌 + 8 椅、北/东台面、冰箱、岛台、书桌、笔记本、书架、鞋柜、洗手台、马桶。

第三轮的三处修正全部落实：取消单人椅、餐桌南移、餐桌改沿 Z 向摆放。

### 灯光

alpha 四盏吸顶灯；beta 全屋停电，只留餐桌上一支蜡烛。
两套灯光分属 `Variant_world_alpha` / `Variant_world_beta`，几何在 `Shared` 中不随现实消失。

### 建造中修复的四个真实缺陷

1. **走出前门掉出地图**（实测 y 掉到 −25）：补室外缓冲地面与门廊/露台/侧院
2. **W3 实心墙隔断侧门通道**：侧门开在东外墙，而该外墙属厨房南段一侧，故 W3 必须开洞
3. **餐桌堵在玄关正前方**：餐桌东移 0.70
4. **岛台横压侧门通道**：两次南移仍重叠，最终贴南墙，z 1.10~3.74 让开
5. 另：电视柜原位置堵死露台推拉门，已西移

### 测试

`party_house_test` 重写为 54 条断言（原 21 条），覆盖七条路线连通性、家具完整性、灯光独立性。

```
party_house 54/0 · wall_geometry 24/0 · movement 34/0
fps_input 29/0 · acceptance 58/0 · v2_p0 13/0
                —— 212 条断言，0 失败
```

测试框架修正两处：超时判断由渲染帧改为物理帧（headless 不限帧，渲染帧会误杀正常步骤）；P06 起点从咖啡桌边角移到空地。

### 性能（真实窗口）

加载 42 ms · 平均 57 FPS · 最低 41 FPS · 静态内存 57.5 MB · 显存 16.3 MB · 图元 344 · 绘制调用 13。
CPU / GPU 占用率未能采集（Godot 无系统级 API），不计入"已优化"。

详见 `docs/GREYBOX_ACCEPTANCE.md`。

## v0.3.1 — 开局改到聚会房屋 + 室外空间序列补全

### 变更

**初始地点由客厅改为聚会房屋**

`start_location` 改为 `party_house`。玩家身份是 Emily，第一人称应当从她自己所在的那栋房子开始，
而不是从一个无关的客厅开始。新开局直接落在聚会房屋的走廊侧。

**室外空间扩展为「门廊 → 车道 → 街道 → 黑暗路段」**

原先的 `house_exterior` 只有房屋立面、门廊、一条窄径和几棵树，出不了院子。
本版沿出门朝向（-Z）铺出完整动线：

| 新增 | 内容 |
| --- | --- |
| 车道 | 6.4 × 9.6 m 混凝土面，从门廊台阶直达街道 |
| 街道 | 44 × 6.5 m 横向沥青路面，含中线与两侧路缘 |
| 路缘 | 在车道口与黑暗路段口两处断开，否则会挡住玩家的唯一通路 |
| 停放的汽车 | 车身 + 车顶 + 车窗 + 四轮，靠右侧停放，把 x≈0 主通路整条让出 |
| 街边路灯 | 2 盏，灯柱固定、灯头随世界变化 |
| 街对面的房子 | 带两扇始终亮着的窗，对应影片中「另一扇亮着的窗」 |
| 黑暗路段入口 | 无任何照明的窄路，接 `dark_road` |

地面由 40×40 扩到 56×60 以容纳上述内容；静态碰撞体由 9 个增到 12 个。

**新增两个可检查热点**

`ParkedCar`（车道上的车）、`FarHouseWindow`（街对面亮着窗的房子），
均为 examine 类型，呼应影片中人物出门检查车辆、以及反复望向对面窗户的情节。

### 差异扩容

`world_beta` 中街道两盏路灯熄灭（`LampHeadA/B` 换成熄灭材质，无 `OmniLight3D`），
与已有的门廊灯熄灭一起，构成影片那种「整个区域停电」的观感。
可观察差异由 7 处增至 8 处，acceptance 的 `>= 3` 断言不受影响。

### 修复

**车道上的车把玩家挤离轴线 4.3 m**

车最初停在 x=1.55，与玩家从 x=0 出发的通行路径之间只剩 33cm 余量。
一旦蹭上 `CarBody`，`move_and_slide` 会沿车身一路滑行，实测走到离轴线 4.29 m 的草地上。
车改停 x=2.10、车道加宽到 6.4 m 后，通路余量提升到 0.9 m，实测横向偏移 0.000 m。

**测试对 `start_location` 的隐式依赖**

`player_movement_test` 的撞墙与家具断言绑定的是客厅实际墙体坐标，
开局地点改动后它会拿客厅的坐标去判定聚会房屋，属于前提失效而非功能故障。
现改为在 setup 末尾显式 `enter_location("living_room")`，不再依赖配置值。
`acceptance_test` 的「起始地点为客厅」同步改为「实际进入地点与配置一致」+「配置确为 party_house」两条，
比原来更严格。

### 验证

```
party_house_test      23/0
wall_geometry_test    24/0
player_movement_test  34/0
fps_input_test        29/0
acceptance_test       58/0
v2_p0_test            13/0
                     —— 181 条断言，0 失败
主场景 headless 200 帧：0 条 error/warning
```

GUI 实测（真实窗口，AMD Radeon 530 / OpenGL 3.3 Compatibility）：

- 开局地点 `party_house`，`Input.mouse_mode = 2 (CAPTURED)`
- 从台阶下方向前直走 7 秒，前进 18.72 m，横向偏移 0.000 m，抵达黑暗路段入口
- 室外 60 fps，聚会房屋室内 33–38 fps

## v0.3.0 — 聚会房屋灰盒（场景考古第一阶段）

### 新增

**聚会房屋灰盒场景 `party_house`**

按用户确认的 13.0 × 9.0 m 尺寸构建，含客厅、餐厅、厨房、走廊、卫生间、露台、
室外地面。共 89 个静态碰撞体、8 个交互热点、两套灯光（有电 / 停电）。

**全部尺寸与房间划分为游戏原创（证据等级 D）**。电影从未提供户型图，
本布局只依据「这些空间在片中确实存在」这一 A 级事实 + 8 人聚会的功能需求推导。
证据表与判断依据见 `docs/SCENE_ARCHAEOLOGY_PARTY_HOUSE.md`。

**构建器拆分为多文件**

```
tools/lib/geom.gd     几何原语（含 wall_with_opening、room_shell）
tools/lib/light.gd    灯光与环境原语
tools/lib/props.gd    家具体块原语（沙发/餐桌/椅/岛台/壁炉/书桌等）
tools/house/house_party.gd      墙体与房间布局
tools/house/house_furniture.gd  家具摆放
tools/house/house_lighting.gd   两套灯光
```

`tools/scene_content.gd`（三个旧场景）**完全未动**，零回归风险。

**`wall_with_opening()` —— 带洞口的墙**

做房间的关键原语。整块盒子的墙无法开门窗，直接留缺口又会漏光、玩家能穿出。
实现方式是把墙沿长度切成「左段 + 门楣 + 右段」（窗洞再加窗台段），
每段独立带碰撞。附 24 条专项测试，用物理射线逐点验证洞口通透、门楣实心、
边界无缝隙。

### 修复

**1. 构建器「假成功」**
构建器脚本解析失败时，`PackedScene.pack()` 仍会成功，产出空场景而日志显示"已生成"。
实测踩到一次（party_house 生成了 0 个碰撞体、0 个热点却报成功）。
现增加空节点检测，构建器未产生任何节点即判为失败。

**2. 新入口热点嵌在建筑内部**
`ExitToPartyHouse` 初始位置 (3.2, *, 2.6) 落在房子主体范围（z 1.6~6.8）内，
被墙体完全包住，射线永远打在墙上而无法聚焦。已移到 (3.9, *, 1.2)。

**3. 测试阶段变量跨步骤污染**
`party_house_test` 曾把 `_t_state` 在步骤间链式传递，导致 setup 结束后 P01 的
初始化分支被整段跳过，`enter_location` 从未执行——**测的其实是 living_room**，
表现为「热点名字全是旧场景的」。现改为每步独立从 0 开始，由外层统一归零。

### 连通性

`house_exterior` 新增出口热点 `ExitToPartyHouse`，叙事上是「另一栋几乎一样的房子」，
呼应影片「同一栋房子的不同版本」的核心设定。`party_house` 前门可返回 `house_exterior`。

### 验证

| 测试 | 结果 |
| --- | --- |
| `wall_geometry_test`（新增） | **PASS=24 FAIL=0** |
| `party_house_test`（新增） | **PASS=23 FAIL=0** |
| `player_movement_test` | **PASS=34 FAIL=0** |
| `fps_input_test` | **PASS=29 FAIL=0** |
| `acceptance_test` | **PASS=55 FAIL=0** |
| `v2_p0_test` | **PASS=13 FAIL=0** |

合计 **178 条断言，0 失败**。主场景 headless 200 帧零报错。

**GUI 实测**：进入 `party_house` 成功，`on_floor=true`，位置 (0, 0, 3.4)。
**帧率 33 fps**（旧三个场景为 60）——见下方已知问题。

### 已知问题（本次新增）

- **聚会房屋帧率偏低（33 fps）**：室内 12 盏灯 + 89 个碰撞体，Compatibility
  (OpenGL) 前向渲染对多光源较吃力。仅启动初期采样，未做长时间稳定测量。
  后续可减少同时点亮的灯数量，或改用更少、范围更大的光源。
- 门内外地面等高（无台阶），灰盒简化，非影片依据。

---

## v0.2.0 — WASD 地面移动

### 新增

**玩家可以在三个地点内自由行走。**

- WASD 前后左右移动，斜向由 `Input.get_vector()` 自动归一化，不会更快
- 移动方向只取玩家 yaw，抬头/低头不影响移动方向（结构上保证：pitch 只存在于子相机）
- 重力 + 地面吸附，可稳定站在地板上
- 移动速度 2.6 m/s，集中在 `PlayerController` 常量与 `@export` 中
- 松开按键立即停止，无惯性滑行

**玩家节点升级**

`CameraRig` 由 `Node3D` 改为 `CharacterBody3D`，新增胶囊碰撞体
（半径 0.32 / 总高 1.72）。**职责划分未变**：本节点仍负责 yaw 与移动，
子 `Camera3D` 仍负责 pitch 与渲染。观察高度仍为 1.62 米，
改由 `Camera3D` 的 local y 承担，玩家原点表示脚底。

**场景碰撞体（此前完全缺失）**

原三个场景共 47 个 `MeshInstance3D`，`StaticBody3D` 数量为 **0**，
玩家无处可站、无墙可撞。现由 `tools/scene_content.gd` 的 `_solid()`
生成 19 处静态碰撞（地面、地板、天花板、墙体、家具、房屋主体、台阶、木箱）；
装饰性物件（树冠、窗玻璃、碎片）保持无碰撞，避免绊住玩家。

**数据驱动的出生点**

`locations.json` 每个地点新增 `spawn.position`。
之所以必需：三个地点地面高度不同（室内地板顶面 y=0，室外门廊顶面 y=0.20），
统一写死一个坐标会让玩家在某处出生时嵌进地面。
切换地点时按该地点 spawn 重置玩家位置，避免带着上一个地点的坐标落进墙体。

### 修复

**1. 垂直灵敏度比水平低约 57 倍**（v0.1.4 遗留的根因）
`pitch` 按弧度累加却按度数使用，移动 1000 像素水平转 200°、垂直只转 3.5°。
现已全链路统一为弧度，实测两者比值 = 1.00。

**2. 客厅出生点过近**
原出生点 (0,0) 距沙发右边缘仅 0.32 米（恰等于玩家半径），一按 A 就贴死。
已改为 (1.2, 0.8) 的空旷位置。

### 关于测试断言调整（非放水，逐条说明）

- `acceptance_test` 中 `_rig.position` 由 `(0,1.62,0)` 改为 `(0,0,0)`：
  节点语义变了（原点＝脚底），并新增关闭该测试 rig 物理处理的调用，
  因为手工装配的 rig 无碰撞体、会每帧下落导致相机下沉、射线失真。
- `acceptance_test` 热点扫描前把玩家放到该地点真实 spawn：
  与 `main.gd` 运行时行为一致，否则相机偏低会被台阶遮挡。
- `fps_input_test` 遮挡体由 `queue_free()` 改为立即 `remove_child + free`：
  `queue_free` 只在帧末释放，物理空间里会多存活一帧，污染下一步骤。
- 新增 `T11/T12` 的**双向断言**（既检查不越界、也检查确实移动到位），
  比原来只检查上界更严格——原断言会让「根本没动」也判为通过。

### 验证

- `tests/player_movement_test.gd`：**PASS=34 FAIL=0**
- `tests/fps_input_test.gd`：**PASS=29 FAIL=0**
- `tests/acceptance_test.gd`：**PASS=53 FAIL=0**
- `tests/v2_p0_test.gd`：**PASS=13 FAIL=0**
- GUI 实机：60 fps，`on_floor=true`，观察高度 1.62，移动位移与脚本测试一致

---

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
