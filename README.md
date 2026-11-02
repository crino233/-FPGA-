# FPGA电子班牌

基于 HX4S20C 开发板和 EG4S20BG256 FPGA，使用 50 MHz 输入时钟，通过 HDMI 输出 640×480 图像及音频。支持图片轮播、滚动字幕、菜单设置、考试计时和应急模式。K1 短按显示当前可见图片的 BMP 源分辨率。

## 工程架构

顶层为 `src/app/top.v`，主要数据流如下：

```text
TF卡 → SPI读取与CRC校验 → FAT32文件访问
  ├─ BMP → 裁切与缩放 → SDRAM四槽缓存 → 读帧 → 字幕与菜单叠加 → HDMI
  ├─ TXT / 字库 → 文本解析与字形缓存 → 字幕叠加
  └─ WAV → PCM缓冲 → 配乐与提示音处理 → HDMI音频

按键与拨码开关 → 页面、播放与场景控制
菜单参数 ↔ Flash保存与恢复
```

| 模块 | 作用 |
| --- | --- |
| `photo_ingest.v`、`photo_fat32.v` | 文件访问、图片装载及音频读取调度 |
| `photo_image_scale.v` | BMP解析、居中裁切和缩放 |
| `photo_cache_control.v`、`photo_frame_loader.v`、`photo_frame_reader.v` | 图片缓存管理、SDRAM写入和显示读帧 |
| `photo_badge_input.v`、`photo_badge_control.v` | 按键、菜单及场景控制 |
| `photo_badge_overlay.v`、`photo_subtitle_*.v` | 菜单、分辨率提示和字幕显示 |
| `photo_audio_product.v`、`photo_wav_stream.v` | 提示音、配乐及PCM输出 |
| `photo_config_flash.v`、`photo_flash_record.v` | 参数保存与恢复 |

## 目录说明

| 路径 | 内容与用途 |
| --- | --- |
| `src/` | RTL、IP、字库初始化文件、约束和TD工程；构建必需 |
| `tools/` | 构建、仿真及素材生成脚本；建议保留 |
| `sim/` | 仿真源码、模型和测试素材；运行仿真时需要 |
| `release/` | 可下载位流、资源与时序报告；直接下载时使用 |
| `reference/` | 可选工程配置副本，不参与当前构建 |
| `requirements.txt` | Python工具依赖清单，不是RTL编译依赖 |

`sim/legacy/` 和 `sim/reference/` 为仿真依赖，与根目录的 `reference/` 用途不同。

`sim/tf_card/` 保存图片、音频、字库和文本素材。`sim/fixtures/` 保存字幕测试输入；缩放测试图片运行时生成到 `sim/work/`。

## 工具脚本

| Python脚本 | 用途 |
| --- | --- |
| `make_badge_font.py` | 生成菜单及状态提示字库 |
| `make_subtitle_rom.py` | 生成内置字幕字库和示例文本 |
| `make_subtitle_font.py` | 生成TF卡字库 `FONT16.BIN` 及字体测试输入 |
| `prepare_badge_audio.py` | 生成WAV测试数据，可转换输入音频 |
| `prepare_image_scale_demo.py` | 生成不同尺寸的BMP测试图片及缩放比对数据 |

这些脚本运行在电脑上。使用现有字库和位流时不需要执行；生成素材或运行仿真时，可用 `python -m pip install -r requirements.txt` 安装 Pillow 和 NumPy。音频格式转换另需 FFmpeg。

## 构建与仿真

TD工程入口：`src/td_project/anlu_hdmi.al`。使用安路TD 6.2，在TD命令行执行：

```tcl
source {工程完整路径/tools/build.tcl}
```

构建输出位于 `build/`。使用ModelSim运行仿真时，在工程根目录执行，并替换为本机工具路径：

```powershell
./tools/simulate.ps1 -model_bin 'ModelSim安装目录/win64' -td_root 'TD安装目录'
```

位流为 `release/anlu_hdmi.bit`，资源和时序报告位于 `release/reports/`。
