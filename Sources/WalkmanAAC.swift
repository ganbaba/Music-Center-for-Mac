import AVFoundation
import CryptoKit
import Foundation

struct PreparedWalkmanTransfer: Sendable {
    let plan: VolumeTransfer.Plan
    let temporaryDirectory: URL?

    func cleanUp() throws {
        if let temporaryDirectory { try FileManager.default.removeItem(at: temporaryDirectory) }
    }
}

enum WalkmanAAC {
    static func prepare(_ tracks: [Track], directory: URL, layout: VolumeTransfer.Layout,
                        convertAll: Bool, bitrate: Int, removesConvertedFiles: Bool,
                        validate: @Sendable () throws -> Void,
                        progress: @Sendable (String) async -> Void) async throws -> PreparedWalkmanTransfer {
        var converted: [Track] = []
        let scratch = removesConvertedFiles
            ? FileManager.default.temporaryDirectory.appending(path: "MusicCenter-AAC-\(UUID().uuidString)")
            : URL.cachesDirectory.appending(path: "MusicCenterUIRecreation/AAC")
        var ownsScratch = false
        do {
            for track in tracks {
                try Task.checkCancellation()
                try validate()
                if !convertAll && ["mp3", "m4a", "aac", "flac", "wav", "wave", "aif", "aiff"].contains(track.url.pathExtension.lowercased()) {
                    converted.append(track)
                    continue
                }
                await progress("正在转换为 AAC · \(track.title)")
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                ownsScratch = removesConvertedFiles
                let digest = try digest(track, bitrate: bitrate)
                let folder = scratch.appending(path: digest, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appending(path: track.url.deletingPathExtension().lastPathComponent + ".m4a")
                if !FileManager.default.fileExists(atPath: destination.path) {
                    let stage = folder.appending(path: "\(UUID().uuidString).m4a")
                    defer {
                        try? FileManager.default.removeItem(at: stage)
                    }
                    try await convert(track, source: track.url, to: stage, bitrate: bitrate)
                    try Task.checkCancellation()
                    try FileManager.default.moveItem(at: stage, to: destination)
                }
                converted.append(Track(id: track.id, url: destination, title: track.title, artist: track.artist,
                                       album: track.album, duration: track.duration, albumArtist: track.albumArtist,
                                       disc: track.disc, number: track.number, artwork: track.artwork))
            }
            try validate()
            let plan = try VolumeTransfer.prepare(converted, into: directory, layout: layout, compareExisting: true)
            return PreparedWalkmanTransfer(plan: plan, temporaryDirectory: ownsScratch ? scratch : nil)
        } catch {
            if ownsScratch { try? FileManager.default.removeItem(at: scratch) }
            throw error
        }
    }

    private static func digest(_ track: Track, bitrate: Int) throws -> String {
        let input = try FileHandle(forReadingFrom: track.url)
        defer { try? input.close() }
        var hash = SHA256()
        hash.update(data: Data("AAC-44100-stereo-\(bitrate)-tags-v2".utf8))
        let fields = [track.title, track.artist, track.album, track.albumArtist,
                      track.disc.map(String.init) ?? "", track.number.map(String.init) ?? ""]
        hash.update(data: try JSONEncoder().encode(fields))
        if let artwork = track.artwork { hash.update(data: artwork) }
        while true {
            try Task.checkCancellation()
            guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { break }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func addMetadata(_ track: Track, source: URL, destination: URL) async throws {
        guard let exporter = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var metadata: [AVMetadataItem] = []
        for (identifier, text) in [(AVMetadataIdentifier.commonIdentifierTitle, track.title),
                                   (.commonIdentifierArtist, track.artist), (.commonIdentifierAlbumName, track.album),
                                   (.iTunesMetadataAlbumArtist, track.albumArtist)] where !text.isEmpty {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = text as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            metadata.append(item)
        }
        for (identifier, number) in [(AVMetadataIdentifier.iTunesMetadataTrackNumber, track.number),
                                     (.iTunesMetadataDiscNumber, track.disc)] {
            if let number, (1...65535).contains(number) {
                let item = AVMutableMetadataItem()
                item.identifier = identifier
                item.dataType = kCMMetadataBaseDataType_RawData as String
                item.value = Data([0, 0, UInt8(number >> 8), UInt8(number & 255), 0, 0, 0, 0]) as NSData
                metadata.append(item)
            }
        }
        if let artwork = track.artwork {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierArtwork
            item.dataType = artwork.starts(with: [137, 80, 78, 71])
                ? kCMMetadataBaseDataType_PNG as String : kCMMetadataBaseDataType_JPEG as String
            item.value = artwork as NSData
            metadata.append(item)
        }
        exporter.metadata = metadata
        exporter.outputURL = destination
        exporter.outputFileType = .m4a
        try Task.checkCancellation()
        await exporter.export()
        try Task.checkCancellation()
        guard exporter.status == .completed else { throw exporter.error ?? CocoaError(.fileWriteUnknown) }
    }

    static func convert(_ track: Track, source: URL, to destination: URL, bitrate: Int) async throws {
        let raw = destination.deletingLastPathComponent().appending(path: "\(UUID().uuidString)-raw.m4a")
        defer { try? FileManager.default.removeItem(at: raw) }
        try await AudioCommand.run(AudioCommand.afconvert,
                                   arguments: ["-f", "m4af", "-d", "aac@44100", "-c", "2", "-b", String(bitrate * 1000),
                                               "-q", "127", source.path, raw.path])
        try await addMetadata(track, source: raw, destination: destination)
    }
}
