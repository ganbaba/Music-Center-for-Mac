import SwiftUI
import UniformTypeIdentifiers

enum LibraryImport {
    case files, folder, playlist
    var contentTypes: [UTType] { [.audio] }
}

@main
struct SettingsQAApp: App {
    @State private var preferences = PreviewSettings()
    @State private var shown = true
    @State private var small = false
    init() {
        do { try verifySettingsPreferences(in: FileManager.default.temporaryDirectory.appending(path: "music-center-settings-smoke-" + UUID().uuidString, directoryHint: .isDirectory)) }
        catch { fatalError("Settings preferences smoke failed: \(error)") }
    }
    var body: some Scene {
        Window("Music Center Settings QA", id: "qa") {
            ZStack {
                Color(white: 0.94)
                if shown {
                    SettingsPreview(page: .display, settings: preferences, height: small ? 518 : 690,
                        cdDrives: [], refreshCDDrives: {}) {
                            preferences = $0
                            shown = false
                        } cancel: { shown = false }
                } else {
                    VStack {
                        Text("已保存：" + preferences.display.textSize.rawValue + " / " + preferences.display.appearance.rawValue)
                        Button("打开设置") { shown = true }
                    }
                }
            }
            .frame(width: 760, height: small ? 558 : 730)
            .environment(\.colorScheme, .light)
        }
        .windowResizability(.contentSize)
        .commands { CommandMenu("验收") { Toggle("紧凑窗口", isOn: $small) } }
    }
}
