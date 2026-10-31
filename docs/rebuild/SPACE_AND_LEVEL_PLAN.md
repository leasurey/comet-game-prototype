# 空间与关卡重建方案

> 核心问题：当前场景是 BoxMesh 灰盒，需要重建为电影写实住宅。
> 电影中住宅的实际布局未完整展示，以下方案标注哪些是电影确认、哪些是原创补充。

---

## 一、住宅空间规划

### 客厅/餐厅（主空间）[FILM|HIGH|CONFIRMED 存在]

**用途**：聚会主场景、8 人餐桌、大部分剧情发生
**连接**：↔ 厨房（开放式）↔ 走廊 ↔ 前门 ↔ 后院
**家具**：
- 长餐桌（8 人位）+ 椅子 8 把 [FILM|HIGH|CONFIRMED]
- 沙发 [FILM|HIGH|CONFIRMED]
- 茶几 [INFERENCE|MEDIUM]
- 壁炉 [INFERENCE|MEDIUM]
- 地毯 [INFERENCE|MEDIUM]
- 酒柜/餐边柜 [DESIGN|PENDING_USER]

**剧情道具**：盒子、照片、骰子、荧光棒、蜡烛、杯子
**NPC 活动**：晚餐、讨论、争论、验证盒创建
**现实差异**：餐桌布置、灯光氛围、个别家具位置 [DESIGN|PENDING_USER]

### 厨房 [FILM|HIGH|CONFIRMED 存在]

**用途**：备餐、Beth 的草药、部分对话
**连接**：↔ 客厅/餐厅
**家具**：操作台、冰箱、水槽、吊柜 [INFERENCE|MEDIUM]
**道具**：杯子、盘子、瓶子、烤箱手套 [FILM|HIGH|CONFIRMED]

### 走廊 [FILM|HIGH|CONFIRMED 存在]

**用途**：连接房间、Laurie 和 Kevin 的私密对话、Beth 目击
**连接**：↔ 客厅 ↔ 卧室 ↔ 浴室
**注意**：走廊是重要的信息差场景——Beth 从走廊看到客厅

### 浴室 [FILM|HIGH|CONFIRMED 存在]

**用途**：Em 最终制服另一个自己的地点
**连接**：↔ 走廊
**家具**：浴缸、洗手台 [INFERENCE|MEDIUM]

### 书房/办公区 [FILM|HIGH|CONFIRMED 存在]

**用途**：Hugh 查物理书、部分讨论
**连接**：↔ 走廊或客厅
**家具**：书桌、书架、笔记本电脑 [INFERENCE|MEDIUM]
**道具**：物理书（Gravitation）[FILM|HIGH|CONFIRMED]

### 前门 [FILM|HIGH|CONFIRMED]

**用途**：主要出入口、便条钉在门上
**设计**：需要真实门体+门框+铰链动画 [DESIGN|PENDING_USER]
**通过**：按 E 开门→走出去（不是点击热点传送）

### 侧门 [FILM|HIGH|CONFIRMED]

**用途**：Hugh 和 Amir 外出的门
**连接**：↔ 侧院/车道

### 露台/后院 [FILM|HIGH|CONFIRMED]

**用途**：看彗星、Em 的车、最终冲突
**连接**：↔ 客厅
**室外**：车道、Em 的车

---

## 二、家具摆放规范

| 规范 | 要求 | 当前状态 |
|---|---|---|
| 椅子与桌子 | 每把椅子对应桌面一个座位 | ❌ 不对应 |
| 门在墙开口 | 门框必须与门洞对齐 | ❌ 有错位 |
| 门开合方向 | 向内开，不挡通道 | ❌ 无动画 |
| 家具碰撞 | 视觉=碰撞，不穿模 | ❌ 有偏差 |
| 通行宽度 | 主通道 ≥ 0.8m | ✅ |
| 桌面高度 | 餐桌 0.75m、茶几 0.4m | ❌ 不精确 |

## 三、室外空间

- 房屋外立面（与内部空间对应）[DESIGN]
- 门廊（前门外）[FILM|HIGH|CONFIRMED]
- 车道 + Em 的车 [FILM|HIGH|CONFIRMED]
- 街道（柏油路面、路缘）[DESIGN]
- 邻近住宅（至少 3 栋可见）[DESIGN]
- 远处亮灯的房子 [FILM|HIGH|CONFIRMED]
- 路灯（不工作——停电）[FILM|HIGH|CONFIRMED]
- 黑暗区域（房屋之间的浓密黑暗）[FILM|HIGH|CONFIRMED]

## 四、空间连续性

| 检查项 | 要求 | 实现方式 |
|---|---|---|
| 室内→室外 | 走过门洞自然过渡 | AutoPortal 无缝切换 |
| 街道→黑暗区域 | 渐变过渡 | 体积雾+光照衰减 |
| 穿越黑暗→另一现实 | 环境渐变 | 光照+音效+变体切换 |
| 玩家状态保持 | 坐标/朝向/速度连续 | WorldManager 已验证 |
