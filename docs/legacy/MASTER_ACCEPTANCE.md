# COMET — 验收状态（MASTER_ACCEPTANCE）

> 本文件记录**当前 commit（`224224a`）** 的真实验收结果，并对照本任务书的完整游戏目标给出差距。
> 所有数字均为实际运行输出，非预期描述；无法实测的项目明确标注。

---

## 1. 测试环境

| 项 | 值 |
| --- | --- |
| 引擎 | Godot 4.7.2-stable（console/headless + 标准 GUI） |
| 渲染 | GL Compatibility（OpenGL 3.3） |
| 操作系统 | Windows 10 64 位 |
| 目标设备 | Lenovo 80T3 / i5-7200U / 12GB / Radeon 530 2GB |
| 分支 / commit | `recovery/master-rebuild` / `224224a` |
| 运行方式 | `godot --headless --script res://tests/<name>.gd` |

---

## 2. 自动化测试结果（当前 commit，实测）

```
acceptance_test        PASS=59 FAIL=0
v2_p0_test             PASS=13 FAIL=0
fps_input_test         PASS=29 FAIL=0
player_movement_test   PASS=34 FAIL=0
party_house_test       PASS=54 FAIL=0
wall_geometry_test     PASS=24 FAIL=0
door_connection_test   PASS=53 FAIL=0
dark_traverse_test     PASS=31 FAIL=0
save_isolation_test    PASS=10 FAIL=0
save_migration_test    PASS=27 FAIL=0
session_reset_test     PASS=17 FAIL=0
data_integrity_test    PASS=22 FAIL=0
ui_flow_test           PASS=12 FAIL=0
──────────────────────────────────
合计                    PASS=385 FAIL=0   （13 个测试文件）
```

主场景 `--headless --quit-after 200`：**0 error / 0 warning**。

覆盖范围（与完整游戏目标对照）：

| 目标能力 | 是否已有自动化断言 |
| --- | --- |
| 启动/新游戏/地点进入 | ✅ acceptance |
| WASD 移动 + 斜向归一化 + 撞墙/家具 | ✅ player_movement(34) |
| 鼠标视角 + 捕获/释放 + ±75° 限位 | ✅ fps_input(29) |
| 中心射线交互 + 2.5m 距离 + 隔墙 | ✅ door_connection / fps_input |
| 门级落点 + 三扇门往返 | ✅ door_connection(53) |
| 黑暗区域穿越 + 掉头 + 现实切换时序 | ✅ dark_traverse(31) |
| 存档原子性 / v1→v2 迁移 / 位置与返回栈恢复 | ✅ save_migration(27) |
| 测试不碰玩家正式存档 | ✅ save_isolation(10) |
| 新局状态清零 / 返回栈去重 | ✅ session_reset(17) |
| 四份 JSON 交叉校验 / 变体缺失告警 | ✅ data_integrity(22) |
| 二次确认 / 保存反馈 / 事件总线 | ✅ ui_flow(12) |
| 带洞口墙几何 | ✅ wall_geometry(24) |
| 住宅灰盒连通性/家具/灯光 | ✅ party_house(54) |
| **跳跃 / 蹲伏 / 奔跑** | ❌ 未实现，无断言 |
| **NPC 行为 / 导航 / 对话** | ❌ 未实现 |
| **玩家认知系统** | ❌ 未实现 |
| **手机系统** | ❌ 未实现 |
| **音频系统** | ❌ 未实现 |
| **主菜单 / 暂停 / 设置持久化** | ❌ 未实现 |
| **多存档槽 / 多结局** | ❌ 未实现 |

---

## 3. 真实窗口验收记录（历史实测，均带退出码 0）

| 项 | 结果 |
| --- | --- |
| 鼠标捕获 | `Input.mouse_mode == MOUSE_MODE_CAPTURED`，确认框弹出时释放、确认后重捕获 |
| 门级落点 | 三扇门落点/朝向各异，往返正确 |
| 黑暗穿越时序 | 进入黑暗 `world_alpha`，走出尽头 `world_beta`，位置 (0,4)→(0,-24) |
| 性能（当前 commit 单次采样） | party_house 60fps / 89 mesh / 86 static / 5 灯(4 可见)；house_exterior 60fps；静态内存 57MB、显存 16.4MB |
| 未确认项 | 独显(Radeon 530)还是核显(HD 620)运行时未确认；CPU/GPU 占用率 Godot 无系统级 API，未采集 |

---

## 4. Bug 修复状态（对照 `MASTER_BUG_REGISTER.md`）

| 状态 | 数量 | 说明 |
| --- | --- | --- |
| 已修已验证 | 18 | 有对应自动化断言且通过 |
| 已实现未验证 | 2 | BUG-009（事件失败不切场景）、BUG-018（失焦释放）——代码已改，缺真实窗口/端到端实测 |
| 部分修 | 5 | 含 BUG-017（fps_input 偶发失败，加了显式驱动+40帧收敛仍偶发，未定位到具体断言） |
| 未修 | 3 | interact 触发通道死码、单槽明文存档、音频、导出、鸭子类型 |

---

## 5. 相对「完整游戏」的差距（本任务书 P0–P13）

| 阶段 | 内容 | 现状 |
| --- | --- | --- |
| P0 审计 | 5 份 MASTER 文档 | ✅ 本轮完成 |
| P1 架构/数据规范 | 唯一状态权威、配置校验 | ✅ 已完成（DataValidator + 状态统一） |
| P2 场景整合 | 门/出口/坐标/碰撞 | ✅ 已完成（含侧门露台回程、黑暗掉头） |
| P3 玩家控制 | WASD/视角/跳跃/蹲伏 | ⚠️ 半完成：WASD+视角✅，**跳跃/蹲伏/奔跑❌** |
| P4 交互/UI | 距离/E键/对话/暂停/手机入口 | ⚠️ 半完成：距离+E键✅，**对话/暂停/手机❌** |
| P5 现实/事件 | 变体/黑暗穿越/切换时序 | ✅ 已完成（2 现实；`world_gamma` 未补） |
| P6 存档 | 读写/迁移/校验/兼容 | ⚠️ 半完成：原子+迁移+隔离✅，**多槽❌** |
| P7 剧情/人物 | 角色档案/NPC/对话/认知 | ❌ 未开始 |
| P8 手机 | 联系人/聊天/照片/通知 | ❌ 未开始 |
| P9 音频 | AudioManager/环境/脚步/语音/音乐 | ❌ 未开始（零音频资源） |
| P10 视觉 | 替换灰盒/材质/灯光/人物 | ❌ 未开始（仍纯色灰盒） |
| P11 完整流程 | 主菜单/开场/主线/结局 | ❌ 未开始 |
| P12 性能验收 | 目标设备全流程 | ⚠️ 仅单场景采样，无全流程压测 |
| P13 发布 | 文档/导出包 | ⚠️ 文档基本齐，**导出❌** |

---

## 6. 结论

**当前可验收的范围**：一个可运行的灰盒垂直切片——自由移动、中心射线交互（2.5m）、门级空间连接、黑暗穿越驱动的现实切换、可靠存档（原子+迁移+位置恢复）。385 条自动化断言全部通过，主场景零报错。

**尚未达到的范围**：本任务书定义的「从主菜单到结局的完整游戏」。跳跃/蹲伏、完整音频、8 名 NPC 与导航、对话与玩家认知、手机、多存档槽、多结局、Windows 导出——这些**均未实现，未有一行代码**，不能记为「基本完成」。

下一步需项目负责人确认总体方案后，按 P3→P13 顺序分阶段执行（每个阶段独立 commit + 自动化/真实窗口双验收）。
