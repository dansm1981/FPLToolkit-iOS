import Foundation

/// `GET /players/{id}/{tab}`: the website's player page tabs, one at a time (contract §18). Rounded
/// figures come as the website writes them.
enum PlayerTab: String, CaseIterable, Identifiable, Sendable {
    case history, form, underlying, fixtures, price, defensive, compare
    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "Gameweek history"
        case .form: "Form trends"
        case .underlying: "Underlying stats"
        case .fixtures: "Fixtures"
        case .price: "Price and ownership"
        case .defensive: "DEFCON"
        case .compare: "Vs similar players"
        }
    }

    var detail: String {
        switch self {
        case .history: "Every gameweek's points, minutes and returns."
        case .form: "Rolling points, minutes and xGI, and starts."
        case .underlying: "xG, xA and ICT against the returns."
        case .fixtures: "The next ten fixtures and returns by difficulty."
        case .price: "Rises and falls, and daily ownership."
        case .defensive: "Defensive contributions match by match."
        case .compare: "Percentile ranks and alternatives at the price."
        }
    }

    var systemImage: String {
        switch self {
        case .history: "list.number"
        case .form: "chart.bar"
        case .underlying: "scope"
        case .fixtures: "calendar"
        case .price: "sterlingsign.circle"
        case .defensive: "shield.lefthalf.filled"
        case .compare: "person.2"
        }
    }
}

struct PlayerHistoryTab: Decodable, Sendable {
    struct Split: Decodable, Sendable { let points: Int; let minutes: Int }
    struct Best: Decodable, Sendable { let gameweek: Int?; let points: Int }
    struct Row: Decodable, Sendable, Hashable {
        let gw: Int?
        let opponentClubId: Int?
        let home: Bool
        let points: Int
        let minutes: Int
        let goals: Int
        let assists: Int
        let cleanSheets: Int
        let goalsConceded: Int
        let xg: String
        let xa: String
        let bonus: Int
        let bps: Int
        let price: String?
    }

    let appearances: Int
    let squadGameweeks: Int
    let hauls: Int
    let blanks: Int
    let best: Best?
    let home: Split
    let away: Split
    let rows: [Row]
}

struct PlayerFormTab: Decodable, Sendable {
    struct Window: Decodable, Sendable, Hashable {
        let last: Int
        let games: Int
        let ppg: String?
        let points: Int
        let minutes: Int
        let xgi: String
    }
    struct Bar: Decodable, Sendable, Hashable {
        enum Band: String, FallbackDecodable {
            case haul, good, ok, poor
            case unknown
            static let fallback = Self.unknown
        }
        let gw: Int?
        let points: Int
        let band: Band
    }

    let fplForm: String
    let startsLast6: Int
    let pointsPerGame: String
    let minutes: Int
    let starts: Int
    let windows: [Window]
    let bars: [Bar]
}

struct PlayerUnderlyingTab: Decodable, Sendable {
    struct Goals: Decodable, Sendable { let display: String; let goals: Int; let xg: String }
    struct Assists: Decodable, Sendable { let display: String; let assists: Int; let xa: String }
    struct Verdict: Decodable, Sendable { let tone: String; let text: String }
    struct Row: Decodable, Sendable, Hashable { let label: String; let total: String; let per90: String }

    let goalsVsXg: Goals
    let assistsVsXa: Assists
    let xgi90: String
    let minutes: Int
    let recentXgi: String
    let recentGames: Int
    let finishing: Verdict
    let meaningfulSample: Bool
    let rows: [Row]
}

struct PlayerFixturesTab: Decodable, Sendable {
    struct Upcoming: Decodable, Sendable, Hashable {
        let gw: Int?
        let opponentClubId: Int?
        let home: Bool
        let fdr: Int
        let kickoff: String?
    }
    struct Bucket: Decodable, Sendable, Hashable {
        let label: String
        let points: Int
        let games: Int
        let ppg: String?
    }

    let averageFdr: String?
    let easy: Int
    let hard: Int
    let upcoming: [Upcoming]
    let byDifficulty: [Bucket]
}

struct PlayerPriceTab: Decodable, Sendable {
    struct Event: Decodable, Sendable, Hashable {
        let date: String
        let direction: String
        let from: String
        let to: String
    }
    struct Snapshot: Decodable, Sendable, Hashable {
        let date: String
        let price: String
        let ownership: String
        let netTransfers: Int
    }

    let current: String
    let started: String
    let seasonChange: String
    let rises: Int
    let falls: Int
    let ownership: String
    let netTransfers: Int
    let events: [Event]
    let snapshots: [Snapshot]
}

struct PlayerDefensiveTab: Decodable, Sendable {
    struct Rank: Decodable, Sendable { let rank: Int; let of: Int }
    struct Match: Decodable, Sendable, Hashable {
        let gw: Int?
        let opponentClubId: Int?
        let home: Bool
        let fdr: Int?
        let minutes: Int
        let cbit: Int
        let tackles: Int
        let recoveries: Int
        let dc: Int
        let hit: Bool
        let nearMiss: Bool
        let short: Int?
        let points: Int
        let bonus: Int
    }

    let eligible: Bool
    let threshold: Int
    let hits: Int
    let starts: Int
    let appearances: Int
    let startHits: Int
    let hitStreak: Int
    let hitRateStarts: String?
    let dcPer90: String
    let dcTotal: Int
    let cbitPer90: String?
    let tackles: Int
    let recoveries: Int
    let gwRange: String
    let rank: Rank?
    let matches: [Match]
}

struct PlayerCompareTab: Decodable, Sendable {
    struct Rank: Decodable, Sendable, Hashable {
        let label: String
        let value: String
        let percentile: Int
        let ordinal: String
    }
    struct Peer: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let price: String
        let points: Int
        let form: String
        let xgi90: String
        let ownership: String
        var id: Int { playerId }
    }

    let played: Int
    let price: String
    let peersCount: Int
    let totalPoints: Int
    let pointsPerGame: String
    let ownership: String
    let ranks: [Rank]
    let peers: [Peer]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}
