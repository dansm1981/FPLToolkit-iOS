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
