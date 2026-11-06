# COMET 剧情设计资料库

版本：Narrative Design v1.0。状态：设计草案，待用户确认，不是可直接运行的游戏数据。

## 文档
- FILM_TIMELINE_AND_FACTS.md：电影事件顺序、叙事结构、证据边界。
- CHARACTERS_AND_KNOWLEDGE.md：八名角色档案、关系、信息差。
- SCENE_AND_SPACE_ATLAS.md：关键场景、空间用途、游戏场景映射。
- NARRATIVE_EVENT_CATALOG.md：剧情事件表，包含触发、参与者、世界变化、玩家信息、后续、存档。
- GAME_ADAPTATION_RULES.md：改编原则、分支规则、系统接口和验收标准。
- OPEN_QUESTIONS.md：待用户决策和待复核事项。

## 证据标记
- F：电影画面或对白直接支持。
- S：二手资料支持，不等同逐镜头核验。
- I：根据线索作出的解释推断。
- G：COMET 原创游戏化设计。
- TBD：尚未核实或需要用户决定。

## 核心原则
1. 电影事实、解释推断、游戏原创设计分开记录。
2. Emily 的玩家认知不等于全知叙事者知道的全部信息。
3. NPC 客观经历、NPC 自己知道的内容、Emily 已知的内容是三套不同状态。
4. 不以进入某区域自动等同于玩家理解了某件事。
5. 事件必须有稳定 ID、明确触发条件、可保存状态和可测试结果。
6. 电影高潮是叙事锚点，不强制玩家照搬原片行为。
7. 不复制电影字幕、剧本或长段对白；所有游戏对白应原创重写。

## WorkBuddy 使用要求
先阅读本目录全部文档，再读取当前 EventManager、CognitionManager、DialogueManager、NPCManager、SaveManager 和剧情数据。不要假定本文档字段已经存在于当前 JSON schema。

第一轮只做只读适配评估，产出 IMPLEMENTATION_MAPPING.md，列出现有字段映射、缺失系统、存档兼容风险和最小扩展建议。用户确认前，不写剧情 JSON、不修改运行时代码、不删除旧数据。

## 来源
- James Ward Byrkit 访谈与导演对观看线索的说明：https://taylorholmes.com/2015/06/19/movie-coherence-explained-and-interview-with-director-james-ward-byrkit/
- 非官方对白转录核对：https://www.springfieldspringfield.co.uk/movie_script.php?movie=coherence
- 角色与基础剧情梗概：https://www.commonsensemedia.org/movie-reviews/coherence
- 时间线辅助解析：https://www.thisisbarry.com/film/coherence-2013-movie-plot-ending-explained/

非官方转录可能有错漏；二手解析中的副本编号属于解释，不应视为官方设定。