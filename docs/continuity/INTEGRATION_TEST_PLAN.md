# 集成测试计划（INTEGRATION_TEST_PLAN）

**基准**：`recovery/master-rebuild` @ `800beb7`｜只读审查｜证据分级 A/B/C/D。
**现有测试**：22 个 / 588 断言，全绿（本轮复跑 cognition_npc_test 确认 PASS=37 [B]；全量绿为 2026-10-31 当日多次运行记录 [B]）。

---

## 1. 现有测试质量审查（任务第九节逐项）

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| 只验证函数返回值？ | 部分。cognition/save/nav 测试断言真实状态（认知条数、坐标、polygon 数）；但 N3/N4 等以 API 返回为主 | **A**（测试源码） |
| 验证真实状态变化？ | 是（C1 认知数、N2 坐标、L3 菜单→场景） | **B** |
| 验证跨系统调用？ | 少量（dialogue_ui_test 走 main 全链、ui_layout_test 出门闭环）；**NPC↔认知↔对话↔存档四系统联测为零** | **A** |
| 场景卸载/重生成？ | **无**。没有任何测试断言离场-重入后 NPC 连续性（CT-004 因此漏网） | **A** |
| 存档读写一致性？ | 有（migration/isolation/C5）；**不含 NPC 字段**（CT-003 漏网） | **A** |
| 模拟对象遮蔽真实流程？ | **是，两处关键**：① N4/U6 手工 `cognition.learn("fact_sticky_note")` 注入钥匙，跳过获取端（CT-019 因此漏网）；② N3 用 `send_to_room` API 直派目标，掩盖"游戏里没人派目标"（CT-020） | **A+B** |
| 测试相互污染/顺序依赖？ | 存档隔离核查通过（全部存档触碰测试 use_test_path）[A+B]；`use_test_path` 各自 tag 互不覆盖 [A]。**无污染证据** | **B** |
| 瞬移替代真实行为？ | 存在（测试普遍直接设 global_position）——任务规则 14 警告的模式；已在下述新设计中要求真实路径 | **A** |

## 2. 覆盖矩阵（四大系统 × 验证类型）

| | 单元返回 | 状态变化 | 跨系统 | 卸载/重建 | 存档往返 |
| --- | --- | --- | --- | --- | --- |
| NPC | ✅ N1/N3/A3 | ⚠️ 仅坐标 | ❌ | ❌ | ❌ |
| 认知 | ✅ C2/C4 | ✅ C1/C3 | ✅ N4/U6（钥匙伪造） | — | ✅ C5 |
| 对话 | ✅ hear | ✅ U3/U4 | ⚠️ U 全链（钥匙伪造） | ❌ | ❌（进度无档） |
| 存档 | ✅ isolation | ✅ migration | ❌ NPC 字段 | ❌ | ⚠️ 无 NPC |

## 3. 新增集成测试设计（任务第九节 1-4）

> 四个设计都要求**真实前置**：真实行走/交互/对话推进，禁止瞬移与直接改内部状态（除"断言用只读接口"）。凡当前无法通过的，如实标注**缺失依赖**，不伪造通过。

### 测试 1：检查物品 → 获得认知 → 解锁对应对话

```
步骤：真实移动到书桌 → E 检查（examine 热点）→ 断言 cognition 出现 fact_inspected_StudyDesk
     → 真实移动到 kevin → E 对话 → 断言话题列表/回复包含"引用该观察"的项
断言：认知来源=inspect；对话 requires 消费该 fact；读档后两者仍在（并入测试 4）
现状可跑部分：inspect→认知→闸门机制（改用 fact_inspected_* 作为 requires 的对话）
缺失依赖：① dialogue.json 中没有任何 requires 消费 fact_inspected_*（CT-019 同源）
         ② 无"观察内容细节"（CT-016）。需先加一条 requires=fact_inspected_StudyDesk 的测试节点
         （数据补丁，属修复批次 3），本测试才能全绿。
```

### 测试 2：NPC 状态改变 → 对话反映变化

```
步骤：对话 kevin 一次（记录 said）→ 触发某事件使 kevin 状态变（如 set_flag 后 NPC 情绪变）
     → 再问同一话题 → 断言回答不同或 NPC 引用先前交流
缺失依赖：NPC 无记忆/情绪/said 记录（CT-009/022/023）；对话无 variants。
         当前代码下**必然失败**——先做批次 2（快照）+批次 5（记忆/对话维度）。
可先行跑的子集：对话两次 granted 不重复授予（learn 幂等）——已有 [B]。
```

### 测试 3：现实切换 → NPC 与对话产生对应变化

```
步骤：与 kevin 对话记录文本 → 真实走入 dark_far_end（area_enter）→ 断言 world=beta
     → 返回住宅 → 再与 kevin 对话
断言：NPC 行为/记忆或对话文本/可用话题与 alpha 下不同（至少一项）
现状：世界切换本身断言已有（reality_cycle [B]）；NPC/对话侧**无机制**（CT-022/009）
缺失依赖：对话 world 维度或 variants；NPC per-world 记忆槽。
可先行跑的子集：切换后 Cognition 不自动增事实（C1 [B]）；异常音 cue 播放（audio [B]）。
```

### 测试 4：保存 → 重启读档 → 状态一致

```
步骤：完成测试 1 的认知 + 对话进度 + NPC 移动到中途（send 后未到）
     → save_game → 新建会话（等价重启）→ continue_game
断言：认知（含来源）一致；NPC 位置/行为=存档值；对话进度一致；世界/地点一致
现状可跑部分：世界/认知/地点/玩家（migration [B]）；NPC 断言**必失败**（CT-003）
缺失依赖：continue_game 调 npc_manager.restore（批次 2）；对话进度字段（批次 5）。
```

## 4. 测试基建补充（任务第九节"真实窗口"）

- `tests/continuity/` 目录承载上述用例（headless 部分）。
- `tests/continuity/real_window/`：17 步走查记录模板（步骤表/截图/日志/结论），由人工执行归档（CT-018）。
- 每用例标注依赖批次：测试 1→批次 3，测试 2→批次 5，测试 3→批次 5，测试 4→批次 2。
- **禁止**新测试直接调用 `cognition.learn` 伪造闸门钥匙；钥匙必须经 examine/hear 真实路径产生（测试 1 的核心整改点）。
