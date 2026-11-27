import AppKit
import SwiftUI

struct ATRACWizard: View {
    private enum Page { case introduction, searching, empty, options, checking, ready, converting, complete }
    let library: Library
    let close: () -> Void
    @State private var page = Page.introduction
    @State private var tracks: [Track] = []
    @State private var format: AudioExportFormat?
    @State private var movesOriginals: Bool?
    @State private var folder: URL?
    @State private var decoder: URL?
    @State private var spaces: [ATRACConversion.Space] = []
    @State private var results: [ATRACConversion.Result] = []
    @State private var current = ""
    @State private var stopping = false
    @State private var stopped = false
    @State private var choosing = false
    @State private var failure: String?
    @State private var showsDetails = false
    @State private var work: Task<Void, Never>?

    init(library: Library, decoder: URL? = AudioCommand.ffmpeg, close: @escaping () -> Void) {
        self.library = library
        self.close = close
        _decoder = State(initialValue: decoder)
    }

    private var busy: Bool { page == .converting || page == .checking || choosing }
    private var canPrepare: Bool { format != nil && movesOriginals != nil && (movesOriginals != true || folder != nil) }
    private var failedCount: Int { results.filter { $0.issue != nil }.count }

    var body: some View {
        LibraryWizardPanel(title: "批量转化ATRAC", contentTop: 10, contentTrailingInset: 50,
                           fontSize: 15, closeTrailingInset: 12, closeDisabled: busy, close: cancel,
                           failure: failure, dismissFailure: { failure = nil }) {
            content
        } controls: {
            controls
        }
        .onDisappear { work?.cancel() }
        .onExitCommand { if failure != nil { failure = nil } else if !busy { cancel() } }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .introduction:
            VStack(alignment: .leading, spacing: 12) {
                Text("在我的音乐库中搜索ATRAC文件，并将其转换为AAC或FLAC格式。")
                Text("备注：\n电脑空间不足时无法执行批量转换。")
                Text("点击【下一项】以开始。")
            }.fixedSize(horizontal: false, vertical: true)
        case .searching:
            LibraryWizardProgress(title: "正在搜索ATRAC文件…")
        case .empty:
            Text("无法在我的音乐库中找到ATRAC文件。\n点击【确定】以结束。")
        case .options:
            options
        case .checking:
            LibraryWizardProgress(title: "正在计算电脑可用储存空间…")
        case .ready:
            VStack(alignment: .leading, spacing: 30) {
                Text("电脑可用储存空间的计算已完成，应用程序已做好转换准备。")
                VStack(alignment: .leading, spacing: 12) {
                    Text("- 硬盘驱动器（总容量）")
                    ForEach(spaces) { space in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("- \(space.name)（\(bytes(space.total))）")
                            Text("目前可用空间 \(bytes(space.available))\n转换后的可用空间 约 \(bytes(max(0, space.available - space.required)))")
                        }.padding(.leading, 10)
                    }
                }.padding(30).frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                    .border(Color(white: 0.86))
                Text("点击【开始】，开始转换。")
            }.fixedSize(horizontal: false, vertical: true)
        case .converting:
            VStack(alignment: .leading, spacing: 25) {
                Text(stopping ? "正在停止转换…" : "正在转换文件…")
                Text(current).lineLimit(2).truncationMode(.middle)
                ProgressView(value: Double(results.count), total: Double(max(1, tracks.count)))
                    .tint(SettingsStyle.gold).padding(.horizontal, 50)
                Text("\(results.count) / \(tracks.count)").frame(maxWidth: .infinity, alignment: .trailing)
            }
        case .complete:
            VStack(alignment: .leading, spacing: 15) {
                Text(stopped ? "文件转换已停止。" : failedCount == 0 ? "文件转换完成。" : "部分文件未能完成转换。")
                if stopped || failedCount > 0 {
                    Text("已转换 \(results.filter { $0.output != nil }.count) 个文件，异常 \(failedCount) 个，未处理 \(tracks.count - results.count) 个。")
                }
                if failedCount > 0 {
                    Button(showsDetails ? "隐藏详情" : "显示详情") { showsDetails.toggle() }
                        .buttonStyle(.plain).underline()
                    if showsDetails {
                        Text(results.compactMap { result in
                            result.issue.map { "\(result.source.url.lastPathComponent)：\n\($0)" }
                        }.joined(separator: "\n\n")).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("在我的音乐库中找到ATRAC文件。\n选择要转换的文件类型，以及转换后要对ATRAC文件执行的操作。")
                .padding(.bottom, 30)
            Text("ATRAC文件要转换的文件类型").foregroundStyle(SettingsStyle.heading).padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 18) {
                formatChoice(.aac, title: "AAC: 优先考虑文件大小", detail: "生成与原始文件大小相近的文件。")
                formatChoice(.flac, title: "FLAC: 优先考虑声音质量", detail: "生成与原始文件声音质量相近，但文件大小倍增的文件。")
            }.padding(.leading, 10)
            Text("文件转换后对ATRAC的操作").foregroundStyle(SettingsStyle.heading).padding(.top, 30).padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 20) {
                ATRACRadio("移动至指定文件夹", selected: movesOriginals == true) { movesOriginals = true }
                HStack(spacing: 10) {
                    Text(folder?.path ?? "").lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                        .frame(height: 32).border(Color(white: 0.63))
                    LibraryWizardSecondary("浏览…", width: 80, action: chooseFolder)
                }.padding(.leading, 40).disabled(movesOriginals != true || choosing)
                ATRACRadio("勿移出原始文件夹", selected: movesOriginals == false) { movesOriginals = false }
            }.padding(.leading, 10)
            Text("点击【下一项】以开始。").padding(.top, 20)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func formatChoice(_ value: AudioExportFormat, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ATRACRadio(title, selected: format == value) { format = value }
            Text(detail).foregroundStyle(SettingsStyle.heading).padding(.leading, 40)
        }
    }

    @ViewBuilder private var controls: some View {
        switch page {
        case .introduction:
            LibraryWizardPrimary(title: "下一页", action: scan)
            LibraryWizardSecondary("取消", action: cancel)
        case .searching:
            LibraryWizardSecondary("取消", action: cancel)
        case .empty, .complete:
            LibraryWizardPrimary(title: "确定", action: close)
        case .options:
            LibraryWizardPrimary(title: "下一页", enabled: canPrepare && !choosing, action: prepare)
            LibraryWizardSecondary("取消", action: cancel).disabled(choosing)
        case .checking:
            LibraryWizardSecondary("取消", action: cancel).disabled(true)
        case .ready:
            LibraryWizardSecondary("后退") { page = .options }
            LibraryWizardPrimary(title: "开始", isDefault: false, action: start)
            LibraryWizardSecondary("取消", action: cancel)
        case .converting:
            LibraryWizardSecondary("停止") { stopping = true; work?.cancel() }.disabled(stopping)
        }
    }

    private func scan() {
        page = .searching
        work = Task {
            let found = ATRACConversion.candidates(in: library.tracks)
            await Task.yield()
            guard !Task.isCancelled else { return }
            tracks = found
            page = found.isEmpty ? .empty : .options
            work = nil
        }
    }

    private func prepare() {
        guard canPrepare else { return }
        guard decoder != nil else { chooseDecoder(); return }
        guard let format else { return }
        let target = movesOriginals == true ? folder : nil
        page = .checking
        work = Task {
            do {
                let found = tracks
                spaces = try await Task.detached { try ATRACConversion.checkSpace(found, format: format, moveOriginalsTo: target) }.value
                page = .ready
            } catch { page = .options; failure = error.localizedDescription }
            work = nil
        }
    }

    private func start() {
        guard page == .ready, let format, let decoder else { return }
        results = []; stopped = false; stopping = false; showsDetails = false; page = .converting
        let target = movesOriginals == true ? folder : nil
        work = Task {
            for track in tracks {
                guard !Task.isCancelled else { stopped = true; break }
                current = track.title
                do {
                    _ = try ATRACConversion.checkSpace([track], format: format, moveOriginalsTo: target)
                    results.append(try await ATRACConversion.convert(track, format: format, decoder: decoder,
                                                                    moveOriginalsTo: target, library: library))
                } catch is CancellationError { stopped = true; break }
                catch { results.append(.init(source: track, output: nil, archivedOriginal: nil, issue: error.localizedDescription)) }
            }
            page = .complete; stopping = false; work = nil
        }
    }

    private func cancel() { guard !busy else { return }; work?.cancel(); close() }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }

    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.title = "选择 ATRAC 原文件移动到的文件夹"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.directoryURL = folder; panel.prompt = "选择"
        choose(panel) { if let url = $0 { folder = url } }
    }
    private func chooseDecoder() {
        let panel = NSOpenPanel(); panel.title = "选择 FFmpeg（ATRAC 解码器）"
        panel.message = "转换 ATRAC 需要本机 FFmpeg。请选择已安装的 ffmpeg 可执行文件。"
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.prompt = "选择"
        choose(panel) { url in
            guard let url else { return }
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                failure = "所选文件不能执行。请选择本机的 ffmpeg。"; return
            }
            decoder = url; prepare()
        }
    }
    private func choose(_ panel: NSOpenPanel, selected: @escaping (URL?) -> Void) {
        choosing = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            choosing = false; selected(response == .OK ? panel.url : nil)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: finish) }
        else { panel.begin(completionHandler: finish) }
    }
}

private struct ATRACRadio: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Circle().strokeBorder(selected ? SettingsStyle.gold : SettingsStyle.ink)
                    .overlay { if selected { Circle().fill(SettingsStyle.gold).padding(2.5) } }
                    .frame(width: 20, height: 20)
                Text(title).fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 24, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
