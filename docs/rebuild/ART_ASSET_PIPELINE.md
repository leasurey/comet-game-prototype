# 美术资源管线：Blender → Godot（已实际执行）

> 本文档记录**实际跑通并验证过**的流程，不是计划书。
> 环境：Blender 5.2.3 LTS（`D:/New Folder/blender.exe`）+ Godot 4.7.2（GL Compatibility）。
> 最后验证：2026-11-01，7 名 NPC 全部导入并通过 126 条校验。

---

## 一、总体思路

角色不是手工建模，而是**用 Blender Python 程序化生成**：

```
tools/blender/build_character.py
        │  （单文件，参数化外观）
        ├─ 生成网格（环放样 loft，非方块拼装）
        ├─ 生成骨架（20 骨骼）
        ├─ 按截面写权重（构建期赋值，不依赖自动权重）
        ├─ 生成 6 段 Action 动画
        └─ 导出 GLB + 保存 .blend 源工程
                ↓
        assets/models/characters/<id>.glb
        assets/source/blender/<id>.blend
                ↓  Godot 自动导入
        core/npc.gd 加载并驱动动画状态机
```

**为什么程序化而不是手工**：8 个角色如果逐个手工建模，改动一处比例就要重做八遍。
脚本化后，调整 `CHARACTERS` 表里的身高/体型/颜色/发型/袖长，一条命令重出全部角色，
且每个角色仍是独立 GLB（改一个人不会影响其他人）。

---

## 二、实际命令

```bash
# 单个角色（含渲染检查图）
blender.exe --background --factory-startup \
  --python tools/blender/build_character.py -- \
  --only kevin --out assets/models/characters --render-dir docs/art/previews

# 全部 7 名（含源工程与检查图）
blender.exe --background --factory-startup \
  --python tools/blender/build_character.py -- \
  --out assets/models/characters \
  --blend-dir assets/source/blender \
  --render-dir docs/art/previews

# 自检（打印大腿/小腿/上臂旋转后的骨骼末端坐标，确认旋转轴方向）
blender.exe --background --factory-startup \
  --python tools/blender/build_character.py -- --only kevin --probe

# Godot 侧导入 + 结构校验
godot --headless --path . --import
godot --headless --path . --script res://tools/verify_character.gd
```

---

## 三、网格构建方式

**不是**把球和方块堆在一起，而是「环放样」（loft）：

- 每个身体部位定义为一串**椭圆截面**（中心 / X 半径 / Y 半径 / 骨骼权重）。
- 相邻截面之间桥接成四边形，末端用三角扇封口。
- 最后统一 `recalc_face_normals` + 平滑着色 + 1 级细分。

好处：躯干有真实收放（肩宽 0.39m → 腰 0.30m → 胯 0.31m），四肢是渐变锥体而不是等粗圆柱。

| 部位 | 截面数 | 说明 |
|---|---|---|
| 骨盆（裤） | 4 | 从裆部收到胯，上衣下摆盖住上沿 |
| 上衣（衬衫） | 8 | 下摆外扩 → 腰收 → 胸放 → 肩线 → 斜方肌 |
| 颈 | 3 | 脖子短，避免「长颈鹿」 |
| 头 | 椭球 + 下颌椭球 | 额头/下巴分别建模 |
| 面部 | 眼/眉/鼻/嘴/耳 | 独立小体块，位置经过 AABB 计算避免陷进头部 |
| 手臂 ×2 | 7~8 | 袖子长度按 `sleeve` 配置裁断（short/rolled/long） |
| 手 ×2 | 4 + 拇指块 | 扁椭圆手掌 |
| 腿 ×2 | 8 | 大腿粗、膝收、小腿收、踝最细 |
| 鞋 ×2 | 6（沿 Y 放样） | 真实鞋型：后跟 → 足弓 → 前掌 → 脚尖 |

---

## 四、骨架与蒙皮

### 骨骼（20 根，19 根形变）

```
root
└ hips ─ spine ─ chest ─ neck ─ head
         │        ├ shoulder.L ─ upper_arm.L ─ forearm.L ─ hand.L
         │        └ shoulder.R ─ upper_arm.R ─ forearm.R ─ hand.R
         ├ thigh.L ─ shin.L ─ foot.L
         └ thigh.R ─ shin.R ─ foot.R
```

### 权重策略（关键差异）

**不使用 Blender 的自动权重**（`ARMATURE_AUTO` 在无界面模式下常报
「Bone Heat Weighting: failed to find solution」，且结果不可控）。

改为**构建期显式赋值**：生成每个截面时就写明这一圈顶点归属哪根骨骼、各占多少。
关节处（肩、肘、膝、胯）用两骨混合，其余 100% 单骨。

```python
((0, 0, 1.165), 0.165, 0.110, {"spine": 0.55, "chest": 0.45}),   # 肋下：脊柱+胸混合
((x0, 0, 0.545), 0.063, 0.061, {"thigh.L": 0.65, "shin.L": 0.35}),  # 膝上：大腿+小腿混合
```

代价：顶点索引必须在写入权重前后保持一致 —— 因此**不做 `remove_doubles`**。

### 旋转轴方向（曾踩坑，已用 `--probe` 固化）

Blender 里骨骼沿自身 Y 轴延伸，绕局部 X 轴旋转才是前后摆动。实测结果：

| 骨骼 | +X 旋转 | 含义 |
|---|---|---|
| `thigh.L` | 腿向前 | 迈步前摆 |
| `shin.L` | 腿向后 | 屈膝（脚跟收向臀部） |
| `upper_arm.L` | 手臂向后 | 摆臂后摆 |

动画全部按这套符号编写，`--probe` 会打印旋转后的骨骼末端世界坐标以便复查。

---

## 五、动画

| Action | 帧数 | 时长@30fps | 循环 | 内容 |
|---|---|---|---|---|
| `idle` | 1–60 | 2.00s | 是 | 呼吸起伏 + 微重心转移 + 头部轻微摆动 |
| `walk` | 1–33 | 1.10s | 是 | 完整步态（前后摆腿、屈膝、反向摆臂、髋部起伏与侧倾） |
| `turn` | 1–26 | 0.87s | 否 | 重心转移 + 上身先转的原地转身 |
| `talk` | 1–90 | 3.00s | 是 | 双手手势 + 点头/侧头 |
| `sit` | 1–31 | 1.03s | 否 | 站立 → 落座（髋降 0.42m、大腿抬 82°、小腿回收） |
| `stand_up` | 1–31 | 1.03s | 否 | 落座 → 站立（`sit` 的反向） |

导出使用 `export_animation_mode='ACTIONS'`，每个 Action 成为 Godot 里一个独立动画片段，
名字与 Action 名一致（`idle`/`walk`/...），由 `core/npc.gd` 的状态机切换。

---

## 六、坐标与朝向（易错点）

| 环节 | 约定 |
|---|---|
| Blender 建模 | 角色面向 **+Y**，脚底在 **Z=0**，身高沿 Z |
| glTF 导出（`export_yup=True`） | Blender (x,y,z) → glTF (x, z, −y)，角色面向 **−Z** |
| Godot NPC | `rotation.y = atan2(dir.x, dir.z)` 使节点 **+Z** 指向移动方向 |

因此 **Godot 侧必须把模型旋转 180°**，否则 NPC 会倒着走：

```gdscript
const MODEL_YAW_FIX := PI
model.rotation.y = MODEL_YAW_FIX
```

`tools/verify_character.gd` 会把这一条作为断言检查（对比 AABB 的 −Z 与 +Z 包络）。

---

## 七、Godot 侧接入

`core/npc.gd`：

```gdscript
func _build_body() -> void:
    if _try_load_model():      # 加载 res://assets/models/characters/<id>.glb
        return
    _build_procedural_body()   # 缺失时降级为程序化占位体（会打 warning）
```

动画状态映射：

| NPC 状态 | 动画 | 备注 |
|---|---|---|
| `STATE_IDLE` | `idle` | 循环 |
| `STATE_WALKING` | `walk` | `speed_scale` 按实际速度缩放，减少脚底打滑 |
| `STATE_TALKING` | `talk` | 进入对话时切换 |
| `sit_down()` / `stand_up()` | `sit` / `stand_up` | 供落座交互调用 |

回归测试：`tests/continuity/npc_model_test.gd`（16 条断言）直接检查运行时节点树，
确认骨架存在、6 段动画齐全、朝向正确、状态切换真的改变 `current_animation`。

---

## 八、导入注意事项（踩过的坑）

1. **`assets/source/` 必须放 `.gdignore`**。
   Godot 会尝试用 Blender 导入 `.blend`，headless 模式没有 Blender 路径 →
   报 `Blender path is invalid` 并**中断整个导入队列**，导致 GLB 全部没导入。
2. **`docs/` 也要 `.gdignore`**，否则检查图/截图会被当作游戏纹理导入。
3. Blender 5.x 的 Action 没有 `.fcurves` 属性（改为 slotted action 的
   layer → strip → channelbag），代码需兼容两条路径。
4. 材质颜色要 **sRGB → 线性**转换，否则渲染严重发白（曾误把 sRGB 值直接塞进线性插槽）。

---

## 九、当前模型的真实完成度

| 项目 | 状态 | 说明 |
|---|---|---|
| 人体比例 | ✅ | 身高 1.68–1.83m，头身比约 7.5 |
| 面部 | ⚠️ 简化的 | 眼/眉/鼻/嘴/耳为独立体块，能辨认但无表情、无口型 |
| 服装 | ⚠️ 单层色块 | 衬衫/裤子/鞋按材质分区，无褶皱、无贴图 |
| 骨架与蒙皮 | ✅ | 20 骨骼真实蒙皮，形变无撕裂 |
| 动画 | ✅ 6 段 | idle/walk/turn/talk/sit/stand_up |
| 贴图 | ❌ 无 | 全部纯色材质（7 个材质槽/角色） |
| 面部表情 / 口型 | ❌ 无 | 需要 BlendShape，本阶段未做 |
| 手指动作 | ❌ 无 | 手是整体体块 |

**这不是写实照片级资产**，是「有真实骨架与动画的结构化低模人形」。
距离电影写实还缺：贴图/法线、面部 BlendShape、布料褶皱、头发面片、LOD。

---

## 十、下一步（若要继续提升）

1. **贴图**：给皮肤/布料做基础色 + 粗糙度贴图，UV 展开用 Smart UV Project 脚本化。
2. **面部**：加 BlendShape（眨眼/口型 8 个基础音素），Godot 侧用 `blend_shape` 驱动。
3. **头发**：改用面片 + alpha 贴图，替代现在的实心壳。
4. **LOD**：每个角色导出 3 级（全模 / 半模 / 低模），Godot 用 `visibility_range`。
5. **动作库扩充**：靠墙站、拿杯子、拥抱、争执——现有骨架可直接复用。
