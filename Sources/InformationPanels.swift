import AppKit
import Darwin
import DiscRecording
import IOKit
import SwiftUI

enum InformationPage: String, Identifiable {
    case system, version
    var id: String { rawValue }
}

struct ApplicationInformation: Equatable, Sendable {
    let name: String
    let version: String?
    let build: String?
    static let reference = "Music Center for PC 2.7.4"

    init(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let raw = info[key] as? String else { return nil }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        name = value("CFBundleDisplayName") ?? value("CFBundleName") ?? "Music Center for Mac"
        version = value("CFBundleShortVersionString")
        build = value("CFBundleVersion")
    }
    static var current: Self { Self(info: Bundle.main.infoDictionary ?? [:]) }
    var title: String { name + " Version " + (version ?? "—") }
    var buildDescription: String { "构建版本：" + (build ?? "—") }
}

struct SystemInformationSnapshot: Equatable, Sendable {
    struct Section: Equatable, Sendable {
        let title: String
        let lines: [String]
    }
    let sections: [Section]
    var text: String {
        sections.map { section in
            (["-" + section.title] + section.lines.map { "  -" + $0 }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

/// A snapshot of local facts. Does not enumerate or open removable volumes, or contact a server.
enum SystemInformationCollector {
    static func collect() -> SystemInformationSnapshot {
        let process = ProcessInfo.processInfo
        let cpu = sysctlString("machdep.cpu.brand_string") ?? "—"
        let model = sysctlString("hw.model") ?? platformString("model") ?? "—"
        let machine = sysctlString("hw.machine") ?? "—"
        let frequency: String
        if let hz = sysctlInteger("hw.cpufrequency"), hz > 0 {
            frequency = String(format: "%.3f GHz", Double(hz) / 1_000_000_000)
        } else { frequency = "—" }

        let driveNames = (DRDevice.devices() as? [DRDevice]).map { devices in devices.map { device in
            let info = device.info() ?? [:]
            let name = [DRDeviceVendorNameKey, DRDeviceProductNameKey].compactMap { info[$0] as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? "光驱（名称不可用）" : name
        } }
        let language = Locale.preferredLanguages.first.map(localizedLanguage) ?? "—"
        let region = Locale(identifier: "zh_CN").localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier
        return SystemInformationSnapshot(sections: [
            .init(title: "计算机环境", lines: [
                "操作系统：macOS " + process.operatingSystemVersionString,
                "系统类型：\(MemoryLayout<Int>.size * 8)位（\(machine)）",
                "处理器：" + cpu,
                "频率：" + frequency,
                "内存：" + size(process.physicalMemory),
            ]),
            .init(title: "计算机制造商", lines: [
                "制造商：" + (platformString("manufacturer") ?? "—"),
                "型号：" + model,
            ]),
            .init(title: "硬盘可用空间", lines: [startupDisk()]),
            .init(title: "CD/DVD驱动器", lines: driveNames.map { $0.isEmpty ? ["未检测到光驱"] : $0 } ?? ["光驱信息不可用"]),
            .init(title: "语言设置", lines: ["用户语言设置：" + language, "区域设置：" + region]),
            .init(title: "互联网环境", lines: [
                networkDescription(activeNetworkInterface()),
                "互联网连通性：未测试",
            ]),
        ])
    }

    static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary)
    }
    private static func localizedLanguage(_ code: String) -> String {
        (Locale(identifier: "zh_CN").localizedString(forIdentifier: code) ?? code) + "（\(code)）"
    }
    private static func startupDisk() -> String {
        // Query only the volume holding the user's home; do not walk user files or mounted devices.
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber else { return "启动磁盘：—" }
        return "启动磁盘：\(size(free.uint64Value))（总共：\(size(total.uint64Value))）"
    }
    private static func sysctlString(_ name: String) -> String? {
        var length = 0
        guard sysctlbyname(name, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        guard sysctlbyname(name, &bytes, &length, nil, 0) == 0 else { return nil }
        let text = String(decoding: bytes.prefix(length).prefix(while: { $0 != 0 }), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    private static func sysctlInteger(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var length = MemoryLayout.size(ofValue: value)
        guard sysctlbyname(name, &value, &length, nil, 0) == 0 else { return nil }
        return value
    }
    private static func platformString(_ key: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        let text: String?
        if let data = value as? Data { text = String(data: data.prefix(while: { $0 != 0 }), encoding: .utf8) }
        else { text = value as? String }
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
    static func networkDescription(_ active: Bool?) -> String {
        switch active {
        case true: "网络连接：已启用（本地接口状态）"
        case false: "网络连接：未检测到活动接口"
        case nil: "网络连接：—"
        }
    }
    private static func activeNetworkInterface() -> Bool? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var current = head
        while let interface = current {
            let value = interface.pointee
            if let address = value.ifa_addr {
                let family = Int32(address.pointee.sa_family)
                let flags = value.ifa_flags
                if (family == AF_INET || family == AF_INET6),
                   flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_RUNNING) != 0,
                   flags & UInt32(IFF_LOOPBACK) == 0 { return true }
            }
            current = value.ifa_next
        }
        return false
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct InformationPanel: View {
    let page: InformationPage
    var height: CGFloat = 600
    var application = ApplicationInformation.current
    var providedSystem: SystemInformationSnapshot? = nil
    var copy: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    let close: () -> Void
    @State private var system: SystemInformationSnapshot?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Text(page == .system ? "系统信息" : application.title)
                .frame(maxWidth: .infinity).frame(height: 48)
                .padding(.horizontal, 42)
                .overlay(alignment: .trailing) {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(white: 0.48)).frame(width: 36, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).keyboardShortcut(.cancelAction).padding(.trailing, 6).accessibilityLabel("关闭" + (page == .system ? "系统信息" : "版本信息"))
                }
            Group {
                if page == .system { systemContent } else { versionContent }
            }
            .frame(maxHeight: .infinity).padding(.horizontal, 16)
            HStack {
                if page == .system {
                    SettingsAction("复制到剪切板", width: 112) {
                        guard let system else { return }
                        copy(system.text); copied = true
                    }.disabled(system == nil).help(copied ? "已复制全部系统信息" : "复制全部系统信息")
                    if copied { Text("已复制").font(.system(size: 10)).foregroundStyle(Color(white: 0.48)).accessibilityLabel("系统信息已复制") }
                }
                Spacer()
                Button(action: close) {
                    Text("确定").foregroundStyle(.white).frame(width: 120, height: 27).background(SettingsStyle.gold)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 14)
        }
        .font(.system(size: 12)).foregroundStyle(SettingsStyle.ink)
        .frame(width: 650, height: height).background(.white)
        .environment(\.colorScheme, .light)
        .compositingGroup().shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        .onExitCommand(perform: close)
        .accessibilityElement(children: .contain).accessibilityLabel(page == .system ? "系统信息窗口" : "版本信息窗口")
        .task(id: page) {
            guard page == .system else { return }
            if let providedSystem { system = providedSystem; return }
            let snapshot = await Task.detached(priority: .utility) { SystemInformationCollector.collect() }.value
            guard !Task.isCancelled else { return }
            system = snapshot
        }
    }

    private var systemContent: some View {
        SettingsScroll {
            if let system {
                Text(system.text).textSelection(.enabled).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24).padding(.vertical, 20)
            } else {
                Text("正在读取系统信息…").padding(24)
            }
        }.padding(1).border(Color(white: 0.48))
    }

    private var versionContent: some View {
        VStack(spacing: 8) {
            SettingsScroll {
                VStack(alignment: .leading, spacing: 30) {
                    versionRow("music.note", name: application.name, color: SettingsStyle.gold) {
                        Text("macOS 音乐播放器与 Windows 界面还原项目。")
                        Text(application.buildDescription).padding(.top, 6)
                    }
                    versionRow("apple.logo", name: "SwiftUI / AppKit", color: .black) {
                        Text("Mac 原生界面与系统窗口。音频播放和处理使用 AVFoundation / Core Audio，本地曲库使用 SQLite。")
                    }
                    Text("Windows 参考界面中的技术名称").foregroundStyle(Color(white: 0.30))
                    versionRow(nil, name: "gracenote", color: Color(red: 0.9, green: 0, blue: 0.35)) {
                        Text("参考软件中的歌曲信息、封面和音乐识别服务。Mac 版尚未接入 Gracenote 与 12 Tone Analysis。")
                    }
                    versionRow(nil, name: "ATRAC", color: .black) {
                        Text("Windows 参考软件中的音频格式名称。Mac 版的现有转换入口使用用户本机的 FFmpeg。")
                    }
                    versionRow(nil, name: "DSEE HX", color: .black) {
                        Text("Windows 参考软件中的音效名称。Mac 版目前保存开关状态，未实现该音频算法。")
                    }
                    versionRow(nil, name: "ASIO", color: .black) {
                        Text("Windows 参考界面包含 ASIO 说明。Mac 版通过 Core Audio 输出，不使用 Windows ASIO 驱动。")
                    }
                    versionRow(nil, name: "ELECTRON", color: Color(red: 0.3, green: 0.5, blue: 0.54)) {
                        Text("Electron 出现在 Windows 原版的版本信息中。Mac 版使用 SwiftUI / AppKit，不基于 Electron。")
                    }
                }.padding(.horizontal, 16).padding(.vertical, 30)
                .textSelection(.enabled)
            }
            Text("Windows 界面参考 · " + ApplicationInformation.reference)
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.32)).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func versionRow<Content: View>(_ symbol: String?, name: String, color: Color,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 30)) }
                Text(name).font(.system(size: name.count > 15 ? 16 : 21, weight: .semibold))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(color).frame(width: 158)
            VStack(alignment: .leading, spacing: 0, content: content)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 100)
    }
}

struct InformationPresentation: ViewModifier {
    @Binding var page: InformationPage?
    func body(content: Content) -> some View {
        content.disabled(page != nil)
            .overlay {
                if let page {
                    GeometryReader { geometry in
                        let scale = min(1, max(0.1, (geometry.size.width - 24) / 650))
                        let height = min(600, (geometry.size.height - 24) / scale)
                        ZStack {
                            Color(white: 0.93).opacity(0.68).contentShape(Rectangle())
                            InformationPanel(page: page, height: height, close: { self.page = nil })
                                .id(page).scaleEffect(scale).frame(width: 650 * scale, height: height * scale)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
    }
}
