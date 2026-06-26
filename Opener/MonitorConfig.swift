import Cocoa
import CoreGraphics

enum MonitorConfig {
    static func currentDisplayUUIDs() -> [String] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }

        return (0..<Int(count)).compactMap { i -> String? in
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(ids[i])?.takeRetainedValue() else { return nil }
            guard let cfStr = CFUUIDCreateString(nil, uuid) else { return nil }
            return cfStr as String
        }.sorted()
    }

    static func currentConfigID() -> String {
        currentDisplayUUIDs().joined(separator: "+")
    }

    static func shortLabel(for displayUUID: String) -> String {
        let suffix = displayUUID.suffix(4)
        return suffix.isEmpty ? displayUUID : String(suffix)
    }
}
