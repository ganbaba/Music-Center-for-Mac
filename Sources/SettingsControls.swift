import SwiftUI

/// Shared Windows-style controls used by every settings page.
enum SettingsStyle {
    static let gold = Color(red: 0.70, green: 0.57, blue: 0.29)
    static let ink = Color(white: 0.08)
    static let heading = Color(white: 0.30)
}

struct SettingsCheck: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Rectangle().fill(isOn ? SettingsStyle.gold.opacity(enabled ? 1 : 0.25) : .white)
                    if isOn {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        Rectangle().strokeBorder(enabled ? SettingsStyle.ink : Color(white: 0.75))
                    }
                }
                .frame(width: 16, height: 16)
                Text(title).foregroundStyle(enabled ? SettingsStyle.ink : Color(white: 0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "已勾选" : "未勾选")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct SettingsRadio: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Circle().strokeBorder(enabled ? (selected ? SettingsStyle.gold : SettingsStyle.ink) : Color(white: 0.75))
                    .overlay { if selected { Circle().fill(SettingsStyle.gold.opacity(enabled ? 1 : 0.25)).padding(2.5) } }
                    .frame(width: 16, height: 16)
                Text(title).fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 24, alignment: .leading)
            .foregroundStyle(enabled ? SettingsStyle.ink : Color(white: 0.75))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SettingsAction: View {
    let title: String
    var width: CGFloat = 96
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, width: CGFloat = 96, action: @escaping () -> Void) {
        self.title = title
        self.width = width
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).frame(width: width, height: 27)
                .foregroundStyle(enabled ? SettingsStyle.ink : Color(white: 0.58))
                .background(.white)
                .overlay { Rectangle().strokeBorder(enabled ? SettingsStyle.ink : Color(white: 0.65)) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct SettingsScrollMeasurement: Equatable {
    var height: CGFloat
    var top: CGFloat
}

private struct SettingsScrollMeasurements: PreferenceKey {
    static let defaultValue: [UUID: SettingsScrollMeasurement] = [:]
    static func reduce(value: inout [UUID: SettingsScrollMeasurement], nextValue: () -> [UUID: SettingsScrollMeasurement]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Trackpad scrolling plus the original flat scrollbar and arrow controls.
struct SettingsScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var id = UUID()
    @State private var measured = SettingsScrollMeasurement(height: 0, top: 0)
    @State private var dragOrigin: CGFloat?

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                let overflow = max(0, measured.height - viewport.size.height)
                let offset = min(overflow, max(0, -measured.top))
                let ratio = overflow > 0 ? offset / overflow : 0
                HStack(spacing: 6) {
                    ScrollView(.vertical, showsIndicators: false) {
                        content()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: SettingsScrollMeasurements.self,
                                        value: [id: SettingsScrollMeasurement(height: geometry.size.height,
                                            top: geometry.frame(in: .named(id)).minY)])
                                }
                            }
                            .id(id)
                    }
                    .scrollIndicators(.never)
                    .coordinateSpace(name: id)
                    if overflow > 1 {
                        let track = max(1, viewport.size.height - 26)
                        let thumb = min(track, max(24, track * viewport.size.height / measured.height))
                        let travel = max(1, track - thumb)
                        VStack(spacing: 0) {
                            arrow("chevron.up") { move(to: offset - 32, overflow: overflow, proxy: proxy) }
                            ZStack(alignment: .top) {
                                Color.white
                                    .onTapGesture { point in
                                        move(to: (point.y / track) * overflow, overflow: overflow, proxy: proxy)
                                    }
                                Rectangle().fill(Color(white: 0.74))
                                    .frame(height: thumb).offset(y: ratio * travel)
                                    .gesture(DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if dragOrigin == nil { dragOrigin = ratio }
                                            let fraction = min(1, max(0, (dragOrigin ?? ratio) + value.translation.height / travel))
                                            move(to: fraction * overflow, overflow: overflow, proxy: proxy)
                                        }
                                        .onEnded { _ in dragOrigin = nil })
                            }
                            .frame(height: track)
                            arrow("chevron.down") { move(to: offset + 32, overflow: overflow, proxy: proxy) }
                        }
                        .frame(width: 16)
                    }
                }
                .onPreferenceChange(SettingsScrollMeasurements.self) { values in
                    if let value = values[id] { measured = value }
                }
            }
        }
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(Color(white: 0.50))
                .frame(width: 16, height: 13).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "chevron.up" ? "向上滚动" : "向下滚动")
    }

    private func move(to offset: CGFloat, overflow: CGFloat, proxy: ScrollViewProxy) {
        guard overflow > 0 else { return }
        proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: min(1, max(0, offset / overflow))))
    }
}
