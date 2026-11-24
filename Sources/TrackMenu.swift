import SwiftUI

struct TrackMenu: View {
    let transfer: Bool
    let playlists: [Playlist]
    let addToPlaylist: (UUID) -> Void
    let searchAlbum: () -> Void
    let properties: () -> Void
    let play: (() -> Void)?
    let enqueue: ((Player.QueuePlacement) -> Void)?
    let openPlaylistPrompt: () -> Void
    let isPlaylist: Bool
    let remove: (() -> Void)?
    let exportTracks: ((AudioExportFormat) -> Void)?
    let lookupAlbum: (() -> Void)?

    @State private var hovered: String?
    nonisolated static let width: CGFloat = 174
    static let submenuWidth: CGFloat = 164
    let opensLeft: Bool
    let availableHeight: CGFloat

    private var groups: [[String]] {
        [(transfer ? ["传输至\(CapturedLibrary.device)"] : []) +
         ["播放", "播放下一曲", "添加到播放队列", "添加到播放列表", "编辑歌曲"],
         ["在线查找专辑…", "搜索专辑"], [isPlaylist ? "从播放列表删除" : "删除"], ["属性"]]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if opensLeft { submenuColumn }
            mainColumn
            if !opensLeft { submenuColumn }
        }
        .fixedSize(horizontal: true, vertical: false)
        .font(.system(size: 11))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("歌曲菜单")
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Color(red: 0.82, green: 0.89, blue: 0.99))
                        .frame(height: 1).padding(.vertical, 6)
                }
                ForEach(groups[index], id: \.self) { title in
                    let hasChildren = title == "添加到播放列表" || !submenu(title).isEmpty
                    row(title, hasChildren: hasChildren, highlighted: hovered == title) {
                        if hasChildren { hovered = title } else { run(title) }
                    }
                    .disabled(!isEnabled(title))
                    .onHover { if $0 { hovered = title } }
                }
            }
        }
        .padding(.vertical, 9)
        .frame(width: Self.width)
        .modifier(MenuSurface())
    }

    @ViewBuilder
    private var submenuColumn: some View {
        if let hovered {
            let entries = submenu(hovered)
            let addsToPlaylist = hovered == "添加到播放列表"
            let count = addsToPlaylist ? playlists.count + 1 : entries.count
            if count > 0 {
                let height = min(availableHeight, CGFloat(count) * 22 + 14)
                ScrollView {
                    VStack(spacing: 0) {
                        if addsToPlaylist {
                            SubmenuRow(title: "新建…", action: openPlaylistPrompt)
                            ForEach(playlists) { playlist in
                                SubmenuRow(title: playlist.name) { addToPlaylist(playlist.id) }
                            }
                        } else {
                            ForEach(entries, id: \.self) { item in
                                SubmenuRow(title: item) { run(item) }.disabled(!isEnabled(item))
                            }
                        }
                    }
                    .padding(.vertical, 7)
                }
                .frame(width: Self.submenuWidth, height: height)
                .modifier(MenuSurface())
                .padding(.top, max(0, min(rowOffset(hovered), availableHeight - height)))
            }
        }
    }

    private func rowOffset(_ title: String) -> CGFloat {
        var offset: CGFloat = 0
        for (index, group) in groups.enumerated() {
            if index > 0 { offset += 13 }
            if let row = group.firstIndex(of: title) { return offset + CGFloat(row) * 22 }
            offset += CGFloat(group.count) * 22
        }
        return 0
    }

    private func submenu(_ title: String) -> [String] {
        switch title {
        case "编辑歌曲": ["导出 WAV…", "导出 FLAC…"]
        case "传输至\(CapturedLibrary.device)": [CapturedLibrary.storage]
        default: []
        }
    }

    private func isEnabled(_ title: String) -> Bool {
        switch title {
        case "在线查找专辑…": lookupAlbum != nil
        case "播放": play != nil
        case "播放下一曲", "添加到播放队列": enqueue != nil
        case "删除", "从播放列表删除": remove != nil
        case "导出 WAV…", "导出 FLAC…": exportTracks != nil
        default: true
        }
    }

    private func run(_ title: String) {
        switch title {
        case "播放": play?()
        case "播放下一曲": enqueue?(.next)
        case "添加到播放队列": enqueue?(.end)
        case "在线查找专辑…": lookupAlbum?()
        case "搜索专辑": searchAlbum()
        case "属性": properties()
        case "导出 WAV…": exportTracks?(.wav)
        case "导出 FLAC…": exportTracks?(.flac)
        case "删除", "从播放列表删除": remove?()
        default: break
        }
    }

    private func row(_ title: String, hasChildren: Bool, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if hasChildren { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)) }
            }
            .padding(.horizontal, 14)
            .frame(height: 22)
            .background(highlighted ? Color(white: 0.94) : .white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SubmenuRow: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title).lineLimit(1).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22)
                .background(hovered ? Color(white: 0.94) : .white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct MenuSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .compositingGroup()
            .shadow(color: .black.opacity(0.24), radius: 8, y: 6)
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
