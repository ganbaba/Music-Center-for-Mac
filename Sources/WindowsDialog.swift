import SwiftUI

enum WindowsDialogSymbol { case none, warning, error, information }
struct WindowsDialogButton: Identifiable {
    let id: String
    let title: String
    var action: () -> Void = {}
    init(_ id: String, _ title: String, action: @escaping () -> Void = {}) {
        self.id = id; self.title = title; self.action = action
    }
}
struct WindowsDialogOption {
    let title: String
    var enabled = false
    var help = ""
}

struct WindowsDialog: View {
    var title = "Music Center for PC"
    let message: String
    var symbol: WindowsDialogSymbol = .none
    var width: CGFloat = 356
    let buttons: [WindowsDialogButton]
    var defaultButton = "ok"
    var cancelButton = "ok"
    var option: WindowsDialogOption? = nil
    let dismiss: () -> Void
    @State private var selected: String?
    @State private var checked = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 12)).frame(width: 24, height: 26).contentShape(Rectangle())
                }.buttonStyle(WindowsFlatButtonStyle()).accessibilityLabel("关闭提示")
            }.padding(.leading, 10).padding(.trailing, 3).background(Color(red: 0.94, green: 0.95, blue: 0.98))
            HStack(alignment: .top, spacing: 12) {
                symbolView
                Text(message).font(.system(size: 12)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(14).frame(minHeight: 60, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if let option {
                    Button { checked.toggle() } label: {
                        HStack(spacing: 7) {
                            Rectangle().fill(.white).overlay { Rectangle().strokeBorder(Color(white: 0.65)) }
                                .overlay { if checked { Image(systemName: "checkmark").font(.system(size: 9)).foregroundStyle(.black) } }
                                .frame(width: 12, height: 12)
                            Text(option.title).font(.system(size: 10))
                        }
                    }.buttonStyle(WindowsFlatButtonStyle()).foregroundStyle(option.enabled ? Color(white: 0.08) : Color(white: 0.58)).disabled(!option.enabled).help(option.help)
                    .accessibilityLabel(option.title)
                }
                Spacer(minLength: 4)
                ForEach(buttons) { button in
                    Button { run(button) } label: {
                        Text(button.title).font(.system(size: 11)).frame(minWidth: 64).frame(height: 23)
                            .background(.white, in: RoundedRectangle(cornerRadius: 2))
                            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder((selected ?? defaultButton) == button.id ? Color(red: 0.05, green: 0.4, blue: 0.8) : Color(white: 0.75)) }
                            .contentShape(Rectangle())
                    }.buttonStyle(WindowsFlatButtonStyle())
                }
            }.padding(.horizontal, 10).padding(.vertical, 9).background(Color(white: 0.94))
        }
        .foregroundStyle(Color(white: 0.08)).frame(width: width)
        .background(.white, in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color(white: 0.7), lineWidth: 0.7) }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
        .environment(\.colorScheme, .light)
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(.escape) { cancel(); return .handled }
        .onKeyPress(.return) {
            if let button = buttons.first(where: { $0.id == (selected ?? defaultButton) }) { run(button) }
            return .handled
        }
        .onKeyPress(keys: [.tab], phases: .down) { press in cycle(press.modifiers.contains(.shift) ? -1 : 1); return .handled }
        .onKeyPress(.leftArrow) { cycle(-1); return .handled }
        .onKeyPress(.rightArrow) { cycle(1); return .handled }
        .task { focused = true }
        .accessibilityElement(children: .contain).accessibilityLabel("提示窗口")
    }
    @ViewBuilder private var symbolView: some View {
        switch symbol {
        case .none: EmptyView()
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 26)).foregroundStyle(Color.yellow)
                .overlay { Text("!").font(.system(size: 19, weight: .bold)).foregroundStyle(.black).offset(y: 2) }
                .accessibilityLabel("警告")
        case .error:
            Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(Color(red: 0.8, green: 0.1, blue: 0.1)).accessibilityLabel("错误")
        case .information:
            Image(systemName: "info.circle.fill").font(.system(size: 26)).foregroundStyle(.blue).accessibilityLabel("信息")
        }
    }
    private func run(_ button: WindowsDialogButton) { button.action(); dismiss() }
    private func cancel() {
        if let button = buttons.first(where: { $0.id == cancelButton }) { run(button) } else { dismiss() }
    }
    private func cycle(_ delta: Int) {
        guard !buttons.isEmpty else { return }
        let old = buttons.firstIndex { $0.id == (selected ?? defaultButton) } ?? 0
        selected = buttons[(old + delta + buttons.count) % buttons.count].id
    }
}

private struct WindowsDialogPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let symbol: WindowsDialogSymbol
    let width: CGFloat
    let buttons: [WindowsDialogButton]
    let defaultButton: String
    let cancelButton: String
    let option: WindowsDialogOption?
    func body(content: Content) -> some View {
        content.disabled(isPresented)
            .overlay {
                if isPresented {
                    GeometryReader { geometry in
                        let scale = min(1, max(0.1, (geometry.size.width - 24) / width))
                        ZStack {
                            Color.black.opacity(0.001).contentShape(Rectangle())
                            WindowsDialog(title: title, message: message, symbol: symbol, width: width, buttons: buttons,
                                defaultButton: defaultButton, cancelButton: cancelButton, option: option,
                                dismiss: { isPresented = false })
                                .scaleEffect(scale)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
    }
}

extension View {
    func windowsAlert(_ title: String = "Music Center for PC", isPresented: Binding<Bool>, message: String,
                      symbol: WindowsDialogSymbol = .none, width: CGFloat = 356,
                      buttons: [WindowsDialogButton] = [WindowsDialogButton("ok", "确定")],
                      defaultButton: String = "ok", cancelButton: String = "ok", option: WindowsDialogOption? = nil) -> some View {
        modifier(WindowsDialogPresentation(isPresented: isPresented, title: title, message: message, symbol: symbol,
            width: width, buttons: buttons, defaultButton: defaultButton, cancelButton: cancelButton, option: option))
    }
}
