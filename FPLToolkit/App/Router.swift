import Foundation
import Observation

enum AppTab: Hashable {
    case today, team, watch
}

/// `fpltoolkit://` links (§5). Unknown links open Today.
enum DeepLink: Equatable {
    case today
    case team
    case watch
    case alerts
    /// `event` is set when the link came from an alert (notifications.md §6).
    case player(Int, event: String? = nil)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "fpltoolkit" else { return nil }
        let host = url.host()?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "team": self = .team
        case "watch": self = parts.first?.lowercased() == "alerts" ? .alerts : .watch
        case "player":
            guard let id = parts.first.flatMap(Int.init), id > 0 else { self = .today; return }
            let event = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "event" }?.value
            self = .player(id, event: event)
        default: self = .today
        }
    }
}

/// Which tab is showing and which player sheet is open, so links and taps anywhere can drive them.
@MainActor
@Observable
final class Router {
    var selectedTab: AppTab = .today
    var presentedPlayer: PlayerRef?
    /// Opens the alert history on the Watch tab (from a bundled notification).
    var showingAlerts = false

    func open(_ link: DeepLink) {
        switch link {
        case .today: selectedTab = .today
        case .team: selectedTab = .team
        case .watch: selectedTab = .watch
        case .alerts:
            selectedTab = .watch
            showingAlerts = true
        case .player(let id, let event): presentedPlayer = PlayerRef(id: id, fromAlert: event != nil)
        }
    }

    func openPlayer(_ id: Int) {
        presentedPlayer = PlayerRef(id: id)
    }
}
