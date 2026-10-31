# COMET 游戏重建蓝图

## 文档结构与阅读顺序

```
REBUILD_BLUEPRINT.md          ← 总蓝图（先读这个）
├── SPACE_AND_LEVEL_PLAN.md   ← 空间与关卡
├── CHARACTER_AND_NPC_PLAN.md ← 人物与 NPC
├── REALITY_SYSTEM_PLAN.md    ← 多重现实系统
├── NARRATIVE_INTEGRATION_PLAN.md ← 剧情衔接
├── ART_AND_PERFORMANCE_GUIDELINES.md ← 美术与性能
└── REBUILD_ASSET_INVENTORY.md ← 资源清单
```

## 阅读建议

1. 先读 `REBUILD_BLUEPRINT.md`——了解全貌、现有系统分类、阶段计划
2. 根据你关心的领域读对应文档
3. 所有"待用户确认"标记的问题需要你做创作决定
4. 电影事实 [FILM] / 研究推断 [INFERENCE] / 原创建议 [DESIGN] 严格区分

## 核心原则

**COMET 是《Coherence》的互动改编。** 所有设计从原作出发。
现有工程是技术积累，不是最终视觉设计的限制。
用户尚未确认蓝图之前，不开始实际重建。


---

## 重构版设计文档（本轮新增）

| 文档 | 内容 |
|---|---|
| WORLD_MAP_DESIGN.md | 地图布局、房间关系、通行路线 |
| CHARACTER_DESIGN.md | 人物设定、认知四账本、关系动态 |
| DIALOGUE_DESIGN.md | 对话数据协议、语言风格、分支条件 |
| STORY_DESIGN.md | 11 个事件结构、信息差、锚点 |
| OPENING_DESIGN.md | 序章 P0-P3 流程 |
| TECHNICAL_PLAN.md | 系统审计、保留/重写清单、接口变更 |
| ART_ASSET_PIPELINE.md | Blender→Godot 管线（**Blender 未安装，为方案**） |
| ART_ASSET_REGISTER.md | 资源授权登记（**暂无外部资源**） |

### 阅读顺序

1. TECHNICAL_PLAN.md — 先看审计结论和已修问题
2. WORLD_MAP_DESIGN.md — 空间
3. CHARACTER_DESIGN.md / DIALOGUE_DESIGN.md — 人物与对话
4. STORY_DESIGN.md / OPENING_DESIGN.md — 剧情与序章
5. ART_ASSET_*.md — 美术管线（了解现状限制）


---

## 美术管线（已执行，非计划）

- `ART_ASSET_PIPELINE.md`：Blender → Godot 实际流程、踩坑记录、模型真实完成度
- `ART_ASSET_REGISTER.md`：资源授权登记（当前无第三方 3D 资产；音频来源待核）
- `../art/README.md`：角色检查图与游戏内截图说明
