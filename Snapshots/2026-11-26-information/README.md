# 系统信息与版本信息 · 2026-11-26

第四项先完成两个只读窗口；备份、恢复和 ATRAC 向导继续待办。本次没有执行备份、恢复或转换。

[14 张验收图](gallery.html) · [文件 SHA-256](manifest.json) · [实际验证](validation.txt)

## 完成内容

- 从生产“帮助 → 系统信息 / 版本信息”进入独立白色面板。沿用 Windows 参考的居中标题、关闭按钮、内容区域、固定底部按钮和金色确认按钮；窗口最高 600pt、宽 650pt，紧凑窗口缩短滚动视口。滚动条与上下箭头复用现有 Windows 风格控件。
- 系统信息读取当前 macOS、架构、CPU、内存、制造商和硬件型号、启动磁盘容量、光驱、用户语言/区域及本地网络接口状态。未能读取的 CPU 频率等显示“—”；查询失败与已知未检测到的状态分别处理。每次打开重新读取，关闭后不保留上次复制提示。
- 系统信息后台读取，仅查询用户主目录所在文件系统容量与设备元数据；不枚举或打开外置卷，不扫描用户文件，不联网探测。网络接口活动不冒充互联网可达。复制按钮复制全部内容，包含滚动视口之外的内容。
- Mac 版本从实际 Info.plist 读取，本轮配置为 **0.1.0（构建 1）**；Windows 参考明确标为 Music Center for PC 2.7.4。缺失或错误类型的版本值显示未知，不用 Windows 版本填充。
- 版本页沿用分段标识/说明和滚动排版。Mac 平台组件与 Windows 参考技术分开说明；Gracenote、DSEE HX、ASIO、Electron 等没有被标成 Mac 版已集成。参考标识采用文字排版及原生符号，并非逐像素复制 Windows 商标位图或原版版权页；显示的是适合当前 Mac 应用的内容。
- 面板打开时阻止底层曲库操作及导入快捷键；支持回车、Escape、确定和右上角关闭。

## 实际执行的验证

- 在真实项目新路径运行 Xcode Release 完整构建，结果 BUILD SUCCEEDED。构建 App 和安装副本均通过 codesign --verify --deep --strict；Info.plist 的实际版本为 0.1.0 / 1。
- 隔离 QA 使用生产 PrototypeView、帮助菜单和 InformationPanel，独立 SQLite 与设置目录，不编辑用户曲库。启动 InformationSmoke 通过：真实系统版本/物理内存、未知与未检测到的网络状态、未探测互联网、缺失/空白/错误类型版本、参考版本分离及完整文本。
- 桌面实际测试：两个帮助菜单入口；正常和 800×558pt 紧凑窗口；系统及版本页顶部/底部；滚轮及向上箭头；固定底部按钮；深色背景；回车、Escape、关闭按钮及确定；关闭再打开时复制状态重置；窗口打开时 Ctrl+O 不启动导入。
- 在紧凑系统信息窗口点击复制，验证剪切板内容包含不可见的末尾“互联网连通性：未测试”；随后恢复原剪切板全部已保存条目和数据类型，临时副本已删除。
- 正式安装 App 实测两个入口、实际产品名与版本号、版本页滚动到底及关闭。12–14 为正式 App 原图；01–11 为隔离 QA。磁盘空闲空间随系统运行变化，不作为 Windows 固定值复制。
- 工程 plutil、Python QA 入口语法及 git diff --check 通过。没有为这次只读面板改动重跑无关的音频、设备、备份恢复或全部业务 smoke。

复现：运行 `python3 Tests/run-information-qa.py`，打开输出的 QA App 后执行启动检查，并通过真实帮助菜单验收。只执行构建脚本不等于 smoke 已运行。

## 参考与本地 App

Windows 参考：[系统信息](../../Reference-Windows-2026-11-24/capture/06-dialogs/system-information.jpg)、[系统信息底部](../../Reference-Windows-2026-11-24/capture/06-dialogs/system-information-bottom.jpg)、[版本信息](../../Reference-Windows-2026-11-24/capture/06-dialogs/about-version.jpg)、[版本信息底部](../../Reference-Windows-2026-11-24/capture/06-dialogs/about-version-bottom.jpg)。原图保持不变。

本地 App：`Build/Music Center for Mac.app`。上一版：`Build/Previous-information-2026-11-26.app`。本地构建、临时曲库、剪切板备份及既有未提交记忆不上传。本轮曾因自动审批服务用量限制暂停，恢复后已完成所需构建与复制验收；没有绕过权限检查。
