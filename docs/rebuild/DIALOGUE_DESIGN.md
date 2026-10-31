# COMET 对话系统设计与协议

> 本轮已修复 `next`/`goto` 协议断裂。本文档定义统一协议。

---

## 一、数据协议（已实现）

### 节点结构

```json
{
  "id": "kevin_vs_open",
  "speaker": "kevin",
  "text": "嘿，Em。你站那儿有一会儿了……怎么了？",
  "requires": ["fact_sticky_note"],
  "entry": false,
  "replies": [
    {
      "text": "没什么，就是有点走神。",
      "goto": "kevin_vs_comet",
      "effects": [
        {"kind": "grant_fact", "fact_id": "obs_comet_discussion"},
        {"kind": "set_flag", "name": "asked_about_comet"}
      ]
    }
  ]
}
```

### 字段定义

| 字段 | 类型 | 说明 | 状态 |
|---|---|---|---|
| `id` | string | 节点唯一 ID | ✅ |
| `speaker` | string | 说话者 NPC id | ✅ |
| `text` | string | 显示文本（支持变体） | ✅ |
| `requires` | string[] | 认知闸门：需已知的事实 | ✅ |
| `entry` | bool | 是否可作为话题入口 | ✅ |
| `replies` | array | 玩家选项 | ✅ |
| `replies[].text` | string | 选项文本 | ✅ |
| **`replies[].goto`** | **string** | **跳转目标节点** | ✅ **统一键名** |
| `replies[].effects` | array | 效果列表 | ✅ |

### 跳转键统一（本轮修复）

**问题**：数据混用 `next` 和 `goto`，代码只读 `goto` → 9 条分支全部失效。

**修复**：
1. 数据迁移：9 条 `next` → `goto`（现 54 条全部统一）
2. 代码兼容：`_reply.get("goto", _reply.get("next", null))` 双键兜底
3. `DialogueManager.get_entry_nodes_for` 同步兼容

**规则**：新数据只用 `goto`。`next` 仅为旧数据兜底，不再新增。

---

## 二、效果类型（effects）

| kind | 参数 | 作用 |
|---|---|---|
| `grant_fact` | `fact_id` | 玩家学到事实 |
| `set_flag` | `name` | 设置事件旗标 |
| `npc_state` | `npc_id`, `state` | 改变 NPC 状态 |
| `audio` | `cue` | 播放音效 |
| `log` | `text` | 记录 |

---

## 三、认知闸门（信息差实现）

**核心机制**：`requires` 列出必须先知道的事实，否则话题不出现。

### 示例

```json
{
  "id": "kevin_sticky",
  "requires": ["fact_sticky_note"],
  "text": "便签？什么便签？我没在门上贴过东西。"
}
```

玩家必须先检查门上的便签（获得 `fact_sticky_note`），才能问 Kevin 关于便签的话题。

**这保证了**：NPC 不会谈论玩家还不知道的信息。

---

## 四、人物语言风格

| 人物 | 句长 | 用词 | 特点 |
|---|---|---|---|
| Kevin | 中 | 温和、含糊 | 回避冲突，"也许""大概" |
| Mike | 短 | 大声、直接 | 脏话、玩笑、打断 |
| Lee | 中 | 平缓 | 照顾性、"要不要…" |
| Beth | 长 | 灵性 | "感觉""能量""直觉" |
| Hugh | 长 | 科学 | "理论上""退相干""概率" |
| Amir | 短 | 快 | 兴奋、慌张、重复 |
| Laurie | 中 | 直接 | 暧昧、试探 |
| Emily（玩家选项） | 变 | 直接/犹豫 | 可尖锐、可回避 |

---

## 五、垂直切片对话（已实现）

```
kevin_vs_open（入口，需 fact_sticky_note）
├── 彗星话题 → kevin_vs_comet ──┬→ 幸运 → kevin_vs_end
│                                └→ 希望普通 → kevin_vs_end
├── 不对劲 → kevin_vs_uneasy ──┬→ 说不上来 → kevin_vs_end
│                               └→ 多心 → kevin_vs_end
└── 累了 → kevin_vs_tired ─────┬→ 还没想好 → kevin_vs_end
                                └→ 不想聊 → kevin_vs_end
```

**设计意图**：
- 三个入口对应 Em 三种心理状态（转移话题 / 表达不安 / 回避）
- 每个分支都收束到 `kevin_vs_end`，避免死路
- 效果写入事实，影响后续

---

## 六、待补（阶段 E）

| 项目 | 状态 |
|---|---|
| 8 人完整对话树 | ❌ 只有 Kevin 5 节点 |
| 背景闲聊（NPC 互谈） | ❌ |
| 现实分支对话差异 | ❌ |
| 关系变化对话 | ❌ 部分 |
| 误解对话（NPC 说错的事） | ❌ |

---

## 七、测试约束

**禁止**：
- 测试代码直接调用 `DialogueManager.hear()` 注入结果
- 通过 `_debug_activate()` 代替真实玩家交互

**要求**：对话必须能从正常 UI 触发和完成。
