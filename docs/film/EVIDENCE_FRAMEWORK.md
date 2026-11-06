# 证据标注体系（统一三维框架）

## EVIDENCE_FRAMEWORK.md

> **2026-11-01 确立**。替代此前混用的 [A]/[A2]/[C+]/[F-D]/[F-T]/[U] 等标签。
> 每条重要结论使用格式：`结论 | 来源类型 | 证据强度 | 确认状态 | 来源定位 | 限制`

---

## 一、三维标注定义

### 维度 1：来源类型（Source Type）

| 标签 | 含义 | 说明 |
|---|---|---|
| FILM | 电影画面或对白直接呈现 | 最强来源 |
| INTERVIEW | 导演/编剧/演员访谈 | 创作意图，非电影规则 |
| TRANSCRIPT | 公开对白转录 | 可证台词，不可证画面 |
| SECONDARY | 影评/剧情解析/影迷分析 | 仅作参考 |
| INFERENCE | 研究者推断 | 非事实 |
| DESIGN | COMET 原创设计建议 | 待用户确认 |

### 维度 2：证据强度（Evidence Strength）

| 标签 | 含义 |
|---|---|
| HIGH | 有直接、明确且可定位的来源支持 |
| MEDIUM | 有间接支持，但存在解释空间 |
| LOW | 主要依赖推断或不完整材料 |
| NONE | 目前没有足够证据 |

### 维度 3：确认状态（Confirmation Status）

| 标签 | 含义 |
|---|---|
| CONFIRMED | 来源直接支持该结论 |
| PARTIAL | 只能支持其中一部分 |
| DISPUTED | 存在相互冲突的材料 |
| UNVERIFIED | 尚未核实 |
| HYPOTHESIS | 研究假设，不是事实 |

---

## 二、使用规则

1. **来源类型 ≠ 证据强度**。FILM 来源可能是 HIGH 也可能是 PARTIAL。
2. **INTERVIEW 不等于 FILM**。导演的创作意图≠电影世界的客观规则。
3. **TRANSCRIPT 不可证画面**。对白文本不能证明动作、表情、空间布局。
4. **SECONDARY 不可作独立证据**。多篇转载同一访谈≠多个独立来源。
5. **INFERENCE 必须标记**。研究者的推断不能写成事实。
6. **DESIGN 一律待用户确认**。研究者不能替用户决定原创设计。

---

## 三、旧标签 → 新体系映射（仅参考，不自动转换）

| 旧标签 | 大致对应 | 注意 |
|---|---|---|
| [A] | FILM + HIGH + CONFIRMED | 但需检查是否真的有画面/对白证据 |
| [A2] | FILM/INTERVIEW + HIGH + CONFIRMED | 来源群一致≠独立验证 |
| [B] | INTERVIEW + MEDIUM + CONFIRMED | 创作意图 |
| [C] | INFERENCE + LOW + HYPOTHESIS | |
| [C+] | INFERENCE + MEDIUM + PARTIAL | |
| [F-D] | INTERVIEW + HIGH + CONFIRMED | |
| [F-T] | TRANSCRIPT + HIGH + CONFIRMED | |
| [F-P] | SECONDARY + MEDIUM + PARTIAL | |
| [U] | * + NONE + UNVERIFIED | |
| [D] | DESIGN + N/A + N/A | 待用户确认 |

**注意**：旧标签不可机械映射。每条结论需重新核实后再用新标注。
