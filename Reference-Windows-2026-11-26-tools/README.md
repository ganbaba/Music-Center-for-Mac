# Windows 工具向导补采 · 2026-11-26

本阶段保存 **39 张 Windows 实机原始 JPEG**，补充 2026-11-24 Reference 未执行的备份与 ATRAC 流程。来源为 Lucas 远程桌面中的 Music Center for PC 2.7.4 中文界面；没有 Mac 重建界面或生成图片。**恢复实际执行尚待用户确认，本轮不是全覆盖完成。**

[截图目录](index.html) · [覆盖与待补项](COVERAGE.md) · [操作与环境变动](SIDE_EFFECTS.md) · [原图索引](capture-index.json) · [校验和](CHECKSUMS.sha256)

| 请求范围 | 本阶段结果 |
| --- | --- |
| 备份实际执行与完成 | 已采集 baseline 搜索、配置、开始、实际进度与完成；备份 0.1GB |
| 备份实际执行失败 | 已采集点击开始后的写入失败弹窗及确认后的返回页；用独立空文件与目标备份目录冲突触发 |
| 恢复执行与完成 | 已读取有效 baseline 的日期和最终开始页；尚未点击开始，等待覆盖恢复的执行时确认 |
| 恢复失败 | 已采集无效目录的路径验证错误；不能冒充实际运行失败 |
| ATRAC 找到文件后的格式选项 | 已采集初始、AAC、FLAC、保留原文件、移动选项启用状态、磁盘空间确认页 |
| ATRAC 转换进度与结果 | AAC 与 FLAC 均实际转换成功；FLAC 连续截图捕获正在转换的100%进度页及金色填充变化 |

## 原图完整性

`capture/` 下文件逐字节复制桌面工具返回的原始 JPEG，未裁切、缩放、补画或重压缩。全部为2732×1536。连续拍摄的重复帧只选取能代表实际状态的原图；同一100%进度的不同填充状态不计作不同业务阶段。精确 SHA-256、字节数、原始来源文件名、时间和选取的连续帧见索引。

原图包含 Lucas 标题栏、Windows 任务栏及远程指针光晕，它们不是 Music Center 控件。目录页面仅按 CSS 缩放显示，点击打开原图。无音频样例、曲库数据库、完整备份、剪切板内容或工具二进制上传。

## 样例来源与实际兼容性

样例取自 [FFmpeg OMA 样例目录](https://samples.ffmpeg.org/oma/) 和 [FFmpeg ATRAC3plus 样例目录](https://samples.ffmpeg.org/A-codecs/ATRAC3%2B/)。本机实测：`03-Exdous.oma` 被原版以 -24663“文件受版权保护，无法导入”拒绝；`at3p_sample1.oma` 成功导入，并分别转换为 AAC、FLAC。前者的导入错误不属于转换失败结果，也不推断所有 OMA 都有相同限制。没有移除或绕过版权保护。

本阶段只新增参考资料，未改 Mac 应用源码，也未重跑 Mac 构建或业务 smoke。此前系统信息、版本信息的实现与测试记录见 [只读窗口快照](../Snapshots/2026-11-26-information/README.md)。原有 [209 张 Windows Reference](../Reference-Windows-2026-11-24/README.md) 保持原样。
