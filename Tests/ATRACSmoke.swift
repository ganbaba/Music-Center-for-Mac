import AVFoundation
import Foundation

@MainActor
func verifyATRAC(in root: URL, sample: URL, decoder: URL, slowDecoder: URL) async throws {
    let root = root.standardizedFileURL.resolvingSymlinksInPath()
    func check(_ value: @autoclosure () -> Bool, _ reason: String) throws {
        if !value() { throw ATRACConversion.Failure(message: "TEST: " + reason) }
    }
    let fm = FileManager.default
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let library = Library(directory: root.appending(path: "library"))
    let first = root.appending(path: "one.oma"), second = root.appending(path: "two.OMA")
    try fm.copyItem(at: sample, to: first); try fm.copyItem(at: sample, to: second)
    let checksum = try ATRACConversion.digest(sample)
    await library.importItems([first, second])
    try check(library.tracks.count == 2, "import ATRAC including uppercase extension")
    let tracks = library.tracks.sorted { $0.url.path < $1.url.path }
    let list = root.appending(path: "duplicates.m3u8")
    try ("#EXTM3U\n" + [first, first, second].map(\.path).joined(separator: "\n")).write(to: list, atomically: true, encoding: .utf8)
    let imported = await library.importPlaylist(list)
    try check(imported, "import real duplicate playlist")
    let entries = library.playlistEntries.mapValues { $0.map(\.id) }
    let subject = PropertySubject.songs([CapturedTrack(tracks[0])])
    try library.saveProperties([PropertyChange(subject: subject, fields: [.genre: "ATRAC regression", .rating: "5"])])
    let properties = library.propertyRecords
    let space = try ATRACConversion.checkSpace(tracks, format: .flac, moveOriginalsTo: nil)
    try check(!space.isEmpty && space.allSatisfy { $0.required > 0 && $0.available >= $0.required }, "actual capacity preflight")
    let flac = try await ATRACConversion.convert(tracks[0], format: .flac, decoder: decoder, moveOriginalsTo: nil, library: library)
    try check(flac.output?.pathExtension == "flac" && flac.issue == nil, "real FLAC conversion")
    let sourceAfter = try ATRACConversion.digest(tracks[0].url)
    try check(sourceAfter == checksum, "keep original byte content")
    let inputPCM = root.appending(path: "input.pcm"), outputPCM = root.appending(path: "output.pcm")
    for (input, output) in [(sample, inputPCM), (flac.output!, outputPCM)] {
        try await AudioCommand.run(decoder, arguments: ["-nostdin", "-v", "error", "-i", input.path,
                                                       "-map", "0:a:0", "-f", "s24le", "-c:a", "pcm_s24le", output.path])
    }
    let inputBytes = try Data(contentsOf: inputPCM), outputBytes = try Data(contentsOf: outputPCM)
    try check(!inputBytes.isEmpty && inputBytes == outputBytes, "FLAC decoded PCM is byte-identical to decoded ATRAC")
    let originalFolder = root.appending(path: "originals")
    try fm.createDirectory(at: originalFolder, withIntermediateDirectories: false)
    let occupied = originalFolder.appending(component: tracks[1].url.lastPathComponent)
    let sentinel = Data("keep occupied original".utf8); try sentinel.write(to: occupied)
    let aac = try await ATRACConversion.convert(tracks[1], format: .aac, decoder: decoder, moveOriginalsTo: originalFolder, library: library)
    try check(aac.output?.pathExtension == "m4a" && aac.issue == nil, "real AAC conversion and move")
    let archivedChecksum = try ATRACConversion.digest(aac.archivedOriginal!)
    let occupiedBytes = try Data(contentsOf: occupied)
    try check(archivedChecksum == checksum && occupiedBytes == sentinel, "move preserves bytes and existing filename")
    try check(!fm.fileExists(atPath: tracks[1].url.path), "original moved only after conversion commit")
    try check(Set(library.tracks.map(\.id)) == Set(tracks.map(\.id)), "track IDs preserved")
    try check(library.propertyRecords == properties && library.playlistEntries.mapValues { $0.map(\.id) } == entries, "properties and duplicate entries preserved")
    let reopened = Library(directory: library.directory)
    try check(reopened.tracks == library.tracks, "replacement paths and duration survive reopen")
    try check(ATRACConversion.candidates(in: reopened.tracks).isEmpty, "converted library has no ATRAC candidates")
    let aacAudio = try AVAudioFile(forReading: aac.output!), flacAudio = try AVAudioFile(forReading: flac.output!)
    let duration = Double(aacAudio.length) / aacAudio.processingFormat.sampleRate
    let expectedDuration = Double(flacAudio.length) / flacAudio.processingFormat.sampleRate
    try check(abs(duration - expectedDuration) < 0.2 && duration > 0, "AAC audio duration verified")
    let corrupt = root.appending(path: "corrupt.aa3"); try Data("not ATRAC".utf8).write(to: corrupt)
    await library.importItems([corrupt])
    guard let corruptTrack = library.tracks.first(where: { $0.url.lastPathComponent == corrupt.lastPathComponent }) else {
        throw ATRACConversion.Failure(message: "TEST: corrupt fixture import: \(library.error ?? library.message ?? "missing")")
    }
    let beforeFailure = library.tracks
    do {
        _ = try await ATRACConversion.convert(corruptTrack, format: .flac, decoder: decoder, moveOriginalsTo: originalFolder, library: library)
        throw ATRACConversion.Failure(message: "TEST: corrupt source accepted")
    } catch let error as ATRACConversion.Failure where error.message.hasPrefix("TEST:") { throw error }
      catch {}
    try check(library.tracks == beforeFailure && fm.fileExists(atPath: corrupt.path), "decode failure preserves original and database")
    let stale = root.appending(path: "stale.at3"); try fm.copyItem(at: sample, to: stale)
    await library.importItems([stale])
    guard let staleTrack = library.tracks.first(where: { $0.url.lastPathComponent == stale.lastPathComponent }) else {
        throw ATRACConversion.Failure(message: "TEST: stale fixture import")
    }
    try check(library.removeFromLibrary([staleTrack.id]), "remove stale entity fixture")
    let beforeNames = try fm.contentsOfDirectory(atPath: root.path).sorted()
    let beforeArchive = try fm.contentsOfDirectory(atPath: originalFolder.path).sorted()
    do {
        _ = try await ATRACConversion.convert(staleTrack, format: .flac, decoder: decoder, moveOriginalsTo: originalFolder, library: library)
        throw ATRACConversion.Failure(message: "TEST: stale track accepted")
    } catch let error as ATRACConversion.Failure where error.message.hasPrefix("TEST:") { throw error }
      catch {}
    let afterNames = try fm.contentsOfDirectory(atPath: root.path).sorted()
    let afterArchive = try fm.contentsOfDirectory(atPath: originalFolder.path).sorted()
    try check(afterNames == beforeNames && afterArchive == beforeArchive && fm.fileExists(atPath: stale.path), "commit failure cleans output/archive and retains source")
    let cancelFile = root.appending(path: "cancel.oma"); try fm.copyItem(at: sample, to: cancelFile)
    await library.importItems([cancelFile])
    guard let cancelTrack = library.tracks.first(where: { $0.url.lastPathComponent == cancelFile.lastPathComponent }) else {
        throw ATRACConversion.Failure(message: "TEST: cancellation fixture import")
    }
    let beforeCancel = library.tracks
    let cancelNames = try fm.contentsOfDirectory(atPath: root.path).sorted()
    let task = Task { try await ATRACConversion.convert(cancelTrack, format: .flac, decoder: slowDecoder, moveOriginalsTo: nil, library: library) }
    try await Task.sleep(for: .milliseconds(350)); task.cancel()
    do {
        _ = try await task.value
        throw ATRACConversion.Failure(message: "TEST: cancelled decode completed")
    } catch is CancellationError {}
    let cancelAfter = try fm.contentsOfDirectory(atPath: root.path).sorted()
    let cancelDigest = try ATRACConversion.digest(cancelFile)
    try check(library.tracks == beforeCancel && cancelNames == cancelAfter && cancelDigest == checksum, "running FFmpeg cancellation cleans output and preserves source/database")
    try "PASS: real ATRAC import, AAC/FLAC audio, lossless PCM equality, keep/move originals, collision preservation, stable IDs/properties/duplicate playlist entries, reopen, corrupt input, failed commit cleanup, real process cancellation.\n".write(to: root.appending(path: "PASS.txt"), atomically: true, encoding: .utf8)
}
