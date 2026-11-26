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

    init(library: Library, preferences: PreviewPreferences, didRestore: @escaping () -> Void, close: @escaping () -> Void) {
        self.library = library
        self.preferences = preferences
        self.didRestore = didRestore
        self.close = close
    }

    var body: some View {
        LibraryWizardPanel(title: "恢复备份数据", closeDisabled: page == .working || choosingFile,
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
            Text("将 Mac 版 Music Center 的备份恢复到当前曲库。")
            Text("恢复会替换当前曲库、播放列表、播放历史和设置。开始前会自动备份现有数据。")
                .fixedSize(horizontal: false, vertical: true)
            Text("音频文件仍使用备份中记录的原始路径。")
        case .selection:
            VStack(alignment: .leading, spacing: 5) {
                Text("需要恢复的备份")
                HStack(spacing: 10) {
                    Text(source?.path ?? "请选择 .musiccenterbackup 文件")
                        .lineLimit(1).truncationMode(.middle).help(source?.path ?? "请选择备份文件")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                        .frame(height: 27).border(Color(white: 0.63))
                    SettingsAction("浏览…", width: 78, action: chooseFile).disabled(choosingFile)
                }
            }
            if checkingFile {
                LibraryWizardProgress(title: "正在检查备份…")
            } else if let candidate {
                Text("备份信息").fontWeight(.semibold)
                Text("备份日期：" + (candidate.createdAt?.formatted(date: .numeric, time: .standard) ?? "未记录"))
                Text("曲目：\(candidate.trackCount) 首")
                VStack(alignment: .leading, spacing: 5) {
                    Text("备注")
                    Text(candidate.notes.flatMap { $0.isEmpty ? nil : $0 } ?? (candidate.notes == nil ? "未记录" : "无"))
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                        .padding(7).border(Color(white: 0.63))
                        .textSelection(.enabled)
                }
            } else if let issue {
                Text(issue).foregroundStyle(Color(red: 0.68, green: 0.12, blue: 0.09))
            }
        case .ready:
            if let candidate {
                Text("恢复来源：\(candidate.url.path)")
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text("恢复目标：当前 Mac 曲库")
                Text("点击「开始」后，将覆盖当前曲库、播放列表、播放历史和设置。")
                    .fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
                Text("开始前会自动保存当前曲库和设置。")
            }
        case .working:
            if failure == nil {
                LibraryWizardProgress(title: progressLabel)
                Text("恢复期间请保持备份磁盘连接。")
            } else {
                Text("恢复未完成。")
            }
        case let .complete(rollback):
            Text("恢复已完成。")
            Text("恢复前备份：\(rollback.path)")
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    @ViewBuilder private var footer: some View {
        switch page {
        case .introduction:
            LibraryWizardPrimary(title: "下一步", enabled: !library.restoring) { page = .selection }
            SettingsAction("取消", action: cancel)
        case .selection:
            LibraryWizardPrimary(title: "下一步", enabled: candidate != nil && !choosingFile) { page = .ready }
            SettingsAction("取消", action: cancel).disabled(choosingFile)
        case .ready:
            SettingsAction("后退") { page = .selection }
            LibraryWizardPrimary(title: "开始", isDefault: false, action: start)
            SettingsAction("取消", action: cancel)
        case .working:
            EmptyView()
        case .complete:
            LibraryWizardPrimary(title: "确定", action: close)
        }
    }

    private var progressLabel: String {
        switch library.restoreProgress {
        case .checking, nil: "正在重新核对备份…"
        case .savingCurrent: "正在保存恢复前备份…"
        case .applying: "正在恢复备份数据…"
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
                let rollback = try await library.restore(candidate, preferences: preferences)
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
