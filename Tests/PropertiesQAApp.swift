import SwiftUI
import UniformTypeIdentifiers

enum LibraryImport {
    case files, folder, playlist
    var contentTypes: [UTType] { [.audio] }
}

@main
struct PropertiesQAApp: App {
    @State private var library = Library(directory: .temporaryDirectory.appending(path: "music-center-properties-ui-" + UUID().uuidString))
    @State private var request: PropertiesRequest?
    @State private var small = false
    @State private var result = "正在验证属性…"
    @State private var showSettings = false
    @State private var settings = PreviewSettings()
    private var rows: [CapturedTrack] { library.tracks.sorted { ($0.number ?? 0) < ($1.number ?? 0) }.map(CapturedTrack.init) }
    var body: some Scene {
        Window("Music Center Properties QA", id: "qa") {
            VStack(spacing: 6) {
                HStack {
                    ForEach(["单曲", "多选", "专辑", "艺术家", "播放列表"], id: \.self) { name in
                        Button(name) { open(name) }.disabled(rows.isEmpty)
                    }
                    Toggle("紧凑窗口", isOn: $small).toggleStyle(.checkbox)
                    Button("设置回归") { request = nil; showSettings = true }
                }.padding(.top, 6)
                ZStack {
                    Color(white: 0.94)
                    if showSettings {
                        SettingsPreview(page: .display, settings: settings, height: small ? 518 : 690, cdDrives: [], refreshCDDrives: {}) {
                            settings = $0; showSettings = false
                        } cancel: { showSettings = false }
                    } else if let request {
                        PropertiesPanel(request: request, records: library.propertyRecords, history: library.playbackHistory,
                            choices: [.artist: ["光田康典", "平松建治"], .albumArtist: [CapturedLibrary.albumArtist], .genre: ["Game", "Soundtrack", "Classical"]],
                            equalizerNames: EqualizerSettings.builtIns.map(\.name), height: small ? 518 : 690,
                            save: { changes in try library.saveProperties(changes); self.request = nil }, close: { self.request = nil })
                            .id(request.id)
                    } else {
                        VStack { Text(result); Text("本地测试曲库：\(library.tracks.count) 首") }.padding()
                    }
                }.frame(width: 760, height: small ? 558 : 730)
            }
            .environment(\.colorScheme, .light)
            .task {
                guard rows.isEmpty else { return }
                let root = URL.temporaryDirectory.appending(path: "music-center-properties-smoke-" + UUID().uuidString)
                do {
                    try await verifyProperties(in: root)
                    try seed()
                    result = "PASS：属性保存、批量编辑与备份恢复"
                    try root.path.write(to: URL(filePath: "/private/tmp/music-center-properties-qa-result.txt"), atomically: true, encoding: .utf8)
                    open("单曲")
                } catch {
                    result = "FAIL：\(error.localizedDescription)"
                    try? result.write(to: URL(filePath: "/private/tmp/music-center-properties-qa-result.txt"), atomically: true, encoding: .utf8)
                }
            }
        }.windowResizability(.contentSize)
    }
    private func open(_ name: String) {
        guard !rows.isEmpty else { return }
        showSettings = false
        switch name {
        case "多选": request = PropertiesRequest(subjects: [.songs(rows)])
        case "专辑", "艺术家":
            let artist = name == "艺术家"
            let groups = TrackCollection.group(rows, by: artist ? .artists : .albums)
            request = PropertiesRequest(subjects: groups.map { .collection($0, artist: artist, byTrack: false) })
        case "播放列表":
            let list = library.playlists[0]
            request = PropertiesRequest(subjects: [.playlist(PlaylistGroup(playlist: list, tracks: rows))])
        default: request = PropertiesRequest(subjects: rows.map { .songs([$0]) })
        }
    }
    private func seed() throws {
        var additions: [(Track, URL)] = []
        let cover = Bundle.main.url(forResource: "CapturedCover", withExtension: "png").flatMap { try? Data(contentsOf: $0) }
        for (i, row) in CapturedLibrary.tracks.enumerated() {
            let url = library.directory.appending(path: "Track \(i + 1).wav")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 96_000,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let audio = try AVAudioFile(forWriting: url, settings: settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 96_000)!
            buffer.frameLength = 96_000
            for channel in 0..<Int(buffer.format.channelCount) { memset(buffer.floatChannelData![channel], 0, 96_000 * 4) }
            try audio.write(from: buffer)
            additions.append((Track(id: UUID(), url: url, title: row.title, artist: row.artist, album: CapturedLibrary.album,
                duration: 1, albumArtist: CapturedLibrary.albumArtist, disc: 1, number: i + 1, artwork: cover), url))
        }
        library.registerCopiedAudio(additions)
        for row in rows {
            try library.saveProperties([PropertyChange(subject: .songs([row]), fields: [.genre: "Game", .year: "2018", .composer: row.artist,
                .titleSort: "", .totalTracks: "105", .totalDiscs: "6"])])
        }
        _ = library.createPlaylist("UI 截图参考", tracks: library.tracks)
    }
}
