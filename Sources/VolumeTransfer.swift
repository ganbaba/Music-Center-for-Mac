import Foundation

enum VolumeTransfer {
    enum Layout: Sendable {
        case flat
        case album(AlbumKey)
        case playlist(String)

        var isAlbum: Bool {
            if case .album = self { return true }
            return false
        }

        var isPlaylist: Bool {
            if case .playlist = self { return true }
            return false
        }
    }

    enum Status: Sendable {
        case ready(bytes: Int64)
        case existing
        case conflict(String)
        case unavailable(String)
    }

    struct Entry: Sendable, Identifiable {
        let id: UUID
        let source: URL
        let folders: [String]
        let name: String
        let status: Status

        var relativePath: String { (folders + [name]).joined(separator: "/") }
    }

    struct Plan: Sendable, Identifiable {
        let id = UUID()
        let directory: URL
        let root: URL
        let layout: Layout
        let entries: [Entry]
        let freeBytes: Int64?
        let playlist: PlaylistFile?

        var totals: (ready: Int, bytes: Int64, existing: Int, conflicts: Int, unavailable: Int) {
            entries.reduce(into: (ready: 0, bytes: Int64(0), existing: 0, conflicts: 0, unavailable: 0)) { totals, entry in
                switch entry.status {
                case .ready(let bytes):
                    totals.ready += 1
                    totals.bytes += bytes
                case .existing: totals.existing += 1
                case .conflict: totals.conflicts += 1
                case .unavailable: totals.unavailable += 1
                }
            }
        }

        var canTransfer: Bool {
            let totals = totals
            let required = totals.bytes + Int64(playlist?.data.count ?? 0)
            if let freeBytes, required > freeBytes { return false }
            guard let playlist else { return totals.ready > 0 }
            return !entries.isEmpty && totals.conflicts == 0 && totals.unavailable == 0
                && (totals.ready > 0 || !playlist.alreadyPresent)
        }
    }

    struct PlaylistFile: Sendable {
        let name: String
        let data: Data
        let alreadyPresent: Bool
    }

    struct Outcome: Sendable {
        var transferredURLs: [URL] = []
        var copied = 0
        var existing = 0
        var playlistName: String?
        var conflicts: [String] = []
        var failures: [String] = []
    }

    struct Interrupted: LocalizedError {
        let outcome: Outcome
        let reason: String
        var errorDescription: String? { reason }
    }

    private enum Failure: LocalizedError {
        case invalidDirectory
        case blockedFolder(String)
        case unreadableSource
        case incompletePlaylist
        case existingTrackChanged
        case playlistConflict(String)

        var errorDescription: String? {
            switch self {
            case .invalidDirectory: "无法访问所选的目标文件夹。"
            case .blockedFolder(let name): "目标路径「\(name)」被文件或符号链接占用。"
            case .unreadableSource: "源文件不可用。"
            case .incompletePlaylist: "播放列表存在同名冲突或不可用的曲目。"
            case .existingTrackChanged: "预览后设备上的曲目有变动，请重新预览。"
            case .playlistConflict(let name): "设备上的「\(name)」已变动，请重新预览。"
            }
        }
    }

    static func prepare(_ tracks: [Track], into directory: URL, layout: Layout, compareExisting: Bool = false) throws -> Plan {
        let hasScope = directory.startAccessingSecurityScopedResource()
        defer { if hasScope { directory.stopAccessingSecurityScopedResource() } }
        let root = try resolve(directory)
        let volume = try? root.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeSupportsCaseSensitiveNamesKey])
        let caseSensitive = volume?.volumeSupportsCaseSensitiveNames == true
        let albumFolders: [String]
        switch layout {
        case .flat, .playlist:
            albumFolders = []
        case .album(let album):
            albumFolders = [safeFolder(album.artist, fallback: "未知艺人"), safeFolder(album.title, fallback: "未知专辑")]
        }
        let splitDiscs = layout.isAlbum && tracks.contains { ($0.disc ?? 1) > 1 }
        func pathKey(_ path: String) -> String {
            let canonical = path.precomposedStringWithCanonicalMapping
            return caseSensitive ? canonical : canonical.lowercased()
        }

        // Preserve the case of filenames already on the destination volume.
        var namesOnDevice: [String: String] = [:]
        if layout.isPlaylist {
            for name in try FileManager.default.contentsOfDirectory(atPath: root.path) {
                namesOnDevice[pathKey(name)] = name
            }
        }
        var plannedPaths: [String: URL] = [:]
        var entries: [Entry] = []
        for track in tracks {
            try Task.checkCancellation()
            let folders = splitDiscs ? albumFolders + ["Disc \(track.disc ?? 1)"] : albumFolders
            var name = track.url.lastPathComponent
            if layout.isPlaylist {
                name = safeFolder(name, fallback: "曲目").precomposedStringWithCanonicalMapping
                if name.hasPrefix("#") { name = "_" + name }
                name = namesOnDevice[pathKey(name)] ?? name
            }
            let status: Status
            do {
                let source = try track.url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard source.isRegularFile == true, let bytes = source.fileSize, bytes >= 0 else { throw Failure.unreadableSource }
                let parent = try destinationFolder(folders, under: root, create: false)
                let destination = parent.appending(path: name, directoryHint: .notDirectory)
                let key = pathKey((folders + [name]).joined(separator: "/"))
                if let previous = plannedPaths[key] {
                    status = previous == track.url ? .existing : .conflict("本次传输有多个曲目使用此文件名")
                } else if let type = try itemType(at: destination) {
                    if (layout.isPlaylist || compareExisting) && type == .typeRegular && sameContents(track.url, destination) {
                        plannedPaths[key] = track.url
                        status = .existing
                    } else {
                        status = .conflict((layout.isPlaylist || compareExisting) && type == .typeRegular ? "设备上的同名文件内容不同" : "目标已存在")
                    }
                } else {
                    plannedPaths[key] = track.url
                    status = .ready(bytes: Int64(bytes))
                }
            } catch {
                status = .unavailable(error.localizedDescription)
            }
            entries.append(Entry(id: UUID(), source: track.url, folders: folders, name: name, status: status))
        }
        let playlist: PlaylistFile?
        if case .playlist(let name) = layout {
            playlist = try preparePlaylist(name, entries: entries, under: root)
        } else {
            playlist = nil
        }
        return Plan(directory: directory, root: root, layout: layout, entries: entries,
                    freeBytes: volume?.volumeAvailableCapacity.map(Int64.init), playlist: playlist)
    }

    static func copy(_ plan: Plan, validate: @Sendable () throws -> Void = {},
                     progress: @Sendable (Int, Int, String) async -> Void = { _, _, _ in }) async throws -> Outcome {
        try Task.checkCancellation()
        try validate()
        if plan.layout.isPlaylist {
            let totals = plan.totals
            guard !plan.entries.isEmpty, totals.conflicts == 0, totals.unavailable == 0 else {
                throw Failure.incompletePlaylist
            }
        }
        let hasScope = plan.directory.startAccessingSecurityScopedResource()
        defer { if hasScope { plan.directory.stopAccessingSecurityScopedResource() } }
        let root = try resolve(plan.directory)
        guard root == plan.root else { throw Failure.invalidDirectory }
        let fileManager = FileManager.default
        var outcome = Outcome()
        do {
            for (index, entry) in plan.entries.enumerated() {
                try Task.checkCancellation()
                try validate()
                await progress(index, plan.entries.count, entry.relativePath)
                switch entry.status {
                case .conflict:
                    outcome.conflicts.append(entry.relativePath)
                    continue
                case .unavailable(let reason):
                    outcome.failures.append("\(entry.relativePath) — \(reason)")
                    continue
                case .ready, .existing:
                    break
                }
    
                var destination: URL?
                do {
                    guard try entry.source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                        throw Failure.unreadableSource
                    }
                    let parent = try destinationFolder(entry.folders, under: root, create: true)
                    let target = parent.appending(path: entry.name, directoryHint: .notDirectory)
                    destination = target
                    let targetType = try itemType(at: target)
                    let matches = targetType == .typeRegular && sameContents(entry.source, target)
                    if matches {
                        outcome.existing += 1
                        outcome.transferredURLs.append(target)
                        continue
                    }
                    if case .existing = entry.status { throw Failure.existingTrackChanged }
                    if targetType != nil {
                        outcome.conflicts.append(entry.relativePath)
                        continue
                    }
                    let stage = parent.appending(path: ".music-center-\(UUID().uuidString).partial", directoryHint: .notDirectory)
                    defer { try? fileManager.removeItem(at: stage) }
                    try copyFile(entry.source, to: stage)
                    try Task.checkCancellation()
                    try validate()
                    try fileManager.moveItem(at: stage, to: target)
                    outcome.copied += 1
                    outcome.transferredURLs.append(target)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try validate()
                    if !plan.layout.isPlaylist, let destination, (try? itemType(at: destination)) != nil {
                        outcome.conflicts.append(entry.relativePath)
                    } else {
                        outcome.failures.append("\(entry.relativePath) — \(error.localizedDescription)")
                    }
                }
            }
            try Task.checkCancellation()
            try validate()
            if let playlist = plan.playlist, !plan.entries.isEmpty,
               outcome.conflicts.isEmpty && outcome.failures.isEmpty {
                let target = root.appending(path: playlist.name, directoryHint: .notDirectory)
                do {
                    if let type = try itemType(at: target) {
                        guard type == .typeRegular, try matchesPlaylist(playlist.data, at: target) else {
                            throw Failure.playlistConflict(playlist.name)
                        }
                    } else {
                        let stage = root.appending(path: ".music-center-\(UUID().uuidString).partial", directoryHint: .notDirectory)
                        defer { try? fileManager.removeItem(at: stage) }
                        try playlist.data.write(to: stage, options: .withoutOverwriting)
                        try Task.checkCancellation()
                        try validate()
                        try fileManager.moveItem(at: stage, to: target)
                    }
                    outcome.playlistName = playlist.name
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try validate()
                    outcome.failures.append(error.localizedDescription)
                }
            }
        } catch {
            throw Interrupted(outcome: outcome, reason: error is CancellationError ? "传输已取消。" : error.localizedDescription)
        }
        await progress(plan.entries.count, plan.entries.count, "")
        return outcome
    }

    private static func copyFile(_ source: URL, to target: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        while true {
            try Task.checkCancellation()
            guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { break }
            try output.write(contentsOf: data)
        }
        try output.synchronize()
    }

    private static func sameContents(_ source: URL, _ target: URL) -> Bool {
        FileManager.default.contentsEqual(atPath: source.path, andPath: target.path)
    }

    private static func preparePlaylist(_ title: String, entries: [Entry], under root: URL) throws -> PlaylistFile {
        let paths = entries.map { $0.relativePath.precomposedStringWithCanonicalMapping }
        let body = (["#EXTM3U"] + paths).joined(separator: "\r\n") + "\r\n"
        let data = Data([0xef, 0xbb, 0xbf]) + Data(body.utf8)
        let stem = safeFolder(title, fallback: "播放列表").precomposedStringWithCanonicalMapping
        var version = 1
        while true {
            let name = version == 1 ? "\(stem).m3u" : "\(stem) (\(version)).m3u"
            let target = root.appending(path: name, directoryHint: .notDirectory)
            guard let type = try itemType(at: target) else {
                return PlaylistFile(name: name, data: data, alreadyPresent: false)
            }
            if type == .typeRegular, try matchesPlaylist(data, at: target) {
                return PlaylistFile(name: name, data: data, alreadyPresent: true)
            }
            version += 1
        }
    }

    private static func matchesPlaylist(_ data: Data, at url: URL) throws -> Bool {
        let info = try url.resourceValues(forKeys: [.fileSizeKey])
        guard info.fileSize == data.count else { return false }
        return try Data(contentsOf: url) == data
    }

    private static func resolve(_ directory: URL) throws -> URL {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard try itemType(at: root) == .typeDirectory else { throw Failure.invalidDirectory }
        return root
    }

    private static func destinationFolder(_ folders: [String], under root: URL, create: Bool) throws -> URL {
        var parent = root
        for folder in folders {
            parent = parent.appending(path: folder, directoryHint: .isDirectory)
            if let type = try itemType(at: parent) {
                guard type == .typeDirectory else { throw Failure.blockedFolder(folder) }
            } else if create {
                do {
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
                } catch {
                    guard try itemType(at: parent) == .typeDirectory else { throw error }
                }
            }
        }
        return parent
    }

    private static func itemType(at url: URL) throws -> FileAttributeType? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private static func safeFolder(_ value: String, fallback: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:<>?*|\"").union(.controlCharacters)
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "–")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? fallback : cleaned
    }
}
