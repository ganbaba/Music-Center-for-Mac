import Foundation

@MainActor
func verifySettingsPreferences(in directory: URL) throws {
    // Old preference files omit newer choices. They must continue to decode.
    let old = try JSONDecoder().decode(PreviewSettings.self, from: Data("{}".utf8))
    precondition(old.cdFormat == .aac && old.cdBitrate == 128)
    var selected = old
    selected.cdFormat = .mp3
    selected.cdBitrate = 224
    precondition(selected.cdBitrate == 224)
    selected.cdBitrate = 112
    selected.cdFormat = .aac
    precondition(selected.cdBitrate == 128)
    selected.cdFormat = .mp3
    precondition(selected.cdBitrate == 112)
    selected.choices["识别语言"] = "English"
    precondition(selected.recognitionLanguage == "英语")
    precondition(selected.choices["识别语言"] == "English")
    selected.recognitionLanguage = "荷兰语"
    selected.autoImportFolders = [directory.appending(path: "参考歌曲").path]
    selected.cdImportDirectory = directory.appending(path: "CD 目标")
    selected.outputSampleRate = .ultraStudio
    selected.outputDeviceUID = "preserved-output-device"
    let preferences = PreviewPreferences(directory: directory)
    preferences.settings = selected
    let reopened = PreviewPreferences(directory: directory)
    precondition(reopened.error == nil)
    precondition(reopened.settings == selected)
    precondition(reopened.settings.cdBitrate == 112)
    precondition(reopened.settings.autoImportFolders == selected.autoImportFolders)
    precondition(reopened.settings.importDestination == selected.importDestination)
    precondition(reopened.settings.recognitionLanguage == "荷兰语")
    // Editing a settings draft must not mutate its saved source before save.
    var draft = reopened.settings
    draft.cdBitrate = 320
    draft.autoImportFolders = []
    precondition(reopened.settings.cdBitrate == 112)
    precondition(reopened.settings.autoImportFolders.count == 1)
    print("Settings preferences smoke passed: legacy decoding, format-specific bitrate fallback, language compatibility, snapshot reopen and isolated drafts.")
}
