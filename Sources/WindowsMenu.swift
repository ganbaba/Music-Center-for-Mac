import AppKit
import SwiftUI

struct WindowsMenuEntry: Identifiable {
    enum Mark: Equatable { case none, check(Bool), radio(Bool) }
    let id: String
    var title: String
    var shortcut: String? = nil
    var enabled = true
    var mark: Mark = .none
    var children: [Self] = []
    var childWidth: CGFloat = 164
    var separator = false
    var action: (() -> Void)? = nil

    static func sections(_ sections: [[Self]]) -> [Self] {
        sections.enumerated().flatMap { index, section in
            (index == 0 ? [] : [Self(id: "separator-\(index)", title: "", separator: true)]) + section
        }
    }
}

/// Navigation and geometry are shared by main, collection, header and queue menus.
struct WindowsMenuNavigation {
    var expanded: [String] = []
    var highlighted: [Int: String] = [:]
    var depth = 0

    func levels(_ root: [WindowsMenuEntry]) -> [[WindowsMenuEntry]] {
        var result = [root]
        for id in expanded {
            guard let parent = result.last?.first(where: { $0.id == id && $0.enabled }), !parent.children.isEmpty else { break }
            result.append(parent.children)
        }
        return result
    }
    mutating func hover(_ entry: WindowsMenuEntry, at level: Int) {
        depth = level
        highlighted[level] = entry.enabled ? entry.id : nil
        expanded = Array(expanded.prefix(level))
        if entry.enabled && !entry.children.isEmpty { expanded.append(entry.id) }
    }
    mutating func move(_ delta: Int, in root: [WindowsMenuEntry]) {
        let columns = levels(root)
        depth = min(depth, columns.count - 1)
        let rows = columns[depth].filter { !$0.separator && $0.enabled }
        guard !rows.isEmpty else { return }
        let old = rows.firstIndex { $0.id == highlighted[depth] }
        let next = old.map { ($0 + delta + rows.count) % rows.count } ?? (delta > 0 ? 0 : rows.count - 1)
        highlighted[depth] = rows[next].id
        expanded = Array(expanded.prefix(depth))
    }
    mutating func right(in root: [WindowsMenuEntry]) {
        let columns = levels(root)
        guard columns.indices.contains(depth), let entry = columns[depth].first(where: { $0.id == highlighted[depth] }),
              entry.enabled, !entry.children.isEmpty else { return }
        expanded = Array(expanded.prefix(depth)) + [entry.id]
        depth += 1
        highlighted[depth] = entry.children.first { $0.enabled && !$0.separator }?.id
    }
    mutating func left() {
        guard depth > 0 else { return }
        expanded = Array(expanded.prefix(depth - 1))
        depth -= 1
    }
    func selected(in root: [WindowsMenuEntry]) -> WindowsMenuEntry? {
        let columns = levels(root)
        guard columns.indices.contains(depth) else { return nil }
        return columns[depth].first { $0.id == highlighted[depth] && $0.enabled && !$0.separator }
    }
}

enum WindowsMenuLayout {
    static let fontSize: CGFloat = 11
    static let horizontalInset: CGFloat = 15
    static let gap: CGFloat = 4
    static let checkGutter: CGFloat = 22
    static let radioGutter: CGFloat = 21
    static let arrowWidth: CGFloat = 8
    static let row: CGFloat = 22.4
    static let padding: CGFloat = 10
    static let separator: CGFloat = 14
    static func height(_ entries: [WindowsMenuEntry]) -> CGFloat {
        padding * 2 + entries.reduce(0) { $0 + ($1.separator ? separator : row) }
    }
    static func offset(_ id: String, in entries: [WindowsMenuEntry]) -> CGFloat {
        var top: CGFloat = 0
        for entry in entries {
            if entry.id == id { break }
            top += entry.separator ? separator : row
        }
        return top
    }
    static func width(_ entries: [WindowsMenuEntry], preferred: CGFloat, maximum: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        func measure(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let reservesChecks = entries.contains { $0.mark == .check(true) || $0.mark == .check(false) }
        let intrinsic = entries.filter { !$0.separator }.map { entry -> CGFloat in
            let mark: CGFloat
            switch entry.mark {
            case .none: mark = reservesChecks ? checkGutter : 0
            case .check: mark = checkGutter
            case .radio: mark = radioGutter
            }
            let trailing = !entry.children.isEmpty ? arrowWidth : entry.shortcut.map(measure) ?? 0
            return ceil(horizontalInset * 2 + gap + mark + measure(entry.title) + trailing)
        }.max() ?? preferred
        return min(max(preferred, intrinsic), max(44, maximum))
    }
    static func frames(root: [WindowsMenuEntry], navigation: WindowsMenuNavigation, width: CGFloat,
                       origin: CGPoint, viewport: CGSize) -> [CGRect] {
        let columns = navigation.levels(root)
        func fit(_ value: CGFloat, length: CGFloat, limit: CGFloat) -> CGFloat { max(4, min(value, max(4, limit - length - 4))) }
        let rootWidth = Self.width(root, preferred: width, maximum: viewport.width - 8)
        let rootHeight = min(height(root), max(44, viewport.height - 8))
        var frames = [CGRect(x: fit(origin.x, length: rootWidth, limit: viewport.width),
                             y: fit(origin.y, length: rootHeight, limit: viewport.height), width: rootWidth, height: rootHeight)]
        for depth in 1..<columns.count {
            let parent = frames[depth - 1]
            guard let id = navigation.expanded.dropFirst(depth - 1).first,
                  let item = columns[depth - 1].first(where: { $0.id == id }) else { break }
            let width = Self.width(columns[depth], preferred: item.childWidth, maximum: viewport.width - 8)
            let height = min(height(columns[depth]), max(44, viewport.height - 8))
            let x = parent.maxX + width <= viewport.width - 4 ? parent.maxX : parent.minX - width
            frames.append(CGRect(x: fit(x, length: width, limit: viewport.width),
                y: fit(parent.minY + offset(id, in: columns[depth - 1]), length: height, limit: viewport.height),
                width: width, height: height))
        }
        return frames
    }
}

struct WindowsMenu: View {
    let entries: [WindowsMenuEntry]
    let width: CGFloat
    let origin: CGPoint
    let viewport: CGSize
    let title: String
    let close: () -> Void
    @State private var navigation = WindowsMenuNavigation()
    @FocusState private var focused: Bool

    var body: some View {
        let columns = navigation.levels(entries)
        let frames = WindowsMenuLayout.frames(root: entries, navigation: navigation, width: width, origin: origin, viewport: viewport)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture(perform: close)
            ForEach(frames.indices, id: \.self) { depth in
                column(columns[depth], depth: depth, frame: frames[depth])
                    .offset(x: frames[depth].minX, y: frames[depth].minY)
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .font(.system(size: WindowsMenuLayout.fontSize)).foregroundStyle(Color(white: 0.08))
        .environment(\.colorScheme, .light)
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(.upArrow) { navigation.move(-1, in: entries); return .handled }
        .onKeyPress(.downArrow) { navigation.move(1, in: entries); return .handled }
        .onKeyPress(.rightArrow) { navigation.right(in: entries); return .handled }
        .onKeyPress(.leftArrow) { navigation.left(); return .handled }
        .onKeyPress(.return) {
            guard let entry = navigation.selected(in: entries) else { return .handled }
            if entry.children.isEmpty { close(); entry.action?() } else { navigation.right(in: entries) }
            return .handled
        }
        .onKeyPress(.escape) { close(); return .handled }
        .task { focused = true }
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }

    private func column(_ entries: [WindowsMenuEntry], depth: Int, frame: CGRect) -> some View {
        let reservesChecks = entries.contains { $0.mark == .check(true) || $0.mark == .check(false) }
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        if entry.separator {
                            Rectangle().fill(Color(red: 0.83, green: 0.88, blue: 0.97)).frame(height: 1)
                                .frame(height: WindowsMenuLayout.separator).accessibilityHidden(true)
                        } else {
                            menuRow(entry, depth: depth, reservesChecks: reservesChecks).id(entry.id)
                        }
                    }
                }.padding(.vertical, WindowsMenuLayout.padding)
            }
            .scrollIndicators(.never)
            .onChange(of: navigation.highlighted[depth]) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .compositingGroup().shadow(color: .black.opacity(0.25), radius: 8, y: 5)
    }

    private func menuRow(_ entry: WindowsMenuEntry, depth: Int, reservesChecks: Bool) -> some View {
        Button {
            if entry.children.isEmpty { close(); entry.action?() }
            else { navigation.hover(entry, at: depth) }
        } label: {
            HStack(spacing: 0) {
                switch entry.mark {
                case .none: if reservesChecks { Color.clear.frame(width: WindowsMenuLayout.checkGutter, height: 1) }
                case .check(let selected):
                    Image(systemName: "checkmark").font(.system(size: 9)).opacity(selected ? 1 : 0).frame(width: WindowsMenuLayout.checkGutter, alignment: .leading)
                case .radio(let selected):
                    Circle().strokeBorder(selected ? Color(red: 0.05, green: 0.34, blue: 0.82) : Color(white: 0.5), lineWidth: 1.2)
                        .overlay { if selected { Circle().fill(Color(red: 0.05, green: 0.34, blue: 0.82)).padding(3) } }
                        .frame(width: 12, height: 12).padding(.trailing, WindowsMenuLayout.radioGutter - 12)
                }
                Text(entry.title).lineLimit(1)
                Spacer(minLength: WindowsMenuLayout.gap)
                if !entry.children.isEmpty { Image(systemName: "chevron.right").font(.system(size: 8)).frame(width: WindowsMenuLayout.arrowWidth) }
                else if let shortcut = entry.shortcut { Text(shortcut).fixedSize().foregroundStyle(Color(white: 0.3)) }
            }
            .padding(.horizontal, WindowsMenuLayout.horizontalInset).frame(height: WindowsMenuLayout.row)
            .foregroundStyle(entry.enabled ? Color(white: 0.08) : Color(white: 0.58))
            .background(navigation.highlighted[depth] == entry.id ? Color(white: 0.94) : .white)
            .contentShape(Rectangle())
        }
        .buttonStyle(WindowsFlatButtonStyle()).disabled(!entry.enabled)
        .onHover { if $0 { navigation.hover(entry, at: depth) } }
        .accessibilityLabel(entry.title)
        .accessibilityValue(entry.shortcut ?? "")
        .accessibilityAddTraits(entry.mark == .check(true) || entry.mark == .radio(true) ? .isSelected : [])
    }
}

private struct WindowsMenuRequest: Identifiable {
    let id = UUID()
    let anchor: UUID
    let entries: [WindowsMenuEntry]
    let width: CGFloat
    let point: CGPoint?
    let title: String
}
private struct WindowsMenuAnchors: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct PresentWindowsMenu: EnvironmentKey { static let defaultValue: @MainActor @Sendable (WindowsMenuRequest?) -> Void = { _ in } }
private struct ActiveWindowsMenu: EnvironmentKey { static let defaultValue: UUID? = nil }
private extension EnvironmentValues {
    var presentWindowsMenu: @MainActor @Sendable (WindowsMenuRequest?) -> Void {
        get { self[PresentWindowsMenu.self] }
        set { self[PresentWindowsMenu.self] = newValue }
    }
    var activeWindowsMenu: UUID? {
        get { self[ActiveWindowsMenu.self] }
        set { self[ActiveWindowsMenu.self] = newValue }
    }
}

struct WindowsMenuHost: ViewModifier {
    @Binding var isPresented: Bool
    let resetID: String
    @State private var request: WindowsMenuRequest?
    func body(content: Content) -> some View {
        content
            .environment(\.presentWindowsMenu) { request = $0; isPresented = $0 != nil }
            .environment(\.activeWindowsMenu, request?.anchor)
            .overlayPreferenceValue(WindowsMenuAnchors.self) { anchors in
                GeometryReader { geometry in
                    if let request, let anchor = anchors[request.anchor] {
                        let bounds = geometry[anchor]
                        let point = request.point ?? CGPoint(x: 0, y: bounds.height)
                        WindowsMenu(entries: request.entries, width: request.width,
                            origin: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), viewport: geometry.size,
                            title: request.title, close: { self.request = nil; isPresented = false })
                            .id(request.id)
                    }
                }
            }
            .onChange(of: isPresented) { if !isPresented { request = nil } }
            .onChange(of: resetID) { request = nil; isPresented = false }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in request = nil; isPresented = false }
    }
}

struct WindowsMenuButton<Label: View>: View {
    let title: String
    var width: CGFloat = 164
    var point: CGPoint? = nil
    var willOpen: () -> Void = {}
    let entries: () -> [WindowsMenuEntry]
    @ViewBuilder let label: () -> Label
    @State private var id = UUID()
    @Environment(\.presentWindowsMenu) private var present
    @Environment(\.activeWindowsMenu) private var active
    var body: some View {
        Button {
            if active == id { present(nil) }
            else { willOpen(); present(WindowsMenuRequest(anchor: id, entries: entries(), width: width, point: point, title: title)) }
        } label: { label() }
        .buttonStyle(.plain).accessibilityLabel(title)
        .anchorPreference(key: WindowsMenuAnchors.self, value: .bounds) { [id: $0] }
    }
}

private struct WindowsContextMenu: ViewModifier {
    let title: String
    let width: CGFloat
    let prepare: () -> Void
    let entries: () -> [WindowsMenuEntry]
    @State private var id = UUID()
    @Environment(\.presentWindowsMenu) private var present
    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    SecondaryClick(size: geometry.size) { point in
                        prepare()
                        present(WindowsMenuRequest(anchor: id, entries: entries(), width: width, point: point, title: title))
                    }
                }
            }
            .anchorPreference(key: WindowsMenuAnchors.self, value: .bounds) { [id: $0] }
    }
}

extension View {
    func windowsContextMenu(_ title: String, width: CGFloat = 164, prepare: @escaping () -> Void = {},
                            entries: @escaping () -> [WindowsMenuEntry]) -> some View {
        modifier(WindowsContextMenu(title: title, width: width, prepare: prepare, entries: entries))
    }
}

struct WindowsFlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
