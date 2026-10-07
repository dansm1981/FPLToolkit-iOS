import Foundation

/// One score convention everywhere (Matchday v2 item 10; Dan, 7 Oct 2026): lead with the live
/// score, FPL's recorded points plus the provisional bonus, and say what's in it underneath. Shared
/// by the app and the Lock Screen, so they read the same.
enum LiveScoreText {
    /// The unit beside the big number: "live pts" while bonus can still change, "pts" once final.
    nonisolated static func unit(status: String) -> String {
        switch status {
        case "live", "between", "awaitingBonus": "live pts"
        default: "pts"
        }
    }

    /// "52 confirmed + 3 estimated", "All confirmed by FPL so far", or "Final, confirmed by FPL".
    nonisolated static func breakdown(estimated: Int, provisionalBonus: Int, status: String) -> String {
        if status == "finished" { return "Final, confirmed by FPL" }
        if provisionalBonus > 0 {
            return "\(estimated - provisionalBonus) confirmed + \(provisionalBonus) estimated"
        }
        return "All confirmed by FPL so far"
    }

    /// The status words, the same on every screen.
    nonisolated static func status(_ status: String) -> String {
        switch status {
        case "upcoming": "Not started"
        case "live": "Live"
        case "between": "Between matches"
        case "awaitingBonus": "Awaiting bonus"
        case "finished": "Final"
        default: "Matchday"
        }
    }
}
