# 备份恢复逐状态视觉验收 · 2026-11-27

第二项：逐状态对照已采集的 Windows 原图，修正 Mac 备份和恢复向导，并保存实际操作证据。20 个状态见[并排图集](gallery.html)和[逐项结果](matrix.md)，原图路径、SHA-256 与显示裁剪范围见 [captures.json](captures.json)。

## 本轮修改

- 两个向导统一为 640×640 逻辑尺寸、60 高标题区、50 左边距；主次按钮统一 120×32，浏览按钮 80×32，输入框高 32。
- 备份配置按原版恢复说明、容量、路径、名称及备注的顺序和间距；首次名称为空。名称超过 32 字符时不能继续。
- 恢复保留日期、备注、两种地址选择及对应目录控件，确认页恢复原版信息层级。完成页简化为原版完成提示，恢复前备份路径仍可在文字和确定按钮的提示中查看。
- 按原图调整介绍、确认、实际进度、完成和错误页；恢复帮助链接打开真实的 Mac 备份说明。
- 修复空闲向导 Escape 不关闭的问题。运行中禁用关闭，备份写入需显式点击停止；备份与恢复确认页的 Return 不会执行开始。
- 紧凑窗口缩短正文视口并滚动，保持底部按钮可见。恢复进度页保留停止按钮的位置，目前禁用。
- 新增独立 QA 入口、限定 QA 应用的辅助控制程序，以及可重跑的实际操作与截图脚本。

## 实际验证

生产 Release 构建、ad-hoc 严格签名验证、工程配置检查及 `git diff --check` 通过。独立 QA Release 构建通过，在新建临时曲库运行回归得到 [PASS](regression.txt)。

通过真实菜单进入两个生产向导，完成 20 个截图状态。空配置禁用下一步、33 字符名称校验、多行备注实际写入、确认页 Return 保护、空闲 Escape 关闭、备份/恢复运行中 Escape 保持运行、恢复停止按钮禁用，以及紧凑窗口均通过。操作日志见 [ui-audit.txt](ui-audit.txt)。恢复介绍页帮助入口另经实际点击并读取说明验证。

真实备份生成后重新打开 SQLite 核对 3 首曲目和备注；真实恢复后核对 3 首曲目。确认之后才制造临时路径冲突，分别触发备份写入失败和恢复运行失败，验证错误返回及阻挡文件原内容保留。

既有回归同时验证：旧备份、损坏备份、预览后被修改的备份拒绝、恢复前自动备份、设置写入失败的数据库回滚、指定目录的同名音频独立复制、内容逐字节一致、路径重开后持久化、播放列表条目 ID 保留、源音频缺失和目的地失效时不覆盖当前数据，失败时清理本次副本。测试使用生成的 WAV，不触及实际用户曲库。

## 仍有的差异与参考缺口

这些差异已在图集中记录，不能将本轮称为整个产品的像素级一致验收：

- Mac 使用 `.musiccenterbackup` 文件，Windows 原版选择备份目录；文件/目录选择器使用 macOS 原生窗口。Mac 备份保存数据库和设置，音频仍引用原路径，指定文件夹恢复要求源音频可读取。
- Mac 显示真实数据量和运行阶段，进度条使用不定进度。没有复用 Windows 截图中的 72% 或 100%。恢复运行图实际停在“正在保存恢复前备份”，与 Windows 的应用数据阶段不同。
- Windows 恢复运行页有可用的停止按钮；Mac 当前恢复流程不能安全中止，按钮保留但禁用。停止后的确认及部分结果状态尚无完整 Windows 参考，仍待补采和实现；本轮未声称验证这些行为。
- Windows 无效备份参考由无效目录触发，Mac 使用损坏文件；运行失败截图也来自各平台实际的不同失败原因，因此错误内容不强行照搬。
- `01-backup/02-searching.jpg` 文件名虽然包含 searching，实际画面为“备份数据搜索已完成”。本轮单独保存 Mac 正在搜索图并标明原图缺失。
- 字体渲染、动态日期/路径/数据量、运行指示器及紧凑滚动条存在平台或测试数据差异。正文中的 Mac 格式和范围说明保留事实表述。

所有 Mac 图来自隔离 QA 中的生产视图，只裁剪向导区域并编码为 JPEG（质量 85）；未注入界面状态。为抓取短暂的搜索、写入和恢复前备份阶段，脚本在临时 QA 数据库上持有约 2.2 秒独占锁，随后释放并等待操作真实完成。Windows 原文件未修改，图集通过 CSS 显示其面板区域；点击可看完整原图。

本轮未替换已安装应用。ATRAC 向导属于后续第三项。

## 重跑

在有 Xcode、辅助功能及屏幕录制权限的本机运行以下命令。QA 使用独立 bundle ID、临时曲库和临时设置，不指向实际曲库。脚本要求全新临时根目录、回归 PASS 和初始主界面；运行时不要操作测试窗口。

```sh
python3 Tests/run-wizards-qa.py > /private/tmp/music-center-wizards-build.log 2>&1
qa_app=$(sed -n 's/^QA_APP=//p' /private/tmp/music-center-wizards-build.log)
qa_root=$(mktemp -d /private/tmp/music-center-wizards-recheck.XXXXXX)
qa_control=$(mktemp -d /private/tmp/music-center-wizards-control.XXXXXX)
swiftc Tests/WizardsQAControl.swift -o "$qa_control/control"
open -na "$qa_app" --args "$qa_root"
open -a "$qa_app"
python3 - "$qa_root" <<'PY'
from pathlib import Path
import sys, time
result = Path(sys.argv[1]) / 'qa-result.txt'
for _ in range(80):
    if result.exists():
        text = result.read_text()
        assert text.startswith('PASS'), text
        print(text)
        break
    time.sleep(.25)
else:
    raise SystemExit('QA result missing')
PY
python3 Tests/audit-wizards-ui.py "$qa_control" "$qa_root" "$qa_control/captures"
```

首次打开若未出现窗口，再执行 `open -a "$qa_app"`。构建输出中的 `QA_APP` 是本次临时应用路径；采集结果保存在最后命令指定的 `captures` 中，临时数据库和应用不属于提交内容。
