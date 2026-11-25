import AppKit
import SwiftUI

struct WalkmanFolder: Identifiable, Sendable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct WalkmanFileIdentity: Sendable {
    let url: URL
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modified: timespec

    static func read(_ url: URL) throws -> Self {
        var file = stat()
        guard lstat(url.path, &file) == 0, file.st_mode & S_IFMT == S_IFREG else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return Self(url: url, device: file.st_dev, inode: file.st_ino, size: file.st_size, modified: file.st_mtimespec)
    }

    func matchesCurrentFile() -> Bool {
        guard let current = try? Self.read(url) else { return false }
        return current.device == device && current.inode == inode && current.size == size
            && current.modified.tv_sec == modified.tv_sec && current.modified.tv_nsec == modified.tv_nsec
    }
}

enum WalkmanFiles {
    struct Contents: Sendable {
        let folders: [WalkmanFolder]
        let tracks: [Track]
    }

    static func directory(_ folders: [String], on volume: WalkmanVolume) throws -> URL {
        try volume.checkMount()
        guard let music = volume.music else { throw CocoaError(.fileReadNoSuchFile) }
        var directory = music
        for name in folders {
            guard name != ".", name != "..", !name.contains("/"), !name.isEmpty else { throw CocoaError(.fileReadInvalidFileName) }
            directory.append(path: name, directoryHint: .isDirectory)
            var entry = stat()
            guard lstat(directory.path, &entry) == 0, entry.st_mode & S_IFMT == S_IFDIR,
                  entry.st_dev == volume.id.filesystem else { throw CocoaError(.fileReadNoSuchFile) }
        }
        return directory
    }

    static func contents(_ folders: [String], on volume: WalkmanVolume) async throws -> Contents {
        let directory = try directory(folders, on: volume)
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])
        var folders: [WalkmanFolder] = []
        var files: [URL] = []
        for url in entries {
            var entry = stat()
            guard lstat(url.path, &entry) == 0, entry.st_dev == volume.id.filesystem else { continue }
            if entry.st_mode & S_IFMT == S_IFDIR { folders.append(WalkmanFolder(url: url)) }
            if entry.st_mode & S_IFMT == S_IFREG { files.append(url) }
        }
        let tracks = await TrackScanner.scan(files)
        try Task.checkCancellation()
        try volume.checkMount()
        return Contents(folders: folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                        tracks: tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
    }

    static func remove(_ selected: [WalkmanFileIdentity], folders: [String], on volume: WalkmanVolume) throws {
        let parent = try directory(folders, on: volume)
        for file in selected {
            try Task.checkCancellation()
            try volume.checkMount()
            guard file.url.deletingLastPathComponent() == parent, file.matchesCurrentFile() else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "设备上的文件已有变化，请刷新后重试。"])
            }
            try FileManager.default.removeItem(at: file.url)
        }
    }
}

struct WalkmanManagement: View {
    let volume: WalkmanVolume
    let connected: Bool
    let close: () -> Void
    let reconnect: (() -> Void)?
    let importTracks: ([Track], URL) -> Void
    @State private var folders: [String] = []
    @State private var contents = WalkmanFiles.Contents(folders: [], tracks: [])
    @State private var selected: Set<UUID> = []
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var error: String?
    @State private var pendingDeletion: [WalkmanFileIdentity] = []
    @State private var revision = 0
    private struct Location: Hashable {
        let device: WalkmanVolume.Identity
        let folders: [String]
        let revision: Int
    }

    private var selectedTracks: [Track] { contents.tracks.filter { selected.contains($0.id) } }
    private var path: String { (["MUSIC"] + folders).joined(separator: " / ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(volume.name).font(.system(size: 29))
                    Text(volume.available.map { "可用空间 " + deviceBytes($0) } ?? volume.label)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") { revision += 1 }.disabled(loading || !connected)
                if !connected, let reconnect { Button("访问 WALKMAN", action: reconnect) }
                Button("返回曲库", action: close)
            }
            HStack(spacing: 12) {
                Button { folders.removeLast() } label: { Image(systemName: "chevron.left") }
                    .disabled(folders.isEmpty || loading)
                    .accessibilityLabel("上一级")
                Text(path).font(.system(size: 12)).lineLimit(2)
                Spacer()
            }
            if !connected {
                Label(reconnect == nil ? "设备已断开。请重新连接 WALKMAN。" : "已检测到 WALKMAN。点击「访问 WALKMAN」继续。",
                      systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.red)
            }
            Text("歌曲").foregroundStyle(Color(red: 0.70, green: 0.57, blue: 0.29))
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.70, green: 0.57, blue: 0.29)).frame(height: 2) }
            if loading { ProgressView("正在读取设备歌曲…") }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Text("标题").frame(maxWidth: .infinity, alignment: .leading)
                Text("艺术家").frame(width: 130, alignment: .leading)
                Text("专辑").frame(width: 160, alignment: .leading)
                Text("格式").frame(width: 45)
                Text("歌曲长度").frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            List(selection: $selected) {
                ForEach(contents.folders) { folder in
                    Button {
                        selected = []
                        folders.append(folder.name)
                    } label: {
                        Label(folder.name, systemImage: "folder.fill").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 30)
                    .disabled(loading || !connected)
                }
                ForEach(contents.tracks) { track in
                    HStack {
                        Text(track.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(track.artist).lineLimit(1).frame(width: 130, alignment: .leading)
                        Text(track.album).lineLimit(1).frame(width: 160, alignment: .leading)
                        Text(track.format).font(.system(size: 11)).frame(width: 45)
                        Text(track.timeLabel).monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                    .frame(height: 34)
                    .tag(track.id)
                }
            }
            .disabled(loading || !connected)
            HStack {
                Text("\(selected.count) 首已选 · \(contents.tracks.count) 首 · \(contents.folders.count) 个文件夹")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("导回到计算机…", action: chooseDestination)
                Button("删除", role: .destructive) {
                    do { pendingDeletion = try selectedTracks.map { try WalkmanFileIdentity.read($0.url) } }
                    catch { self.error = error.localizedDescription }
                }
            }
            .disabled(loading || !connected || selectedTracks.isEmpty)
        }
        .padding(28)
        .task(id: Location(device: volume.id, folders: folders, revision: revision)) {
            let currentLoad = UUID()
            loadID = currentLoad
            selected = []
            loading = true
            error = nil
            let worker = Task.detached { try await WalkmanFiles.contents(folders, on: volume) }
            defer { if loadID == currentLoad { loading = false } }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard loadID == currentLoad else { return }
                contents = result
            } catch is CancellationError {
            } catch {
                if loadID == currentLoad {
                    contents = .init(folders: [], tracks: [])
                    self.error = error.localizedDescription
                }
            }
        }
        .onChange(of: connected) { if !connected { selected = [] } else { revision += 1 } }
        .windowsAlert(isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
            message: "将永久删除设备上的\(pendingDeletion.count)个音频文件。", symbol: .warning, width: 392,
            buttons: [WindowsDialogButton("yes", "是") {
                do { try WalkmanFiles.remove(pendingDeletion, folders: folders, on: volume) }
                catch { self.error = error.localizedDescription }
                revision += 1
            }, WindowsDialogButton("no", "否")], defaultButton: "no", cancelButton: "no")
    }

    private func chooseDestination() {
        let tracks = selectedTracks
        let picker = NSOpenPanel()
        picker.title = "选择导回歌曲的文件夹"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = true
        picker.prompt = "选择"
        picker.begin { response in
            if response == .OK, let directory = picker.url { importTracks(tracks, directory) }
        }
    }
}
