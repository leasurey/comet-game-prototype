# COMET — 数据层说明

地点、世界、事件三类数据都以纯 JSON 存放，与代码逻辑完全分离。
目的是让「剧情/世界规则」可以脱离引擎代码独立编辑。

> 注意：JSON 标准不支持注释。这些文件必须保持纯 JSON，
> 字段说明一律写在本文档中，不得写进 JSON 文件内部。

---

## worlds.json

描述世界本身，不含任何地点与几何信息。

| 字段 | 说明 |
| --- | --- |
| `initial_world` | 新游戏启用的世界 id |
| `worlds[].id` | 世界唯一标识；场景中的 variant 节点通过该 id 与之关联 |
| `worlds[].label` | 内部日志/存档用的人类可读名称 |
| `worlds[].descriptor` | 一句话语义描述 |
| `worlds[].origin` | 父世界 id；初始世界为空字符串 |

---

## world_transitions.json

世界转移的唯一合法来源。任何世界变化都必须能追溯到这里的一条规则。

| 字段 | 说明 |
| --- | --- |
| `transitions[].id` | 规则 id，同时作为事件 id 写入历史 |
| `transitions[].type` | `fixed` / `conditional` / `pseudo_random` |
| `transitions[].once` | 为 true 时整个存档周期只允许触发一次 |
| `transitions[].trigger.kind` | `enter_location`（进入地点）或 `interact`（与热点交互） |
| `transitions[].trigger.location_id` | `enter_location` 时必填 |
| `transitions[].require_from_world` | 仅当当前世界为该值时才允许触发 |
| `transitions[].to_world` | `fixed` / `conditional` 的目标世界 |
| `transitions[].seed` | `pseudo_random` 用的确定性种子 |
| `transitions[].candidate_worlds` | `pseudo_random` 的允许结果范围，不得越界 |
| `transitions[].log` | 触发时送入 UI 的叙述文本 |

**类型语义**

- `fixed`：条件满足就必须发生，目标世界唯一确定。
- `conditional`：额外要求 `requires` 条件全部满足。
- `pseudo_random`：只能在 `candidate_worlds` 范围内取值，且由 `seed` 决定。
  相同 seed 与相同触发序号必然得到相同结果，因此可复现——这不是真随机。

第一版原型只使用 `fixed` 类型；其余两类已实现通路但未启用，避免过早引入不可控变量。

---

## events.json

事件是世界变化的触发器容器，也是历史记录的单位。
事件本身不直接改世界，而是引用 `world_transitions.json` 中的同名规则生效，
使「发生了什么」与「世界怎么变」可以各自独立演化。

| 字段 | 说明 |
| --- | --- |
| `events[].id` | 事件唯一标识，必须与转移规则 id 对应 |
| `events[].label` | 内部可读名称 |
| `events[].kind` | 事件性质分类 |
| `events[].repeatable` | 是否允许重复记录 |
| `events[].narrative_hint` | 可选的叙述提示（可为空字符串） |

---

## locations.json

地点定义，与世界无关。

| 字段 | 说明 |
| --- | --- |
| `locations[].id` | 地点唯一标识 |
| `locations[].scene` | 对应的 `.tscn` 路径 |
| `locations[].display_name` | 显示在 UI 上的地点名 |
| `locations[].ambient` | 环境基调描述，仅用于日志 |
| `locations[].exits[]` | 出口列表，含目标地点 id 与面向玩家的说法 |
| `locations[].variants` | 支持的世界 id 列表；缺失时回退到 `default` variant |
