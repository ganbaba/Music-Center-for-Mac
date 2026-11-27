import AVFoundation
import CryptoKit
import Foundation

enum ATRACConversion {
    static let extensions: Set<String> = ["oma", "aa3", "at3"]
    static func candidates(in tracks: [Track]) -> [Track] {
        tracks.filter { extensions.contains($0.url.pathExtension.lowercased()) }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    struct Space: Identifiable, Sendable {
        let id: URL
        let name: String
        let total: Int64
        let available: Int64
        let required: Int64
    }
    struct Result: Sendable {
        let source: Track
        let output: URL?
        let archivedOriginal: URL?
        let issue: String?
    }

    static func checkSpace(_ tracks: [Track], format: AudioExportFormat, moveOriginalsTo folder: URL?) throws -> [Space] {
        var volumes: [URL: (String, Int64, Int64, Int64)] = [:]
        func add(_ directory: URL, bytes: Int64) throws {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .volumeURLKey, .volumeNameKey,
                                                                 .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            guard values.isDirectory == true, let volume = values.volume else {
                throw Failure(message: "请选择可用的文件夹。")
            }
            let prior = volumes[volume]
            let needed = (prior?.3 ?? 0) + bytes
            let free = Int64(values.volumeAvailableCapacity ?? 0)
            guard needed <= free else { throw Failure(message: "磁盘可用空间不足，无法执行批量转换。") }
            volumes[volume] = (values.volumeName ?? volume.path, Int64(values.volumeTotalCapacity ?? 0), free, needed)
        }
        for track in tracks {
            let source = track.url.standardizedFileURL.resolvingSymlinksInPath()
            let facts = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard facts.isRegularFile == true else { throw Failure(message: "无法读取 ATRAC 文件：\n\(source.path)") }
            let bytes = Int64(facts.fileSize ?? 0)
            // Reserve for the decoded PCM, encoded file and metadata staging. This is an estimate,
            // not an assertion about the compression ratio of every ATRAC source.
            let seconds = track.duration.flatMap { $0.isFinite ? $0 : nil } ?? 0
            let pcm = max(min(bytes, Int64.max / 1024) * 64, Int64(min(max(seconds, 0), 1_000_000) * 384_000))
            try add(source.deletingLastPathComponent(), bytes: max(1_048_576, pcm * 3))
            if let folder {
                guard folder.standardizedFileURL.resolvingSymlinksInPath() != source.deletingLastPathComponent() else {
                    throw Failure(message: "原文件已在所选文件夹中，请选择其他文件夹或选择勿移出原始文件夹。")
                }
                try add(folder, bytes: bytes)
            }
        }
        return volumes.map { Space(id: $0.key, name: $0.value.0, total: $0.value.1,
                                   available: $0.value.2, required: $0.value.3) }.sorted { $0.id.path < $1.id.path }
    }

    static func digest(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        return Data(hash.finalize())
    }

    private static func archive(_ source: URL, into folder: URL) throws -> URL {
        let stage = folder.appending(path: ".music-center-atrac-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stage) }
        let copy = stage.appending(component: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: copy)
        let stem = source.deletingPathExtension().lastPathComponent
        for index in 1...10_000 {
            let name = index == 1 ? source.lastPathComponent : "\(stem) (\(index)).\(source.pathExtension)"
            let target = folder.appending(component: name)
            do { try FileManager.default.moveItem(at: copy, to: target); return target }
            catch CocoaError.fileWriteFileExists { continue }
        }
        throw Failure(message: "原文件的目标文件夹中存在过多同名文件。")
    }

    private static func io<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    @MainActor
    static func convert(_ track: Track, format: AudioExportFormat, decoder: URL,
                        moveOriginalsTo folder: URL?, library: Library) async throws -> Result {
        guard format == .aac || format == .flac else { throw Failure(message: "请选择 AAC 或 FLAC。") }
        guard candidates(in: [track]).count == 1 else { throw Failure(message: "所选曲目不是 ATRAC 文件。") }
        let source = track.url.standardizedFileURL.resolvingSymlinksInPath()
        let before = try await io { try digest(source) }
        try Task.checkCancellation()
        let output = try await AudioExport.save(track, into: source.deletingLastPathComponent(),
                                                format: format, bitrate: 256, decoder: decoder)
        var archived: URL?
        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: output)
                if let archived { try? FileManager.default.removeItem(at: archived) }
            }
        }
        try Task.checkCancellation()
        guard try await io({ try digest(source) }) == before else { throw Failure(message: "转换期间原文件已更改，请重新扫描。") }
        if let folder {
            archived = try await io { try archive(source, into: folder) }
            guard let archived, try await io({ try digest(archived) }) == before else {
                throw Failure(message: "原文件副本校验失败，源文件已保留。")
            }
        }
        try Task.checkCancellation()
        let audio = try AVAudioFile(forReading: output)
        guard audio.length > 0 else { throw Failure(message: "转换后的文件没有可读取的音频。") }
        try library.replaceConvertedAudio(track, with: output, duration: Double(audio.length) / audio.processingFormat.sampleRate)
        committed = true
        var issue: String?
        if let archived {
            do {
                try await io {
                    guard try digest(source) == before else { throw Failure(message: "原文件已更改，保留原位置的文件。") }
                    try FileManager.default.removeItem(at: source)
                }
            } catch {
                issue = "转换已保存，原文件未能移出；两处文件均保留。\n\(source.path)\n\(archived.path)"
            }
        }
        return Result(source: track, output: output, archivedOriginal: archived, issue: issue)
    }
}
