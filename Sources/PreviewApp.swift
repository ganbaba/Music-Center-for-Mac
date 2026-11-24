import SwiftUI
import UniformTypeIdentifiers

enum LibraryImport {
    case files, folder, playlist

    var contentTypes: [UTType] {
        switch self {
        case .files: [.audio]
        case .folder: [.folder]
        case .playlist: ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
        }
    }
}

@main
struct PreviewApp: App {
    @State private var sampleLibrary = false
    @State private var sampleDevice = false
    @State private var library = Library()
    @State private var preferences = PreviewPreferences()
    @State private var player = Player()
    @State private var importer: LibraryImport?

    var body: some Scene {
        Window("Music Center UI Preview", id: "preview") {
            PrototypeView(showsDevice: true, sampleLibrary: $sampleLibrary, sampleDevice: $sampleDevice,
                          library: library, player: player, importer: $importer, preferences: preferences)
        }
        .defaultSize(width: 1638, height: 914)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入文件…") { importer = .files }
                    .keyboardShortcut("o")
                    .disabled(library.importing)
                Button("导入文件夹…") { importer = .folder }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(library.importing)
                Button("导入播放列表…") { importer = .playlist }
                    .disabled(library.importing)
            }
            CommandMenu("原型") {
                Toggle("显示参考曲库", isOn: $sampleLibrary)
                Toggle("显示已连接的 WALKMAN", isOn: $sampleDevice)
            }
        }
    }
}
