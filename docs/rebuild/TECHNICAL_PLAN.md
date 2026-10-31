# COMET 技术计划

> 基于对实际源码的审计（非旧报告）。本轮已修复四个地基缺陷。

---

## 一、审计结论（本轮实测）

| # | 问题 | 实际证据 | 状态 |
|---|---|---|---|
| 1 | `spawn_list` 死代码 | `to_spawn` 计算但循环用 `_characters.keys()` | ✅ 已修 |
| 2 | 对话 `next`/`goto` 断裂 | 9 条 reply 用 next，代码只读 goto | ✅ 已修 |
| 3 | 空 `Skeleton3D` | `Skeleton3D.new()` 无骨骼 | ✅ 已删除 |
| 4 | `DoorController` 未被调用 | main.gd 零引用 | ✅ 已接入 |
| 5 | 门 pivot 引用不持久 | 构建期 setup() 引用不随 .tscn 保存 | ✅ `_ready` 解析 |

---

## 二、现有系统分类

### A. 直接保留（验证可用）
| 系统 | 文件 | 依据 |
|---|---|---|
| WorldManager | core/world_manager.gd | 现实切换测试通过 |
| SceneManager | core/scene_manager.gd | 地点切换正常 |
| SaveManager | core/save_manager.gd | 存读档测试通过 |
| EventBus | core/event_bus.gd | 信号总线 |
| EventManager | core/event_manager.gd | effects 系统完整 |
| DialogueManager | core/dialogue_manager.gd | 变体+闸门可用 |
| CognitionManager | core/cognition_manager.gd | 三本账完整 |
| NPCManager | core/npc_manager.gd | 导航+行为可用 |
| PlayerController | core/player_controller.gd | FPS 控制稳定 |
| InteractionManager | core/interaction_manager.gd | 热点系统 |
| AudioManager | core/audio_manager.gd | 音频框架 |
| GameLogger | autoload/game_logger.gd | 日志系统 |

### B. 修改后保留
| 系统 | 需要改什么 |
|---|---|
| NPC | 换真实模型（Blender） |
| DoorController | 侧门/后门接入真实流程 |
| main.gd | 接入序章状态机 |

### C. 需要重写
| 系统 | 原因 |
|---|---|
| 场景几何 | BoxMesh 灰盒，需电影写实住宅 |
| 人物模型 | 低模拼接体，需 Blender 管线 |

### D. 需实测验证
| 项目 | 方法 |
|---|---|
| 导航网格 | 家具变化后重测 |
| 性能 | 目标低配机实测 |
| 变体稳定性 | 手动切换测试 |

---

## 三、实施顺序

```
阶段 A（当前）
  ✅ 修复四个地基缺陷
  ✅ 家具几何升级（沙发/桌/椅）
  ✅ 前门真实开合
  ⏳ 序章状态机接入

阶段 B
  □ Kevin 真实模型（Blender 管线）
  □ 其余 6 NPC
  □ 序章 P0-P3 串联

阶段 C
  □ 室外街区
  □ 黑暗区域氛围

阶段 D
  □ 现实切换视觉差异
  □ 侧门/后门真实流程

阶段 E
  □ 完整对话树
  □ 事件链接入

阶段 F
  □ 低配机性能验收
```

---

## 四、接口变更记录（本轮）

| 变更 | 兼容策略 |
|---|---|
| `Hotspot.door_name` 新增 | 默认空=旧传送行为 |
| `NPCManager.spawn_list` 生效 | 默认空=全部生成 |
| `replies.goto` 统一 | 代码双键兜底，旧数据可跑 |
| `DoorController.set_outside_ref` | 新增，不影响旧调用 |
| `geom.door()` 加 `yaw_deg` | 默认 0=旧行为 |

---

## 五、禁止事项

- ❌ 删除原有测试断言换取全绿
- ❌ 用 `_debug_activate()` 代替真实玩家操作验收
- ❌ 空节点冒充功能
- ❌ 不改存档兼容性
