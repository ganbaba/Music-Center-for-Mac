import AppKit
import DiscRecording
import SwiftUI

struct AudioDisc: Equatable, Sendable {
    let root: URL
    let filesystem: UInt64
    var driveID: String? = nil

    var name: String { root.lastPathComponent }

    var isMounted: Bool {
        MountedVolume.list().contains { $0.format == "cddafs" && $0.root == root && $0.identifier == filesystem }
    }

    func tracks() async throws -> [Track] {
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { ["aiff", "aif", "aifc"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let scanned = await TrackScanner.scan(files)
        return scanned.enumerated().map { index, track in
            Track(id: track.id, url: track.url, title: track.title, artist: track.artist,
                  album: track.album.isEmpty ? name : track.album, duration: track.duration,
                  albumArtist: track.albumArtist, disc: track.disc ?? 1, number: track.number ?? index + 1, artwork: track.artwork)
        }
    }
}

struct AudioCDDrive: Identifiable, Equatable {
    let id: String
    let name: String

    private init?(device: DRDevice) {
        guard let info = device.info(), let path = info[DRDeviceIORegistryEntryPathKey] as? String, !path.isEmpty else {
            return nil
        }
        id = path
        let names = [DRDeviceVendorNameKey, DRDeviceProductNameKey].compactMap { (info[$0] as? String)?.trimmingCharacters(in: .whitespaces) }
        let label = names.filter { !$0.isEmpty }.joined(separator: " ")
        name = label.isEmpty ? "光驱" : label
    }

    private init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    static func inventory() -> (drives: [Self], discs: [AudioDisc]) {
        var drives: [String: Self] = [:]
        for device in (DRDevice.devices() as? [DRDevice] ?? []) {
            if let drive = Self(device: device) { drives[drive.id] = drive }
        }
        let discs = MountedVolume.list().filter { $0.format == "cddafs" }.map { media in
            let bsd = media.source.split(separator: "/").last.map(String.init) ?? ""
            let device = bsd.isEmpty ? nil : DRDevice(forBSDName: bsd)
            let drive = device.flatMap(Self.init(device:)) ??
                Self(id: "mounted-cd:" + media.root.path, name: media.root.lastPathComponent)
            drives[drive.id] = drive
            return AudioDisc(root: media.root, filesystem: media.identifier, driveID: drive.id)
        }.sorted { $0.root.path < $1.root.path }
        return (drives.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }, discs)
    }
}

enum CDInsertionBehavior: String, CaseIterable, Identifiable {
    case play = "打开并播放"
    case importDisc = "自动导入"
    case none = "无操作"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .play: "CD 自动播放"
        case .importDisc: "开始自动导入歌曲"
        case .none: "无操作"
        }
    }
}

enum CDImportMode: String, CaseIterable, Identifiable, Sendable {
    case verifySource = "校验源文件"
    case standard = "标准"

    var id: String { rawValue }
    var label: String { self == .standard ? "导入速度优先" : "音质优先" }
}

extension PreviewSettings {
    var cdDriveID: String? {
        get { choices["CD光驱标识"] }
        set { choices["CD光驱标识"] = newValue }
    }

    var cdInsertionBehavior: CDInsertionBehavior {
        get { CDInsertionBehavior(rawValue: choices["CD操作"] ?? "") ?? .none }
        set { choices["CD操作"] = newValue.rawValue }
    }

    var cdImportDirectory: URL? {
        get { choices["CD导入目录"].map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { choices["CD导入目录"] = newValue?.path }
    }

    var cdFormat: AudioExportFormat {
        get { AudioExportFormat(rawValue: choices["CD格式"] ?? "") ?? .aac }
        set { choices["CD格式"] = newValue.rawValue }
    }

    static let aacBitrates = [320, 256, 192, 160, 128, 96, 80]
    static let mp3Bitrates = [320, 256, 224, 192, 160, 128, 112, 96]
    var availableCDBitrates: [Int] { cdFormat == .mp3 ? Self.mp3Bitrates : Self.aacBitrates }

    var cdBitrate: Int {
        get {
            let value = Int((choices["CD码率"] ?? "").split(separator: " ").first ?? "")
            return availableCDBitrates.first { $0 == value } ?? 128
        }
        set { choices["CD码率"] = "\(newValue) kbps" }
    }

    var cdImportMode: CDImportMode {
        get { CDImportMode(rawValue: choices["CD模式"] ?? "") ?? .standard }
        set { choices["CD模式"] = newValue.rawValue }
    }


}

struct AudioDiscPanel: View {
    let disc: AudioDisc
    let tracks: [Track]
    let play: (Track) -> Void
    let copy: ([Track]) -> Void
    let lookup: () -> Void
    let eject: () -> Void
    @State private var selection: Set<UUID> = []

    private var selected: [Track] { tracks.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(disc.name, systemImage: "opticaldisc").font(.title2.bold())
            HStack {
                Button("播放", systemImage: "play") {
                    if let track = selected.first ?? tracks.first { play(track) }
                }.disabled(tracks.isEmpty)
                Button(selection.isEmpty ? "导入整张 CD…" : "导入所选…", systemImage: "square.and.arrow.down") {
                    copy(selection.isEmpty ? tracks : selected)
                }.disabled(tracks.isEmpty)
                Button("查找专辑信息…", systemImage: "magnifyingglass", action: lookup).disabled(tracks.isEmpty)
                Spacer()
                Button("弹出", systemImage: "eject", action: eject)
            }
            List(tracks, selection: $selection) { track in
                HStack {
                    Text(track.number.map(String.init) ?? "").frame(width: 32)
                    Text(track.title).lineLimit(1)
                    Spacer()
                    Text(track.timeLabel).monospacedDigit().foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { play(track) }
                .tag(track.id)
            }
            if tracks.isEmpty { Text("正在读取光盘曲目…").foregroundStyle(.secondary) }
        }
        .padding(22)
    }
}

struct AudioExportRequest: Identifiable, Sendable {
    let id = UUID()
    let tracks: [Track]
    let directory: URL
    let format: AudioExportFormat
    var bitrate = 128
    var decoder: URL?
    var importsToLibrary = false
    var disc: AudioDisc?
    var ejectAfterImport = false
    var verifiesSource = false
}

struct AudioExportPanel: View {
    let request: AudioExportRequest
    let finish: ([(Track, URL)], Bool) -> Void
    let close: () -> Void
    @State private var task: Task<Void, Never>?
    @State private var status = "正在准备…"
    @State private var completed = 0
    @State private var failures: [String] = []
    @State private var running = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(request.importsToLibrary ? "导入音频 CD" : "导出音频", systemImage: "waveform")
                .font(.headline)
            Text("格式 · \(request.format.rawValue)")
            Text(request.directory.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            ProgressView(value: Double(completed), total: Double(request.tracks.count))
            Text(status).textSelection(.enabled)
            if !failures.isEmpty {
                ScrollView {
                    Text(failures.joined(separator: "\n")).foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 100)
            }
            HStack {
                Spacer()
                if running { Button("取消") { task?.cancel() } }
                else { Button("完成", action: close).keyboardShortcut(.defaultAction) }
            }
        }
        .padding(24)
        .frame(width: 505)
        .interactiveDismissDisabled(running)
        .onAppear {
            guard task == nil else { return }
            task = Task {
                var files: [(Track, URL)] = []
                for track in request.tracks {
                    if Task.isCancelled { break }
                    status = "正在处理「\(track.title)」"
                    let worker = Task.detached(priority: .userInitiated) {
                        if let disc = request.disc, !disc.isMounted {
                            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "音频 CD 已移除。"])
                        }
                        return try await AudioExport.save(track, into: request.directory, format: request.format,
                                                          bitrate: request.bitrate, decoder: request.decoder,
                                                          verifiesSource: request.verifiesSource)
                    }
                    do {
                        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                        files.append((track, result))
                    } catch is CancellationError {
                        break
                    } catch {
                        failures.append("\(track.title) · \(error.localizedDescription)")
                    }
                    completed += 1
                }
                let cancelled = Task.isCancelled
                finish(files, !cancelled && failures.isEmpty && files.count == request.tracks.count)
                status = (cancelled ? "已取消。" : "处理完毕。") + "已保存 \(files.count) 首，失败 \(failures.count) 首。"
                running = false
            }
        }
        .onDisappear { task?.cancel() }
    }
}
