import Foundation

// Codable mirrors of docs/mobile/api-contract.md §2–§4 (v1).
// Unknown fields are ignored by Decodable; unknown enum values map to a fallback case.

// MARK: - Envelope

struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T
    let meta: Meta
}

struct Meta: Decodable, Sendable {
    let apiVersion: String
    let generatedAt: Date
    let freshness: [FreshnessSource]?
}

struct ErrorEnvelope: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let code: APIErrorCode
        let message: String
        let retryable: Bool
    }
    let error: Body
}

enum APIErrorCode: String, FallbackDecodable {
    case invalidEntryId = "invalid_entry_id"
    case entryNotFound = "entry_not_found"
    case invalidPlayerId = "invalid_player_id"
    case playerNotFound = "player_not_found"
    case rateLimited = "rate_limited"
    case upstreamUnavailable = "upstream_unavailable"
    case dataUnavailable = "data_unavailable"
    /// Device routes: the device isn't registered, or its secret is wrong.
    case unauthorized
    case invalidRequest = "invalid_request"
    /// Planner: not this device's draft.
    case draftNotFound = "draft_not_found"
    /// Planner: a rule refused the edit; the message says why.
    case invalidAction = "invalid_action"
    case tooManyDrafts = "too_many_drafts"
    case shortlistFull = "shortlist_full"
    case leagueNotFound = "league_not_found"
    case tooManyLeagues = "too_many_leagues"
    case `internal`
    case unknown
    static let fallback = Self.unknown
}

// MARK: - Freshness (§2.3)

struct FreshnessSource: Decodable, Sendable, Hashable {
    enum Kind: String, FallbackDecodable {
        case fplCore = "fpl_core"
        case availability
        case pricePredictions = "price_predictions"
        case picks, elite, xfdr, defcon
        case livePoints = "live_points", matchEvents = "match_events"
        case unknown
        static let fallback = Self.unknown
    }
    enum State: String, FallbackDecodable {
        case fresh, stale, unknown
        static let fallback = Self.unknown
    }

    let source: Kind
    let asOf: Date?
    /// Null for sources with no fixed age (picks, xfdr).
    let expectedMaxAgeSeconds: Int?
    let state: State
    let label: String?
}

// MARK: - Bootstrap (§3.1)

struct Bootstrap: Decodable, Sendable {
    struct Gameweek: Decodable, Sendable {
        let current: Int?
        let locked: Int
        let next: NextDeadline?
    }
    struct Club: Decodable, Sendable, Identifiable {
        let id: Int
        let name: String
        let shortName: String
        /// API-Football logo, relative to the API base (`images/clubs/{id}?v=…`); nil without one.
        let logo: String?
        /// Club colours as "#RRGGBB" (happy-backend-pal#42); nil for older servers or a club
        /// without an entry.
        let colors: Colors?

        struct Colors: Decodable, Sendable, Hashable {
            let primary: String
            let secondary: String
        }
    }
    struct Config: Decodable, Sendable {
        struct Features: Decodable, Sendable {
            let priceAlerts: Bool
            let availabilityAlerts: Bool
            let deadlineReminders: Bool
        }
        let minSupportedAppVersion: String
        let webBaseUrl: String
        let disclosure: String
        let features: Features
        /// API abilities the server offers (happy-backend-pal#43); nil from older servers.
        let capabilities: [String]?
    }

    let season: String
    let gameweek: Gameweek
    let clubs: [Club]
    let config: Config
}

struct NextDeadline: Decodable, Sendable, Hashable {
    let id: Int
    let deadline: Date
}

// MARK: - Players (§3.2)

enum Position: String, FallbackDecodable {
    case gk = "GK", def = "DEF", mid = "MID", fwd = "FWD"
    case unknown
    static let fallback = Self.unknown
}

struct PlayerSummary: Decodable, Sendable, Identifiable, Hashable {
    struct Availability: Decodable, Sendable, Hashable {
        enum Level: String, FallbackDecodable {
            case ok, doubt, out
            case unknown
            static let fallback = Self.unknown
        }
        /// FPL status letter (a, d, i, s, u, n). Kept as a string: display uses `level`.
        let code: String
        let level: Level
        let chanceNext: Int?
        let news: String?
    }

    let id: Int
    let webName: String
    /// API-Football photo, relative to the API base (`images/players/{id}?v=…`); nil without one.
    let photo: String?
    let clubId: Int
    let position: Position
    let price: Double
    let availability: Availability
    let selectedByPct: Double?
    let nextFixture: FixtureDifficulty?
    /// Present only when he's one yellow card from a ban (happy-backend-pal#51).
    var suspensionRisk: SuspensionRisk? = nil

    /// One yellow card from a Premier League ban: the server's reading of the rules.
    struct SuspensionRisk: Decodable, Sendable, Hashable {
        let yellowCards: Int
        let threshold: Int
        /// Nil when a commission decides.
        let banMatches: Int?
        /// League matches his club has before the cut-off; nil when there's none.
        let matchesLeft: Int?

        /// "4 yellows · ban at 5".
        var chip: String { "\(yellowCards) yellows · ban at \(threshold)" }

        /// "one yellow card from a 1-match ban, 14 matches before the cut-off".
        var spoken: String {
            let ban = banMatches.map { "a \($0)-match ban" } ?? "a ban set by a commission"
            let window = matchesLeft.map { ", \($0) matches before the cut-off" } ?? ""
            return "one yellow card from \(ban)\(window)"
        }
    }
}

struct FixtureDifficulty: Decodable, Sendable, Hashable {
    struct XFDR: Decodable, Sendable, Hashable {
        enum Lens: String, FallbackDecodable {
            case attack, match
            case cleanSheet = "clean_sheet"
            case unknown
            static let fallback = Self.unknown
        }
        enum Source: String, FallbackDecodable {
            case market, fpl
            case unknown
            static let fallback = Self.unknown
        }
        let value: Double
        let lens: Lens
        let source: Source
        /// The website's colour band, 1 (easiest) to 5 (hardest). Absent from older servers.
        let band: Int?
    }

    let gw: Int
    let blank: Bool
    let opponentClubId: Int?
    let home: Bool?
    let kickoff: Date?
    let xfdr: XFDR?
}

enum NoSnapshotReason: String, FallbackDecodable {
    case noPublishedTeamYet = "no_published_team_yet"
    case unknown
    static let fallback = Self.unknown
}

struct Entry: Decodable, Sendable, Hashable {
    let id: Int
    let name: String
    // FPL's entry summary (happy-backend-pal#44); nil from older servers or before any points.
    var manager: String?
    var overallRank: Int?
    var totalPoints: Int?
    var summaryGw: Int?
    var gwPoints: Int?
    var gwRank: Int?
    /// Overall rank after the week before `summaryGw` (happy-backend-pal#46), for the up/down arrow.
    var previousOverallRank: Int?
}

// MARK: - Season history (happy-backend-pal#46)

/// An entry's season week by week, with each gameweek's FPL average and highest score.
struct SeasonHistory: Decodable, Sendable {
    struct Week: Decodable, Sendable, Hashable, Identifiable {
        let gw: Int
        let points: Int
        let totalPoints: Int
        let gwRank: Int?
        let overallRank: Int?
        let benchPoints: Int
        let transfers: Int
        /// Points deducted for extra transfers (positive, e.g. 4).
        let hitPoints: Int
        let value: Double?
        let bank: Double?
        /// "wildcard", "freehit", "bboost" or "3xc".
        let chip: String?
        let average: Int?
        let highest: Int?
        var id: Int { gw }
    }

    struct Past: Decodable, Sendable, Hashable {
        let season: String
        let totalPoints: Int
        let rank: Int?
    }

    let entryId: Int
    let weeks: [Week]
    let past: [Past]
}

// MARK: - Team (§3.2)

struct Team: Decodable, Sendable {
    struct Snapshot: Decodable, Sendable {
        let gw: Int
        let deadline: Date
        let kind: String
        let activeChip: String?
        /// Set when the locked GW used a Free Hit: the squad shown is the one it reverts to.
        let freeHitGw: Int?
        let bank: Double?
        let value: Double?
        let picks: [Pick]
    }
    struct Pick: Decodable, Sendable, Hashable {
        enum Role: String, FallbackDecodable {
            case starter, bench
            case unknown
            static let fallback = Self.unknown
        }
        let playerId: Int
        let slot: Int
        let role: Role
        let benchOrder: Int?
        let isCaptain: Bool
        let isViceCaptain: Bool
    }

    let entry: Entry
    let snapshot: Snapshot?
    let noSnapshotReason: NoSnapshotReason?
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

// MARK: - Today (§3.3)

struct Today: Decodable, Sendable {
    enum Status: String, FallbackDecodable {
        case attention, clear, unverified
        /// Never treat an unknown status as clear.
        static let fallback = Self.unverified
    }
    struct Snapshot: Decodable, Sendable, Hashable {
        let gw: Int
        let deadline: Date
        let freeHitGw: Int?
    }
    struct Gameweek: Decodable, Sendable {
        let next: NextDeadline?
    }

    let entry: Entry
    let snapshot: Snapshot?
    let noSnapshotReason: NoSnapshotReason?
    let gameweek: Gameweek
    let status: Status
    let attentionCount: Int
    let insights: [TeamInsight]
    let players: [String: PlayerSummary]
    /// Each squad player's daily transfers in and out, last 7 days, oldest first (Team news
    /// sparklines, happy-backend-pal#65); nil from servers before it.
    let transferTrends: [String: [TransferDay]]?

    /// One day's transfers for a player, from FPL's running totals.
    struct TransferDay: Decodable, Sendable, Hashable {
        let date: String
        let `in`: Int
        let out: Int
    }

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
    func transfers(_ id: Int) -> [TransferDay]? { transferTrends?[String(id)] }
    var attentionInsights: [TeamInsight] { insights.filter(\.needsAttention) }
}

// MARK: - Insights (§4.1)

struct TeamInsight: Decodable, Sendable, Identifiable, Hashable {
    enum Category: String, FallbackDecodable {
        case availability, price, minutes, elite, market, setpiece
        case other
        static let fallback = Self.other
    }
    enum Tone: String, FallbackDecodable {
        case bad, warn, good, info
        static let fallback = Self.info
    }

    let id: String
    let playerId: Int
    let category: Category
    let severity: Int
    let tone: Tone
    let needsAttention: Bool
    let title: String
    let summary: String
    let supportingValue: SupportingValue?
    let sourceTimestamp: Date?
    let expiresAt: Date?
    let deepLink: String
}

struct SupportingValue: Decodable, Sendable, Hashable {
    enum Kind: String, FallbackDecodable {
        case chanceOfPlaying = "chance_of_playing"
        case priceProgress = "price_progress"
        case minutes
        case elitePct = "elite_pct"
        case netTransfers = "net_transfers"
        case unknown
        static let fallback = Self.unknown
    }
    enum Unit: String, FallbackDecodable {
        case percent = "%"
        case minutes = "min"
        case count
        case unknown
        static let fallback = Self.unknown
    }
    let kind: Kind
    let value: Double
    let unit: Unit
    let label: String
}

// MARK: - Player sheet (§3.4)

struct PlayerSheet: Decodable, Sendable {
    struct Player: Decodable, Sendable {
        let summary: PlayerSummary
        let firstName: String?
        let secondName: String?
        let form: Double?
        let pointsPerGame: Double?
        let totalPoints: Int
        let minutes: Int
        let newsAddedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case firstName, secondName, form, pointsPerGame, totalPoints, minutes, newsAddedAt
        }

        init(from decoder: Decoder) throws {
            summary = try PlayerSummary(from: decoder)
            let c = try decoder.container(keyedBy: CodingKeys.self)
            firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
            secondName = try c.decodeIfPresent(String.self, forKey: .secondName)
            form = try c.decodeIfPresent(Double.self, forKey: .form)
            pointsPerGame = try c.decodeIfPresent(Double.self, forKey: .pointsPerGame)
            totalPoints = try c.decode(Int.self, forKey: .totalPoints)
            minutes = try c.decode(Int.self, forKey: .minutes)
            newsAddedAt = try c.decodeIfPresent(Date.self, forKey: .newsAddedAt)
        }
    }
    struct Market: Decodable, Sendable {
        struct TrendPoint: Decodable, Sendable, Hashable {
            /// A calendar date ("2026-09-19"), not a timestamp.
            let date: String
            let selectedByPct: Double?
        }
        let selectedByPct: Double?
        let transfersInEvent: Int
        let transfersOutEvent: Int
        let ownershipChange7d: Double?
        let ownershipTrend7d: [TrendPoint]
    }
    struct PricePrediction: Decodable, Sendable {
        struct Projection: Decodable, Sendable, Hashable {
            let offset: Int
            let projectedPct: Double
            let likelihood: Double?
        }
        /// "% of threshold": never a probability.
        let progressPct: Double
        let hourlyRate: Double?
        let tonightPct: Double?
        let projections: [Projection]
        let lockedUntil: Date?
        let calibrating: Bool
    }
    struct Elite: Decodable, Sendable {
        let gw: Int
        let cohortSize: Int
        let ownedPct: Double
        let captainPct: Double
        let boughtPct: Double
        let soldPct: Double
    }
    struct Defcon: Decodable, Sendable {
        let threshold: Int
        let starts: Int
        let hits: Int
        let hitRateStarts: Double
        let dcPer90: Double
    }
    struct Links: Decodable, Sendable {
        let web: String
    }

    let player: Player
    let insights: [TeamInsight]
    let fixtures: [FixtureDifficulty]
    let market: Market
    let pricePrediction: PricePrediction?
    let elite: Elite?
    let defcon: Defcon?
    let links: Links
}

// MARK: - Player search (GET /players/search?q=…)

struct PlayerSearchResult: Decodable, Sendable {
    let query: String
    let players: [PlayerSummary]
}

// MARK: - Device and watch (§6, as built in Step 1)

struct DeviceRegistration: Decodable, Sendable {
    let deviceId: String
    let deviceSecret: String
}

/// Notification preferences (contract §12.3). Device-local quiet hours; start == end means none.
struct DevicePrefs: Codable, Sendable, Equatable {
    struct Notifications: Codable, Sendable, Equatable {
        var price: Bool
        var availability: Bool
        var deadline24h: Bool
        var deadline3h: Bool
    }
    struct QuietHours: Codable, Sendable, Equatable {
        var start: String
        var end: String
    }
    var notifications: Notifications
    var quietHours: QuietHours
    var autoTrackSquad: Bool
    /// Matchday's players to watch (happy-backend-pal#66); nil from servers before it.
    var matchday: MatchdayPrefs?

    /// Which players Matchday shows beside your own team, and how many mini-league rivals.
    struct MatchdayPrefs: Codable, Sendable, Equatable {
        var highlyOwned: Bool
        var eliteDifferentials: Bool
        var rivals: Bool
        var rivalsLeague: Int?
        var rivalsAbove: Int
        var rivalsBelow: Int
        var rivalsLeader: Bool
        var inFeed: Bool

        /// Rivals above or below you, at most (the server clamps to the same).
        static let maxEachSide = 5

        /// The server's defaults: highly owned only, two rivals each side and the leader.
        static let standard = MatchdayPrefs(highlyOwned: true, eliteDifferentials: false, rivals: false,
                                            rivalsLeague: nil, rivalsAbove: 2, rivalsBelow: 2,
                                            rivalsLeader: true, inFeed: true)

        enum CodingKeys: String, CodingKey {
            case highlyOwned, eliteDifferentials, rivals, rivalsLeague, rivalsAbove, rivalsBelow, rivalsLeader, inFeed
        }

        // The league is sent as null when cleared, not left out.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(highlyOwned, forKey: .highlyOwned)
            try c.encode(eliteDifferentials, forKey: .eliteDifferentials)
            try c.encode(rivals, forKey: .rivals)
            if let rivalsLeague { try c.encode(rivalsLeague, forKey: .rivalsLeague) } else { try c.encodeNil(forKey: .rivalsLeague) }
            try c.encode(rivalsAbove, forKey: .rivalsAbove)
            try c.encode(rivalsBelow, forKey: .rivalsBelow)
            try c.encode(rivalsLeader, forKey: .rivalsLeader)
            try c.encode(inFeed, forKey: .inFeed)
        }
    }
}

struct DeviceInfo: Decodable, Sendable {
    let id: String
    let entryId: Int?
    let apnsRegistered: Bool
    let timeZone: String?
    let appVersion: String?
    let prefs: DevicePrefs?
}

/// `PUT /devices/me`. Only the fields that are set are sent.
struct DeviceUpdate: Encodable, Sendable {
    /// The notification part of prefs only, so the watch list's squad toggle is never overwritten.
    struct PrefsPatch: Encodable, Sendable {
        var notifications: DevicePrefs.Notifications?
        var quietHours: DevicePrefs.QuietHours?
        var matchday: DevicePrefs.MatchdayPrefs?
    }

    var entryId: Int??
    var timeZone: String?
    var appVersion: String?
    /// `.some(nil)` clears the token (notifications turned off).
    var apnsToken: String??
    var apnsEnvironment: String?
    var prefs: PrefsPatch?

    private enum CodingKeys: String, CodingKey { case entryId, timeZone, appVersion, apnsToken, apnsEnvironment, prefs }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let entryId {
            // .some(nil) sends an explicit null: "no team".
            if let id = entryId { try c.encode(id, forKey: .entryId) } else { try c.encodeNil(forKey: .entryId) }
        }
        if let apnsToken {
            if let token = apnsToken { try c.encode(token, forKey: .apnsToken) } else { try c.encodeNil(forKey: .apnsToken) }
        }
        try c.encodeIfPresent(timeZone, forKey: .timeZone)
        try c.encodeIfPresent(appVersion, forKey: .appVersion)
        try c.encodeIfPresent(apnsEnvironment, forKey: .apnsEnvironment)
        try c.encodeIfPresent(prefs, forKey: .prefs)
    }
}

/// One entry in the alert history (contract §12.4): what was sent, held or not sent, and why.
struct AlertItem: Decodable, Sendable, Identifiable, Hashable {
    enum Category: String, FallbackDecodable {
        case price, availability, deadline
        case other
        static let fallback = Self.other
    }
    enum Status: String, FallbackDecodable {
        case sent, deferred, suppressed, superseded, failed, queued
        case unknown
        static let fallback = Self.unknown
    }

    let eventKey: String
    let category: Category
    let playerId: Int?
    let gameweek: Int?
    let title: String
    let body: String
    let status: Status
    let reason: String?
    let detectedAt: Date
    let sentAt: Date?
    let expiresAt: Date
    let deepLink: String

    var id: String { eventKey }
}

struct AlertHistory: Decodable, Sendable {
    let alerts: [AlertItem]
}

/// The effective watch set is computed by the server: manual ∪ (autoTrackSquad ? squad : ∅).
struct Watch: Decodable, Sendable {
    struct Squad: Decodable, Sendable {
        let entryId: Int
        let gw: Int
        let freeHitGw: Int?
        let playerIds: [Int]
    }
    struct Item: Decodable, Sendable, Hashable, Identifiable {
        enum Reason: String, FallbackDecodable {
            case squad, manual
            case unknown
            static let fallback = Self.unknown
        }
        /// Price-change progress, the same numbers as the player page (§12.6).
        struct Price: Decodable, Sendable, Hashable {
            let progressPct: Double?
            let tonightPct: Double?
        }
        let playerId: Int
        let reasons: [Reason]
        // Added in §12.6; absent from older servers, so all optional.
        let needsAttention: Bool?
        /// The player's most important current note, by the same rules as Today.
        let topInsight: TeamInsight?
        let price: Price?
        /// Percentage-point change in ownership over 7 days; nil when there isn't enough history.
        let ownershipChange7d: Double?
        var id: Int { playerId }
    }

    let autoTrackSquad: Bool
    let manual: [Int]
    let squad: Squad?
    let effective: [Item]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
    func isManual(_ playerId: Int) -> Bool { manual.contains(playerId) }
    func reasons(for playerId: Int) -> [Item.Reason] {
        effective.first { $0.playerId == playerId }?.reasons ?? []
    }
}

struct WatchUpdate: Encodable, Sendable {
    let manual: [Int]
    let autoTrackSquad: Bool?
}

struct DeleteResult: Decodable, Sendable {
    let deleted: Bool
}

// MARK: - Fallback enums

/// A string enum that decodes unknown raw values to `fallback` instead of failing,
/// so additive v1 changes (new enum values) never break the app.
protocol FallbackDecodable: RawRepresentable, Decodable, Sendable, Hashable where RawValue == String {
    static var fallback: Self { get }
}

extension FallbackDecodable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
}

// MARK: - A player in your mini-leagues (happy-backend-pal#48)

struct PlayerLeagues: Decodable, Sendable {
    struct Row: Decodable, Sendable, Identifiable, Hashable {
        struct League: Decodable, Sendable, Hashable {
            let id: Int
            let name: String
            let syncedGw: Int?
        }
        let league: League
        /// Managers counted (those with picks for the league's synced gameweek).
        let counted: Int
        let ownedPct: Double
        let startedPct: Double
        let captainedPct: Double
        /// Effective ownership: starts plus captain shares.
        let eo: Double
        var id: Int { league.id }
    }

    /// Your rivals who have him in their latest synced team (happy-backend-pal#67).
    struct Rival: Decodable, Sendable, Identifiable, Hashable {
        let entryId: Int
        let name: String
        let started: Bool
        let captain: Bool
        let gameweek: Int
        var id: Int { entryId }
    }

    let playerId: Int
    let leagues: [Row]
    /// Nil from servers before happy-backend-pal#67.
    let rivals: [Rival]?
}
