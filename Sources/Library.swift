import AVFoundation
import CryptoKit
import Foundation
import Observation
import SQLite3

struct Track: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String
    let album: String
    let duration: Double?
    let albumArtist: String
    let disc: Int?
    let number: Int?
    let artwork: Data?
    var registeredAt: Date? = nil

    var albumKey: AlbumKey? {
        album.isEmpty ? nil : AlbumKey(title: album, artist: albumArtist.isEmpty ? artist : albumArtist)
    }

    static func albumOrder(_ lhs: Track, _ rhs: Track) -> Bool {
        let comparison = lhs.album.localizedStandardCompare(rhs.album)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        let albumArtistOrder = (lhs.albumKey?.artist ?? "").localizedStandardCompare(rhs.albumKey?.artist ?? "")
        if albumArtistOrder != .orderedSame { return albumArtistOrder == .orderedAscending }
        let lhsDisc = lhs.disc ?? 1
        let rhsDisc = rhs.disc ?? 1
        if lhsDisc != rhsDisc { return lhsDisc < rhsDisc }
        let lhsNumber = lhs.number ?? Int.max
        let rhsNumber = rhs.number ?? Int.max
        if lhsNumber != rhsNumber { return lhsNumber < rhsNumber }
        let fileOrder = lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
        if fileOrder != .orderedSame { return fileOrder == .orderedAscending }
        return lhs.url.path < rhs.url.path
    }

    var format: String { url.pathExtension.uppercased() }

    var timeLabel: String {
        guard let duration else { return "—" }
        return playbackTimeLabel(duration)
    }
}

func playbackTimeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
    let total = Int(seconds)
    return "\(total / 60):" + String(format: "%02d", total % 60)
}

struct AlbumKey: Hashable, Sendable {
    let title: String
    let artist: String
}

struct TrackPlayback: Sendable {
    let lastPlayedAt: Date
    let count: Int
}

struct Playlist: Identifiable, Sendable {
    let id: UUID
    let name: String
}

struct PlaylistEntry: Identifiable, Sendable {
    let id: UUID
    let trackID: UUID
}

struct RestoreCandidate: Sendable {
    let url: URL
    let createdAt: Date?
    let notes: String?
    let trackCount: Int
    fileprivate let digest: SHA256.Digest
    fileprivate let settings: Data
}

enum RestoreProgress: Sendable {
    case checking, savingCurrent, applying
}

struct RestoreFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
@Observable
final class Library {
    let directory: URL
    private(set) var tracks: [Track] = []
    private(set) var playlists: [Playlist] = []
    private(set) var propertyRecords: [PropertyKey: PropertyRecord] = [:]
    private(set) var playbackHistory: [UUID: TrackPlayback] = [:]
    private(set) var playlistEntries: [UUID: [PlaylistEntry]] = [:]
    private(set) var importing = false
    private(set) var restoreProgress: RestoreProgress?
    var restoring: Bool { restoreProgress != nil }
    var message: String?
    var error: String?
    @ObservationIgnored private var database: LibraryDatabase?

    init(directory: URL = .applicationSupportDirectory.appending(path: "MusicCenterUIRecreation", directoryHint: .isDirectory)) {
        self.directory = directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            database = try LibraryDatabase(url: directory.appending(path: "Library.sqlite"))
            try reload()
        } catch {
            self.error = "无法打开曲库。\(error.localizedDescription)"
        }
    }

    func importItems(_ urls: [URL]) async {
        guard !importing, !restoring, !urls.isEmpty else { return }
        importing = true
        defer { importing = false }
        do {
            guard let database else { throw LibraryDatabase.Failure(message: "曲库不可用。") }
            let items = await Task.detached(priority: .userInitiated) { await TrackScanner.scan(urls) }.value
            let previousCount = tracks.count
            try database.insert(items)
            try reload()
            let added = tracks.count - previousCount
            message = items.isEmpty ? "没有找到支持的音频文件。" : "已导入 \(added) 首，跳过 \(items.count - added) 首重复曲目。"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func registerCopiedAudio(_ files: [(Track, URL)]) {
        guard !files.isEmpty else { return }
        let converted = files.map { source, url in
            Track(id: UUID(), url: url.standardizedFileURL.resolvingSymlinksInPath(), title: source.title,
                  artist: source.artist, album: source.album, duration: source.duration,
                  albumArtist: source.albumArtist, disc: source.disc, number: source.number, artwork: source.artwork)
        }
        if update({ try $0.insert(converted) }) { message = "已导入 \(files.count) 首 CD 曲目。" }
    }

    func importPlaylist(_ url: URL) async -> Bool {
        guard !importing, !restoring else { return false }
        importing = true
        defer { importing = false }
        do {
            guard let database else { throw LibraryDatabase.Failure(message: "曲库不可用。") }
            let knownTracks = Dictionary(uniqueKeysWithValues: tracks.map { ($0.url, $0) })
            let importedTracks = try await Task.detached(priority: .userInitiated) {
                try await TrackScanner.scanPlaylist(url, knownTracks: knownTracks)
            }.value
            guard !importedTracks.isEmpty else {
                throw M3UPlaylist.Failure(message: "播放列表中没有可导入的本地曲目。")
            }
            try database.importPlaylist(UUID(), name: url.deletingPathExtension().lastPathComponent, tracks: importedTracks)
            try reload()
            return true
        } catch {
            self.error = "无法导入播放列表。\(error.localizedDescription)"
            return false
        }
    }

    func backup(to url: URL, preferences: PreviewPreferences) throws {
        guard !importing, !restoring, let database else { throw LibraryDatabase.Failure(message: "曲库正在使用，请稍后重试。") }
        _ = try Self.backupLocation(url, outside: directory)
        try database.backup(to: url, preferences: preferences.snapshot())
    }

    func backupSize(preferences: PreviewPreferences) async throws -> Int64 {
        let source = try backupSource()
        let settings = try preferences.snapshot()
        return try await Task.detached(priority: .utility) {
            let reader = try LibraryDatabase(url: source, readOnly: true)
            return try reader.usedBytes() + Int64(settings.count)
        }.value
    }

    func checkNewBackupDestination(_ url: URL) throws {
        let location = try Self.backupLocation(url, outside: directory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: location.deletingLastPathComponent().path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw LibraryDatabase.Failure(message: "请选择可用的保存文件夹。")
        }
        if FileManager.default.fileExists(atPath: location.path) {
            throw LibraryDatabase.Failure(message: "此处已有同名项目。请选择其他名称或文件夹。")
        }
    }

    func writeNewBackup(to url: URL, notes: String, preferences: PreviewPreferences) async throws -> URL {
        try Task.checkCancellation()
        let source = try backupSource()
        let settings = try preferences.snapshot()
        let support = directory
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let location = try Self.backupLocation(url, outside: support)
            let reader = try LibraryDatabase(url: source, readOnly: true)
            try reader.backup(to: location, preferences: settings, notes: notes, replaceExisting: false)
            return location
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func backupSource() throws -> URL {
        guard !importing, !restoring, database != nil else {
            throw LibraryDatabase.Failure(message: "曲库正在使用或不可用，请稍后重试。")
        }
        return directory.appending(path: "Library.sqlite")
    }

    private nonisolated static func backupLocation(_ url: URL, outside directory: URL) throws -> URL {
        let support = directory.standardizedFileURL.resolvingSymlinksInPath()
        let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let location = parent.appending(component: url.lastPathComponent, directoryHint: .notDirectory)
        let resolved = location.resolvingSymlinksInPath()
        guard ![parent, resolved].contains(where: { $0.pathComponents.starts(with: support.pathComponents) }) else {
            throw LibraryDatabase.Failure(message: "请选择曲库文件夹以外的位置。")
        }
        return location
    }

    func inspectBackup(at url: URL, preferences: PreviewPreferences) async throws -> RestoreCandidate {
        let worker = Task.detached(priority: .utility) {
            try Self.withBackupCopy(of: url) { copy in
                let archive = try LibraryDatabase(url: copy, readOnly: true)
                let contents = try archive.validatedBackupContents()
                let details = try archive.backupDetails()
                return RestoreCandidate(url: url, createdAt: details?.date, notes: details?.notes,
                                        trackCount: contents.trackCount, digest: try Self.digest(of: copy), settings: contents.settings)
            }
        }
        let candidate = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        _ = try preferences.decodeSnapshot(candidate.settings)
        return candidate
    }

    func restore(_ candidate: RestoreCandidate, preferences: PreviewPreferences) async throws -> URL {
        let source = try backupSource()
        let previous = try preferences.snapshot()
        let restored = try preferences.decodeSnapshot(candidate.settings)
        let writeSettings = preferences.restorationWriter()
        let rollback = directory.appending(path: "Before Restore \(UUID().uuidString).musiccenterbackup")
        restoreProgress = .checking
        defer { restoreProgress = nil }

        let contents = try await Task.detached(priority: .userInitiated) {
            let folder = try Self.copyBackup(from: candidate.url)
            defer { try? FileManager.default.removeItem(at: folder) }
            let copy = folder.appending(path: "Selected.musiccenterbackup")
            guard try Self.digest(of: copy) == candidate.digest else {
                throw RestoreFailure(message: "备份文件已更改，请重新选择后再恢复。")
            }
            await self.setRestoreProgress(.savingCurrent)
            let writer = try LibraryDatabase(url: source, existing: true)
            do {
                try writer.backup(to: rollback, preferences: previous, notes: "恢复前自动备份")
            } catch {
                throw RestoreFailure(message: "无法保存恢复前备份。请检查曲库所在磁盘的可用空间。")
            }
            await self.setRestoreProgress(.applying)
            var settingsWritten = false
            do {
                return try writer.restoreSnapshot(from: copy) {
                    try writeSettings(candidate.settings, true)
                    settingsWritten = true
                }
            } catch {
                if settingsWritten {
                    do { try writeSettings(previous, false) }
                    catch { throw RestoreFailure(message: "无法还原恢复前的设置。恢复前备份位于：\n\(rollback.path)") }
                }
                throw RestoreFailure(message: "无法恢复曲库或设置。恢复前备份位于：\n\(rollback.path)")
            }
        }.value
        (tracks, playlists, playlistEntries, playbackHistory) = contents.library
        propertyRecords = contents.properties
        preferences.applySnapshot(restored)
        return rollback
    }

    private func setRestoreProgress(_ stage: RestoreProgress) {
        restoreProgress = stage
    }

    private nonisolated static func withBackupCopy<T>(of url: URL, perform: (URL) throws -> T) throws -> T {
        let folder = try copyBackup(from: url)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try perform(folder.appending(path: "Selected.musiccenterbackup"))
    }

    private nonisolated static func copyBackup(from url: URL) throws -> URL {
        let source = url.standardizedFileURL.resolvingSymlinksInPath()
        let folder = URL.temporaryDirectory.appending(path: "music-center-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            guard url.isFileURL, try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.copyItem(at: source, to: folder.appending(path: "Selected.musiccenterbackup"))
            return folder
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw RestoreFailure(message: "无法读取备份文件。请确认文件仍可访问，再重新选择。")
        }
    }

    private nonisolated static func digest(of url: URL) throws -> SHA256.Digest {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var sha = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            sha.update(data: data)
        }
        return sha.finalize()
    }

    func refresh() {
        guard !restoring else { return }
        do {
            try reload()
        } catch {
            self.error = "无法刷新曲库。\(error.localizedDescription)"
        }
    }

    func restoreImportedMetadata() async {
        guard !importing, !restoring, let database else { return }
        importing = true
        defer { importing = false }
        do {
            let urls = try database.pathsNeedingMetadata()
            guard !urls.isEmpty else { return }
            let items = await Task.detached(priority: .userInitiated) { await TrackScanner.scan(urls) }.value
            try database.restoreMetadata(items)
            try reload()
            message = "已重新读取 \(items.count) 首曲目的标签和封面。"
        } catch {
            self.error = "无法更新曲库标签。\(error.localizedDescription)"
        }
    }

    func saveProperties(_ changes: [PropertyChange]) throws {
        guard !restoring, let database else { throw LibraryDatabase.Failure(message: "曲库不可用。") }
        try database.transaction {
            var records = try database.loadProperties()
            for change in changes where !change.fields.isEmpty || change.changesArtwork {
                try change.validate()
                try database.applyProperties(change, records: &records)
            }
        }
        try reload()
    }

    func createPlaylist(_ name: String, tracks: [Track] = []) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let id = UUID()
        return update { database in
            try database.transaction {
                try database.createPlaylist(id, name: trimmed)
                try database.add(tracks, to: id)
            }
        } ? id : nil
    }

    func add(_ tracks: [Track], to playlist: UUID) {
        guard !tracks.isEmpty else { return }
        update { database in try database.transaction { try database.add(tracks, to: playlist) } }
    }

    func reorderPlaylist(_ order: [UUID], replacing original: [UUID], in playlist: UUID) -> Bool {
        let saved = update { try $0.reorderPlaylist(order, replacing: original, in: playlist) }
        if !saved { try? reload() }
        return saved
    }

    @discardableResult
    func removePlaylistEntries(_ entries: [UUID], from playlist: UUID) -> Bool {
        update { database in
            try database.transaction {
                for entry in entries {
                    try database.execute("DELETE FROM playlist_entries WHERE playlist_id = ? AND id = ?", [.uuid(playlist), .uuid(entry)])
                }
            }
        }
    }

    func deletePlaylist(_ id: UUID) -> Bool {
        update { database in
            try database.transaction {
                try database.execute("DELETE FROM library_properties WHERE kind = 'playlist' AND identity = ?", [.uuid(id)])
                try database.execute("DELETE FROM playlists WHERE id = ?", [.uuid(id)])
            }
        }
    }

    func removeFromLibrary(_ trackIDs: Set<UUID>) -> Bool {
        update { database in
            try database.transaction {
                for id in trackIDs {
                    try database.execute("DELETE FROM library_properties WHERE kind = 'song' AND identity = ?", [.uuid(id)])
                    try database.execute("DELETE FROM tracks WHERE id = ?", [.uuid(id)])
                }
            }
        }
    }

    func recordPlayback(of track: Track) {
        guard !restoring else { return }
        do {
            if let playback = try database?.recordPlayback(of: track.id, at: .now) {
                playbackHistory[track.id] = playback
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    private func update(_ operation: (LibraryDatabase) throws -> Void) -> Bool {
        guard !restoring else { return false }
        do {
            guard let database else { throw LibraryDatabase.Failure(message: "曲库不可用。") }
            try operation(database)
            try reload()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func reload() throws {
        guard let database else { return }
        let snapshot = try database.load()
        (tracks, playlists, playlistEntries, playbackHistory) = snapshot
        propertyRecords = try database.loadProperties()
    }
}

enum M3UPlaylist {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func entries(in url: URL) throws -> [String] {
        let ext = url.pathExtension.lowercased()
        guard ext == "m3u8" || ext == "m3u" else { throw Failure(message: "请选择 M3U 或 M3U8 文件。") }
        let data = try Data(contentsOf: url)
        let text: String?
        if ext == "m3u" && (data.starts(with: [0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE])) {
            text = String(data: data, encoding: .utf16)
        } else {
            text = String(data: data, encoding: .utf8)
                ?? (ext == "m3u" ? String(data: data, encoding: .windowsCP1252) : nil)
        }
        guard let text else { throw Failure(message: "无法读取文本编码。请将列表另存为 UTF-8。") }
        var entries: [String] = []
        var isStreamingPlaylist = false
        let content = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXT-X-") { isStreamingPlaylist = true }
            if !trimmed.isEmpty, !trimmed.hasPrefix("#") { entries.append(line) }
        }
        guard !isStreamingPlaylist else { throw Failure(message: "请选择包含本地音频路径的列表。") }
        return entries
    }

    static func localURL(for entry: String, relativeTo directory: URL) -> URL? {
        let windowsPath = entry.replacingOccurrences(of: "\\", with: "/")
        guard !windowsPath.hasPrefix("//") else { return nil }
        if let parsed = URLComponents(string: entry), let scheme = parsed.scheme {
            if scheme.count == 1, windowsPath.dropFirst().hasPrefix(":/") { return nil }
            guard scheme.lowercased() == "file", let url = parsed.url,
                  parsed.host == nil || parsed.host == "" || parsed.host?.lowercased() == "localhost",
                  url.path.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: url.path)
        }
        guard !entry.hasPrefix("\\") else { return nil }
        if entry.hasPrefix("/") { return URL(fileURLWithPath: entry) }
        let native = directory.appending(path: entry)
        if windowsPath == entry || FileManager.default.fileExists(atPath: native.path) { return native }
        return directory.appending(path: windowsPath)
    }
}

enum TrackScanner {
    private static let supported = Set(["mp3", "m4a", "aac", "flac", "wav", "wave", "aif", "aiff", "aifc", "caf"])
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]

    static func scan(_ inputs: [URL]) async -> [Track] {
        var seen = Set<URL>()
        var tracks: [Track] = []
        for input in inputs {
            let hasScope = input.startAccessingSecurityScopedResource()
            defer { if hasScope { input.stopAccessingSecurityScopedResource() } }
            let root = input.standardizedFileURL.resolvingSymlinksInPath()
            if (try? root.resourceValues(forKeys: keys).isDirectory) == true,
               let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                while let file = files.nextObject() as? URL {
                    if let track = await inspect(file, seen: &seen) { tracks.append(track) }
                }
            } else if let track = await inspect(root, seen: &seen) {
                tracks.append(track)
            }
        }
        return tracks
    }

    static func scanPlaylist(_ url: URL, knownTracks: [URL: Track]) async throws -> [Track] {
        let hasScope = url.startAccessingSecurityScopedResource()
        defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
        let directory = url.deletingLastPathComponent()
        let entries = try M3UPlaylist.entries(in: url)
        var tracksByFile = knownTracks
        var unreadable: Set<URL> = []
        var tracks: [Track] = []
        for entry in entries {
            guard let url = M3UPlaylist.localURL(for: entry, relativeTo: directory),
                  let file = audioFile(url), !unreadable.contains(file) else { continue }
            if let known = tracksByFile[file] {
                tracks.append(known)
            } else {
                let track = await readTrack(file)
                if track.duration != nil {
                    tracksByFile[file] = track
                    tracks.append(track)
                } else {
                    unreadable.insert(file)
                }
            }
        }
        return tracks
    }

    private static func audioFile(_ url: URL) -> URL? {
        let file = url.standardizedFileURL.resolvingSymlinksInPath()
        guard supported.contains(file.pathExtension.lowercased()),
              (try? file.resourceValues(forKeys: keys).isRegularFile) == true else { return nil }
        return file
    }

    private static func inspect(_ url: URL, seen: inout Set<URL>) async -> Track? {
        guard let file = audioFile(url), seen.insert(file).inserted else { return nil }
        return await readTrack(file)
    }

    private static func readTrack(_ file: URL) async -> Track {
        let asset = AVURLAsset(url: file)
        let tags = await TrackTags.read(file, asset: asset)
        var duration = (try? await asset.load(.duration))?.seconds
        if duration?.isFinite != true, let audio = try? AVAudioFile(forReading: file) {
            duration = Double(audio.length) / audio.processingFormat.sampleRate
        }
        return Track(
            id: UUID(), url: file, title: tags.title ?? file.deletingPathExtension().lastPathComponent,
            artist: tags.artist ?? "", album: tags.album ?? "",
            duration: duration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            albumArtist: tags.albumArtist ?? "", disc: tags.disc, number: tags.number, artwork: tags.artwork
        )
    }


}

private final class LibraryDatabase {
    struct RestoredContents: Sendable {
        let library: ([Track], [Playlist], [UUID: [PlaylistEntry]], [UUID: TrackPlayback])
        let properties: [PropertyKey: PropertyRecord]
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum Value {
        case text(String), number(Double), integer(Int64), blob(Data), null

        static func uuid(_ id: UUID) -> Self { .text(id.uuidString) }
    }

    private let connection: OpaquePointer
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, readOnly: Bool = false, existing: Bool = false) throws {
        var handle: OpaquePointer?
        let access = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | (existing ? 0 : SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(url.path, &handle, access | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite 无法打开数据库。"
            if let handle { sqlite3_close(handle) }
            throw Failure(message: message)
        }
        connection = handle
        sqlite3_busy_timeout(connection, 3_000)
        try execute("PRAGMA trusted_schema = OFF")
        try execute("PRAGMA foreign_keys = ON")
        if readOnly || existing { return }
        try transaction {
            try execute("""
                CREATE TABLE IF NOT EXISTS tracks (
                    id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
                    artist TEXT NOT NULL, album TEXT NOT NULL, duration REAL
                )
                """)
            var version: Int32 = 0
            try query("PRAGMA user_version") { version = sqlite3_column_int($0, 0) }
            if version == 0 {
                try execute("ALTER TABLE tracks ADD COLUMN album_artist TEXT NOT NULL DEFAULT ''")
                try execute("ALTER TABLE tracks ADD COLUMN disc_number INTEGER")
                try execute("ALTER TABLE tracks ADD COLUMN track_number INTEGER")
                try execute("ALTER TABLE tracks ADD COLUMN artwork BLOB")
                try execute("ALTER TABLE tracks ADD COLUMN metadata_read INTEGER NOT NULL DEFAULT 0")
            }
            try execute("CREATE TABLE IF NOT EXISTS playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS library_properties (kind TEXT NOT NULL, identity TEXT NOT NULL, data BLOB NOT NULL, PRIMARY KEY(kind, identity))")
            try execute("""
                CREATE TABLE IF NOT EXISTS playlist_entries (
                    id TEXT NOT NULL PRIMARY KEY,
                    playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
                    track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL
                )
                """)
            try execute("CREATE INDEX IF NOT EXISTS playlist_entries_order ON playlist_entries(playlist_id, position)")
            if version < 2 {
                try migratePlaylistEntries()
            }
            if version < 3 {
                try execute("ALTER TABLE tracks ADD COLUMN registered_at REAL")
                try execute("ALTER TABLE tracks ADD COLUMN last_played_at REAL")
                try execute("ALTER TABLE tracks ADD COLUMN play_count INTEGER NOT NULL DEFAULT 0")
                try execute("PRAGMA user_version = 3")
            }
        }
    }

    private func migratePlaylistEntries() throws {
        var hasLegacyTable = false
        try query("SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = 'playlist_tracks'") { _ in
            hasLegacyTable = true
        }
        guard hasLegacyTable else { return }
        try query("SELECT playlist_id, track_id, position FROM playlist_tracks") { row in
            try execute("""
                INSERT INTO playlist_entries (id, playlist_id, track_id, position) VALUES (?, ?, ?, ?)
                """, [.uuid(UUID()), .text(string(row, 0)), .text(string(row, 1)), .integer(sqlite3_column_int64(row, 2))])
        }
        try execute("DROP TABLE playlist_tracks")
    }

    deinit { sqlite3_close(connection) }

    func usedBytes() throws -> Int64 {
        var pages: Int64 = 0
        var free: Int64 = 0
        var size: Int64 = 0
        try query("PRAGMA page_count") { pages = sqlite3_column_int64($0, 0) }
        try query("PRAGMA freelist_count") { free = sqlite3_column_int64($0, 0) }
        try query("PRAGMA page_size") { size = sqlite3_column_int64($0, 0) }
        return max(0, pages - free) * size
    }

    func backup(to url: URL, preferences: Data, notes: String? = nil, replaceExisting: Bool = true) throws {
        let stage = url.deletingLastPathComponent().appending(path: ".music-center-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stage) }
        if !replaceExisting {
            try Task.checkCancellation()
            sqlite3_progress_handler(connection, 2_000, { _ in Task.isCancelled ? 1 : 0 }, nil)
        }
        defer { if !replaceExisting { sqlite3_progress_handler(connection, 0, nil, nil) } }
        do {
            try execute("VACUUM INTO ?", [.text(stage.path)])
        } catch {
            if !replaceExisting { try Task.checkCancellation() }
            throw error
        }
        do {
            let snapshot = try LibraryDatabase(url: stage)
            try snapshot.transaction {
                try snapshot.execute("""
                    CREATE TABLE music_center_backup (format INTEGER NOT NULL, preferences BLOB NOT NULL)
                    """)
                try snapshot.execute("INSERT INTO music_center_backup VALUES (1, ?)", [.blob(preferences)])
                if let notes {
                    try snapshot.execute("""
                        CREATE TABLE music_center_backup_details (created_at REAL NOT NULL, notes TEXT NOT NULL)
                        """)
                    try snapshot.execute("INSERT INTO music_center_backup_details VALUES (?, ?)",
                                         [.number(Date.now.timeIntervalSince1970), .text(notes)])
                }
            }
        }
        if !replaceExisting { try Task.checkCancellation() }
        if replaceExisting && FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: stage)
        } else {
            try FileManager.default.moveItem(at: stage, to: url)
        }
    }

    func validatedBackupContents() throws -> (settings: Data, trackCount: Int) {
        var version: Int32 = 0
        try query("PRAGMA user_version") { version = sqlite3_column_int($0, 0) }
        guard version == 3 else { throw Failure(message: "此备份的曲库版本不受支持。") }
        try query("PRAGMA quick_check") { row in
            guard string(row, 0) == "ok" else { throw Failure(message: "备份中的曲库已损坏。") }
        }
        try query("PRAGMA foreign_key_check") { _ in throw Failure(message: "备份中的播放列表引用无效。") }
        let (tracks, _, _, _) = try load()
        _ = try loadProperties()
        var data: Data?
        try query("SELECT format, preferences FROM music_center_backup") { row in
            guard data == nil, sqlite3_column_int(row, 0) == 1, let bytes = sqlite3_column_blob(row, 1) else {
                throw Failure(message: "备份中的设置格式无效。")
            }
            data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, 1)))
        }
        guard let data else { throw Failure(message: "备份中缺少设置。") }
        return (data, tracks.count)
    }

    func backupDetails() throws -> (date: Date, notes: String)? {
        var exists = false
        try query("SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = 'music_center_backup_details'") { _ in exists = true }
        guard exists else { return nil }
        var details: (Date, String)?
        try query("SELECT created_at, notes FROM music_center_backup_details") { row in
            let timestamp = sqlite3_column_double(row, 0)
            guard details == nil, timestamp.isFinite, timestamp > 0, sqlite3_column_type(row, 1) == SQLITE_TEXT else {
                throw Failure(message: "备份日期或备注格式无效。")
            }
            details = (Date(timeIntervalSince1970: timestamp), string(row, 1))
        }
        return details
    }

    func restoreSnapshot(from url: URL, applyingSettings: () throws -> Void) throws -> RestoredContents {
        guard var location = URLComponents(url: url, resolvingAgainstBaseURL: true) else { throw CocoaError(.fileReadInvalidFileName) }
        location.queryItems = [URLQueryItem(name: "mode", value: "ro")]
        guard let source = location.string else { throw CocoaError(.fileReadInvalidFileName) }
        try execute("ATTACH DATABASE ? AS restore", [.text(source)])
        defer { try? execute("DETACH DATABASE restore") }
        return try transaction {
            try execute("DELETE FROM library_properties")
            try execute("DELETE FROM playlist_entries")
            try execute("DELETE FROM playlists")
            try execute("DELETE FROM tracks")
            let fields = "id, path, title, artist, album, duration, album_artist, disc_number, track_number, artwork, metadata_read, registered_at, last_played_at, play_count"
            try execute("INSERT INTO tracks (\(fields)) SELECT \(fields) FROM restore.tracks")
            try execute("INSERT INTO playlists (id, name) SELECT id, name FROM restore.playlists")
            try execute("""
                INSERT INTO playlist_entries (id, playlist_id, track_id, position)
                SELECT id, playlist_id, track_id, position FROM restore.playlist_entries
                """)
            var sourceHasProperties = false
            try query("SELECT 1 FROM restore.sqlite_schema WHERE type = 'table' AND name = 'library_properties'") { _ in
                sourceHasProperties = true
            }
            if sourceHasProperties {
                try execute("INSERT INTO library_properties SELECT kind, identity, data FROM restore.library_properties")
            }
            let contents = RestoredContents(library: try load(), properties: try loadProperties())
            try applyingSettings()
            return contents
        }
    }

    func load() throws -> ([Track], [Playlist], [UUID: [PlaylistEntry]], [UUID: TrackPlayback]) {
        var tracks: [Track] = []
        var playlists: [Playlist] = []
        var memberships: [UUID: [PlaylistEntry]] = [:]
        var history: [UUID: TrackPlayback] = [:]
        try query("""
            SELECT id, path, title, artist, album, duration, album_artist, disc_number, track_number,
                artwork, registered_at, last_played_at, play_count
            FROM tracks ORDER BY title COLLATE NOCASE, id
            """) { row in
            guard let id = UUID(uuidString: string(row, 0)) else { throw Failure(message: "曲库包含无效的曲目 ID。") }
            let duration = sqlite3_column_type(row, 5) == SQLITE_NULL ? nil : sqlite3_column_double(row, 5)
            let artwork = sqlite3_column_blob(row, 9).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(row, 9))) }
            tracks.append(Track(
                id: id, url: URL(fileURLWithPath: string(row, 1)), title: string(row, 2),
                artist: string(row, 3), album: string(row, 4), duration: duration,
                albumArtist: string(row, 6), disc: integer(row, 7), number: integer(row, 8),
                artwork: artwork, registeredAt: date(row, 10)
            ))
            if let lastPlayedAt = date(row, 11) {
                history[id] = TrackPlayback(lastPlayedAt: lastPlayedAt, count: Int(sqlite3_column_int64(row, 12)))
            }
        }
        try query("SELECT id, name FROM playlists ORDER BY name COLLATE NOCASE, id") { row in
            guard let id = UUID(uuidString: string(row, 0)) else { throw Failure(message: "曲库包含无效的播放列表 ID。") }
            playlists.append(Playlist(id: id, name: string(row, 1)))
        }
        try query("SELECT playlist_id, id, track_id FROM playlist_entries ORDER BY playlist_id, position, id") { row in
            guard let playlist = UUID(uuidString: string(row, 0)),
                  let id = UUID(uuidString: string(row, 1)),
                  let track = UUID(uuidString: string(row, 2)) else {
                throw Failure(message: "曲库包含无效的播放列表条目。")
            }
            memberships[playlist, default: []].append(PlaylistEntry(id: id, trackID: track))
        }
        return (tracks, playlists, memberships, history)
    }

    func insert(_ tracks: [Track]) throws {
        let registeredAt = Date.now
        try transaction {
            for track in tracks { try insertTrack(track, registeredAt: registeredAt) }
        }
    }

    func recordPlayback(of track: UUID, at timestamp: Date) throws -> TrackPlayback? {
        var result: TrackPlayback?
        try query("""
            UPDATE tracks SET last_played_at = ?, play_count = play_count + 1 WHERE id = ?
            RETURNING play_count
            """, [.number(timestamp.timeIntervalSince1970), .uuid(track)]) { row in
            result = TrackPlayback(lastPlayedAt: timestamp, count: Int(sqlite3_column_int64(row, 0)))
        }
        return result
    }

    func importPlaylist(_ id: UUID, name: String, tracks: [Track]) throws {
        try transaction {
            try createPlaylist(id, name: name)
            let registeredAt = Date.now
            var insertedPaths: Set<URL> = []
            for (position, track) in tracks.enumerated() {
                if insertedPaths.insert(track.url).inserted { try insertTrack(track, registeredAt: registeredAt) }
                try execute("""
                    INSERT INTO playlist_entries (id, playlist_id, track_id, position)
                    VALUES (?, ?, (SELECT id FROM tracks WHERE path = ?), ?)
                    """, [.uuid(UUID()), .uuid(id), .text(track.url.path), .integer(Int64(position))])
            }
        }
    }

    private func insertTrack(_ track: Track, registeredAt: Date) throws {
        try execute("""
            INSERT INTO tracks (id, path, title, artist, album, duration, album_artist,
                disc_number, track_number, artwork, metadata_read, registered_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
            ON CONFLICT(path) DO NOTHING
            """, [.uuid(track.id), .text(track.url.path)] + metadataValues(track) + [.number(registeredAt.timeIntervalSince1970)])
    }

    func pathsNeedingMetadata() throws -> [URL] {
        var urls: [URL] = []
        try query("SELECT path FROM tracks WHERE metadata_read = 0") {
            urls.append(URL(fileURLWithPath: string($0, 0)))
        }
        return urls
    }

    func restoreMetadata(_ tracks: [Track]) throws {
        try transaction {
            for track in tracks {
                try execute("""
                    UPDATE tracks SET title = ?, artist = ?, album = ?, duration = COALESCE(?, duration),
                        album_artist = ?, disc_number = ?, track_number = ?, artwork = ?, metadata_read = 1
                    WHERE path = ? AND metadata_read = 0
                    """, metadataValues(track) + [.text(track.url.path)])
            }
        }
    }

    private func metadataValues(_ track: Track) -> [Value] {
        [
            .text(track.title), .text(track.artist), .text(track.album), track.duration.map(Value.number) ?? .null,
            .text(track.albumArtist), track.disc.map { .integer(Int64($0)) } ?? .null,
            track.number.map { .integer(Int64($0)) } ?? .null, track.artwork.map(Value.blob) ?? .null
        ]
    }

    func createPlaylist(_ id: UUID, name: String) throws {
        try execute("INSERT INTO playlists (id, name) VALUES (?, ?)", [.uuid(id), .text(name)])
        try writeProperty(PropertyRecord(createdAt: .now), key: .playlist(id))
    }

    func add(_ tracks: [Track], to playlist: UUID) throws {
        for track in tracks {
            try execute("""
                INSERT INTO playlist_entries (id, playlist_id, track_id, position)
                SELECT ?, ?, ?, (SELECT COALESCE(MAX(position) + 1, 0) FROM playlist_entries WHERE playlist_id = ?)
                WHERE NOT EXISTS (SELECT 1 FROM playlist_entries WHERE playlist_id = ? AND track_id = ?)
                """, [.uuid(UUID()), .uuid(playlist), .uuid(track.id), .uuid(playlist), .uuid(playlist), .uuid(track.id)])
        }
    }

    func reorderPlaylist(_ order: [UUID], replacing original: [UUID], in playlist: UUID) throws {
        try transaction {
            var current: [UUID] = []
            try query("""
                SELECT id FROM playlist_entries WHERE playlist_id = ? ORDER BY position, id
                """, [.uuid(playlist)]) { row in
                guard let id = UUID(uuidString: string(row, 0)) else {
                    throw Failure(message: "曲库包含无效的播放列表条目。")
                }
                current.append(id)
            }
            guard current == original, order.count == current.count, Set(order) == Set(current) else {
                throw Failure(message: "播放列表已有变更，请重新打开排序窗口。")
            }
            for (position, entry) in order.enumerated() {
                try execute("""
                    UPDATE playlist_entries SET position = ? WHERE playlist_id = ? AND id = ?
                    """, [.integer(Int64(position)), .uuid(playlist), .uuid(entry)])
            }
        }
    }

    func loadProperties() throws -> [PropertyKey: PropertyRecord] {
        var exists = false
        try query("SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = 'library_properties'") { _ in exists = true }
        guard exists else { return [:] } // Backups created before properties were added.
        var records: [PropertyKey: PropertyRecord] = [:]
        try query("SELECT kind, identity, data FROM library_properties") { row in
            guard let kind = PropertyKey.Kind(rawValue: string(row, 0)), let pointer = sqlite3_column_blob(row, 2) else {
                throw Failure(message: "曲库包含无效的属性记录。")
            }
            let data = Data(bytes: pointer, count: Int(sqlite3_column_bytes(row, 2)))
            records[PropertyKey(kind: kind, identity: string(row, 1))] = try JSONDecoder().decode(PropertyRecord.self, from: data)
        }
        return records
    }

    private func writeProperty(_ record: PropertyRecord, key: PropertyKey) throws {
        let data = try JSONEncoder().encode(record)
        try execute("INSERT INTO library_properties (kind, identity, data) VALUES (?, ?, ?) ON CONFLICT(kind, identity) DO UPDATE SET data = excluded.data",
                    [.text(key.kind.rawValue), .text(key.identity), .blob(data)])
    }

    func applyProperties(_ change: PropertyChange, records: inout [PropertyKey: PropertyRecord]) throws {
        let subject = change.subject
        var owner = records[subject.key] ?? PropertyRecord()
        owner.fields.merge(change.fields, uniquingKeysWith: { _, new in new })
        owner.modifiedAt = .now
        if change.changesArtwork { owner.artwork = change.artwork; owner.overridesArtwork = true }
        if subject.key.kind == .playlist {
            guard let playlist = subject.playlist else { throw Failure(message: "播放列表不可用。") }
            try requireEntity("playlists", id: playlist.id)
            if let title = change.fields[.title] { try execute("UPDATE playlists SET name = ? WHERE id = ?", [.text(title), .uuid(playlist.id)]) }
            owner.fields[.title] = nil // Playlist names are owned by the playlists table.
            try writeProperty(owner, key: subject.key)
            records[subject.key] = owner
            return
        }
        let targets = subject.localTracks
        guard subject.hasOnlyLocalTracks else { throw Failure(message: "参考曲库的属性只供查看。请切换到本地曲库后编辑。") }
        for track in targets { try requireEntity("tracks", id: track.id) }
        var songFields = change.fields
        if subject.key.kind == .album {
            songFields = [:]
            for (field, value) in change.fields {
                let mapped: PropertyField = switch field {
                case .title: .album
                case .titleSort: .albumSort
                case .artist: .albumArtist
                case .artistSort: .albumArtistSort
                default: field
                }
                songFields[mapped] = value
            }
        } else if subject.key.kind == .artist {
            songFields = [:]
            if let name = change.fields[.artist] { songFields[subject.artistByTrack ? .artist : .albumArtist] = name }
            if let sort = change.fields[.artistSort] { songFields[subject.artistByTrack ? .artistSort : .albumArtistSort] = sort }
        }
        for track in targets where !songFields.isEmpty || (change.changesArtwork && subject.key.kind != .artist) {
            var assignments: [String] = []
            var values: [Value] = []
            for (field, column) in [(PropertyField.title, "title"), (.artist, "artist"), (.album, "album"), (.albumArtist, "album_artist")] {
                if let value = songFields[field] { assignments.append(column + " = ?"); values.append(.text(value)) }
            }
            for (field, column) in [(PropertyField.number, "track_number"), (.disc, "disc_number")] {
                if let raw = songFields[field] {
                    assignments.append(column + " = ?")
                    values.append(Int(raw).map { .integer(Int64($0)) } ?? .null)
                }
            }
            if change.changesArtwork && subject.key.kind != .artist {
                assignments.append("artwork = ?"); values.append(change.artwork.map(Value.blob) ?? .null)
            }
            if !assignments.isEmpty {
                try execute("UPDATE tracks SET " + assignments.joined(separator: ", ") + " WHERE id = ?", values + [.uuid(track.id)])
            }
            let key = PropertyKey.song(track.id)
            var record = records[key] ?? PropertyRecord()
            let core: Set<PropertyField> = [.title, .artist, .album, .albumArtist, .number, .disc]
            record.fields.merge(songFields.filter { !core.contains($0.key) }, uniquingKeysWith: { _, new in new })
            record.modifiedAt = .now
            // Track artwork lives in the tracks table, not in a duplicate JSON blob.
            try writeProperty(record, key: key)
            records[key] = record
        }
        // Album fields/artwork are owned by their member songs; keep no competing copy.
        if subject.key.kind == .artist {
            let key = PropertyKey.artist(change.fields[.artist] ?? subject.key.identity)
            var photo = records[key] ?? owner
            photo.fields = [:]
            if change.changesArtwork { photo.artwork = change.artwork; photo.overridesArtwork = true }
            if photo.overridesArtwork {
                photo.modifiedAt = .now
                try writeProperty(photo, key: key)
                records[key] = photo
            }
        }
    }

    private func requireEntity(_ table: String, id: UUID) throws {
        var exists = false
        try query("SELECT 1 FROM " + table + " WHERE id = ?", [.uuid(id)]) { _ in exists = true }
        guard exists else { throw Failure(message: "此项目已从曲库移除，请关闭属性后重新选择。") }
    }

    func transaction<T>(_ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try operation()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String, _ values: [Value] = []) throws {
        try withStatement(sql, values) { statement in
            guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
        }
    }

    private func query(_ sql: String, _ values: [Value] = [], row: (OpaquePointer) throws -> Void) throws {
        try withStatement(sql, values) { statement in
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                try row(statement)
                result = sqlite3_step(statement)
            }
            guard result == SQLITE_DONE else { throw failure() }
        }
    }

    private func withStatement(_ sql: String, _ values: [Value], operation: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text): result = sqlite3_bind_text(statement, index, text, Int32(text.utf8.count), transient)
            case .number(let number): result = sqlite3_bind_double(statement, index, number)
            case .integer(let number): result = sqlite3_bind_int64(statement, index, number)
            case .blob(let data):
                result = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw failure() }
        }
        try operation(statement)
    }

    private func string(_ row: OpaquePointer, _ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(row, index) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(row, index))), as: UTF8.self)
    }

    private func date(_ row: OpaquePointer, _ index: Int32) -> Date? {
        guard sqlite3_column_type(row, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(row, index))
    }

    private func integer(_ row: OpaquePointer, _ index: Int32) -> Int? {
        sqlite3_column_type(row, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(row, index))
    }

    private func failure() -> Failure {
        Failure(message: String(cString: sqlite3_errmsg(connection)))
    }
}

/// A user-requested existence check. Permission/read failures are not missing files.
struct MissingTrackReport: Sendable {
    var missing: Set<UUID> = []
    var unreadable: Set<UUID> = []
    static func scan(_ tracks: [Track]) async -> Self {
        await Task.detached(priority: .userInitiated) {
            var report = Self()
            for track in tracks {
                if Task.isCancelled { break }
                do {
                    if try !track.url.checkResourceIsReachable() { report.missing.insert(track.id) }
                } catch {
                    let error = error as NSError
                    if error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                        report.missing.insert(track.id)
                    } else { report.unreadable.insert(track.id) }
                }
            }
            return report
        }.value
    }
}
