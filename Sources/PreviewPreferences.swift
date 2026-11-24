import Foundation
import Observation

@MainActor
@Observable
final class PreviewPreferences {
    var settings = PreviewSettings() { didSet { if settings != oldValue { save() } } }
    var equalizer = EqualizerSettings() { didSet { if equalizer != oldValue { save() } } }
    var dsee = true { didSet { if dsee != oldValue { save() } } }
    var error: String?

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var needsBackup = true
    @ObservationIgnored private var loaded = false

    init(directory: URL = .applicationSupportDirectory.appending(path: "MusicCenterUIRecreation", directoryHint: .isDirectory)) {
        url = directory.appending(path: "Preferences.json")
        defer { loaded = true }
        do {
            let data: Data
            do { data = try Data(contentsOf: url) }
            catch CocoaError.fileReadNoSuchFile { return }
            let saved = try JSONDecoder().decode(SavedPreferences.self, from: data)
            try saved.validate()
            settings = saved.settings
            equalizer = saved.equalizer
            dsee = saved.dsee
        } catch {
            self.error = "无法读取设置，已使用默认值。\(error.localizedDescription)"
        }
    }

    func snapshot() throws -> Data {
        let saved = SavedPreferences(settings: settings, equalizer: equalizer, dsee: dsee)
        try saved.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(saved)
    }

    func decodeSnapshot(_ data: Data) throws -> SavedPreferences {
        let saved = try JSONDecoder().decode(SavedPreferences.self, from: data)
        try saved.validate()
        return saved
    }

    func writeSnapshot(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if needsBackup {
            do {
                let previous = try Data(contentsOf: url)
                try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
            } catch CocoaError.fileReadNoSuchFile {}
            needsBackup = false
        }
        try data.write(to: url, options: .atomic)
    }

    func applySnapshot(_ saved: SavedPreferences) {
        loaded = false
        defer { loaded = true }
        settings = saved.settings
        equalizer = saved.equalizer
        dsee = saved.dsee
    }

    private func save() {
        guard loaded else { return }
        do { try writeSnapshot(snapshot()) }
        catch { self.error = "无法保存设置。\(error.localizedDescription)" }
    }
}

struct SavedPreferences: Codable {
    let settings: PreviewSettings
    let equalizer: EqualizerSettings
    let dsee: Bool

    enum CodingKeys: String, CodingKey {
        case settings, equalizer, dsee
    }

    init(settings: PreviewSettings, equalizer: EqualizerSettings, dsee: Bool) {
        self.settings = settings
        self.equalizer = equalizer
        self.dsee = dsee
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        settings = try values.decodeIfPresent(PreviewSettings.self, forKey: .settings) ?? PreviewSettings()
        equalizer = try values.decodeIfPresent(EqualizerSettings.self, forKey: .equalizer) ?? EqualizerSettings()
        dsee = try values.decodeIfPresent(Bool.self, forKey: .dsee) ?? true
    }

    func validate() throws {
        let columns = PreviewSettings.defaultColumns + PreviewSettings.extraColumns
        let validColumns = settings.columns.contains("标题")
            && Set(settings.columns).count == settings.columns.count
            && settings.columns.allSatisfy(columns.contains)
        let validWidths = settings.columnWidths.allSatisfy { _, width in width.isFinite && (42...650).contains(width) }
        let curves = [equalizer.gains] + equalizer.custom.map(\.gains)
        let validGains = curves.allSatisfy {
            $0.count == EqualizerSettings.frequencies.count && $0.allSatisfy { (-12...12).contains($0) }
        }
        let names = equalizer.custom.map(\.name)
        guard validColumns, validWidths, validGains, Set(names).count == names.count else {
            throw CocoaError(.coderReadCorrupt)
        }
    }
}
