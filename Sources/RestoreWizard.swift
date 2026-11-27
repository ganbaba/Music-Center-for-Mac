import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RestoreWizard: View {
    private enum Page: Equatable {
        case introduction, selection, ready, working, complete(URL)
    }

    let library: Library
    let preferences: PreviewPreferences
    let didRestore: () -> Void
    let close: () -> Void
    @State private var page = Page.introduction
    @State private var source: URL?
    @State private var candidate: RestoreCandidate?
    @State private var choosingFile = false
    @State private var checkingFile = false
    @State private var issue: String?
    @State private var failure: String?
    @State private var inspection: Task<Void, Never>?
    @State private var usesFolder = false
    @State private var destinationFolder: URL?
    @State private var showsHelp = false

    init(library: Library, preferences: PreviewPreferences, didRestore: @escaping () -> Void, close: @escaping () -> Void) {
        self.library = library
        self.preferences = preferences
        self.didRestore = didRestore
        self.close = close
    }

    var body: some View {
        LibraryWizardPanel(title: "恢复备份数据", headerHeight: 60, contentInset: 50, contentTop: 20,
                           fontSize: 14, closeDisabled: page == .working || choosingFile,
                           close: cancel, failure: failure, dismissFailure: dismissFailure) {
            bodyContent
        } controls: {
            footer
        }
        .onExitCommand {
            if failure != nil { dismissFailure() } else { cancel() }
        }
        .onDisappear { inspection?.cancel() }
    }

    @ViewBuilder private var bodyContent: some View {
        switch page {
        case .introduction:
            VStack(alignment: .leading, spacing: 8) {
                Text("恢复已备份的 Music Center 数据到此电脑。")
                Text("备注：")
                Text("・执行恢复操作会将 Music Center 管理的所有数据，恢复到执行备份时的状态。")
                Text("・指定文件夹恢复需要从原始位置读取音频。")
                Button("查看帮助") { showsHelp = true }
                    .buttonStyle(.plain).underline().foregroundStyle(Color(white: 0.48))
                    .popover(isPresented: $showsHelp) {
                        Text("请选择 Music Center for Mac 创建的 .musiccenterbackup 文件。恢复前会自动保存当前曲库和设置。指定文件夹恢复会复制原位置仍可读取的音频。")
                            .font(.system(size: 13)).frame(width: 300).padding(16)
                    }
            }.fixedSize(horizontal: false, vertical: true)
        case .selection:
            selectionContent
        case .ready:
            if let candidate {
                VStack(alignment: .leading, spacing: 0) {
                    Text("已准备恢复备份数据。\n\n点击【开始】，开始恢复。").padding(.bottom, 30)
                    Text("需恢复的备份数据：\(candidate.url.path)")
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text("恢复地址：" + (usesFolder
                        ? (destinationFolder?.appending(path: "Music Center").path ?? "")
                        : "恢复到与备份数据相同的地址"))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        case .working:
            if failure == nil {
                LibraryWizardProgress(title: progressLabel)
                Text("恢复操作过程中请勿关闭计算机或取出媒体。").padding(.top, 60)
            } else {
                Text("恢复未完成。")
            }
        case let .complete(rollback):
            Text("恢复已完成。").help("恢复前备份：\(rollback.path)")
        }
    }

    private var selectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("指定要恢复的备份数据，然后指定备份数据恢复到的位置。")
                .padding(.bottom, 30)
            VStack(alignment: .leading, spacing: 5) {
                Text("需恢复的备份数据：")
                HStack(spacing: 10) {
                    Text(source?.path ?? "")
                        .lineLimit(1).truncationMode(.middle).help(source?.path ?? "请选择备份文件")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                        .frame(height: 32).border(Color(white: 0.63))
                    LibraryWizardSecondary("浏览…", width: 80, action: chooseFile).disabled(choosingFile)
                }.frame(width: 494)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("备份数据信息").padding(.bottom, 14)
                Text("备份日期：" + dateLabel)
                Text("备注：")
                Text(notesLabel)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                    .padding(3).border(Color(white: 0.63))
                    .textSelection(.enabled)
            }.padding(.top, 30)
            VStack(alignment: .leading, spacing: 8) {
                Text("恢复地址：")
                SettingsRadio("恢复到与备份数据相同的地址", selected: !usesFolder) {
                    usesFolder = false
                    issue = nil
                }
                    .help("恢复当前曲库和设置，音频继续使用备份中记录的原始路径。")
                SettingsRadio("恢复到指定文件夹", selected: usesFolder) {
                    usesFolder = true
                    issue = nil
                }
                    .help("将可读取的原音频复制到所选位置的新 Music Center 文件夹，并更新曲库路径。")
                HStack(spacing: 10) {
                    Text(destinationFolder?.path ?? "").lineLimit(1).truncationMode(.middle)
                        .help(destinationFolder?.path ?? "请选择恢复文件夹")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6).frame(height: 32).border(Color(white: 0.63))
                    LibraryWizardSecondary("浏览…", width: 80, action: chooseFolder)
                        .accessibilityLabel("浏览恢复文件夹")
                }.frame(width: 494).disabled(!usesFolder || choosingFile)
            }.padding(.top, 30)
            if checkingFile {
                Text("正在检查备份…").padding(.top, 8)
            }
            if let issue {
                Text(issue).foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09))
            }
        }
    }

    private var dateLabel: String {
        guard let candidate else { return "" }
        guard let date = candidate.createdAt else { return "未记录" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private var notesLabel: String {
        guard let candidate else { return "" }
        return candidate.notes ?? "未记录"
    }

    @ViewBuilder private var footer: some View {
        switch page {
        case .introduction:
            LibraryWizardPrimary(title: "下一步", enabled: !library.restoring) { page = .selection }
            LibraryWizardSecondary("取消", action: cancel)
        case .selection:
            LibraryWizardPrimary(title: "下一步", enabled: candidate != nil && !choosingFile
                                 && (!usesFolder || destinationFolder != nil), action: prepare)
            LibraryWizardSecondary("取消", action: cancel).disabled(choosingFile)
        case .ready:
            LibraryWizardSecondary("后退") { page = .selection }
            LibraryWizardPrimary(title: "开始", isDefault: false, action: start)
            LibraryWizardSecondary("取消", action: cancel)
        case .working:
            LibraryWizardSecondary("停止") {}.disabled(true)
        case let .complete(rollback):
            LibraryWizardPrimary(title: "确定", action: close).help("恢复前备份：\(rollback.path)")
        }
    }

    private var progressLabel: String {
        switch library.restoreProgress {
        case .checking, nil: "正在重新核对备份…"
        case let .copyingAudio(completed, total): "正在复制音频… \(completed)/\(total)"
        case .savingCurrent: "正在保存恢复前备份…"
        case .applying: "正在恢复备份数据…"
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择恢复文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = destinationFolder
        panel.prompt = "选择"
        choosingFile = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            choosingFile = false
            if response == .OK, let url = panel.url {
                destinationFolder = url
                issue = nil
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private func prepare() {
        guard candidate != nil else { return }
        do {
            if usesFolder {
                guard let destinationFolder else { return }
                _ = try library.restoreDestination(in: destinationFolder)
            }
            issue = nil
            page = .ready
        } catch {
            issue = error.localizedDescription
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择曲库备份"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "musiccenterbackup") ?? .data]
        panel.directoryURL = source?.deletingLastPathComponent()
        panel.prompt = "选择"
        choosingFile = true
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            choosingFile = false
            if response == .OK, let url = panel.url { inspect(url) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private func inspect(_ url: URL) {
        inspection?.cancel()
        source = url
        candidate = nil
        issue = nil
        checkingFile = true
        inspection = Task {
            do {
                let result = try await library.inspectBackup(at: url, preferences: preferences)
                guard !Task.isCancelled else { return }
                candidate = result
            } catch {
                guard !Task.isCancelled else { return }
                issue = "无法读取此备份。请选择完整的 Music Center for Mac 备份文件。"
            }
            checkingFile = false
        }
    }

    private func start() {
        guard page == .ready, let candidate, !library.restoring else { return }
        page = .working
        Task {
            do {
                let rollback = try await library.restore(candidate, preferences: preferences,
                                                         audioFolder: usesFolder ? destinationFolder : nil)
                didRestore()
                page = .complete(rollback)
            } catch {
                failure = (error as? RestoreFailure)?.message ?? "无法恢复备份。请检查备份文件和曲库所在磁盘。"
            }
        }
    }

    private func cancel() {
        guard page != .working, !choosingFile else { return }
        inspection?.cancel()
        close()
    }

    private func dismissFailure() {
        failure = nil
        candidate = nil
        issue = "请重新选择备份后重试。"
        page = .selection
    }
}
