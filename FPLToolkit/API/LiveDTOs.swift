import Foundation

// MARK: - Live team (contract §24; happy-backend-pal#36, #37)

/// One team's live gameweek. Every judgement (score, substitutions, bonus, what's close) is the
/// server's; the app lays it out.
struct LiveTeam: Decodable, Sendable {
    enum Status: String, FallbackDecodable {
        case upcoming, live, between, awaitingBonus, finished
        case unknown
        static let fallback = Self.unknown
    }

    struct Total: Decodable, Sendable, Hashable {
        /// confirmed + provisionalBonus.
        let estimated: Int
        /// FPL-recorded points × multipliers − transfer cost.
        let confirmed: Int
        let provisionalBonus: Int
        let transferCost: Int
        let benchPoints: Int
    }

    struct NextPoints: Decodable, Sendable, Hashable {
        struct Defcon: Decodable, Sendable, Hashable {
            let count: Int
            let threshold: Int
            let reached: Bool
        }
        struct Saves: Decodable, Sendable, Hashable {
            let count: Int
            let toNextPoint: Int
        }
        struct Bonus: Decodable, Sendable, Hashable {
            let provisional: Int
            let bps: Int
            let bpsToNext: Int?
        }
        struct CleanSheet: Decodable, Sendable, Hashable {
            let conceded: Int
            let alive: Bool
        }
        let defcon: Defcon?
        let saves: Saves?
        let bonus: Bonus?
        let cleanSheet: CleanSheet?
    }

    struct Player: Decodable, Sendable, Identifiable, Hashable {
        enum State: String, FallbackDecodable {
            case blank, notStarted, inPlay, done
            case unknown
            static let fallback = Self.unknown
        }
        enum Lineup: String, FallbackDecodable {
            case starting, bench, notInSquad
            case unknown
            static let fallback = Self.unknown
        }
        enum AutoSub: String, FallbackDecodable {
            case `in`, out
            case unknown
            static let fallback = Self.unknown
        }
        struct Breakdown: Decodable, Sendable, Hashable {
            let fixtureId: Int
            let stat: String
            let value: Double
            let points: Int
        }
        /// FPL's counts for the gameweek (happy-backend-pal#47): everything the player did,
        /// points or not; a double gameweek adds both matches.
        struct Line: Decodable, Sendable, Hashable {
            let minutes: Int
            let goals: Int
            let assists: Int
            let cleanSheets: Int
            let goalsConceded: Int
            let ownGoals: Int
            let penaltiesSaved: Int
            let penaltiesMissed: Int
            let yellowCards: Int
            let redCards: Int
            let saves: Int
            let bonus: Int
            let bps: Int
            let defensiveContribution: Int
            let clearancesBlocksInterceptions: Int
            let recoveries: Int
            let tackles: Int
            let expectedGoals: Double
            let expectedAssists: Double
        }
        struct Context: Decodable, Sendable, Hashable {
            let rating: String?
            let shots: Int?
            let shotsOn: Int?
            let keyPasses: Int?
            let tackles: Int?
            let interceptions: Int?
            let saves: Int?
        }

        let playerId: Int
        /// 1–11 starting, 12–15 bench in order.
        let position: Int
        let counted: Bool
        let multiplier: Int
        let isCaptain: Bool
        let isViceCaptain: Bool
        let autoSub: AutoSub?
        let state: State
        let minutes: Int
        /// FPL-recorded.
        let points: Int
        /// Toolkit estimate, not yet in `points`.
        let provisionalBonus: Int
        /// Football context; nil while not yet reported.
        let lineup: Lineup?
        let fixtureIds: [Int]
        let next: NextPoints
        let breakdown: [Breakdown]
        /// Nil from servers before happy-backend-pal#47.
        let line: Line?
        let context: Context?

        var id: Int { playerId }
    }

    struct Fixture: Decodable, Sendable, Identifiable, Hashable {
        enum State: String, FallbackDecodable {
            case notStarted, inPlay, finished
            case unknown
            static let fallback = Self.unknown
        }
        let id: Int
        let homeClubId: Int
        let awayClubId: Int
        let kickoff: Date?
        let state: State
        let minute: Int?
        let homeScore: Int?
        let awayScore: Int?
        let bonusConfirmed: Bool
    }

    struct Moment: Decodable, Sendable, Identifiable, Hashable {
        enum Kind: String, FallbackDecodable {
            case goal, ownGoal, assist, penaltyMissed, redCard, subbedOff, subbedOn, defcon, cleanSheetLost, bonus
            case unknown
            static let fallback = Self.unknown
        }
        enum State: String, FallbackDecodable {
            case reported, confirmed, withdrawn
            case unknown
            static let fallback = Self.unknown
        }
        /// Stable across refreshes: the same event keeps its id when its state changes.
        let id: String
        let kind: Kind
        let fixtureId: Int
        let playerId: Int?
        let minute: Int?
        let state: State
        let players: [Int]?
        let points: Int?
    }

    /// One line of the live feed (happy-backend-pal#61; contract §32). The server writes the text,
    /// detail and points; the app only lays them out.
    struct FeedItem: Decodable, Sendable, Identifiable, Hashable {
        enum Kind: String, FallbackDecodable {
            case lineup, kickOff, halfTime, fullTime
            case goal, ownGoal, assist, penaltyMissed, penaltySaved, yellowCard, redCard
            case subbedOff, subbedOn
            case defcon, save, sixtyMinutes, cleanSheet, cleanSheetLost
            case bonusPosition, bonus
            case unknown
            static let fallback = Self.unknown
        }
        /// The app's filters; `match` items show under All only.
        enum Group: String, FallbackDecodable {
            case goals, defence, bonus, lineups, match
            case unknown
            static let fallback = Self.unknown
        }
        /// Stable across refreshes.
        let id: String
        let kind: Kind
        let group: Group
        let fixtureId: Int
        let playerId: Int?
        let minute: Int?
        let at: Date
        let state: Moment.State
        let text: String
        let detail: String?
        /// The points it's worth to the player (before the captain's multiplier); nil when none change.
        let points: Int?
        let players: [Int]?
        let lineup: Player.Lineup?
    }

    struct Headline: Decodable, Sendable, Hashable {
        let text: String
        let kind: String
    }

    struct Substitution: Decodable, Sendable, Hashable {
        let `in`: Int
        let out: Int
    }

    let entryId: Int
    let gameweek: Int
    let status: Status
    /// The single most relevant thing right now (the Lock Screen's second line); nil from servers
    /// before happy-backend-pal#39.
    let headline: Headline?
    let chip: String?
    let total: Total
    let captainId: Int?
    let playing: Int
    let toPlay: Int
    let autoSubs: [Substitution]
    let squad: [Player]
    let fixtures: [Fixture]
    let moments: [Moment]
    /// Everything that happened to the squad, newest first; nil from servers before
    /// happy-backend-pal#61 (Matchday then shows the moments).
    let feed: [FeedItem]?
    let players: [String: PlayerSummary]
    /// Only on a live matchday replay: what's being replayed and how far through it is.
    var replay: Replay?

    /// A replay's position (happy-backend-pal#58).
    struct Replay: Decodable, Sendable, Hashable {
        let id: String
        let label: String
        /// The moment shown, in the original matchday's time.
        let at: Date
        let elapsedSeconds: Int
        let durationSeconds: Int
    }

    func player(_ id: Int?) -> PlayerSummary? { id.flatMap { players[String($0)] } }
    func fixture(_ id: Int) -> Fixture? { fixtures.first { $0.id == id } }
}

// MARK: - One match's stats (happy-backend-pal#47)

/// A match's FPL tables for the Matches tab: most first in each list.
struct MatchStats: Decodable, Sendable {
    enum Side: String, FallbackDecodable {
        case home, away
        case unknown
        static let fallback = Self.unknown
    }

    struct Entry: Decodable, Sendable, Hashable {
        let playerId: Int
        let side: Side
        let value: Int
    }

    struct Defcon: Decodable, Sendable, Hashable {
        let playerId: Int
        let side: Side
        let value: Int
        let threshold: Int
        let reached: Bool
    }

    let fixtureId: Int
    let homeClubId: Int
    let awayClubId: Int
    let homeScore: Int?
    let awayScore: Int?
    let state: LiveTeam.Fixture.State
    let minute: Int?
    let goals: [Entry]
    let assists: [Entry]
    let ownGoals: [Entry]
    let penaltiesSaved: [Entry]
    let penaltiesMissed: [Entry]
    let yellowCards: [Entry]
    let redCards: [Entry]
    let saves: [Entry]
    /// FPL's bonus once added; before that the Toolkit's estimate from BPS.
    let bonus: [Entry]
    let bonusProvisional: Bool
    let bps: [Entry]
    /// Every outfield player with a DEFCON count, misses included.
    let defcon: [Defcon]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}
