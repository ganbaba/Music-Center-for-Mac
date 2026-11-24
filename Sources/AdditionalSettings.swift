import SwiftUI

struct AdditionalSettings: View {
    let page: SettingsPage
    @Binding var settings: PreviewSettings
    let gold: Color
    let cdDrives: [AudioCDDrive]
    let refreshCDDrives: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch page {
                case .importFiles:
                    heading("自动导入文件夹设置")
                    Text("将文件夹设置为执行自动导入。")
                    check("[音乐]文件夹")
                    box("", height: 116)
                    HStack { unavailable("添加文件夹…"); unavailable("删除") }
                    heading("文件目的地")
                    Text("原型曲库记录引用导入文件的位置。")
                    box("MusicCenterUIRecreation", height: 70)
                    HStack { unavailable("浏览…"); unavailable("恢复默认") }
                case .cd:
                    cdSettings
                case .metadata:
                    heading("获取歌曲信息")
                    Text("备注：获取歌曲信息需要连接互联网")
                    check("自动检索歌曲信息/执行12 Tone Analysis")
                    Text("如果以下信息不可用，则将进行自动检索。")
                    VStack(alignment: .leading) {
                        check("歌曲信息，例如歌曲名称、类型以及发行年份", initial: true)
                        check("封面图样", initial: true)
                        check("12 TONE ANALYSIS", initial: true)
                    }.padding(.leading, 24).disabled(!flag("自动检索歌曲信息/执行12 Tone Analysis"))
                    heading("歌曲信息的获取时间")
                    check("CD插入光驱时，自动获取CD信息和封面图样", initial: true)
                    heading("Gracenote音乐识别服务")
                    options("已设置语言", ["繁体中文", "简体中文", "日本語", "English"], selection("识别语言", "繁体中文"))
                    heading("清空识别结果数据")
                    unavailable("删除")
                case .share:
                    heading("分享我的数据库")
                    let sharing = "与本地网络设备分享注册到我的数据库中的歌曲"
                    check(sharing)
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("数据库名称：", text: selection("数据库名称", "Music Center"))
                        check("自动允许新设备访问我的数据库", initial: true)
                        check("使用当前应用语言显示内容分类", initial: true)
                        heading("高解析度流媒体")
                        check("降低高解析度音源的音质到CD水平")
                    }.disabled(!flag(sharing))
                case .update:
                    heading("自动软件更新")
                    Text("启动时连接服务器，检查 Music Center for PC 和连接设备的软件更新。")
                    check("启动Music Center for PC时，自动检查更新信息。", initial: true)
                    heading("更新检查频率")
                    radio(["每周", "每日", "每次启动时"], selection("更新检查频率", "每周"))
                    heading("手动软件更新")
                    unavailable("检查软件更新…")
                case .other:
                    heading("音效")
                    check("歌曲从CD完全导入并传输到设备后，将播放通知声音。", initial: true)
                    heading("清空播放历史")
                    Text("清空全部歌曲播放历史信息。")
                    unavailable("清空")
                    heading("删除临时文件")
                    Text("删除传输中创建的文件和临时文件，增加硬盘空间。")
                    unavailable("删除")
                case .display, .columns, .playback, .transfer, .output:
                    EmptyView()
                }
                if page != .cd {
                    Text("此页设置为界面预览").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        }
        .frame(maxHeight: 580)
    }

    private var cdSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("导入CD数据的光驱")
            CDDrivePicker(selection: $settings.cdDriveID, drives: cdDrives, refresh: refreshCDDrives)
                .frame(width: 200, height: 26)

            heading("CD插入光驱后的操作")
                .padding(.top, 12)
            radio(CDInsertionBehavior.allCases.map(\.label), Binding(
                get: { settings.cdInsertionBehavior.label },
                set: { label in
                    if let behavior = CDInsertionBehavior.allCases.first(where: { $0.label == label }) {
                        settings.cdInsertionBehavior = behavior
                    }
                }
            ))
            if settings.cdInsertionBehavior == .importDisc {
                Button("选择自动导入位置…", action: chooseCDImportDirectory)
                if let directory = settings.cdImportDirectory {
                    Text(directory.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            heading("CD导入开始和结束时的操作")
                .padding(.top, 12)
            check("CD导入结束时自动弹出")
                .padding(.leading, 6)

            heading("CD导入设置")
                .padding(.top, 12)
            Text("从CD导入歌曲时设置文件格式。")
            cdFormatControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cdFormatControls: some View {
        let canEncodeMP3 = AudioCommand.ffmpeg != nil
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("格式")
                Menu {
                    ForEach(AudioExportFormat.allCases) { format in
                        Button { settings.cdFormat = format } label: {
                            if settings.cdFormat == format {
                                Label(format.rawValue, systemImage: "checkmark")
                            } else {
                                Text(format.rawValue)
                            }
                        }
                        .disabled(format == .mp3 && !canEncodeMP3)
                    }
                } label: {
                    Text(settings.cdFormat.rawValue)
                }
                .accessibilityLabel("格式")
                .accessibilityValue(settings.cdFormat.rawValue)
            }
            if settings.cdFormat == .mp3, !canEncodeMP3 {
                cdFormatHint(AudioCommand.mp3Requirement)
            }
            if settings.cdFormat.usesBitrate {
                GridRow {
                    Text("比特率")
                    Picker("比特率", selection: $settings.cdBitrate) {
                        ForEach(PreviewSettings.cdBitrates, id: \.self) { bitrate in
                            Text("\(bitrate) kbps").tag(bitrate)
                        }
                    }
                    .labelsHidden()
                }
            }
            cdFormatHint(capacityEstimate)
            if settings.cdFormat.usesBitrate {
                cdFormatHint("值越高，音质越好，但导入歌曲所需的数据容量也会增加。")
            }
            GridRow {
                Text("导入模式")
                Picker("导入模式", selection: $settings.cdImportMode) {
                    ForEach(CDImportMode.allCases) { mode in Text(mode.label).tag(mode) }
                }
                .labelsHidden()
            }
            if settings.cdImportMode == .verifySource {
                cdFormatHint("转换前复制并比对光盘源文件。")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cdFormatHint(_ title: String) -> some View {
        GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            Text(title)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capacityEstimate: String {
        let size = (Double(settings.estimatedCDBytes) / 1_048_576).formatted(.number.precision(.fractionLength(1)))
        if settings.cdFormat == .flac { return "每张CD的参考数据容量 \(size) MiB（80 分钟，未压缩 PCM）" }
        return "每张CD的数据容量 \(size) MiB（80 分钟）"
    }

    private func chooseCDImportDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择 CD 自动导入位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.cdImportDirectory
        panel.prompt = "选择"
        panel.begin { response in
            if response == .OK { settings.cdImportDirectory = panel.url }
        }
    }

    private func heading(_ label: String) -> some View {
        Text(label).foregroundStyle(.secondary).padding(.top, 5)
    }

    private func radio(_ values: [String], _ selected: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(values, id: \.self) { value in
                Button { selected.wrappedValue = value } label: {
                    Label(value, systemImage: selected.wrappedValue == value ? "largecircle.fill.circle" : "circle")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(selected.wrappedValue == value ? gold : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 6)
    }

    private func options(_ title: String, _ values: [String], _ selected: Binding<String>) -> some View {
        Picker(title, selection: selected) {
            ForEach(values, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 340, alignment: .leading)
    }

    private func check(_ title: String, initial: Bool = false) -> some View {
        Toggle(title, isOn: Binding(get: { flag(title, initial: initial) },
                                    set: { settings.flags[title] = $0 }))
            .toggleStyle(.checkbox).tint(gold)
    }

    private func flag(_ title: String, initial: Bool = false) -> Bool { settings.flags[title] ?? initial }
    private func selection(_ title: String, _ initial: String) -> Binding<String> {
        Binding(get: { settings.choices[title] ?? initial }, set: { settings.choices[title] = $0 })
    }

    private func box(_ text: String, height: CGFloat) -> some View {
        Text(text).padding(8).frame(width: 335, height: height, alignment: .topLeading).border(.secondary)
    }

    private func unavailable(_ title: String) -> some View {
        Button(title) {}.disabled(true)
    }
}


private struct CDDrivePicker: NSViewRepresentable {
    @Binding var selection: String?
    let drives: [AudioCDDrive]
    let refresh: () -> Void

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 13)
        button.autoenablesItems = false
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setAccessibilityLabel("光驱")
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.removeAllItems()
        button.addItem(withTitle: drives.isEmpty ? "" : "自动选择")
        for drive in drives {
            let item = NSMenuItem(title: drive.name, action: nil, keyEquivalent: "")
            item.representedObject = drive.id
            button.menu?.addItem(item)
        }
        if let selection, !drives.contains(where: { $0.id == selection }) {
            let unavailable = NSMenuItem(title: "光驱暂不可用", action: nil, keyEquivalent: "")
            unavailable.representedObject = selection
            unavailable.isEnabled = false
            button.menu?.addItem(unavailable)
        }
        button.menu?.addItem(.separator())
        let refreshItem = NSMenuItem(title: "刷新光驱列表", action: nil, keyEquivalent: "")
        refreshItem.tag = 1
        button.menu?.addItem(refreshItem)
        context.coordinator.restoreSelection(button)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: CDDrivePicker

        init(parent: CDDrivePicker) { self.parent = parent }

        func restoreSelection(_ button: NSPopUpButton) {
            let item = button.itemArray.first { ($0.representedObject as? String) == parent.selection && $0.tag == 0 && !$0.isSeparatorItem }
            button.select(item)
        }

        @objc func choose(_ button: NSPopUpButton) {
            guard let item = button.selectedItem else { return }
            if item.tag == 1 {
                restoreSelection(button)
                parent.refresh()
            } else {
                parent.selection = item.representedObject as? String
            }
        }
    }
}
