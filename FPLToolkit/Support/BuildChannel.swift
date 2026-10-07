import Foundation

/// Where this copy of the app came from: Xcode, TestFlight or the App Store.
enum BuildChannel {
    /// Xcode and TestFlight builds, which show the Developer tools (live matchday replay).
    /// App Store builds never do. TestFlight installs carry a sandbox receipt; the same binary
    /// installed from the App Store doesn't.
    static let isBeta: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()
}

/// Matchday v2 (tasks/matchday-v2.md; Dan, 7 Oct 2026): tried behind Settings → Developer, in Xcode
/// and TestFlight builds only, so it can be compared with v1 on a real matchday and switched off.
enum MatchdayV2 {
    static let key = "matchday.v2"
    static func isOn(_ stored: Bool) -> Bool { BuildChannel.isBeta && stored }
}
