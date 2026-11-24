import Darwin
import Foundation

// Read the kernel's cached mount table without visiting paths on removable media.
struct MountedVolume {
    let root: URL
    let format: String
    let source: String
    let identifier: UInt64
    let isLocal: Bool

    static func list() -> [Self] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        var entries = Array(repeating: statfs(), count: Int(count) + 8)
        let capacity = Int32(entries.count * MemoryLayout<statfs>.stride)
        let found = entries.withUnsafeMutableBufferPointer { buffer in
            getfsstat(buffer.baseAddress, capacity, MNT_NOWAIT)
        }
        guard found > 0 else { return [] }
        return entries.prefix(Int(found)).compactMap { entry in
            let path = withUnsafeBytes(of: entry.f_mntonname) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            guard !path.isEmpty else { return nil }
            let format = withUnsafeBytes(of: entry.f_fstypename) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            let source = withUnsafeBytes(of: entry.f_mntfromname) {
                String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
            }
            let identifier = withUnsafeBytes(of: entry.f_fsid) { $0.loadUnaligned(as: UInt64.self) }
            return Self(root: URL(fileURLWithPath: path, isDirectory: true), format: format, source: source,
                        identifier: identifier, isLocal: entry.f_flags & UInt32(MNT_LOCAL) != 0)
        }
    }
}
