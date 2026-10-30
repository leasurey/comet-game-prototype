# COMET — 技术架构说明

## 一、总体分层

```
┌──────────────────────────────────────────────────────────────┐
│  表现层  scenes/*.tscn, GameLocation, Hotspot, Camera3D       │
│          负责「看起来是什么样」，不含任何剧情规则                │
├──────────────────────────────────────────────────────────────┤
│  装配层  autoload/game_services.gd + scenes/main.gd           │
│          负责把下层模块连起来，不含业务逻辑                     │
├──────────────────────────────────────────────────────────────┤
│  逻辑层  core/*_manager.gd                                    │
│          SceneManager / WorldManager / EventManager /         │
│          InteractionManager / SaveManager                     │
│          不触碰 UI 文本，不直接操作几何体                       │
├──────────────────────────────────────────────────────────────┤
│  数据层  data/*.json                                          │
│          地点、世界、事件、转移规则，可脱离代码独立编辑           │
└──────────────────────────────────────────────────────────────┘
```

依赖方向严格自上而下。下层不知道上层的存在。

---

## 二、七个职责模块

任务书要求至少划分七个职责。本项目的对应关系与边界如下。

### 1. SceneManager — 场景加载与地点切换

**负责**：加载 `.tscn`、实例化、释放旧实例、维护返回栈与访问记录。

**不负责**：决定这个地点该长什么样。

**关键约定**：地点 id 与世界 id 正交。切换地点本身**永远不会**改变世界。
但如果进入某地触发了事件、进而改变了世界，SceneManager 会在事件求值之后
再刷一次表现，让同一个地点立刻呈现新世界的样子。

```
enter_location(id)
  ├─ 压栈（previous → _visit_stack）
  ├─ 释放旧实例（remove_child + queue_free）
  ├─ instantiate → add_child
  ├─ apply_world(当前世界)
  ├─ 收集热点 → InteractionManager
  ├─ emit location_entered
  └─ EventManager.evaluate("enter_location", {location_id: id})
        └─ 若 world 变了 → 再次 apply_world + 重新收集热点
```

### 2. WorldManager — 世界状态与世界转移规则的执行

**负责**：当前处于哪个世界，以及世界是怎么一步步变的。

**不负责**：判定什么时候该变（那是 EventManager 的事）。

**唯一入口**：`apply_transition(to_world_id, reason_id)`。
不接受随便切换到任意世界的调用场景；每次变更都会写入 `change_log`，
记录 `from / to / reason`，保证可追溯。

### 3. EventManager — 事件触发与历史记录

**负责**：「什么时候该发生什么」，并记录「已经发生过什么」。

**不负责**：直接改世界。它通过调用 `WorldManager.apply_transition()` 完成变更，
让「判定」与「执行」分离，避免历史漏记。

**三类规则**（架构全部支持，第一版只启用 `fixed`）：

| 类型 | 语义 |
| --- | --- |
| `fixed` | 条件满足就必须发生，目标世界唯一确定 |
| `conditional` | 需额外条件全部满足 |
| `pseudo_random` | 只能在 `candidate_worlds` 范围内取值，由 `seed + 触发序号` 决定 |

`pseudo_random` **不是真随机**：相同 seed 与相同触发序号必然得到相同结果，
因此可复现、可测试。这是为了避免「玩家看不出是随机的还是崩了」。

### 4. InteractionManager — 热点识别与交互

**负责**：准星指向了哪个热点，点击时派发给谁。

**不负责**：热点代表什么剧情。

**遮挡处理**：分别对静态环境层（layer 1）和热点层（layer 2）投射射线，
若墙壁比热点更近则视为被遮挡，**不允许隔墙点击**。

### 5. PlayerController — 第一人称观察控制

**负责**：把鼠标移动翻译成 yaw / pitch。

**输入机制**：使用原生鼠标捕获 `Input.MOUSE_MODE_CAPTURED`。
捕获后引擎在 `InputEventMouseMotion.relative` 中直接给出本次位移量，
因此不需要任何屏幕坐标补偿，鼠标移到窗口边缘也不会中断。
`capture_mouse()` / `release_mouse()` 由 `main.gd` 在启动、ESC、退出时调用；
`_exit_tree()` 里还会再释放一次，作为兜底。

**实现要点**：yaw 施加在自身 Y 轴，pitch 施加在子 `Camera3D` 的 X 轴。
分成两层可以避免欧拉角耦合导致的视角翻转；pitch 额外做 ±75° 硬限位，双保险。

**单位约定**：yaw 与 pitch 一律使用**弧度**。
早期版本曾出现「按弧度累加、按度数使用」的单位混乱，
使垂直灵敏度比水平低约 57 倍；v0.1.4 已全链路统一，并有测试守护两者比值为 1.00。

**yaw 收敛**：`yaw` 每次应用后 `wrapf` 到 `[-π, π]`，避免长时间游玩后浮点精度下降。
`-π` 与 `+π` 是同一朝向，视觉连续，不会出现跳变或突然回正。

### 6. UIManager — 界面与提示

**负责**：把状态显示出来，把界面操作转成信号。

**不负责**：读世界数据或做射线检测。

**扩展点**：`register_overlay(panel)`。后续虚拟桌面、聊天软件、浏览器、
文件管理器一律挂到 `OverlayLayer`，不塞进 HUD 分支。

### 7. SaveManager — 状态保存与恢复

**负责**：把状态安全写盘、安全读回、并做完整性校验。

**不负责**：知道哪些 id 合法——那由调用方注入（依赖倒置），
这样 SaveManager 可以独立于其他模块测试。

**校验项**：magic / version / 必需字段 / 类型 / 地点与世界 id 是否存在。
写盘后会**立即回读一次**验证可解析，避免产出损坏存档。

---

## 三、为什么核心 Manager 继承 `RefCounted` 而不是 `Node`

`WorldManager`、`EventManager`、`SaveManager` 都是 `RefCounted`：

1. **不依赖 SceneTree**，可以在 `godot --headless --script` 下直接实例化做单元测试；
2. 数据由外部注入（`load_from_data()`），不自己读文件，逻辑与环境彻底解耦；
3. 依赖倒置：`SaveManager` 通过参数接收合法 id 集合，不反向依赖 `WorldManager`。

`SceneManager` 与 `InteractionManager` 需要 SceneTree 才能工作（前者操作节点树，
后者需要物理空间），因此是 `Node`，由 `GameServices` 挂载。

---

## 四、为什么只有一个 autoload

`GameServices` 是唯一的 autoload。所有 Manager 作为普通对象在这里装配。

这样做的考虑：
- 依赖关系显式可见，不用去工程配置里翻 Autoload 列表；
- 替换实现或加单元测试不需要改 `project.godot`；
- 避免「全局变量满天飞」导致的状态不确定。

---

## 五、世界差异如何落到位

核心约束：**节点集合恒定，只有可见性变化。**

```
HouseExterior (GameLocation)
└── Environment
    ├── Shared                  ← 不随世界变化（地面、房屋主体、树）
    ├── Variant_world_alpha     ← 只有 Variant_ 前缀参与世界切换
    └── Variant_world_beta
Hotspots                        ← 热点集合恒定
    ├── DoorToInterior
    ├── RoadToDark
    ├── CrateAlpha              ← visible_only_in_worlds = ["world_alpha"]
    ├── CrateBeta               ← visible_only_in_worlds = ["world_beta"]
    ├── GlassShards             ← visible_only_in_worlds = ["world_beta"]
    └── Mailbox
```

**不在于**：切换世界时动态增删节点。
这样即使连续往返几十次，场景树结构也不会错乱——这是「往返不产生状态异常」的结构性保证。

热点跟随物件位置：木箱在两个世界里位置不同，因此用**两个互斥的热点**
（同一 `display_name`）分别绑定各自世界，而不是让一个热点在运行时搬家。

---

## 六、场景为什么由脚本生成

`scenes/locations/*.tscn` 由 `tools/scene_builder.gd` 生成。

原因：手写场景文本对属性名、资源引用、子节点归属极为敏感，
容易产出「加载不报错但节点缺失」的坏场景。由 Godot 自己 `PackedScene.pack()`
产出的文件与编辑器生成的完全一致，且仍可在编辑器里打开继续调整。

副作用是：**改场景要改 `tools/scene_content.gd` 再重新生成**，
直接改 `.tscn` 会在下次生成时被覆盖。这一点必须记住。

---

## 七、存档格式

`user://comet_save.json`，明文 JSON 便于审阅。

```jsonc
{
  "magic": "COMET_SAVE",
  "version": 1,
  "saved_at_unix": 1761...,
  "location_id": "house_exterior",
  "world_id": "world_beta",
  "visited_locations": ["living_room", "house_exterior", "dark_road"],
  "world_change_records": [
    { "index": 0, "from": "world_alpha", "to": "world_beta", "reason": "evt_cross_dark_road" }
  ],
  "triggered_events": ["evt_cross_dark_road"],
  "event_history": { "evt_cross_dark_road": { "count": 1, "first_index": 0, "last_index": 0 } },
  "event_sequence": ["evt_cross_dark_road"],
  "game_clock_minutes": 1420.0,
  "player_view": { "yaw": 0.0, "pitch": 0.0 }
}
```

读取时逐字段校验；任何一项不合法（含引用了已删除的地点/世界/事件）
都**整体拒绝恢复**并由上层回退到新游戏，绝不进入半损坏状态。

---

## 八、关键设计决策与权衡

| 决策 | 理由 | 代价 |
| --- | --- | --- |
| 固定观察点而非自由移动 | 消除相机错位/朝向丢失风险，聚焦核心机制 | 场景必须围绕单视点构图 |
| 三个地点共用一个观察点坐标 | 切换地点不可能丢朝向 | 不同地点无法各自设定视点高度 |
| 核心 Manager 用 `RefCounted` | 可 headless 单元测试 | 需要显式装配 |
| 单个 autoload | 依赖显式可见 | 多一层转发 |
| 场景由脚本生成 | 避免手写 tscn 出错 | 不能直接编辑 .tscn |
| HUD 用代码构建 | 避免手写 Control anchor 出错 | 编辑器内无法可视化调整 UI |
| 只用基础几何体 | 零第三方素材 | 美术表现粗糙 |
| 第一版只启用 `fixed` 事件 | 避免不可控变量 | 伪随机通路暂未实践验证 |
