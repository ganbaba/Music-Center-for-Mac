import AVFoundation
import CoreAudio
import Observation

@MainActor
@Observable
final class Player {
    struct Item {
        let track: Track
        var playlistEntryID: UUID? = nil
        var id: UUID { playlistEntryID ?? track.id }
    }

    enum QueuePlacement {
        case next
        case end
    }

    enum RepeatMode: String, CaseIterable {
        case off = "关"
        case one = "单曲"
        case all = "全部歌曲"

        var next: Self {
            switch self {
            case .off: .one
            case .one: .all
            case .all: .off
            }
        }
    }

    var repeatMode = RepeatMode.off {
        didSet {
            if isShuffled, repeatMode != oldValue, let index {
                rebuildOrder(keeping: order[index])
            }
        }
    }

    private(set) var isShuffled = false
    private var items: [Item] = []
    private var order: [Int] = []

    var queue: [Track] { order.map { items[$0].track } }
    var hasQueue: Bool { !order.isEmpty }
    private(set) var index: Int?
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var volume: Double = 1
    private(set) var isMuted = false
    var error: String?
    private(set) var outputs: [AudioOutputDevice] = []
    private(set) var defaultOutput: AudioDeviceID?
    private(set) var effectiveOutput: AudioDeviceID?
    private(set) var renderingRate: AudioRenderRate = .automatic
    @ObservationIgnored private var preferredOutputUID: String?
    @ObservationIgnored private var equalizerSettings = EqualizerSettings()

    func refreshOutputs(renderingRate: AudioRenderRate? = nil) {
        let oldFormat = outputs.first { $0.deviceID == effectiveOutput }?.formats
        let devices = AudioOutputDevice.available
        let systemDefault = AudioOutputDevice.systemDefault
        if outputs != devices { outputs = devices }
        if defaultOutput != systemDefault { defaultOutput = systemDefault }
        let destination = devices.first { $0.id == preferredOutputUID }?.deviceID ?? systemDefault
        let rate = renderingRate ?? self.renderingRate
        let newFormat = devices.first { $0.deviceID == destination }?.formats
        let hardwareChanged = oldFormat != nil && newFormat != nil && oldFormat != newFormat
        if effectiveOutput != destination || self.renderingRate != rate || hardwareChanged {
            do { try routeAudio(to: destination, renderingRate: rate, rebuild: hardwareChanged) }
            catch {
                if isPlaying { updateElapsed(); node?.pause(); isPlaying = false; ticker?.cancel() }
                self.error = "无法切换音频输出。\(error.localizedDescription)"
            }
        }
    }

    func selectOutput(_ uid: String?, renderingRate: AudioRenderRate? = nil) throws {
        let device = outputs.first { $0.id == uid }
        if uid != nil && device == nil && uid != preferredOutputUID { throw CocoaError(.fileNoSuchFile) }
        try routeAudio(to: device?.deviceID ?? defaultOutput, renderingRate: renderingRate ?? self.renderingRate)
        preferredOutputUID = uid
    }

    func setInitialAudio(outputUID: String?, equalizer: EqualizerSettings, renderingRate: AudioRenderRate = .automatic) {
        preferredOutputUID = outputUID
        setEqualizer(equalizer)
        refreshOutputs(renderingRate: renderingRate)
    }

    func setEqualizer(_ settings: EqualizerSettings) {
        equalizerSettings = settings
        if let equalizer, let file {
            Self.configure(equalizer, settings: settings, sampleRate: file.processingFormat.sampleRate)
        }
    }

    static func configure(_ unit: AVAudioUnitEQ, settings: EqualizerSettings, sampleRate: Double) {
        unit.bypass = !settings.enabled
        unit.globalGain = 0
        let frequencies: [Float] = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        for (band, index) in zip(unit.bands, frequencies.indices) {
            band.filterType = .parametric
            band.frequency = frequencies[index]
            band.bandwidth = 1
            band.gain = Float(settings.gains[index])
            band.bypass = Double(frequencies[index]) >= sampleRate / 2
        }
    }

    func clearQueue() {
        stopGraph()
        items = []
        order = []
        index = nil
        elapsed = 0
        duration = 0
    }
    @ObservationIgnored var onPlaybackStarted: ((Track) -> Void)?
    @ObservationIgnored private var recordedStart = false

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        updateOutputVolume()
    }

    func toggleMute() {
        isMuted.toggle()
        updateOutputVolume()
    }

    private func updateOutputVolume() {
        engine?.mainMixerNode.outputVolume = isMuted ? 0 : Float(volume)
    }

    func stop() {
        if isPlaying { toggle() }
        seek(0)
    }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var equalizer: AVAudioUnitEQ?
    @ObservationIgnored private var node: AVAudioPlayerNode?
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var startFrame: AVAudioFramePosition = 0

    var currentItem: Item? { index.map { items[order[$0]] } }
    var current: Track? { currentItem?.track }
    var canGoNext: Bool { index.map { $0 + 1 < order.count || repeatMode == .all } ?? false }
    var canGoPrevious: Bool { index.map { $0 > 0 } ?? false }

    func toggleShuffle() {
        let currentPosition = index.map { order[$0] }
        isShuffled.toggle()
        rebuildOrder(keeping: currentPosition)
    }

    private func rebuildOrder(keeping currentPosition: Int?) {
        order = Array(items.indices)
        if isShuffled {
            if let currentPosition {
                order.remove(at: currentPosition)
                order.shuffle()
                order.insert(currentPosition, at: 0)
            } else {
                order.shuffle()
            }
        }
        index = currentPosition.flatMap { order.firstIndex(of: $0) }
    }

    isolated deinit {
        ticker?.cancel()
        node?.stop()
        engine?.stop()
    }

    func play(_ items: [Item], from id: UUID? = nil) {
        guard !items.isEmpty else { return }
        self.items = items
        let startPosition = id.flatMap { id in items.firstIndex { $0.id == id } }
        rebuildOrder(keeping: startPosition)
        start(at: index ?? 0)
    }

    func refreshMetadata(_ tracks: [Track]) {
        let latest = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        items = items.map { item in
            Item(track: latest[item.track.id] ?? item.track, playlistEntryID: item.playlistEntryID)
        }
    }

    func enqueue(_ additions: [Item], placement: QueuePlacement) {
        guard !additions.isEmpty else { return }
        let insertionInQueue: Int
        let insertionInSource: Int
        switch placement {
        case .next:
            insertionInQueue = index.map { $0 + 1 } ?? 0
            insertionInSource = index.map { order[$0] + 1 } ?? 0
        case .end:
            insertionInQueue = order.count
            insertionInSource = items.count
        }
        items.insert(contentsOf: additions, at: insertionInSource)
        order = order.map { $0 < insertionInSource ? $0 : $0 + additions.count }
        order.insert(contentsOf: insertionInSource..<(insertionInSource + additions.count), at: insertionInQueue)
    }

    func jump(to index: Int) {
        guard order.indices.contains(index) else { return }
        start(at: index)
    }

    func next() {
        guard let index, canGoNext else { return }
        if index + 1 < order.count {
            start(at: index + 1, playing: isPlaying)
        } else {
            startNextCycle(playing: isPlaying)
        }
    }

    func previous() {
        if let index, canGoPrevious { start(at: index - 1, playing: isPlaying) }
    }

    func toggle() {
        guard let index else {
            if !order.isEmpty { start(at: 0) }
            return
        }
        guard let node else { start(at: index); return }
        if isPlaying {
            updateElapsed()
            node.pause()
            isPlaying = false
            ticker?.cancel()
        } else {
            if elapsed >= duration {
                start(at: index)
            } else {
                resume()
            }
        }
    }

    func seek(_ seconds: Double) {
        guard let file, seconds.isFinite, duration > 0 else { return }
        let frame = AVAudioFramePosition(min(max(0, seconds), duration) * file.processingFormat.sampleRate)
        let wasPlaying = isPlaying
        schedule(from: min(frame, file.length - 1))
        if wasPlaying { resume() }
    }

    private func startNextCycle(playing: Bool) {
        rebuildOrder(keeping: nil)
        start(at: 0, playing: playing)
    }

    private func start(at index: Int, playing: Bool = true) {
        stopGraph()
        self.index = index
        recordedStart = false
        elapsed = 0
        duration = 0
        let track = items[order[index]].track
        do {
            let file = try AVAudioFile(forReading: track.url)
            let rate = file.processingFormat.sampleRate
            guard rate > 0, rate.isFinite, file.length > 0, file.length <= Int64(UInt32.max) else {
                error = "无法播放此文件的音频流。"
                return
            }
            let graph = try makeGraph(for: file, output: effectiveOutput, renderingRate: renderingRate)
            engine = graph.engine
            node = graph.node
            equalizer = graph.equalizer
            self.file = file
            duration = Double(file.length) / rate
            schedule(from: 0)
            if playing { resume() }
        } catch {
            self.error = "无法播放「\(track.title)」。\(error.localizedDescription)"
        }
    }

    private func makeGraph(for file: AVAudioFile, output: AudioDeviceID?, renderingRate: AudioRenderRate) throws
        -> (engine: AVAudioEngine, node: AVAudioPlayerNode, equalizer: AVAudioUnitEQ) {
        let engine = AVAudioEngine()
        if let output {
            let unit = engine.outputNode.auAudioUnit
            if unit.deviceID != output { try unit.setDeviceID(output) }
        }
        let node = AVAudioPlayerNode()
        let equalizer = AVAudioUnitEQ(numberOfBands: EqualizerSettings.frequencies.count)
        let format = file.processingFormat
        Self.configure(equalizer, settings: equalizerSettings, sampleRate: format.sampleRate)
        engine.attach(node)
        engine.attach(equalizer)
        engine.connect(node, to: equalizer, format: format)
        if let rate = renderingRate.sampleRate, rate != format.sampleRate,
           let renderFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: format.channelCount) {
            let resampler = AVAudioMixerNode()
            engine.attach(resampler)
            engine.connect(equalizer, to: resampler, format: format)
            engine.connect(resampler, to: engine.mainMixerNode, format: renderFormat)
        } else {
            engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = isMuted ? 0 : Float(volume)
        return (engine, node, equalizer)
    }

    private func routeAudio(to output: AudioDeviceID?, renderingRate: AudioRenderRate, rebuild: Bool = false) throws {
        guard rebuild || effectiveOutput != output || self.renderingRate != renderingRate else { return }
        if let file {
            let wasPlaying = isPlaying
            if wasPlaying { updateElapsed() }
            let frame = min(AVAudioFramePosition(elapsed * file.processingFormat.sampleRate), file.length - 1)
            let replacement = try makeGraph(for: file, output: output, renderingRate: renderingRate)
            if wasPlaying { try replacement.engine.start() }
            node?.stop()
            engine?.stop()
            engine = replacement.engine
            node = replacement.node
            equalizer = replacement.equalizer
            schedule(from: frame)
            if wasPlaying { resume() }
        }
        effectiveOutput = output
        self.renderingRate = renderingRate
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let node, let file else { return }
        let generation = UUID()
        self.generation = generation
        ticker?.cancel()
        node.stop()
        isPlaying = false
        startFrame = frame
        elapsed = Double(frame) / file.processingFormat.sampleRate
        node.scheduleSegment(file, startingFrame: frame, frameCount: AVAudioFrameCount(file.length - frame), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.finished(generation) }
        }
    }

    private func resume() {
        guard let engine, let node else { return }
        do {
            if !engine.isRunning { try engine.start() }
            node.play()
            isPlaying = true
            if !recordedStart, let current {
                recordedStart = true
                onPlaybackStarted?(current)
            }
            ticker?.cancel()
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(200)) }
                    catch { break }
                    self?.updateElapsed()
                }
            }
        } catch {
            self.error = "无法启动音频输出。\(error.localizedDescription)"
        }
    }

    private func updateElapsed() {
        guard let node, let file, let time = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: time), playerTime.sampleTime >= 0 else { return }
        elapsed = min(duration, Double(startFrame) / file.processingFormat.sampleRate
                      + Double(playerTime.sampleTime) / playerTime.sampleRate)
    }

    private func finished(_ generation: UUID) {
        guard generation == self.generation, let index else { return }
        if repeatMode == .one {
            start(at: index)
        } else if index + 1 < order.count {
            start(at: index + 1)
        } else if repeatMode == .all {
            startNextCycle(playing: true)
        } else {
            stopGraph()
            self.index = nil
            elapsed = 0
            duration = 0
        }
    }

    private func stopGraph() {
        generation = UUID()
        ticker?.cancel()
        ticker = nil
        node?.stop()
        engine?.stop()
        node = nil
        equalizer = nil
        engine = nil
        file = nil
        isPlaying = false
    }
}
