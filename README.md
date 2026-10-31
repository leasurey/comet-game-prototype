# COMET

以电影《彗星来的那一夜》（*Coherence*, 2013）的**叙事构想**为灵感的第一人称悬疑探索游戏。
在彗星过境的那一夜，一段没有灯的路走过去之后，熟悉的屋子开始变得和记忆里不一样。

> **核心体验**：走进黑暗 → 沿路返回 → 发现「同一个地方」已经不是原来的样子。
> 你亲眼看过的证据、你和别人的对话、你留下的记号，决定你能否发现真相。

**当前版本 v0.6.0** —— 完整可玩闭环：主菜单 → 探索全屋 → 出门 → 黑路穿越（现实切换）→ NPC 对话与推理 → 存档/读档。

---

## 快速开始

**双击 `start_game.bat`**（需要同级 `tools\Godot\` 下有 Godot 4.7.2，见下方前置条件）。

或手动运行：

```bash
"C:/path/to/Godot_v4.7.2-stable_win64.exe" --path "D:/新建文件夹/comet-game-prototype"
```

### 前置条件

1. 下载 **Godot 4.7.2-stable 标准版**（不要 mono 版）：
   <https://github.com/godotengine/godot/releases/tag/4.7.2-stable>
2. 解压后按以下布局放置（`start_game.bat` 会自动寻找）：

```
<workspace>/
├── comet-game-prototype/          ← 本项目
└── tools/Godot/Godot_v4.7.2-stable_win64.exe
```

### 操作

| 输入 | 作用 |
| --- | --- |
| 鼠标移动 | 环视（进入游戏后自动捕获光标） |
| **W A S D** | 移动 |
| **Shift** | 奔跑 |
| **空格** | 跳跃 |
| **E** / 鼠标左键 | 交互（走近目标 ≤2.5 m，准星对准后显示名称） |
| **ESC** | 暂停菜单（继续 / 保存 / 设置 / 返回主菜单 / 退出） |
| **Q** | 退出游戏 |
| **TAB** | 手机（占位，后续版本） |

对话面板：点击话题/回复推进，ESC 或「结束对话」退出。

---

## 玩法闭环

1. **主菜单** → 开始新游戏 / 继续游戏 / 设置 / 退出
2. **聚会房屋**（玄关、客厅、餐厅、厨房、书房——13.4 m × 9.4 m 灰盒全屋）
   - 7 名角色可交谈：话题受**认知闸门**控制（没亲眼见过的东西，没人会跟你谈）
   - 可查看的物品留下证据（检查过的物品才「知道」）
3. **三扇门**（前门 / 侧门 / 露台推拉门）→ **房屋外部**（门廊、车道、街道）
4. **走向那条没有灯的路** → 黑暗区域穿越 → **现实切换**
   - 三个现实（α/β/γ）循环，环境差异是可观察的
   - 穿越发生在**走出黑暗时**，不是进入时——回头路才是关键
5. 回屋继续对话与调查：你的认知决定 NPC 愿意说什么
6. **保存 / 读档**（含玩家位置、朝向、认知、NPC 状态；写入原子化，断电不坏档）

---

## 系统一览

| 系统 | 说明 |
| --- | --- |
| 第一人称控制 | CharacterBody3D + 鼠标捕获视角（俯仰 ±75°），行走/奔跑/跳跃，步距触发脚步声 |
| 世界与现实 | 3 个现实变体按事件规则循环切换；地点内容随世界状态呈现可观察差异 |
| 热点交互 | 准星射线 + 距离（2.5 m）+ 遮挡三重判定；查看物品推进认知 |
| 玩家认知 | 「客观世界 ≠ 玩家知道」：事实经亲证（inspect）或对话（dialogue）习得，可存档 |
| 对话系统 | 29 个对话节点、22 条认知事实、分支回复（goto 链）、话题入口 + 正式对话面板 |
| NPC | 7 名角色、navmesh 寻路、确定性分离转向避让（对向错车）、状态存档 |
| 音频 | 21 个程序合成 WAV（环境/脚步/门/交互/移动/UI/异常），分类音量 × 总音量 |
| 存档 | 原子写入（tmp→校验→备份→改名）、v1→v2 迁移、损坏存档自动隔离 |
| UI | 主菜单 / 暂停 / 设置（灵敏度、音量、分辨率、帧率、全屏）/ 对话面板 / HUD |
| 时钟 | 动作驱动的离散 tick（重放一致性），显示于 HUD |

---

## 技术

| 项目 | 选择 |
| --- | --- |
| 引擎 | Godot **4.7.2-stable**（commit `ed1daf0bf`，官方 SHA-512 校验） |
| 语言 | GDScript |
| 渲染 | OpenGL 3.3 Compatibility（集显/老旧机型友好，Radeon 530 实测流畅） |
| 素材 | **零第三方**：几何全部程序生成，音频全部本地合成，无电影画面/音频/台词 |
| 测试 | 22 个 headless 测试 / 588 条断言，`--headless --script` 可独立运行 |

---

## 项目结构

```
comet-game-prototype/
├── start_game.bat          # 启动游戏（双击）
├── open_editor.bat         # 打开 Godot 编辑器
├── project.godot
├── autoload/game_services.gd   # 唯一 autoload：装配各 Manager
├── core/                   # 逻辑层（world/event/save/scene/interaction/
│                           #   cognition/dialogue/npc/audio/settings...）
├── core/ui/                # UI（ui_manager / menu_controller，代码构建）
├── scenes/main.tscn        # 入口场景 + main.gd（输入路由/装配）
├── scenes/locations/*.tscn # 4 个地点场景（由 scene_builder 生成，勿手改）
├── tools/scene_builder.gd  # 场景生成管线（改 tools/ 后需重新生成）
├── data/*.json             # 世界/事件/地点/角色/对话数据
├── assets/audio/           # 21 个合成 WAV（见 docs/AUDIO_ASSET_REGISTER.md）
├── tests/*.gd              # 22 个 headless 测试
└── docs/                   # 架构 / 已知问题 / 验收 / 恢复报告 / 交付物
```

---

## 测试

```bash
# 单个测试
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/acceptance_test.gd

# 全量（22 个）
for t in tests/*.gd; do Godot_..._console.exe --headless --path . --script res://$t; done
```

当前基线：**22 测试 / 588 断言全部通过，退出日志零泄漏**。覆盖：

- FPS 输入与移动 / 跳跃 / 门与热点连通
- 三现实循环穿越与黑暗区域触发
- 存档原子性 / 隔离 / 迁移 / 会话重置
- 主菜单 / 暂停 / 设置流程
- 认知闸门 / 对话分支 / NPC 寻路与避让 / 多 agent 性能护栏
- 音频系统 / 导航可行性 / UI 布局（屏内 + 命中路由 + 出门主循环）
- 数据完整性 / 场景几何

改 `tools/` 后必须重新生成场景再跑测试：

```bash
Godot_..._console.exe --headless --path . --script res://tools/scene_builder.gd
```

---

## 性能目标

为低配笔记本设计（i5-7200U / 12 GB / Radeon 530 / 1280×720）：

| 场景 | 实测 |
| --- | --- |
| 室外 / 一般室内 | 60 fps |
| 聚会房屋（12 盏灯） | 33–38 fps（Compatibility 渲染的光照 pass 限制，待优化） |

多 agent 寻路：7 个 NPC 同时派目标 213 μs、寻路查询 303 μs、每帧 tick 2 μs（预算断言守护）。

---

## 素材与许可

| 类别 | 来源 | 许可 |
| --- | --- | --- |
| 全部代码 | 原创 | MIT |
| 全部 3D 几何 | `tools/` 程序生成（Box/Cylinder + 纯色材质） | MIT |
| 全部音频 | 本地脚本合成的 WAV | MIT |
| 引擎 | Godot 4.7.2 | MIT |
| 电影素材 | **无**（不包含画面/音频/台词/商标，不复述剧情） | — |

只借用「熟悉的地点在不知不觉间变得不同」这一叙事构想。电影细节请以影片为准。

---

## 文档

| 文档 | 内容 |
| --- | --- |
| `docs/KNOWN_ISSUES.md` | 已知限制与未验证项（玩之前建议扫一眼） |
| `docs/ARCHITECTURE.md` / `MASTER_ARCHITECTURE.md` | 分层架构与依赖关系 |
| `docs/ACCEPTANCE.md` / `MASTER_ACCEPTANCE.md` | 验收标准与结果 |
| `docs/AUDIO_ASSET_REGISTER.md` | 音频素材登记 |
| `docs/NAVIGATION_FEASIBILITY.md` | navmesh 可行性验证 |
| `docs/MASTER_RECOVERY_REPORT.md` | 全量审计修复记录（28 项 bug） |
| `docs/deliverables/` | 各阶段交付物 |
| `docs/CHANGELOG.md` / `SESSION_LOG.md` | 变更与会话记录 |

---

## 当前状态

**可完整游玩**。欢迎报告的问题：

1. 画面观感（明暗、比例、UI 排版细节）未经人眼校准——机制全部机器验证过；
2. 聚会房屋帧率 33–38 fps（灯光数量待优化）；
3. 手机（TAB）为占位功能；
4. 角色为无模型的灰盒占位（胶囊体），对话内容为原创中文。

问题清单与修复历史见 `docs/KNOWN_ISSUES.md`。
