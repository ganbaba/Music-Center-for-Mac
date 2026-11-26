import AVFoundation
import CryptoKit
import SQLite3

@MainActor
func verifyProperties(in root: URL) async throws {
    func check(_ condition: @autoclosure () -> Bool, _ reason: String) throws {
        if !condition() { throw PropertyFailure(message: reason) }
    }
    func sql(_ url: URL, _ statement: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw PropertyFailure(message: "test database open") }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else { throw PropertyFailure(message: "test SQL: " + String(cString: sqlite3_errmsg(db))) }
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let library = Library(directory: root.appending(path: "library"))
    let prefs = PreviewPreferences(directory: root.appending(path: "prefs"))
    var fixtures: [(Track, URL)] = []
    for i in 1...3 {
        let url = root.appending(path: "\(i).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        buffer.frameLength = 4800
        memset(buffer.mutableAudioBufferList.pointee.mBuffers.mData, 0, Int(buffer.mutableAudioBufferList.pointee.mBuffers.mDataByteSize))
        try file.write(from: buffer)
        fixtures.append((Track(id: UUID(), url: url, title: "Song \(i)", artist: "Artist \(i)", album: "Album",
            duration: 0.1, albumArtist: "Various", disc: 1, number: i, artwork: nil), url))
    }
    library.registerCopiedAudio(fixtures)
    try check(library.error == nil && library.tracks.count == 3, "fixture registration")
    let beforeAudio = try fixtures.map { SHA256.hash(data: try Data(contentsOf: $0.1)) }
    func rows() -> [CapturedTrack] { library.tracks.sorted { $0.number! < $1.number! }.map(CapturedTrack.init) }
    func song(_ i: Int) -> PropertySubject { .songs([rows()[i]]) }
    var draft = PropertyDraft(subject: song(0), records: library.propertyRecords)
    draft.set("Edited", for: .title); draft.set("Orchestral", for: .genre); draft.set("5", for: .rating)
    try check(library.tracks.first { $0.id == song(0).localTracks[0].id }!.title == "Song 1", "draft must not save")
    try library.saveProperties([draft.change])
    try check(rows()[0].title == "Edited", "single title")
    let reopened = Library(directory: library.directory)
    try check(reopened.propertyRecords == library.propertyRecords, "reopen persistence")
    try library.saveProperties([PropertyChange(subject: song(1), fields: [.genre: "Rock"])])
    var bulk = PropertyDraft(subject: .songs(rows()), records: library.propertyRecords)
    try check(bulk.mixed.contains(.genre) && bulk.mixed.contains(.artist), "mixed selection")
    bulk.set("2026", for: .year)
    try library.saveProperties([bulk.change])
    try check(rows().map(\.artist) == ["Artist 1", "Artist 2", "Artist 3"], "bulk must retain untouched artists")
    bulk = PropertyDraft(subject: .songs(rows()), records: library.propertyRecords)
    bulk.set("", for: .genre)
    try library.saveProperties([bulk.change])
    try check(rows().allSatisfy { library.propertyRecords[.song($0.localTrack!.id)]?.fields[.genre] == "" }, "explicit mixed clear")
    let oldTitle = rows()[0].title
    do {
        try library.saveProperties([PropertyChange(subject: song(0), fields: [.title: "Rollback"]),
            PropertyChange(subject: song(1), fields: [.number: "bad"])])
        throw PropertyFailure(message: "invalid save accepted")
    } catch let failure as PropertyFailure where failure.message == "invalid save accepted" { throw failure }
      catch {}
    try check(Library(directory: library.directory).tracks.first { $0.id == song(0).localTracks[0].id }!.title == oldTitle, "transaction rollback")
    do {
        try PropertyChange(subject: .songs(rows()), fields: [.title: "bulk title"]).validate()
        throw PropertyFailure(message: "bulk title accepted")
    } catch let failure as PropertyFailure where failure.message == "bulk title accepted" { throw failure }
      catch {}
    let album = PropertySubject.collection(TrackCollection.group(rows(), by: .albums)[0], artist: false, byTrack: false)
    try library.saveProperties([PropertyChange(subject: album, fields: [.title: "Renamed album", .genre: "Classical", .artist: "Ensemble"])])
    try check(rows().allSatisfy { $0.album == "Renamed album" && $0.albumArtist == "Ensemble" }, "album member updates")
    try library.saveProperties([PropertyChange(subject: song(1), fields: [.genre: "Jazz"])])
    let updatedAlbum = PropertySubject.collection(TrackCollection.group(rows(), by: .albums)[0], artist: false, byTrack: false)
    try check(PropertyDraft(subject: updatedAlbum, records: library.propertyRecords).mixed.contains(.genre), "album no stale competing record")
    let photo = Data("isolated test artwork".utf8)
    let artist = PropertySubject.collection(TrackCollection.group(rows(), by: .artists)[0], artist: true, byTrack: false)
    try library.saveProperties([PropertyChange(subject: artist, fields: [.artist: "Ensemble 2"], artwork: photo, changesArtwork: true)])
    try check(rows().allSatisfy { $0.albumArtist == "Ensemble 2" && $0.localTrack?.artwork == nil }, "artist photo independent of song covers")
    try check(library.propertyRecords[.artist("Ensemble 2")]?.artwork == photo, "artist photo identity")
    let trackArtist = PropertySubject.collection(TrackCollection.group(rows(), by: .artists, groupArtistsByTrack: true)[0], artist: true, byTrack: true)
    try library.saveProperties([PropertyChange(subject: trackArtist, fields: [.artist: "Soloist"])])
    try check(rows()[0].artist == "Soloist" && rows()[1].artist == "Artist 2", "track artist grouping")
    let playlistFile = root.appending(path: "Test list.m3u8")
    try ("#EXTM3U\n" + [rows()[0], rows()[0], rows()[1]].map { $0.localTrack!.url.absoluteString }.joined(separator: "\n")).write(to: playlistFile, atomically: true, encoding: .utf8)
    let imported = await library.importPlaylist(playlistFile)
    try check(imported, "duplicate playlist import")
    let playlistID = library.playlists.first { $0.name == "Test list" }!.id
    let entries = library.playlistEntries[playlistID]!
    try check(entries.count == 3 && entries[0].trackID == entries[1].trackID && entries[0].id != entries[1].id, "real duplicate membership fixture")
    let byID = Dictionary(uniqueKeysWithValues: rows().map { ($0.localTrack!.id, $0) })
    let members = entries.enumerated().map { byID[$0.element.trackID]!.inPlaylist(entryID: $0.element.id, position: $0.offset + 1) }
    let group = PlaylistGroup(playlist: library.playlists.first { $0.id == playlistID }!, tracks: members)
    try library.saveProperties([PropertyChange(subject: .playlist(group), fields: [.title: "New list", .creator: "QA", .comment: "line 1\nline 2"], artwork: photo, changesArtwork: true)])
    try check(library.playlists.first { $0.id == playlistID }?.name == "New list" && library.playlistEntries[playlistID]!.map(\.id) == entries.map(\.id), "playlist metadata preserves duplicate memberships")
    try check(library.propertyRecords[.playlist(playlistID)]?.createdAt != nil, "playlist registration date")
    let archive = root.appending(path: "properties.musiccenterbackup")
    let notes = "测试备份：第一行\n第二行 '音乐'"
    let estimate = try await library.backupSize(preferences: prefs)
    try check(estimate > 0, "real backup size estimate")
    try library.checkNewBackupDestination(archive)
    let written = try await library.writeNewBackup(to: archive, notes: notes, preferences: prefs)
    try check(written.path == archive.resolvingSymlinksInPath().path, "backup published to the selected destination")
    let hexNotes = notes.utf8.map { String(format: "%02X", $0) }.joined()
    try sql(archive, """
        CREATE TEMP TABLE check_metadata (valid INTEGER CHECK(valid = 1));
        INSERT INTO check_metadata SELECT COUNT(*) FROM music_center_backup_details
        WHERE created_at > 0 AND hex(notes) = '\(hexNotes)';
        """)
    let originalArchive = try Data(contentsOf: archive)
    let cancelledOutput = root.appending(path: "cancelled.musiccenterbackup")
    let cancelled = Task { try await library.writeNewBackup(to: cancelledOutput, notes: "", preferences: prefs) }
    cancelled.cancel()
    do {
        _ = try await cancelled.value
        throw PropertyFailure(message: "cancelled backup was published")
    } catch is CancellationError {}
    try check(!FileManager.default.fileExists(atPath: cancelledOutput.path), "cancellation leaves no archive")
    let obstruction = root.appending(path: "disconnected-destination")
    let failedOutput = obstruction.appending(path: "failed.musiccenterbackup")
    try FileManager.default.createDirectory(at: obstruction, withIntermediateDirectories: false)
    try library.checkNewBackupDestination(failedOutput)
    try FileManager.default.removeItem(at: obstruction)
    let originalObstruction = Data("simulated destination write error".utf8)
    try originalObstruction.write(to: obstruction)
    for blocked in [archive, failedOutput] {
        do {
            _ = try await library.writeNewBackup(to: blocked, notes: "replacement", preferences: prefs)
            throw PropertyFailure(message: "backup published to a blocked destination")
        } catch let failure as PropertyFailure { throw failure }
          catch {}
    }
    let currentArchive = try Data(contentsOf: archive)
    let currentObstruction = try Data(contentsOf: obstruction)
    try check(currentArchive == originalArchive, "duplicate destination never replaces original archive")
    try check(currentObstruction == originalObstruction, "write failure preserves unrelated destination file")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
    try check(!leftovers.contains { $0.hasPrefix(".music-center-backup-") }, "failed backup leaves no staging file")
    let saved = library.propertyRecords
    try library.saveProperties([PropertyChange(subject: song(0), fields: [.genre: "Changed after backup"])])
    _ = try library.restore(from: archive, preferences: prefs)
    try check(library.propertyRecords == saved, "backup restore properties")
    let corrupt = root.appending(path: "corrupt.musiccenterbackup")
    try FileManager.default.copyItem(at: archive, to: corrupt)
    try sql(corrupt, "UPDATE library_properties SET data = x'00'")
    do {
        _ = try library.restore(from: corrupt, preferences: prefs)
        throw PropertyFailure(message: "malformed backup accepted")
    } catch let failure as PropertyFailure where failure.message == "malformed backup accepted" { throw failure }
      catch {}
    try check(library.propertyRecords == saved, "malformed restore leaves current data")
    let legacy = root.appending(path: "legacy.musiccenterbackup")
    try FileManager.default.copyItem(at: archive, to: legacy)
    try sql(legacy, "DROP TABLE library_properties; DROP TABLE music_center_backup_details")
    _ = try library.restore(from: legacy, preferences: prefs)
    try check(library.propertyRecords.isEmpty && library.tracks.count == 3, "legacy backup migration")
    // A window can outlive removal of its selected entity; it must not create orphan metadata.
    let stale = song(2)
    try check(library.removeFromLibrary([stale.localTracks[0].id]), "remove fixture")
    do {
        try library.saveProperties([PropertyChange(subject: stale, fields: [.genre: "orphan"])])
        throw PropertyFailure(message: "stale entity accepted")
    } catch let failure as PropertyFailure where failure.message == "stale entity accepted" { throw failure }
      catch {}
    try check(library.propertyRecords[stale.key] == nil, "no orphan properties")
    let facts = PropertyFileFacts.read(rows()[0].localTrack!)
    try check(facts.format == "WAV(PCM)" && facts.sampleRate.contains("48") && facts.sampleBits.contains("16") && facts.channels == "2 ch", "actual audio facts")
    // Exercise the production Vorbis reader, including explicit sort and total fields.
    func le(_ value: Int) -> Data { var n = UInt32(value).littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
    let fields = ["TITLE=Tagged", "TITLESORT=Sort", "ALBUMARTISTSORT=Ensemble", "GENRE=Jazz", "DATE=2026", "COMPOSER=Composer", "TRACKTOTAL=12", "DISCTOTAL=2", "ORGANIZATION=Label"]
    var comments = le(0) + le(fields.count)
    for field in fields { let data = Data(field.utf8); comments += le(data.count) + data }
    let tagged = root.appending(path: "tags.flac")
    try (Data("fLaC".utf8) + Data([0x84, UInt8((comments.count >> 16) & 255), UInt8((comments.count >> 8) & 255), UInt8(comments.count & 255)]) + comments).write(to: tagged)
    let tags = await TrackTags.read(tagged, asset: AVURLAsset(url: tagged))
    try check(tags.title == "Tagged" && tags.properties[.titleSort] == "Sort" && tags.properties[.totalTracks] == "12" && tags.properties[.label] == "Label", "source metadata fields")
    var merging = PropertyDraft(subject: song(0), records: [:])
    merging.set("User edit", for: .composer)
    merging.mergeSource([song(0).localTracks[0].id: [.composer: "Source", .genre: "Jazz"]], records: [:])
    try check(merging.fields[.composer] == "User edit" && merging.fields[.genre] == "Jazz", "async source cannot overwrite edits")
    let player = Player()
    let queued = [Player.Item(track: rows()[0].localTrack!, playlistEntryID: UUID()),
                  Player.Item(track: rows()[0].localTrack!, playlistEntryID: UUID()),
                  Player.Item(track: rows()[1].localTrack!, playlistEntryID: UUID())]
    player.enqueue(queued, placement: .end)
    let queueIDs = player.queue.map(\.id)
    let changedTrack = queued[0].track
    let renamed = Track(id: changedTrack.id, url: changedTrack.url, title: "Queue rename", artist: changedTrack.artist,
        album: changedTrack.album, duration: changedTrack.duration, albumArtist: changedTrack.albumArtist,
        disc: changedTrack.disc, number: changedTrack.number, artwork: changedTrack.artwork)
    player.refreshMetadata([renamed])
    try check(player.queue.map(\.id) == queueIDs && player.queue[0].title == "Queue rename" && player.queue[1].title == "Queue rename" && !player.isPlaying, "metadata refresh preserves queue and playback state")
    let afterAudio = try fixtures.map { SHA256.hash(data: try Data(contentsOf: $0.1)) }
    try check(beforeAudio == afterAudio, "source audio bytes changed")
    try "PASS: properties persistence, drafts, bulk, album/artist membership, playlist duplicates, atomic rollback, backup/legacy/corrupt restore, stale entities, actual file facts, Vorbis fields, source merge, queue metadata refresh, original audio SHA256.\n".write(to: root.appending(path: "PASS.txt"), atomically: true, encoding: .utf8)
}
