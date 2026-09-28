import Foundation

/// `GET /defcon`: the website's DEFCON hub, summarised on the server (contract §21). Rounded
/// figures come as the website writes them.
struct Defcon: Decodable, Sendable {
    struct Filter: Decodable, Sendable, Hashable {
        /// DEF, MID or FWD; nil for all.
        let position: Position?
        let minStarts: Int
        /// £m; 0 for any price.
        let maxPrice: Double
        let sort: String
    }

    struct Choice: Decodable, Sendable, Hashable, Identifiable {
        let value: Double
        let label: String
        var id: Double { value }
    }

    struct SortChoice: Decodable, Sendable, Hashable, Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    struct Options: Decodable, Sendable, Hashable {
        let minStarts: [Int]
        let prices: [Choice]
        let sorts: [SortChoice]
    }

    struct Next: Decodable, Sendable, Hashable {
        let opponentClubId: Int
        let home: Bool
        /// FPL's difficulty for the player's club.
        let fdr: Int?
    }

    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let starts: Int
        /// Hits in starts.
        let startHits: Int
        /// "60%", or "—" with no starts.
        let hitRate: String
        let dcPer90: String
        let cbitPer90: String
        let minutes: Int
        let next: Next?
        var id: Int { playerId }
    }

    struct MapFilter: Decodable, Sendable, Hashable {
        let position: Position?
        let minStarts: Int
    }

    struct Point: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let position: Position
        /// Hit rate in starts, whole %.
        let hitRate: Int
        let dcPer90: Double
        let minutes: Int
        /// One of the six the website names on the chart.
        let labelled: Bool
        var id: Int { playerId }
    }

    struct Top: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        /// Every appearance's hits, as the website's list shows them.
        let hits: Int
        let starts: Int
        let hitRate: String
        var id: Int { playerId }
    }

    struct Map: Decodable, Sendable, Hashable {
        let filter: MapFilter
        let medianDcPer90: Double
        let points: [Point]
        let top: [Top]
    }

    struct ReliableRow: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let startHits: Int
        let starts: Int
        let hitRate: String
        let dcPer90: String
        var id: Int { playerId }
    }

    struct Reliable: Decodable, Sendable, Hashable {
        let minSample: Int
        let smallSample: Bool
        let answer: String
        let coverage: String
        let rows: [ReliableRow]
    }

    struct Leak: Decodable, Sendable, Hashable, Identifiable {
        let clubId: Int
        let defHitRate: String
        /// 30% or more, which the website picks out.
        let defHighlight: Bool
        let avgDcVsDef: String
        let attackHitRate: String
        let avgDcVsAttack: String
        var id: Int { clubId }
    }

    struct Tough: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let toughStarts: Int
        let hitRate: String
        var id: Int { playerId }
    }

    let stats: [EliteStat]
    let filter: Filter
    let options: Options
    let leaderboard: [Row]
    let map: Map
    let mostReliable: Reliable
    let leakiness: [Leak]
    let tough: [Tough]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}
