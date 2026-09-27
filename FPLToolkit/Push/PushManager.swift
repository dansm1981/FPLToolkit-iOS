import Observation
import UIKit
import UserNotifications

/// Notification permission, the push token, and what happens when a notification is tapped.
/// Pushes only reach the phone once the app is signed with the paid team (the push
/// entitlement) and the server has switched a category on; until then this stays quiet.
@MainActor
@Observable
final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    enum Permission: Equatable {
        case unknown, notDetermined, denied, authorized
    }

    private(set) var permission: Permission = .unknown
    /// Opens a notification's deep link (set by AppModel to the router).
    var openLink: ((DeepLink) -> Void)?
    /// Hands the token to the device session with the current team.
    var tokenChanged: ((String?) -> Void)?

    private let defaults: UserDefaults
    private enum Keys { static let primerDismissed = "push.primerDismissed" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        UNUserNotificationCenter.current().delegate = self
        PushRelay.shared.manager = self
    }

    /// "Not now" on the primer: don't ask again from Today (Settings still offers it).
    var primerDismissed: Bool {
        get { defaults.bool(forKey: Keys.primerDismissed) }
        set { defaults.set(newValue, forKey: Keys.primerDismissed) }
    }

    /// Reads the permission; when allowed, asks iOS for a (fresh) push token.
    func refresh() async {
        let status = await Self.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral: permission = .authorized
        case .denied: permission = .denied
        case .notDetermined: permission = .notDetermined
        @unknown default: permission = .unknown
        }
        if permission == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        } else if permission == .denied {
            tokenChanged?(nil)
        }
    }

    /// Shows the system prompt. Returns whether notifications were allowed.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refresh()
        return granted
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Token (from AppDelegate)

    func didRegister(deviceToken: Data) {
        tokenChanged?(deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func didFailToRegister(_ error: Error) {
        // Expected until the app is signed with the paid team (no push entitlement yet).
        print("Push registration failed: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let link = response.notification.request.content.userInfo["deepLink"] as? String
        await MainActor.run {
            if let link, let url = URL(string: link), let deepLink = DeepLink(url: url) {
                openLink?(deepLink)
            }
        }
    }

    private nonisolated static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
}

/// Lets the UIKit app delegate reach the PushManager the SwiftUI app owns.
@MainActor
final class PushRelay {
    static let shared = PushRelay()
    weak var manager: PushManager?
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRelay.shared.manager?.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushRelay.shared.manager?.didFailToRegister(error)
    }
}
