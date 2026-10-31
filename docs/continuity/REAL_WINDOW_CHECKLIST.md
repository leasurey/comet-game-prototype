# 真实窗口验收清单（批次 6）

> 本清单供人工在有画面的窗口中逐项验证。自动化已覆盖逻辑正确性，
> 但观感、手感、听感必须由人确认。每项标注对应自动化证据。

## 一、主菜单与启动

| # | 验收项 | 预期结果 | 自动化证据 | 人工结果 |
|---|--------|----------|------------|----------|
| 1 | 启动游戏 → 主菜单显示 | 标题 + 开始新游戏/继续游戏/退出按钮 | ui_layout_test | |
| 2 | 点击「开始新游戏」 | 按钮可点、鼠标变为捕获 | ui_layout_test L1/L2 | |
| 3 | 无存档时「继续游戏」禁用 | 按钮灰置 | menu_flow_test | |
| 4 | 菜单按钮有音效 | 点击发出 UI 音 | phone_feedback_test F5 | |

## 二、探索与交互

| # | 验收项 | 预期结果 | 自动化证据 | 人工结果 |
|---|--------|----------|------------|----------|
| 5 | WASD 移动 | 流畅行走，不穿墙 | player_movement_test | |
| 6 | Shift 加速跑 | 明显变快 | player_movement_test | |
| 7 | 空格跳 | 起跳+落地音效 | player_jump_test | |
| 8 | 鼠标环视 | 流畅无卡顿，俯仰受限 | fps_input_test | |
| 9 | 门上前门 → 准星显示「前门」 | 交互提示在屏内 | ui_layout_test L6 | |
| 10 | E 键出门 → 房屋外部 | 场景切换流畅 | ui_layout_test L5 | |
| 11 | 侧门/露台门均可出入 | 三扇门都通 | door_connection_test | |
| 12 | 检查门上便签 | 「你记下了…」+「你了解到…」 | cognition_key_test K1 | |
| 13 | 手机（TAB） | 打开三页签面板 | phone_feedback_test F4 | |
| 14 | 事实台账有观察记录 | 便签观察已入账 | phone_feedback_test F3 | |
| 15 | 点空白处/ESC 关手机 | 关闭并恢复鼠标捕获 | phone_feedback_test F4 | |

## 三、对话

| # | 验收项 | 预期结果 | 自动化证据 | 人工结果 |
|---|--------|----------|------------|----------|
| 16 | 走近 Kevin 按 E | 对话面板打开，话题列表 | dialogue_ui_test | |
| 17 | 未检查便签 → 便签话题不见 | 认知闸门生效 | full_flow_test A2 | |
| 18 | 检查便签后 → 便签话题出现 | 同上反向 | full_flow_test A1 | |
| 19 | 选便签话题 | Kevin 回复 + 「你了解到」 | dialogue_ui_test | |
| 20 | 再问同题 | 「我们刚才不是说过了吗？」 | full_flow_test B1 | |
| 21 | 对话中玩家不能移动 | 冻结验证 | input_lock_test L3 | |
| 22 | ESC 关对话 | 恢复鼠标 | dialogue_ui_test | |

## 四、现实切换

| # | 验收项 | 预期结果 | 自动化证据 | 人工结果 |
|---|--------|----------|------------|----------|
| 23 | 走向黑暗的路 | 自动触发穿越 | dark_traverse_test | |
| 24 | 穿越后环境变化 | 窗户/灯光/物品差异 | reality_cycle_test | |
| 25 | 三次穿越回原点 | α→β→γ→α 循环 | full_flow_test C2 | |
| 26 | 穿越后手机事实+1 | 「黑路」入账 | full_flow_test C1 | |
| 27 | 不同现实对话不同 | Kevin 说不同的话 | dialogue_system_test D4 | |
| 28 | 现实切换音效 | reality_shift 音效 | audio_system_test | |

## 五、NPC 行为

| # | 验收项 | 预期结果 | 自动化证据 | 人工结果 |
|---|--------|----------|------------|----------|
| 29 | NPC 不站桩 | 空闲时自行走动 | npc_character_test P3 | |
| 30 | 说话时 NPC 面向你 | 转身面向玩家 | npc.gd start_talking | |
| 31 | 两个 NPC 不穿模 | 对向行走错车 | npc_avoidance_test A1 | |
| 32 | 出门再回来 NPC 位置连续 | 不回出生点 | full_flow_test B1 | |
| 33 | NPC 不堵门 | 门口/通道畅通 | npc_avoidance_test A4 | |

## 六、存档恢复

| # | 验收项 | 预期结果 | 自动化证据 | 人工结果 |
|---|--------|----------|------------|----------|
| 34 | 点「保存」 | 「已保存」提示 + 音效 | save_isolation_test | |
| 35 | 退出 → 重进 → 继续 | 全部状态恢复 | full_flow_test S1 | |
| 36 | 恢复后认知不丢 | 事实/观察数一致 | full_flow_test S1 | |
| 37 | 恢复后 NPC 不重置 | 位置/记忆/对话进度连续 | full_flow_test S1 | |
| 38 | 恢复后现实一致 | 仍在正确的 world | full_flow_test S1 | |

## 七、整体观感

| # | 验收项 | 预期结果 | 自动化证据 | 人工结果 |
|---|--------|----------|------------|----------|
| 39 | 室内明暗平衡 | 不过暗不过亮 | KNOWN_ISSUES 未验证 | |
| 40 | 交互提示字号/位置 | 舒适可读 | ui_layout_test 几何 | |
| 41 | 对话面板排版 | 美观、不遮挡视野 | KNOWN_ISSUES 未验证 | |
| 42 | 手机面板排版 | 三页签清晰 | KNOWN_ISSUES 未验证 | |
| 43 | 音效不过响不刺耳 | 主/分类音量平衡 | KNOWN_ISSUES 未验证 | |

---

## 使用方法

1. 双击 `start_game.bat` 启动游戏
2. 按表格逐项操作，在「人工结果」列填 PASS / FAIL / 备注
3. 发现问题记录到 `docs/continuity/CONTINUITY_BUG_REGISTER.md`
