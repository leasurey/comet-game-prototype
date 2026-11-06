# 彗星来的那一夜 · 资料归档

《彗星来的那一夜》（*Coherence*, 2013）的电影考据与叙事设计资料归档。

**游戏制作已终止。** 本仓库不再作为游戏项目维护，只保留研究资料与历史版本分支。

> 仓库根目录附 `index.html` —— 用浏览器直接打开可看资料索引页（卡片式导航，本地与线上均可读）。

---

## 资料

### `docs/film/` — 电影考据

对原片的逐条考据，每条结论标注证据等级（`FILM` / `INTERVIEW` / `INFERENCE`）。这是全部资料中证据标准最高的一套。

| 文件 | 内容 |
|---|---|
| [FILM_BIBLE.md](docs/film/FILM_BIBLE.md) | 电影圣经：全片事实总纲 |
| [FILM_TIMELINE.md](docs/film/FILM_TIMELINE.md) | 逐场时间线（T 编号事件） |
| [FILM_LOCATIONS.md](docs/film/FILM_LOCATIONS.md) | 场景与空间考据 |
| [CHARACTERS.md](docs/film/CHARACTERS.md) | 人物考据（含演员、关系、行为特征） |
| [RELATIONSHIPS.md](docs/film/RELATIONSHIPS.md) | 人物关系网络 |
| [REALITY_RULES.md](docs/film/REALITY_RULES.md) | 现实规则 A1–A6：渗透、穿越黑暗、多层现实、替换、物理标记、同一事件多版本 |
| [REALITY_BRANCHES.md](docs/film/REALITY_BRANCHES.md) | 分支现实推演 |
| [PROPS_AND_CLUES.md](docs/film/PROPS_AND_CLUES.md) | 道具与线索（便签、宝丽来、荧光棒、戒指、盒子、骰子） |
| [NARRATIVE_ANALYSIS.md](docs/film/NARRATIVE_ANALYSIS.md) | 叙事结构分析 |
| [SOURCE_EVIDENCE_MAP.md](docs/film/SOURCE_EVIDENCE_MAP.md) | 证据来源映射 |
| [EVIDENCE_FRAMEWORK.md](docs/film/EVIDENCE_FRAMEWORK.md) | 证据分级框架 |
| [CONSISTENCY_REPORT.md](docs/film/CONSISTENCY_REPORT.md) | 内部一致性审查 |
| [CROSS_RESEARCH_REVIEW.md](docs/film/CROSS_RESEARCH_REVIEW.md) | 交叉研究复核 |
| [COMET_ADAPTATION.md](docs/film/COMET_ADAPTATION.md) | 改编可行性评估 |
| [OPEN_QUESTIONS.md](docs/film/OPEN_QUESTIONS.md) | 未决问题清单 |
| [REVISION_LOG.md](docs/film/REVISION_LOG.md) | 考据修订记录 |
| [FACT_CHECK.md](docs/film/FACT_CHECK.md) | **改编设计的事实核对表**：41 条逐条标注【电影】14 /【延展】16 /【新增】11，含出处节号 |
| [research/](docs/film/research) | 原始研究包与来源登记 |

### `docs/narrative/` — 叙事资料

| 文件 | 内容 |
|---|---|
| [README.md](docs/narrative/README.md) | 本目录导引 |
| [FILM_TIMELINE_AND_FACTS.md](docs/narrative/FILM_TIMELINE_AND_FACTS.md) | 时间线与事实摘要 |
| [CHARACTERS_AND_KNOWLEDGE.md](docs/narrative/CHARACTERS_AND_KNOWLEDGE.md) | 人物与各人掌握的信息差 |
| [NARRATIVE_EVENT_CATALOG.md](docs/narrative/NARRATIVE_EVENT_CATALOG.md) | 叙事事件目录（E 编号） |
| [SCENE_AND_SPACE_ATLAS.md](docs/narrative/SCENE_AND_SPACE_ATLAS.md) | 场景与空间图集 |
| [GAME_ADAPTATION_RULES.md](docs/narrative/GAME_ADAPTATION_RULES.md) | 改编规则（哪些设定不可动） |
| [OPEN_QUESTIONS.md](docs/narrative/OPEN_QUESTIONS.md) | 未决问题 |
| [CHAPTER_OUTLINE.md](docs/narrative/CHAPTER_OUTLINE.md) | 曾经的七章叙事结构大纲（留存） |

### `docs/legacy/` — 制作遗留

游戏开发阶段的全部代码、工程文档与设计文档，原样留存、不再维护。

**这些文件搬离了原位置，Godot 工程已不能直接运行。** 如需可运行的历史版本，请切换到对应分支（见下）。

---

## 历史分支

| 分支 | 说明 |
|---|---|
| [`recovery/visual-rebuild`](../../tree/recovery/visual-rebuild) | **3D 第一人称版本**：完整可运行的 Godot 工程（v0.6.0），含当时全部考据与设计文档。这是最后一个可玩版本。 |
| [`recovery/master-rebuild`](../../tree/recovery/master-rebuild) | 重建主线历史 |
| [`recovery/continuity-integration`](../../tree/recovery/continuity-integration) | 连贯性整合阶段 |
| [`docs/narrative-design-v1`](../../tree/docs/narrative-design-v1) | 叙事设计的独立留档 |

## 说明

- 影片版权归原作者所有。本仓库只包含文字考据、分析笔记与设计文档，不含影片素材。
- 考据结论按证据等级标注；`INFERENCE` 级别的内容属于推演，不应作为事实引用。
- 归档后不再接受功能性更新。
