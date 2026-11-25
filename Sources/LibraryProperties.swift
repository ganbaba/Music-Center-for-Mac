import AVFoundation
import Foundation

/// Identity and values for local library properties; source audio files remain independent.
struct PropertyKey: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case song, album, artist, playlist, selection }
    let kind: Kind
    let identity: String
    static func song(_ id: UUID) -> Self { Self(kind: .song, identity: id.uuidString) }
    static func playlist(_ id: UUID) -> Self { Self(kind: .playlist, identity: id.uuidString) }
    static func artist(_ name: String) -> Self { Self(kind: .artist, identity: name) }
    static func album(_ key: AlbumKey) -> Self {
        let data = try! JSONEncoder().encode([key.title, key.artist])
        return Self(kind: .album, identity: String(decoding: data, as: UTF8.self))
    }
}

enum PropertyField: String, CaseIterable, Codable, Sendable {
    case title, titleSort, artist, artistSort, album, albumSort, albumArtist, albumArtistSort
    case genre, year, composer, equalizer, number, totalTracks, disc, totalDiscs, rating, mediaType
    case creator, source, comment, publisher, label, copyright
}

struct PropertyRecord: Codable, Equatable, Sendable {
    var fields: [PropertyField: String] = [:]
    var artwork: Data?
    var overridesArtwork = false
    var createdAt: Date? = nil
    var modifiedAt: Date = .now
}

struct PropertySubject: Identifiable, Sendable {
    let key: PropertyKey
    let tracks: [CapturedTrack]
    var playlist: Playlist?
    var group: TrackCollection?
    var artistByTrack = false
    var id: PropertyKey { key }
    var isMultiple: Bool { key.kind == .selection }
    var hasFileTab: Bool { key.kind == .song }
    var hasArtworkTab: Bool { !isMultiple }
    var title: String {
        switch key.kind {
        case .song: tracks.first?.title ?? "属性"
        case .album: group?.key.title ?? "属性"
        case .artist: group?.key.title ?? "属性"
        case .playlist: playlist?.name ?? "属性"
        case .selection: "属性"
        }
    }
    var hasOnlyLocalTracks: Bool { tracks.allSatisfy { $0.localTrack != nil } }
    var localTracks: [Track] {
        var seen: Set<UUID> = []
        return tracks.compactMap(\.localTrack).filter { seen.insert($0.id).inserted }
    }
    static func songs(_ tracks: [CapturedTrack]) -> Self {
        let key = tracks.count == 1 ? PropertyKey.song(tracks[0].localTrack?.id ?? tracks[0].id) :
            PropertyKey(kind: .selection, identity: tracks.map { $0.id.uuidString }.joined(separator: ","))
        return Self(key: key, tracks: tracks)
    }
    static func collection(_ group: TrackCollection, artist: Bool, byTrack: Bool) -> Self {
        Self(key: artist ? .artist(group.key.title) : .album(group.key), tracks: group.tracks,
             group: group, artistByTrack: byTrack)
    }
    static func playlist(_ group: PlaylistGroup) -> Self {
        Self(key: .playlist(group.id), tracks: group.tracks, playlist: group.playlist)
    }
}

struct PropertiesRequest: Identifiable {
    let id = UUID()
    let subjects: [PropertySubject]
    var selectedIndex = 0
}

struct PropertyChange: Sendable {
    let subject: PropertySubject
    var fields: [PropertyField: String]
    var artwork: Data?
    var changesArtwork = false

    func validate() throws {
        if subject.isMultiple, fields[.title] != nil || fields[.titleSort] != nil || fields[.number] != nil || fields[.disc] != nil {
            throw PropertyFailure(message: "多选歌曲时不能统一修改标题或歌曲、歌碟编号。")
        }
        for field in [PropertyField.number, .totalTracks, .disc, .totalDiscs] {
            if let raw = fields[field], !raw.isEmpty, Int(raw).map({ $0 > 0 }) != true {
                throw PropertyFailure(message: "歌曲和歌碟编号必须为空或正整数。")
            }
        }
        if let rating = fields[.rating], Int(rating).map({ (0...5).contains($0) }) != true {
            throw PropertyFailure(message: "评价必须为 0 至 5 颗星。")
        }
        if let title = fields[.title], subject.key.kind != .selection,
           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PropertyFailure(message: "标题不能为空。")
        }
        if subject.key.kind == .artist, let name = fields[.artist], name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PropertyFailure(message: "艺术家不能为空。")
        }
    }
}

struct PropertyFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct PropertyDraft {
    let subject: PropertySubject
    var fields: [PropertyField: String]
    var initial: [PropertyField: String]
    var mixed: Set<PropertyField>
    var touched: Set<PropertyField> = []
    var artwork: Data?
    var changesArtwork = false

    init(subject: PropertySubject, records: [PropertyKey: PropertyRecord], source: [UUID: [PropertyField: String]] = [:]) {
        self.subject = subject
        let owner = records[subject.key]
        var result: [PropertyField: String] = [:]
        var mixed: Set<PropertyField> = []
        for field in PropertyField.allCases {
            if let value = owner?.fields[field] { result[field] = value; continue }
            if subject.key.kind == .playlist {
                result[field] = field == .title ? subject.playlist?.name ?? "" : ""
                continue
            }
            let values = subject.tracks.map { row -> String in
                let local = row.localTrack
                let songKey = PropertyKey.song(local?.id ?? row.id)
                let song = records[songKey]
                let extras = source[local?.id ?? row.id] ?? [:]
                func extra(_ key: PropertyField) -> String { song?.fields[key] ?? extras[key] ?? "" }
                if subject.key.kind == .album {
                    switch field {
                    case .title: return row.album
                    case .titleSort: return extra(.albumSort)
                    case .artist: return row.albumArtist
                    case .artistSort: return extra(.albumArtistSort)
                    default: break
                    }
                }
                if subject.key.kind == .artist {
                    if field == .artist { return subject.artistByTrack ? row.artist : row.albumArtist }
                    if field == .artistSort { return extra(subject.artistByTrack ? .artistSort : .albumArtistSort) }
                }
                if let value = song?.fields[field] { return value }
                switch field {
                case .title: return row.title
                case .artist: return row.artist
                case .album: return row.album
                case .albumArtist: return row.albumArtist
                case .number: return row.number.map(String.init) ?? ""
                case .disc: return local?.disc.map(String.init) ?? ""
                case .equalizer: return "关"
                case .rating: return "0"
                case .mediaType: return "歌曲"
                default: return extras[field] ?? ""
                }
            }
            if let first = values.first, values.allSatisfy({ $0 == first }) { result[field] = first }
            else { result[field] = ""; if !values.isEmpty { mixed.insert(field) } }
        }
        fields = result
        initial = result
        self.mixed = mixed
        if let owner, owner.overridesArtwork { artwork = owner.artwork }
        else if subject.key.kind == .song || subject.key.kind == .album {
            artwork = subject.tracks.lazy.compactMap { $0.localTrack?.artwork }.first
            if artwork == nil, subject.tracks.first?.localTrack == nil,
               let url = Bundle.main.url(forResource: "CapturedCover", withExtension: "png") {
                artwork = try? Data(contentsOf: url)
            }
        }
    }

    mutating func set(_ value: String, for field: PropertyField) { fields[field] = value; touched.insert(field) }
    mutating func mergeSource(_ values: [UUID: [PropertyField: String]], records: [PropertyKey: PropertyRecord]) {
        let loaded = Self(subject: subject, records: records, source: values)
        for field in PropertyField.allCases where !touched.contains(field) {
            fields[field] = loaded.fields[field]
            initial[field] = loaded.initial[field]
            if loaded.mixed.contains(field) { mixed.insert(field) } else { mixed.remove(field) }
        }
    }
    var change: PropertyChange {
        let changed = fields.filter { touched.contains($0.key) && ($0.value != initial[$0.key] || mixed.contains($0.key)) }
        return PropertyChange(subject: subject, fields: changed, artwork: artwork, changesArtwork: changesArtwork)
    }
}

struct PropertyFileFacts: Sendable {
    var path = ""
    var format = "—"
    var bitrate = "—"
    var sampleRate = "—"
    var sampleBits = "—"
    var channels = "—"
    var size = "—"
    var modifiedAt: Date?

    static func read(_ track: Track) -> Self {
        let resource = try? track.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var result = Self(path: track.url.path, format: "\(track.format)(—)", modifiedAt: resource?.contentModificationDate)
        if let bytes = resource?.fileSize {
            result.size = (Double(bytes) / 1_048_576).formatted(.number.precision(.fractionLength(0...1))) + "MB"
            if let seconds = track.duration, seconds > 0 {
                let bits = Double(bytes) * 8 / seconds
                result.bitrate = bits >= 1_000_000 ? (bits / 1_000_000).formatted(.number.precision(.fractionLength(1))) + " mbps" :
                    (bits / 1000).formatted(.number.precision(.fractionLength(0))) + " kbps"
            }
        }
        if let audio = try? AVAudioFile(forReading: track.url) {
            let format = audio.fileFormat.streamDescription.pointee
            let codec: String
            switch format.mFormatID {
            case kAudioFormatLinearPCM: codec = "PCM"
            case kAudioFormatFLAC: codec = "FLAC"
            case kAudioFormatMPEG4AAC: codec = "AAC"
            case kAudioFormatMPEGLayer3: codec = "MP3"
            case kAudioFormatAppleLossless: codec = "ALAC"
            default: codec = String(format: "0x%08X", format.mFormatID)
            }
            result.format = "\(track.format)(\(codec))"
            result.sampleRate = format.mSampleRate.isFinite && format.mSampleRate > 0 ? AudioRenderRate.label(for: format.mSampleRate) : "—"
            result.sampleBits = format.mBitsPerChannel > 0 ? "\(format.mBitsPerChannel) bit" : "—"
            result.channels = "\(format.mChannelsPerFrame) ch"
        }
        return result
    }
}

struct PropertySourceValues: Sendable {
    var tags: [UUID: [PropertyField: String]] = [:]
    var file: PropertyFileFacts?

    static func read(_ subject: PropertySubject) async -> Self {
        guard subject.key.kind != .playlist else { return Self() }
        let tracks = subject.localTracks
        var result = Self()
        await withTaskGroup(of: (UUID, [PropertyField: String]).self) { group in
            var iterator = tracks.makeIterator()
            func enqueue(_ track: Track) {
                group.addTask {
                    guard !Task.isCancelled else { return (track.id, [:]) }
                    let tags = await TrackTags.read(track.url, asset: AVURLAsset(url: track.url))
                    return (track.id, tags.properties)
                }
            }
            for _ in 0..<4 { if let track = iterator.next() { enqueue(track) } }
            while let (id, fields) = await group.next() {
                result.tags[id] = fields
                if !Task.isCancelled, let track = iterator.next() { enqueue(track) }
            }
        }
        if subject.hasFileTab, let track = tracks.first, !Task.isCancelled { result.file = PropertyFileFacts.read(track) }
        return result
    }
}
