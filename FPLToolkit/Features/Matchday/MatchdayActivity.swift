import ActivityKit
import Foundation

/// Starts, updates and ends the Matchday Live Activity (Phase 3, P3-4). Until the Apple membership
/// brings push updates, the app updates it whenever Matchday refreshes; a stale date after five
/// minutes lets iOS show it's out of date if the app stops (never claiming to be live when it
/// isn't).
@MainActor
enum MatchdayActivity {
    nonisolated static let staleAfter: TimeInterval = 5 * 60

    static var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    nonisolated static func running(entryId: Int) -> Activity<MatchdayActivityAttributes>? {
        Activity<MatchdayActivityAttributes>.activities.first {
            $0.attributes.entryId == entryId && $0.activityState == .active
        }
    }

    nonisolated static func state(_ live: LiveTeam, updated: Date?) -> MatchdayActivityAttributes.ContentState {
        .init(
            points: live.total.estimated,
            provisionalBonus: live.total.provisionalBonus,
            playing: live.playing,
            toPlay: live.toPlay,
            headline: live.headline?.text ?? "\(live.playing) playing · \(live.toPlay) to play",
            status: live.status.rawValue,
            updatedAt: updated ?? .now
        )
    }

    static func start(_ live: LiveTeam, entryId: Int, updated: Date?) throws {
        // One at a time: a new gameweek replaces any older one.
        for activity in Activity<MatchdayActivityAttributes>.activities where activity.attributes.entryId == entryId {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        _ = try Activity.request(
            attributes: MatchdayActivityAttributes(entryId: entryId, gameweek: live.gameweek),
            content: .init(state: state(live, updated: updated), staleDate: Date.now.addingTimeInterval(staleAfter)),
            pushType: nil
        )
    }

    /// Brings a running activity up to date; ends it an hour after FPL confirms the gameweek.
    nonisolated static func update(_ live: LiveTeam, entryId: Int, updated: Date?) async {
        guard let activity = running(entryId: entryId), activity.attributes.gameweek == live.gameweek else { return }
        let content = ActivityContent(state: state(live, updated: updated), staleDate: Date.now.addingTimeInterval(staleAfter))
        if live.status == .finished {
            await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(60 * 60)))
        } else {
            await activity.update(content)
        }
    }

    nonisolated static func stop(entryId: Int) async {
        for activity in Activity<MatchdayActivityAttributes>.activities where activity.attributes.entryId == entryId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
