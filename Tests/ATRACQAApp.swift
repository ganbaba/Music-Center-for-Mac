import SwiftUI
import UniformTypeIdentifiers

enum LibraryImport {
    case files, folder, playlist
    var contentTypes: [UTType] { [.audio] }
}

@main
struct ATRACQAApp: App {
    private let root: URL
    private let decoder: URL
    private let sample: URL
    private let slowDecoder: URL
    private let validArguments: Bool
    @State private var library: Library
    @State private var preferences: PreviewPreferences
    @State private var player = Player()
    @State private var sampleLibrary = false
    @State private var sampleDevice = false
    @State private var importer: LibraryImport?
    @State private var compact = false
    @State private var hasDecoder = true
    @State private var result = "正在验证…"

    init() {
        let args = CommandLine.arguments
        validArguments = args.count == 5
        root = args.count == 5 ? URL(filePath: args[1], directoryHint: .isDirectory)
            : URL.temporaryDirectory.appending(path: "music-center-atrac-ui-" + UUID().uuidString)
        sample = URL(filePath: args.count == 5 ? args[2] : "/invalid")
        decoder = URL(filePath: args.count == 5 ? args[3] : "/invalid")
        slowDecoder = URL(filePath: args.count == 5 ? args[4] : "/invalid")
        _library = State(initialValue: Library(directory: root.appending(path: "ui-library")))
        _preferences = State(initialValue: PreviewPreferences(directory: root.appending(path: "ui-preferences")))
    }

    var body: some Scene {
        Window("Music Center ATRAC QA", id: "atrac-qa") {
            VStack(spacing: 0) {
                HStack {
                    Toggle("紧凑窗口", isOn: $compact).toggleStyle(.checkbox)
                    Toggle("提供解码器", isOn: $hasDecoder).toggleStyle(.checkbox)
                    Button("加入 ATRAC") {
                        Task { await addSample() }
                    }
                    Button("加入损坏文件") {
                        Task {
                            let url = root.appending(path: "invalid.oma")
                            try? Data("invalid ATRAC".utf8).write(to: url)
                            await library.importItems([url])
                        }
                    }
                    Spacer(); Text(result).font(.system(size: 10))
                }.padding(.horizontal, 12).frame(height: 28)
                PrototypeView(sampleLibrary: $sampleLibrary, sampleDevice: $sampleDevice, library: library,
                              player: player, importer: $importer, preferences: preferences,
                              atracDecoder: hasDecoder ? slowDecoder : nil)
            }.frame(width: compact ? 800 : 1100, height: compact ? 550 : 710)
                .task {
                    guard validArguments else { result = "请通过测试脚本提供临时目录、样例和解码器参数。"; return }
                    do {
                        try await verifyProperties(in: root.appending(path: "property-smoke"))
                        try await verifyATRAC(in: root.appending(path: "atrac-smoke"), sample: sample,
                                              decoder: decoder, slowDecoder: slowDecoder)
                        await addSample()
                        result = "PASS · ATRAC 验证"
                    } catch { result = "FAIL: " + error.localizedDescription }
                    try? result.write(to: root.appending(path: "qa-result.txt"), atomically: true, encoding: .utf8)
                }
        }.windowResizability(.contentSize)
    }

    private func addSample() async {
        let file = root.appending(path: UUID().uuidString + ".oma")
        do { try FileManager.default.copyItem(at: sample, to: file); await library.importItems([file]) }
        catch { result = "FAIL: " + error.localizedDescription }
    }
}
