import Foundation
import AVFoundation

@MainActor
func verifyMenus(in root: URL) async throws {
    func check(_ condition: @autoclosure () -> Bool, _ reason: String) throws {
        if !condition() { throw PropertyFailure(message: reason) }
    }
    let leaf = WindowsMenuEntry(id: "leaf", title: "Leaf")
    let child = WindowsMenuEntry(id: "child", title: "Child", children: [leaf], childWidth: 120)
    let menu = [WindowsMenuEntry(id: "disabled", title: "Disabled", enabled: false),
        WindowsMenuEntry(id: "separator", title: "", separator: true), child,
        WindowsMenuEntry(id: "last", title: "Last")]
    var navigation = WindowsMenuNavigation()
    navigation.move(1, in: menu)
    try check(navigation.selected(in: menu)?.id == "child", "keyboard skips disabled and separator")
    navigation.right(in: menu)
    try check(navigation.depth == 1 && navigation.selected(in: menu)?.id == "leaf", "right enters child")
    navigation.left()
    try check(navigation.depth == 0 && navigation.levels(menu).count == 1 && navigation.selected(in: menu)?.id == "child", "left closes child and retains parent")
    navigation.hover(child, at: 0)
    try check(navigation.levels(menu).count == 2, "hover opens submenu")
    navigation.hover(menu.last!, at: 0)
    try check(navigation.levels(menu).count == 1, "leaf hover closes stale submenu")
    navigation.move(1, in: menu)
    try check(navigation.selected(in: menu)?.id == "child", "keyboard wraps enabled rows")
    navigation.right(in: menu)
    let viewport = CGSize(width: 800, height: 520)
    for origin in [CGPoint(x: 20, y: 20), CGPoint(x: 790, y: 510)] {
        let frames = WindowsMenuLayout.frames(root: menu, navigation: navigation, width: 164, origin: origin, viewport: viewport)
        try check(frames.count == 2 && frames.allSatisfy { $0.minX >= 4 && $0.minY >= 4 && $0.maxX <= viewport.width - 4 && $0.maxY <= viewport.height - 4 }, "menus remain inside compact viewport")
        try check(frames[1].minX == frames[0].maxX || frames[1].maxX == frames[0].minX, "submenu opens beside parent without crossing it")
    }
    try check(WindowsMenuLayout.width([WindowsMenuEntry(id: "wide", title: String(repeating: "长", count: 50))], preferred: 64, maximum: 300) == 300, "long menu captions grow within the viewport bound")
    let tall = (0..<100).map { WindowsMenuEntry(id: "\($0)", title: "Item \($0)") }
    try check(WindowsMenuLayout.frames(root: tall, navigation: WindowsMenuNavigation(), width: 164, origin: .zero, viewport: viewport)[0].height == 512, "long menus are bounded and scrollable")
    let capabilities = MainMenuCapabilities()
    try check(!capabilities.allows(.playPause) && !capabilities.allows(.eject) && !capabilities.allows(.selectAll) && capabilities.allows(.volumeUp), "empty library and unavailable hardware capabilities")
    var selectedList: UUID?
    let list = Playlist(id: UUID(), name: "Same visible label")
    let entries = TrackMenuCatalog.entries(kind: .song, playlists: [list], capabilities: TrackMenuCapabilities()) { command in
        if case .addToPlaylist(let id) = command { selectedList = id }
    }
    let add = entries.first { $0.id == "add" }!
    add.children.first { $0.id == list.id.uuidString }!.action?()
    try check(selectedList == list.id, "playlist dispatch uses identity rather than formatted title")

    let track = Track(id: UUID(), url: root.appending(path: "present.wav"), title: "Duplicate", artist: "QA", album: "QA",
        duration: 1, albumArtist: "QA", disc: 1, number: 1, artwork: nil)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    do {
        let file = try AVAudioFile(forWriting: track.url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for channel in 0..<2 { memset(buffer.floatChannelData![channel], 0, 48_000 * 4) }
        try file.write(from: buffer)
    }
    let missing = Track(id: UUID(), url: root.appending(path: "missing.wav"), title: "Missing", artist: "QA", album: "QA",
        duration: 1, albumArtist: "QA", disc: 1, number: 2, artwork: nil)
    let report = await MissingTrackReport.scan([track, missing])
    try check(report.missing == [missing.id] && report.unreadable.isEmpty, "filesystem check reports actual missing references")
    let player = Player()
    let repeated = Player.Item(track: track)
    player.enqueue([repeated, repeated, repeated], placement: .end)
    let ids = player.queueEntries.map(\.queueID)
    try check(Set(ids).count == 3, "duplicate queued songs own distinct identities")
    player.refreshMetadata([track])
    try check(player.queueEntries.map(\.queueID) == ids, "metadata refresh retains queue identities")
    player.toggleShuffle()
    try check(Set(player.queueEntries.map(\.queueID)) == Set(ids), "shuffle retains identity")
    player.removeQueueEntry(ids[1])
    try check(Set(player.queueEntries.map(\.queueID)) == [ids[0], ids[2]], "queue removal targets one duplicate")
    player.removeQueueEntry(ids[1])
    try check(player.queue.count == 2, "stale queue menu cannot remove another item")
    player.removeQueueEntry(ids[0]); player.removeQueueEntry(ids[2])
    try check(!player.hasQueue && player.index == nil && player.elapsed == 0, "last queue removal clears playback selection")
    let active = Player()
    active.setVolume(0)
    active.enqueue([repeated, repeated, repeated], placement: .end)
    let activeIDs = active.queueEntries.map(\.queueID)
    active.jump(toQueueEntry: activeIDs[1])
    let audioAvailable = active.error == nil
    if active.isPlaying { active.toggle() }
    active.removeQueueEntry(activeIDs[0])
    try check(active.currentItem?.queueID == activeIDs[1] && active.index == 0 && !active.isPlaying, "remove before paused current preserves selection")
    active.removeQueueEntry(activeIDs[1])
    try check(active.currentItem?.queueID == activeIDs[2] && active.index == 0 && !active.isPlaying, "remove paused current selects successor without starting playback")
    active.removeQueueEntry(activeIDs[2])
    try check(active.currentItem == nil && !active.hasQueue, "remove last current clears playback")
    try "Audio engine available for silent paused-queue checks: \(audioAvailable)\n".write(to: root.appending(path: "audio-check.txt"), atomically: true, encoding: .utf8)
    try "PASS: menu keyboard/disabled/separator/parent navigation, compact-edge positioning, long menus, capability states, playlist identity dispatch, actual missing files, duplicate queue ownership/shuffle/removal/stale actions.\n".write(to: root.appending(path: "PASS.txt"), atomically: true, encoding: .utf8)
}
