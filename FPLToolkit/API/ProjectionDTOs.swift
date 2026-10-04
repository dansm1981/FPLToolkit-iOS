import Foundation

// MARK: - Projections (happy-backend-pal#74; Dan, 4 Oct 2026)

/// The run behind every projection: what stage it reached, which gameweeks, how it got its
/// match context. The same header as the website's /projections.
struct ProjectionRun: Decodable, Sendable, Hashable {
    struct Stage: Decodable, Sendable, Hashable {
        /// early, odds, pressconf, deadline, lineups or played.
        let key: String
        let label: String
        let note: String?
    }
    struct Context: Decodable, Sendable, Hashable {
        /// Team-fixtures whose xG came from odds (Market FDR) and from the fitted model.
        let market: Int
        let fitted: Int
    }
    let id: String
    let modelVersion: String
    let fromGw: Int
    let toGw: Int
    let horizon: Int
    let sims: Int
    let stage: Stage
    let hoursToDeadline: Int?
    let deadline: Date?
    let context: Context
    let finishedAt: Date?
    let players: Int
}

enum ProjectionSort: String, CaseIterable, Identifiable, Sendable {
    case mean, median, mode, p90, haul, blank, sixty, price, fplEp
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mean: "Mean"
        case .median: "Median"
        case .mode: "Mode"
        case .p90: "P90"
        case .haul: "Haul"
        case .blank: "Blank"
        case .sixty: "60+ minutes"
        case .price: "Price"
        case .fplEp: "FPL ep"
        }
    }
    /// Blank and FPL ep are one-gameweek columns, as on the website.
    var gameweekOnly: Bool { self == .blank || self == .fplEp }
}

/// `GET /projections`: every player's points for the coming gameweeks as a distribution, for one
/// horizon, filtered and sorted by the server (the website's own table code).
struct Projections: Decodable, Sendable {
    struct Knew: Decodable, Sendable {
        struct Input: Decodable, Sendable, Hashable, Identifiable {
            enum Status: String, FallbackDecodable {
                case available, missing, stale, unknown
                static let fallback = Self.unknown
            }
            let name: String
            let status: Status
            let observedAt: Date?
            let detail: String?
            var id: String { name }
        }
        let inputs: [Input]
        let notes: [String]
    }
    struct Horizon: Decodable, Sendable, Hashable, Identifiable {
        let value: Int
        /// "GW6" or "Next 3 (GW6–8)".
        let label: String
        var id: Int { value }
    }
    struct Row: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let price: Double
        /// Chance of 60+ minutes in the first gameweek: yours when adjusted, else the model's.
        let sixtyPct: Int?
        let modelSixtyPct: Int?
        let adjusted: Bool
        let mean: Double
        let median: Int
        let mode: Int
        let p10: Int
        let p90: Int
        /// One gameweek: 10+ points. Over a horizon: at least one 10+ gameweek.
        let haulPct: Int?
        /// 2 points or fewer; nil over a horizon.
        let blankPct: Int?
        /// FPL's own expected points for the round; nil over a horizon.
        let fplEp: Double?
        var id: Int { playerId }
    }
    let run: ProjectionRun?
    let knew: Knew?
    let horizons: [Horizon]
    let horizon: Int
    let total: Int
    let rows: [Row]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}

/// `GET /projections/players/{id}`: how one player's projection is built, gameweek by gameweek.
struct ProjectionPlayer: Decodable, Sendable {
    struct Figure: Decodable, Sendable, Hashable, Identifiable {
        let label: String
        /// Display text, as the website prints it ("84%", "×0.98", "3.4 matches").
        let value: String
        var id: String { label }
    }
    struct Fixture: Decodable, Sendable, Hashable {
        enum Source: String, FallbackDecodable {
            case market, fitted, unknown
            static let fallback = Self.unknown
        }
        let opponentId: Int
        let home: Bool
        let teamXg: Double
        let opponentXg: Double
        let cleanSheetPct: Int
        let defconFactor: Double
        let source: Source
    }
    struct Component: Decodable, Sendable, Hashable, Identifiable {
        /// appearance, goals, assists, clean_sheet, saves, defcon, bonus, conceded or cards.
        let key: String
        let label: String
        let value: Double
        var id: String { key }
    }
    struct Gameweek: Decodable, Sendable, Hashable, Identifiable {
        struct Chart: Decodable, Sendable, Hashable {
            /// Points for `bars[0]`; may be below zero.
            let first: Int
            /// The chance of each points total from `first` up.
            let bars: [Double]
        }
        struct Explained: Decodable, Sendable, Hashable {
            let figures: [Figure]
            let basis: [String]
        }
        let gameweek: Int
        /// 0 is a blank gameweek, 2 or more a double.
        let fixtureCount: Int
        let mean: Double
        let median: Int
        let mode: Int
        let p10: Int
        let p90: Int
        let haulPct: Int?
        let blankPct: Int?
        let chart: Chart
        let minutes: Explained
        let fixtures: [Fixture]
        let rates: Explained?
        let components: [Component]
        var id: Int { gameweek }
    }
    struct Horizon: Decodable, Sendable, Hashable, Identifiable {
        let horizon: Int
        let toGw: Int
        /// "GW6–7".
        let label: String
        let mean: Double
        let median: Int
        let mode: Int
        let p10: Int
        let p90: Int
        let anyHaulPct: Int?
        let allBlankPct: Int?
        var id: Int { horizon }
    }
    let run: ProjectionRun?
    let player: PlayerSummary
    let availabilityText: String
    let gameweeks: [Gameweek]
    let horizons: [Horizon]
}

/// The website's projection wording, shared by the list and the breakdown.
enum ProjectionText {
    /// "84%", or "—" when there's no figure.
    nonisolated static func pct(_ v: Int?) -> String { v.map { "\($0)%" } ?? "—" }
    nonisolated static func one(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }
    nonisolated static func two(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(2))) }
    /// A points-by-source value: "+2.79" or "−0.10".
    nonisolated static func signed(_ v: Double) -> String {
        let text = two(abs(v))
        return v < 0 ? "−\(text)" : "+\(text)"
    }
    /// The stage line under the run card's pill: "142h to the GW6 deadline".
    nonisolated static func deadline(_ run: ProjectionRun) -> String? {
        run.hoursToDeadline.map { "\($0)h to the GW\(run.fromGw) deadline" }
    }
}
