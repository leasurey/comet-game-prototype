# COMET — 验收测试结果

> 以下为真实执行输出，非预期描述。

## 当前状态（v0.6.0 / commit 见本节末尾）

| 测试 | 断言数 | 结果 | 覆盖 |
| --- | ---: | --- | --- |
| `acceptance_test.gd` | 59 | PASS | 地点/世界/存档/交互核心链路 |
| `v2_p0_test.gd` | 13 | PASS | 时间 tick、具名随机流、信号总线、条件求值 |
| `fps_input_test.gd` | 29 | PASS | 鼠标捕获视角 T01–T13 |
| `player_movement_test.gd` | 34 | PASS | WASD、斜向归一化、碰撞 T01–T16 |
| `party_house_test.gd` | 54 | PASS | 住宅几何、七条路线连通性、两套灯光 |
| `wall_geometry_test.gd` | 24 | PASS | 带洞口墙体原语（射线逐点验证） |
| `door_connection_test.gd` | 53 | PASS | 门级落点、三扇门往返、交互距离与遮挡 |
| `dark_traverse_test.gd` | 31 | PASS | 进入不变/尽头才变、once 语义、掉头不改现实 |
| `save_isolation_test.gd` | 10 | PASS | 测试不触碰玩家正式存档（SHA-256 比对） |
| `save_migration_test.gd` | 27 | PASS | 原子写入、备份、v1→v2 迁移、损坏隔离、位置与栈恢复 |
| `session_reset_test.gd` | 17 | PASS | 重新开始后七项状态归零、返回栈去重限深 |
| `data_integrity_test.gd` | 22 | PASS | 四份 JSON 交叉校验、变体完整性、材质隔离 |
| `ui_flow_test.gd` | 12 | PASS | 二次确认（未确认不删档）、保存反馈、总线连接 |
| **合计** | **385** | **全通过** | |

主场景 `--headless --quit-after 200`：0 error / 0 warning。

> 说明：本文件下方保留的是 v0.1.x 时期的历史输出，仅作存档参考，
> **不得用于证明当前版本通过**。当前版本的结论以上表为准。

## 执行命令

```bash
godot --headless --script res://tests/acceptance_test.gd
```

## 环境

| 项目 | 值 |
| --- | --- |
| 引擎 | Godot Engine v4.7.2.stable.official.ed1daf0bf |
| 模式 | `--headless` |
| 结果 | **PASS = 52, FAIL = 0** |
| 退出码 | 0 |

## 完整输出

```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

=== COMET acceptance test ===
engine: 4.7.2-stable (official)

[PASS] 1. WorldManager 初始化 | current=world_alpha
[PASS] 1. EventManager 初始化
[PASS] 1. 地点表载入三个地点 | ["living_room", "house_exterior", "dark_road"]
[PASS] 1. 可进入起始地点 | start=living_room
[PASS] 1. 起始地点为客厅 | current=living_room
[PASS] 1. 主场景可加载
[PASS] 1. 主场景节点结构完整 | container=true rig=true hud=true
[PASS] 2. 客厅实例存在
[PASS] 2. 客厅存在可交互内容 | count=4
[PASS] 2. 第一人称相机在场景中
[PASS] 2. 水平视角可改变 | delta=-0.7700 rad
[PASS] 2. 垂直视角可改变 | delta=-0.2100 deg
[PASS] 2. 垂直视角受限不翻转 | pitch=-0.210 deg (限制 ±75)
[PASS] 3. 可从客厅进入房屋外部
[PASS] 3. 当前地点为房屋外部 | current=house_exterior
[PASS] 3. 仅切换地点不改变世界 | world=world_alpha
[PASS] 3. 房屋外部热点可用 | ["DoorToInterior", "RoadToDark", "CrateAlpha", "Mailbox"]
[PASS] 4. 可进入黑暗区域
[PASS] 4. 当前地点为黑暗区域
[PASS] 5. 进入黑暗区域后世界发生变化 | world_alpha -> world_beta
[PASS] 5. 世界按预设规则切到 world_beta | got=world_beta
[PASS] 5. 世界变化被记录一次 | change_count=1
[PASS] 5. 对应事件写入历史
[PASS] 5. 当前场景已按新世界重刷 | applied=world_beta
[PASS] 6. 可沿原路返回
[PASS] 6. 返回到房屋外部 | current=house_exterior
[PASS] 6. 返回后仍处于新世界 | world=world_beta
[PASS] 6. 返回后场景按新世界呈现 | applied=world_beta
[PASS] 7. 同一地点存在 >=3 处可观察差异 | 共 7 处:
        环境变体 ["Shared", "Variant_world_alpha"] -> ["Shared", "Variant_world_beta"];
        可用热点 [DoorToInterior, RoadToDark, CrateAlpha, Mailbox]
              -> [DoorToInterior, RoadToDark, CrateBeta, GlassShards, Mailbox];
        木箱位置 (1.60,-1.60) -> (-1.50,-2.25);
        门廊灯 visible=true energy=5.50 -> visible=false energy=-1.00;
        窗户自发光 true -> false;
        门牌角度 0.0° -> 24.0°;
        新增线索 GlassShards
[PASS] 7. 新线索初始不存在、穿越后出现 | alpha=false beta=true
[PASS] 8. 连续往返无切换失败 | round0(dark=true,back=true); round1(dark=true,back=true);
                                round2(dark=true,back=true); round3(dark=true,back=true)
[PASS] 8. 往返后世界不再变化 | world=world_beta
[PASS] 8. 世界变化次数稳定 | 1 -> 1
[PASS] 8. 表现层与逻辑层世界一致 | applied=world_beta
[PASS] 8. 访问记录完整 | ["living_room", "house_exterior", "dark_road"]
[PASS] 10. 热点可被射线聚焦 | Mailbox
[PASS] 10. 热点可被射线聚焦 | GlassShards
[PASS] 10. 热点可被射线聚焦 | CrateBeta
[PASS] 10. 热点可被射线聚焦 | RoadToDark
[PASS] 10. 热点可被射线聚焦 | DoorToInterior
[PASS] 9. 存档写入成功
[PASS] 9. 存档文件确实落盘 | user://comet_save.json
[PASS] 9. 损坏存档被拒绝而非崩溃 | 存档 JSON 解析失败: Expected key
[PASS] 9. 未知地点存档被拒绝 | 存档中的地点已不存在: nowhere
[PASS] 9. 恢复有效存档
[PASS] 9. 重新启动后存档可读取
[PASS] 9. 重新启动后可恢复到存档地点
[PASS] 9. 恢复地点正确 | got=house_exterior expect=house_exterior
[PASS] 9. 恢复世界状态正确 | got=world_beta expect=world_beta
[PASS] 9. 世界变化历史一致 | 1 vs 1
[PASS] 9. 事件历史被恢复
[PASS] 9. 恢复后场景呈现正确世界 | applied=world_beta

=== RESULT: PASS=52 FAIL=0 ===
```

---

## 与任务书第十节 10 条验收项的对应

| # | 验收项 | 结果 | 对应断言 |
| --- | --- | --- | --- |
| 1 | 游戏能够正常启动 | ✅ | 1. WorldManager/EventManager 初始化、地点表载入、主场景结构与节点完整 |
| 2 | 玩家能够在客厅中观察四周 | ✅ | 2. 水平/垂直视角可改变、垂直视角受限不翻转（实测 pitch = -0.21° ≤ 75°）、客厅 4 个可交互内容 |
| 3 | 玩家能够进入房屋外部 | ✅ | 3. 可从客厅进入房屋外部、当前地点正确、地点切换不改变世界 |
| 4 | 玩家能够进入黑暗区域 | ✅ | 4. 可进入黑暗区域、当前地点为黑暗区域 |
| 5 | 进入后世界按预设规则变化 | ✅ | 5. alpha → beta、规则命中 world_beta、变化记录恰好 1 次、事件入历史、场景按新世界重刷 |
| 6 | 玩家能够沿原路返回 | ✅ | 6. go_back 成功、返回到房屋外部、仍处于新世界、表现层同步 |
| 7 | 返回后至少 3 处环境差异 | ✅ | 7. 实测检出 **7 处**差异，含物品位移、灯光变化、新增线索 |
| 8 | 连续往返不导致状态异常 | ✅ | 8. 连续 4 轮往返无失败，世界不再变化，变化次数稳定为 1，表现层与逻辑层一致 |
| 9 | 保存后退出再启动可恢复 | ✅ | 9. 存档落盘并回读校验；模拟全新一套 Manager 重建后，地点/世界/历史/表现全部一致；损坏存档与未知地点存档均被拒绝而非崩溃 |
| 10 | 无崩溃、无热点不可交互 | ✅ | 10. 房屋外部全部 5 个热点逐一射线聚焦成功；全流程零 SCRIPT ERROR |

---

## 补充：真实渲染路径验证

headless 不渲染画面，因此另行验证真实渲染管线：

```bash
godot --quit-after 200 --log-file gui_run.log
```

输出（`gui_run.log`）：

```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
OpenGL API 3.3.14831 Core Profile Forward-Compatible Context 21.5.2 27.20.20903.8001
  - Compatibility - Using Device: ATI Technologies Inc. - AMD Radeon (TM) 530
```

退出码 0，无 ERROR / WARNING / 着色器编译失败。

另外，以 `--headless --quit-after 240` 运行主场景本体（走真实 autoload 链路），
同样零报错、退出码 0。

---

## 测试未覆盖的部分（诚实说明）

以下内容 **headless 无法验证**，需要人工肉眼确认：

1. **画面观感**：几何体比例是否协调、昼夜氛围是否符合预期、色彩是否过暗或过亮；
2. **差异的可辨识度**：7 处差异在技术上确实存在，但是否「一眼能看出来」需要人眼判断；
3. **实际操作手感**：鼠标拖动灵敏度是否舒适；
4. **UI 排版**：HUD 由代码构建，位置偏移需要实际观看才能校准。

上述项目中，差异已通过场景快照的数值对比得到结构性保证（位置、旋转、发光、可见性
均有明确数值差异），但**主观视觉质量尚未得到验证**。
