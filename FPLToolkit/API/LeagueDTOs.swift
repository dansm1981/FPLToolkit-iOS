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
