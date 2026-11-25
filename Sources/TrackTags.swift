import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct TrackTags {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var disc: Int?
    var number: Int?
    var artwork: Data?
    var properties: [PropertyField: String] = [:]

    static func read(_ url: URL, asset: AVURLAsset) async -> Self {
        if url.pathExtension.lowercased() == "flac", let tags = try? readFLAC(url) {
            return tags
        }

        let common = (try? await asset.load(.commonMetadata)) ?? []
        let items = (try? await asset.load(.metadata)) ?? []
        var tags = TrackTags()
        tags.title = await string(.commonIdentifierTitle, in: common)
        tags.artist = await string(.commonIdentifierArtist, in: common)
        tags.album = await string(.commonIdentifierAlbumName, in: common)
        tags.albumArtist = await string(.iTunesMetadataAlbumArtist, in: items)
        if tags.albumArtist == nil {
            tags.albumArtist = await string(.id3MetadataBand, in: items)
        }
        tags.disc = await position(.id3MetadataPartOfASet, .iTunesMetadataDiscNumber, in: items)
        tags.number = await position(.id3MetadataTrackNumber, .iTunesMetadataTrackNumber, in: items)
        let propertyIdentifiers: [(PropertyField, [AVMetadataIdentifier])] = [
            (.titleSort, [.id3MetadataTitleSortOrder]),
            (.artistSort, [.id3MetadataPerformerSortOrder]),
            (.albumSort, [.id3MetadataAlbumSortOrder]),
            (.genre, [.iTunesMetadataUserGenre, .id3MetadataContentType]),
            (.year, [.iTunesMetadataReleaseDate, .commonIdentifierCreationDate]),
            (.composer, [.iTunesMetadataComposer, .id3MetadataComposer]),
            (.publisher, [.commonIdentifierPublisher]),
            (.copyright, [.commonIdentifierCopyrights, .iTunesMetadataCopyright])
        ]
        for (field, identifiers) in propertyIdentifiers {
            for identifier in identifiers {
                if let value = await string(identifier, in: common + items) {
                    tags.properties[field] = value
                    break
                }
            }
        }
        for item in AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork) {
            if let data = try? await item.load(.dataValue), let artwork = thumbnail(data) {
                tags.artwork = artwork
                break
            }
        }
        return tags
    }

    private static func string(_ identifier: AVMetadataIdentifier, in items: [AVMetadataItem]) async -> String? {
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
            if let value = try? await item.load(.stringValue), let value = nonempty(value) { return value }
        }
        return nil
    }

    private static func position(_ id3: AVMetadataIdentifier, _ iTunes: AVMetadataIdentifier, in items: [AVMetadataItem]) async -> Int? {
        if let value = await string(id3, in: items), let number = position(value) { return number }
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: iTunes).first else { return nil }
        if let value = try? await item.load(.stringValue), let number = position(value) { return number }
        if let value = try? await item.load(.numberValue), value.intValue > 0 { return value.intValue }
        // MP4 trkn and disk atoms put the big-endian index after two reserved bytes.
        if let bytes = try? await item.load(.dataValue), bytes.count >= 6 {
            let index = Int(bytes[2]) << 8 | Int(bytes[3])
            return index > 0 ? index : nil
        }
        return nil
    }

    private static func position(_ text: String?) -> Int? {
        guard let field = text?.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first,
              let value = Int(field.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 192
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    // RFC 9639 §8.6 and §8.8. Read only metadata blocks before the audio frames.
    private static func readFLAC(_ url: URL) throws -> Self {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let end = try file.seekToEnd()
        try file.seek(toOffset: 0)
        guard try file.read(upToCount: 4) == Data("fLaC".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        var offset: UInt64 = 4
        var tags = TrackTags()
        var hasFrontCover = false
        while let header = try file.read(upToCount: 4), header.count == 4 {
            let type = header[0] & 0x7f
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            offset += 4 + UInt64(length)
            guard offset <= end else { break }

            if type == 4, let data = try file.read(upToCount: length), data.count == length {
                let fields = vorbisFields(data)
                tags.title = fields["TITLE"]
                tags.artist = fields["ARTIST"]
                tags.album = fields["ALBUM"]
                tags.albumArtist = fields["ALBUMARTIST"] ?? fields["ALBUM ARTIST"]
                tags.disc = position(fields["DISCNUMBER"])
                tags.number = position(fields["TRACKNUMBER"])
                let propertyKeys: [(PropertyField, String)] = [(.titleSort, "TITLESORT"), (.artistSort, "ARTISTSORT"),
                    (.albumSort, "ALBUMSORT"), (.albumArtistSort, "ALBUMARTISTSORT"), (.genre, "GENRE"),
                    (.year, "DATE"), (.composer, "COMPOSER"), (.publisher, "PUBLISHER"), (.label, "ORGANIZATION"),
                    (.copyright, "COPYRIGHT"), (.totalTracks, "TRACKTOTAL"), (.totalDiscs, "DISCTOTAL")]
                for (field, key) in propertyKeys { tags.properties[field] = fields[key] }

            } else if type == 6, !hasFrontCover, let data = try file.read(upToCount: length),
                      let picture = flacPicture(data), (picture.front || tags.artwork == nil),
                      let artwork = thumbnail(picture.image) {
                tags.artwork = artwork
                hasFrontCover = picture.front
            }

            if header[0] & 0x80 != 0 { break }
            try file.seek(toOffset: offset)
        }
        return tags
    }

    private static func vorbisFields(_ data: Data) -> [String: String] {
        var reader = BlockReader(data: data, littleEndian: true)
        guard let vendorLength = reader.uint32(), reader.skip(vendorLength),
              let count = reader.uint32(), count <= reader.remaining / 4 else { return [:] }
        let keys: Set<String> = ["TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "ALBUM ARTIST", "DISCNUMBER", "TRACKNUMBER", "TITLESORT", "ARTISTSORT", "ALBUMSORT", "ALBUMARTISTSORT", "GENRE", "DATE", "COMPOSER", "PUBLISHER", "ORGANIZATION", "COPYRIGHT", "TRACKTOTAL", "DISCTOTAL"]
        var fields: [String: String] = [:]
        for _ in 0..<count {
            guard let length = reader.uint32(), let field = reader.bytes(length) else { break }
            guard let equals = field.firstIndex(of: 61),
                  let key = String(bytes: field[..<equals], encoding: .ascii)?.uppercased(),
                  keys.contains(key), fields[key] == nil,
                  let value = String(bytes: field[(equals + 1)...], encoding: .utf8) else { continue }
            fields[key] = nonempty(value)
        }
        return fields
    }

    private static func flacPicture(_ data: Data) -> (front: Bool, image: Data)? {
        var reader = BlockReader(data: data, littleEndian: false)
        guard let type = reader.uint32(), let mimeLength = reader.uint32(), let mime = reader.bytes(mimeLength),
              mime != Data("-->".utf8), let descriptionLength = reader.uint32(), reader.skip(descriptionLength),
              reader.skip(16), let length = reader.uint32(), length > 0,
              let image = reader.bytes(length) else { return nil }
        return (type == 3, image)
    }

    private struct BlockReader {
        let data: Data
        let littleEndian: Bool
        private var offset = 0
        var remaining: Int { data.count - offset }

        init(data: Data, littleEndian: Bool) {
            self.data = data
            self.littleEndian = littleEndian
        }

        mutating func skip(_ count: Int) -> Bool {
            guard count <= remaining else { return false }
            offset += count
            return true
        }

        mutating func bytes(_ count: Int) -> Data? {
            let start = offset
            guard skip(count) else { return nil }
            return data[start..<offset]
        }

        mutating func uint32() -> Int? {
            guard remaining >= 4 else { return nil }
            let raw = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            offset += 4
            return Int(littleEndian ? UInt32(littleEndian: raw) : UInt32(bigEndian: raw))
        }
    }
}
