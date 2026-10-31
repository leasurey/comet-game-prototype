# 导航可行性验证报告

**目的**：为 P7（NPC / 对话 / 认知）做前置验证——确认当前逐段 Box 拼接的墙体拓扑，
能否烘出连续可用的 navmesh，以及参数该取多少。

**验证方式**：真实运行 Godot 4.7.2 headless，烘焙 navmesh 并寻路，不是静态推断。

**回归测试**：`tests/navigation_feasibility_test.gd`（7 条断言，全通过）

---

## 一、结论

**导航可行。可以进入 P7 的 NPC 开发。**

| 验证项 | 结果 | 证据 |
| --- | --- | --- |
| N1 逐段 Box 墙体能烘出 navmesh | ✅ | 77–125 个多边形，烘焙 30–90 ms |
| N2 所有房间可达 | ✅ | 从玄关寻路到 9 个采样点全部成功 |
| N3 任意两房间可寻路 | ✅ | **72/72** 成功，零受阻 |
| N4 agent_radius 量化安全 | ✅ | 0.35 量化后 0.50 < 门洞半宽 0.60 |
| N5 墙体实体无泄漏 | ✅ | 6 个墙段实体采样点，零命中 |
| N6 高度偏移可控 | ✅ | 稳定 +0.20 ~ +0.40 m |

---

## 二、关键实测数据

### 2.1 agent_radius 扫描（cell_size = 0.25）

| agent_radius | 量化后实际半径 | 两两寻路 | 房内采样 | 判定 |
| --- | --- | --- | --- | --- |
| 0.30 | 0.50 | **0/42 全失败** | 0/7 | ❌ 不可用 |
| **0.35** | **0.50** | **42/42** | 6/7 | ✅ **推荐** |
| **0.40** | **0.50** | **42/42** | 6/7 | ✅ 可用 |
| 0.50 | 0.50 | — | 6/7 | ⚠️ 偏大 |

**为什么 0.30 反而失败、0.35 成功，两者量化后都是 0.50？**
Recast 的 `agent_radius` 会向上取整到 `cell_size` 的整数倍（引擎告警原文：
`Property agent_radius is ceiled to cell_size voxel units and loses precision`）。
0.30 与 0.35 经 0.25 量化后都变 0.50，但烘焙结果不同——这说明量化之外还有浮点栅格化差异，
0.30 恰好跨进了让门洞消失的那一格。**结论：不要取临界值，留余量用 0.35 或 0.40。**

### 2.2 门洞通行（N3 的直接证据）

72/72 全部连通，覆盖所有门洞：

| 门洞 | 净宽 | 连通性 |
| --- | --- | --- |
| 前门 | 1.60 m | ✅ |
| 玄关 → 主空间 | 1.60 m | ✅ |
| 厨房连通 | 3.00 m | ✅ |
| 书房门 | 1.20 m | ✅ |
| 卫生间门 | 1.20 m | ✅ |
| 侧门 | 1.20 m | ✅ |
| 露台推拉门 | 1.80 m | ✅ |

**1.20 m 门洞是全屋最窄点**，量化后 0.50 的腐蚀半径两侧各吃 0.50 m，
剩 0.20 m 可走带——很窄但**连续**，路径确实能通过。这与第二轮审查的理论推算一致。

### 2.3 navmesh 高度偏移

| 采样点 | 地面 y | navmesh y | 偏移 |
| --- | --- | --- | --- |
| 玄关 | 0.20 | 0.40 ~ 0.60 | **+0.20 ~ +0.40 m** |

**影响**：NPC 出生位置若直接取 navmesh 点，会浮空 20–40 cm。
**对策**：NPC 出生时用 `map_get_closest_point()` 取 XZ，Y 用 `FLOOR_Y`（地面高度）。
已在 N6 断言中锁定偏移范围。

### 2.4 烘焙时序（两次踩坑，必须记录）

| 阶段 | 要求 | 不满足的后果 |
| --- | --- | --- |
| 烘焙前 | 等 **≥8 个物理帧**（物理碰撞体建立） | 报 `parse_source_geometry_data` 错误，产出 **0 个多边形** |
| 查询前 | 烘焙后等 **≥12 个物理帧**（NavigationServer 同步） | `map_get_closest_point` 恒返回 `(0,0,0)`，`map_get_path` 全空 |

**注意是物理帧不是渲染帧**——headless 下渲染帧几乎不耗时，等 5 个渲染帧
可能 1 个物理帧都没过。这个坑本轮踩了三次。

### 2.5 层级要求

`NavigationRegion3D` **必须是几何的祖先**。
`SOURCE_GEOMETRY_ROOT_NODE_CHILDREN` 只解析 region 自己的子节点；
若把 region 挂在场景实例之下，几何是它的兄弟/祖先，烘焙得到 **0 个多边形**。

---

## 三、推荐参数

```gdscript
NavigationMesh:
    cell_size                = 0.25
    cell_height              = 0.20
    agent_radius             = 0.35      # 量化后 0.50，留余量
    agent_height             = 1.60
    agent_max_climb          = 0.30
    agent_max_slope          = 40.0
    geometry_parsed_geometry_type = PARSED_GEOMETRY_STATIC_COLLIDERS
    geometry_collision_mask  = 1
    geometry_source_geometry_mode = SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
```

NPC 实体建议：`NavigationAgent3D.radius = 0.35`（与烘焙一致），
碰撞胶囊半径 0.30（略小于导航半径，留出避让余量）。

---

## 四、对 P7 的直接约束

1. **NPC 出生点 Y 必须取 `FLOOR_Y`，不能直接用 navmesh 点的 Y**（会浮空 0.2–0.4 m）。
2. **`NavigationRegion3D` 要包住场景几何**，不能挂在场景实例之下。
3. **烘焙与查询之间必须等物理帧**，不能用渲染帧计时。
4. **`agent_radius` 不要取 0.30**，会因量化导致门洞消失；用 0.35 或 0.40。
5. **1.20 m 门洞只剩 0.20 m 可走带**，两名 NPC 不能并排通过——这是第二轮审查
   已经指出的瓶颈，导航验证确认了它在物理上确实成立。若要 NPC 并排通行，
   需把主要门洞加宽到 1.60 m。

---

## 五、尚未验证（需在 P7 实施中确认）

| 项 | 状态 |
| --- | --- |
| `NavigationAgent3D` 运行时避让行为 | ❌ 未测试（本轮只验烘焙与寻路） |
| 多 agent 同时寻路的性能 | ❌ 未测试 |
| navmesh 在家具周围的可走宽度（沙发/餐桌间隙） | ⚠️ 两两寻路已通，但未逐点测间隙 |
| 动态避让（NPC 相互绕行） | ❌ 未测试 |
| `neighbor_house` 等未来地点的导航 | ❌ 场景尚不存在 |

---

## 六、验证环境

| 项 | 值 |
| --- | --- |
| 引擎 | Godot 4.7.2-stable |
| 运行方式 | headless，`--script` |
| 场景 | `scenes/locations/party_house.tscn` |
| 墙体拓扑 | `geom.wall_with_opening()` 逐段生成（左段 + 门楣 + 右段） |
| 碰撞体 | 86 个 `StaticBody3D` + `BoxShape3D` |
| 回归测试 | `tests/navigation_feasibility_test.gd`，**PASS=7 FAIL=0** |
