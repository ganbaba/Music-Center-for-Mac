import SwiftUI

struct AdditionalSettings: View {
    let page: SettingsPage
    @Binding var settings: PreviewSettings
    let cdDrives: [AudioCDDrive]
    let refreshCDDrives: () -> Void
    let explain: (String) -> Void
    @State private var selectedFolder: String?

    var body: some View {
        SettingsScroll {
            Group {
                switch page {
                case .importFiles: importSettings
                case .cd: cdSettings
                case .metadata: metadataSettings
                case .share: sharingSettings
                case .update: updateSettings
                case .other: otherSettings
                default: EmptyView()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, page == .cd ? 26 : 24)
            .padding(.bottom, 8)
        }
    }

    private var importSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("自动导入文件夹设置")
            Text("将文件夹设置为执行自动导入。")
            check("[音乐]文件夹").padding(.leading, 8).padding(.top, 8)
            SettingsScroll {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(settings.autoImportFolders, id: \.self) { folder in
                        Button { selectedFolder = folder } label: {
                            Text(folder).lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                                .padding(.horizontal, 6)
                                .background(selectedFolder == folder ? Color(white: 0.87) : .white)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(1).frame(height: 120).border(SettingsStyle.ink)
            HStack(spacing: 12) {
                SettingsAction("添加文件夹…", width: 128, action: chooseImportFolder)
                SettingsAction("删除", width: 128) {
                    settings.autoImportFolders.removeAll { $0 == selectedFolder }
                    selectedFolder = nil
                }.disabled(selectedFolder == nil)
            }
            heading("文件目的地").padding(.top, 24)
            Text("在Music Center for PC中管理的内容将保存在以下目标文件夹。")
            Text(settings.importDestination.path)
                .textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                .border(SettingsStyle.ink)
            HStack(spacing: 12) {
                SettingsAction("浏览…", width: 128, action: chooseDestination)
                SettingsAction("恢复默认", width: 128) {
                    settings.cdImportDirectory = nil
                }
            }
        }
        .frame(maxWidth: 342, alignment: .leading)
    }

    private var cdSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("导入CD数据的光驱")
            SettingsDropdown(title: "光驱", selection: $settings.cdDriveID,
                options: cdDriveOptions)
                .frame(width: 200).padding(.top, 8)
                .onAppear(perform: refreshCDDrives)
            heading("CD插入光驱后的操作").padding(.top, 32)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(CDInsertionBehavior.allCases) { behavior in
                    SettingsRadio(behavior.label, selected: settings.cdInsertionBehavior == behavior) {
                        settings.cdInsertionBehavior = behavior
                    }
                }
            }.padding(.leading, 8).padding(.top, 12)
            heading("CD导入开始和结束时的操作").padding(.top, 36)
            check("CD导入结束时自动弹出").padding(.leading, 8).padding(.top, 16)
            heading("CD导入设置").padding(.top, 36)
            Text("从CD导入歌曲时设置文件格式。").padding(.top, 8)
            cdFormatControls.padding(.top, 8)
        }
    }

    private var cdDriveOptions: [SettingsDropdownOption<String?>] {
        guard !cdDrives.isEmpty || settings.cdDriveID != nil else { return [] }
        var options = [SettingsDropdownOption<String?>(value: nil, title: "自动选择")]
        options += cdDrives.map { SettingsDropdownOption(value: Optional($0.id), title: $0.name) }
        if let id = settings.cdDriveID, !cdDrives.contains(where: { $0.id == id }) {
            options.append(SettingsDropdownOption(value: id, title: "光驱暂不可用", enabled: false))
        }
        return options
    }

    private var cdFormatControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            cdRow("格式") {
                SettingsDropdown(title: "格式", selection: $settings.cdFormat,
                    options: AudioExportFormat.allCases.map { SettingsDropdownOption(value: $0, title: $0.rawValue) })
            }
            cdRow("比特率") {
                if settings.cdFormat.usesBitrate {
                    SettingsDropdown(title: "比特率", selection: $settings.cdBitrate,
                        options: settings.availableCDBitrates.map { SettingsDropdownOption(value: $0, title: "\($0) kbps") })
                } else {
                    SettingsDropdown(title: "比特率", selection: .constant(settings.cdFormat == .wav ? "1411 kbps" : "平均 950 kbps"),
                        options: [SettingsDropdownOption(value: settings.cdFormat == .wav ? "1411 kbps" : "平均 950 kbps",
                            title: settings.cdFormat == .wav ? "1411 kbps" : "平均 950 kbps")])
                }
            }
            Text(capacityEstimate).padding(.leading, 108)
            Text("值越高，音质越好，但导入歌曲所需的数据容量也会增加。")
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 108)
            cdRow("导入模式：") {
                SettingsDropdown(title: "导入模式", selection: $settings.cdImportMode,
                    options: CDImportMode.allCases.map { SettingsDropdownOption(value: $0, title: $0.label) })
                    .disabled(!settings.cdFormat.usesBitrate)
            }
        }
        .frame(width: 406, alignment: .leading)
    }

    private func cdRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 96, alignment: .leading)
            content().frame(maxWidth: .infinity)
        }
    }

    private var capacityEstimate: String {
        let value: String
        switch settings.cdFormat {
        case .wav: value = "807.4"
        case .flac: value = "543.5"
        case .aac, .mp3:
            value = (Double(settings.cdBitrate) * 1000 / 8 * 80 * 60 / 1_048_576)
                .formatted(.number.precision(.fractionLength(1)))
        }
        return "每张CD的数据容量：\(value)MB (80 分钟)"
    }

    private var metadataSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("获取歌曲信息")
            Text("备注：获取歌曲信息需要连接互联网")
            check("自动检索歌曲信息/执行12 Tone Analysis").padding(.leading, 8)
            Text("如果以下信息不可用，则将进行自动检索。（不会覆盖现有信息。）")
                .padding(.leading, 40)
            VStack(alignment: .leading, spacing: 8) {
                check("歌曲信息，例如歌曲名称、类型以及发行年份", initial: true)
                check("封面图样", initial: true)
                check("12 TONE ANALYSIS", initial: true)
            }
            .padding(.leading, 48)
            .disabled(!flag("自动检索歌曲信息/执行12 Tone Analysis"))
            heading("歌曲信息的获取时间").padding(.top, 36)
            check("CD插入光驱时，自动获取CD信息和封面图样", initial: true)
                .padding(.leading, 8).padding(.top, 8)
            heading("Gracenote音乐识别服务").padding(.top, 36)
            Text("设置Gracenote音乐识别服务的语言。")
            HStack(spacing: 12) {
                Text("已设置语言").frame(width: 80, alignment: .leading)
                SettingsDropdown(title: "已设置语言", selection: $settings.recognitionLanguage,
                    options: (PreviewSettings.recognitionLanguages + (PreviewSettings.recognitionLanguages.contains(settings.recognitionLanguage) ? [] : [settings.recognitionLanguage])).map { SettingsDropdownOption(value: $0, title: $0) })
                    .frame(width: 200)
            }
            heading("清空识别结果数据").padding(.top, 36)
            Text("先前的识别结果数据已删除，硬盘空间扩大。")
            HStack { Spacer(); SettingsAction("删除") { explain("Gracenote 音乐识别服务尚未接入，当前没有可清除的识别结果数据。") } }
                .padding(.trailing, 24)
        }
    }

    private var sharingSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("分享我的数据库")
            check("与本地网络设备分享注册到我的数据库中的歌曲").padding(.leading, 8).padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("数据库名称:").frame(width: 92, alignment: .leading)
                    TextField("", text: selection("数据库名称", "Music Center"))
                        .textFieldStyle(.plain).padding(.horizontal, 6).frame(width: 200, height: 26)
                        .background(.white).border(SettingsStyle.heading)
                        .accessibilityLabel("数据库名称")
                }.padding(.top, 8)
                check("自动允许新设备访问我的数据库", initial: true).padding(.top, 8)
                check("使用当前应用语言显示内容分类", initial: true)
                Text("高解析度流媒体").padding(.leading, 32)
                Text("低网速播放高解析度流媒体音源时可能导致播放中断。如果发生这种播放问题，降低音频流质量到CD水平。")
                    .fixedSize(horizontal: false, vertical: true).padding(.leading, 32)
                check("降低高解析度音源的音质到CD水平")
            }
            .padding(.leading, 8)
            .disabled(!flag("与本地网络设备分享注册到我的数据库中的歌曲"))
            .foregroundStyle(flag("与本地网络设备分享注册到我的数据库中的歌曲") ? SettingsStyle.ink : Color(white: 0.75))
        }
    }

    private var updateSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("自动软件更新")
            Text("启动时通过互联网连接服务器，自动检查Music Center for PC和连接设备的软件更新信息。\n如果最新更新信息可用，则进行更新。")
                .fixedSize(horizontal: false, vertical: true)
            check("启动Music Center for PC时，自动检查更新信息。", initial: true)
                .padding(.leading, 8).padding(.top, 8)
            Text("注：\n必须连接互联网检查软件更新情况。\nMusic Center正在检查更新情况时将不会分享您的信息。")
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                Text("更新检查频率")
                ForEach(["每周", "每日", "每次启动时"], id: \.self) { value in
                    SettingsRadio(value, selected: selection("更新检查频率", "每周").wrappedValue == value) {
                        settings.choices["更新检查频率"] = value
                    }.padding(.leading, 8)
                }
            }
            .padding(.leading, 40)
            .disabled(!flag("启动Music Center for PC时，自动检查更新信息。", initial: true))
            heading("手动软件更新").padding(.top, 36)
            Text("立即检查Music Center for PC和连接设备的软件更新信息。")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                SettingsAction("检查软件更新…", width: 112) {
                    explain("Sony 软件更新服务尚未接入。")
                }
            }
        }
    }

    private var otherSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("音效")
            check("歌曲从CD完全导入并传输到设备后，将播放通知声音。", initial: true)
                .padding(.leading, 8).padding(.top, 8)
            heading("清空播放历史").padding(.top, 36)
            Text("清空全部歌曲播放历史信息。")
            HStack { Spacer(); SettingsAction("清空") { explain("暂不支持从这里清空播放历史。") } }
                .padding(.trailing, 76)
            heading("删除临时文件").padding(.top, 24)
            Text("删除传输中创建的文件和临时文件，增加硬盘空间。")
            HStack { Spacer(); SettingsAction("删除") { explain("暂不支持从这里删除传输缓存或临时文件。") } }
                .padding(.trailing, 76)
        }
    }

    private func heading(_ label: String) -> some View { Text(label).foregroundStyle(SettingsStyle.heading) }
    private func check(_ title: String, initial: Bool = false) -> some View {
        SettingsCheck(title, isOn: Binding(get: { flag(title, initial: initial) }, set: { settings.flags[title] = $0 }))
    }
    private func flag(_ title: String, initial: Bool = false) -> Bool { settings.flags[title] ?? initial }
    private func selection(_ title: String, _ initial: String) -> Binding<String> {
        Binding(get: { settings.choices[title] ?? initial }, set: { settings.choices[title] = $0 })
    }
    private func chooseImportFolder() {
        chooseFolder(title: "选择自动导入文件夹", initial: nil) { folder in
            if !settings.autoImportFolders.contains(folder.path) { settings.autoImportFolders.append(folder.path) }
            selectedFolder = folder.path
        }
    }
    private func chooseDestination() {
        chooseFolder(title: "选择文件目的地", initial: settings.importDestination) { folder in
            settings.cdImportDirectory = folder
        }
    }
    private func chooseFolder(title: String, initial: URL?, selected: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = initial
        panel.prompt = "选择文件夹"
        panel.begin { response in if response == .OK, let folder = panel.url { selected(folder) } }
    }
}

extension PreviewSettings {
    static let recognitionLanguages = ["德语", "英语", "西班牙语", "芬兰语", "法语", "意大利语", "日语", "朝鲜语",
        "荷兰语", "波兰语", "葡萄牙语", "俄语", "瑞典语", "土耳其语", "简体中文", "繁体中文"]

    var recognitionLanguage: String {
        get {
            let original = choices["识别语言"] ?? "繁体中文"
            return ["English": "英语", "日本語": "日语", "繁體中文": "繁体中文"][original] ?? original
        }
        set { choices["识别语言"] = newValue }
    }

    var autoImportFolders: [String] {
        get {
            guard let raw = choices["自动导入文件夹"], let data = raw.data(using: .utf8),
                  let folders = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return folders
        }
        set {
            choices["自动导入文件夹"] = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
    var importDestination: URL {
        cdImportDirectory ?? FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
            .appending(path: "Music Center", directoryHint: .isDirectory)
    }
}
