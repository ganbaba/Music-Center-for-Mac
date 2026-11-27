# ATRAC 向导 · 2026-11-27

第三项：将“工具 → 批量转化ATRAC”从直接选择文件导出 FLAC，改为按 Windows 原图组织的完整向导。支持介绍、扫描空态、AAC／FLAC 和原文件操作选项、空间预检、确认、实际转换、停止、完成及错误详情。[并排图集](gallery.html)、[逐项结果](matrix.md)、[截图与原图哈希](captures.json)。

本快照保存实现、音频回归和 **18 个实际界面状态**。FFmpeg 原生选择器的 Escape 取消、不可执行文件拒绝及错误返回均已补验通过。已有 17 张截图逐一核对哈希并保留，未重复执行原转换流程。

## 界面与实际行为

正常面板为 580×640 逻辑尺寸，按 ATRAC 原图调整字号、留白、单选框、字段和底部按钮。初始格式和原文件操作均未选择；两项选完才可继续。移动原文件时必须选目标目录。紧凑窗口保留正文滚动和固定底部按钮。确认页按 Return 不执行开始；空闲 Escape 关闭，运行中 Escape 不取消，停止使用显式按钮。

从真实 Mac 曲库扫描 OMA、AA3、AT3（扩展名不区分大小写）；普通文件和文件夹导入也支持这些后缀。格式由解码器实际验证，损坏或不支持的文件会在转换时列出错误。

AAC 复用现有本机编码流程，输出 256 kbps、44.1 kHz 双声道 M4A。FLAC 经 FFmpeg 解码为 24 位 PCM 后编码。转换文件保存在原音频所在文件夹，自动选择可用名称，避免覆盖既有文件。

成功后更新原曲目路径和时长，保留 ID、属性、播放历史及播放列表关系，并刷新队列路径。“勿移出原始文件夹”保留原音频；“移动至指定文件夹”先复制并校验，曲库路径提交成功后再移除原位置文件。同名原文件另取名称，现有目标保留。失败时清理本次未提交的转换文件和副本，保留源文件；若提交成功后原位置文件不能移除，会保留两处文件并给出实际路径说明。

## 依赖与差异

- 应用查找常见安装位置的 FFmpeg；没有找到时，继续配置会打开本机可执行文件选择窗口。不会自动安装、下载或修改系统 FFmpeg。
- 空间页使用真实 Mac 卷名、总容量和可用容量。剩余空间是包含解码、编码和暂存的保守估算，标注“约”；开始后逐文件重新检查。
- 进度按真正完成的文件数显示，并显示当前曲目。未复制 Windows 截图中的 100% 或伪造单文件字节百分比。
- 停止后保留已经完成的转换，当前未提交文件清理，未处理文件保留。失败、停止和解码器错误的 Mac 实测状态已单独记录；当前没有对应 Windows 实际转换失败、停止结果的完整原图，不能用 Windows 导入错误图代替。
- 原生文件夹／解码器选择器、字体渲染、动态路径与容量、进度计算方式仍与 Windows 存在平台差异。没有实现 Windows 曲库格式、Sony 专属解码或保护移除能力。

## 实际验证

最终生产及独立 QA 的 Release 构建、ad-hoc 严格签名验证、工程配置及 Git 差异检查通过。隔离 QA 中运行既有属性／备份／恢复回归，以及本轮 [ATRACSmoke](../../Tests/ATRACSmoke.swift)。结果见 [regression.txt](regression.txt) 和 [validation.txt](validation.txt)。

- 实际导入小写 OMA 和大写 OMA；真实转换 AAC、FLAC，均可重新读取音频；核对 AAC 音频时长。
- 将源 ATRAC 和转换后的 FLAC 分别解码为 24 位裸 PCM，逐字节比较相同。
- 核对保留源文件 SHA-256；移动后校验原文件副本一致，既有同名文件内容不变；原位置只在提交后移除。
- 曲目 ID、属性、真实重复播放列表条目保留，重开数据库后路径和时长一致。
- 损坏输入、已移出曲库的旧曲目提交失败、转换进程取消：源文件和数据库保留，本次未提交输出及副本清理。
- 从实际菜单操作并截图，核对空选择／空目标禁用、Return／Escape、AAC／FLAC 完成、空扫描、移动、停止、部分失败和详情、紧凑窗口，以及缺少解码器时的原生选择器取消、无效可执行文件拒绝和错误返回。实际结果见 [ui-audit.txt](ui-audit.txt)。

主采集在取得 17 个状态后，因测试脚本按中文“取消”查找英文 Cancel 而中止；脚本改用原生 Escape，随后因 Mac 锁屏暂缓。解锁后的独立补验已完成最后步骤，并取得第 18 张图。日志保留主采集失败和后续补验通过的真实记录，不将两次运行记作一次全流程通过。

所有操作使用临时 QA 曲库；未替换安装应用，未操作实际用户曲库。源音频、测试数据库、FFmpeg 二进制及构建产物不提交。

## 样例与复现

测试使用与 Windows 补采相同的公开 [FFmpeg ATRAC3plus 样例](https://samples.ffmpeg.org/A-codecs/ATRAC3%2B/at3p_sample1.oma)。测试解码器来自 [imageio-ffmpeg 项目](https://github.com/imageio/imageio-ffmpeg) 的 macOS ARM wheel，仅解包到临时目录；下载与二进制 SHA-256 见 [provenance.json](provenance.json)。命令行参数依据 [FFmpeg 文档](https://ffmpeg.org/ffmpeg.html)。这些文件不随应用分发。

```sh
python3 Tests/run-atrac-qa.py
```

上面命令构建并打印 `QA_APP`。以全新临时目录、ATRAC 样例、FFmpeg 和测试用限速解码器四个参数启动它，再执行共享控制程序与采集脚本：

```sh
qa_root=$(mktemp -d /private/tmp/music-center-atrac-ui.XXXXXX)
qa_control=$(mktemp -d /private/tmp/music-center-atrac-control.XXXXXX)
swiftc Tests/WizardsQAControl.swift -o "$qa_control/control"
open -na "$qa_app" --args "$qa_root" "$sample" "$decoder" "$slow_decoder"
# 应用启动后如未出现窗口，再带相同参数 open -a。
# 等 qa-result.txt 显示 PASS 后，从主界面开始：
python3 Tests/audit-atrac-ui.py "$qa_control" "$qa_root" "$qa_control/captures"
```

`qa_app`、`sample`、`decoder`、`slow_decoder` 应指向本次测试文件。`slow_decoder` 是只在 QA 使用的脚本，内容为 `exec /absolute/path/to/ffmpeg -readrate 4 "$@"`，仍执行真实解码；仅限制输入读取速度，使短暂运行状态可采集和停止。生产应用不使用限速器。实际测试的源文件约 21 秒、44.1 kHz 双声道；没有注入界面状态或替换转换结果。
