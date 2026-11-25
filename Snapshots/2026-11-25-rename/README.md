# Music Center for Mac 更名快照 · 2026-11-25

项目根目录已更名为 `/Users/luyufeng/Documents/Codex Projects/Music Center for Mac`。Xcode 工程及 scheme 为 `MusicCenterForMac.xcodeproj` / `MusicCenterForMac`；App 名称、窗口标题、版本提示、项目说明和三个隔离 QA 构建入口已同步更新。

应用：`Build/Music Center for Mac.app`。原构建与之前备份均保留。bundle ID `local.musiccenter.uirecreation`、Application Support 与缓存标识继续沿用，已有曲库/设置无需迁移。Windows 参考图、历史快照及其哈希清单保留原状；此前的 `Music Center UI Preview` 名称是历史记录。

实际验证：在新目录执行 Xcode Release 完整构建成功；构建 App 与本地安装副本均通过 `codesign --verify --deep --strict`；Info.plist 的应用名称、可执行名称和原 bundle ID 符合预期；三份 QA 脚本语法、新工程/scheme 引用与独立 QA 产品名替换检查通过；工程 `plutil -lint`、`git diff --check` 通过。

本次仅更名，没有重跑业务 smoke、GUI、音频和物理设备验收。构建仅报告没有 AppIntents 依赖的元数据提取提示。更名不表示第四项工具向导已经完成。

已有 `.agent/`、`HANDOFF.md` 和未提交内容整体保留，不混入此次产品提交。更名前检查点 `3634c5bf587c42e6976be0bd3aa8737a` 记录新路径。Chorotheia v1.0.0 的私有回执绑定旧绝对路径，改名后 `restore` 可读，但 `status` 报 ownership missing_or_changed；没有伪造回执或改写历史。需要工具后续提供受支持的目录迁移功能才能继续写入检查点。

Codex 当前项目显示名已为 Music Center for Mac，但关联仍指向旧目录；现有项目工具没有修改目录关联的能力，需在 Codex 重新选择新文件夹。GitHub 仓库地址不变。
