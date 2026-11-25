import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

enum LibraryImport {
    case files, folder, playlist
    var contentTypes: [UTType] {
        switch self {
        case .files: [.audio]
        case .folder: [.folder]
        case .playlist: [UTType(filenameExtension: "m3u")!]
        }
    }
}

@main
struct MenusQAApp: App {
    private let root: URL
    @State private var library: Library
    @State private var preferences: PreviewPreferences
    @State private var player = Player()
    @State private var sample = false
    @State private var device = false
    @State private var importer: LibraryImport?
    @State private var small = false
    @State private var edgeMenu = false
    @State private var dialogTest = false
    @State private var decision = "未测试"
    @State private var ready = false
    @State private var result = "正在运行检查…"
    init() {
        let root = URL.temporaryDirectory.appending(path: "music-center-menus-qa-data-" + UUID().uuidString)
        self.root = root
        _library = State(initialValue: Library(directory: root.appending(path: "library")))
        _preferences = State(initialValue: PreviewPreferences(directory: root.appending(path: "preferences")))
    }
    var body: some Scene {
        Window("Music Center Menus QA", id: "qa") {
            VStack(spacing: 0) {
                HStack {
                    Toggle("紧凑窗口", isOn: $small).toggleStyle(.checkbox)
                    Button("测试错误提示") { player.error = "无法播放此文件的音频流。" }
                    Toggle("参考曲库", isOn: $sample).toggleStyle(.checkbox)
                    Button("边缘菜单") { edgeMenu = true }
                    Button("确认键盘") { dialogTest = true }
                    Text(decision).font(.system(size: 10))
                    Spacer()
                    Text("\(library.tracks.count)首 / \(library.playlists.count)列表 / \(player.queue.count)队列").font(.system(size: 11))
                }.padding(.horizontal, 12).frame(height: 30)
                if ready {
                    PrototypeView(sampleLibrary: $sample, sampleDevice: $device, library: library, player: player,
                        importer: $importer, preferences: preferences)
                } else { Text(result).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .frame(width: small ? 800 : 1100, height: small ? 558 : 760)
            .overlay {
                if edgeMenu {
                    GeometryReader { geometry in
                        WindowsMenu(entries: [WindowsMenuEntry(id: "long", title: "添加到播放列表", children:
                            (1...50).map { index in WindowsMenuEntry(id: "list-\(index)", title: String(format: "播放列表 %03d", index), action: { decision = "选择 \(index)" }) })],
                            width: 164, origin: CGPoint(x: geometry.size.width - 5, y: geometry.size.height - 5), viewport: geometry.size,
                            title: "边缘菜单验收", close: { edgeMenu = false })
                    }
                }
            }
            .overlay {
                if dialogTest {
                    ZStack {
                        Color.black.opacity(0.001).contentShape(Rectangle())
                        WindowsDialog(message: "删除确认的键盘取消验收（隔离状态，不删除数据）。", symbol: .warning,
                            buttons: [WindowsDialogButton("yes", "是") { decision = "确认：是" }, WindowsDialogButton("no", "否") { decision = "确认：否" }],
                            defaultButton: "no", cancelButton: "no", dismiss: { dialogTest = false })
                    }
                }
            }
            .task {
                guard !ready else { return }
                do {
                    try await verifyMenus(in: root.appending(path: "menu-smoke"))
                    try await verifyProperties(in: root.appending(path: "properties-smoke"))
                    try verifySettingsPreferences(in: root.appending(path: "settings-smoke"))
                    try await seed()
                    ready = true
                    result = "PASS"
                    try root.path.write(to: URL(filePath: "/private/tmp/music-center-menus-qa-result.txt"), atomically: true, encoding: .utf8)
                } catch {
                    result = "FAIL: \(error.localizedDescription)"
                    try? result.write(to: URL(filePath: "/private/tmp/music-center-menus-qa-result.txt"), atomically: true, encoding: .utf8)
                }
            }
        }.windowResizability(.contentSize)
    }
    private func seed() async throws {
        let cover = Bundle.main.url(forResource: "CapturedCover", withExtension: "png").flatMap { try? Data(contentsOf: $0) }
        var additions: [(Track, URL)] = []
        for (i, row) in CapturedLibrary.tracks.enumerated() {
            let url = library.directory.appending(path: "Track \(i + 1).wav")
            if i != 3 {
                let file = try AVAudioFile(forWriting: url, settings: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!.settings)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000)!
                buffer.frameLength = 48_000
                for channel in 0..<2 { memset(buffer.floatChannelData![channel], 0, 48_000 * 4) }
                try file.write(from: buffer)
            }
            additions.append((Track(id: UUID(), url: url, title: row.title, artist: row.artist, album: CapturedLibrary.album,
                duration: 1, albumArtist: CapturedLibrary.albumArtist, disc: 1, number: i + 1, artwork: cover), url))
        }
        library.registerCopiedAudio(additions)
        let tracks = library.tracks.sorted { $0.number! < $1.number! }
        let playlistFile = root.appending(path: "UI 截图参考.m3u8")
        try ("#EXTM3U\n" + [tracks[0], tracks[0], tracks[1]].map { $0.url.absoluteString }.joined(separator: "\n")).write(to: playlistFile, atomically: true, encoding: .utf8)
        guard await library.importPlaylist(playlistFile) else { throw PropertyFailure(message: "Cannot seed duplicate playlist") }
        _ = library.createPlaylist("菜单验收列表", tracks: tracks)
        player.enqueue([Player.Item(track: tracks[0]), Player.Item(track: tracks[0]), Player.Item(track: tracks[1])], placement: .end)
        library.message = nil
    }
}
