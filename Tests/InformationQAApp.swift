import SwiftUI
import UniformTypeIdentifiers

enum LibraryImport {
    case files, folder, playlist
    var contentTypes: [UTType] { [.audio] }
}

@main
struct InformationQAApp: App {
    private let root: URL
    @State private var library: Library
    @State private var preferences: PreviewPreferences
    @State private var player = Player()
    @State private var sample = true
    @State private var device = false
    @State private var importer: LibraryImport?
    @State private var compact = false
    @State private var result = "运行只读检查…"
    init() {
        let root = URL.temporaryDirectory.appending(path: "music-center-information-qa-" + UUID().uuidString)
        self.root = root
        _library = State(initialValue: Library(directory: root.appending(path: "library")))
        _preferences = State(initialValue: PreviewPreferences(directory: root.appending(path: "preferences")))
    }
    var body: some Scene {
        Window("Music Center Information QA", id: "qa") {
            VStack(spacing: 0) {
                HStack {
                    Toggle("紧凑窗口", isOn: $compact).toggleStyle(.checkbox)
                    Button("黑色背景") { preferences.settings.display.appearance = .black }
                    Button("白色背景") { preferences.settings.display.appearance = .white }
                    Spacer()
                    Text(result).font(.system(size: 10))
                }.padding(.horizontal, 12).frame(height: 30)
                PrototypeView(sampleLibrary: $sample, sampleDevice: $device, library: library, player: player,
                              importer: $importer, preferences: preferences)
            }
            .frame(width: compact ? 800 : 1100, height: compact ? 558 : 760)
            .task {
                do {
                    try await verifyInformation(in: root)
                    result = "PASS · 只读窗口"
                    try root.path.write(to: URL(filePath: "/private/tmp/music-center-information-qa-result.txt"), atomically: true, encoding: .utf8)
                } catch { result = "FAIL: " + error.localizedDescription }
            }
        }.windowResizability(.contentSize)
    }
}
