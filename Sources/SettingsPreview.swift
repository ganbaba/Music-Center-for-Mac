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
    @State private var dropdown: SettingsDropdownRequest?
    let panelHeight: CGFloat
    @State private var explanation: String?
    let cdDrives: [AudioCDDrive]
    let refreshCDDrives: () -> Void
    let save: (PreviewSettings) -> Void
    let cancel: () -> Void

    private let gold = SettingsStyle.gold
    private let ink = SettingsStyle.ink
    private let muted = SettingsStyle.heading
    private let selected = Color(white: 0.87)
    init(page: SettingsPage, settings: PreviewSettings, height: CGFloat = 690,
         cdDrives: [AudioCDDrive], refreshCDDrives: @escaping () -> Void,
         save: @escaping (PreviewSettings) -> Void, cancel: @escaping () -> Void) {
        _page = State(initialValue: page)
        _draft = State(initialValue: settings)
        panelHeight = height
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
                    default: AdditionalSettings(page: page, settings: $draft,
                                                cdDrives: cdDrives, refreshCDDrives: refreshCDDrives,
                                                explain: { explanation = $0 }).id(page)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, page == .cd ? 0 : 16)
                .padding(.top, 11)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity, alignment: .top)
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
        .frame(width: 710, height: panelHeight)
        .environment(\.presentSettingsDropdown) { dropdown = $0 }
        .environment(\.activeSettingsDropdown, dropdown?.id)
        .overlayPreferenceValue(SettingsDropdownAnchors.self) { anchors in
            GeometryReader { geometry in
                if let dropdown, let anchor = anchors[dropdown.id] {
                    let bounds = geometry[anchor]
                    let below = max(0, geometry.size.height - 6 - bounds.maxY)
                    let above = max(0, bounds.minY - 6)
                    let showBelow = below >= min(CGFloat(dropdown.titles.count) * 22 + 2, 280) || below >= above
                    let height = min(CGFloat(dropdown.titles.count) * 22 + 2, showBelow ? below : above)
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.001).onTapGesture { self.dropdown = nil }
                        SettingsDropdownList(request: dropdown, height: height) { self.dropdown = nil }
                            .frame(width: bounds.width)
                            .offset(x: bounds.minX, y: showBelow ? bounds.maxY : bounds.minY - height)
                    }
                    .id(dropdown.id)
                }
            }
        }
        .alert("Music Center UI Preview", isPresented: Binding(get: { explanation != nil }, set: { if !$0 { explanation = nil } })) {
            Button("确定") { explanation = nil }
        } message: { Text(explanation ?? "") }
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
                    dropdown = nil
                } label: {
                    sidebarLabel(destination.rawValue)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == destination ? .isSelected : [])
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
        SettingsScroll {
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
                    SettingsCheck("为切换屏幕显示等操作启用视觉效果", isOn: $draft.display.visualEffects)
                        .padding(.leading, 8)
                }
                displaySection("初始化隐藏信息") {
                    Text("显示[下次不要显示此信息]复选框中勾选的所有信息。")
                    HStack {
                        Spacer()
                        SettingsAction("初始化") { explanation = "当前没有已隐藏的提示。" }
                    }
                }
            }
            .frame(width: 284, alignment: .leading)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 332)
    }

    private func displaySection<Controls: View>(_ title: String, @ViewBuilder controls: () -> Controls) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(muted)
            controls()
        }
    }

    private var appearanceControl: some View {
        SettingsDropdown(title: "应用程序显示颜色", selection: $draft.display.appearance,
            options: DisplaySettings.Appearance.allCases.map {
                SettingsDropdownOption(value: $0, title: $0.rawValue)
            })
    }

    private func settingRadio(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        SettingsRadio(title, selected: selected, action: action).padding(.leading, 8)
    }

    private var transferControls: some View {
        SettingsScroll {
            VStack(alignment: .leading, spacing: 8) {
                Text("传输模式").foregroundStyle(muted)
                HStack(spacing: 16) {
                    Text("转换比特率：").frame(width: 88, alignment: .leading)
                    SettingsDropdown(title: "转换比特率", selection: $draft.bitrate,
                        options: PreviewSettings.aacBitrates.map { SettingsDropdownOption(value: $0, title: "\($0) kbps") })
                        .frame(width: 200)
                }
                Text("如果指定比特率与设备不兼容，则转换为近似值后传输。")
                    .padding(.leading, 40).fixedSize(horizontal: false, vertical: true)
                settingRadio("正常传输：原始文件格式传输 (推荐)", selected: !draft.convertsAll) { draft.convertsAll = false }
                Text("设备无法播放的文件将转换为AAC格式后传输。")
                    .padding(.leading, 40).fixedSize(horizontal: false, vertical: true)
                settingRadio("自动指定传输：文件始终转换为AAC格式后传输。", selected: draft.convertsAll) { draft.convertsAll = true }
                Text("传输后操作").foregroundStyle(muted).padding(.top, 36)
                SettingsCheck("传输后，删除传输中的已转换文件", isOn: $draft.removesConvertedFiles)
                    .padding(.leading, 8).padding(.top, 8)
                Text("虽然反选会缩短下次传输已转换文件的时间，但占用更大的计算机硬盘容量。")
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            .padding(.trailing, 8).padding(.bottom, 8)
        }
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("歌曲回放范围").foregroundStyle(muted)
            settingRadio("所有范围", selected: draft.playsAcrossLists) { draft.playsAcrossLists = true }
            Text("在包含选定歌曲的列表结束后，继续播放下一个列表。")
                .padding(.leading, 40).fixedSize(horizontal: false, vertical: true)
            settingRadio("选定范围", selected: !draft.playsAcrossLists) { draft.playsAcrossLists = false }
            Text("只播放包含选定歌曲的列表。").padding(.leading, 40)
        }
    }

    private var outputControls: some View {
        SettingsScroll {
            VStack(alignment: .leading, spacing: 8) {
                Text("输出格式(ASIO/WASAPI专用)").foregroundStyle(muted)
                settingRadio("推荐设置：自动设置最佳输出格式", selected: draft.outputSampleRate == .automatic) {
                    draft.outputSampleRate = .automatic
                }.padding(.top, 8)
                settingRadio("手动设置：选择输出格式", selected: draft.outputSampleRate != .automatic) {
                    if draft.outputSampleRate == .automatic { draft.outputSampleRate = .standard }
                }
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Text("量化比特率").frame(width: 92, alignment: .leading)
                        SettingsDropdown(title: "量化比特率", selection: Binding(
                            get: { draft.choices["输出量化比特率"] ?? "16 bit" },
                            set: { draft.choices["输出量化比特率"] = $0 }),
                            options: ["16 bit", "24 bit", "32 bit"].map { SettingsDropdownOption(value: $0, title: $0) })
                            .frame(width: 208)
                    }
                    HStack(spacing: 12) {
                        Text("采样频率").frame(width: 92, alignment: .leading)
                        SettingsDropdown(title: "采样频率", selection: Binding(
                            get: { draft.outputSampleRate == .automatic ? .standard : draft.outputSampleRate },
                            set: { draft.outputSampleRate = $0 }),
                            options: AudioRenderRate.allCases.filter { $0 != .automatic }
                                .map { SettingsDropdownOption(value: $0, title: $0.label) })
                            .frame(width: 208)
                    }
                }
                .padding(.leading, 40)
                .disabled(draft.outputSampleRate == .automatic)
                SettingsCheck("出现跳过音频时请勾选。", isOn: Binding(
                    get: { draft.flags["出现跳过音频时请勾选。"] ?? false },
                    set: { draft.flags["出现跳过音频时请勾选。"] = $0 }))
                    .padding(.leading, 8)
                Text("调整设备设置有时可以消除跳过现象。确保检查设备设置。")
                    .padding(.leading, 40).fixedSize(horizontal: false, vertical: true)
                Text("备注：处于ASIO或WASAPI专属模式下时，下列限制适用。\n- 无法使用Music Center for PC。\n- 调节音量、均衡器功能禁用。")
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            .padding(.trailing, 8).padding(.bottom, 8)
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
                    SettingsAction("恢复默认", width: 86) {
                        draft.columns = PreviewSettings.defaultColumns
                        shownSelection = nil
                        hiddenSelection = nil
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
                }
            }
        }
    }

    private func columnList(_ names: [String], selection: Binding<String?>, otherSelection: Binding<String?>,
                            height: CGFloat = 262) -> some View {
        SettingsScroll {
            VStack(spacing: 0) {
                ForEach(names, id: \.self) { name in
                    Button {
                        selection.wrappedValue = name
                        otherSelection.wrappedValue = nil
                    } label: {
                        Text(name)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 22)
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

struct SettingsDropdownOption<Value: Hashable> {
    let value: Value
    let title: String
    var enabled = true
}

private struct SettingsDropdownRequest {
    let id: UUID
    let title: String
    let titles: [String]
    let enabled: [Bool]
    let selectedIndex: Int?
    let select: (Int) -> Void
}

private struct SettingsDropdownAnchors: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ActiveSettingsDropdown: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private struct PresentSettingsDropdown: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (SettingsDropdownRequest) -> Void = { _ in }
}

private extension EnvironmentValues {
    var activeSettingsDropdown: UUID? {
        get { self[ActiveSettingsDropdown.self] }
        set { self[ActiveSettingsDropdown.self] = newValue }
    }

    var presentSettingsDropdown: @MainActor @Sendable (SettingsDropdownRequest) -> Void {
        get { self[PresentSettingsDropdown.self] }
        set { self[PresentSettingsDropdown.self] = newValue }
    }
}

struct SettingsDropdown<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [SettingsDropdownOption<Value>]
    @State private var id = UUID()
    @Environment(\.presentSettingsDropdown) private var present
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.activeSettingsDropdown) private var active

    var body: some View {
        Button {
            guard !options.isEmpty else { return }
            present(SettingsDropdownRequest(id: id, title: title,
                titles: options.map(\.title), enabled: options.map(\.enabled),
                selectedIndex: options.firstIndex { $0.value == selection },
                select: { selection = options[$0].value }))
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.title ?? "")
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity).frame(height: 26)
            .foregroundStyle(isEnabled ? Color(white: 0.10) : Color(white: 0.64))
            .background(isEnabled ? .white : .white)
            .overlay {
                Rectangle().strokeBorder(active == id ? Color(red: 0.70, green: 0.57, blue: 0.29) :
                    Color(white: isEnabled ? 0.42 : 0.78))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.value == selection }?.title ?? "")
        .anchorPreference(key: SettingsDropdownAnchors.self, value: .bounds) { [id: $0] }
    }
}

private struct SettingsDropdownList: View {
    let request: SettingsDropdownRequest
    let height: CGFloat
    let close: () -> Void
    @State private var highlighted: Int?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(request.titles.indices, id: \.self) { index in
                        Button { choose(index) } label: {
                            Text(request.titles[index])
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 22)
                                .foregroundStyle(!request.enabled[index] ? Color(white: 0.65) :
                                    (highlighted == index ? .white : Color(white: 0.10)))
                                .background(highlighted == index ? Color(red: 0.08, green: 0.37, blue: 0.80) : .white)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!request.enabled[index])
                        .accessibilityAddTraits(request.selectedIndex == index ? .isSelected : [])
                        .onHover { inside in if inside && request.enabled[index] { highlighted = index } }
                        .id(index)
                    }
                }
            }
            .onChange(of: highlighted) { _, index in
                if let index { scroll.scrollTo(index) }
            }
            .onAppear {
                highlighted = request.selectedIndex
                if let index = request.selectedIndex { scroll.scrollTo(index) }
            }
        }
        .scrollIndicators(.never)
        .padding(1).frame(height: height)
        .background(.white)
        .overlay { Rectangle().strokeBorder(Color(white: 0.42)) }
        .focusable().focused($focused).focusEffectDisabled()
        .task {
            await Task.yield()
            focused = true
        }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.home) { highlighted = request.titles.indices.first { request.enabled[$0] }; return .handled }
        .onKeyPress(.end) { highlighted = request.titles.indices.last { request.enabled[$0] }; return .handled }
        .onKeyPress(.tab) { close(); return .ignored }
        .onKeyPress(.return) {
            if let highlighted { choose(highlighted) }
            return .handled
        }
        .onKeyPress(.escape) { close(); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.title + "选项")
    }

    private func move(_ delta: Int) {
        let available = request.titles.indices.filter { request.enabled[$0] }
        guard !available.isEmpty else { return }
        guard let highlighted, let current = available.firstIndex(of: highlighted) else {
            highlighted = delta > 0 ? available.first : available.last
            return
        }
        self.highlighted = available[min(available.count - 1, max(0, current + delta))]
    }

    private func choose(_ index: Int) {
        guard request.enabled[index] else { return }
        request.select(index)
        close()
    }
}
