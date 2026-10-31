# COMET 美术资源管线（Blender → Godot）

## ⚠️ 环境实况（必须如实记录）

| 项目 | 状态 |
|---|---|
| Blender 是否安装 | ❌ **本机未安装 Blender** |
| 是否已产出 .blend 源工程 | ❌ 无 |
| 是否已引入外部模型 | ❌ 无 |
| 当前 NPC 模型 | 程序化生成（CylinderMesh/SphereMesh/BoxMesh 拼接） |
| 当前家具模型 | 程序化生成（BoxMesh 组合） |

**结论**：本阶段的"Blender 管线"是**方案设计**，不是已执行的工作流。不能声称已完成 Blender 建模。
当前所有人物/家具模型都是**明确标记的程序化占位**，不是最终资产。

---

## 一、目录规划

```
assets/
├── source/          # Blender 原始工程（.blend）
│   ├── characters/
│   └── props/
├── models/          # 导出给 Godot 的 .glb
├── textures/        # 贴图
├── animations/      # 独立动画资源
tools/blender/       # Python 自动化脚本
docs/art/            # 来源与授权记录
```

---

## 二、推荐管线（待 Blender 可用后执行）

### 2.1 环境准备
1. 安装 Blender 4.x（官方 blender.org，LTS 版本）
2. 启用内置插件：glTF 2.0 Exporter（默认已启用）
3. 可选：Rigify（内置，自动生成人形骨架）

### 2.2 人物制作流程（单个原型验证优先）

```
① 基础人体
   - 方案 A：Blender 内置 Rigify 人形骨架 + 手工建模
   - 方案 B：复用 CC0/CC-BY 授权的基础人体（如 Quaternius、Mixamo 需核对授权）
   - 方案 C：MakeHuman（开源，CC0 输出）
② 外观调整
   - 体型比例、发型、服装、面部特征
③ 骨骼绑定
   - Rigify 生成 → 权重绘制 → 验证变形
④ 动画
   - idle / walk / turn / talk / sit / stand_up
   - 可用 Mixamo 动作重定向（需核对授权）
⑤ 导出
   - glTF 2.0 (.glb)，含骨骼+动画+材质
⑥ Godot 导入
   - 检查比例/朝向/材质/骨骼/动画
⑦ 游戏内验证
   - 实际场景中的比例、动画切换、性能
```

### 2.3 Godot 导入检查清单

| 检查项 | 要求 |
|---|---|
| 比例 | 1.75m 高，Y-up |
| 朝向 | 面向 -Z（Godot 前向） |
| 骨骼 | Skeleton3D 有实际骨骼层级 |
| 蒙皮 | 权重正确，无穿插 |
| 动画 | 6 个基础动画可播放 |
| 材质 | PBR 正确，无丢失贴图 |
| 面数 | ≤ 15K 三角/人 |
| 动画切换 | 无明显错位 |

### 2.4 自动化脚本（规划）

`tools/blender/` 下规划：
- `export_characters.py`：批量导出人形
- `validate_rig.py`：检查骨骼完整性
- `batch_materials.py`：批量材质设置

**状态**：❌ 未实现（无 Blender 环境）

---

## 三、当前替代方案（阶段 A 实际使用）

**程序化人形**（core/npc.gd）：
- 躯干：Chest/Abdomen/Pelvis（BoxMesh）
- 头：椭球（SphereMesh 缩放）+ 鼻/下巴/耳
- 头发：球体 + 前额发带
- 四肢：圆柱（肩/肘/膝关节）
- 鞋：BoxMesh

**诚实的评价**：
- ✅ 有基本人形轮廓、可辨识
- ✅ 7 人不同肤色/发色/服装
- ❌ 无骨骼动画（idle/walk 未实现）
- ❌ 无面部表情
- ❌ 达不到"电影写实"

**这是占位，不是最终资产。** 必须由 Blender 管线替换。

---

## 四、性能约束

| 项目 | 上限 |
|---|---|
| NPC 单模型 | ≤ 15K 三角 |
| 贴图 | ≤ 1024² |
| 8 NPC 同屏 | ≤ 120K 三角 |
| 骨骼数 | ≤ 60/人 |

目标设备：i5-7200U / 12GB / Radeon 530 2GB
