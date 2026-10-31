# 现实分支与人物移动追踪

> **证据标注说明**：本文档中旧标签（[FILM|HIGH|CONFIRMED]/[INTERVIEW|MEDIUM|CONFIRMED]/[INFERENCE|LOW|HYPOTHESIS] 等）为历史版本遗留。
> 三维证据体系见 [EVIDENCE_FRAMEWORK.md](EVIDENCE_FRAMEWORK.md)。争议结论已用三维标签更新（见 OPEN_QUESTIONS.md）。
> 旧标签不可机械映射——使用时请根据来源类型和证据强度自行判断。


> **注意**：电影未给出完整的现实编号系统。以下追踪基于人物对话和物理标记的推断。
> 不要为了给每个现实分配确定编号而强行归类。

---

> **⚠️ 第二轮修订（2026-11-01）**：Emily 的归属分析是**人物推断**，不是客观事实。
> 电影从未确认各人物的真实归属。以下"Emily 的推断"段落必须保留为"C 级推断"。
> 支持证据：Emily 创建了验证盒并做了分析。反对/不确定证据：验证盒本身可能不准确，Emily 的分析基于她当时的认知。

## 人物移动追踪

### 初始群体（蓝色荧光棒）→ 聚会开始 [FILM|HIGH|CONFIRMED]

| 人物 | 起始 | 第一次外出 | 返回后 | 最终归属 |
|---|---|---|---|---|
| **Em** | 房子 A | 是（4 人组） | 被替换的 Kevin 在场 | 最终离开，去了"完美"房子 [FILM|HIGH|CONFIRMED] |
| **Kevin** | 房子 A | 是（4 人组） | **来自不同现实** [FILM|HIGH|CONFIRMED] | 不确定 [INFERENCE|LOW|HYPOTHESIS] |
| **Mike** | 房子 A | 是（单独外出勒索） | **来自第四栋房子** [FILM|HIGH|CONFIRMED] | 不确定 [INFERENCE|LOW|HYPOTHESIS] |
| **Lee** | 房子 A | **从未外出** [FILM|HIGH|CONFIRMED] | **属于房子 A** [FILM|HIGH|CONFIRMED] | 留在房子 A [FILM|HIGH|CONFIRMED] |
| **Beth** | 房子 A | **从未外出** [FILM|HIGH|CONFIRMED] | **属于房子 A** [FILM|HIGH|CONFIRMED] | 留在房子 A [FILM|HIGH|CONFIRMED] |
| **Hugh** | 房子 A | 是（第一次外出去亮灯房） | **来自第三栋房子** [FILM|HIGH|CONFIRMED] | 不确定 [INFERENCE|LOW|HYPOTHESIS] |
| **Amir** | 房子 A | 是（与 Hugh 同行） | **来自第三栋房子** [FILM|HIGH|CONFIRMED] | 不确定 [INFERENCE|LOW|HYPOTHESIS] |
| **Laurie** | 被 Amir 带来 | 是（4 人组） | **来自不同现实** [FILM|HIGH|CONFIRMED] | 不确定 [INFERENCE|LOW|HYPOTHESIS] |

### Emily 的归属推断 [INFERENCE|MEDIUM|PARTIAL]（Emily 的分析]

| 归属 | 人物 | 依据 |
|---|---|---|
| **房子 A（原始）** | Lee、Beth | 从未离开过房子 |
| **另一栋** | Em、Kevin、Laurie | 4 人外出后返回 |
| **第三栋** | Hugh、Amir | 第一次外出 |
| **第四栋** | Mike | 单独外出勒索 |

**重要**：这是 Emily 的推断，不是 100% 确认。[INFERENCE|MEDIUM|PARTIAL]

**支持此推断的证据** [INFERENCE|LOW|HYPOTHESIS]：
- Emily 创建验证盒（骰子随机数+随机物品）
- Lee 和 Beth 从未离开房子（有对话支撑）
- Hugh/Amir 的红荧光棒暴露了替换

**反对此推断/不确定的证据** [INFERENCE|LOW|HYPOTHESIS]：
- 验证盒方法本身可能被不同现实的版本使用
- Emily 的分析基于她当时能观察到的，可能有盲区
- 电影未最终确认各人物的"原始"归属

---

## 现实分支图（简化）

```
初始现实 A（8 人聚会，蓝荧光棒）
├── 停电 → 手机碎裂
├── Hugh + Amir 外出 → 到达现实 B（亮灯房）
│   ├── 返回时已非原版（红荧光棒暴露）
│   └── "真" Hugh + Amir 后来返回
├── Em + Kevin + Mike + Laurie 外出
│   └── 遇到红荧光棒群体（现实 C 或 D）
├── Mike 单独外出勒索 → 到达现实 D
├── 便条重复出现 → 确认多现实
├── 验证盒创建 → Emily 的归属分析
├── Em 离开 → 探索多个房子
│   ├── 暴力现实
│   ├── 其他变体
│   └── "完美"现实（Em-Kevin 和谐）
│       └── Em 暴力替换另一个自己
└── 彗星碎裂 → 现实窗口关闭
    └── 结尾电话（悬念保留）
```

---

## 不确定性保留

以下内容电影**未确认** [DESIGN|N/A|PENDING_USER]，游戏改编中应保留悬念：

1. 被替换的 Em 的命运 [DESIGN|N/A|PENDING_USER]
2. 电话是谁打来的 [DESIGN|N/A|PENDING_USER]
3. 有多少个现实 [DESIGN|N/A|PENDING_USER]
4. 穿越是否可以控制 [DESIGN|N/A|PENDING_USER]
5. 彗星经过后现实是否恢复 [DESIGN|N/A|PENDING_USER]
