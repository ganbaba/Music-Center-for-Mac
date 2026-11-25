import SwiftUI
import UniformTypeIdentifiers

enum LibraryPage: String, CaseIterable {
    case new = "新添加的"
    case unsent = "未传输"
    case songs = "歌曲"
    case albums = "专辑"
    case artists = "艺术家"
    case frequent = "经常播放"
    case recent = "最近播放的"
    case playlists = "播放列表"
    case cd = "CD"

    var symbol: String {
        switch self {
        case .new: "calendar"
        case .unsent: "arrow.right.to.line.compact"
        case .songs: "music.note"
        case .albums, .cd: "opticaldisc"
        case .artists: "person"
        case .frequent, .recent, .playlists: "list.bullet.below.rectangle"
        }
    }

    var isCollection: Bool { self == .new || self == .albums || self == .artists }
    var isHistory: Bool { self == .frequent || self == .recent }
    var hasViewModes: Bool { isCollection || self == .playlists }
}

struct PrototypeView: View {
    @State private var page: LibraryPage
    @State private var showsDevice: Bool
    @Binding private var sampleLibrary: Bool
    @Binding private var sampleDevice: Bool
    @State private var showsManagement = false
    @State private var walkmanRoots: [URL] = []
    @State private var walkmans: [WalkmanVolume] = []
    @State private var isOpeningWalkman = false
    @State private var walkmanRefreshID = UUID()
    @State private var selectedVolume: WalkmanVolume.Identity?
    @State private var transferRequest: WalkmanPreviewRequest?
    @State private var managedDevice: WalkmanVolume?
    @State private var trackSelection: Set<UUID> = []
    @State private var properties: PropertiesRequest?
    @State private var localRows: [CapturedTrack] = []
    @State private var showsImporter = false
    @State private var exportRequest: AudioExportRequest?
    @State private var albumLookup: AlbumLookupRequest?
    @State private var audioDisc: AudioDisc?
    @State private var cdDrives: [AudioCDDrive] = []
    @State private var mountedDiscs: [AudioDisc] = []
    @State private var discInsertionAction: CDInsertionBehavior = .none
    @State private var discTracks: [Track] = []
    @State private var audioPanel: AudioPanel?
    @Binding private var dsee: Bool
    @Binding private var equalizer: EqualizerSettings
    @State private var classificationMessage: String?
    @State private var missingTrackIDs: Set<UUID> = []
    @State private var checkingMissingFiles = false
    @State private var collectionDetailKey: AlbumKey?
    @State private var notice: String?
    @State private var playlistDraftTracks: [Track] = []
    @State private var playlistDetailID: UUID?
    @State private var pendingRestore: URL?
    @State private var pendingPlaylistDeletion: Playlist?
    @State private var pendingTrackDeletion: Set<UUID> = []
    @State private var playlistsShowGrid = true
    @State private var seekPreview: Double?
    @Binding private var importer: LibraryImport?
    private let library: Library
    private let player: Player
    @State private var showsMenu = false
    @State private var settingsPage: SettingsPage?
    @Binding private var settings: PreviewSettings
    private let preferences: PreviewPreferences
    @State private var showsPlaylistPrompt = false
    @State private var playlistName = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var playlistNameFocused: Bool
    @State private var search = ""
    @State private var showsGrid = true

    private var display: DisplaySettings { settings.display }
    private var canvas: Color { display.appearance.canvas }
    private var surface: Color { display.appearance.surface }
    private var selected: Color { display.appearance.selected }
    private let gold = Color(red: 0.70, green: 0.57, blue: 0.29)
    private var ink: Color { Color(white: display.appearance.dark ? 1 : 0.08) }
    private var muted: Color { Color(white: display.appearance.dark ? 0.72 : 0.48) }
    private var textScale: CGFloat { display.textSize.scale }
    private let defaultPlaylistName = "我的播放列表"
    private var canSelectTracks: Bool { !showsManagement && !capturedTracks.isEmpty }
    private var canClearTrackSelection: Bool { !showsManagement && !selectedTracks.isEmpty }
    private var menuIsBlocked: Bool {
        settingsPage != nil || audioPanel == .equalizer || transferRequest != nil || exportRequest != nil
            || showsImporter || showsPlaylistPrompt || properties != nil || pendingPlaylistDeletion != nil
            || !pendingTrackDeletion.isEmpty || pendingRestore != nil || notice != nil || classificationMessage != nil
            || library.error != nil || player.error != nil || preferences.error != nil
    }

    private var canPlay: Bool { player.hasQueue || capturedTracks.contains { $0.localTrack != nil } }

    init(page: LibraryPage = .songs, showsDevice: Bool = false,
         sampleLibrary: Binding<Bool>, sampleDevice: Binding<Bool>,
         library: Library, player: Player, importer: Binding<LibraryImport?>, preferences: PreviewPreferences) {
        _page = State(initialValue: page)
        _showsDevice = State(initialValue: showsDevice)
        _sampleLibrary = sampleLibrary
        _sampleDevice = sampleDevice
        self.library = library
        self.player = player
        _importer = importer
        self.preferences = preferences
        _settings = Binding(get: { preferences.settings }, set: { preferences.settings = $0 })
        _equalizer = Binding(get: { preferences.equalizer }, set: { preferences.equalizer = $0 })
        _dsee = Binding(get: { preferences.dsee }, set: { preferences.dsee = $0 })
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                sidebar
                if let managedDevice {
                    let connectedDevice = walkmans.first {
                        $0.id == managedDevice.id || (managedDevice.id.uuid != nil && $0.id.uuid == managedDevice.id.uuid)
                    }
                    WalkmanManagement(volume: connectedDevice ?? managedDevice, connected: connectedDevice != nil,
                                      close: { self.managedDevice = nil },
                                      reconnect: walkmanRoots.isEmpty ? nil : {
                        Task { await refreshWalkmans() }
                    },
                                      importTracks: { tracks, directory in
                        do {
                            transferRequest = try WalkmanPreviewRequest.returning(tracks, from: connectedDevice ?? managedDevice, to: directory)
                        } catch { notice = error.localizedDescription }
                    })
                } else if showsManagement && sampleDevice {
                    management
                } else {
                    content
                    if showsDevice {
                        devicePane
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .font(.system(size: 14 * textScale))
        .foregroundStyle(ink)
        .background(canvas)
        .environment(\.colorScheme, display.appearance.dark ? .dark : .light)
        .blur(radius: settingsPage == nil && properties == nil && audioPanel != .equalizer && !showsPlaylistPrompt ? 0 : 3)
        .overlay {
            if let panel = audioPanel, panel != .equalizer {
                GeometryReader { geometry in
                    ZStack(alignment: .topTrailing) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { audioPanel = nil }
                            .padding(.top, 72)
                        AudioPopover(panel: panel, player: player, dsee: $dsee, gold: gold, selectedOutput: settings.outputDeviceUID,
                                     queueHeight: geometry.size.height - 94,
                                     selectOutput: selectOutput, createPlaylist: {
                            audioPanel = nil
                            openPlaylistPrompt(tracks: player.queue)
                        })
                        .environment(\.colorScheme, .light)
                        .padding(.top, panel == .dsee || panel == .volume ? 80 : 75)
                        .padding(.trailing, audioPanelInset(panel))
                    }
                }
            }
        }
        .overlay {
            if audioPanel == .equalizer {
                GeometryReader { geometry in
                    let scale = min(1, (geometry.size.width - 24) / 660, (geometry.size.height - 24) / 408)
                    ZStack {
                        Color(white: 0.93).opacity(0.68)
                        EqualizerPanel(settings: $equalizer, close: { audioPanel = nil })
                            .scaleEffect(scale)
                            .frame(width: 660 * scale, height: 408 * scale)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background {
            Group {
                shortcut(.newPlaylist, "n", modifiers: .command)
                shortcut(.newPlaylist, "n", modifiers: .control)
                shortcut(.importFiles, "o", modifiers: .control)
                shortcut(.selectAll, "a", modifiers: .control, enabled: canSelectTracks && !searchFocused)
                shortcut(.deselectAll, "a", modifiers: [.control, .shift], enabled: canClearTrackSelection && !searchFocused)
                shortcut(.eject, "e", modifiers: .control, enabled: audioDisc != nil)
                shortcut(.lookupCD, "i", modifiers: .control, enabled: !discTracks.isEmpty)
                shortcut(.support, KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey)!)))
                shortcut(.quit, KeyEquivalent(Character(UnicodeScalar(NSF4FunctionKey)!)), modifiers: .option)
                shortcut(.selectAll, "a", modifiers: .command, enabled: canSelectTracks && !searchFocused)
                shortcut(.deselectAll, "a", modifiers: [.command, .shift], enabled: canClearTrackSelection && !searchFocused)
                shortcut(.refresh, KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)))
                shortcut(.playPause, KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!)), enabled: canPlay)
                shortcut(.stop, KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!)), enabled: player.current != nil)
                shortcut(.mute, KeyEquivalent(Character(UnicodeScalar(NSF8FunctionKey)!)))
                shortcut(.volumeDown, KeyEquivalent(Character(UnicodeScalar(NSF9FunctionKey)!)))
                shortcut(.volumeUp, KeyEquivalent(Character(UnicodeScalar(NSF10FunctionKey)!)))
                shortcut(.previous, .leftArrow, modifiers: .control, enabled: player.canGoPrevious)
                shortcut(.next, .rightArrow, modifiers: .control, enabled: player.canGoNext)
            }
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            .disabled(menuIsBlocked)
        }
        .onExitCommand { audioPanel = nil; showsMenu = false }
        .windowsAlert(isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }), message: notice ?? "")
        .windowsAlert(isPresented: Binding(get: { classificationMessage != nil }, set: { if !$0 { classificationMessage = nil } }),
            message: classificationMessage ?? "", buttons: [WindowsDialogButton("close", "关闭(C)")], defaultButton: "close", cancelButton: "close")
        .overlay {
            if let settingsPage {
                GeometryReader { geometry in
                    let scale = min(1, (geometry.size.width - 24) / 710)
                    let panelHeight = min(690, (geometry.size.height - 24) / scale)
                    ZStack {
                        Color(white: 0.93).opacity(0.68)
                        SettingsPreview(page: settingsPage, settings: settings, height: panelHeight,
                                        cdDrives: cdDrives, refreshCDDrives: { refreshAudioDisc() }) { updated in
                            do {
                                if updated.outputDeviceUID != settings.outputDeviceUID || updated.outputSampleRate != settings.outputSampleRate {
                                    try player.selectOutput(updated.outputDeviceUID, renderingRate: updated.outputSampleRate)
                                }
                                settings = updated
                                refreshAudioDisc()
                                self.settingsPage = nil
                            } catch {
                                notice = "无法切换音频输出。\(error.localizedDescription)"
                            }
                        } cancel: {
                            self.settingsPage = nil
                        }
                        .scaleEffect(scale)
                        .frame(width: 710 * scale, height: panelHeight * scale)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .environment(\.colorScheme, .light)
            }
        }
        .overlay {
            if let properties {
                GeometryReader { geometry in
                    let scale = min(1, (geometry.size.width - 24) / 640)
                    let height = min(690, (geometry.size.height - 24) / scale)
                    ZStack {
                        Color(white: 0.93).opacity(0.68)
                        PropertiesPanel(request: properties, records: library.propertyRecords, history: library.playbackHistory,
                            choices: propertyChoices, equalizerNames: (EqualizerSettings.builtIns + equalizer.custom).map(\.name),
                            height: height, save: { changes in
                                try library.saveProperties(changes)
                                player.refreshMetadata(library.tracks)
                            }, close: { self.properties = nil })
                            .scaleEffect(scale).frame(width: 640 * scale, height: height * scale)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .environment(\.colorScheme, .light)
            }
        }
        .task { [library, player] in
            player.setInitialAudio(outputUID: settings.outputDeviceUID, equalizer: equalizer, renderingRate: settings.outputSampleRate)
            player.onPlaybackStarted = { [weak library] track in library?.recordPlayback(of: track) }
            while !Task.isCancelled {
                player.refreshOutputs()
                do { try await Task.sleep(for: .seconds(2)) }
                catch { break }
            }
        }
        .task { refreshMountedMedia() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            refreshMountedMedia(onMount: true)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            refreshMountedMedia()
        }
        .sheet(item: $albumLookup) { request in
            AlbumLookupPanel(request: request, close: { albumLookup = nil }) { tracks in
                if request.disc == audioDisc { discTracks = tracks }
                else { notice = "音频 CD 已移除。" }
                albumLookup = nil
            }
        }
        .sheet(item: $exportRequest) { request in
            AudioExportPanel(request: request, finish: { files, complete in
                if request.importsToLibrary {
                    library.registerCopiedAudio(files)
                    if complete, request.ejectAfterImport, let disc = request.disc { ejectAudioDisc(disc) }
                }
            }, close: { exportRequest = nil })
        }
        .sheet(item: $transferRequest) { request in
            WalkmanPreviewSheet(request: request, volume: walkmans.first {
                $0.id == request.device || (request.device.uuid != nil && $0.id.uuid == request.device.uuid)
            },
                                close: { transferRequest = nil }, didTransfer: { outcome in
                Task {
                    await refreshWalkmans()
                    if request.importsToLibrary { await library.importItems(outcome.transferredURLs) }
                }
            })
        }
        .onChange(of: equalizer) { player.setEqualizer(equalizer) }
        .onChange(of: sampleDevice) {
            if !sampleDevice {
                showsManagement = false
                if page == .unsent { page = .songs }
            }
        }
        .onChange(of: sampleLibrary) { trackSelection = [] }
        .onChange(of: library.tracks, initial: true) { _, tracks in
            localRows = tracks.map(CapturedTrack.init)
        }
        .onChange(of: importer) {
            guard importer != nil else { return }
            guard !menuIsBlocked, !library.importing else {
                if !showsImporter { importer = nil }
                return
            }
            showsMenu = false
            showsImporter = true
        }
    }

    var body: some View {
        workspace
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: (importer ?? .files).contentTypes,
                      allowsMultipleSelection: importer == .files, onCompletion: finishImport) {
            importer = nil
        }
        .windowsAlert(isPresented: Binding(
            get: { library.error != nil || player.error != nil || preferences.error != nil },
            set: { if !$0 { library.error = nil; player.error = nil; preferences.error = nil } }
        ), message: library.error ?? player.error ?? preferences.error ?? "", symbol: .error)
        .windowsAlert(isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            message: "用「\(pendingRestore?.lastPathComponent ?? "")」中的曲库、播放历史和设置替换当前数据。恢复前会保存一份当前备份。",
            symbol: .warning, width: 392, buttons: [WindowsDialogButton("yes", "恢复") {
                guard let url = pendingRestore else { return }
                do {
                    let previous = try library.restore(from: url, preferences: preferences)
                    player.clearQueue()
                    player.setInitialAudio(outputUID: settings.outputDeviceUID, equalizer: equalizer, renderingRate: settings.outputSampleRate)
                    refreshAudioDisc(); sampleLibrary = false; selectPage(.songs)
                    notice = "已恢复曲库和设置。恢复前的备份位于「\(previous.path)」。"
                } catch { notice = "无法恢复备份。\(error.localizedDescription)" }
            }, WindowsDialogButton("no", "取消")], defaultButton: "no", cancelButton: "no")
        .windowsAlert(isPresented: Binding(get: { !pendingTrackDeletion.isEmpty }, set: { if !$0 { pendingTrackDeletion = [] } }),
            message: "将从我的音乐库删除所选项目。\n\(pendingTrackDeletion.count)歌曲", symbol: .warning, width: 392,
            buttons: [WindowsDialogButton("yes", "是") {
                if library.removeFromLibrary(pendingTrackDeletion) { trackSelection.subtract(pendingTrackDeletion) }
            }, WindowsDialogButton("no", "否")], defaultButton: "no", cancelButton: "no",
            option: WindowsDialogOption(title: "同时删除计算机中的文件", help: "本轮仅从曲库移除，原音频文件保留。"))
        .windowsAlert(isPresented: Binding(get: { pendingPlaylistDeletion != nil }, set: { if !$0 { pendingPlaylistDeletion = nil } }),
            message: "删除所选项目。", symbol: .warning, width: 356,
            buttons: [WindowsDialogButton("yes", "是") {
                guard let playlist = pendingPlaylistDeletion else { return }
                if library.deletePlaylist(playlist.id), playlistDetailID == playlist.id { openPlaylist(nil) }
            }, WindowsDialogButton("no", "否")], defaultButton: "no", cancelButton: "no")
        .overlay {
            if showsPlaylistPrompt {
                ZStack {
                    Color(white: 0.93).opacity(0.68)
                    playlistPrompt
                }
                .environment(\.colorScheme, .light)
            }
        }
        .modifier(WindowsMenuHost(isPresented: $showsMenu, resetID: "\(page.rawValue)-\(menuIsBlocked)-\(sampleLibrary)"))
    }

    private func openPlaylistPrompt(tracks: [Track] = []) {
        searchFocused = false
        playlistDraftTracks = tracks
        playlistName = ""
        showsPlaylistPrompt = true
    }

    private var playlistPrompt: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("新建播放列表")
                .frame(maxWidth: .infinity)
                .frame(height: 45)
                .overlay(alignment: .trailing) {
                    Button { showsPlaylistPrompt = false } label: {
                        Image(systemName: "xmark").frame(width: 38, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
            Text("输入播放列表名称")
                .padding(.bottom, 20)
                .padding(.horizontal, 30)
            TextField(defaultPlaylistName, text: $playlistName)
                .textFieldStyle(.plain)
                .focused($playlistNameFocused)
                .padding(.horizontal, 6)
                .frame(height: 25)
                .border(gold)
                .accessibilityLabel("播放列表名称")
                .padding(.horizontal, 30)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Spacer()
                Button { showsPlaylistPrompt = false } label: {
                    Text("取消").frame(width: 96, height: 27).border(Color(white: 0.12))
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    let enteredName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = enteredName.isEmpty ? defaultPlaylistName : enteredName
                    _ = library.createPlaylist(name, tracks: playlistDraftTracks)
                    showsPlaylistPrompt = false
                } label: {
                    Text("创建").foregroundStyle(.white)
                        .frame(width: 96, height: 27).background(gold)
                }
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.bottom, 14)
        }
        .font(.system(size: 12))
        .foregroundStyle(Color(white: 0.10))
        .frame(width: 446, height: 208)
        .background(.white)
        .shadow(color: .black.opacity(0.45), radius: 7, y: 2)
        .task { playlistNameFocused = true }
    }

    private var header: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Text("Music Center for PC")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                HStack(spacing: 0) {
                    ZStack {
                        Circle().fill(.linearGradient(colors: [.yellow.opacity(0.70), gold], startPoint: .top, endPoint: .bottom))
                        Image(systemName: "music.note").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(width: 18, height: 18)
                    .padding(.horizontal, 7)
                    WindowsMenuButton(title: "主菜单", width: 77, point: CGPoint(x: 11, y: 16),
                        willOpen: { audioPanel = nil }, entries: { mainMenuEntries }) {
                        Image(systemName: "line.3.horizontal").frame(width: 32, height: 32)
                    }.help("菜单")
                }
            }
            .frame(height: 32)

            ZStack(alignment: .bottomTrailing) {
                HStack(spacing: 0) {
                    Button(action: player.toggleShuffle) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(player.isShuffled ? gold : muted)
                            .frame(width: 40, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("随机播放")
                    .accessibilityValue(player.isShuffled ? "开" : "关")
                    .help("随机播放：\(player.isShuffled ? "开" : "关")")
                    playbackButton("backward.end.fill", "上一首", enabled: player.canGoPrevious, action: player.previous)
                    playbackButton(player.isPlaying ? "pause.fill" : "play.fill", player.isPlaying ? "暂停" : "播放",
                                   enabled: canPlay, action: togglePlayback)
                    playbackButton("forward.end.fill", "下一首", enabled: player.canGoNext, action: player.next)
                    Button { player.repeatMode = player.repeatMode.next } label: {
                        Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(player.repeatMode == .off ? muted : gold)
                            .frame(width: 40, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重复播放")
                    .accessibilityValue(player.repeatMode.rawValue)
                    .help("重复播放：\(player.repeatMode.rawValue)")
                    if let track = player.current {
                        HStack(spacing: 8) {
                            CapturedCover(artwork: track.artwork).frame(width: 24, height: 24)
                            Text([track.title, track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " / "))
                                .lineLimit(1)
                                .font(.system(size: 13))
                        }
                        .padding(.leading, 8)
                    } else if library.importing || library.message != nil {
                        Text(library.importing ? "正在导入…" : library.message ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 10)
                    Button { toggleAudioPanel(.dsee) } label: {
                        Text("DSEE HX").font(.system(size: 10, weight: .bold))
                            .frame(width: 57, height: 28)
                            .background(audioPanel == .dsee ? selected : .clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(dsee ? "开" : "关")
                    .help("将有损压缩和 CD 品质的音频升级至等同于高解析度音频。音效界面预览。")
                    audioButton(.equalizer)
                    audioButton(.output)
                    audioButton(.queue)
                    audioButton(.volume)
                }
                .frame(height: 28)
                .frame(maxHeight: .infinity, alignment: .top)
                HStack(spacing: 8) {
                    if player.duration > 0 {
                        seekControl
                    }
                    Text("\(previewTime(seekPreview ?? player.elapsed))/\(previewTime(player.duration))")
                        .font(.system(size: 9))
                        .monospacedDigit()
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 205)
                .padding(.trailing, 18)
                .padding(.bottom, 2)
            }
            .frame(height: 40)
        }
    }

    private var seekControl: some View {
        GeometryReader { geometry in
            let fraction = min(1, max(0, (seekPreview ?? player.elapsed) / player.duration))
            let position = geometry.size.width * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.85)).frame(height: 2)
                Capsule().fill(gold).frame(width: position, height: 2)
                Circle().fill(gold).frame(width: 7, height: 7)
                    .offset(x: min(max(0, position - 3.5), max(0, geometry.size.width - 7)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { seekPreview = seekTime(at: $0.location.x, width: geometry.size.width) }
                .onEnded {
                    player.seek(seekTime(at: $0.location.x, width: geometry.size.width))
                    seekPreview = nil
                }
            )
        }
        .frame(height: 13)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue(previewTime(seekPreview ?? player.elapsed))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.seek(player.elapsed + 5)
            case .decrement: player.seek(player.elapsed - 5)
            @unknown default: break
            }
        }
    }

    private func seekTime(at x: CGFloat, width: CGFloat) -> Double {
        width > 0 ? Double(min(1, max(0, x / width))) * player.duration : 0
    }

    private func playbackButton(_ name: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { playbackSymbol(name, label, inactive: !enabled) }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(label)
    }

    private func togglePlayback() {
        if player.hasQueue {
            player.toggle()
        } else {
            let order = capturedTracks
            guard let first = order.first(where: { trackSelection.contains($0.id) }) ?? order.first else { return }
            play(order, from: first)
        }
    }

    private func play(_ order: [CapturedTrack], from first: CapturedTrack) {
        guard first.localTrack != nil else { return }
        var rows = order
        if page.isCollection {
            let groups = TrackCollection.group(capturedTracks, by: page, groupArtistsByTrack: display.groupArtistsByTrack)
            if let group = groups.firstIndex(where: { $0.tracks.contains { $0.id == first.id } }) {
                let groupIDs = Set(groups[group].tracks.map(\.id))
                rows = rows.filter { groupIDs.contains($0.id) }
                if settings.playsAcrossLists {
                    rows += groups.dropFirst(group + 1).flatMap(\.tracks)
                }
            }
        }
        player.play(playableItems(rows), from: first.id)
    }

    private func enqueue(_ rows: [CapturedTrack], placement: Player.QueuePlacement) {
        player.enqueue(playableItems(rows), placement: placement)
    }

    private func playableItems(_ rows: [CapturedTrack]) -> [Player.Item] {
        rows.compactMap { row in
            row.localTrack.map { Player.Item(track: $0, playlistEntryID: row.playlistEntryID) }
        }
    }

    private func finishImport(_ result: Result<[URL], Error>) {
        let kind = importer
        importer = nil
        switch result {
        case .success(let urls):
            Task {
                if kind == .playlist {
                    if let url = urls.first, await library.importPlaylist(url) {
                        notice = "导入完成。"
                    }
                    return
                }
                await library.importItems(urls)
                if library.error == nil, !library.tracks.isEmpty {
                    sampleLibrary = false
                    selectPage(.songs)
                }
            }
        case .failure(let error): library.error = error.localizedDescription
        }
    }

    private func requestImport(_ kind: LibraryImport) {
        guard !library.importing, !menuIsBlocked else { return }
        showsMenu = false
        importer = kind
    }

    private func playbackSymbol(_ name: String, _ label: String, inactive: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(inactive ? muted : ink)
            .frame(width: 40)
            .accessibilityLabel(label)
            .help(label)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("传输和管理")
                Button {
                    if showsManagement {
                        showsManagement = false
                        showsDevice = true
                    } else {
                        showsDevice.toggle()
                        if !showsDevice && page == .unsent { selectPage(.songs) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.to.line.compact")
                            .frame(width: 17)
                        Text(sampleDevice ? "NW-\nWM1Z/WM1A" : activeWalkman?.name ?? "传输到设备")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Image(systemName: showsDevice ? "chevron.left" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(gold, in: Circle())
                    }
                    .foregroundStyle(showsDevice ? gold : ink)
                    .padding(.horizontal, 13)
                    .frame(height: (sampleDevice || activeWalkman != nil ? 48 : 32) * textScale)
                    .background(showsDevice ? selected : canvas)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                sectionTitle("我的音乐库")
                ForEach(LibraryPage.allCases.filter { $0 != .cd && ($0 != .unsent || (sampleDevice && showsDevice && !showsManagement)) }, id: \.self) { libraryRow($0) }
                sectionTitle("导入")
                libraryRow(.cd)
            }
        }
        .scrollIndicators(.never)
        .frame(width: 200 * textScale)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11 * textScale))
            .foregroundStyle(muted)
            .padding(.leading, 19)
            .padding(.top, 13)
            .padding(.bottom, 4)
    }

    private func libraryRow(_ item: LibraryPage) -> some View {
        Button { selectPage(item) } label: {
            HStack(spacing: 7) {
                Image(systemName: item.symbol)
                    .frame(width: 17)
                Text(item.rawValue).fontWeight(page == item && !showsManagement ? .bold : .regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .frame(height: 32 * textScale)
            .background(page == item && !showsManagement ? selected : canvas)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectPage(_ item: LibraryPage) {
        withAnimation(display.visualEffects ? .easeInOut(duration: 0.15) : nil) {
            page = item
            playlistDetailID = nil
            collectionDetailKey = nil
            showsMenu = false
            showsManagement = false
            managedDevice = nil
            search = ""
            trackSelection = []
        }
    }

    private var collectionDetail: TrackCollection? {
        guard page.isCollection, let key = collectionDetailKey else { return nil }
        return TrackCollection.group(sampleLibrary ? CapturedLibrary.tracks : localRows, by: page,
            groupArtistsByTrack: display.groupArtistsByTrack).first { $0.id == key }
    }

    private var capturedTracks: [CapturedTrack] {
        if let group = collectionDetail { return group.tracks.filter { $0.matches(search) } }
        if page == .playlists, let playlistDetail {
            return playlistDetail.tracks.filter { $0.matches(search) }
        }
        if page.isHistory {
            return historyRows.enumerated().map { $0.element.numbered(at: $0.offset + 1) }
                .filter { $0.matches(search) }
        }
        guard page == .songs || page.isCollection else { return [] }
        let rows = sampleLibrary ? CapturedLibrary.tracks : localRows
        return rows.filter { row in
            (page != .new || sampleLibrary || row.localTrack?.registeredAt != nil) && row.matches(search)
        }
    }

    private var historyRows: [CapturedTrack] {
        if sampleLibrary {
            let tracks = CapturedLibrary.tracks
            return page == .recent ? tracks : [tracks[1], tracks[2], tracks[0], tracks[3]]
        }
        return localRows.compactMap { row in
            library.playbackHistory[row.id].map { (row, $0) }
        }.sorted {
            if page == .frequent, $0.1.count != $1.1.count {
                return $0.1.count > $1.1.count
            }
            return $0.1.lastPlayedAt > $1.1.lastPlayedAt
        }.map { $0.0 }
    }

    private var content: some View {
        GeometryReader { geometry in
            let reserved = showsDevice ? 78.0 : 0
            let bodyWidth = geometry.size.width - reserved
            ZStack(alignment: .topLeading) {
                surface
                if page == .cd, let audioDisc {
                    AudioDiscPanel(disc: audioDisc, tracks: discTracks,
                                   play: { track in player.play(discTracks.map { Player.Item(track: $0) }, from: track.id) },
                                   copy: chooseDiscExport, lookup: showDiscLookup, eject: ejectAudioDisc)
                        .task(id: audioDisc) { await loadAudioDisc(audioDisc) }
                        .id(audioDisc.root)
                        .frame(width: bodyWidth, height: geometry.size.height)
                } else if let detail = collectionDetail {
                    collectionDetailView(detail).frame(width: bodyWidth, height: geometry.size.height, alignment: .topLeading)
                } else if page == .playlists, let detail = playlistDetail {
                    playlistDetailView(detail)
                        .frame(width: bodyWidth, height: geometry.size.height, alignment: .topLeading)
                } else if page == .playlists && !filteredPlaylists.isEmpty {
                    playlistOverview
                        .frame(width: bodyWidth, height: geometry.size.height, alignment: .topLeading)
                } else if !capturedTracks.isEmpty {
                    Group {
                        if page.isHistory { historyContent } else { populatedContent }
                    }
                    .frame(width: bodyWidth, height: geometry.size.height, alignment: .topLeading)
                } else {
                    emptyContent
                        .position(x: bodyWidth / 2, y: geometry.size.height * 0.55)
                }
                if page != .cd {
                    filters
                        .frame(width: bodyWidth, height: 45, alignment: .trailing)
                }
                if showsDevice {
                    transferStatus
                        .position(x: geometry.size.width - 39, y: geometry.size.height / 2 + 8)
                }
            }
        }
    }

    private var historyContent: some View {
        let tracks = capturedTracks
        let artwork = tracks.lazy.compactMap { $0.localTrack?.artwork }.first
        let duration = previewTime(tracks.reduce(0) { $0 + $1.seconds })
        let size = tracks.reduce(0) { $0 + $1.sizeMB }.formatted(.number.precision(.fractionLength(0...1)))
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 30) {
                CapturedCover(artwork: artwork, reference: sampleLibrary)
                    .frame(width: 154, height: 169)
                VStack(alignment: .leading, spacing: 6) {
                    Text(page.rawValue).font(.system(size: 30 * textScale))
                    Text("\(tracks.count)歌曲, \(duration), \(size)MB")
                        .font(.system(size: 11)).foregroundStyle(muted)
                }
            }
            trackTable(tracks, columns: ["#"] + settings.columns)
                .id(page)
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .padding(.top, 48)
    }

    private var populatedContent: some View {
        let collection: LibraryPage? = page.isCollection ? page : nil
        let tracks = capturedTracks
        let subtitle = collection.map {
            "\(TrackCollection.group(tracks, by: $0, groupArtistsByTrack: display.groupArtistsByTrack).count)\($0 == .artists ? "艺术家" : "专辑")"
        } ?? "\(tracks.count)歌曲"
        let columns = page == .artists ? ["艺术家", "歌曲长度", "文件大小"]
            : (collection != nil ? ["#"] : []) + settings.columns
        return VStack(alignment: .leading, spacing: 0) {
            Text(page.rawValue)
                .font(.system(size: 41 * textScale, weight: .bold))
                .frame(height: 50 * textScale, alignment: .topLeading)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(muted)
            trackTable(tracks, columns: columns, collection: collection)
                .id(page)
                .padding(.top, 20)
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .padding(.top, 50)
    }

    private var filters: some View {
        HStack(spacing: 0) {
            if page.hasViewModes && playlistDetail == nil && collectionDetail == nil {
                viewModeButton("square.grid.2x2.fill", grid: true)
                viewModeButton("line.3.horizontal", grid: false)
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(muted)
                TextField("过滤器搜索", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: 234)
            .frame(height: 26)
            .background(Capsule().strokeBorder(Color(white: 0.60), lineWidth: 1))
            .padding(.leading, page.hasViewModes ? 8 : 0)
        }
        .padding(.trailing, 17)
    }

    private func viewModeButton(_ symbol: String, grid: Bool) -> some View {
        let currentGrid = page == .playlists ? playlistsShowGrid : showsGrid
        return Button {
            if page == .playlists { playlistsShowGrid = grid } else { showsGrid = grid }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 40, height: 39)
                .overlay(alignment: .bottom) {
                    if currentGrid == grid {
                        Rectangle().fill(gold).frame(height: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(grid ? "网格视图" : "列表视图")
        .help(grid ? "网格视图" : "列表视图")
    }

    private var filteredPlaylists: [Playlist] {
        library.playlists.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var playlistDetail: PlaylistGroup? {
        guard page == .playlists, let playlistDetailID,
              let playlist = library.playlists.first(where: { $0.id == playlistDetailID }) else { return nil }
        return playlistGroup(playlist, rowsByID: Dictionary(uniqueKeysWithValues: localRows.map { ($0.id, $0) }))
    }

    private func playlistGroup(_ playlist: Playlist, rowsByID: [UUID: CapturedTrack]) -> PlaylistGroup {
        let entries = library.playlistEntries[playlist.id] ?? []
        let tracks = entries.enumerated().compactMap { index, entry in
            rowsByID[entry.trackID]?.inPlaylist(entryID: entry.id, position: index + 1)
        }
        return PlaylistGroup(playlist: playlist, tracks: tracks, propertyRecord: library.propertyRecords[.playlist(playlist.id)])
    }

    private func openPlaylist(_ id: UUID?) {
        searchFocused = false
        search = ""
        trackSelection = []
        playlistDetailID = id
    }

    private func playPlaylist(_ group: PlaylistGroup) {
        if let first = group.tracks.first { play(group.tracks, from: first) }
    }

    private var playlistOverview: some View {
        let rowsByID = Dictionary(uniqueKeysWithValues: localRows.map { ($0.id, $0) })
        let groups = filteredPlaylists.map { playlistGroup($0, rowsByID: rowsByID) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 20) {
                Text("播放列表").font(.system(size: 41 * textScale, weight: .bold))
                newPlaylistButton
            }
            Text("播放列表").font(.system(size: 11)).foregroundStyle(muted)
            trackTable([], columns: ["#"] + settings.columns, playlistGroups: groups)
                .padding(.top, 20)
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .padding(.top, 50)
    }

    private func playlistDetailView(_ group: PlaylistGroup) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { openPlaylist(nil) } label: {
                Image(systemName: "chevron.left").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回播放列表")
            HStack(alignment: .top, spacing: 22) {
                PlaylistCover(group: group).frame(width: 158, height: 169)
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name).font(.system(size: 30 * textScale)).lineLimit(1)
                    Text(group.summary).font(.system(size: 11)).foregroundStyle(muted)
                    Spacer()
                    HStack(spacing: 10) {
                        Button { playPlaylist(group) } label: {
                            Label("播放", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(group.tracks.isEmpty)
                        WindowsMenuButton(title: "播放列表更多操作", width: 184, entries: { playlistDetailMenu(group) }) {
                            Image(systemName: "ellipsis").frame(width: 25, height: 24)
                        }
                    }
                }
                .frame(height: 169)
            }
            trackTable(group.tracks.filter { $0.matches(search) }, columns: ["#"] + settings.columns, playlistID: group.id)
                .id(group.id)
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .padding(.top, 8)
    }

    private func trackTable(_ tracks: [CapturedTrack], columns: [String], collection: LibraryPage? = nil,
                            playlistGroups: [PlaylistGroup]? = nil, playlistID: UUID? = nil) -> some View {
        CapturedTable(tracks: tracks, columns: columns, collection: collection,
                      isGrid: playlistGroups == nil ? showsGrid : playlistsShowGrid,
                      selection: $trackSelection, onShowAlbum: { track in
                          selectPage(.albums)
                          search = track.album
                      },
                      onProperties: openSongProperties,
                      onCollectionProperties: openCollectionProperties,
                      onPlaylistProperties: { properties = PropertiesRequest(subjects: [.playlist($0)]) },
                      propertyRecords: library.propertyRecords,
                      onOpenCollection: { group, page in selectPage(page); collectionDetailKey = group.id },
                      onClassify: { rows in
                          classificationMessage = rows.allSatisfy { $0.localTrack?.format == "MP3" } ? "MP3分类编辑器尚未接入。" : "指定歌曲无法分类。\n仅MP3格式的歌曲可以分类。"
                      },
                      onUnknownProperties: { _ in notice = "Gracenote 音乐识别服务尚未接入。" },
                      onColumnSettings: { settingsPage = .columns },
                      onRestoreColumnOrder: restoreColumnOrder, missingTrackIDs: missingTrackIDs, connected: sampleDevice, playlists: library.playlists,
                      playlistGroups: playlistGroups, showsDisplayPositions: playlistID != nil || page.isHistory, playlistID: playlistID,
                      allowsReordering: playlistID != nil && search.isEmpty,
                      reorderPlaylist: { library.reorderPlaylist($0, replacing: $1, in: $2) },
                      removeFromPlaylist: { entries, id in
                          if library.removePlaylistEntries(entries, from: id) { trackSelection.subtract(entries) }
                      }, removeFromLibrary: { pendingTrackDeletion = Set($0.map(\.id)) },
                      deletePlaylist: { pendingPlaylistDeletion = $0 },
                      openPlaylist: { openPlaylist($0) }, playPlaylist: playPlaylist,
                      addToPlaylist: { library.add($0, to: $1) }, playingTrackID: player.current?.id,
                      playingPlaylistEntryID: player.currentItem?.playlistEntryID,
                      play: sampleLibrary && page != .playlists ? nil : { play($0, from: $1) },
                      enqueue: enqueue,
                      exportTracks: exportTracks,
                      columnWidths: $settings.columnWidths,
                      rowHeight: display.spacing.rowHeight * textScale, textScale: textScale,
                      selectedRowColor: display.appearance.selectedTrack,
                      groupArtistsByTrack: display.groupArtistsByTrack,
                      onNewPlaylist: { openPlaylistPrompt(tracks: $0) })
    }

    private var propertyChoices: [PropertyField: [String]] {
        var values: [PropertyField: Set<String>] = [:]
        for track in library.tracks {
            values[.artist, default: []].insert(track.artist)
            values[.albumArtist, default: []].insert(track.albumArtist)
        }
        for record in library.propertyRecords.values {
            for field in [PropertyField.artist, .albumArtist, .genre] {
                if let value = record.fields[field] { values[field, default: []].insert(value) }
            }
        }
        return values.mapValues { $0.sorted() }
    }

    private func openSongProperties(_ order: [CapturedTrack], selected: CapturedTrack) {
        let selectedRows = order.filter { trackSelection.contains($0.id) }
        if selectedRows.count > 1 {
            properties = PropertiesRequest(subjects: [.songs(selectedRows)])
        } else {
            let subjects = order.map { PropertySubject.songs([$0]) }
            properties = PropertiesRequest(subjects: subjects, selectedIndex: order.firstIndex { $0.id == selected.id } ?? 0)
        }
    }

    private func openCollectionProperties(_ group: TrackCollection, page: LibraryPage) {
        let groups = TrackCollection.group(capturedTracks, by: page, groupArtistsByTrack: display.groupArtistsByTrack)
        let complete = TrackCollection.group(sampleLibrary ? CapturedLibrary.tracks : localRows,
            by: page, groupArtistsByTrack: display.groupArtistsByTrack)
        let byID = Dictionary(uniqueKeysWithValues: complete.map { ($0.id, $0) })
        let subjects = groups.map {
            PropertySubject.collection(byID[$0.id] ?? $0, artist: page == .artists, byTrack: display.groupArtistsByTrack)
        }
        properties = PropertiesRequest(subjects: subjects, selectedIndex: groups.firstIndex { $0.id == group.id } ?? 0)
    }

    private var newPlaylistButton: some View {
        Button { openPlaylistPrompt() } label: {
            Label("新建…", systemImage: "plus")
                .font(.system(size: 11))
                .padding(.horizontal, 11)
                .frame(height: 25)
                .background(Capsule().strokeBorder(ink.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyContent: some View {
        VStack(spacing: 0) {
            if page == .cd {
                connectionIllustration("opticaldisc", direction: "arrow.left")
            } else {
                EmptyNotes()
                    .stroke(Color(white: 0.55), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                    .frame(width: 47, height: 49)
            }
            Text(page == .cd ? "插入音乐CD。" : search.isEmpty ? "内容未找到。" : "搜索结果未找到。\n不同关键词搜索。")
                .multilineTextAlignment(.center)
                .font(.system(size: 17))
                .foregroundStyle(muted)
                .padding(.top, 37)
            if !sampleLibrary && localRows.isEmpty && page == .songs && search.isEmpty {
                Button("导入文件…") { requestImport(.files) }
                    .buttonStyle(.bordered)
                    .disabled(library.importing)
                    .padding(.top, 10)
            }
            if page == .playlists {
                newPlaylistButton.padding(.top, 10)
            }
        }
    }

    private var selectedTracks: [CapturedTrack] {
        capturedTracks.filter { trackSelection.contains($0.id) }
    }

    private var activeWalkman: WalkmanVolume? {
        walkmans.first { $0.id == selectedVolume } ?? walkmans.first
    }

    private var selectedTransferRequest: WalkmanPreviewRequest? {
        guard !sampleDevice, !sampleLibrary else { return nil }
        let tracks = selectedTracks.compactMap(\.localTrack)
        let album = tracks.first?.albumKey
        let wholeAlbum = (page == .albums || page == .new) && album != nil
            && Set(library.tracks.filter { $0.albumKey == album }.map(\.id)) == Set(tracks.map(\.id))
        let layout: VolumeTransfer.Layout
        if page == .playlists, let detail = playlistDetail {
            layout = .playlist(detail.name)
        } else {
            if wholeAlbum, let album { layout = .album(album) } else { layout = .flat }
        }
        return WalkmanPreviewRequest.make(for: activeWalkman, tracks: wholeAlbum ? tracks.sorted(by: Track.albumOrder) : tracks,
                                          layout: layout, settings: settings)
    }

    private func refreshMountedMedia(onMount: Bool = false) {
        refreshAudioDisc(onMount: onMount)
        let roots = WalkmanVolume.mountedRoots()
        guard Set(roots) != Set(walkmanRoots) else { return }
        walkmanRoots = roots
        walkmanRefreshID = UUID()
        walkmans.removeAll { volume in !roots.contains(volume.id.url) }
    }

    private func refreshWalkmans() async {
        guard !isOpeningWalkman else { return }
        isOpeningWalkman = true
        defer { isOpeningWalkman = false }
        let refreshID = UUID()
        walkmanRefreshID = refreshID
        let updated = await Task.detached(priority: .utility) { WalkmanVolume.discover() }.value
        guard !Task.isCancelled, walkmanRefreshID == refreshID else { return }
        if walkmans != updated { walkmans = updated }
        if let selectedVolume, !updated.contains(where: { $0.id == selectedVolume }) { self.selectedVolume = nil }
    }

    private var transferStatus: some View {
        let sizeMB = selectedTracks.reduce(0) { $0 + $1.sizeMB }
        let size = sizeMB == 0 ? "0KB" : "\(sizeMB.formatted(.number.precision(.fractionLength(0...1))))MB"
        return VStack(spacing: 20) {
            Button {
                Task {
                    await refreshWalkmans()
                    transferRequest = selectedTransferRequest
                }
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(gold.opacity(sampleDevice || selectedTransferRequest != nil ? 1 : 0.25), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(selectedTransferRequest == nil)
            .accessibilityLabel("传输到设备")
            .help("传输到设备")
            Text("\(selectedTracks.count)歌曲\n\(size)")
                .font(.system(size: 14))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
        }
    }

    private var devicePane: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                canvas
                Button {
                    showsDevice = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(muted, in: Circle())
                }
                .buttonStyle(.plain)
                .help("关闭设备面板")
                .padding(.top, 19)
                .padding(.trailing, 20)

                if sampleDevice {
                    connectedDevice
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.49)
                } else if let activeWalkman {
                    liveDevice(activeWalkman)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.49)
                } else {
                    VStack(spacing: 23) {
                        Text(walkmanRoots.isEmpty ? "连接设备。" : "已检测到 WALKMAN")
                            .font(.system(size: 14))
                        connectionIllustration("iphone", direction: "arrow.right")
                        if !walkmanRoots.isEmpty {
                            Button("访问 WALKMAN") {
                                Task {
                                    await refreshWalkmans()
                                    if walkmans.isEmpty { notice = "无法读取 WALKMAN。请确认已允许访问设备。" }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isOpeningWalkman)
                        }
                    }
                    .foregroundStyle(muted)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.40)
                }

                Button {
                    settingsPage = .transfer
                } label: {
                    Text("设备传输设置")
                        .font(.system(size: 14))
                        .underline()
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 33)
            }
        }
        .frame(width: 200 * textScale)
    }

    private var connectedDevice: some View {
        VStack(spacing: 0) {
            Text(CapturedLibrary.device).foregroundStyle(ink)
            deviceIcon
            storageLabel
            capacityBar.padding(.top, 20)
            Text("可用空间4GB")
                .foregroundStyle(muted)
                .padding(.top, 7)
            Button {
                showsManagement = true
                trackSelection = []
            } label: {
                Text("管理设备中的歌曲")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(width: 152, height: 26)
                    .background(gold)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
    }

    private var deviceIcon: some View {
        Rectangle()
            .strokeBorder(ink, lineWidth: 4)
            .overlay(alignment: .top) { Rectangle().fill(ink).frame(height: 7) }
            .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 7) }
            .frame(width: 35, height: 53)
            .accessibilityHidden(true)
            .padding(.top, 18)
            .padding(.bottom, 30)
    }

    private func liveDevice(_ volume: WalkmanVolume) -> some View {
        VStack(spacing: 8) {
            Text(volume.name).foregroundStyle(ink)
            deviceIcon
            if walkmans.count > 1 {
                Menu(volume.label) {
                    ForEach(walkmans) { target in
                        Button(target.label) { selectedVolume = target.id }
                    }
                }
                .frame(width: 170)
            } else {
                Text(volume.label).font(.system(size: 12)).textSelection(.enabled)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(white: 0.93))
                    Rectangle().fill(gold).frame(width: geometry.size.width * volume.usedFraction)
                }
            }
            .frame(width: 152, height: 4)
            .padding(.top, 8)
            Text(volume.available.map { "可用空间 " + deviceBytes($0) } ?? "容量不可用")
                .foregroundStyle(muted)
                .accessibilityIdentifier("walkman-available")
            if let capacity = volume.capacity {
                Text("总容量 " + deviceBytes(capacity)).font(.system(size: 11)).foregroundStyle(muted)
            }
            if let music = volume.music {
                Text(music.lastPathComponent).font(.system(size: 11)).foregroundStyle(muted)
                Button("管理设备中的歌曲") {
                    managedDevice = volume
                    trackSelection = []
                }
                .buttonStyle(.borderedProminent)
                .tint(gold)
                .font(.system(size: 12))
                .padding(.top, 12)
            } else {
                Text("找不到可访问的 MUSIC 目录").font(.system(size: 11)).foregroundStyle(muted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("walkman-live")
    }

    private var storageLabel: some View {
        HStack {
            Text(CapturedLibrary.storage).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down").font(.system(size: 9))
        }
        .font(.system(size: 12))
        .padding(.horizontal, 6)
        .frame(width: 152, height: 24)
        .border(muted)
    }

    private var capacityBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(white: 0.93))
                Rectangle().fill(gold)
                    .frame(width: geometry.size.width * CapturedLibrary.used / CapturedLibrary.capacity)
            }
        }
        .frame(width: 152, height: 4)
    }

    private var management: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(CapturedLibrary.device).font(.system(size: 29))
            HStack(alignment: .top, spacing: 18) {
                storageLabel
                VStack(alignment: .leading, spacing: 5) {
                    capacityBar
                    Text("8.23GB / 12.26GB").font(.system(size: 12))
                }
                Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                    .help("刷新")
                    .padding(.leading, 8)
            }
            .padding(.top, 12)
            Text("歌曲")
                .frame(width: 80, height: 32)
                .overlay(alignment: .bottom) { Rectangle().fill(gold).frame(height: 2) }
                .padding(.top, 36)
            HStack(spacing: 16) {
                Button {
                    showsManagement = false
                    trackSelection = []
                } label: {
                    Image(systemName: "chevron.left").frame(width: 31, height: 31)
                }
                .buttonStyle(.plain)
                .help("返回传输面板")
                Text("MUSIC").font(.system(size: 12)).foregroundStyle(muted)
            }
            .padding(.top, 12)
            CapturedTable(tracks: CapturedLibrary.tracks, columns: ["标题", "高解析度", "艺术家", "专辑", "歌曲长度"],
                          isDevice: true, selection: $trackSelection,
                          onShowAlbum: { _ in selectPage(.albums) }, onProperties: openSongProperties, connected: false, columnWidths: $settings.columnWidths)
                .padding(.top, 6)
        }
        .padding(.leading, 28)
        .padding(.trailing, 16)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(canvas)
    }

    private func connectionIllustration(_ device: String, direction: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: direction == "arrow.left" ? "laptopcomputer" : device)
            Image(systemName: direction).font(.system(size: 19, weight: .heavy))
            Image(systemName: direction == "arrow.left" ? device : "laptopcomputer")
        }
        .font(.system(size: 35, weight: .ultraLight))
        .foregroundStyle(muted)
        .frame(height: 49)
    }

    private func selectOutput(_ uid: String?) {
        do {
            try player.selectOutput(uid)
            settings.outputDeviceUID = uid
        } catch {
            audioPanel = nil
            notice = "无法切换音频输出。\(error.localizedDescription)"
        }
    }

    private func audioPanelInset(_ panel: AudioPanel) -> CGFloat {
        switch panel {
        case .dsee: 166
        case .output: 104
        case .queue: 29
        case .volume: 3
        case .equalizer: 0
        }
    }

    private func toggleAudioPanel(_ panel: AudioPanel) {
        showsMenu = false
        audioPanel = audioPanel == panel ? nil : panel
    }

    private func audioButton(_ panel: AudioPanel) -> some View {
        Button { toggleAudioPanel(panel) } label: {
            playbackSymbol(panel == .volume && player.isMuted ? "speaker.slash.fill" : panel.symbol, panel.rawValue)
                .frame(height: 28)
                .background(audioPanel == panel ? selected : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panel.rawValue)
        .help(panel.rawValue)
    }

    private func shortcut(_ action: MainMenuCommand, _ key: KeyEquivalent, modifiers: EventModifiers = [], enabled: Bool = true) -> some View {
        Button(action.rawValue) { performMenuAction(action) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(!enabled)
    }

    private func refreshAudioDisc(onMount: Bool = false) {
        let inventory = AudioCDDrive.inventory()
        let previouslyMounted = mountedDiscs
        if inventory.drives != cdDrives { cdDrives = inventory.drives }
        if inventory.discs != mountedDiscs { mountedDiscs = inventory.discs }

        let candidates = mountedDiscs.filter { settings.cdDriveID == nil || $0.driveID == settings.cdDriveID }
        let canRunInsertionAction = onMount && settings.cdInsertionBehavior != .none
            && exportRequest == nil && transferRequest == nil && albumLookup == nil
        let inserted = canRunInsertionAction ? candidates.first { !previouslyMounted.contains($0) } : nil
        let chosen = inserted ?? candidates.first { $0 == audioDisc } ?? candidates.first
        guard chosen != audioDisc else { return }
        audioDisc = chosen
        discTracks = []
        discInsertionAction = .none
        if inserted != nil {
            discInsertionAction = settings.cdInsertionBehavior
            if page != .cd || showsManagement || managedDevice != nil { selectPage(.cd) }
        }
    }

    private func loadAudioDisc(_ disc: AudioDisc) async {
        guard disc == audioDisc, discTracks.isEmpty else { return }
        do {
            let tracks = try await Task.detached(priority: .utility) { try await disc.tracks() }.value
            guard !Task.isCancelled, disc == audioDisc else { return }
            discTracks = tracks
            let action = discInsertionAction
            discInsertionAction = .none
            guard let first = tracks.first else { return }
            switch action {
            case .none: break
            case .play: player.play(tracks.map { Player.Item(track: $0) }, from: first.id)
            case .importDisc:
                if let directory = settings.cdImportDirectory {
                    beginDiscExport(tracks, disc: disc, directory: directory)
                } else {
                    notice = "请先在「导入文件」设置中选择文件目的地。"
                }
            }
        } catch {
            if !Task.isCancelled, disc == audioDisc { notice = "无法读取音频 CD。\(error.localizedDescription)" }
        }
    }

    private func ejectAudioDisc() {
        if let audioDisc { ejectAudioDisc(audioDisc) }
    }

    private func ejectAudioDisc(_ disc: AudioDisc) {
        guard disc.isMounted else { return }
        if player.queue.contains(where: { $0.url.path.hasPrefix(disc.root.path + "/") }) { player.clearQueue() }
        Task {
            do {
                try await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: disc.root) }.value
                refreshAudioDisc()
            } catch { notice = "无法弹出光盘。\(error.localizedDescription)" }
        }
    }

    private func chooseDiscExport(_ tracks: [Track]) {
        guard let audioDisc, !tracks.isEmpty else { return }
        chooseExportDirectory(title: "选择 CD 导入文件夹") { directory in
            beginDiscExport(tracks, disc: audioDisc, directory: directory)
        }
    }

    private func beginDiscExport(_ tracks: [Track], disc: AudioDisc, directory: URL) {
        guard disc.isMounted else { notice = "音频 CD 已移除。"; return }
        guard exportRequest == nil, transferRequest == nil, albumLookup == nil else { return }
        if settings.cdFormat == .mp3, AudioCommand.ffmpeg == nil { notice = AudioCommand.mp3Requirement; return }
        exportRequest = .init(tracks: tracks, directory: directory, format: settings.cdFormat, bitrate: settings.cdBitrate,
                              importsToLibrary: true, disc: disc,
                              ejectAfterImport: settings.flags["CD导入结束时自动弹出"] ?? false,
                              verifiesSource: settings.cdImportMode == .verifySource)
    }

    private func chooseExportDirectory(title: String, selected: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.begin { response in
            if response == .OK, let directory = panel.url { selected(directory) }
        }
    }

    private func exportTracks(_ tracks: [Track], format: AudioExportFormat) {
        guard !tracks.isEmpty else { return }
        chooseExportDirectory(title: "选择\(format.rawValue)导出文件夹") { directory in
            exportRequest = .init(tracks: tracks, directory: directory, format: format)
        }
    }

    private func chooseATRAC() {
        guard let decoder = AudioCommand.ffmpeg else {
            notice = "ATRAC 转换需要本机的 FFmpeg。"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "选择 ATRAC 音频"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["oma", "aa3", "at3"].map { UTType(filenameExtension: $0) ?? .data }
        panel.begin { response in
            guard response == .OK else { return }
            let tracks = panel.urls.filter { ["oma", "aa3", "at3"].contains($0.pathExtension.lowercased()) }.map { url in
                Track(id: UUID(), url: url, title: url.deletingPathExtension().lastPathComponent, artist: "", album: "",
                      duration: nil, albumArtist: "", disc: nil, number: nil, artwork: nil)
            }
            guard !tracks.isEmpty else { notice = "请选择 ATRAC 音频文件。"; return }
            chooseExportDirectory(title: "选择无损转换文件夹") { directory in
                exportRequest = .init(tracks: tracks, directory: directory, format: .flac, decoder: decoder)
            }
        }
    }

    private func showDiscLookup() {
        guard let audioDisc, !discTracks.isEmpty else { return }
        albumLookup = .init(title: audioDisc.name == "Audio CD" ? "" : audioDisc.name,
                            disc: audioDisc, tracks: discTracks)
    }

    private func saveBackup() {
        let panel = NSSavePanel()
        panel.title = "备份曲库和设置"
        panel.nameFieldStringValue = "Music Center.musiccenterbackup"
        panel.message = "备份包含曲库记录、播放列表、历史和设置。音频由原始路径引用。"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try library.backup(to: url, preferences: preferences)
                notice = "已保存备份「\(url.lastPathComponent)」。"
            } catch { notice = "无法创建备份。\(error.localizedDescription)" }
        }
    }

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.title = "选择曲库备份"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "musiccenterbackup") ?? .data]
        panel.begin { response in
            if response == .OK { pendingRestore = panel.url }
        }
    }

    private var mainMenuEntries: [WindowsMenuEntry] {
        MainMenuCatalog.entries(display: $settings.display, repeatMode: player.repeatMode, isMuted: player.isMuted, isShuffled: player.isShuffled,
            capabilities: MainMenuCapabilities(canPlay: canPlay, canStop: player.current != nil, canGoNext: player.canGoNext,
                canGoPrevious: player.canGoPrevious, canEject: audioDisc != nil, canLookupCD: !discTracks.isEmpty,
                canImport: !library.importing, canSelect: canSelectTracks, canDeselect: canClearTrackSelection, canSearch: !checkingMissingFiles),
            perform: performMenuAction, changeRepeat: { player.repeatMode = $0 })
    }

    private func restoreColumnOrder() {
        let preferred = PreviewSettings.defaultColumns + PreviewSettings.extraColumns
        settings.columns = preferred.filter { settings.columns.contains($0) } + settings.columns.filter { !preferred.contains($0) }
    }

    private func playlistDetailMenu(_ group: PlaylistGroup) -> [WindowsMenuEntry] {
        TrackMenuCatalog.entries(kind: .playlistDetail, playlists: library.playlists,
            capabilities: TrackMenuCapabilities(play: !group.tracks.isEmpty, queue: !group.tracks.isEmpty, remove: true)) { command in
            switch command {
            case .play: playPlaylist(group)
            case .next: enqueue(group.tracks, placement: .next)
            case .queue: enqueue(group.tracks, placement: .end)
            case .newPlaylist: openPlaylistPrompt(tracks: group.tracks.compactMap(\.localTrack))
            case .addToPlaylist(let id): library.add(group.tracks.compactMap(\.localTrack), to: id)
            case .remove: pendingPlaylistDeletion = group.playlist
            case .properties: properties = PropertiesRequest(subjects: [.playlist(group)])
            default: break
            }
        }
    }

    private func collectionDetailView(_ group: TrackCollection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { collectionDetailKey = nil; search = ""; trackSelection = [] } label: {
                Image(systemName: "chevron.left").frame(width: 30, height: 30)
            }.buttonStyle(.plain).accessibilityLabel("返回\(page.rawValue)")
            HStack(alignment: .top, spacing: 22) {
                CapturedCover(artwork: page == .artists && library.propertyRecords[.artist(group.key.title)]?.overridesArtwork == true ? library.propertyRecords[.artist(group.key.title)]?.artwork : group.tracks.first?.localTrack?.artwork,
                    reference: sampleLibrary).frame(width: 158, height: 169)
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.key.title).font(.system(size: 30 * textScale)).lineLimit(2)
                    if page != .artists { Text(group.key.artist).font(.system(size: 12)).lineLimit(1) }
                    Text("\(group.tracks.count)歌曲, \(previewTime(group.tracks.reduce(0) { $0 + $1.seconds }))").font(.system(size: 11)).foregroundStyle(muted)
                    Spacer()
                    WindowsMenuButton(title: "\(page.rawValue)更多操作", width: 176, entries: {
                        TrackMenuCatalog.entries(kind: page == .artists ? .artist : .album, playlists: library.playlists,
                            capabilities: TrackMenuCapabilities(play: !sampleLibrary, queue: !sampleLibrary, remove: !sampleLibrary), showsDestination: false) { command in
                            switch command {
                            case .play: if let first = group.tracks.first { play(group.tracks, from: first) }
                            case .next: enqueue(group.tracks, placement: .next)
                            case .queue: enqueue(group.tracks, placement: .end)
                            case .newPlaylist: openPlaylistPrompt(tracks: group.tracks.compactMap(\.localTrack))
                            case .addToPlaylist(let id): library.add(group.tracks.compactMap(\.localTrack), to: id)
                            case .unknownProperties: notice = "Gracenote 音乐识别服务尚未接入。"
                            case .searchAlbum: search = group.key.title
                            case .remove: pendingTrackDeletion = Set(group.tracks.compactMap { $0.localTrack?.id })
                            case .properties: properties = PropertiesRequest(subjects: [.collection(group, artist: page == .artists, byTrack: display.groupArtistsByTrack)])
                            default: break
                            }
                        }
                    }) { Image(systemName: "ellipsis").frame(width: 25, height: 24) }
                }.frame(height: 169)
            }
            trackTable(group.tracks.filter { $0.matches(search) }, columns: ["#"] + settings.columns).id(group.id)
        }.padding(.leading, 28).padding(.trailing, 16).padding(.top, 8)
    }

    private func searchMissingFiles() {
        guard !checkingMissingFiles else { return }
        checkingMissingFiles = true
        let tracks = library.tracks
        Task {
            let report = await MissingTrackReport.scan(tracks)
            missingTrackIDs = report.missing.intersection(Set(library.tracks.map(\.id)))
            checkingMissingFiles = false
            if report.unreadable.isEmpty {
                notice = missingTrackIDs.isEmpty ? "搜索完成。\n一个图标已显示在无文件歌曲的歌曲列表信息项目中。" : "搜索完成。\n已在\(missingTrackIDs.count)首无文件歌曲的信息栏中显示图标。"
            } else {
                notice = "搜索完成。\n找不到\(missingTrackIDs.count)首歌曲的文件；另有\(report.unreadable.count)首无法读取，未将其判为缺失。"
            }
        }
    }

    private func performMenuAction(_ action: MainMenuCommand) {
        showsMenu = false
        switch action {
        case .newPlaylist: openPlaylistPrompt()
        case .importFiles: requestImport(.files)
        case .importFolder: requestImport(.folder)
        case .importPlaylist: requestImport(.playlist)
        case .quit: NSApp.terminate(nil)
        case .selectAll:
            if canSelectTracks {
                searchFocused = false
                trackSelection = Set(capturedTracks.map(\.id))
            }
        case .deselectAll:
            if canClearTrackSelection {
                searchFocused = false
                trackSelection = []
            }
        case .refresh:
            missingTrackIDs = []
            library.refresh()
            refreshMountedMedia()
        case .playPause: togglePlayback()
        case .stop: player.stop()
        case .previous: player.previous()
        case .next: player.next()
        case .shuffle: player.toggleShuffle()
        case .volumeUp: player.setVolume(player.volume + 0.05)
        case .volumeDown: player.setVolume(player.volume - 0.05)
        case .mute: player.toggleMute()
        case .eject: ejectAudioDisc()
        case .lookupCD: showDiscLookup()
        case .atrac: chooseATRAC()
        case .backup: saveBackup()
        case .restore: chooseBackup()
        case .settings: settingsPage = .display
        case .version: notice = "Music Center for Mac · Windows 2.7.4 界面还原"
        case .system: notice = ProcessInfo.processInfo.operatingSystemVersionString
        case .missing: searchMissingFiles()
        case .update: notice = "Sony 软件更新服务尚未接入。"
        case .support: NSWorkspace.shared.open(URL(string: "https://www.sony.com/electronics/support/articles/MC4PC020001")!)
        }
    }

}

private struct EmptyNotes: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 48
        let sy = rect.height / 52
        var path = Path()
        path.move(to: CGPoint(x: 13, y: 41))
        path.addLine(to: CGPoint(x: 13, y: 6))
        path.addQuadCurve(to: CGPoint(x: 17, y: 2), control: CGPoint(x: 13, y: 1))
        path.addQuadCurve(to: CGPoint(x: 42, y: 2), control: CGPoint(x: 30, y: 7))
        path.addQuadCurve(to: CGPoint(x: 46, y: 6), control: CGPoint(x: 46, y: 1))
        path.addLine(to: CGPoint(x: 46, y: 42))
        path.addCurve(to: CGPoint(x: 32, y: 48), control1: CGPoint(x: 46, y: 51), control2: CGPoint(x: 34, y: 53))
        path.addCurve(to: CGPoint(x: 42, y: 40), control1: CGPoint(x: 29, y: 44), control2: CGPoint(x: 34, y: 39))
        path.addLine(to: CGPoint(x: 42, y: 10))
        path.addQuadCurve(to: CGPoint(x: 17, y: 10), control: CGPoint(x: 29, y: 14))
        path.addLine(to: CGPoint(x: 17, y: 42))
        path.addCurve(to: CGPoint(x: 3, y: 48), control1: CGPoint(x: 17, y: 51), control2: CGPoint(x: 5, y: 53))
        path.addCurve(to: CGPoint(x: 13, y: 41), control1: CGPoint(x: 0, y: 43), control2: CGPoint(x: 6, y: 39))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: sx, y: sy))
    }
}
