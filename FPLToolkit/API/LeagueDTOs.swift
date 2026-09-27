import Foundation

/// Mini-leagues (Phase 2b, P2-10): the shapes of `/leagues…` (happy-backend-pal#21). Every number
/// comes from the website's league model on the server.
struct LeagueMeta: Decodable, Sendable, Hashable {
    let id: Int
    let name: String
    /// The always-available anonymous Elite 100 cohort.
    let isElite: Bool
    let managers: Int?
    /// Managers we track (the top 150).
    let tracked: Int
    let syncedGw: Int?
    let lastSyncedAt: String?
}

struct LeagueList: Decodable, Sendable {
    struct League: Decodable, Sendable, Hashable, Identifiable {
        let id: Int
        let name: String
        let isElite: Bool
        let managers: Int?
        let tracked: Int
        let syncedGw: Int?
        let synced: Bool
        let myRank: Int?
        let gapToFirst: Int?
    }
    struct SharedRival: Decodable, Sendable, Hashable, Identifiable {
        struct Membership: Decodable, Sendable, Hashable {
            let id: Int
            let name: String
            let rank: Int?
            let total: Int?
        }
        let entryId: Int
        let name: String
        let leagues: [Membership]
        var id: Int { entryId }
    }
    let leagues: [League]
    let sharedRivals: [SharedRival]
    let max: Int
}

struct LeagueManager: Decodable, Sendable, Hashable {
    let entryId: Int
    let teamName: String?
    let managerName: String?
    let rank: Int?
    let total: Int?
    /// The manager's name, else the team's, as the website shows it.
    var displayName: String { managerName ?? teamName ?? "Manager \(entryId)" }
}

struct LeagueIntel: Decodable, Sendable, Hashable, Identifiable {
    let playerId: Int
    let score: Int
    /// "Very high", "High", "Medium" or "Low".
    let band: String
    let eo: Double
    let leagueOwnPct: Double
    let globalPct: Double
    let gapPp: Double
    var id: Int { playerId }
}

struct LeagueRival: Decodable, Sendable, Hashable, Identifiable {
    let entryId: Int
    let teamName: String?
    let managerName: String?
    let rank: Int?
    let total: Int?
    /// Their total minus yours (positive: they're ahead).
    let pointsDiff: Int
    let reasons: [String]
    let shared: Int
    let yourDifferences: [Int]
    let theirDifferences: [Int]
    var id: Int { entryId }
    var displayName: String { managerName ?? teamName ?? "Manager \(entryId)" }
}

struct LeagueOverview: Decodable, Sendable {
    struct Headline: Decodable, Sendable {
        struct Position: Decodable, Sendable { let rank: Int?; let of: Int; let behindFirst: Int? }
        struct Threat: Decodable, Sendable { let playerId: Int; let eo: Double }
        struct Differential: Decodable, Sendable { let playerId: Int; let leagueOwnPct: Double }
        struct Chips: Decodable, Sendable {
            struct Count: Decodable, Sendable, Hashable { let chip: String; let label: String; let count: Int }
            let total: Int
            let top: [Count]
        }
        let position: Position
        let similarityPct: Int?
        let biggestThreat: Threat?
        let bestDifferential: Differential?
        let chips: Chips
        let leader: LeagueManager?
    }
    let league: LeagueMeta
    let baseline: String
    let me: LeagueManager?
    let headline: Headline
    let threats: [LeagueIntel]
    let opportunities: [LeagueIntel]
    let rivals: [LeagueRival]
    let players: [String: PlayerSummary]
    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

struct LeagueChip: Decodable, Sendable, Hashable {
    let chip: String
    let label: String
    let gw: Int
}

struct LeagueStandings: Decodable, Sendable {
    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let entryId: Int
        let teamName: String?
        let managerName: String?
        let rank: Int?
        let total: Int?
        let lastRank: Int?
        let gwPoints: Int?
        let hits: Int
        let benchPoints: Int
        let value: Double?
        let chips: [LeagueChip]
        let captainId: Int?
        let isMe: Bool
        var id: Int { entryId }
    }
    let league: LeagueMeta
    let rows: [Row]
    let players: [String: PlayerSummary]
    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

struct LeagueVs: Decodable, Sendable {
    struct Pick: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let isCaptain: Bool
        let isVice: Bool
        var id: Int { playerId }
    }
    struct ChipLeft: Decodable, Sendable, Hashable { let chip: String; let label: String; let count: Int }
    struct Transfer: Decodable, Sendable, Hashable { let gw: Int; let out: Int; let `in`: Int }
    struct Them: Decodable, Sendable {
        let entryId: Int
        let teamName: String?
        let managerName: String?
        let rank: Int?
        let total: Int?
        let gwPoints: Int?
        let overallRank: Int?
        let value: Double?
        let transfers: Int
        let hits: Int
        let formation: String
        let starting: [Pick]
        let bench: [Pick]
        let chipsPlayed: [LeagueChip]
        let chipsLeft: [ChipLeft]
        let recentTransfers: [Transfer]
    }
    struct HeadToHead: Decodable, Sendable {
        let pointsGap: Int
        let gwGap: Int
        let shared: [Int]
        let yourDifferences: [Int]
        let theirDifferences: [Int]
        let myCaptainId: Int?
        let theirCaptainId: Int?
        let sameCaptain: Bool
    }
    let league: LeagueMeta
    let them: Them
    let headToHead: HeadToHead?
    let players: [String: PlayerSummary]
    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
    func name(_ id: Int?) -> String { id.flatMap { player($0)?.webName } ?? "—" }
}

/// Whose squad the league is compared with: your FPL team, or one of your planner drafts.
enum LeagueBaseline: Hashable, Sendable {
    case team
    case draft(id: String, name: String)

    var queryItems: [URLQueryItem] {
        switch self {
        case .team: [URLQueryItem(name: "baseline", value: "team")]
        case .draft(let id, _): [URLQueryItem(name: "baseline", value: "draft"), URLQueryItem(name: "draftId", value: id)]
        }
    }

    var label: String {
        switch self {
        case .team: "My FPL team"
        case .draft(_, let name): name
        }
    }
}

// MARK: - The remaining tabs (P2-10b, happy-backend-pal#23)

struct LeagueSimilar: Decodable, Sendable, Hashable {
    let manager: LeagueManager
    let similarity: Int
}

struct LeagueRivals: Decodable, Sendable {
    let league: LeagueMeta
    let rivals: [LeagueRival]
    let mostSimilar: [LeagueSimilar]
    let mostDifferent: [LeagueSimilar]
    let players: [String: PlayerSummary]
    func name(_ id: Int) -> String { players[String(id)]?.webName ?? "Player \(id)" }
}

struct LeaguePlayers: Decodable, Sendable {
    struct Template: Decodable, Sendable { let formation: String; let xi: [Int]; let bench: [Int]; let owned: Int; let similarityPct: Int? }
    struct Consensus: Decodable, Sendable, Hashable, Identifiable { let playerId: Int; let leaguePct: Double; let globalPct: Double; let gapPp: Double; var id: Int { playerId } }
    struct Captaincy: Decodable, Sendable, Hashable, Identifiable { let playerId: Int; let count: Int; let pct: Double; var id: Int { playerId } }
    struct Ownership: Decodable, Sendable, Hashable, Identifiable { let playerId: Int; let ownedPct: Double; let started: Int; let eo: Double; let globalPct: Double; var id: Int { playerId } }
    let league: LeagueMeta
    let threats: [LeagueIntel]
    let opportunities: [LeagueIntel]
    let template: Template
    let loves: [Consensus]
    let avoids: [Consensus]
    let captaincy: [Captaincy]
    let ownership: [Ownership]
    let players: [String: PlayerSummary]
    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
    func name(_ id: Int) -> String { player(id)?.webName ?? "Player \(id)" }
}

struct LeagueCaptains: Decodable, Sendable {
    struct Row: Decodable, Sendable, Hashable { let manager: LeagueManager; let captains: [Int?] }
    struct Trend: Decodable, Sendable, Hashable {
        struct Top: Decodable, Sendable, Hashable { let playerId: Int; let pct: Double }
        let gw: Int
        let total: Int
        let top: [Top]
    }
    let league: LeagueMeta
    let gws: [Int]
    let rows: [Row]
    let trend: [Trend]
    let players: [String: PlayerSummary]
    func name(_ id: Int?) -> String { id.flatMap { players[String($0)]?.webName } ?? "–" }
}

struct LeagueChips: Decodable, Sendable {
    struct Row: Decodable, Sendable, Hashable { let manager: LeagueManager; let remaining: [String: Int]; let used: [LeagueChip] }
    struct Usage: Decodable, Sendable, Hashable { let chip: String; let label: String; let used: Int; let left: Int }
    let league: LeagueMeta
    let rows: [Row]
    let usage: [Usage]
}

struct LeagueTransfers: Decodable, Sendable {
    struct Intel: Decodable, Sendable, Hashable, Identifiable {
        struct Counterpart: Decodable, Sendable, Hashable { let playerId: Int; let count: Int }
        struct Manager: Decodable, Sendable, Hashable { let entryId: Int; let name: String }
        let playerId: Int
        let count: Int
        let pct: Double
        let counterparts: [Counterpart]
        let managers: [Manager]
        var id: Int { playerId }
    }
    struct Trend: Decodable, Sendable, Hashable { let gw: Int; let transfers: Int; let managersActive: Int; let hits: Int }
    struct Feed: Decodable, Sendable, Hashable {
        struct Move: Decodable, Sendable, Hashable { let out: Int; let `in`: Int }
        struct Chip: Decodable, Sendable, Hashable { let chip: String; let label: String }
        let manager: LeagueManager
        let transfers: [Move]
        let cost: Int
        let chip: Chip?
    }
    let league: LeagueMeta
    let scope: String
    let gws: [Int]
    let total: Int
    let bought: [Intel]
    let sold: [Intel]
    let trend: [Trend]
    let feed: [Feed]
    let players: [String: PlayerSummary]
    func name(_ id: Int) -> String { players[String(id)]?.webName ?? "Player \(id)" }
}

struct LeagueHistory: Decodable, Sendable {
    struct Position: Decodable, Sendable, Hashable {
        struct Point: Decodable, Sendable, Hashable { let gw: Int; let rank: Int; let gapToLeader: Int }
        let manager: LeagueManager
        let points: [Point]
    }
    struct Performance: Decodable, Sendable, Hashable {
        struct Week: Decodable, Sendable, Hashable { let gw: Int; let points: Int }
        let manager: LeagueManager?
        let entryId: Int
        let avgPoints: Double
        let best: Week?
        let worst: Week?
        let transfers: Int
        let hitPoints: Int
        let benchPoints: Int
        let wastage: Int
    }
    let league: LeagueMeta
    let positions: [Position]
    let performance: [Performance]
}

struct LeagueReport: Decodable, Sendable {
    struct Manager: Decodable, Sendable, Hashable { let entryId: Int; let name: String; let team: String }
    struct Points: Decodable, Sendable, Hashable { let manager: Manager; let points: Int }
    struct Total: Decodable, Sendable, Hashable { let manager: Manager; let total: Int }
    struct Places: Decodable, Sendable, Hashable { let manager: Manager; let places: Int }
    struct Captain: Decodable, Sendable, Hashable { let manager: Manager; let playerId: Int; let points: Int }
    struct Hit: Decodable, Sendable, Hashable { let manager: Manager; let points: Int; let transfers: Int }
    struct Differential: Decodable, Sendable, Hashable { let playerId: Int; let points: Int; let owners: Int; let ownedPct: Double }
    struct ChipPlay: Decodable, Sendable, Hashable { let manager: Manager; let chip: String; let label: String }
    struct You: Decodable, Sendable, Hashable { let manager: Manager; let points: Int; let rank: Int?; let gapToLeader: Int }
    struct Body: Decodable, Sendable {
        let managers: Int
        let average: Double
        let winner: Points?
        let lowest: Points?
        let leader: Total?
        let climber: Places?
        let faller: Places?
        let bestCaptain: Captain?
        let worstCaptain: Captain?
        let worstBench: Points?
        let biggestHit: Hit?
        let bestDifferential: Differential?
        let chips: [ChipPlay]
        let you: You?
    }
    let league: LeagueMeta
    let gw: Int
    let gws: [Int]
    let report: Body
    /// The website's "Share report" text.
    let text: String
    let players: [String: PlayerSummary]
    func name(_ id: Int) -> String { players[String(id)]?.webName ?? "Player \(id)" }
}
