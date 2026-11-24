import SwiftUI

enum SettingsPage: String, CaseIterable {
    case display = "显示屏幕"
    case columns = "歌曲列表上显示项目"
    case importFiles = "导入文件"
    case cd = "从CD导入"
    case metadata = "获取歌曲信息"
    case playback = "歌曲回放"
    case transfer = "设备传输"
    case output = "音频输出"
    case share = "分享我的数据库"
    case update = "更新软件"
    case other = "其他设置"
}

struct PreviewSettings: Codable, Equatable {
    static let defaultColumns = ["标题", "高解析度", "艺术家", "专辑", "歌曲长度", "文件大小", "类型", "发行年份", "歌曲编号", "最后注册"]
    static let extraColumns = ["专辑艺术家", "歌曲", "播放次数", "格式", "编解码器", "比特率", "量化比特率",
                               "最后更新", "最后播放", "目的地", "12 TONE ANALYSIS", "歌碟编号", "评价", "均衡器", "作曲家"]

    var bitrate = 128
    var convertsAll = false
    var removesConvertedFiles = true
    var columns = defaultColumns
    var columnWidths: [String: Double] = [:]
    var display = DisplaySettings()
    var playsAcrossLists = true
    var outputDeviceUID: String?
    var outputSampleRate: AudioRenderRate = .automatic
    var choices: [String: String] = [:]
    var flags: [String: Bool] = [:]
    init() {}

    private enum CodingKeys: String, CodingKey {
        case bitrate, convertsAll, removesConvertedFiles, columns, columnWidths, display, playsAcrossLists, outputDeviceUID, outputSampleRate, choices, flags
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bitrate = try values.decodeIfPresent(type(of: bitrate), forKey: .bitrate) ?? bitrate
        convertsAll = try values.decodeIfPresent(type(of: convertsAll), forKey: .convertsAll) ?? convertsAll
        removesConvertedFiles = try values.decodeIfPresent(type(of: removesConvertedFiles), forKey: .removesConvertedFiles) ?? removesConvertedFiles
        columns = try values.decodeIfPresent(type(of: columns), forKey: .columns) ?? columns
        columnWidths = try values.decodeIfPresent(type(of: columnWidths), forKey: .columnWidths) ?? columnWidths
        display = try values.decodeIfPresent(type(of: display), forKey: .display) ?? display
        playsAcrossLists = try values.decodeIfPresent(type(of: playsAcrossLists), forKey: .playsAcrossLists) ?? playsAcrossLists
        outputDeviceUID = try values.decodeIfPresent(String.self, forKey: .outputDeviceUID)
        outputSampleRate = (try values.decodeIfPresent(Int.self, forKey: .outputSampleRate)).flatMap(AudioRenderRate.init(rawValue:)) ?? .automatic
        choices = try values.decodeIfPresent(type(of: choices), forKey: .choices) ?? choices
        flags = try values.decodeIfPresent(type(of: flags), forKey: .flags) ?? flags
    }

}

struct DisplaySettings: Codable, Equatable {
    enum TextSize: String, CaseIterable, Codable {
        case small = "小"
        case medium = "中"
        case large = "大"

        var settingsLabel: String { self == .medium ? "中 (默认)" : rawValue }
        var scale: CGFloat {
            switch self {
            case .small: 0.70
            case .medium: 1
            case .large: 1.25
            }
        }
    }

    enum Spacing: String, CaseIterable, Codable {
        case standard = "标准"
        case narrow = "狭窄"

        var rowHeight: CGFloat { self == .standard ? 40 : 20 }
    }

    enum Appearance: String, CaseIterable, Codable {
        case white = "白色(默认)"
        case black = "黑色"
        case red = "红色"
        case blue = "蓝色"
        case green = "绿色"

        var dark: Bool { self != .white }

        // Sampled from the Windows header, library background, sidebar selection, and song selection.
        private var palette: (canvas: UInt32, surface: UInt32, selected: UInt32, track: UInt32) {
            switch self {
            case .white: (0xffffff, 0xf0f0f0, 0xdfdfdf, 0xd7d7d7)
            case .black: (0x303030, 0x191919, 0x171717, 0x3d3d3d)
            case .red: (0xa23d2c, 0x7c2517, 0x642317, 0x49170e)
            case .blue: (0x4b5560, 0x3b4249, 0x2b3137, 0x23272c)
            case .green: (0x546c68, 0x39514d, 0x303e3c, 0x23312f)
            }
        }

        var canvas: Color { color(palette.canvas) }
        var surface: Color { color(palette.surface) }
        var selected: Color { color(palette.selected) }
        var selectedTrack: Color { color(palette.track) }

        private func color(_ rgb: UInt32) -> Color {
            Color(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255)
        }
    }

    var textSize = TextSize.medium
    var spacing = Spacing.standard
    var appearance = Appearance.white
    var groupArtistsByTrack = false
    var visualEffects = true
    init() {}

    private enum CodingKeys: String, CodingKey {
        case textSize, spacing, appearance, groupArtistsByTrack, visualEffects
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        textSize = try values.decodeIfPresent(type(of: textSize), forKey: .textSize) ?? textSize
        spacing = try values.decodeIfPresent(type(of: spacing), forKey: .spacing) ?? spacing
        appearance = try values.decodeIfPresent(type(of: appearance), forKey: .appearance) ?? appearance
        groupArtistsByTrack = try values.decodeIfPresent(type(of: groupArtistsByTrack), forKey: .groupArtistsByTrack) ?? groupArtistsByTrack
        visualEffects = try values.decodeIfPresent(type(of: visualEffects), forKey: .visualEffects) ?? visualEffects
    }

}

struct SettingsPreview: View {
    @State private var page: SettingsPage
    @State private var draft: PreviewSettings
    @State private var shownSelection: String?
    @State private var hiddenSelection: String?
    @State private var showsBitrates = false
    @State private var showsAppearances = false
    let outputDevices: [AudioOutputDevice]
    let defaultOutput: AudioOutputDevice.ID?
    let cdDrives: [AudioCDDrive]
    let refreshCDDrives: () -> Void
    let save: (PreviewSettings) -> Void
    let cancel: () -> Void

    private let gold = Color(red: 0.70, green: 0.57, blue: 0.29)
    private let ink = Color(white: 0.10)
    private let muted = Color(white: 0.42)
    private let selected = Color(white: 0.87)
    init(page: SettingsPage, settings: PreviewSettings, outputDevices: [AudioOutputDevice], defaultOutput: AudioOutputDevice.ID?,
         cdDrives: [AudioCDDrive], refreshCDDrives: @escaping () -> Void,
         save: @escaping (PreviewSettings) -> Void, cancel: @escaping () -> Void) {
        _page = State(initialValue: page)
        _draft = State(initialValue: settings)
        self.outputDevices = outputDevices
        self.defaultOutput = defaultOutput
        self.cdDrives = cdDrives
        self.refreshCDDrives = refreshCDDrives
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("设置")
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(alignment: .trailing) {
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(width: 35, height: 35)
                    }
                    .buttonStyle(.plain)
                    .help("关闭设置")
                    .padding(.trailing, 7)
                }
            HStack(alignment: .top, spacing: 32) {
                sidebar
                Group {
                    switch page {
                    case .display: displayControls
                    case .columns: columnControls
                    case .playback: playbackControls
                    case .output: outputControls
                    case .transfer: transferControls
                    default: AdditionalSettings(page: page, settings: $draft, gold: gold,
                                                cdDrives: cdDrives, refreshCDDrives: refreshCDDrives).id(page)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 24)
                .padding(.top, 7)
            }
            Spacer(minLength: 12)
            HStack(spacing: 9) {
                Spacer()
                Button { save(draft) } label: {
                    Text("确定")
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 27)
                        .background(gold)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                Button(action: cancel) {
                    Text("取消")
                        .frame(width: 96, height: 27)
                        .border(ink)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 14)
        }
        .font(.system(size: 12))
        .foregroundStyle(ink)
        .frame(width: 710, height: 690)
        .background(.white)
        .compositingGroup()
        .shadow(color: .black.opacity(0.55), radius: 7, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置")
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ForEach(SettingsPage.allCases, id: \.self) { destination in
                Button {
                    page = destination
                    showsBitrates = false
                    showsAppearances = false
                } label: {
                    sidebarLabel(destination.rawValue)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 224)
    }

    private func sidebarLabel(_ text: String) -> some View {
        Text(text)
            .padding(.leading, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 31)
            .background(page.rawValue == text ? selected : .white)
            .contentShape(Rectangle())
    }

    private var displayControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 33) {
                displaySection("文本大小") {
                    ForEach(DisplaySettings.TextSize.allCases, id: \.self) { value in
                        settingRadio(value.settingsLabel, selected: draft.display.textSize == value) {
                            draft.display.textSize = value
                        }
                    }
                }
                displaySection("列表显示间距") {
                    ForEach(DisplaySettings.Spacing.allCases, id: \.self) { value in
                        settingRadio(value.rawValue, selected: draft.display.spacing == value) {
                            draft.display.spacing = value
                        }
                    }
                }
                displaySection("应用程序显示颜色") {
                    appearanceControl
                }
                .zIndex(1)
                displaySection("显示艺术家") {
                    settingRadio("按专辑演出者排序", selected: !draft.display.groupArtistsByTrack) {
                        draft.display.groupArtistsByTrack = false
                    }
                    settingRadio("按歌曲演出者排序", selected: draft.display.groupArtistsByTrack) {
                        draft.display.groupArtistsByTrack = true
                    }
                    Text("专辑按歌曲艺术家分类显示。").padding(.leading, 39)
                }
                displaySection("视觉效果") {
                    Button { draft.display.visualEffects.toggle() } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Rectangle().strokeBorder(muted)
                                if draft.display.visualEffects {
                                    Rectangle().fill(gold)
                                    Image(systemName: "checkmark").foregroundStyle(.white)
                                }
                            }
                            .frame(width: 16, height: 16)
                            Text("为切换屏幕显示等操作启用视觉效果")
                        }
                        .frame(height: 24)
                        .padding(.leading, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.display.visualEffects ? .isSelected : [])
                }

            }
            .frame(width: 284, alignment: .leading)
            .padding(.bottom, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .frame(width: 332, height: 577)
    }

    private func displaySection<Controls: View>(_ title: String, @ViewBuilder controls: () -> Controls) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(muted)
            controls()
        }
    }

    private var appearanceControl: some View {
        Button { showsAppearances.toggle() } label: {
            HStack {
                Text(draft.display.appearance.rawValue)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(muted)
            }
            .padding(.horizontal, 7)
            .frame(height: 25)
            .border(showsAppearances ? gold : muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("应用程序显示颜色")
        .accessibilityValue(draft.display.appearance.rawValue)
        .overlay(alignment: .top) {
            if showsAppearances {
                VStack(spacing: 0) {
                    ForEach(DisplaySettings.Appearance.allCases, id: \.self) { value in
                        let selected = value == draft.display.appearance
                        Button {
                            draft.display.appearance = value
                            showsAppearances = false
                        } label: {
                            Text(value.rawValue)
                                .padding(.horizontal, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 22)
                                .foregroundStyle(selected ? .white : ink)
                                .background(selected ? Color(red: 0.08, green: 0.37, blue: 0.80) : .white)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(1)
                .background(.white)
                .border(muted)
                .offset(y: 25)
            }
        }
    }

    private func settingRadio(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Circle().strokeBorder(selected ? gold : muted)
                    .overlay { if selected { Circle().fill(gold).padding(2.5) } }
                    .frame(width: 16, height: 16)
                Text(title)
            }
            .frame(height: 24)
            .padding(.leading, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var transferControls: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("传输模式").foregroundStyle(muted)
            HStack(spacing: 18) {
                Text("转换比特率：")
                bitrateControl
            }
            .zIndex(1)
            Text("如果指定比特率与设备不兼容，则转换为近似值后传输。")
                .padding(.leading, 39)
            transferMode("正常传输：原始文件格式传输 (推荐)", converts: false)
            Text("设备无法播放的文件将转换为AAC格式后传输。")
                .padding(.leading, 39)
                .padding(.top, -6)
            transferMode("自动指定传输：文件始终转换为AAC格式后传输。", converts: true)
            Text("传输后操作").foregroundStyle(muted).padding(.top, 25)
            Button {
                draft.removesConvertedFiles.toggle()
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Rectangle().strokeBorder(muted)
                        if draft.removesConvertedFiles {
                            Rectangle().fill(gold)
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 16, height: 16)
                    Text("传输后，删除传输中的已转换文件")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 5)
            .accessibilityAddTraits(draft.removesConvertedFiles ? .isSelected : [])
            Text("虽然反选会缩短下次传输已转换文件的时间，但占用更大的计算机硬盘容量。")
        }
    }

    private var bitrateControl: some View {
        Button {
            showsBitrates.toggle()
        } label: {
            HStack {
                Text("\(draft.bitrate) kbps")
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .padding(.horizontal, 7)
            .frame(width: 200, height: 24)
            .border(showsBitrates ? gold : muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("转换比特率")
        .accessibilityValue("\(draft.bitrate) kbps")
        .overlay(alignment: .top) {
            if showsBitrates {
                VStack(spacing: 0) {
                    ForEach([320, 256, 192, 160, 128, 96, 80], id: \.self) { rate in
                        Button {
                            draft.bitrate = rate
                            showsBitrates = false
                        } label: {
                            Text("\(rate) kbps")
                                .padding(.leading, 7)
                                .frame(width: 198, height: 21, alignment: .leading)
                                .foregroundStyle(rate == draft.bitrate ? .white : ink)
                                .background(rate == draft.bitrate ? Color(red: 0.08, green: 0.37, blue: 0.80) : .white)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(1)
                .background(.white)
                .border(muted)
                .offset(y: 24)
            }
        }
    }

    private func transferMode(_ label: String, converts: Bool) -> some View {
        Button {
            draft.convertsAll = converts
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle().strokeBorder(muted, lineWidth: 1)
                    if draft.convertsAll == converts {
                        Circle().fill(gold).padding(2.5)
                    }
                }
                .frame(width: 16, height: 16)
                Text(label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 5)
        .accessibilityAddTraits(draft.convertsAll == converts ? .isSelected : [])
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("歌曲回放范围").foregroundStyle(muted)
            settingRadio("所有范围", selected: draft.playsAcrossLists) { draft.playsAcrossLists = true }
            Text("在包含选定歌曲的列表结束后，继续播放下一个列表。")
                .padding(.leading, 39)
            settingRadio("选定范围", selected: !draft.playsAcrossLists) { draft.playsAcrossLists = false }
            Text("只播放包含选定歌曲的列表。").padding(.leading, 39)
        }
    }

    private var outputControls: some View {
        let selected = outputDevices.first { $0.id == draft.outputDeviceUID }
        let device = selected ?? outputDevices.first { $0.id == defaultOutput }
        let formats = device?.formats.map(\.label).joined(separator: "\n") ?? ""
        return ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Label("播放设备", systemImage: "speaker.wave.2").font(.headline)
                Picker("输出设备", selection: $draft.outputDeviceUID) {
                    Text("跟随系统").tag(String?.none)
                    ForEach(outputDevices) { device in Text(device.name).tag(Optional(device.id)) }
                    if let uid = draft.outputDeviceUID, selected == nil {
                        Text("已断开的设备").tag(Optional(uid))
                    }
                }
                if draft.outputDeviceUID != nil, selected == nil {
                    Text("此设备已断开，播放使用系统输出。").foregroundStyle(.secondary)
                }
                LabeledContent("设备格式", value: formats.isEmpty ? "不可用" : formats)

                Divider()
                Label("应用渲染", systemImage: "waveform").font(.headline)
                Picker("采样率", selection: $draft.outputSampleRate) {
                    ForEach(AudioRenderRate.allCases) { rate in Text(rate.label).tag(rate) }
                }
                Text("自动使用 macOS 的输出格式。手动采样率作用于本应用的播放处理。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("打开音频 MIDI 设置…") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                }
                Text("设备的采样率和位深由 macOS 管理。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 390, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var columnControls: some View {
        let hidden = (PreviewSettings.defaultColumns + PreviewSettings.extraColumns).filter { !draft.columns.contains($0) }
        return VStack(alignment: .leading, spacing: 16) {
            Text("歌曲列表").foregroundStyle(muted)
            HStack(alignment: .top, spacing: 15) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("显示项目")
                    columnList(draft.columns, selection: $shownSelection, otherSelection: $hiddenSelection)
                    HStack(spacing: 0) {
                        arrowButton("chevron.up", "上移", width: 26, height: 26) { moveColumn(-1) }.disabled(!canMoveColumn(-1))
                        arrowButton("chevron.down", "下移", width: 26, height: 26) { moveColumn(1) }.disabled(!canMoveColumn(1))
                        Spacer()
                    }
                    .frame(width: 160, height: 26)
                    .border(ink)
                }
                VStack(spacing: 32) {
                    arrowButton("arrow.left", "显示所选列", width: 36, height: 27) {
                        guard let hiddenSelection, let index = hidden.firstIndex(of: hiddenSelection) else { return }
                        draft.columns.append(hiddenSelection)
                        self.hiddenSelection = adjacentColumn(in: hidden, removing: index)
                    }
                    .disabled(hiddenSelection == nil)
                    arrowButton("arrow.right", "隐藏所选列", width: 36, height: 27) {
                        guard let shownSelection, let index = draft.columns.firstIndex(of: shownSelection) else { return }
                        self.shownSelection = adjacentColumn(in: draft.columns, removing: index)
                        draft.columns.remove(at: index)
                    }
                    .disabled(shownSelection == nil || shownSelection == "标题")
                }
                .padding(.top, 119)
                VStack(alignment: .leading, spacing: 0) {
                    Text("隐藏")
                    columnList(hidden, selection: $hiddenSelection, otherSelection: $shownSelection, height: 288)
                    Button {
                        draft.columns = PreviewSettings.defaultColumns
                        shownSelection = nil
                        hiddenSelection = nil
                    } label: {
                        Text("恢复默认").padding(.horizontal, 8).frame(height: 27).border(ink)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
                }
            }
        }
    }

    private func columnList(_ names: [String], selection: Binding<String?>, otherSelection: Binding<String?>,
                            height: CGFloat = 262) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(names, id: \.self) { name in
                    Button {
                        selection.wrappedValue = name
                        otherSelection.wrappedValue = nil
                    } label: {
                        Text(name)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 23)
                            .background(selection.wrappedValue == name ? selected : .white)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.wrappedValue == name ? .isSelected : [])
                }
            }
        }
        .frame(width: 160, height: height)
        .border(ink)
    }

    private func arrowButton(_ symbol: String, _ label: String, width: CGFloat, height: CGFloat,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: width, height: height)
                .border(muted)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func adjacentColumn(in columns: [String], removing index: Int) -> String? {
        if columns.indices.contains(index + 1) { return columns[index + 1] }
        return index > 0 ? columns[index - 1] : nil
    }

    private func canMoveColumn(_ delta: Int) -> Bool {
        guard let shownSelection, let index = draft.columns.firstIndex(of: shownSelection) else { return false }
        return draft.columns.indices.contains(index + delta)
    }

    private func moveColumn(_ delta: Int) {
        guard canMoveColumn(delta), let shownSelection, let index = draft.columns.firstIndex(of: shownSelection) else { return }
        draft.columns.swapAt(index, index + delta)
    }
}
