import Foundation

/// A figure as the website writes it.
struct ShownValue: Decodable, Sendable, Hashable {
    let value: Double
    let display: String
}

/// `GET /players/insights`: the website's player insights table (contract §17).
struct PlayerInsights: Decodable, Sendable {
    struct Column: Decodable, Sendable, Hashable, Identifiable {
        let key: String
        /// As the website heads it, e.g. "Pts", "xGI", "FDR6".
        let label: String
        let per90: Bool
        var id: String { key }
    }

    struct Sort: Decodable, Sendable {
        let key: String
        let dir: String
    }

    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let values: [String: ShownValue]
        var id: Int { playerId }
    }

    let gw: Int
    let fdrHorizon: Int
    let per90: Bool
    let sort: Sort
    let columns: [Column]
    /// The website's default columns, in its order.
    let shown: [String]
    let count: Int
    let rows: [Row]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
    func column(_ key: String) -> Column? { columns.first { $0.key == key } }
}

/// `GET /players/opportunity`: the website's differential opportunity map.
struct OpportunityMap: Decodable, Sendable {
    struct Metric: Decodable, Sendable, Hashable, Identifiable {
        let key: String
        let label: String
        let per90: Bool
        var id: String { key }
    }

    struct Filter: Decodable, Sendable {
        let position: String?
        let maxOwn: Int
        let minMins: Int
    }

    struct Point: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let own: Double
        let value: Double
        let minutes: Int
        let labelled: Bool
        var id: Int { playerId }
    }

    struct Top: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let value: Double
        let display: String
        var id: Int { playerId }
    }

    let metric: Metric
    let metrics: [Metric]
    let ownershipCeilings: [Int]
    let minuteFloors: [Int]
    let filter: Filter
    let medianOwnership: Double
    let medianValue: Double
    let points: [Point]
    let top: [Top]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /players/template`: the website's template team.
struct TemplateTeam: Decodable, Sendable {
    struct Player: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let price: Double
        let own: Double
        let points: Int
        let form: Double
        var id: Int { playerId }
    }

    let formation: String
    let cost: ShownValue
    let points: Int
    let averageOwnership: ShownValue
    let xi: [Player]
    let essential: [Player]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /players/injuries`: the website's injury list.
struct InjuryList: Decodable, Sendable {
    struct Counts: Decodable, Sendable {
        let flagged: Int
        let owned: Int
        let doubtful: Int
        let ruledOut: Int
    }

    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let price: Double
        let own: Double
        let chance: Int?
        let news: String?
        var id: Int { playerId }
    }

    struct Group: Decodable, Sendable, Identifiable {
        let key: String
        let label: String
        let blurb: String
        let rows: [Row]
        var id: String { key }
    }

    let counts: Counts
    let groups: [Group]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}
