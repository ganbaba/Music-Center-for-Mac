import AppKit
import SwiftUI
import Observation

struct WalkmanVolume: Identifiable, Equatable, Sendable {
    struct Identity: Hashable, Sendable {
        let url: URL
        let filesystem: dev_t
        let uuid: String?

        func checkMount(music: URL) throws {
            try Task.checkCancellation()
            let roots = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
            var mount = stat()
            var directory = stat()
            guard roots.contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }),
                  lstat(url.path, &mount) == 0, mount.st_dev == filesystem,
                  lstat(music.path, &directory) == 0, directory.st_mode & S_IFMT == S_IFDIR,
                  directory.st_dev == filesystem,
                  (try url.resourceValues(forKeys: [.volumeUUIDStringKey])).volumeUUIDString == uuid else {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "WALKMAN 已断开或目标目录不可用。"])
            }
        }
    }

    let id: Identity
    let music: URL?
    let capacity: Int64?
    let available: Int64?

    let model: String?
    var name: String { model ?? "Sony WALKMAN" }
    var label: String { id.url.path }
    var usedFraction: Double {
        guard let capacity, capacity > 0, let available else { return 0 }
        return min(1, max(0, 1 - Double(available) / Double(capacity)))
    }

    func checkMount() throws {
        guard let music else { throw CocoaError(.fileReadNoSuchFile) }
        try id.checkMount(music: music)
    }

    private static func deviceModel(at root: URL) -> String? {
        guard let parser = XMLParser(contentsOf: root.appending(path: "default-capability.xml")) else { return nil }
        let reader = WalkmanIdentification()
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        return parser.parse() ? reader.model : nil
    }

    static func mountedRoots() -> [URL] {
        MountedVolume.list().compactMap { volume in
            let name = volume.root.lastPathComponent.uppercased()
            let suffix = name.hasPrefix("WALKMAN ") && Int(name.dropFirst("WALKMAN ".count)) != nil
            return volume.isLocal && (name == "WALKMAN" || suffix) ? volume.root : nil
        }
    }

    static func discover() -> [Self] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsInternalKey, .volumeIsLocalKey,
                                         .volumeUUIDStringKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        return mountedRoots().compactMap { url -> Self? in
            guard let info = try? url.resourceValues(forKeys: keys), info.volumeIsLocal == true,
                  info.volumeIsInternal == false, info.volumeName?.caseInsensitiveCompare("WALKMAN") == .orderedSame else { return nil }
            var mount = stat()
            guard lstat(url.path, &mount) == 0 else { return nil }
            let directory = url.appending(path: "MUSIC", directoryHint: .isDirectory)
            var entry = stat()
            let music = lstat(directory.path, &entry) == 0 && entry.st_mode & S_IFMT == S_IFDIR && entry.st_dev == mount.st_dev
                ? directory : nil
            return Self(id: Identity(url: url, filesystem: mount.st_dev, uuid: info.volumeUUIDString), music: music,
                        capacity: info.volumeTotalCapacity.map(Int64.init), available: info.volumeAvailableCapacity.map(Int64.init), model: deviceModel(at: url))
        }.sorted { $0.label < $1.label }
    }
}

struct WalkmanPreviewRequest: Identifiable, Sendable {
    let id = UUID()
    let device: WalkmanVolume.Identity
    let directory: URL
    let music: URL
    let importsToLibrary: Bool
    let tracks: [Track]
    let layout: VolumeTransfer.Layout
    let convertAll: Bool
    let bitrate: Int
    let removesConvertedFiles: Bool

    static func make(for volume: WalkmanVolume?, tracks: [Track], layout: VolumeTransfer.Layout,
                     settings: PreviewSettings) -> Self? {
        guard let volume, let directory = volume.music, !tracks.isEmpty else { return nil }
        return Self(device: volume.id, directory: directory, music: directory, importsToLibrary: false, tracks: tracks, layout: layout,
                    convertAll: settings.convertsAll, bitrate: settings.bitrate,
                    removesConvertedFiles: settings.removesConvertedFiles)
    }

    static func returning(_ tracks: [Track], from volume: WalkmanVolume, to directory: URL) throws -> Self {
        guard let music = volume.music, !tracks.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        var destination = stat()
        guard stat(directory.path, &destination) == 0, destination.st_dev != volume.id.filesystem else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "请选择计算机或其他磁盘上的文件夹。"])
        }
        return Self(device: volume.id, directory: directory, music: music, importsToLibrary: true, tracks: tracks,
                    layout: .flat, convertAll: false, bitrate: 128, removesConvertedFiles: true)
    }

    func reconnected(to volume: WalkmanVolume) -> Self {
        Self(device: volume.id, directory: importsToLibrary ? directory : volume.music ?? directory,
             music: volume.music ?? music, importsToLibrary: importsToLibrary, tracks: tracks, layout: layout,
             convertAll: convertAll, bitrate: bitrate, removesConvertedFiles: removesConvertedFiles)
    }

    func prepare(progress: @Sendable (String) async -> Void) async throws -> PreparedWalkmanTransfer {
        try checkMount()
        if importsToLibrary {
            let plan = try VolumeTransfer.prepare(tracks, into: directory, layout: layout, compareExisting: true)
            try checkMount()
            return PreparedWalkmanTransfer(plan: plan, temporaryDirectory: nil)
        }
        return try await WalkmanAAC.prepare(tracks, directory: directory, layout: layout,
                                            convertAll: convertAll, bitrate: bitrate,
                                            removesConvertedFiles: removesConvertedFiles,
                                            validate: checkMount, progress: progress)
    }

    func checkMount() throws {
        try device.checkMount(music: music)
    }
}

struct WalkmanPreviewSheet: View {
    let request: WalkmanPreviewRequest
    let volume: WalkmanVolume?
    let close: () -> Void
    let didTransfer: (VolumeTransfer.Outcome) -> Void
    @State private var session = WalkmanTransferSession()

    private var connected: Bool { volume?.music != nil }
    private var currentRequest: WalkmanPreviewRequest { volume.map { request.reconnected(to: $0) } ?? request }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.importsToLibrary ? "导回到计算机" : "传输到设备").font(.title2.bold())
            Text(currentRequest.directory.path).textSelection(.enabled).foregroundStyle(.secondary)
            if !connected {
                Label("设备已断开，重新连接后可重试。", systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.red)
            }
            if let prepared = session.prepared {
                let plan = prepared.plan
                let totals = plan.totals
                Text("\(plan.entries.count) 首 · 待传输 \(totals.ready) 首（\(deviceBytes(totals.bytes))） · 已存在 \(totals.existing) · 冲突 \(totals.conflicts) · 不可用 \(totals.unavailable)")
                    .accessibilityIdentifier("preview-summary")
                if let freeBytes = plan.freeBytes {
                    Text("可用空间 \(deviceBytes(freeBytes))").foregroundStyle(.secondary)
                    if totals.bytes > freeBytes {
                        Label("预计需要的空间超过可用容量。", systemImage: "exclamationmark.triangle")
                    }
                }
                List(plan.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.relativePath).textSelection(.enabled)
                        Text(status(entry.status)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            } else {
                Spacer()
            }
            if session.working {
                ProgressView(value: session.progress)
                Text(session.activity).lineLimit(2)
            }
            if let report = session.report {
                Text(report).textSelection(.enabled).accessibilityIdentifier("transfer-result")
            }
            if let error = session.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if session.working {
                    Button("取消传输") { session.cancel() }
                } else {
                    Button("重新检查") { session.prepare(currentRequest) }.disabled(!connected)
                }
                Spacer()
                Button("关闭") { session.close(close) }.disabled(session.working)
                Button("开始传输") { session.transfer(currentRequest, didTransfer: didTransfer) }
                    .disabled(!connected || session.working || !(session.prepared?.plan.canTransfer ?? false))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 690, height: 490)
        .interactiveDismissDisabled(session.working)
        .task { session.prepare(currentRequest) }
        .onChange(of: connected) { if !connected { session.cancel() } }
        .onDisappear { session.cancel() }
    }

    private func status(_ status: VolumeTransfer.Status) -> String {
        switch status {
        case .ready(let bytes): "待传输 · \(deviceBytes(bytes))"
        case .existing: "已存在 · 内容相同"
        case .conflict(let reason): "冲突 · \(reason)"
        case .unavailable(let reason): "不可用 · \(reason)"
        }
    }
}

@MainActor
@Observable
final class WalkmanTransferSession {
    private(set) var prepared: PreparedWalkmanTransfer?
    private(set) var working = false
    private(set) var progress: Double = 0
    private(set) var activity = ""
    private(set) var report: String?
    private(set) var error: String?
    @ObservationIgnored private var worker: Task<Void, Never>?

    func prepare(_ request: WalkmanPreviewRequest) {
        guard !working else { return }
        do {
            try prepared?.cleanUp()
            prepared = nil
        } catch {
            self.error = error.localizedDescription
            return
        }
        working = true
        error = nil
        report = nil
        activity = "正在检查目标文件…"
        progress = 0
        worker = Task {
            let task = Task.detached(priority: .userInitiated) {
                try await request.prepare { await self.setActivity($0) }
            }
            defer { working = false }
            do {
                let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                if Task.isCancelled {
                    try result.cleanUp()
                    throw CancellationError()
                }
                prepared = result
            } catch is CancellationError {
                self.report = "检查已取消。"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func transfer(_ request: WalkmanPreviewRequest, didTransfer: @escaping (VolumeTransfer.Outcome) -> Void) {
        guard !working, let prepared else { return }
        working = true
        error = nil
        report = nil
        progress = 0
        worker = Task {
            let task = Task.detached(priority: .userInitiated) {
                try await VolumeTransfer.copy(prepared.plan, validate: request.checkMount) { completed, total, name in
                    await self.updateProgress(completed, total: total, name: name)
                }
            }
            defer {
                working = false
            }
            do {
                let outcome = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                didTransfer(outcome)
                report = "传输完成。已传输 \(outcome.copied) 首，已存在 \(outcome.existing) 首，冲突 \(outcome.conflicts.count) 首，失败 \(outcome.failures.count) 首。"
                if let name = outcome.playlistName { report = (report ?? "") + "\n播放列表 · " + name }
                if !outcome.failures.isEmpty { error = outcome.failures.joined(separator: "\n") }
                try prepared.cleanUp()
                self.prepared = nil
            } catch let interruption as VolumeTransfer.Interrupted {
                didTransfer(interruption.outcome)
                report = interruption.reason + "已完成 \(interruption.outcome.copied) 首，可重新检查后继续。"
            } catch is CancellationError {
                report = "传输已取消，可重新检查后继续。"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() { worker?.cancel() }

    func close(_ action: () -> Void) {
        guard !working else { return }
        do {
            try prepared?.cleanUp()
            prepared = nil
            action()
        } catch { self.error = error.localizedDescription }
    }

    private func setActivity(_ text: String) { activity = text }

    private func updateProgress(_ completed: Int, total: Int, name: String) {
        progress = Double(completed) / Double(max(1, total))
        activity = "正在传输 \(completed)/\(total) · " + name
    }
}

func deviceBytes(_ bytes: Int64) -> String {
    bytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private final class WalkmanIdentification: NSObject, XMLParserDelegate {
    var model: String?
    private var elements: [String] = []
    private var text = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        elements.append(name)
        text = ""
    }
    func parser(_ parser: XMLParser, foundCharacters value: String) { text += value }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if elements.suffix(2) == ["identification", "model"] {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { model = value }
        }
        elements.removeLast()
        text = ""
    }
}
