import AppKit
import SwiftUI

struct LibraryWizardPresentation<Panel: View>: ViewModifier {
    let isPresented: Bool
    var width: CGFloat = 640
    var preferredHeight: CGFloat = 640
    @ViewBuilder let panel: () -> Panel

    func body(content: Content) -> some View {
        content.disabled(isPresented)
            .overlay {
                if isPresented {
                    GeometryReader { geometry in
                        let scale = min(1, max(0.1, (geometry.size.width - 24) / width))
                        let height = min(preferredHeight, max(1, (geometry.size.height - 24) / scale))
                        ZStack {
                            Color(white: 0.93).opacity(0.68).contentShape(Rectangle())
                            panel()
                                .frame(width: width, height: height)
                                .scaleEffect(scale)
                                .frame(width: width * scale, height: height * scale)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
    }
}

struct LibraryWizardPanel<Contents: View, Controls: View>: View {
    let title: String
    var headerHeight: CGFloat = 60
    var contentInset: CGFloat = 50
    var contentTop: CGFloat = 20
    var contentTrailingInset: CGFloat = 40
    var fontSize: CGFloat = 14
    var closeTrailingInset: CGFloat = 6
    var closeDisabled = false
    let close: () -> Void
    var failure: String? = nil
    var dismissFailure: () -> Void = {}
    @ViewBuilder let contents: () -> Contents
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(spacing: 0) {
            Text(title).frame(maxWidth: .infinity).frame(height: headerHeight).padding(.horizontal, 42)
                .overlay(alignment: .trailing) {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(white: closeDisabled ? 0.83 : 0.48)).frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).keyboardShortcut(.cancelAction).disabled(closeDisabled)
                        .padding(.trailing, closeTrailingInset).accessibilityLabel("关闭" + title)
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 15, content: contents)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, contentInset).padding(.trailing, contentTrailingInset)
                    .padding(.top, contentTop).padding(.bottom, 12)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                controls()
            }.padding(.horizontal, 20).padding(.vertical, 15)
        }
        .font(.system(size: fontSize)).foregroundStyle(SettingsStyle.ink)
        .background(.white).environment(\.colorScheme, .light)
        .disabled(failure != nil)
        .overlay {
            if let failure {
                ZStack {
                    Color.black.opacity(0.001).contentShape(Rectangle())
                    WindowsDialog(title: "Music Center for Mac", message: failure,
                                  width: 360, buttons: [WindowsDialogButton("ok", "确定")],
                                  dismiss: dismissFailure)
                }
            }
        }
        .compositingGroup().shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        .accessibilityElement(children: .contain).accessibilityLabel(title + "向导")
    }
}

struct LibraryWizardPrimary: View {
    let title: String
    var enabled = true
    var isDefault = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).foregroundStyle(.white).frame(width: 120, height: 32)
                .background(SettingsStyle.gold.opacity(enabled ? 1 : 0.35)).contentShape(Rectangle())
        }.buttonStyle(.plain).keyboardShortcut(isDefault ? .defaultAction : nil).disabled(!enabled)
    }
}

struct LibraryWizardSecondary: View {
    let title: String
    var width: CGFloat = 120
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, width: CGFloat = 120, action: @escaping () -> Void) {
        self.title = title
        self.width = width
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).frame(width: width, height: 32)
                .foregroundStyle(enabled ? SettingsStyle.ink : Color(white: 0.58))
                .background(.white)
                .overlay { Rectangle().strokeBorder(enabled ? SettingsStyle.ink : Color(white: 0.65)) }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

struct LibraryWizardProgress: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 35) {
            Text(title)
            ProgressView().progressViewStyle(.linear).tint(SettingsStyle.gold).accessibilityLabel(title)
                .padding(.horizontal, 50)
        }
    }
}

struct BackupWizard: View {
    private enum Page: Equatable {
        case introduction, searching, settings, ready(URL), writing, complete(URL)
    }

    let library: Library
    let preferences: PreviewPreferences
    let close: () -> Void
    @State private var page = Page.introduction
    @State private var folder: URL?
    @State private var name = ""
    @State private var notes = ""
    @State private var size: Int64?
    @State private var choosingFolder = false
    @State private var issue: String?
    @State private var failure: String?
    @State private var stopping = false
    @State private var work: Task<Void, Never>?

    init(library: Library, preferences: PreviewPreferences, close: @escaping () -> Void) {
        self.library = library
        self.preferences = preferences
        self.close = close
    }

    private var baseName: String {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = ".musiccenterbackup"
        return text.lowercased().hasSuffix(suffix) ? String(text.dropLast(suffix.count)) : text
    }

    private var nameIssue: String? {
        if baseName.isEmpty { return "请输入备份名称。" }
        if baseName.count > 32 { return "备份名称最多为 32 个字符。" }
        if baseName == "." || baseName == ".." ||
            baseName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:").union(.controlCharacters)) != nil {
            return "请输入有效的文件名，名称中不能包含斜杠或冒号。"
        }
        return nil
    }

    private var destination: URL? {
        guard nameIssue == nil else { return nil }
        return folder?.appending(component: baseName + ".musiccenterbackup", directoryHint: .notDirectory)
    }

    var body: some View {
        LibraryWizardPanel(title: "数据备份", closeDisabled: page == .writing || choosingFolder,
                           close: cancel, failure: failure, dismissFailure: dismissFailure) {
            bodyContent
        } controls: {
            footer
        }
        .onExitCommand {
            if failure != nil { dismissFailure() } else if page != .writing { cancel() }
        }
        .onDisappear { work?.cancel() }
    }

    @ViewBuilder private var bodyContent: some View {
        switch page {
        case .introduction:
            VStack(alignment: .leading, spacing: 8) {
                Text("Music Center 管理的数据可备份至硬盘上的单独位置，或外接硬盘等便携式媒体。")
                Text("备注：")
                Text("・请勿在备份时移除便携式媒体。\n・如果电脑正在以电池电力运行，建议连接至电源。")
                Text("点击「下一步」，开始搜索备份数据。")
                Text("搜索时间取决于数据量。")
                Text("Mac 备份保存曲库记录和设置，音频继续引用原始位置。")
                    .foregroundStyle(SettingsStyle.heading).padding(.top, 8)
            }.fixedSize(horizontal: false, vertical: true)
        case .searching:
            LibraryWizardProgress(title: "正在搜索备份数据…")
        case .settings:
            VStack(alignment: .leading, spacing: 0) {
                Text("备份数据搜索已完成。\n点击[浏览]指定保存备份数据的硬盘或可移动媒体。")
                    .padding(.bottom, 30)
                Text("备份数据大小：约 " + sizeLabel).padding(.bottom, 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text("备份数据保存地址：")
                    HStack(spacing: 10) {
                        Text(folder?.path ?? "")
                            .lineLimit(1).truncationMode(.middle).help(folder?.path ?? "请选择文件夹")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                            .frame(height: 32).border(Color(white: 0.63))
                        LibraryWizardSecondary("浏览…", width: 80, action: chooseFolder).disabled(choosingFolder)
                    }.frame(width: 494)
                }.padding(.bottom, 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text("备份数据名称（最多32字符）：")
                    TextField("", text: $name).textFieldStyle(.plain)
                        .padding(.horizontal, 6).frame(width: 400, height: 32).border(Color(white: 0.63))
                        .accessibilityLabel("备份数据名称")
                        .onChange(of: name) { issue = nil }
                }
                if let message = issue ?? (name.isEmpty ? nil : nameIssue) {
                    Text(message).foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09)).padding(.top, 5)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("备注：\n备注中可输入任何文本。恢复时可检查该备注。")
                    TextEditor(text: $notes)
                        .padding(3).frame(height: 60).border(Color(white: 0.63))
                        .accessibilityLabel("备注")
                }.padding(.top, 30)
            }
        case let .ready(url):
            VStack(alignment: .leading, spacing: 0) {
                Text("备份数据保存准备已完成。\n点击【开始】，开始写入。").padding(.bottom, 30)
                Text("备份数据大小：约 " + sizeLabel)
                Text("备份数据保存地址：\(url.path)")
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        case .writing:
            LibraryWizardProgress(title: stopping ? "正在停止备份…" : "正在备份数据…")
            Text("备份操作过程中请勿关闭计算机或取出媒体。").padding(.top, 60)
        case let .complete(url):
            VStack(alignment: .leading, spacing: 8) {
                Text("备份已完成。")
                Text("备份数据保存地址：\(url.path)")
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        switch page {
        case .introduction:
            LibraryWizardPrimary(title: "下一步", action: estimate)
            LibraryWizardSecondary("取消", action: cancel)
        case .searching:
            LibraryWizardSecondary("取消", action: cancel)
        case .settings:
            LibraryWizardPrimary(title: "下一步", enabled: destination != nil && !choosingFolder, action: prepare)
            LibraryWizardSecondary("取消", action: cancel).disabled(choosingFolder)
        case let .ready(url):
            LibraryWizardSecondary("后退") { page = .settings }
            LibraryWizardPrimary(title: "开始", isDefault: false) { start(url) }
            LibraryWizardSecondary("取消", action: cancel)
        case .writing:
            LibraryWizardSecondary("停止", action: cancel).disabled(stopping || work == nil)
        case .complete:
            LibraryWizardPrimary(title: "确定", action: close)
        }
    }

    private var sizeLabel: String {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择备份保存位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.directoryURL = folder
        choosingFolder = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            choosingFolder = false
            if response == .OK, let url = panel.url {
                folder = url
                issue = nil
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private func estimate() {
        page = .searching
        work = Task {
            do {
                let estimate = try await library.backupSize(preferences: preferences)
                guard !Task.isCancelled else { return }
                size = estimate
                page = .settings
            } catch {
                guard !Task.isCancelled else { return }
                page = .introduction
                failure = "无法读取备份数据。请检查曲库是否可用，再重试。"
            }
            work = nil
        }
    }

    private func prepare() {
        guard let destination else { return }
        do {
            try library.checkNewBackupDestination(destination)
            issue = nil
            page = .ready(destination)
        } catch {
            issue = error.localizedDescription
        }
    }

    private func start(_ url: URL) {
        guard case .ready = page, work == nil else { return }
        page = .writing
        work = Task {
            defer { work = nil; stopping = false }
            do {
                page = .complete(try await library.writeNewBackup(to: url, notes: notes, preferences: preferences))
            } catch is CancellationError {
                page = .settings
                issue = "备份已停止。"
            } catch {
                failure = FileManager.default.fileExists(atPath: url.path)
                    ? "此处已有同名项目。请更改备份名称或选择其他文件夹。"
                    : "无法写入指定文件夹。无法备份。请指定其他文件夹。"
            }
        }
    }

    private func cancel() {
        guard !choosingFolder, failure == nil else { return }
        if page == .writing {
            guard let work else { return }
            stopping = true
            work.cancel()
        } else {
            work?.cancel()
            close()
        }
    }

    private func dismissFailure() {
        failure = nil
        if page == .writing { page = .settings }
    }
}
