import Foundation
import Observation

/// The tabs (Dan, 4 Oct): Team and Planner are one Planner tab, plans on top and your current team
/// below; Projections has the freed place.
enum AppTab: Hashable {
    case today, planner, projections, research, watch
}

/// The Planner tab's two parts, for links that land on one of them.
enum PlannerSection: Hashable {
    case plans, team
}

/// `fpltoolkit://` links (§5). Unknown links open Today.
enum DeepLink: Equatable {
    case today
    case team
    case planner
    case projections
    case research
    case watch
    case alerts
    /// Matchday (Phase 3): `fpltoolkit://matchday`, also where the Live Activity opens. A matchday
    /// alert adds `?item=<feed item>`, the moment it's about (Matchday v2 item 10).
    case matchday(item: String? = nil)
    /// The Deadline reveal (tasks/deadline-reveal.md): `fpltoolkit://reveal`, from its push.
    case reveal
    /// `event` is set when the link came from an alert (notifications.md §6).
    case player(Int, event: String? = nil)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "fpltoolkit" else { return nil }
        let host = url.host()?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "team": self = .team
        case "planner": self = .planner
        case "projections": self = .projections
        case "research": self = .research
        case "watch": self = parts.first?.lowercased() == "alerts" ? .alerts : .watch
        case "reveal": self = .reveal
        case "matchday":
            self = .matchday(item: URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "item" }?.value)
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
    /// Matchday, over whichever tab is showing.
    var showingMatchday = false
    /// The feed item a matchday alert was about: Matchday opens its feed there, then clears it.
    var matchdayFocus: String?
    /// The Deadline reveal, opened over Matchday; Matchday clears it.
    var revealRequested = false
    /// A draft to open on the Planner tab (Today's "Continue your plan"); the Planner clears it.
    var pendingDraftId: String?
    /// The part of the Planner tab to scroll to when it next shows; the Planner clears it.
    var pendingPlannerSection: PlannerSection?

    /// Your current team, on the Planner tab below your plans.
    func openTeam() {
        selectedTab = .planner
        pendingPlannerSection = .team
    }

    /// Your plans, at the top of the Planner tab.
    func openPlans() {
        selectedTab = .planner
        pendingPlannerSection = .plans
    }

    func open(_ link: DeepLink) {
        switch link {
        case .today: selectedTab = .today
        case .team: openTeam()
        case .planner: openPlans()
        case .projections: selectedTab = .projections
        case .research: selectedTab = .research
        case .watch: selectedTab = .watch
        case .alerts:
            selectedTab = .watch
            showingAlerts = true
        case .matchday(let item):
            matchdayFocus = item
            showingMatchday = true
        case .reveal:
            revealRequested = true
            showingMatchday = true
        case .player(let id, let event): presentedPlayer = PlayerRef(id: id, fromAlert: event != nil)
        }
    }

    func openPlayer(_ id: Int) {
        presentedPlayer = PlayerRef(id: id)
    }
}
