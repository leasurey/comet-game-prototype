# COMET — 版本记录

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
