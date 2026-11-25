import Foundation

func verifyInformation(in root: URL) async throws {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }
    let unknown = ApplicationInformation(info: [:])
    try check(unknown.version == nil && unknown.build == nil && unknown.title.hasSuffix("—"), "absent version remains unknown")
    try check(!unknown.title.contains("2.7.4"), "reference version cannot become the application version")
    let metadata = ApplicationInformation(info: ["CFBundleName": "Music Center for Mac", "CFBundleShortVersionString": " 0.1.0 ", "CFBundleVersion": "1"])
    try check(metadata.version == "0.1.0" && metadata.build == "1", "read and trim actual bundle metadata")
    let blank = ApplicationInformation(info: ["CFBundleShortVersionString": " \n", "CFBundleVersion": 1])
    try check(blank.version == nil && blank.build == nil, "malformed metadata is not invented")
    try check(SystemInformationCollector.networkDescription(nil) == "网络连接：—", "unreadable network state remains unknown")
    try check(SystemInformationCollector.networkDescription(false).contains("未检测到"), "known absence remains distinct from unreadable state")
    let snapshot = await Task.detached { SystemInformationCollector.collect() }.value
    try check(snapshot.sections.count == 6 && snapshot.sections.allSatisfy { !$0.lines.isEmpty }, "system information sections available")
    try check(snapshot.text.contains(ProcessInfo.processInfo.operatingSystemVersionString), "actual current operating system")
    try check(snapshot.text.contains(SystemInformationCollector.size(ProcessInfo.processInfo.physicalMemory)), "actual current physical memory")
    try check(snapshot.text.contains("互联网连通性：未测试"), "interface status does not claim internet reachability")
    try check(!snapshot.text.contains("Microsoft Windows") && !snapshot.text.contains("LENOVO"), "Windows reference machine is not reported as this Mac")
    let long = SystemInformationSnapshot(sections: [.init(title: "全部内容", lines: (1...80).map { "信息项目 \($0)" })])
    try check(long.text.contains("信息项目 80"), "copy source retains content below the viewport")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try snapshot.text.write(to: root.appending(path: "system-information.txt"), atomically: true, encoding: .utf8)
    try "PASS: actual OS/memory, explicit untested network, absent/malformed bundle versions, reference version separation, complete report text.\n".write(to: root.appending(path: "PASS.txt"), atomically: true, encoding: .utf8)
}
