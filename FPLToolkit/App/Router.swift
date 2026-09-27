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
    case player(Int)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "fpltoolkit" else { return nil }
        let host = url.host()?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "team": self = .team
        case "watch": self = parts.first?.lowercased() == "alerts" ? .alerts : .watch
        case "player":
            guard let id = parts.first.flatMap(Int.init), id > 0 else { self = .today; return }
            self = .player(id)
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

    func open(_ link: DeepLink) {
        switch link {
        case .today: selectedTab = .today
        case .team: selectedTab = .team
        case .watch, .alerts: selectedTab = .watch
        case .player(let id): presentedPlayer = PlayerRef(id: id)
        }
    }

    func openPlayer(_ id: Int) {
        presentedPlayer = PlayerRef(id: id)
    }
}
