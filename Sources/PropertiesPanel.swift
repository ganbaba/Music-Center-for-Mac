import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct PropertiesPanel: View {
    let request: PropertiesRequest
    let records: [PropertyKey: PropertyRecord]
    let history: [UUID: TrackPlayback]
    let choices: [PropertyField: [String]]
    let equalizerNames: [String]
    let height: CGFloat
    let save: ([PropertyChange]) throws -> Void
    let close: () -> Void
    private let draftSlots: [PropertyKey: Int]
    @State private var index: Int
    @State private var drafts: [PropertyDraft]
    @State private var tab = "常规"
    @State private var fileFacts: [PropertyKey: PropertyFileFacts] = [:]
    @State private var loaded: Set<PropertyKey> = []
    @State private var message: String?

    init(request: PropertiesRequest, records: [PropertyKey: PropertyRecord], history: [UUID: TrackPlayback],
         choices: [PropertyField: [String]], equalizerNames: [String], height: CGFloat = 690,
         save: @escaping ([PropertyChange]) throws -> Void, close: @escaping () -> Void) {
        self.request = request
        self.records = records
        self.history = history
        self.choices = choices
        self.equalizerNames = equalizerNames
        self.height = height
        self.save = save
        self.close = close
        _index = State(initialValue: request.selectedIndex)
        var slots: [PropertyKey: Int] = [:]
        var drafts: [PropertyDraft] = []
        for subject in request.subjects where slots[subject.key] == nil {
            slots[subject.key] = drafts.count
            drafts.append(PropertyDraft(subject: subject, records: records))
        }
        draftSlots = slots
        _drafts = State(initialValue: drafts)
    }

    private var subject: PropertySubject { request.subjects[index] }
    private var draftIndex: Int { draftSlots[subject.key]! }
    private var artworkTab: String { subject.key.kind == .artist ? "艺术家照片" : "封面图样" }
    private var tabs: [String] { ["常规"] + (subject.hasArtworkTab ? [artworkTab] : []) + (subject.hasFileTab ? ["文件"] : []) }
    private var duration: String { previewTime(subject.tracks.reduce(0) { $0 + $1.seconds }) }
    private var size: String { subject.tracks.reduce(0) { $0 + $1.sizeMB }.formatted(.number.precision(.fractionLength(0...1))) + "MB" }
    private var dateRegistered: Date? { subject.key.kind == .playlist ? records[subject.key]?.createdAt : subject.tracks.compactMap { $0.localTrack?.registeredAt }.min() }
    private var facts: PropertyFileFacts? { fileFacts[subject.key] }

    var body: some View {
        VStack(spacing: 0) {
            Text(subject.title).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 50).frame(maxWidth: .infinity).frame(height: 48)
                .overlay(alignment: .trailing) {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Color(white: 0.48))
                            .frame(width: 36, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("关闭属性").padding(.trailing, 6)
                }
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item).frame(minWidth: 68).frame(height: 33)
                            .overlay(alignment: .bottom) {
                                if tab == item { Rectangle().fill(SettingsStyle.gold).frame(height: 2) }
                            }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16)
            Group {
                if tab == "常规" { general }
                else if tab == "文件" { filePage }
                else { artworkPage }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 10).padding(.bottom, 12)
            HStack(spacing: 9) {
                SettingsAction("上一首") { navigate(-1) }.disabled(index == 0)
                SettingsAction("下一首") { navigate(1) }.disabled(index + 1 == request.subjects.count)
                Spacer()
                Button(action: confirm) {
                    Text("确定").foregroundStyle(.white).frame(width: 96, height: 27).background(SettingsStyle.gold)
                }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
                SettingsAction("取消", action: close).keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 16).padding(.bottom, 14)
        }
        .font(.system(size: 12)).foregroundStyle(SettingsStyle.ink)
        .frame(width: 640, height: height)
        .modifier(SettingsDropdownHost(resetID: "\(index)-\(tab)"))
        .environment(\.colorScheme, .light)
        .background(.white).compositingGroup().shadow(color: .black.opacity(0.45), radius: 7, y: 2)
        .accessibilityElement(children: .contain).accessibilityLabel("属性")
        .alert("Music Center UI Preview", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定") { message = nil }
        } message: { Text(message ?? "") }
        .task(id: subject.key) {
            let key = subject.key
            guard !loaded.contains(key) else { return }
            let current = subject
            let task = Task.detached(priority: .userInitiated) { await PropertySourceValues.read(current) }
            let source = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled, let position = drafts.firstIndex(where: { $0.subject.key == key }) else { return }
            drafts[position].mergeSource(source.tags, records: records)
            fileFacts[key] = source.file
            loaded.insert(key)
        }
    }

    private var general: some View {
        SettingsScroll {
            VStack(alignment: .leading, spacing: 12) {
                switch subject.key.kind {
                case .song, .selection: songFields
                case .album: albumFields
                case .artist:
                    comboRow("艺术家：", .artist)
                    textRow("艺术家(分类方式)：", .artistSort)
                case .playlist: playlistFields
                }
            }
            .padding(.leading, 20).padding(.trailing, subject.key.kind == .artist ? 20 : 14).padding(.bottom, 8)
        }
    }

    @ViewBuilder private var songFields: some View {
        textRow("标题：", .title, disabled: subject.isMultiple, highResolution: true)
        textRow("标题(分类方式)：", .titleSort, disabled: subject.isMultiple, highResolution: true)
        comboRow("艺术家：", .artist)
        textRow("艺术家(分类方式)：", .artistSort)
        textRow("专辑：", .album)
        textRow("专辑(分类方式)：", .albumSort)
        comboRow("专辑艺术家：", .albumArtist)
        textRow("专辑艺术家(分类方式)：", .albumArtistSort)
        comboRow("类型：", .genre)
        textRow("发行年份：", .year)
        textRow("作曲家：", .composer)
        dropdownRow("均衡器：", .equalizer, values: ["关"] + equalizerNames)
        numberRow("歌曲编号：", .number, .totalTracks)
        numberRow("歌碟编号：", .disc, .totalDiscs)
        valueRow("歌曲长度：", duration)
        fieldRow("评价：") {
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        let old = Int(drafts[draftIndex].fields[.rating] ?? "0") ?? 0
                        set(old == value ? "0" : String(value), field: .rating)
                    } label: {
                        let selected = value <= (Int(drafts[draftIndex].fields[.rating] ?? "0") ?? 0)
                        Image(systemName: selected ? "star.fill" : "star").font(.system(size: 14))
                            .foregroundStyle(selected ? SettingsStyle.gold : SettingsStyle.ink)
                            .frame(width: 22, height: 26)
                    }.buttonStyle(.plain).accessibilityLabel("\(value)星")
                }
            }
        }
        dropdownRow("类型：", .mediaType, values: ["歌曲", "有声读物"])
        if !subject.isMultiple {
            HStack {
                Spacer(minLength: 0)
                SettingsAction("获取歌曲信息", width: 380) { message = "Gracenote 音乐识别服务尚未接入。" }
                Spacer(minLength: 0)
            }.padding(.top, 20)
        }
    }

    @ViewBuilder private var albumFields: some View {
        textRow("标题：", .title)
        textRow("标题(分类方式)：", .titleSort)
        comboRow("艺术家：", .artist)
        textRow("艺术家(分类方式)：", .artistSort)
        comboRow("类型：", .genre)
        textRow("发行年份：", .year)
        dropdownRow("均衡器：", .equalizer, values: ["关"] + equalizerNames)
        statsPair("歌曲：", "\(subject.tracks.count)", "歌曲长度：", duration)
        statsPair("文件大小：", size, "最后注册：", dateLabel(dateRegistered))
        dropdownRow("类型：", .mediaType, values: ["歌曲", "有声读物"]).padding(.top, 20)
    }

    @ViewBuilder private var playlistFields: some View {
        textRow("标题：", .title)
        textRow("标题(分类方式)：", .titleSort)
        statsPair("歌曲：", "\(subject.tracks.count)", "歌曲长度：", duration)
        statsPair("文件大小：", size, "最后注册：", dateLabel(dateRegistered))
        statsPair("最后更新：", dateLabel(records[subject.key]?.modifiedAt), "", "")
        Divider().padding(.horizontal, 22).padding(.vertical, 8)
        textRow("创建者：", .creator)
        textRow("来源：", .source)
        fieldRow("注释：") {
            TextEditor(text: binding(.comment)).font(.system(size: 12)).scrollContentBackground(.hidden).scrollIndicators(.never)
                .padding(3).frame(height: 62).background(.white).border(Color(white: 0.42))
                .accessibilityLabel("注释")
        }
    }

    private var artworkPage: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                if let data = drafts[draftIndex].artwork, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Rectangle().fill(Color(white: subject.key.kind == .playlist ? 0.72 : 0.90))
                    Image(systemName: subject.key.kind == .playlist ? "list.bullet.below.rectangle" : "music.note")
                        .font(.system(size: 90, weight: .light))
                        .foregroundStyle(Color(white: subject.key.kind == .playlist ? 0.92 : 0.66))
                }
            }
            .frame(width: 240, height: 240)
            .accessibilityLabel(artworkTab)
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                SettingsAction(subject.key.kind == .artist ? "注册艺术家相片…" : "选择封面图样…", width: 188, action: chooseArtwork)
                SettingsAction("删除", width: 188) {
                    drafts[draftIndex].artwork = nil
                    drafts[draftIndex].changesArtwork = true
                }
                if subject.key.kind == .song || subject.key.kind == .album {
                    Spacer().frame(height: 84)
                    SettingsAction("获取封面图样", width: 188) { message = "Gracenote 封面图样获取服务尚未接入。" }
                    SettingsAction("转换封面图样", width: 188) { convertArtwork() }
                }
            }
        }
        .padding(.horizontal, 20).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filePage: some View {
        SettingsScroll {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("目标地：")
                        Text(facts?.path ?? subject.tracks.first?.localTrack?.url.path ?? "—")
                            .foregroundStyle(Color(white: 0.45)).underline().textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SettingsAction("移动到其他文件夹…", width: 122) {
                        message = "暂不支持从属性窗口移动源音频文件。"
                    }.padding(.top, 12)
                }
                VStack(alignment: .leading, spacing: 0) { Text("注册文件格式："); Text(facts?.format ?? "—") }
                statsPair("比特率：", facts?.bitrate ?? "—", "采样频率：", facts?.sampleRate ?? "—")
                statsPair("量化比特率：", facts?.sampleBits ?? "—", "文件大小：", facts?.size ?? size)
                statsPair("声道数量：", facts?.channels ?? "—", "12 TONE ANALYSIS：", "未分析")
                Divider().padding(.horizontal, 22).padding(.vertical, 8)
                statsPair("最后注册：", dateLabel(dateRegistered), "最后更新：", dateLabel(records[subject.key]?.modifiedAt ?? facts?.modifiedAt))
                statsPair("最后播放：", dateLabel(currentPlayback?.lastPlayedAt), "播放次数：", currentPlayback.map { String($0.count) } ?? "0")
                VStack(alignment: .leading, spacing: 0) { Text("累计传送的专辑："); Text("—") }
                Divider().padding(.horizontal, 22).padding(.vertical, 8)
                VStack(alignment: .leading, spacing: 18) {
                    Text("唱片公司信息：" + (drafts[draftIndex].fields[.label] ?? ""))
                    Text("发行商：\n" + (drafts[draftIndex].fields[.publisher] ?? ""))
                    Text("版权信息：\n" + (drafts[draftIndex].fields[.copyright] ?? ""))
                }.padding(.bottom, 16)
            }
            .padding(.leading, 20).padding(.trailing, 20)
        }
    }

    private var currentPlayback: TrackPlayback? {
        subject.tracks.first?.localTrack.flatMap { history[$0.id] }
    }
    private func textRow(_ title: String, _ field: PropertyField, disabled: Bool = false, highResolution: Bool = false) -> some View {
        fieldRow(title) {
            TextField("", text: binding(field)).textFieldStyle(.plain).padding(.horizontal, 6)
                .frame(height: 26).background(disabled ? Color(white: 0.95) : .white).border(Color(white: 0.42))
                .disabled(disabled).accessibilityLabel(title)
                .overlay(alignment: .leading) {
                    if highResolution, !subject.isMultiple,
                       subject.tracks.first?.localTrack == nil || (Double(facts?.sampleBits.split(separator: " ").first ?? "") ?? 0) > 16 {
                        Text("HR").font(.system(size: 10)).foregroundStyle(SettingsStyle.gold)
                            .padding(.horizontal, 1).border(SettingsStyle.gold).offset(x: -23)
                    }
                }
        }
    }
    private func comboRow(_ title: String, _ field: PropertyField) -> some View {
        fieldRow(title) { SettingsCombo(title: title, selection: binding(field), options: comboOptions(field)) }
    }
    private func dropdownRow(_ title: String, _ field: PropertyField, values: [String]) -> some View {
        let current = drafts[draftIndex].fields[field] ?? ""
        let available = values.contains(current) ? values : [current] + values
        return fieldRow(title) {
            SettingsDropdown(title: title, selection: binding(field), options: available.map { SettingsDropdownOption(value: $0, title: $0) })
        }
    }
    private func comboOptions(_ field: PropertyField) -> [String] {
        let current = drafts[draftIndex].fields[field] ?? ""
        let choiceField: PropertyField = field == .artist &&
            (subject.key.kind == .album || (subject.key.kind == .artist && !subject.artistByTrack)) ? .albumArtist : field
        return Array(Set([current] + (choices[choiceField] ?? []))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private func numberRow(_ title: String, _ numerator: PropertyField, _ denominator: PropertyField) -> some View {
        fieldRow(title) {
            HStack(spacing: 12) {
                TextField("", text: binding(numerator)).textFieldStyle(.plain).padding(.horizontal, 6)
                    .frame(width: 48, height: 26).background(subject.isMultiple ? Color(white: 0.95) : .white)
                    .border(Color(white: 0.42)).disabled(subject.isMultiple).accessibilityLabel(title)
                Text("/")
                TextField("", text: binding(denominator)).textFieldStyle(.plain).padding(.horizontal, 6)
                    .frame(width: 48, height: 26).border(Color(white: 0.42)).accessibilityLabel(title + "总数")
            }
        }
    }
    private func valueRow(_ title: String, _ value: String) -> some View { fieldRow(title) { Text(value).frame(height: 26) } }
    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label).frame(width: 194, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func statsPair(_ label1: String, _ value1: String, _ label2: String, _ value2: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) { Text(label1); Text(value1) }.frame(width: 300, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) { Text(label2); Text(value2) }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 10)
    }
    private func dateLabel(_ date: Date?) -> String {
        date?.formatted(Date.FormatStyle().year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).locale(Locale(identifier: "zh_CN"))) ?? "—"
    }
    private func binding(_ field: PropertyField) -> Binding<String> {
        Binding(get: { drafts[draftIndex].fields[field] ?? "" }, set: { set($0, field: field) })
    }
    private func set(_ value: String, field: PropertyField) { drafts[draftIndex].set(value, for: field) }
    private func navigate(_ delta: Int) {
        let next = index + delta
        guard request.subjects.indices.contains(next) else { return }
        index = next
        if !tabs.contains(tab) { tab = "常规" }
    }
    private func confirm() {
        let changes = drafts.map(\.change).filter { !$0.fields.isEmpty || $0.changesArtwork }
        do {
            for change in changes { try change.validate() }
            if !changes.isEmpty { try save(changes) }
            close()
        } catch { message = error.localizedDescription }
    }
    private func chooseArtwork() {
        let target = draftIndex
        let panel = NSOpenPanel()
        panel.title = subject.key.kind == .artist ? "注册艺术家相片" : "选择封面图样"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                guard let converted = Self.imageData(data) else { throw PropertyFailure(message: "无法读取所选图片。") }
                drafts[target].artwork = converted
                drafts[target].changesArtwork = true
            } catch { message = error.localizedDescription }
        }
    }
    private func convertArtwork() {
        guard let data = drafts[draftIndex].artwork, let converted = Self.imageData(data) else { message = "请先选择封面图样。"; return }
        drafts[draftIndex].artwork = converted
        drafts[draftIndex].changesArtwork = true
    }
    private static func imageData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { return nil }
        let bytes = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.90] as CFDictionary)
        return CGImageDestinationFinalize(output) ? bytes as Data : nil
    }
}
