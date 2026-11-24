import SwiftUI

private struct ArtistCredit: Decodable, Sendable {
    let name: String
    let joinphrase: String?
}

private func artistName(_ credit: [ArtistCredit]?) -> String {
    (credit ?? []).map { $0.name + ($0.joinphrase ?? "") }.joined()
}

struct AlbumRelease: Decodable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let date: String?
    let country: String?
    let disambiguation: String?
    let media: [Medium]?
    private let artistCredit: [ArtistCredit]?

    var artist: String { artistName(artistCredit) }
    var details: String { [artist, date ?? "", country ?? "", disambiguation ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") }

    enum CodingKeys: String, CodingKey {
        case id, title, date, country, disambiguation, media
        case artistCredit = "artist-credit"
    }

    struct Medium: Decodable, Identifiable, Sendable {
        let position: Int?
        let format: String?
        let tracks: [Song]?
        var id: Int { position ?? 0 }
    }

    struct Song: Decodable, Identifiable, Sendable {
        let position: Int
        let title: String
        private let artistCredit: [ArtistCredit]?
        var id: Int { position }
        var artist: String { artistName(artistCredit) }

        enum CodingKeys: String, CodingKey {
            case position, title
            case artistCredit = "artist-credit"
        }
    }

    func labelDisc(_ disc: [Track], medium: Medium) -> [Track]? {
        guard let position = medium.position, let songs = medium.tracks?.sorted(by: { $0.position < $1.position }),
              !disc.isEmpty, songs.count == disc.count, songs.enumerated().allSatisfy({ $0.element.position == $0.offset + 1 }) else { return nil }
        return zip(disc, songs).map { track, song in
            Track(id: track.id, url: track.url, title: song.title, artist: song.artist.isEmpty ? artist : song.artist,
                  album: title, duration: track.duration, albumArtist: artist, disc: position,
                  number: song.position, artwork: track.artwork)
        }
    }
}

actor MusicBrainz {
    static let shared = MusicBrainz()
    private let session = URLSession(configuration: .ephemeral)
    private var lastRequest: ContinuousClock.Instant?
    private struct Results: Decodable { let releases: [AlbumRelease] }

    func search(_ title: String) async throws -> [AlbumRelease] {
        let value = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let response: Results = try await fetch("release/", [
            URLQueryItem(name: "query", value: "release:\"\(value)\""),
            URLQueryItem(name: "limit", value: "12")
        ])
        return response.releases
    }

    func release(_ id: UUID) async throws -> AlbumRelease {
        try await fetch("release/" + id.uuidString.lowercased(), [URLQueryItem(name: "inc", value: "recordings+artist-credits")])
    }

    private func fetch<T: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> T {
        while let lastRequest, ContinuousClock.now < lastRequest.advanced(by: .seconds(1)) {
            try await Task.sleep(until: lastRequest.advanced(by: .seconds(1)), clock: .continuous)
        }
        try Task.checkCancellation()
        var url = URLComponents()
        url.scheme = "https"
        url.host = "musicbrainz.org"
        url.path = "/ws/2/" + path
        url.queryItems = query + [URLQueryItem(name: "fmt", value: "json")]
        // Query parameters treat a bare plus as a space on this endpoint.
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let endpoint = url.url else { throw URLError(.badURL) }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("MusicCenterMacPreview/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        lastRequest = .now
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, [429, 503].contains(http.statusCode) {
            try await Task.sleep(for: .seconds(2))
            while let lastRequest, ContinuousClock.now < lastRequest.advanced(by: .seconds(1)) {
                try await Task.sleep(until: lastRequest.advanced(by: .seconds(1)), clock: .continuous)
            }
            lastRequest = .now
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            throw NSError(domain: "MusicBrainz", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "MusicBrainz 返回 HTTP \(http.statusCode)。"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct AlbumLookupRequest: Identifiable {
    let id = UUID()
    let title: String
    var disc: AudioDisc?
    var tracks: [Track] = []
}

struct AlbumLookupPanel: View {
    let request: AlbumLookupRequest
    let close: () -> Void
    let apply: ([Track]) -> Void
    @State private var search = ""
    @State private var results: [AlbumRelease] = []
    @State private var resultID: UUID?
    @State private var release: AlbumRelease?
    @State private var mediumID: Int?
    @State private var task: Task<Void, Never>?
    @State private var status = ""

    private var media: [AlbumRelease.Medium] { release?.media?.filter { $0.position != nil && !($0.tracks ?? []).isEmpty } ?? [] }

    private var medium: AlbumRelease.Medium? { media.first { $0.id == mediumID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("MusicBrainz 专辑查询", systemImage: "magnifyingglass")
                .font(.headline)
            Text("点击搜索会将输入的专辑名称发送到 MusicBrainz。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("专辑名称", text: $search).onSubmit(find)
                Button("搜索", action: find).disabled(task != nil || search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let release {
                Text(release.title).font(.title3.bold())
                if media.isEmpty { Text("该版本没有曲目数据。") }
                else {
                    Picker("碟片", selection: $mediumID) {
                        ForEach(media) { disc in
                            Text("第 \(disc.id) 碟 · \(disc.tracks?.count ?? 0) 首").tag(Optional(disc.id))
                        }
                    }
                    List(medium?.tracks ?? []) { song in
                        HStack {
                            Text("\(song.position)").monospacedDigit().foregroundStyle(.secondary)
                            Text(song.title)
                        }
                    }.frame(height: 195)
                    if request.disc != nil, let medium, release.labelDisc(request.tracks, medium: medium) == nil {
                        Text("查询结果的曲目编号或数量与光盘不符。").foregroundStyle(.secondary)
                    }
                }
            } else if !results.isEmpty {
                List(results, selection: $resultID) { result in
                    VStack(alignment: .leading) {
                        Text(result.title)
                        if !result.details.isEmpty {
                            Text(result.details).font(.caption).foregroundStyle(.secondary)
                        }
                    }.tag(result.id)
                }.frame(height: 240)
            }
            if !status.isEmpty { Text(status).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                if release != nil {
                    Button("返回结果") { release = nil; status = "" }
                }
                Spacer()
                Button("关闭", action: close).keyboardShortcut(.cancelAction)
                if request.disc != nil, let release, let medium, let tracks = release.labelDisc(request.tracks, medium: medium) {
                    Button("应用到光盘曲目") { apply(tracks) }.buttonStyle(.borderedProminent)
                } else if release == nil {
                    Button("查看曲目", action: load).disabled(resultID == nil || task != nil)
                }
            }
        }
        .padding(24)
        .frame(width: 550)
        .onAppear { search = request.title }
        .onDisappear { task?.cancel() }
    }

    private func find() {
        let title = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard task == nil, !title.isEmpty else { return }
        release = nil
        results = []
        resultID = nil
        status = "正在查询…"
        task = Task {
            defer { task = nil }
            do {
                let found = try await MusicBrainz.shared.search(title)
                guard !Task.isCancelled else { return }
                results = found
                resultID = found.first?.id
                status = found.isEmpty ? "没有找到专辑。" : ""
            } catch {
                if !Task.isCancelled { status = "查询失败。\(error.localizedDescription)" }
            }
        }
    }

    private func load() {
        guard task == nil, let resultID else { return }
        status = "正在读取曲目…"
        task = Task {
            defer { task = nil }
            do {
                let detail = try await MusicBrainz.shared.release(resultID)
                guard !Task.isCancelled else { return }
                release = detail
                mediumID = media.first { $0.tracks?.count == request.tracks.count }?.id ?? media.first?.id
                status = ""
            } catch {
                if !Task.isCancelled { status = "无法读取曲目。\(error.localizedDescription)" }
            }
        }
    }
}
