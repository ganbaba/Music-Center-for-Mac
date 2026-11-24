import SwiftUI

struct MainMenu: View {
    @Binding var display: DisplaySettings
    let perform: (String) -> Void
    @State private var category = ""
    @State private var branch = ""

    private let categories = ["文件", "编辑", "查看", "控制", "工具", "帮助"]
    private let groups = [
        "文件": [["新建播放列表…"], ["导入文件…", "导入文件夹…"], ["导入播放列表…"], ["退出"]],
        "编辑": [["全选", "取消全选"]],
        "查看": [["更新至最新信息", "文本大小", "应用程序显示颜色", "列表显示间距"]],
        "控制": [["播放/暂停", "停止", "下一首", "上一首"], ["随机播放", "重复播放"], ["提高音量", "降低音量", "静音"], ["弹出光盘"]],
        "工具": [["获取CD信息"], ["批量转化ATRAC"], ["搜索无文件歌曲"], ["更新软件…"], ["数据备份", "恢复备份数据"], ["设置"]],
        "帮助": [["Music Center for PC支持"], ["系统信息", "版本信息"]]
    ]
    private let branches = ["文本大小", "应用程序显示颜色", "列表显示间距", "重复播放"]
    private let keys = ["新建播放列表…": "⌘N", "导入文件…": "⌘O", "导入文件夹…": "⇧⌘O",
                        "退出": "⌘Q", "全选": "⌘A", "取消全选": "⇧⌘A", "更新至最新信息": "F5", "播放/暂停": "F6", "停止": "F7",
                        "下一首": "Ctrl+向右箭头", "上一首": "Ctrl+向左箭头", "弹出光盘": "Ctrl+E",
                        "提高音量": "F10", "降低音量": "F9", "静音": "F8", "Music Center for PC支持": "F1"]

    let repeatMode: Player.RepeatMode
    let isMuted: Bool
    let isShuffled: Bool
    let canPlay: Bool
    let canStop: Bool
    let canGoNext: Bool
    let canGoPrevious: Bool
    let canEject: Bool
    let canLookupCD: Bool
    let canImport: Bool
    let changeRepeat: (Player.RepeatMode) -> Void
    let dismiss: () -> Void

    private let rowHeight: CGFloat = 22.4
    private let inset: CGFloat = 10
    private let separatorHeight: CGFloat = 14

    private var submenuWidth: CGFloat {
        switch category {
        case "查看": 134
        case "控制": 166
        default: 184
        }
    }

    private var branchOffset: CGFloat {
        var offset: CGFloat = 0
        for (index, section) in (groups[category] ?? []).enumerated() {
            if index > 0 { offset += separatorHeight }
            if let row = section.firstIndex(of: branch) { return offset + CGFloat(row) * rowHeight }
            offset += CGFloat(section.count) * rowHeight
        }
        return 0
    }

    var body: some View {
        let categoryOffset = CGFloat(categories.firstIndex(of: category) ?? 0) * rowHeight
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(categories, id: \.self) { title in
                    row(title, width: 77, active: category == title, arrow: true) { choose(title) }
                        .onHover { if $0 { choose(title) } }
                }
            }
            .padding(.vertical, inset)
            .modifier(MainMenuBackground())
            if let sections = groups[category] {
                submenu(sections).padding(.top, categoryOffset)
                branchMenu.padding(.top, categoryOffset + branchOffset)
            }
        }
        .fixedSize()
        .font(.system(size: 11))
    }

    private func choose(_ title: String) {
        guard category != title else { return }
        category = title
        branch = ""
    }

    private func submenu(_ sections: [[String]]) -> some View {
        VStack(spacing: 0) {
            ForEach(sections.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Color(red: 0.83, green: 0.88, blue: 0.97))
                        .frame(height: 1).frame(height: separatorHeight)
                }
                ForEach(sections[index], id: \.self) { title in
                    row(title, width: submenuWidth, active: branch == title, arrow: branches.contains(title),
                        checked: (title == "静音" && isMuted) || (title == "随机播放" && isShuffled), enabled: isEnabled(title)) {
                        if branches.contains(title) { branch = title } else { perform(title) }
                    }
                    .onHover { if $0 { branch = title } }
                }
            }
        }
        .padding(.vertical, inset)
        .modifier(MainMenuBackground())
    }

    @ViewBuilder
    private var branchMenu: some View {
        switch branch {
        case "文本大小":
            choices(DisplaySettings.TextSize.allCases, selected: display.textSize, width: 64) { display.textSize = $0 }
        case "应用程序显示颜色":
            choices(DisplaySettings.Appearance.allCases, selected: display.appearance, width: 100) { display.appearance = $0 }
        case "列表显示间距":
            choices(DisplaySettings.Spacing.allCases, selected: display.spacing, width: 74) { display.spacing = $0 }
        case "重复播放":
            choices(Player.RepeatMode.allCases, selected: repeatMode, width: 93, change: changeRepeat)
        default:
            EmptyView()
        }
    }

    private func choices<Option: RawRepresentable & Hashable>(_ values: [Option], selected: Option, width: CGFloat,
                                                              change: @escaping (Option) -> Void) -> some View
    where Option.RawValue == String {
        VStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                row(value.rawValue, width: width, active: false, arrow: false, radio: value == selected) {
                    change(value)
                    dismiss()
                }
            }
        }
        .padding(.vertical, inset)
        .modifier(MainMenuBackground())
    }

    private func isEnabled(_ title: String) -> Bool {
        switch title {
        case "导入文件…", "导入文件夹…", "导入播放列表…": canImport
        case "播放/暂停": canPlay
        case "停止": canStop
        case "下一首": canGoNext
        case "上一首": canGoPrevious
        case "弹出光盘": canEject
        case "获取CD信息": canLookupCD
        default: true
        }
    }

    private func row(_ title: String, width: CGFloat, active: Bool, arrow: Bool, radio: Bool? = nil,
                     checked: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if let radio {
                    Image(systemName: radio ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 12))
                        .padding(.trailing, 9)
                        .foregroundStyle(radio ? Color(red: 0.05, green: 0.34, blue: 0.82) : .secondary)
                } else if checked {
                    Image(systemName: "checkmark").font(.system(size: 9)).padding(.trailing, 6)
                }
                Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 3)
                if arrow { Image(systemName: "chevron.right").font(.system(size: 8)) }
                else if let key = keys[title] { Text(key).fixedSize().foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 13)
            .frame(width: width, height: rowHeight)
            .background(active ? Color(white: 0.94) : .white)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(radio == true || checked ? .isSelected : [])
    }
}

private struct MainMenuBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: 10).fill(.white)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
        }
    }
}
