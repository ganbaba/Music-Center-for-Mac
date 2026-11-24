import SwiftUI

struct CapturedTrack: Identifiable {
    private let sourceID: UUID
    private(set) var playlistEntryID: UUID?
    private(set) var displayPosition: Int?
    var id: UUID { playlistEntryID ?? sourceID }

    let number: Int?
    let title: String
    let artist: String
    let seconds: Double
    let sizeMB: Double
    let localTrack: Track?

    init(number: Int, title: String, artist: String, seconds: Double, sizeMB: Double) {
        sourceID = UUID()
        self.number = number
        self.title = title
        self.artist = artist
        self.seconds = seconds
        self.sizeMB = sizeMB
        localTrack = nil
    }

    init(_ track: Track) {
        sourceID = track.id
        number = track.number
        title = track.title
        artist = track.artist
        seconds = track.duration ?? 0
        let bytes = (try? track.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        sizeMB = Double(bytes) / (1024 * 1024)
        localTrack = track
    }

    func inPlaylist(entryID: UUID, position: Int) -> Self {
        var row = numbered(at: position)
        row.playlistEntryID = entryID
        return row
    }

    func numbered(at position: Int) -> Self {
        var row = self
        row.displayPosition = position
        return row
    }

    var duration: String { previewTime(seconds) }
    var size: String { "\(sizeMB.formatted(.number.precision(.fractionLength(0...1))))MB" }
    var album: String { localTrack?.album ?? CapturedLibrary.album }
    var albumArtist: String {
        guard let localTrack else { return CapturedLibrary.albumArtist }
        return localTrack.albumArtist.isEmpty ? localTrack.artist : localTrack.albumArtist
    }

    func matches(_ search: String) -> Bool {
        search.isEmpty || [title, artist, album, albumArtist].contains { $0.localizedCaseInsensitiveContains(search) }
    }
}

func registrationLabel(_ date: Date?) -> String {
    date?.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "zh_CN"))) ?? ""
}

func previewTime(_ seconds: Double) -> String {
    let total = seconds.isFinite && seconds >= 0 && seconds < Double(Int.max) ? Int(seconds) : 0
    return String(format: "%02d:%02d", total / 60, total % 60)
}

struct TrackCollection: Identifiable {
    let key: AlbumKey
    let tracks: [CapturedTrack]
    var id: AlbumKey { key }
    let latestRegistration: Date?

    static func group(_ tracks: [CapturedTrack], by page: LibraryPage, groupArtistsByTrack: Bool = false) -> [Self] {
        Dictionary(grouping: tracks) { track in
            let artist = groupArtistsByTrack ? track.artist : track.albumArtist
            return page == .artists
                ? AlbumKey(title: artist.isEmpty ? "未知艺术家" : artist, artist: "")
                : AlbumKey(title: track.album.isEmpty ? "未知专辑" : track.album, artist: track.albumArtist)
        }.map { key, members in
            let order = members.sorted { first, second in
                if let a = first.localTrack, let b = second.localTrack {
                    return Track.albumOrder(a, b)
                }
                return (first.number ?? Int.max) < (second.number ?? Int.max)
            }
            let latestRegistration = members.lazy.compactMap { $0.localTrack?.registeredAt }.max()
            return Self(key: key, tracks: order, latestRegistration: latestRegistration)
        }.sorted {
            if page == .new {
                let first = $0.latestRegistration ?? .distantPast
                let second = $1.latestRegistration ?? .distantPast
                if first != second { return first > second }
            }
            let comparison = $0.key.title.localizedStandardCompare($1.key.title)
            return comparison == .orderedSame
                ? $0.key.artist.localizedStandardCompare($1.key.artist) == .orderedAscending
                : comparison == .orderedAscending
        }
    }
}

enum CapturedLibrary {
    static let album = "ゼノブレイド2 オリジナル・サウンドトラック"
    static let albumArtist = "光田康典 / ACE(工藤ともり、CHiCO) / 平松建治 / 清田愛未"
    static let device = "NW-WM1Z/WM1A"
    static let storage = "系统储存空间 (G:)"
    static let albumDuration = "04:48"
    static let albumSize = "160.3MB"
    static let registered = "2026/11/13 01:…"
    static let used = 8.23
    static let capacity = 12.26
    static let folders = ["Adele", "Christian-Pierre La …", "Coldplay", "Hans Zimmer", "Taylor Swift", "网易云音乐", "陈怡"]
    static let tracks = [
        CapturedTrack(number: 1, title: "Xenoblade II - Where It All Began -", artist: "光田康典", seconds: 79, sizeMB: 44.3),
        CapturedTrack(number: 5, title: "バーンのテーマ", artist: "平松建治", seconds: 29, sizeMB: 16.5),
        CapturedTrack(number: 22, title: "ブレイド誕生", artist: "平松建治", seconds: 66, sizeMB: 37),
        CapturedTrack(number: 58, title: "最強サクラの歌", artist: "平松建治", seconds: 112, sizeMB: 62.3)
    ]
}

struct CapturedCover: View {
    var artwork: Data?
    var reference = false

    var body: some View {
        let image = artwork.flatMap(NSImage.init(data:)) ?? referenceImage
        if let image {
            Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("专辑封面")
        } else {
            Image(systemName: "music.note").foregroundStyle(.secondary).accessibilityLabel("无封面")
        }
    }

    private var referenceImage: NSImage? {
        guard reference, let url = Bundle.main.url(forResource: "CapturedCover", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct PlaylistGroup: Identifiable {
    let playlist: Playlist
    let tracks: [CapturedTrack]
    var id: UUID { playlist.id }
    var name: String { playlist.name }
    var duration: String { previewTime(tracks.reduce(0) { $0 + $1.seconds }) }
    var summary: String { "\(tracks.count)歌曲, \(duration)" }
    var size: String { "\(tracks.reduce(0) { $0 + $1.sizeMB }.formatted(.number.precision(.fractionLength(0...1))))MB" }
    var artwork: Data? { tracks.lazy.compactMap { $0.localTrack?.artwork }.first }
}

struct PlaylistCover: View {
    let group: PlaylistGroup
    var body: some View {
        if let artwork = group.artwork {
            CapturedCover(artwork: artwork)
        } else {
            GeometryReader { geometry in
                Color(white: 0.71)
                    .overlay {
                        Image(systemName: "list.bullet.below.rectangle")
                            .font(.system(size: geometry.size.width * 0.33, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
            }
            .accessibilityHidden(true)
        }
    }
}

struct CapturedTable: View {
    let tracks: [CapturedTrack]
    let columns: [String]
    var isDevice = false
    var collection: LibraryPage?
    var isGrid = false
    @Binding var selection: Set<UUID>
    var onShowAlbum: (CapturedTrack) -> Void
    var onProperties: (CapturedTrack) -> Void
    var connected: Bool
    var playlists: [Playlist] = []
    var playlistGroups: [PlaylistGroup]? = nil
    var showsDisplayPositions = false
    var playlistID: UUID?
    var allowsReordering = false
    var reorderPlaylist: ([UUID], [UUID], UUID) -> Bool = { _, _, _ in false }
    var removeFromPlaylist: ([UUID], UUID) -> Void = { _, _ in }
    var removeFromLibrary: (([Track]) -> Void)?
    var deletePlaylist: (Playlist) -> Void = { _ in }
    var openPlaylist: (UUID) -> Void = { _ in }
    var playPlaylist: (PlaylistGroup) -> Void = { _ in }
    var addToPlaylist: ([Track], UUID) -> Void = { _, _ in }
    var playingTrackID: UUID?
    var playingPlaylistEntryID: UUID?
    var play: (([CapturedTrack], CapturedTrack) -> Void)?
    var enqueue: (([CapturedTrack], Player.QueuePlacement) -> Void)?

    var exportTracks: (([Track], AudioExportFormat) -> Void)?
    var lookupAlbum: ((CapturedTrack) -> Void)?

    @Binding var columnWidths: [String: Double]
    var rowHeight: CGFloat = 40
    var textScale: CGFloat = 1
    var selectedRowColor = Color(white: 0.84)
    var groupArtistsByTrack = false
    var onNewPlaylist: ([Track]) -> Void = { _ in }
    @State private var resizing: (column: String, width: CGFloat, currentWidth: CGFloat)?
    @State private var menu: (track: CapturedTrack, order: [CapturedTrack], playlistID: UUID?, point: CGPoint)?
    @State private var draggedTrack: UUID?
    @State private var dropTarget: UUID?
    @State private var selectedPlaylist: UUID?
    @State private var expandedPlaylists: Set<UUID> = []
    @State private var selectedCover: AlbumKey?
    @State private var sortColumn: String?
    @State private var ascending = true
    @State private var expanded: Set<AlbumKey> = []
    @State private var selectionAnchor: UUID?
    @State private var hovered: UUID?

    @Environment(\.colorScheme) private var colorScheme
    private var muted: Color { Color(white: colorScheme == .dark ? 0.65 : 0.48) }
    private let gold = Color(red: 0.70, green: 0.57, blue: 0.29)

    private var tableWidth: CGFloat { 70 + columns.map(width).reduce(0, +) }
    private func ordered(_ tracks: [CapturedTrack]) -> [CapturedTrack] {
        guard let sortColumn else { return tracks }
        if showsDisplayPositions && sortColumn == "#" { return ascending ? tracks : Array(tracks.reversed()) }
        return tracks.sorted { a, b in
            let comparison: ComparisonResult
            switch sortColumn {
            case "歌曲长度": comparison = a.seconds == b.seconds ? .orderedSame : a.seconds < b.seconds ? .orderedAscending : .orderedDescending
            case "文件大小": comparison = a.sizeMB == b.sizeMB ? .orderedSame : a.sizeMB < b.sizeMB ? .orderedAscending : .orderedDescending
            case "歌曲编号", "#": comparison = a.number == b.number ? .orderedSame : (a.number ?? Int.max) < (b.number ?? Int.max) ? .orderedAscending : .orderedDescending
            case "最后注册":
                let first = a.localTrack?.registeredAt ?? .distantPast
                let second = b.localTrack?.registeredAt ?? .distantPast
                comparison = first.compare(second)
            default: comparison = value(a, sortColumn).localizedStandardCompare(value(b, sortColumn))
            }
            return comparison == .orderedSame ? (a.number ?? Int.max) < (b.number ?? Int.max) : comparison == (ascending ? .orderedAscending : .orderedDescending)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    heading
                    if isDevice {
                        ForEach(CapturedLibrary.folders, id: \.self) { folder in
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Color(white: 0.69))
                                    .frame(width: 44)
                                Text(folder).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: rowHeight)
                        }
                    }
                    if let playlistGroups {
                        if isGrid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 166, maximum: 166), spacing: 22)],
                                      alignment: .leading, spacing: 22) {
                                ForEach(playlistGroups) { playlistTile($0) }
                            }
                            .frame(width: geometry.size.width, alignment: .leading)
                        } else {
                            ForEach(playlistGroups) { playlistRow($0) }
                        }
                    } else if let collection {
                        let groups = TrackCollection.group(tracks, by: collection, groupArtistsByTrack: groupArtistsByTrack)
                        if isGrid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 194, maximum: 194), spacing: 16, alignment: .topLeading)],
                                      alignment: .leading, spacing: 20) {
                                ForEach(groups) { collectionEntry(collection, group: $0) }
                            }
                            .frame(width: geometry.size.width, alignment: .leading)
                        } else {
                            ForEach(groups) { collectionEntry(collection, group: $0) }
                        }
                    } else {
                        rows(ordered(tracks), playlistID: playlistID)
                    }
                }
                .frame(minWidth: max(geometry.size.width, tableWidth), alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .coordinateSpace(name: "track-table")
            .overlay(alignment: .topLeading) {
                if let menu {
                    menuOverlay(menu.track, order: menu.order, playlistID: menu.playlistID, at: menu.point, in: geometry.size)
                }
            }
        }
        .onChange(of: isGrid) { expanded = []; expandedPlaylists = []; menu = nil }
        .onChange(of: tracks.map(\.id)) { menu = nil }
        .onChange(of: columns) {
            if let sortColumn, !columns.contains(sortColumn) { self.sortColumn = nil }
        }
        .onExitCommand { menu = nil }
    }

    private func menuOverlay(_ track: CapturedTrack, order: [CapturedTrack], playlistID: UUID?, at point: CGPoint, in size: CGSize) -> some View {
        let canTransfer = connected && !isDevice
        let height: CGFloat = canTransfer ? 277 : 255
        let x = max(0, min(point.x, size.width - TrackMenu.width))
        let y = max(0, min(point.y, size.height - height))
        let left = x >= TrackMenu.submenuWidth && x + TrackMenu.width + TrackMenu.submenuWidth > size.width
        let selected = order.filter { selection.contains($0.id) }
        let targets = selected.compactMap(\.localTrack)
        let remove: (() -> Void)?
        if let playlistID {
            remove = {
                menu = nil
                removeFromPlaylist(selected.compactMap(\.playlistEntryID), playlistID)
            }
        } else {
            remove = targets.isEmpty ? nil : removeFromLibrary.map { action in
                { menu = nil; action(targets) }
            }
        }
        return ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { menu = nil }
            TrackMenu(transfer: canTransfer, playlists: targets.isEmpty ? [] : playlists, addToPlaylist: { id in
                menu = nil
                addToPlaylist(targets, id)
            }, searchAlbum: {
                menu = nil
                onShowAlbum(track)
            }, properties: {
                menu = nil
                onProperties(track)
            }, play: play.map { action in
                {
                    menu = nil
                    action(order, track)
                }
            }, enqueue: targets.isEmpty ? nil : enqueue.map { action in
                {
                    menu = nil
                    action(selected, $0)
                }
            }, openPlaylistPrompt: {
                menu = nil
                onNewPlaylist(targets)
            }, isPlaylist: playlistID != nil, remove: remove, exportTracks: targets.isEmpty ? nil : exportTracks.map { action in
                { format in
                    menu = nil
                    action(targets, format)
                }
            }, lookupAlbum: lookupAlbum.map { action in
                {
                    menu = nil
                    action(track)
                }
            }, opensLeft: left, availableHeight: size.height - y)
            .foregroundStyle(Color(white: 0.08))
            .environment(\.colorScheme, .light)
            .id(track.id)
            .alignmentGuide(.leading) { left ? $0[.trailing] - TrackMenu.width : 0 }
            .offset(x: x, y: y)
        }
    }

    private var heading: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 44)
            if columns.contains("#") { headerCell("#") }
            Group {
                if !isDevice { Image(systemName: "info.circle.fill") }
            }
            .foregroundStyle(muted)
            .frame(width: 26)
            ForEach(columns.filter { $0 != "#" }, id: \.self) { headerCell($0) }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11 * textScale))
        .foregroundStyle(muted)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(white: 0.76)).frame(height: 1)
        }
    }

    private func headerCell(_ name: String) -> some View {
        Button {
            if sortColumn == name {
                ascending.toggle()
            } else {
                sortColumn = name
                ascending = true
            }
        } label: {
            HStack(spacing: 3) {
                if name == "高解析度" { hrBadge } else { Text(name).lineLimit(1) }
                if sortColumn == name {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 7))
                }
            }
            .padding(.horizontal, 8)
            .frame(width: width(name), height: 21, alignment: alignment(name))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(sortColumn == name ? Color.primary : muted)
        .overlay(alignment: .trailing) { resizeHandle(name) }
    }

    private func resizeHandle(_ name: String) -> some View {
        Rectangle()
            .fill(resizing?.column == name ? gold : Color(white: 0.75))
            .frame(width: 1, height: resizing?.column == name ? 17 : 5)
            .frame(width: 9, height: 21, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if resizing?.column != name { resizing = (name, width(name), width(name)) }
                        if let resizing { self.resizing?.currentWidth = min(650, max(42, resizing.width + value.translation.width)) }
                    }
                    .onEnded { _ in
                        if let resizing { columnWidths[name] = Double(resizing.currentWidth) }
                        resizing = nil
                    }
            )
            .onTapGesture(count: 2) { columnWidths[name] = nil }
            .help("拖动调整列宽")
    }

    private func rows(_ order: [CapturedTrack], playlistID: UUID? = nil) -> some View {
        ForEach(order) { track in
            let playingID = track.playlistEntryID == nil ? playingTrackID : playingPlaylistEntryID
            let row = HStack(spacing: 0) {
                Group {
                    if let playingID, playingID == track.id { Image(systemName: "speaker.wave.2.fill").foregroundStyle(gold) }
                    else { Color.clear }
                }
                .frame(width: 44)
                if columns.contains("#") {
                    Text((track.displayPosition ?? track.number).map(String.init) ?? "").padding(.trailing, 7)
                        .frame(width: width("#"), alignment: .trailing)
                }
                Color.clear.frame(width: 26)
                ForEach(columns.filter { $0 != "#" }, id: \.self) { name in
                    Group {
                        if name == "高解析度" {
                            if track.localTrack == nil { hrBadge } else { Color.clear.frame(height: 1) }
                        } else {
                            Text(value(track, name)).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(width: width(name), alignment: alignment(name))
                }
                Spacer(minLength: 0)
            }
            .frame(height: rowHeight)
            .background(selection.contains(track.id) ? selectedRowColor : hovered == track.id ? Color(white: colorScheme == .dark ? 0.26 : 0.91) : .clear)
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? track.id : nil }
            .onTapGesture(count: 2) {
                select(track, in: order)
                play?(order, track)
            }
            .onTapGesture { select(track, in: order) }
            .background {
                GeometryReader { row in
                    SecondaryClick(size: row.size) { point in
                        if !selection.contains(track.id) { selection = [track.id] }
                        selectionAnchor = track.id
                        let origin = row.frame(in: .named("track-table")).origin
                        menu = (track, order, playlistID, CGPoint(x: origin.x + point.x, y: origin.y + point.y))
                    }
                    .frame(width: row.size.width, height: row.size.height)
                }
            }
            .accessibilityAddTraits(selection.contains(track.id) ? .isSelected : [])
            if let playlistID, allowsReordering, order.count > 1, sortColumn == nil || (sortColumn == "#" && ascending) {
                row.onDrag {
                    draggedTrack = track.id
                    return NSItemProvider(object: track.id.uuidString as NSString)
                }
                .dropDestination(for: String.self) { values, point in
                    guard let draggedTrack, values == [draggedTrack.uuidString] else { return false }
                    self.draggedTrack = nil
                    return movePlaylistTrack(draggedTrack, relativeTo: track.id, after: point.y > rowHeight / 2,
                                             tracks: order, in: playlistID)
                } isTargeted: { targeted in
                    if targeted { dropTarget = track.id }
                    else if dropTarget == track.id { dropTarget = nil }
                }
                .overlay {
                    if dropTarget == track.id, draggedTrack != nil, draggedTrack != track.id {
                        Rectangle().strokeBorder(gold, lineWidth: 1).allowsHitTesting(false)
                    }
                }
            } else {
                row
            }
        }
    }

    private func movePlaylistTrack(_ source: UUID, relativeTo target: UUID, after: Bool,
                                   tracks: [CapturedTrack], in playlistID: UUID) -> Bool {
        guard source != target else { return false }
        let original = tracks.map(\.id)
        guard let sourceIndex = original.firstIndex(of: source), let targetIndex = original.firstIndex(of: target) else {
            return false
        }
        var order = original
        order.remove(at: sourceIndex)
        let insertion = targetIndex + (after ? 1 : 0) - (sourceIndex < targetIndex ? 1 : 0)
        order.insert(source, at: insertion)
        return order == original || reorderPlaylist(order, original, playlistID)
    }

    private func select(_ track: CapturedTrack, in ordered: [CapturedTrack]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let selectionAnchor,
           let start = ordered.firstIndex(where: { $0.id == selectionAnchor }),
           let end = ordered.firstIndex(where: { $0.id == track.id }) {
            selection = Set(ordered[min(start, end)...max(start, end)].map(\.id))
        } else if flags.contains(.command) {
            if selection.contains(track.id) { selection.remove(track.id) } else { selection.insert(track.id) }
            selectionAnchor = track.id
        } else {
            selection = [track.id]
            selectionAnchor = track.id
        }
    }

    @ViewBuilder
    private func playlistTile(_ group: PlaylistGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            PlaylistCover(group: group)
                .frame(width: 158, height: 158)
                .overlay {
                    if selectedPlaylist == group.id { Rectangle().strokeBorder(gold, lineWidth: 2) }
                }
                .overlay(alignment: .trailing) {
                    playlistMore(group).padding(.trailing, 7)
                }
            Text(group.name).lineLimit(1)
            Text(group.summary).font(.system(size: 11)).foregroundStyle(muted)
        }
        .frame(width: 166, alignment: .leading)
        .padding(.top, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selectedPlaylist = group.id; playPlaylist(group) }
        .onTapGesture { selectedPlaylist = group.id }
        .contextMenu { playlistActions(group) }
        .accessibilityAddTraits(selectedPlaylist == group.id ? .isSelected : [])
    }

    private func playlistRow(_ group: PlaylistGroup) -> some View {
        let expanded = expandedPlaylists.contains(group.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                PlaylistCover(group: group).frame(width: 52, height: 58)
                disclosure(expanded).frame(width: width("#") + 18)
                ForEach(columns.filter { $0 != "#" }, id: \.self) { column in
                    Text(playlistValue(column, group: group)).lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(width: width(column), alignment: alignment(column))
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .trailing) { playlistMore(group).padding(.trailing, 8) }
            .background(expanded ? selectedRowColor : .clear)
            .contentShape(Rectangle())
            .onTapGesture { if expanded { expandedPlaylists.remove(group.id) } else { expandedPlaylists.insert(group.id) } }
            .contextMenu { playlistActions(group) }
            if expanded { rows(group.tracks, playlistID: group.id) }
        }
    }

    private func playlistValue(_ column: String, group: PlaylistGroup) -> String {
        switch column {
        case "标题": group.name
        case "歌曲长度": group.duration
        case "文件大小": group.size
        default: ""
        }
    }

    private func playlistMore(_ group: PlaylistGroup) -> some View {
        Menu { playlistActions(group) } label: {
            Image(systemName: "ellipsis").frame(width: 22, height: 22)
                .background(.regularMaterial, in: Circle())
        }
        .fixedSize()
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("\(group.name)的更多操作")
    }

    @ViewBuilder
    private func playlistActions(_ group: PlaylistGroup) -> some View {
        Button("播放") { playPlaylist(group) }.disabled(group.tracks.isEmpty)
        Button("播放下一曲") { enqueue?(group.tracks, .next) }.disabled(group.tracks.isEmpty || enqueue == nil)
        Button("添加到播放队列") { enqueue?(group.tracks, .end) }.disabled(group.tracks.isEmpty || enqueue == nil)
        Button("前往播放列表详情界面") { openPlaylist(group.id) }
        Divider()
        Button("删除播放列表", role: .destructive) { deletePlaylist(group.playlist) }
    }

    @ViewBuilder
    private func collectionEntry(_ page: LibraryPage, group: TrackCollection) -> some View {
        let isArtist = page == .artists
        let title = group.key.title
        let open = expanded.contains(group.id)
        let reference = group.tracks.first?.localTrack == nil
        let artwork = group.tracks.lazy.compactMap { $0.localTrack?.artwork }.first
        if isGrid {
            VStack(alignment: isArtist ? .center : .leading, spacing: 2) {
                CapturedCover(artwork: artwork, reference: reference)
                    .frame(width: 194, height: isArtist ? 164 : 184)
                    .overlay {
                        if selectedCover == group.id { Rectangle().strokeBorder(gold, lineWidth: 2.5) }
                    }
                Text(title).font(.system(size: 15 * textScale)).lineLimit(1)
                Text(isArtist ? "\(group.tracks.count)歌曲" : group.key.artist)
                    .font(.system(size: 12 * textScale)).foregroundStyle(muted).lineLimit(1)
            }
            .frame(width: 194)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if let first = group.tracks.first { play?(group.tracks, first) }
            }
            .onTapGesture {
                selectedCover = selectedCover == group.id ? nil : group.id
                selection = selectedCover == nil ? [] : Set(group.tracks.map(\.id))
            }
            .padding(.top, 9)
        } else {
            Button {
                if open { expanded.remove(group.id) } else { expanded.insert(group.id) }
            } label: {
                HStack(spacing: 0) {
                    CapturedCover(artwork: artwork, reference: reference).frame(width: 44, height: 64)
                    if columns.contains("#") {
                        disclosure(open).frame(width: width("#"))
                        Color.clear.frame(width: 26)
                    } else {
                        disclosure(open).frame(width: 26)
                    }
                    ForEach(columns.filter { $0 != "#" }, id: \.self) { name in
                        Text(collectionValue(name, group: group, reference: reference))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(width: width(name), alignment: alignment(name))
                    }
                    Spacer(minLength: 0)
                }
                .background(open ? selectedRowColor : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { rows(ordered(group.tracks)) }
        }
    }

    private func disclosure(_ open: Bool) -> some View {
        Image(systemName: open ? "chevron.down" : "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 32, height: 32)
            .background(open ? selectedRowColor : .clear, in: Circle())
            .accessibilityLabel(open ? "收起曲目" : "展开曲目")
    }

    private func collectionValue(_ name: String, group: TrackCollection, reference: Bool) -> String {
        switch name {
        case "标题": group.key.title
        case "艺术家": group.key.artist.isEmpty ? group.key.title : group.key.artist
        case "歌曲长度": reference ? CapturedLibrary.albumDuration : previewTime(group.tracks.reduce(0) { $0 + $1.seconds })
        case "文件大小": reference ? CapturedLibrary.albumSize : "\(group.tracks.reduce(0) { $0 + $1.sizeMB }.formatted(.number.precision(.fractionLength(0...1))))MB"
        case "最后注册": reference ? CapturedLibrary.registered : registrationLabel(group.latestRegistration)
        default: ""
        }
    }

    private var hrBadge: some View {
        Text("HR")
            .font(.system(size: 10))
            .foregroundStyle(gold)
            .padding(.horizontal, 2)
            .overlay { RoundedRectangle(cornerRadius: 1).strokeBorder(gold, lineWidth: 1) }
    }

    private func width(_ name: String) -> CGFloat {
        if resizing?.column == name, let resizing { return resizing.currentWidth }
        if let width = columnWidths[name] { return CGFloat(width) }
        return switch name {
        case "标题", "专辑": 168
        case "高解析度": 64
        case "艺术家", "类型", "发行年份", "最后注册": 136
        case "歌曲长度", "文件大小": 88
        case "歌曲编号", "#": 56
        default: 112
        }
    }

    private func alignment(_ name: String) -> Alignment {
        switch name {
        case "高解析度": .center
        case "歌曲长度", "文件大小", "发行年份", "歌曲编号", "最后注册": .trailing
        default: .leading
        }
    }

    private func value(_ track: CapturedTrack, _ column: String) -> String {
        switch column {
        case "标题", "歌曲": track.title
        case "艺术家": track.artist
        case "专辑": track.album
        case "歌曲长度": track.duration
        case "文件大小": track.size
        case "歌曲编号", "#": track.number.map(String.init) ?? ""
        case "最后注册": track.localTrack == nil ? CapturedLibrary.registered : registrationLabel(track.localTrack?.registeredAt)
        case "专辑艺术家": track.albumArtist
        case "格式": track.localTrack?.format ?? "FLAC"
        case "歌碟编号": track.localTrack?.disc.map(String.init) ?? ""
        default: ""
        }
    }
}
