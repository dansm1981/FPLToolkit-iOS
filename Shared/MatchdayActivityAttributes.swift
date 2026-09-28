import ActivityKit
import Foundation

/// The Matchday Live Activity (Phase 3, P3-4; tasks/phase-3.md §4.1): one for the whole team,
/// shared by the app (which starts and updates it) and the widget extension (which draws it).
/// Plain values only, so a push update can carry the same state later.
struct MatchdayActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// The score as it stands (FPL-recorded plus projected bonus).
        var points: Int
        var provisionalBonus: Int
        var playing: Int
        var toPlay: Int
        /// The single most relevant thing right now, worded by the server.
        var headline: String
        /// LiveTeam.Status raw value: upcoming, live, between, awaitingBonus, finished.
        var status: String
        var updatedAt: Date
    }

    var entryId: Int
    var gameweek: Int
}
