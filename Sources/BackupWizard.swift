import AppKit
import SwiftUI

struct BackupPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let library: Library
    let preferences: PreviewPreferences

    func body(content: Content) -> some View {
        content.disabled(isPresented)
            .overlay {
                if isPresented {
                    GeometryReader { geometry in
                        let width: CGFloat = 620
                        let scale = min(1, max(0.1, (geometry.size.width - 24) / width))
                        let height = min(560, max(1, (geometry.size.height - 24) / scale))
                        ZStack {
                            Color(white: 0.93).opacity(0.68).contentShape(Rectangle())
                            BackupWizard(library: library, preferences: preferences, close: { isPresented = false })
                                .frame(width: width, height: height)
                                .scaleEffect(scale)
                                .frame(width: width * scale, height: height * scale)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
    }
}

private struct BackupWizard: View {
    private enum Page: Equatable {
        case introduction, searching, settings, ready(URL), writing, complete(URL)
    }

    let library: Library
    let preferences: PreviewPreferences
    let close: () -> Void
    @State private var page = Page.introduction
    @State private var folder: URL?
    @State private var name = "Music Center"
    @State private var notes = ""
    @State private var size: Int64?
    @State private var choosingFolder = false
    @State private var issue: String?
    @State private var failure: String?
    @State private var stopping = false
    @State private var work: Task<Void, Never>?

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
        VStack(spacing: 0) {
            Text("数据备份")
                .frame(maxWidth: .infinity).frame(height: 48)
                .padding(.horizontal, 42)
                .overlay(alignment: .trailing) {
                    Button(action: cancel) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(white: 0.48)).frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(page == .writing || choosingFolder)
                        .padding(.trailing, 6).accessibilityLabel("关闭数据备份")
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    bodyContent
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 37).padding(.vertical, 12)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                footer
            }.padding(.horizontal, 20).padding(.vertical, 15)
        }
        .font(.system(size: 12)).foregroundStyle(SettingsStyle.ink)
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
        .accessibilityElement(children: .contain).accessibilityLabel("数据备份向导")
        .onExitCommand {
            if failure != nil { dismissFailure() } else { cancel() }
        }
        .onDisappear { work?.cancel() }
    }

    @ViewBuilder private var bodyContent: some View {
        switch page {
        case .introduction:
            Text("将 Music Center 管理的数据备份到所选文件夹。")
            Text("备份内容").fontWeight(.semibold)
            Text("曲库记录、播放列表、播放历史和设置。音频文件继续引用原始位置。")
                .fixedSize(horizontal: false, vertical: true)
            Text("点击「下一步」估算备份大小。")
        case .searching:
            progress("正在估算备份大小…")
        case .settings:
            Text("备份数据大小：约 " + sizeLabel)
            VStack(alignment: .leading, spacing: 5) {
                Text("备份数据保存位置")
                HStack(spacing: 10) {
                    Text(folder?.path ?? "请选择文件夹")
                        .lineLimit(1).truncationMode(.middle).help(folder?.path ?? "请选择文件夹")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                        .frame(height: 27).border(Color(white: 0.63))
                    SettingsAction("浏览…", width: 78, action: chooseFolder).disabled(choosingFolder)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("备份数据名称（最多 32 个字符）")
                TextField("备份数据名称", text: $name).textFieldStyle(.plain)
                    .padding(.horizontal, 6).frame(height: 27).border(Color(white: 0.63))
                    .accessibilityLabel("备份数据名称")
                    .onChange(of: name) { issue = nil }
            }
            if let message = nameIssue ?? issue {
                Text(message).foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("备注")
                TextEditor(text: $notes)
                    .padding(3).frame(height: 80).border(Color(white: 0.63))
                    .accessibilityLabel("备注")
            }
        case let .ready(url):
            Text("已准备备份数据。点击「开始」保存备份。")
            Text("备份数据大小：约 " + sizeLabel)
            Text("备份数据保存地址：\(url.path)")
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        case .writing:
            progress(stopping ? "正在停止备份…" : "正在备份数据…")
            Text("备份期间请保持目标磁盘连接。")
        case let .complete(url):
            Text("备份已完成。")
            Text("备份数据保存地址：\(url.path)")
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    @ViewBuilder private var footer: some View {
        switch page {
        case .introduction:
            primary("下一步", action: estimate)
            SettingsAction("取消", action: cancel)
        case .searching:
            SettingsAction("取消", action: cancel)
        case .settings:
            primary("下一步", enabled: destination != nil && !choosingFolder, action: prepare)
            SettingsAction("取消", action: cancel).disabled(choosingFolder)
        case let .ready(url):
            SettingsAction("后退") { page = .settings }
            primary("开始") { start(url) }
            SettingsAction("取消", action: cancel)
        case .writing:
            SettingsAction("停止", action: cancel).disabled(stopping || work == nil)
        case .complete:
            primary("确定", action: close)
        }
    }

    private var sizeLabel: String {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
    }

    private func progress(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 19) {
            Text(title)
            ProgressView().progressViewStyle(.linear).tint(SettingsStyle.gold)
                .accessibilityLabel(title)
        }
    }

    private func primary(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).foregroundStyle(.white).frame(width: 112, height: 27)
                .background(SettingsStyle.gold.opacity(enabled ? 1 : 0.35)).contentShape(Rectangle())
        }.buttonStyle(.plain).keyboardShortcut(.defaultAction).disabled(!enabled)
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
                    : "无法写入备份目的地。请检查保存位置和剩余空间，或选择其他文件夹。"
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
