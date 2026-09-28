import Foundation

/// `GET /deep-dives/hauls`: the website's /hauls (contract §22).
struct Hauls: Decodable, Sendable {
    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let hauls: Int
        let best: Int
        let returns: Int
        let appearances: Int
        let points: Int
        var id: Int { playerId }
    }

    let rows: [Row]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /deep-dives/consistency`: the website's /consistency.
struct Consistency: Decodable, Sendable {
    struct Row: Decodable, Sendable, Hashable, Identifiable {
        enum Tone: String, FallbackDecodable {
            case good, bad
            case neutral = "default"
            static let fallback = Self.neutral
        }
        let playerId: Int
        /// "67%": appearances returning 4+ points.
        let consistency: ShownValue
        let tone: Tone
        let goodGames: Int
        let appearances: Int
        let blanks: Int
        let hauls: Int
        let pointsPerGame: String
        var id: Int { playerId }
    }

    /// Fewer appearances and a player isn't ranked.
    let minApps: Int
    let rows: [Row]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /deep-dives/home-away`: the website's /home-away.
struct HomeAway: Decodable, Sendable {
    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let home: String
        let away: String
        /// Home minus away points per game, e.g. "+2.3".
        let diff: ShownValue
        let homeGames: Int
        let awayGames: Int
        var id: Int { playerId }
    }

    let count: Int
    let homeSpecialists: [Row]
    let travellers: [Row]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /deep-dives/records`: the website's /records.
struct SeasonRecords: Decodable, Sendable {
    struct Tile: Decodable, Sendable, Hashable {
        let label: String
        /// Nil for the price-change count, or before there's any data.
        let playerId: Int?
        let value: String
        let sub: String?
    }

    struct Score: Decodable, Sendable, Hashable {
        let playerId: Int
        let gameweek: Int
        let points: Int
        let goals: Int
        let assists: Int
        let bonus: Int
    }

    struct Count: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let count: Int
        var id: Int { playerId }
    }

    let tiles: [Tile]
    let topScores: [Score]
    let mostRises: [Count]
    let mostFalls: [Count]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}
