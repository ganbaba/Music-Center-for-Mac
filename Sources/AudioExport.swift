import AVFoundation
import Foundation

enum AudioExportFormat: String, CaseIterable, Identifiable, Sendable {
    case wav = "WAV"
    case mp3 = "MP3"
    case aac = "AAC"
    case flac = "FLAC"

    var id: String { fileExtension }
    var usesBitrate: Bool { self == .aac || self == .mp3 }
    var fileExtension: String { self == .aac ? "m4a" : rawValue.lowercased() }
}

enum AudioExport {
    static func save(_ track: Track, into directory: URL, format: AudioExportFormat, bitrate: Int = 128,
                     decoder: URL? = nil, verifiesSource: Bool = false) async throws -> URL {
        try Task.checkCancellation()
        let hasScope = directory.startAccessingSecurityScopedResource()
        defer { if hasScope { directory.stopAccessingSecurityScopedResource() } }
        let scratch = directory.appending(path: ".music-center-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let stage = scratch.appending(path: "output.\(format.fileExtension)")
        let source: URL
        if let decoder {
            source = scratch.appending(path: "decoded.wav")
            try await AudioCommand.run(decoder, arguments: ["-nostdin", "-v", "error", "-i", track.url.path,
                                                            "-map", "0:a:0", "-c:a", "pcm_s24le", source.path])
        } else if verifiesSource {
            source = scratch.appending(path: "verified." + track.url.pathExtension)
            try FileManager.default.copyItem(at: track.url, to: source)
            try Task.checkCancellation()
            guard FileManager.default.contentsEqual(atPath: track.url.path, andPath: source.path) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "光盘曲目的读取校验失败。"])
            }
        } else {
            source = track.url
        }
        try Task.checkCancellation()
        switch format {
        case .wav:
            let input = try AVAudioFile(forReading: source)
            let pcm = input.fileFormat.streamDescription.pointee
            let isFloat = pcm.mFormatID == kAudioFormatLinearPCM && pcm.mFormatFlags & kAudioFormatFlagIsFloat != 0
            let depth = pcm.mBitsPerChannel
            let encoding = isFloat ? (depth == 64 ? "LEF64" : "LEF32") :
                (depth > 24 ? "LEI32" : (depth > 0 && depth <= 16 ? "LEI16" : "LEI24"))
            try await AudioCommand.run(AudioCommand.afconvert, arguments: ["-f", "WAVE", "-d", encoding, source.path, stage.path])
            guard try AVAudioFile(forReading: stage).length > 0 else { throw CocoaError(.fileWriteUnknown) }
        case .flac:
            let encoded = scratch.appending(path: "encoded.flac")
            try await AudioCommand.run(AudioCommand.afconvert, arguments: ["-f", "flac", "-d", "flac", source.path, encoded.path])
            guard try AVAudioFile(forReading: encoded).length > 0 else { throw CocoaError(.fileWriteUnknown) }
            try FLACMetadata.write(track, from: encoded, to: stage)
        case .aac:
            try await WalkmanAAC.convert(track, source: source, to: stage, bitrate: bitrate)
        case .mp3:
            guard let mp3Encoder = AudioCommand.ffmpeg else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: AudioCommand.mp3Requirement])
            }
            let fields = [("title", track.title), ("artist", track.artist), ("album", track.album),
                          ("album_artist", track.albumArtist), ("track", track.number.map(String.init) ?? ""),
                          ("disc", track.disc.map(String.init) ?? "")]
            let metadata = fields.filter { !$0.1.isEmpty }.flatMap { ["-metadata", "\($0.0)=\($0.1)"] }
            try await AudioCommand.run(mp3Encoder,
                arguments: ["-nostdin", "-v", "error", "-i", source.path, "-map", "0:a:0",
                            "-c:a", "libmp3lame", "-b:a", "\(bitrate)k", "-map_metadata", "-1", "-id3v2_version", "3"]
                    + metadata + [stage.path])
            guard try AVAudioFile(forReading: stage).length > 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        try Task.checkCancellation()
        let base = track.title.components(separatedBy: CharacterSet(charactersIn: "/:").union(.controlCharacters))
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let stem = String((base.isEmpty ? "曲目" : base).prefix(96))
        for suffix in 1...10_000 {
            let name = suffix == 1 ? stem : "\(stem) (\(suffix))"
            let target = directory.appending(path: name + "." + format.fileExtension)
            do {
                try FileManager.default.moveItem(at: stage, to: target)
                return target
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

enum AudioCommand {
    static let afconvert = URL(fileURLWithPath: "/usr/bin/afconvert")
    static let mp3Requirement = "MP3 导入需要带 libmp3lame 编码器的 FFmpeg。"

    static var ffmpeg: URL? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func run(_ executable: URL, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        // Use a file so a verbose child cannot block waiting for its stderr pipe to drain.
        let log = FileManager.default.temporaryDirectory.appending(path: "MusicCenter-convert-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: log.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: log) }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        process.standardError = output
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (result: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { child in result.resume(returning: child.terminationStatus) }
                do {
                    try Task.checkCancellation()
                    try process.run()
                    if Task.isCancelled, process.isRunning { process.terminate() }
                } catch {
                    process.terminationHandler = nil
                    result.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        guard status == 0 else {
            let reader = try FileHandle(forReadingFrom: log)
            defer { try? reader.close() }
            let detail = String(decoding: try reader.read(upToCount: 2048) ?? Data(), as: UTF8.self)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "无法转换此音频。" : detail])
        }
    }
}

private enum FLACMetadata {
    static func write(_ track: Track, from encoded: URL, to destination: URL) throws {
        let source = try FileHandle(forReadingFrom: encoded)
        defer { try? source.close() }
        let signature = Data([0x66, 0x4c, 0x61, 0x43])
        guard try source.read(upToCount: 4) == signature else { throw CocoaError(.fileReadCorruptFile) }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.write(contentsOf: signature)

        var last = false
        while !last {
            try Task.checkCancellation()
            guard var header = try source.read(upToCount: 4), header.count == 4 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            last = header[0] & 0x80 != 0
            header[0] &= 0x7f
            let size = (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
            if header[0] == 4 || header[0] == 6 {
                try source.seek(toOffset: source.offset() + UInt64(size))
            } else {
                let body = size == 0 ? Data() : try source.read(upToCount: size)
                guard let body, body.count == size else { throw CocoaError(.fileReadCorruptFile) }
                try output.write(contentsOf: header)
                try output.write(contentsOf: body)
            }
        }

        let artwork = picture(track.artwork)
        var metadata = Data()
        metadata.appendMetadata(type: 4, last: artwork == nil, body: comment(track))
        if let artwork { metadata.appendMetadata(type: 6, last: true, body: artwork) }
        try output.write(contentsOf: metadata)
        while let chunk = try source.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
    }

    private static func comment(_ track: Track) -> Data {
        let tags = [("TITLE", track.title), ("ARTIST", track.artist), ("ALBUM", track.album),
                    ("ALBUMARTIST", track.albumArtist), ("DISCNUMBER", track.disc.map(String.init) ?? ""),
                    ("TRACKNUMBER", track.number.map(String.init) ?? "")]
            .filter { !$0.1.isEmpty }.map { Data("\($0.0)=\(String($0.1.prefix(4096)))".utf8) }
        let vendor = Data("Music Center Preview".utf8)
        var block = Data()
        block.appendLE(UInt32(vendor.count))
        block.append(vendor)
        block.appendLE(UInt32(tags.count))
        for value in tags {
            block.appendLE(UInt32(value.count))
            block.append(value)
        }
        return block
    }

    private static func picture(_ image: Data?) -> Data? {
        guard let image, image.count < 15_000_000 else { return nil }
        let mime = Data((image.starts(with: [137, 80, 78, 71]) ? "image/png" : "image/jpeg").utf8)
        var block = Data()
        block.appendBE(UInt32(3))
        block.appendBE(UInt32(mime.count))
        block.append(mime)
        for _ in 0..<5 { block.appendBE(UInt32(0)) }
        block.appendBE(UInt32(image.count))
        block.append(image)
        return block
    }
}

private extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendMetadata(type: UInt8, last: Bool, body: Data) {
        append(type | (last ? 0x80 : 0))
        append(UInt8(truncatingIfNeeded: body.count >> 16))
        append(UInt8(truncatingIfNeeded: body.count >> 8))
        append(UInt8(truncatingIfNeeded: body.count))
        append(body)
    }
}
