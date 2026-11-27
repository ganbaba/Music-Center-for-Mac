import SwiftUI
import UniformTypeIdentifiers

enum LibraryImport {
    case files, folder, playlist
    var contentTypes: [UTType] { [.audio] }
}

@main
struct WizardsQAApp: App {
    private let root: URL
    @State private var library: Library
    @State private var preferences: PreviewPreferences
    @State private var player = Player()
    @State private var sample = false
    @State private var device = false
    @State private var importer: LibraryImport?
    @State private var compact = false
    @State private var result = "正在验证…"

    init() {
        let root = CommandLine.arguments.count > 1
            ? URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
            : URL.temporaryDirectory.appending(path: "music-center-wizards-qa-" + UUID().uuidString)
        self.root = root
        _library = State(initialValue: Library(directory: root.appending(path: "ui-library")))
        _preferences = State(initialValue: PreviewPreferences(directory: root.appending(path: "ui-preferences")))
    }

    var body: some Scene {
        Window("Music Center Wizards QA", id: "wizards-qa") {
            VStack(spacing: 0) {
                HStack {
                    Toggle("紧凑窗口", isOn: $compact).toggleStyle(.checkbox)
                    Spacer()
                    Text(result).font(.system(size: 11))
                }.padding(.horizontal, 12).frame(height: 28)
                PrototypeView(sampleLibrary: $sample, sampleDevice: $device, library: library,
                              player: player, importer: $importer, preferences: preferences)
            }.frame(width: compact ? 800 : 1100, height: compact ? 550 : 710)
                .task {
                    do {
                        try await verifyProperties(in: root.appending(path: "property-smoke"))
                        await library.importItems((1...3).map { root.appending(path: "property-smoke/\($0).wav") })
                        result = library.error.map { "FAIL: " + $0 } ?? "PASS · 备份恢复验证"
                    } catch {
                        result = "FAIL: " + error.localizedDescription
                    }
                    try? result.write(to: root.appending(path: "qa-result.txt"), atomically: true, encoding: .utf8)
                }
        }.windowResizability(.contentSize)
    }
}
