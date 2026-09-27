import Foundation

/// `GET /research/fixtures`: the website's fixture ticker, every club's run (contract §15).
struct ResearchTicker: Decodable, Sendable {
    enum SortKey: Hashable, Sendable, Decodable {
        case sum
        case gw(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let gw = try? container.decode(Int.self) { self = .gw(gw) } else { self = .sum }
        }

        var queryValue: String {
            switch self {
            case .sum: "sum"
            case .gw(let gw): String(gw)
            }
        }
    }

    struct Sort: Decodable, Sendable {
        let key: SortKey
        let dir: String
    }

    struct Fixture: Decodable, Sendable, Hashable {
        let opponentClubId: Int?
        let home: Bool
        let value: Double?
        /// As the website writes it: xFDR to one decimal place, FPL's difficulty whole.
        let display: String
        let band: Int?
        let source: String
        let fplValue: Int?
    }

    struct Cell: Decodable, Sendable, Hashable {
        let gw: Int
        let blank: Bool
        /// Left out of the total in Fuzzy mode.
        let ignored: Bool
        let fdr: Double
        let fixtures: [Fixture]
    }

    struct Row: Decodable, Sendable, Identifiable, Hashable {
        let clubId: Int
        let sum: Double
        let sumDisplay: String
        let cells: [Cell]
        var id: Int { clubId }
    }

    let gws: [Int]
    let fuzzy: Bool
    let dropCount: Int
    let lens: String
    let sort: Sort
    let rows: [Row]
}

/// `GET /research/rotation`: the website's rotation planner for 2–6 players.
struct ResearchRotation: Decodable, Sendable {
    struct Fixture: Decodable, Sendable, Hashable {
        let opponentClubId: Int?
        let home: Bool
        let value: Double?
    }

    struct Cell: Decodable, Sendable, Hashable {
        let playerId: Int
        let blank: Bool
        let fdr: Double?
        let band: Int?
        let starter: Bool
        let fixtures: [Fixture]
    }

    struct Week: Decodable, Sendable, Hashable {
        let gw: Int
        /// Best first: the first is the top pick.
        let starterIds: [Int]
        let cells: [Cell]
    }

    let fromGw: Int
    let horizon: Int
    let starters: Int
    let playerIds: [Int]
    let weeks: [Week]
    let rotationTotal: Double
    let bestSolo: Double
    let gain: Double
    let combinedCost: Double
    let startCounts: [String: Int]
    let soloTotals: [String: Double]
    /// The four figures as the website writes them.
    struct Display: Decodable, Sendable {
        let rotationTotal: String
        let bestSolo: String
        let gain: String
        let combinedCost: String
    }

    let blankWeeks: Int
    let display: Display
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /research/congestion`: every club's games and rest days around today.
struct ResearchCongestion: Decodable, Sendable {
    struct Match: Decodable, Sendable, Hashable {
        let kickoff: Date
        let home: Bool
        let opponent: String
        /// "Premier League", or the website's cup abbreviation (UCL, UEL, UECL, FAC, EFL).
        let competition: String
        let isLeague: Bool
    }

    struct Day: Decodable, Sendable, Hashable {
        let day: Int
        /// The length of the recovery block this empty day sits in.
        let gap: Int?
        /// The website's heat step: 0 (no game either side) to 7 (a day or less).
        let level: Int
        let matches: [Match]
    }

    struct Club: Decodable, Sendable, Identifiable, Hashable {
        let clubId: Int
        let count: Int
        let shortest: Int?
        let daysToNext: Int?
        let days: [Day]
        var id: Int { clubId }
    }

    struct GameweekDay: Decodable, Sendable, Hashable {
        let day: Int
        let gw: Int
    }

    struct Feed: Decodable, Sendable {
        let updatedAt: Date?
        let stale: Bool
    }

    let windowStart: Date
    let days: Int
    /// Each column's date, YYYY-MM-DD.
    let dates: [String]
    let todayIndex: Int
    let sort: String
    let gameweeks: [GameweekDay]
    let clubs: [Club]
    let missingCompetitions: [String]
    let feed: Feed
}
