import Foundation

// MARK: - Expected stats (happy-backend-pal#73; Dan, 3 Oct 2026)

enum ExpectedWindow: String, CaseIterable, Identifiable, Sendable {
    case season, last5, last10
    var id: String { rawValue }
    var label: String {
        switch self {
        case .season: "Season"
        case .last5: "Last 5"
        case .last10: "Last 10"
        }
    }
}

enum ExpectedVenue: String, CaseIterable, Identifiable, Sendable {
    case all, home, away
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "Overall"
        case .home: "Home"
        case .away: "Away"
        }
    }
}

/// `GET /research/expected-teams`: each club's results beside its xG and xGA (FPL's per-match
/// figures, from Opta), ranked by points, goal difference, goals.
struct ExpectedTeams: Decodable, Sendable {
    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let rank: Int
        let teamId: Int
        let played: Int
        let won: Int
        let drawn: Int
        let lost: Int
        let goals: Int
        let against: Int
        let points: Int
        let xg: Double
        let xga: Double
        /// Goals minus xG: positive is finishing above the chances.
        let goalsVsXg: Double
        /// Conceded minus xGA: positive is conceding more than the chances allowed.
        let againstVsXga: Double
        var id: Int { teamId }
    }
    let window: String
    let venue: String
    let rows: [Row]
}

/// `GET /research/expected-players`: goals, assists, xG and xA over a window, filtered and sorted.
struct ExpectedPlayers: Decodable, Sendable {
    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let apps: Int
        let minutes: Int
        let goals: Int
        let assists: Int
        let xg: Double
        let xa: Double
        let xgi: Double
        let goalsVsXg: Double
        let assistsVsXa: Double
        /// Nil under 90 minutes.
        let xg90: Double?
        let xa90: Double?
        let xgi90: Double?
        var id: Int { playerId }
    }
    let window: String
    let gameweeks: [Int]
    let total: Int
    let rows: [Row]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}
