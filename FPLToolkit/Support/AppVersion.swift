import Foundation

/// Dotted version numbers ("1.2.10"), compared number by number.
struct AppVersion: Comparable, Sendable {
    let parts: [Int]

    init(_ string: String) {
        parts = string.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    static var current: AppVersion {
        AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0
            let r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}
