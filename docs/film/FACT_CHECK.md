# 《聚会之前》文字版 · 电影事实核对表与 E3 分支审查

> 任务 N4 · design-strategist · 核对对象：`design/novel/NOVEL_CONCEPT.md`（N1）。
> 合法"电影事实"出处经本次核实共 4 处：`docs/film/`（FILM_LOCATIONS / FILM_TIMELINE / PROPS_AND_CLUES / REALITY_RULES / CHARACTERS）、`docs/rebuild/STORY_DESIGN.md` E01–E11、`docs/rebuild/MIRROR_HOUSE_DESIGN.md`（仅其内部标 FILM_CONFIRMED 的条目）、`docs/rebuild/REALITY_SYSTEM_PLAN.md` §一（A1–A5）。
> ⚠️ **前提纠正**：`FILM_LOCATIONS.md / REALITY_RULES.md / PROPS_AND_CLUES.md` **并非不存在**——它们在 `docs/film/` 下，novel-edition 分支在库（见 §三）。N1 附录第 1 条结论作废。

## 0. 来源等级定义

- **【电影】**：与文档明确标注电影事实的条目直接对应（写明出处）。
- **【延展】**：由电影事实或既有设计合理推导（写明依据链条）。
- **【新增】**：N1 原创设计，无电影依据（写明叙事功能）。

## 一、逐章核对表（41 条）

### 序章 · 玄关（5 条）

| # | N1 内容 | 等级 | 出处 / 依据 |
|---|---|---|---|
| S1 | 玄关抵达、聚会开场 | 【电影】 | STORY_DESIGN E02；FILM_TIMELINE T02；OPENING_DESIGN P0 |
| S2 | 与 Kevin 交谈 | 【电影】 | STORY_DESIGN E02（场景存在）；"Kevin 主动招呼"为 OPENING_DESIGN P1 既有设计 |
| S3 | 八副餐具的餐桌 | 【电影】 | FILM_LOCATIONS「主场景：餐桌 8 人位」[FILM\|HIGH\|CONFIRMED]；T02/S2 |
| S4 | 停电 + 手机碎裂 + 碎杯子 | 【电影】 | STORY_DESIGN E04；FILM_TIMELINE T04/T05 |
| S5 | 章末"对面那栋还亮着" | 【电影】 | FILM_LOCATIONS「远处亮灯的房子」；MIRROR_HOUSE L3-1/R2（FILM_CONFIRMED） |

> ⚠️ **遗漏项**：E01 车内对话（STORY_DESIGN E01【电影事实】）未纳入序章。需用户拍板：补写或明确舍弃。

### 第 1 章（6 条）

| # | N1 内容 | 等级 | 出处 / 依据 |
|---|---|---|---|
| C1-1 | Mike 最先发现对面亮灯 | 【新增】 | 电影中是 Hugh/Amir 决定外出（T06）；characters.json 的说法非电影事实。功能：给玩家勘察选择入口 |
| C1-2 | 勘察主屋基准项（便签"4"、钟 7:05） | 【延展】 | 由 A3 便条规则（REALITY_RULES）+ MIRROR L3-4/L1-6 的设计值延展；具体数字 4/7:05 为 MIRROR 既有设计（GAME_LAYOUT），非电影画面 |
| C1-3 | L1/L2 五项差异转为观察条目 | 【延展】 | MIRROR L1-1/L1-2/L1-5/L2-1/L2-3（均为 GAME_LAYOUT 既有设计，非电影事实）；"对面住着同一群人"的氛围由电影"另一栋房"延展 |
| C1-4 | 过街勘察 vs 留守的选择结构 | 【电影】 | STORY_DESIGN E05【电影事实】"玩家行为：可选择是否跟随" |
| C1-5 | 离开期间 Kevin-Laurie 接触、只能听转述 | 【延展】 | T13（Beth 目睹走廊亲吻）[FILM]；"玩家缺席→转述"由 E05 信息差列推导；Hugh 的具体台词为 N1 加工 |
| C1-6 | 章末盒子回来 | 【电影】 | STORY_DESIGN E05/E06；FILM_TIMELINE T07 |

### 第 2 章（5 条）

| # | N1 内容 | 等级 | 出处 / 依据 |
|---|---|---|---|
| C2-1 | 盒子验物（球拍、照片、数字） | 【电影】 | STORY_DESIGN E06；T07；PROPS_AND_CLUES #2/#3 |
| C2-2 | 7:12 vs 7:05 →"对面不是跟着我们走的" | 【延展】 | MIRROR L1-6（GAME_LAYOUT）；钟面数字差异无电影画面依据，"对面独立运行"的判断由电影对照逻辑延展 |
| C2-3 | 跟随 Hugh 走黑暗路段 → 进入 beta | 【电影】 | E05（跟随选择）+ REALITY_RULES A2（穿越黑暗=换现实）；β 层本身为 STORY_DESIGN §四明确标注的【游戏原创设计】 |
| C2-4 | 转述错漏 `fact_wrong_darkness`（玩家不知是错的） | 【新增】 | 功能：落实支柱 3"每条分支关闭一条信息路径" |
| C2-5 | 章末红色荧光棒 | 【电影】 | STORY_DESIGN E08；FILM_TIMELINE T09（红荧光棒属"另一组"） |

### 第 3 章（6 条）

| # | N1 内容 | 等级 | 出处 / 依据 |
|---|---|---|---|
| C3-1 | 骰子、随机物品、数字的验证盒 | 【电影】 | STORY_DESIGN E09；FILM_TIMELINE T15；PROPS #9 |
| C3-2 | Mike-Beth 秘密暴露、站边/调解/回避 | 【电影】 | STORY_DESIGN E10；T16 |
| C3-3 | 8 张宝丽来之一被"我们这栋"找到、背面写 5 | 【新增】⚠ | **无依据且与 L3-3 冲突**：既有文档中 8 张宝丽来只挂在**对面**壁炉（L3-3，二级观察"数字不是我们的笔迹"）。我方群体的自证物是验证盒（T15），不是壁炉宝丽来 |
| C3-4 | 3-3 把宝丽来 5 号交给 Kevin 保管 | 【新增】⚠ | 未经任何文档支撑，动机链不成立（详见 §二） |
| C3-5 | 3-4 自留宝丽来、解锁"对比笔迹" | 【新增】 | 功能：与 3-3 构成互斥信任取舍；"笔迹"概念延展自 FarPolaroids 二级观察 |
| C3-6 | 章末"这栋房子也在做标记，比我们仔细" | 【延展】 | REALITY_RULES A5（编号照片=群体标记）[FILM] + L3-3 暗示列 |

### 第 4 章（5 条）

| # | N1 内容 | 等级 | 出处 / 依据 |
|---|---|---|---|
| C4-1 | gamma 冷光 + 蜡烛同亮 | 【延展】 | MIRROR §3.1 gamma 行（GAME_LAYOUT）；"更极端现实"由 A2/A3 延展 |
| C4-2 | 对面西翼三盏灯全亮 | 【延展】 | MIRROR §4.3 `FarHallLamp/FarBedLamp/FarBathLamp`（vc 专属，既有设计） |
| C4-3 | Beth 灵性直觉意外地准 | 【电影】 | docs/film/CHARACTERS.md §Beth"有些直觉敏锐但表达混乱"[FILM\|HIGH\|CONFIRMED]；"准确性取决于第 3 章信任值"为【新增】 |
| C4-4 | 书房书架钉眼、"没人查过书" | 【延展】 | MIRROR L3-2（GAME_LAYOUT）；"书房=Hugh 查书处"为电影事实（FILM_LOCATIONS）；钉眼为设计 |
| C4-5 | 章末便签 7 vs 门上 4 | 【延展】 | A3 便条重复 [FILM]；具体数字 4/7 为 L3-4 设计值 |

### 第 5 章（4 条）

| # | N1 内容 | 等级 | 出处 / 依据 |
|---|---|---|---|
| C5-1 | A3 便条重复成为主谜题 | 【电影】 | STORY_DESIGN E07；REALITY_RULES A3 [FILM\|HIGH\|CONFIRMED] |
| C5-2 | 数字递增→"有人在按顺序来" | 【延展】 | 由 A3+L3-4（4/7 两个数据点）推导；"递增/顺序"是 N1 的推断性加工，电影只确认"数字不是随机的"（L3-4 暗示列） |
| C5-3 | 指认替身玩法（可指错） | 【延展】 | A4 人物可能被替换 [FILM] + E10 信任崩溃；指认的具体玩法属 STORY_DESIGN §三"可改变"范围 |
| C5-4 | 先指认自己 / 只记录不指认 | 【新增】 | 功能：把 A4 从"NPC 可能被换"翻转为"玩家自证"与"旁观者"两条正交路径 |

### 第 6 章与结局矩阵（6 条）

| # | N1 内容 | 等级 | 出处 / 依据 |
|---|---|---|---|
| C6-1 | 留下 / 穿越找原版 / 交换位置三向终选 | 【延展】 | STORY_DESIGN E11【电影事实】骨架 + "不预设替换/共存/离开"【游戏原创设计】 |
| C6-2 | E1 留下来的人（真·团结） | 【新增】 | 电影无对应结局；功能：高信任+高证据的正反馈出口 |
| C6-3 | E2 第八张照片（去对面） | 【延展】 | T18/T19（Em 探索其他房子、找到"更好"版本）[FILM]；"九副餐具"延展自 L2-3 |
| C6-4 | E3 第七分钟（surrendered_marker 坏结局） | 【新增】⚠ | 触发机制无依据（§二专项审查）；终幕"7:12"意象延展自 L1-6；"被换掉而不自知"主题延展自 A4 |
| C6-5 | E4 黑暗里的门（循环） | 【延展】 | A2（黑暗穿越）+ C1（现实可能无限）+ T09（双方各自逃回）；"相同句式自曝循环"的手法为【新增】 |
| C6-6 | E5 Laurie 的房子（隐藏结局） | 【新增】⚠ | 无任何文档依据：既有设定中 Laurie 不是任何一栋房子的主人；对面房子拓扑=主屋（MIRROR 前置决策），"她的房子"与之一致性未解释 |

### 人物关系系统（4 条）

| # | N1 内容 | 等级 | 出处 / 依据 |
|---|---|---|---|
| P1 | trust 初值（Laurie −1、Hugh +1） | 【延展】 | CHARACTER_AND_NPC_PLAN §二/§三关系设定（Em-Laurie 竞争、Hugh 理性核心） |
| P2 | 信任阈值机制（±2 密谈 / ≤−2 拒绝 / =−3 一票否决） | 【新增】 | 功能：把"社交许可"与 facts 闸门解耦 |
| P3 | `min_trust` 数据协议字段 | 【新增】 | 需工程评估（N1 附录第 3 条已声明） |
| P4 | `markers_seen` 标记物集合 | 【延展】 | 便签/宝丽来/荧光棒/钟/戒指均为 REALITY_RULES A5 + PROPS 确认的标记类道具 |

## 二、E3「交出宝丽来」专项审查

**1. 宝丽来的既定归属**：电影事实中编号照片只以两种形态存在——① Hugh/Amir 从**对面亮灯房**带回的盒子里的编号照片（STORY_DESIGN E06 / T07 / PROPS #3"不同现实的数字不同"）；② **对面**壁炉上的一排 8 张（MIRROR L3-3，二级观察明确"数字不是我们的笔迹"）。玩家在全部既有文档中**从未获得过任何一张宝丽来**；我方群体的自证物是 T15 的验证盒（骰子+随机物品）。N1 第 3 章"我们这栋找到一张"在归属上悬空。

**2. Kevin 的既定设定**：docs/film/CHARACTERS.md §Kevin [FILM|HIGH|CONFIRMED]——Em 男友、即将赴越南出差、温和善良但迟钝、对 Laurie 暧昧回应不果断、混乱中"试图维持秩序但效果有限"、是"被选择的对象而非主动行动者"。CHARACTER_AND_NPC_PLAN §三一致（Em 男友、Laurie 前任、压力下调和/茫然）。characters.json 的"男主人/房子主人、Beth 是 Kevin 妻子、Lee 是朋友"**全部错误**——正确：房子是 Mike 和 Lee 的（T02、FILM_LOCATIONS 主场景），Beth 是 Hugh 妻子，Lee 是 Mike 妻子。

**3. 动机链是否成立：不成立**。① 归属悬空（见上）；② Kevin 收下无动机——他的压力反应是"调和与茫然"，主动保管"层数物证"并锁进书房抽屉是电影/设定中从未有过的主动决断（书房还是 Hugh 查书的地方，归属感也错位）；③ 证据逻辑自相矛盾——若那真是"我们层数"的物证，它应像我方标记一样成套存在，单张被"找到"更像对面的东西；且交进抽屉随时可取回，并不构成"销毁自证"，E3"验证环节差一块"的因果断裂。

**替代方案**：
- **方案 A（推荐）· 换成戒指**：3-3 改为"把戒指交给 Kevin 以证信任"。依据：PROPS #6 戒指=Em-Kevin 关系象征 [FILM|HIGH|CONFIRMED]；PROPS 导演访谈"手机、戒指、照片、花瓶是人物抓住的身份凭据" [INTERVIEW|HIGH|CONFIRMED]；T20/T22 中另一 Em 的身份正是靠戒指被识别/顶替。情感动机链最短（男友收信物天经地义），"交出身份凭据"字面成立；E3 终幕可写"Kevin 手上戴着你的戒指"。
- **方案 B · 交出我方验证盒/名单便签**：依据 T15（我方自建验证盒）+ Kevin"试图维持秩序"——由 Kevin 提议"自证物集中保管，防被替换者利用"，玩家响应。动机链硬，但需先铺垫"我方验证盒"设定（可挂第 1 章 1-3 写名单作伏笔）。

**4. 最终建议**：换触发器物件为戒指（方案 A）；宝丽来降级为纯观察线索（`markers_seen`），不再承担 `surrendered_marker`。原设计不保留。

## 三、悬空引用清单（只列不改）

**前提纠正**：N1 附录第 1 条称 `FILM_LOCATIONS.md / REALITY_RULES.md / PROPS_AND_CLUES.md` 在任何分支不存在——**错误**。三者均在 `docs/film/` 下（novel-edition 分支，commit af39fa2 起在库）。MIRROR_HOUSE L3-3 引 `REALITY_RULES.md` A5 是**有效引用**（docs/film/REALITY_RULES.md §A5 确为 [FILM|HIGH|CONFIRMED]），任务书中"实际内容应在 REALITY_SYSTEM_PLAN.md"不成立；REALITY_RULES.md 内容更全（A1–A6）。

| # | 引用位置 | 悬空目标 | 状态与正确指向 |
|---|---|---|---|
| 1 | docs/continuity/CONTINUITY_RECOVERY_PLAN.md:201 | `CONTINUITY_FINAL_REPORT.md` | 计划产出未建（任务十四报告），需补建或删引用 |
| 2 | docs/MASTER_RECOVERY_PLAN.md:132 | `docs/GEOMETRY_RECHECK.md` | 计划产出未建 |
| 3 | docs/novel/TECH_AUDIT.md:75 | `data/story/chapter_XX.json` | 文字版数据文件规划位，未建（N1 落地时按此建） |
| 4 | docs/MASTER_RECOVERY_PLAN.md:244 | `data/npcs.json` | 规划未建；现状数据在 `data/characters.json`（且其 Kevin/Beth/Lee 设定错误，见 §二.2） |
| 5 | docs/continuity/CONTINUITY_AUDIT.md:165 | `settings.json` | 标注"✅"但仓库无此文件；若指 user:// 运行时文件应写明路径，否则视为悬空 |

**澄清（非悬空）**：`comet_save.json` 为 `user://` 运行时存档（docs/ARCHITECTURE.md:217 写明），非仓库文件。**N1 自身需更正**：NOVEL_CONCEPT.md 头部引用行与附录第 1 条关于"三文件不存在"的表述作废，应改为指向 `docs/film/`。

**附带发现的命名冲突**：N1 结局编号 E1–E5 与项目既有事件编号 E01–E11（STORY_DESIGN）撞车，落地数据/代码前应改为 Ending-1…Ending-5 之类的前缀。
