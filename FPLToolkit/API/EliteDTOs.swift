import Foundation

/// `GET /elite/{page}?gw=`: one of the website's Elite pages for a gameweek (contract §19). Figures
/// come as the website writes them. `body` is nil when nothing is published for `gw` yet.
struct ElitePage<Body: Decodable & Sendable>: Decodable, Sendable {
    /// The gameweek shown: the one asked for when it's published, else the newest. 0 before any.
    let gw: Int
    /// Published gameweeks, newest first.
    let gameweeks: [Int]
    let body: Body?
    let players: [String: PlayerSummary]

    private enum CodingKeys: String, CodingKey { case gw, gameweeks, published, players }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gw = try c.decode(Int.self, forKey: .gw)
        gameweeks = try c.decode([Int].self, forKey: .gameweeks)
        players = try c.decodeIfPresent([String: PlayerSummary].self, forKey: .players) ?? [:]
        body = try c.decode(Bool.self, forKey: .published) ? Body(from: decoder) : nil
    }

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// One of the website's stat tiles.
struct EliteStat: Decodable, Sendable, Hashable {
    let label: String
    let value: String
    let sub: String?
    let accent: Bool
}

/// A change in percentage points. `display` is the website's figure without its arrow.
struct EliteChange: Decodable, Sendable, Hashable {
    let value: Double
    let display: String

    /// "+2.0pp", "−9.0pp", or "—" for none.
    var shown: String { value > 0 ? "+\(display)" : value < 0 ? "−\(display)" : display }
    var spoken: String { value > 0 ? "up \(display)" : value < 0 ? "down \(display)" : "no change" }
}

/// A player with a share of the cohort, e.g. "36%" bought.
struct EliteShareRow: Decodable, Sendable, Hashable, Identifiable {
    let playerId: Int
    let value: Double
    let display: String
    let change: EliteChange?
    /// "conviction 99%", "owned 82%", "£4.5m · start 42%".
    let detail: String?
    var id: Int { playerId }
}

struct EliteChangeRow: Decodable, Sendable, Hashable, Identifiable {
    let playerId: Int
    let change: EliteChange
    var id: Int { playerId }
}

/// A player and one figure, e.g. a vice-captain's share.
struct EliteFigureRow: Decodable, Sendable, Hashable, Identifiable {
    let playerId: Int
    let display: String
    var id: Int { playerId }
}

struct EliteTemplatePick: Decodable, Sendable, Hashable, Identifiable {
    let playerId: Int
    let position: Position
    let starting: Bool
    let owned: ShownValue
    let start: String
    /// Nil when nobody captains him.
    let captain: String?
    let price: String
    var id: Int { playerId }
}

struct ElitePitch: Decodable, Sendable, Hashable {
    /// Goalkeeper, defenders, midfielders, forwards: most owned first.
    let rows: [[EliteTemplatePick]]
    let bench: [EliteTemplatePick]
}

struct EliteOverview: Decodable, Sendable {
    struct Signal: Decodable, Sendable, Hashable, Identifiable {
        enum Tone: String, FallbackDecodable {
            case amber, red, green
            case unknown
            static let fallback = Self.unknown
        }
        let title: String
        let body: String
        let tone: Tone
        var id: String { title }
    }

    struct Edge: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let edge: String
        /// "57% vs 12%": elite against overall ownership.
        let detail: String
        var id: Int { playerId }
    }

    struct PositionSpend: Decodable, Sendable, Hashable, Identifiable {
        let position: Position
        let title: String
        let averageSpend: String
        let medianSpend: String
        let top: [EliteFigureRow]
        var id: String { position.rawValue }
    }

    struct Formation: Decodable, Sendable, Hashable, Identifiable {
        let formation: String
        let value: Double
        let display: String
        var id: String { formation }
    }

    let signals: [Signal]
    let snapshot: [EliteStat]
    let templateSummary: String?
    let pitch: ElitePitch
    let bought: [EliteShareRow]
    let sold: [EliteShareRow]
    let net: [EliteChangeRow]
    let mostOwned: [EliteShareRow]
    let favourites: [Edge]
    let avoids: [Edge]
    let captains: [EliteShareRow]
    let positions: [PositionSpend]
    let structure: [EliteStat]
    let formations: [Formation]
    let chips: [EliteStat]
    let rising: [EliteChangeRow]
    let cooling: [EliteChangeRow]
}

struct EliteOwnership: Decodable, Sendable {
    struct Filter: Decodable, Sendable, Hashable {
        let position: Position?
        let club: Int?
        let maxPrice: Double?
        let view: String
        let q: String
        let sort: String
        let dir: String
    }

    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let owned: ShownValue
        let start: String
        let bench: String
        let captain: String
        let overall: String
        let edge: String
        let change: EliteChange
        var id: Int { playerId }
    }

    let filter: Filter
    /// The price slider's top (£m): "any price" at or above it.
    let priceCap: Double
    let count: Int
    let rows: [Row]
}

struct EliteTransfers: Decodable, Sendable {
    struct Move: Decodable, Sendable, Hashable, Identifiable {
        let outId: Int
        let inId: Int
        let value: Double
        let display: String
        var id: String { "\(outId)-\(inId)" }
    }

    let stats: [EliteStat]
    let bought: [EliteShareRow]
    let sold: [EliteShareRow]
    let net: [EliteChangeRow]
    let moves: [Move]
}

struct EliteCaptaincy: Decodable, Sendable {
    let stats: [EliteStat]
    let captains: [EliteShareRow]
    let conviction: [EliteFigureRow]
    let vices: [EliteFigureRow]
}

struct EliteTemplate: Decodable, Sendable {
    struct Moved: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let owned: String
        let change: String
        var id: Int { playerId }
    }

    struct Changes: Decodable, Sendable, Hashable {
        let from: Int
        let movedIn: [Moved]
        let movedOut: [Moved]
    }

    struct Group: Decodable, Sendable, Hashable, Identifiable {
        let position: Position
        let title: String
        let rows: [EliteShareRow]
        var id: String { position.rawValue }
    }

    let consensus: String?
    let stats: [EliteStat]
    let pitch: ElitePitch
    /// Nil in the first gameweek.
    let changes: Changes?
    let positions: [Group]
}
