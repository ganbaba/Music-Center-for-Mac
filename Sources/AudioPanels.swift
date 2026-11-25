import SwiftUI

enum AudioPanel: String {
    case dsee = "DSEE HX"
    case equalizer = "均衡器"
    case output = "音频输出"
    case queue = "播放队列"
    case volume = "音量"

    var symbol: String {
        switch self {
        case .dsee: "waveform"
        case .equalizer: "slider.vertical.3"
        case .output: "hifispeaker.fill"
        case .queue: "list.bullet"
        case .volume: "speaker.wave.2.fill"
        }
    }
}

struct EqualizerSettings: Codable, Equatable {
    struct Preset: Identifiable, Codable, Equatable {
        let name: String
        let gains: [Int]
        var id: String { name }
    }

    static let frequencies = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    // Slider positions captured from Music Center for PC 2.7.4 at each preset.
    static let builtIns = [
        Preset(name: "沉静", gains: [8, 8, 5, 0, 5, 5, 3, 2, -1, -3]),
        Preset(name: "电子", gains: [5, 4, 2, 0, -3, 3, 1, 2, 4, 5]),
        Preset(name: "钢琴", gains: [3, 2, 0, 2, 3, 2, 4, 5, 3, 4]),
        Preset(name: "古典", gains: [5, 4, 3, 3, -1, -1, 0, 2, 3, 4]),
        Preset(name: "爵士", gains: [4, 3, 2, 2, -1, -1, 0, 2, 3, 4]),
        Preset(name: "拉丁", gains: [5, 3, 0, 0, -1, -1, -1, 0, 3, 5]),
        Preset(name: "雷鬼", gains: [2, 2, 2, -3, 0, 3, 5, 0, 3, 4]),
        Preset(name: "流行", gains: [-1, -1, 0, 2, 5, 5, 2, 0, -1, -1]),
        Preset(name: "民歌", gains: [0, 2, 2, -1, 2, 0, 0, 0, 2, 2]),
        Preset(name: "平直", gains: Array(repeating: 0, count: frequencies.count)),
        Preset(name: "人声", gains: [-1, -3, -3, 2, 4, 4, 3, 2, 0, -1]),
        Preset(name: "融合", gains: [3, 6, 6, 5, 2, -1, 2, 5, 5, 5]),
        Preset(name: "舞曲", gains: [4, 6, 5, 0, 2, 3, 5, 5, 4, 0]),
        Preset(name: "嬉哈", gains: [5, 4, 2, 3, -1, -1, 2, -1, 2, 3]),
        Preset(name: "摇滚", gains: [5, 4, 3, 2, -1, -1, 1, 3, 3, 3]),
        Preset(name: "吟咏", gains: [-3, -1, 0, 1, 3, 4, 5, 4, 3, -2]),
        Preset(name: "硬核及重金属", gains: [8, 12, 9, 6, 3, -1, 5, 8, 12, 6]),
        Preset(name: "原声", gains: [5, 4, 4, 1, 2, 2, 4, 4, 4, 2]),
        Preset(name: "治愈", gains: [2, 3, 3, 0, 0, 0, 0, 2, 3, 3]),
        Preset(name: "R&B", gains: [3, 7, 6, 2, -3, -1, 3, 3, 3, 4])
    ]

    var enabled = false
    var name = ""
    var gains = Array(repeating: 0, count: frequencies.count)
    var custom: [Preset] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, name, gains, custom
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(type(of: enabled), forKey: .enabled) ?? enabled
        name = try values.decodeIfPresent(type(of: name), forKey: .name) ?? name
        gains = try values.decodeIfPresent(type(of: gains), forKey: .gains) ?? gains
        custom = try values.decodeIfPresent(type(of: custom), forKey: .custom) ?? custom
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool {
        !trimmedName.isEmpty && !Self.builtIns.contains { $0.name == trimmedName }
            && !custom.contains { $0.name == trimmedName && $0.gains == gains }
    }

    mutating func select(_ preset: Preset) {
        name = preset.name
        gains = preset.gains
    }

    mutating func setGain(_ gain: Int, at index: Int) {
        guard gains[index] != gain else { return }
        gains[index] = gain
        name = ""
    }

    mutating func save() {
        guard canSave else { return }
        name = trimmedName
        let preset = Preset(name: name, gains: gains)
        if let index = custom.firstIndex(where: { $0.name == name }) {
            custom[index] = preset
        } else {
            custom.append(preset)
        }
    }
}

struct EqualizerPanel: View {
    @Binding var settings: EqualizerSettings
    let close: () -> Void

    @State private var showsPresets = false
    @State private var highlightedPreset: String?
    @FocusState private var presetListFocused: Bool
    private let gold = Color(red: 0.69, green: 0.57, blue: 0.30)
    private var presets: [EqualizerSettings.Preset] { settings.custom + EqualizerSettings.builtIns }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 10) {
                Text("均衡器")
                EffectSwitch(isOn: $settings.enabled, gold: gold, label: "启用均衡器")
            }
            .frame(width: 660, height: 22)
            .offset(y: 26)

            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    TextField("", text: $settings.name)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("均衡器预设名称")
                        .padding(.horizontal, 6)
                        .onTapGesture { showsPresets = false }
                    Button {
                        highlightedPreset = settings.name
                        showsPresets.toggle()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .frame(width: 22, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择均衡器预设")
                    .accessibilityValue(settings.name)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color(white: 0.65)).frame(width: 1)
                    }
                }
                .frame(width: 264, height: 24)
                .background(.white)
                .overlay(Rectangle().strokeBorder(showsPresets ? gold : Color(white: 0.65)))
                Button {
                    settings.custom.removeAll { $0.name == settings.name }
                    settings.name = ""
                } label: {
                    Image(systemName: "trash").frame(width: 18, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除均衡器预设")
                .disabled(!settings.custom.contains { $0.name == settings.name })
                .opacity(settings.custom.contains { $0.name == settings.name } ? 1 : 0)
                Button { settings.save() } label: {
                    Text("保存")
                        .foregroundStyle(.white)
                        .frame(width: 94, height: 24)
                        .background(gold.opacity(settings.canSave ? 1 : 0.25))
                }
                .buttonStyle(.plain)
                .disabled(!settings.canSave)
                .accessibilityLabel("保存均衡器预设")
            }
            .offset(x: 135, y: 64)

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text("+12dB")
                    Spacer(minLength: 0)
                    Text("0dB")
                    Spacer(minLength: 0)
                    Text("-12dB")
                }
                .frame(width: 62, height: 204, alignment: .trailing)
                .padding(.trailing, 20)
                ForEach(EqualizerSettings.frequencies.indices, id: \.self) { index in
                    VStack(spacing: 8) {
                        EqualizerBand(gain: Binding(
                            get: { settings.gains[index] },
                            set: { settings.setGain($0, at: index) }),
                            frequency: EqualizerSettings.frequencies[index], gold: gold)
                        Text(EqualizerSettings.frequencies[index])
                    }
                    .frame(width: 49)
                }
            }
            .offset(x: 28, y: 140)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭均衡器")
            .offset(x: 622)

            if showsPresets {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { showsPresets = false }
                presetList.offset(x: 135, y: 88)
            }
        }
        .frame(width: 660, height: 408, alignment: .topLeading)
        .font(.system(size: 12))
        .foregroundStyle(Color(white: 0.08))
        .background(.white)
        .environment(\.colorScheme, .light)
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 7, y: 2)
        .onExitCommand {
            if showsPresets { showsPresets = false } else { close() }
        }
    }

    private var presetList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(presets) { preset in
                        Button {
                            settings.select(preset)
                            showsPresets = false
                        } label: {
                            Text(preset.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .frame(height: 22)
                                .foregroundStyle(highlightedPreset == preset.name ? .white : Color(white: 0.08))
                                .background(highlightedPreset == preset.name ? Color(red: 0.08, green: 0.36, blue: 0.80) : .white)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(preset.name)
                        .onHover { if $0 { highlightedPreset = preset.name } }
                    }
                }
            }
            .frame(width: 264, height: min(264, CGFloat(presets.count) * 22))
            .background(.white)
            .overlay(Rectangle().strokeBorder(Color(white: 0.5)))
            .focusable()
            .focused($presetListFocused)
            .focusEffectDisabled()
            .accessibilityLabel("均衡器预设列表")
            .task {
                await Task.yield()
                presetListFocused = true
                if let highlightedPreset { proxy.scrollTo(highlightedPreset, anchor: .center) }
            }
            .onChange(of: highlightedPreset) {
                if let highlightedPreset { proxy.scrollTo(highlightedPreset, anchor: .center) }
            }
            .onKeyPress(.downArrow) { movePreset(1); return .handled }
            .onKeyPress(.upArrow) { movePreset(-1); return .handled }
            .onKeyPress(.return) {
                if let preset = presets.first(where: { $0.name == highlightedPreset }) {
                    settings.select(preset)
                    showsPresets = false
                }
                return .handled
            }
        }
    }

    private func movePreset(_ offset: Int) {
        guard !presets.isEmpty else { return }
        let current = presets.firstIndex { $0.name == highlightedPreset }
        let index = min(presets.count - 1, max(0, (current ?? (offset > 0 ? -1 : presets.count)) + offset))
        highlightedPreset = presets[index].name
    }
}

private struct EqualizerBand: View {
    @Binding var gain: Int
    let frequency: String
    let gold: Color
    @FocusState private var focused: Bool

    var body: some View {
        Canvas { context, size in
            let center = size.width / 2
            var ticks = Path()
            ticks.move(to: CGPoint(x: center, y: 6))
            ticks.addLine(to: CGPoint(x: center, y: size.height - 6))
            for step in 0...24 {
                let y = 6 + CGFloat(step) * (size.height - 12) / 24
                let half: CGFloat = step % 12 == 0 ? 7 : step % 6 == 0 ? 5 : 3
                ticks.move(to: CGPoint(x: center - half, y: y))
                ticks.addLine(to: CGPoint(x: center + half, y: y))
            }
            context.stroke(ticks, with: .color(Color(white: 0.65)), lineWidth: 1)
            let y = 6 + CGFloat(12 - gain) * (size.height - 12) / 24
            context.fill(Path(CGRect(x: center - 9, y: y - 1.5, width: 18, height: 3)), with: .color(gold))
        }
        .frame(width: 29, height: 204)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { event in
            focused = true
            gain = min(12, max(-12, Int((12 - (event.location.y - 6) / 8).rounded())))
        })
        .focusable()
        .focused($focused)
        .overlay {
            if focused { RoundedRectangle(cornerRadius: 2).stroke(gold.opacity(0.5)).padding(.horizontal, -2) }
        }
        .onKeyPress(.upArrow) { gain = min(12, gain + 1); return .handled }
        .onKeyPress(.downArrow) { gain = max(-12, gain - 1); return .handled }
        .accessibilityRepresentation {
            Slider(value: Binding(get: { Double(gain) }, set: { gain = Int($0) }), in: -12...12, step: 1)
                .accessibilityLabel(frequency + " Hz")
                .accessibilityValue("\(gain) dB")
        }
        .help(frequency + " Hz · \(gain) dB")
    }
}

private struct EffectSwitch: View {
    @Binding var isOn: Bool
    let gold: Color
    let label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                Capsule().fill(isOn ? gold : Color(white: 0.72))
                    .frame(width: 32, height: 16)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 13, height: 13).padding(1.5)
                    }
                Text(isOn ? "开" : "关")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "开" : "关")
    }
}

struct AudioPopover: View {
    let panel: AudioPanel
    let player: Player
    @Binding var dsee: Bool
    let gold: Color
    let selectedOutput: String?
    let queueHeight: CGFloat
    let selectOutput: (String?) -> Void
    let createPlaylist: () -> Void

    var body: some View {
        Group {
            switch panel {
            case .dsee:
                HStack(spacing: 9) {
                    Text("DSEE HX：")
                    EffectSwitch(isOn: $dsee, gold: gold, label: "DSEE HX 音效预览")
                }
                .font(.system(size: 15))
                .frame(width: 157, height: 46)
            case .volume:
                HStack(spacing: 7) {
                    Button(action: player.toggleMute) {
                        Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 16)).frame(width: 31, height: 31)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(player.isMuted ? "取消静音" : "静音")
                    .accessibilityLabel(player.isMuted ? "取消静音" : "静音")
                    volumeSlider
                }
                .padding(.horizontal, 12)
                .frame(width: 166, height: 60)
            case .output:
                VStack(alignment: .leading, spacing: 10) {
                    Label("此应用的音频输出", systemImage: "speaker.wave.2").font(.headline)
                    Picker("输出设备", selection: Binding(get: { selectedOutput }, set: { selectOutput($0) })) {
                        Text("跟随系统").tag(String?.none)
                        ForEach(player.outputs) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                        if let selectedOutput, !player.outputs.contains(where: { $0.id == selectedOutput }) {
                            Text("已断开的设备").tag(Optional(selectedOutput))
                        }
                    }
                    if let name = player.outputs.first(where: { $0.deviceID == player.effectiveOutput })?.name {
                        Text("当前输出 · " + name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16).frame(width: 290)
            case .queue:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("播放队列").fontWeight(.medium)
                        Spacer()
                        Button("创建播放列表", action: createPlaylist)
                            .buttonStyle(.plain)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Capsule().strokeBorder(.primary))
                            .disabled(!player.hasQueue)
                    }
                    if !player.hasQueue {
                        Text("内容未找到。").foregroundStyle(.secondary).padding(.vertical, 25)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                let queue = player.queueEntries
                                ForEach(queue, id: \.queueID) { entry in
                                    let track = entry.track
                                    Button { player.jump(toQueueEntry: entry.queueID) } label: {
                                        HStack(spacing: 7) {
                                            Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                                .opacity(player.currentItem?.queueID == entry.queueID ? 1 : 0)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(track.title).lineLimit(1)
                                                Text(track.artist).font(.system(size: 10))
                                            }
                                            Spacer()
                                            Text(track.duration.map(previewTime) ?? "—").font(.system(size: 10))
                                        }
                                        .foregroundStyle(player.currentItem?.queueID == entry.queueID ? gold : .primary)
                                        .frame(height: 39)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .windowsContextMenu("队列项目菜单", width: 132) {
                                        [WindowsMenuEntry(id: "remove", title: "从队列中删除歌曲", action: { player.removeQueueEntry(entry.queueID) })]
                                    }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12).frame(width: 348, height: queueHeight)
            case .equalizer:
                EmptyView()
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color(white: 0.10))
        .background(.white)
        .overlay(alignment: .topTrailing) {
            if panel == .volume || panel == .dsee {
                Rectangle().fill(.white).frame(width: 13, height: 13)
                    .rotationEffect(.degrees(45))
                    .offset(x: -14, y: -6)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
    }

    private var volumeSlider: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 10
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.73)).frame(width: width, height: 4)
                Capsule().fill(gold).frame(width: width * player.volume, height: 4)
                Circle().fill(gold).frame(width: 10, height: 10).offset(x: width * player.volume - 5)
            }
            .padding(.leading, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                player.setVolume((event.location.x - 5) / width)
            })
        }
        .frame(height: 30)
        .accessibilityLabel("音量")
        .accessibilityValue(player.volume.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.setVolume(player.volume + 0.05)
            case .decrement: player.setVolume(player.volume - 0.05)
            @unknown default: break
            }
        }
    }

}
