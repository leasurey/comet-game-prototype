# 美术产出证据

本目录存放**真实产出**，用于人工验收，不是概念图也不是参考图。

## `previews/` — 角色检查图

由 Blender 实际渲染（EEVEE，720×1000，三点布光 + 地面）。

| 文件 | 内容 |
|---|---|
| `<角色>_rest.png` | 静止站姿（检查比例、面部、服装分区） |
| `<角色>_walk.png` | walk 动画第 9 帧（检查腿部摆动与蒙皮形变） |
| `<角色>_talk.png` | talk 动画第 20 帧（检查手臂手势） |

生成命令：
```bash
blender.exe --background --factory-startup \
  --python tools/blender/build_character.py -- \
  --out assets/models/characters \
  --blend-dir assets/source/blender \
  --render-dir docs/art/previews
```

注意：这是 Blender 离线渲染，**只能说明模型本身的样子**，
不能代表游戏内效果。游戏内效果见 `screenshots/`。

## `screenshots/` — 游戏内实拍

由 `tools/capture_screenshots.gd` 在真实运行的 Godot 中抓取
（1280×720，走真实「开始新游戏」入口，非编辑器视图、非 Blender 渲染）。

| 文件 | 视角 |
|---|---|
| `01_foyer_to_living.png` | 玄关看向客厅/餐厅 |
| `02_living_room.png` | 客厅家具 |
| `03_dining_table.png` | 餐桌与椅子 |
| `04_kitchen.png` | 厨房 |
| `05_front_door_closed.png` | 前门关闭 |
| `06_door_open.png` | 前门打开 |
| `07_kevin_closeup.png` | Kevin 近景 |
| `08_kevin_dialogue.png` | 与 Kevin 的对话 UI |

重新抓取：
```bash
godot --path . --resolution 1280x720 --script res://tools/capture_screenshots.gd
```

**已知局限**：截图反映的是 2026-11-01 的构建状态。
家具仍是参数化 BoxMesh 组合（灰盒级），只有角色是结构化模型。
所以截图里「人比家具精致」是真实的当前状态，不是渲染错误。
