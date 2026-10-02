import Foundation

// MARK: - Rivals (happy-backend-pal#67; contract §35)

/// A rival as every screen shows them: the gap now and at the gameweek's start, and this
/// gameweek's net points. The server works out every figure and writes the lines; the app lays
/// them out. Positive gaps mean you're ahead.
struct RivalSummary: Decodable, Sendable, Hashable, Identifiable {
    enum State: String, FallbackDecodable {
        /// In one of your saved leagues.
        case ok
        /// In none of your saved leagues any more: no new data until one is added back.
        case notInLeagues
        /// Saved in an earlier season: may be someone else under that ID now.
        case otherSeason
        case unknown
        static let fallback = Self.unknown
    }

    struct League: Decodable, Sendable, Hashable, Identifiable {
        let id: Int
        let name: String
        let rank: Int?
    }

    let entryId: Int
    let manager: String?
    let team: String?
    let nickname: String?
    /// The nickname, else the manager's first name, else the team.
    let name: String
    let featured: Bool
    let state: State
    let leagues: [League]
    let gap: Int?
    let gapBefore: Int?
    let you: Int?
    let them: Int?
    let youBonus: Int
    let themBonus: Int
    /// "4 pts ahead of Andy".
    let gapText: String?
    /// "You've gained 7 this gameweek".
    let swingText: String?

    var id: Int { entryId }

    /// The manager and team under the name: both when a nickname stands in for them.
    var identity: String {
        var parts: [String] = []
        if nickname != nil, let manager { parts.append(manager) }
        if let team { parts.append(team) }
        return parts.joined(separator: " · ")
    }
}

/// `GET /rivals`, and the reply to adding, changing or removing one.
struct RivalsList: Decodable, Sendable {
    let season: String
    let gameweek: Int
    let status: LiveTeam.Status
    let max: Int
    /// Featured first, then in the order added.
    let rivals: [RivalSummary]

    var featured: RivalSummary? { rivals.first { $0.featured } }
    func contains(_ entryId: Int) -> Bool { rivals.contains { $0.entryId == entryId } }
}

/// `GET /rivals/candidates`: everyone in your saved leagues (not yourself, not the Elite 100).
struct RivalCandidates: Decodable, Sendable {
    struct Manager: Decodable, Sendable, Hashable, Identifiable {
        let entryId: Int
        let manager: String?
        let team: String?
        let name: String
        let leagues: [RivalSummary.League]
        let total: Int?
        let isRival: Bool
        var id: Int { entryId }
    }
    let managers: [Manager]
    let max: Int
    let count: Int
}

/// `GET /rivals/{entryId}`: one rival against you, from the same engine as the list.
struct RivalComparison: Decodable, Sendable {
    struct Side: Decodable, Sendable, Hashable {
        /// 0 benched (or subbed off), 1, 2 captain, 3 triple captain.
        let multiplier: Int
        let position: Int
        let isCaptain: Bool
        let isViceCaptain: Bool
        let autoSub: LiveTeam.Player.AutoSub?
    }

    struct PlayerRow: Decodable, Sendable, Hashable, Identifiable {
        enum Group: String, FallbackDecodable {
            /// Scores only for you / only for them.
            case yours, theirs
            /// For both, at different multipliers.
            case multiplier
            /// For both equally: cancels out.
            case shared
            /// For neither.
            case bench
            case unknown
            static let fallback = Self.unknown
        }
        let playerId: Int
        let group: Group
        let you: Side?
        let them: Side?
        let points: Int
        let provisionalBonus: Int
        let state: LiveTeam.Player.State
        let minutes: Int
        /// Recorded points × (your multiplier − theirs): positive helps you.
        let effect: Int
        /// "Matters more to Andy: ×1 v ×2".
        let note: String?
        var id: Int { playerId }
    }

    struct Teams: Decodable, Sendable {
        struct Summary: Decodable, Sendable, Hashable {
            let yours: Int
            let theirs: Int
            let multiplier: Int
            let shared: Int
        }
        let gameweek: Int
        let rows: [PlayerRow]
        let summary: Summary
        /// Automatic subs and captaincy can still change until the matches finish.
        let provisional: Bool
    }

    struct Captain: Decodable, Sendable, Hashable {
        let playerId: Int
        /// Points credited, the multiplier included.
        let points: Int
        let multiplier: Int
    }

    struct SideStats: Decodable, Sendable, Hashable {
        struct Positions: Decodable, Sendable, Hashable {
            let gk: Int
            let def: Int
            let mid: Int
            let fwd: Int
        }
        struct Chip: Decodable, Sendable, Hashable {
            let chip: String
            let label: String
            let gw: Int
        }
        let points: Int
        let transfers: Int
        let hits: Int
        /// Not counted (Bench Boost weeks left out).
        let bench: Int
        let chips: [Chip]
        let captainPoints: Int?
        let byPosition: Positions?
    }

    struct Stats: Decodable, Sendable, Hashable {
        enum Period: String, FallbackDecodable {
            case gw, last5, season
            case unknown
            static let fallback = Self.unknown
        }
        struct GapPoint: Decodable, Sendable, Hashable {
            let gw: Int
            let gap: Int
        }
        struct Outscored: Decodable, Sendable, Hashable {
            let won: Int
            let lost: Int
            let drawn: Int
            let of: Int
        }
        struct CaptainWeek: Decodable, Sendable, Hashable {
            let gw: Int
            let you: Captain?
            let them: Captain?
        }
        let period: Period
        let gameweeks: [Int]
        let you: SideStats
        let them: SideStats
        let gapStart: Int?
        let gapTrend: [GapPoint]
        let gapChange: Int?
        let outscored: Outscored
        /// Nil for the season: picks are kept for the last 6 gameweeks.
        let captains: [CaptainWeek]?
        let summary: String?
    }

    struct AllStats: Decodable, Sendable {
        /// Nil until both teams for this gameweek are synced.
        let gw: Stats?
        let last5: Stats
        let season: Stats
    }

    struct Chips: Decodable, Sendable, Hashable {
        let you: [String]
        let them: [String]
    }

    let season: String
    let gameweek: Int
    let status: LiveTeam.Status
    let rival: RivalSummary
    /// "Started GW6 3 behind".
    let startText: String?
    let explanation: String?
    let teams: Teams?
    let teamsNote: String?
    let stats: AllStats
    let chipsAvailable: Chips
    let players: [String: PlayerSummary]

    func player(_ id: Int?) -> PlayerSummary? { id.flatMap { players[String($0)] } }
}

/// `PUT /rivals/{entryId}` body: only what changes.
struct RivalPatch: Encodable, Sendable {
    var nickname: String??
    var featured: Bool?

    enum CodingKeys: String, CodingKey { case nickname, featured }

    // A cleared nickname is sent as null; one left alone isn't sent.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let nickname {
            if let value = nickname { try c.encode(value, forKey: .nickname) } else { try c.encodeNil(forKey: .nickname) }
        }
        try c.encodeIfPresent(featured, forKey: .featured)
    }
}
