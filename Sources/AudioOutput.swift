import CoreAudio
import Foundation

enum AudioRenderRate: Int, CaseIterable, Identifiable, Codable {
    case automatic = 0
    case standard = 44100
    case studio = 48000
    case doubleStandard = 88200
    case doubleStudio = 96000
    case highStandard = 176400
    case highStudio = 192000
    case ultraStandard = 352800
    case ultraStudio = 384000

    var id: Int { rawValue }
    var sampleRate: Double? { self == .automatic ? nil : Double(rawValue) }
    var label: String { sampleRate.map(Self.label(for:)) ?? "自动" }

    static func label(for sampleRate: Double) -> String {
        (sampleRate / 1000).formatted(.number.precision(.fractionLength(0...3))) + " kHz"
    }
}

struct AudioDeviceFormat: Equatable {
    let sampleRate: Double
    let sampleBits: UInt32
    let channels: UInt32
    let isFloat: Bool

    var label: String {
        let depth = sampleBits == 0 ? nil : (isFloat ? "\(sampleBits) 位浮点" : "\(sampleBits) 位")
        return [AudioRenderRate.label(for: sampleRate), depth, "\(channels) 声道"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

struct AudioOutputDevice: Identifiable, Equatable {
    let deviceID: AudioDeviceID
    let id: String
    let name: String
    let formats: [AudioDeviceFormat]

    static var available: [Self] {
        var address = property(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = Array(repeating: AudioDeviceID(0), count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes { buffer in
            guard let addressOfDevices = buffer.baseAddress else { return OSStatus(kAudioHardwareBadPropertySizeError) }
            return AudioObjectGetPropertyData(system, &address, 0, nil, &size, addressOfDevices)
        }
        guard status == noErr else { return [] }
        return devices.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size).compactMap { device in
            var output = property(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var outputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &output, 0, nil, &outputSize) == noErr, outputSize > 0,
                  let id = string(device, kAudioDevicePropertyDeviceUID),
                  let name = string(device, kAudioObjectPropertyName) else { return nil }
            let formats = formats(device, address: &output, size: outputSize)
            return Self(deviceID: device, id: id, name: name, formats: formats)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static var systemDefault: AudioDeviceID? {
        var result = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &result) == noErr,
              result != kAudioObjectUnknown else { return nil }
        return result
    }

    private static func property(_ selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func formats(_ device: AudioDeviceID, address: inout AudioObjectPropertyAddress,
                                size: UInt32) -> [AudioDeviceFormat] {
        var count = size
        var streams = Array(repeating: AudioStreamID(0), count: Int(size) / MemoryLayout<AudioStreamID>.size)
        let status = streams.withUnsafeMutableBytes { buffer in
            guard let storage = buffer.baseAddress else { return OSStatus(kAudioHardwareBadPropertySizeError) }
            return AudioObjectGetPropertyData(device, &address, 0, nil, &count, storage)
        }
        guard status == noErr else { return [] }
        return streams.prefix(Int(count) / MemoryLayout<AudioStreamID>.size).compactMap { stream in
            var address = property(kAudioStreamPropertyPhysicalFormat)
            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            guard AudioObjectGetPropertyData(stream, &address, 0, nil, &size, &format) == noErr,
                  format.mSampleRate.isFinite, format.mSampleRate > 0, format.mChannelsPerFrame > 0 else { return nil }
            return AudioDeviceFormat(sampleRate: format.mSampleRate,
                                     sampleBits: format.mFormatID == kAudioFormatLinearPCM ? format.mBitsPerChannel : 0,
                                     channels: format.mChannelsPerFrame,
                                     isFloat: format.mFormatFlags & kAudioFormatFlagIsFloat != 0)
        }
    }

    private static func string(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = property(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
