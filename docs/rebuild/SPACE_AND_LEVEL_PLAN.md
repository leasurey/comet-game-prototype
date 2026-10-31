# 空间与关卡重建方案

> **三类标注**：
> - `FILM_CONFIRMED`：电影画面/对白明确支持
> - `INFERENCE`：资料推断，允许修正
> - `GAME_LAYOUT`：为可玩性/连续性的原创设计

---

## 一、住宅空间连接方案（GAME_LAYOUT）

电影展示了住宅的多个房间，但**完整布局未确认**。以下为游戏空间方案：

```
         [后院/露台]
              |
   [书房]—[走廊]—[浴室]
     |       |       |
   [客厅/餐厅]———[厨房]
              |
          [前门]
              |
         [门廊]——[车道]
              |
          [街道]——[黑暗区域]——[亮灯房]
```

### 房间连接与通行

| 房间 | 门/出口 | 通向 | 电影依据 |
|---|---|---|---|
| 客厅/餐厅 | 前门 | 门廊 | FILM_CONFIRMED（前门存在）|
| 客厅/餐厅 | 后门（推拉） | 后院/露台 | FILM_CONFIRMED |
| 客厅/餐厅 | 侧门 | 侧院/车道 | FILM_CONFIRMED |
| 客厅/餐厅 | 开放式 | 厨房 | INFERENCE（开放连接为游戏设计）|
| 客厅/餐厅 | 门洞 | 走廊 | INFERENCE |
| 走廊 | 门 ×2 | 浴室/书房 | INFERENCE |
| 厨房 | 无独立出口 | — | INFERENCE |

**GAME_LAYOUT 标注**：
- 厨房与客厅的开放式连接 [GAME_LAYOUT]
- 走廊宽度 1.2m [GAME_LAYOUT]
- 书房位置（走廊尽头）[GAME_LAYOUT]
- 浴室位置（走廊旁）[GAME_LAYOUT]

## 二、房间详细设计

### 客厅/餐厅 [FILM_CONFIRMED 存在]

**家具** [混合标注]：
| 家具 | 标注 | 说明 |
|---|---|---|
| 长餐桌（8 人位） | FILM_CONFIRMED | 电影明确展示 |
| 椅子 8 把 | FILM_CONFIRMED | 对应 8 人 |
| 沙发 | FILM_CONFIRMED | 电影展示 |
| 壁炉 | INFERENCE | 对白提及 |
| 地毯 | INFERENCE | 视觉推断 |
| 茶几 | INFERENCE | 常见搭配 |
| 酒柜 | GAME_LAYOUT | 游戏补充 |

**通行路线** [GAME_LAYOUT]：
- 主通道：前门→餐桌→厨房（宽 1.2m）
- 副通道：餐桌→走廊（宽 0.9m）
- 椅子间距：0.5m（可拉开坐下）

### 厨房 [FILM_CONFIRMED 存在]

**连接**：开放式连客厅 [GAME_LAYOUT]
**家具** [INFERENCE]：操作台、冰箱、水槽、吊柜
**道具** [FILM_CONFIRMED]：杯子、盘子、烤箱手套

### 走廊 [FILM_CONFIRMED 存在]

**功能**：连接客厅→浴室/书房；Beth 目击场景
**宽度**：1.2m [GAME_LAYOUT]
**门**：浴室门 + 书房门 [INFERENCE]

### 浴室 [FILM_CONFIRMED 存在]

**功能**：Em 最终冲突场景
**家具** [INFERENCE]：浴缸、洗手台
**门**：向内开 [GAME_LAYOUT]

### 书房 [FILM_CONFIRMED 存在]

**功能**：Hugh 查物理书
**家具** [INFERENCE]：书桌、书架、笔记本电脑
**道具** [FILM_CONFIRMED]：物理书

## 三、家具摆放与通行规范

| 规范 | 要求 | 标注 |
|---|---|---|
| 椅子↔桌面 | 每椅对一个座位，间距 0.5m | GAME_LAYOUT |
| 门在墙开口 | 门框中心=门洞中心 | GAME_LAYOUT |
| 门开合 | 向内开，不挡主通道 | GAME_LAYOUT |
| 碰撞=视觉 | CollisionShape=Mesh 尺寸 | GAME_LAYOUT |
| 主通道 ≥ 0.8m | 确保玩家通行 | GAME_LAYOUT |
| 餐桌高 0.75m | 标准人体工学 | GAME_LAYOUT |

## 四、室外连续路线（GAME_LAYOUT）

```
室内(前门) → 门廊(2m) → 车道(3m) → 街道(6m宽) → 邻居住宅
                                  ↓
                           黑暗区域(浓密黑暗)
                                  ↓
                          另一现实的亮灯房
```

**标注**：
- 房屋间距离 [INFERENCE]（从画面估算）
- 黑暗区域范围 [GAME_LAYOUT]（游戏设计）
- 邻居住宅位置 [GAME_LAYOUT]

## 五、现实差异设计

| 差异类型 | α 现实 | β 现实 | γ 现实 | 标注 |
|---|---|---|---|---|
| 灯光色温 | 暖黄 | 偏冷 | 更暗 | GAME_LAYOUT |
| 餐桌布置 | 整齐 | 有些乱 | 更乱 | GAME_LAYOUT |
| 家具位置 | 标准 | 沙发偏移 | 椅子歪 | GAME_LAYOUT |
| 道具状态 | 杯子完整 | 杯子碎了 | 多了物品 | GAME_LAYOUT |
| 窗外光 | 正常 | 偏绿 | 偏红 | GAME_LAYOUT |
| 空间细节 | 无异常 | 照片内容变 | 物品位置变 | GAME_LAYOUT |
| NPC 状态 | 正常 | 紧张 | 恐惧 | GAME_LAYOUT |

**注意** [INFERENCE]：电影展示了现实差异，但具体差异内容为游戏设计。
