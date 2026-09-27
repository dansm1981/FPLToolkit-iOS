import Foundation

/// One player in a market list: the website's market figures (contract §16).
struct MarketRow: Decodable, Sendable, Hashable, Identifiable {
    let playerId: Int
    /// £m.
    let price: Double
    /// £m: the confirmed change on the day, or against the previous snapshot.
    let dayPrice: Double
    let seasonPrice: Double
    /// Selected by, %.
    let own: Double
    /// Percentage points against the previous snapshot.
    let dayOwn: Double
    /// Percentage points over about a week.
    let weekOwn: Double
    let transfersIn: Int
    let transfersOut: Int
    let net: Int
    var id: Int { playerId }
}

/// `GET /market/changes`: the website's confirmed price changes.
struct MarketChanges: Decodable, Sendable {
    /// Days with a confirmed change, newest first (YYYY-MM-DD).
    let days: [String]
    let day: String?
    let latest: Bool
    let risers: [MarketRow]
    let fallers: [MarketRow]
    let risersCount: Int
    let fallersCount: Int
    let seasonRisers: [MarketRow]
    let seasonFallers: [MarketRow]
    let seasonRisersCount: Int
    let seasonFallersCount: Int
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /market/predictions`: FPL's own figures for the players nearest a change.
struct MarketPredictions: Decodable, Sendable {
    struct Night: Decodable, Sendable, Hashable {
        let offset: Int
        let projected: Double?
        /// As the website writes it, e.g. "100.5%".
        let display: String
        /// FPL's likelihood, out of 5.
        let likelihood: Int?
    }

    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let price: Double
        let own: Double
        /// Progress towards the next change, -100 to 100.
        let progress: Double
        let progressDisplay: String
        let hourly: Double?
        let nights: [Night]
        /// The database timestamp; screens show `lockedDisplay`.
        let lockedUntil: String?
        /// "Mon 01:30", UK time, as the website writes it.
        let lockedDisplay: String?
        let calibrating: Bool
        var id: Int { playerId }
    }

    let tracked: Int
    let headingUp: Int
    let headingDown: Int
    let locked: Int
    let risers: [Row]
    let fallers: [Row]
    let risersCount: Int
    let fallersCount: Int
    /// The first player row's own timestamp, as the website reads it (not shown: the response
    /// metadata carries the price sync's freshness).
    let updatedAt: String?
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /market/trends`: the website's price and transfer trends.
struct MarketTrends: Decodable, Sendable {
    struct Row: Decodable, Sendable, Hashable, Identifiable {
        enum Band: String, FallbackDecodable {
            case rising, stable, falling
            case watchUp = "watch-up"
            case watchDown = "watch-down"
            case unknown
            static let fallback = Self.unknown
        }

        let playerId: Int
        let price: Double
        let dayPrice: Double?
        let seasonPrice: Double
        let own: Double
        let dayOwn: Double?
        let net: Int
        let dayNet: Int?
        /// 0–100; 50 is stable.
        let likelihood: Int
        let band: Band
        let bandLabel: String
        /// From gameweek-to-date flow rather than today's.
        let estimated: Bool
        /// Recent daily prices, oldest first, ending with today's.
        let history: [Double]
        var id: Int { playerId }
    }

    let snapshotDays: Int
    let latestSnapshot: String?
    let hasDaily: Bool
    let risers: [Row]
    let fallers: [Row]
    let risersCount: Int
    let fallersCount: Int
    let upFlow: [Row]
    let downFlow: [Row]
    let count: Int
    let rows: [Row]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /market/transfers`: the website's transfers and ownership hubs.
struct MarketTransfers: Decodable, Sendable {
    let gw: Int?
    let bought: [MarketRow]
    let sold: [MarketRow]
    let net: [MarketRow]
    let mostOwned: [MarketRow]
    let byPosition: [String: [MarketRow]]
    let ownershipRisers: [MarketRow]
    let ownershipFallers: [MarketRow]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}
