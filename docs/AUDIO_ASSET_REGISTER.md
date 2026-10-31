# COMET 音频素材来源登记

本项目所有音频均为**程序合成的原创素材**，不含任何第三方音频、电影原声或未授权素材。

## 一、生成方式

全部由 Python 脚本直接合成 WAV（16-bit PCM / 22050 Hz / 单声道），用到的合成原语：

| 原语 | 用途 | 说明 |
| --- | --- | --- |
| `noise_burst` | 脚步、落地、开门 | 带指数衰减的滤波噪声 |
| `tone` | UI 音、交互音 | 衰减正弦 + 少量噪声 |
| `sweep` | 门的开合 | 频率扫描 |
| 低频噪声 + 正弦叠加 | 环境底噪、风声 | 一阶低通 + 缓慢起伏 |
| 调频正弦 | 现实切换低频涌动 | 52 Hz 附近缓慢调频 |

**没有任何素材来自网络下载、素材库、电影原声或他人作品。**

## 二、素材清单

| 文件 | 用途 | 时长 | 授权 |
| --- | --- | --- | --- |
| `footsteps/wood_1..3.wav` | 木地板脚步（3 变体防重复） | 0.11 s | 原创合成 |
| `footsteps/carpet_1..3.wav` | 地毯脚步 | 0.10 s | 原创合成 |
| `footsteps/outdoor_1..3.wav` | 室外地面脚步 | 0.13 s | 原创合成 |
| `movement/jump.wav` | 起跳 | 0.14 s | 原创合成 |
| `movement/land.wav` | 落地 | 0.20 s | 原创合成 |
| `doors/open.wav` | 开门 | 0.30 s | 原创合成 |
| `doors/close.wav` | 关门 | 0.26 s | 原创合成 |
| `interaction/examine.wav` | 检查物品 | 0.12 s | 原创合成 |
| `interaction/pickup.wav` | 拾取 | 0.14 s | 原创合成 |
| `ui/click.wav` | 界面点击 | 0.055 s | 原创合成 |
| `ui/confirm.wav` | 确认 | 0.12 s | 原创合成 |
| `ui/cancel.wav` | 取消 | 0.10 s | 原创合成 |
| `ambience/room_tone.wav` | 室内房间底噪（循环） | 3.0 s | 原创合成 |
| `ambience/wind.wav` | 室外风声（循环） | 3.0 s | 原创合成 |
| `anomaly/reality_shift.wav` | 现实切换 | 1.6 s | 原创合成 |

合计 21 个文件，约 434 KB。

## 三、授权结论

- 全部素材：**原创，可随项目自由分发**（与项目同为 MIT）。
- **无**电影原声、无 CC 素材、无网络下载、无音效库素材。
- 若后续引入外部配音或音乐，必须先在此登记来源与授权，再入库。

## 四、音量标准

| 类别 | 设置键 | 默认线性值 |
| --- | --- | --- |
| 总音量 | `master_volume` | 0.80 |
| 音乐 | `music_volume` | 0.55 |
| 环境 | `ambience_volume` | 0.70 |
| 音效/UI/脚步/交互 | `sfx_volume` | 0.80 |

最终音量 = `master_volume × category_volume`，由 `AudioManager.apply_volumes()` 落到每个播放器。
