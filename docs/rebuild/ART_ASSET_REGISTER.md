# 美术资源登记表

> 记录项目内每一个第三方或自生成资源。**没有登记的资源不得进入正式版本。**
> 最后更新：2026-11-01

---

## 一、授权总览

| 来源类型 | 数量 | 授权状态 |
|---|---|---|
| 项目自生成（Blender 脚本产出） | 7 个角色 GLB + 7 个 .blend 源工程 | 项目自有，随仓库分发 |
| 项目自生成（程序化几何体） | 全部家具/建筑/道具 | 项目自有 |
| 第三方模型 / 骨骼 / 动画 | **0** | — |
| 第三方贴图 | **0** | — |
| 音频 | 21 个 wav | ⚠️ **来源待核**，见第四节 |

**结论**：当前版本不含任何第三方 3D 资产。不涉及 CC-BY 署名、商业授权或再分发限制。

---

## 二、角色资产（自生成）

生成脚本：`tools/blender/build_character.py`
重生成命令见 `ART_ASSET_PIPELINE.md`。

| 角色 | GLB | 源工程 | 身高 | 体型系数 | 发型 | 袖型 | 面数（导出后） |
|---|---|---|---|---|---|---|---|
| Kevin | `kevin.glb` | `kevin.blend` | 1.79 m | 1.00 | short | rolled | ~16k tris |
| Mike | `mike.glb` | `mike.blend` | 1.76 m | 1.10 | short | short | ~16k tris |
| Lee | `lee.glb` | `lee.blend` | 1.66 m | 0.97 | long | long | ~17k tris |
| Beth | `beth.glb` | `beth.blend` | 1.68 m | 0.98 | long | long | ~17k tris |
| Hugh | `hugh.glb` | `hugh.blend` | 1.81 m | 1.02 | short | long | ~16k tris |
| Amir | `amir.glb` | `amir.blend` | 1.74 m | 0.98 | short | rolled | ~16k tris |
| Laurie | `laurie.glb` | `laurie.blend` | 1.70 m | 0.95 | long | long | ~17k tris |

每个角色：
- 网格 1 个（2002–2059 顶点，细分 1 级后导出）
- 材质 7 个（皮肤 / 头发 / 上衣 / 裤子 / 鞋 / 眼 / 嘴），全部纯色 Principled BSDF
- 骨架 20 根骨骼（19 形变）
- 动画 6 段（idle / walk / turn / talk / sit / stand_up）

**差异度检查**：7 人通过 `CHARACTERS` 配置表区分身高（1.66–1.81m）、体型（0.95–1.10）、
肤色、发色、上衣色、裤色、鞋色、发型（短/长）、袖型（短/卷/长）。
不存在「同一模型换颜色」——骨架与动画复用是刻意的（同一套制作规范），
但外观参数、身高、体型、发型、袖型都不同。

### 可编辑性

`assets/source/blender/*.blend` 为完整可编辑工程（含网格、骨架、权重、6 个 Action、
预览相机与三点布光），可直接在 Blender GUI 打开修改后重新导出。
修改外观不需要开 Blender——改脚本参数重跑即可。

---

## 三、程序化几何资产（自生成）

| 类别 | 生成位置 | 说明 |
|---|---|---|
| 建筑结构（墙/地板/天花/门/窗） | `tools/house/house_party.gd`、`tools/lib/geom.gd` | 全部 BoxMesh + 参数化 |
| 家具（沙发/餐桌/椅子/橱柜/床） | `tools/lib/props.gd`、`tools/house/house_furniture.gd` | 参数化组件 |
| 生活道具（杯/盘/书/蜡烛/花瓶） | `tools/house/house_furniture.gd` `_small_props()` | 小尺寸 BoxMesh |
| 灯光 | `tools/house/house_lighting.gd`、`tools/lib/light.gd` | 9 盏 OmniLight3D（α 供电 / β 停电两套变体） |
| 环境（WorldEnvironment） | `tools/lib/light.gd` `world_env()` | Filmic tonemap + 低强度环境光 |

这些不需要授权登记（纯代码生成，无外部素材）。

---

## 四、⚠️ 音频：来源待核

`assets/audio/` 下有 21 个 wav 文件（脚步声、开门、UI 点击、氛围音等）。

**现状：仓库内没有这些文件来源和授权的记录。** 在补上来源之前：

- 不得对外发布包含这些音频的构建
- 需要逐项确认：是自录、公共领域素材库（如 freesound CC0），还是来源不明

处置方式（待用户决定）：
1. 找出原始下载记录并补登记（来源 URL + 许可证）；
2. 或替换为 CC0 素材库资源并在此登记；
3. 或临时用代码生成的合成音（正弦/噪声包络）替代，彻底规避授权问题。

---

## 五、字体与 UI

| 资源 | 来源 | 授权 |
|---|---|---|
| 中文字体 | Godot 默认字体（系统字体回退） | 随 Godot 引擎，MIT |
| UI 图标 | 无（纯文字/色块） | — |

---

## 六、登记规则（后续新增资源必须遵守）

提交任何外部资源前，在本文件新增一行，至少包含：

| 字段 | 要求 |
|---|---|
| 资源名称 | 文件名 |
| 原始来源 | 完整 URL |
| 作者 / 发布者 | 可查证的署名 |
| 许可证 | 精确名称与版本（CC0-1.0 / CC-BY-4.0 / MIT / 商业授权…） |
| 是否允许修改 | 是 / 否 / 需注明 |
| 是否允许随游戏分发 | 是 / 否 |
| 是否要求署名 | 是（写在哪里）/ 否 |
| 商业使用限制 | 有 / 无 |

**不得**因为「能免费下载」就当作可打包分发。
**不得**在未确认许可证的情况下把资源合入 main 分支或发布构建。
