import SwiftUI

enum TrackMenuCommand {
    case play, next, queue, newPlaylist, classify, exportWav, exportFlac, unknownProperties, searchAlbum, remove, properties, openCollection, transfer
    case addToPlaylist(UUID)
}

enum TrackMenuKind { case song, playlistSong, album, artist, playlist, playlistDetail }

struct TrackMenuCapabilities {
    var play = false
    var queue = false
    var edit = false
    var remove = false
    var transfer = false
}

enum TrackMenuCatalog {
    static func entries(kind: TrackMenuKind, playlists: [Playlist], capabilities: TrackMenuCapabilities, showsDestination: Bool = true,
                        perform: @escaping (TrackMenuCommand) -> Void) -> [WindowsMenuEntry] {
        func item(_ id: String, _ title: String, _ action: TrackMenuCommand, enabled: Bool = true) -> WindowsMenuEntry {
            WindowsMenuEntry(id: id, title: title, enabled: enabled, action: { perform(action) })
        }
        let add = WindowsMenuEntry(id: "add", title: "添加到播放列表", children:
            [item("new", "新建...", .newPlaylist)] + playlists.map {
                item($0.id.uuidString, $0.name, .addToPlaylist($0.id))
            }, childWidth: 164)
        var first = [item("play", "播放", .play, enabled: capabilities.play),
            item("next", "播放下一曲", .next, enabled: capabilities.queue),
            item("queue", "添加到播放队列", .queue, enabled: capabilities.queue), add]
        if capabilities.transfer {
            first.insert(WindowsMenuEntry(id: "transfer", title: "传输至" + CapturedLibrary.device,
                children: [item("storage", CapturedLibrary.storage, .transfer, enabled: false)]), at: 0)
        }
        if kind == .song || kind == .playlistSong {
            first.append(WindowsMenuEntry(id: "edit", title: "编辑歌曲", children: [
                item("classify", "分类...", .classify),
                item("wav", "保存为WAV格式...", .exportWav, enabled: capabilities.edit),
                item("flac", "保存为FLAC格式...", .exportFlac, enabled: capabilities.edit)]))
            return WindowsMenuEntry.sections([first,
                [item("unknown", "获取未知属性", .unknownProperties), item("search", "搜索专辑", .searchAlbum)],
                [item("remove", kind == .playlistSong ? "从播放列表删除" : "删除", .remove, enabled: capabilities.remove)],
                [item("properties", "属性", .properties)]])
        }
        var groups = [first]
        if kind != .playlistDetail && showsDestination {
            let title = kind == .album ? "前往专辑详情界面" : kind == .artist ? "前往艺术家详情界面" : "前往播放列表详情界面"
            groups.append([item("open", title, .openCollection)])
        }
        if kind == .album { groups.append([item("unknown", "获取未知属性", .unknownProperties), item("search", "搜索专辑", .searchAlbum)]) }
        groups.append([item("remove", kind == .playlist || kind == .playlistDetail ? "删除播放列表" : "删除", .remove, enabled: capabilities.remove)])
        groups.append([item("properties", "属性", .properties)])
        return WindowsMenuEntry.sections(groups)
    }
}

struct SecondaryClick: NSViewRepresentable {
    let size: CGSize
    var action: (CGPoint) -> Void

    func makeNSView(context: Context) -> Observer { Observer() }
    func updateNSView(_ view: Observer, context: Context) {
        view.hitSize = size
        view.action = action
    }

    final class Observer: NSView {
        var action: ((CGPoint) -> Void)?
        var hitSize = CGSize.zero
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, window === event.window,
                      event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.visibleRect.contains(point), CGRect(origin: .zero, size: self.hitSize).contains(point) else { return event }
                self.action?(point)
                return nil
            }
        }
    }
}
