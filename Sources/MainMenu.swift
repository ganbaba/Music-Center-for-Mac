import SwiftUI

enum MainMenuCommand: String, CaseIterable {
    case newPlaylist = "新建播放列表...", importFiles = "导入文件...", importFolder = "导入文件夹...", importPlaylist = "导入播放列表...", quit = "退出"
    case selectAll = "全选", deselectAll = "取消全选", refresh = "更新至最新信息"
    case playPause = "播放/暂停", stop = "停止", next = "下一首", previous = "上一首", shuffle = "随机播放"
    case volumeUp = "提高音量", volumeDown = "降低音量", mute = "静音", eject = "弹出光盘"
    case lookupCD = "获取CD信息", atrac = "批量转化ATRAC", missing = "搜索无文件歌曲", update = "更新软件..."
    case backup = "数据备份", restore = "恢复备份数据", settings = "设置"
    case support = "Music Center for PC支持", system = "系统信息", version = "版本信息"

    var shortcut: String? {
        switch self {
        case .newPlaylist: "Ctrl+N"
        case .importFiles: "Ctrl+O"
        case .quit: "Alt+F4"
        case .selectAll: "Ctrl+A"
        case .deselectAll: "Ctrl+Shift+A"
        case .refresh: "F5"
        case .playPause: "F6"
        case .stop: "F7"
        case .next: "Ctrl+向右箭头"
        case .previous: "Ctrl+向左箭头"
        case .volumeUp: "F10"
        case .volumeDown: "F9"
        case .mute: "F8"
        case .eject: "Ctrl+E"
        case .lookupCD: "Ctrl+I"
        case .support: "F1"
        default: nil
        }
    }
}

struct MainMenuCapabilities {
    var canPlay = false
    var canStop = false
    var canGoNext = false
    var canGoPrevious = false
    var canEject = false
    var canLookupCD = false
    var canImport = true
    var canSelect = false
    var canDeselect = false
    var canSearch = true
    func allows(_ command: MainMenuCommand) -> Bool {
        switch command {
        case .importFiles, .importFolder, .importPlaylist: canImport
        case .selectAll: canSelect
        case .deselectAll: canDeselect
        case .missing: canSearch
        case .playPause: canPlay
        case .stop: canStop
        case .next: canGoNext
        case .previous: canGoPrevious
        case .eject: canEject
        case .lookupCD: canLookupCD
        default: true
        }
    }
}

enum MainMenuCatalog {
    static func entries(display: Binding<DisplaySettings>, repeatMode: Player.RepeatMode, isMuted: Bool, isShuffled: Bool,
                        capabilities: MainMenuCapabilities, perform: @escaping (MainMenuCommand) -> Void,
                        changeRepeat: @escaping (Player.RepeatMode) -> Void) -> [WindowsMenuEntry] {
        func item(_ command: MainMenuCommand) -> WindowsMenuEntry {
            WindowsMenuEntry(id: String(describing: command), title: command.rawValue, shortcut: command.shortcut,
                enabled: capabilities.allows(command),
                mark: command == .shuffle ? .check(isShuffled) : command == .mute ? .check(isMuted) : .none,
                action: { perform(command) })
        }
        func group(_ id: String, _ width: CGFloat, _ sections: [[WindowsMenuEntry]]) -> WindowsMenuEntry {
            WindowsMenuEntry(id: id, title: id, children: WindowsMenuEntry.sections(sections), childWidth: width)
        }
        func choices<T: RawRepresentable & Hashable>(_ id: String, _ values: [T], selected: T, width: CGFloat,
                                                      change: @escaping (T) -> Void) -> WindowsMenuEntry where T.RawValue == String {
            WindowsMenuEntry(id: id, title: id, children: values.map { value in
                WindowsMenuEntry(id: value.rawValue, title: value.rawValue, mark: .radio(value == selected), action: { change(value) })
            }, childWidth: width)
        }
        return [
            group("文件", 148, [[item(.newPlaylist)], [item(.importFiles), item(.importFolder)], [item(.importPlaylist)], [item(.quit)]]),
            group("编辑", 142, [[item(.selectAll), item(.deselectAll)]]),
            group("查看", 134, [[item(.refresh),
                choices("文本大小", DisplaySettings.TextSize.allCases, selected: display.wrappedValue.textSize, width: 64) { display.wrappedValue.textSize = $0 },
                choices("应用程序显示颜色", DisplaySettings.Appearance.allCases, selected: display.wrappedValue.appearance, width: 100) { display.wrappedValue.appearance = $0 },
                choices("列表显示间距", DisplaySettings.Spacing.allCases, selected: display.wrappedValue.spacing, width: 74) { display.wrappedValue.spacing = $0 }]]),
            group("控制", 166, [[item(.playPause), item(.stop), item(.next), item(.previous)],
                [item(.shuffle), choices("重复播放", Player.RepeatMode.allCases, selected: repeatMode, width: 93, change: changeRepeat)],
                [item(.volumeUp), item(.volumeDown), item(.mute)], [item(.eject)]]),
            group("工具", 142, [[item(.lookupCD)], [item(.atrac)], [item(.missing)], [item(.update)], [item(.backup), item(.restore)], [item(.settings)]]),
            group("帮助", 162, [[item(.support)], [item(.system), item(.version)]])
        ]
    }
}
