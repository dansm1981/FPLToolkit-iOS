import Foundation

// The Draft Planner (contract §13). Every rule is applied by the server; these only carry
// what it decided. New enum values fall back instead of failing (§2.4).

struct PlannerDraftSummary: Decodable, Sendable, Identifiable, Hashable {
    enum Source: String, FallbackDecodable {
        case `import`, blank, copy
        case unknown
        static let fallback = Self.unknown
    }

    let id: String
    let name: String
    let source: Source
    let entryId: Int?
    /// Kept as text: the server sends microsecond timestamps.
    let createdAt: String?
    let updatedAt: String?
    /// Gameweeks with planned changes after the starting squad.
    let plannedGws: [Int]
    let playerCount: Int
}

struct PlannerDraftList: Decodable, Sendable {
    let drafts: [PlannerDraftSummary]
}

struct PlannerDraft: Decodable, Sendable {
    struct Pick: Decodable, Sendable, Hashable, Identifiable {
        let playerId: Int
        let slot: Int
        let isCaptain: Bool
        let isVice: Bool
        /// £m
        let purchasePrice: Double?
        /// £m, what selling him returns at today's price.
        let sellingPrice: Double?
        let purchaseEstimated: Bool
        var id: Int { playerId }
    }

    struct Chip: Decodable, Sendable, Hashable, Identifiable {
        enum State: String, FallbackDecodable {
            case available, active, played, outside, blocked
            case unknown
            static let fallback = Self.unknown
        }
        struct Window: Decodable, Sendable, Hashable {
            let start: Int
            let end: Int
        }
        let key: String
        let label: String
        let state: State
        let gw: Int?
        let window: Window?
        let note: String?
        var id: String { key }
    }

    struct Money: Decodable, Sendable, Hashable {
        let bank: Double
        let squadValue: Double
        let sellValue: Double
        let profitToDate: Double
        let startBudget: Double
    }

    struct Check: Decodable, Sendable, Hashable {
        let ok: Bool
        let issues: [String]
        let players: Int
    }

    struct Transfers: Decodable, Sendable, Hashable {
        let out: [Int]
        let `in`: [Int]
    }

    struct LedgerRow: Decodable, Sendable, Hashable, Identifiable {
        let gw: Int
        let transfers: Int
        let chip: String?
        let freeTransfers: Int
        let bankedAfter: Int
        let hits: Int
        let hitPoints: Int
        var id: Int { gw }
    }

    struct FreeTransfers: Decodable, Sendable, Hashable {
        let starting: Int
        let estimated: Bool
    }

    struct EmptySlots: Decodable, Sendable, Hashable {
        let starting: [String: Int]
        let bench: [String: Int]
    }

    /// One gameweek of a player's fixture strip (the website's pitch card).
    struct StripWeek: Decodable, Sendable, Hashable {
        let gw: Int
        /// The hardest fixture's band, 1 (easiest) to 5 (hardest); nil in a blank.
        let band: Int?
        /// Two in a double, a blank marker in a blank.
        let fixtures: [FixtureDifficulty]
        var isDouble: Bool { fixtures.filter { !$0.blank }.count > 1 }
    }

    let id: String
    let name: String
    let source: PlannerDraftSummary.Source
    let entryId: Int?
    let shareUrl: String
    let gw: Int
    let firstEditableGw: Int
    let baseGw: Int?
    let lastGw: Int
    let starting: [Pick]
    let bench: [Pick]
    /// A legal shape to draw, e.g. "4-4-2".
    let formation: String
    let emptySlots: EmptySlots
    let players: [String: PlayerSummary]
    let fixtures: [String: [FixtureDifficulty]]
    /// The next six gameweeks per player; absent from servers before happy-backend-pal#13.
    let fixtureStrip: [String: [StripWeek]]?
    let money: Money
    let check: Check
    let chips: [Chip]
    let transfers: Transfers
    let ledger: [LedgerRow]
    let freeTransfers: FreeTransfers
    let estimatedPurchasePrices: Bool

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
    func fixtures(for id: Int) -> [FixtureDifficulty] { fixtures[String(id)] ?? [] }
    func strip(for id: Int) -> [StripWeek] { fixtureStrip?[String(id)] ?? [] }
    /// Free transfers in the gameweek shown: the ledger's row, else the starting figure (a draft
    /// with nothing planned yet); nil for a gameweek that has passed.
    var freeTransfersThisWeek: Int? {
        if let row = ledger.first(where: { $0.gw == gw }) { return row.freeTransfers }
        return gw >= firstEditableGw ? freeTransfers.starting : nil
    }

    /// The squad as the "restore" action takes it (undo and redo).
    var restorePicks: [PlannerAction.RestorePick] {
        (starting + bench).map {
            PlannerAction.RestorePick(playerId: $0.playerId, slot: $0.slot, isCaptain: $0.isCaptain, isVice: $0.isVice)
        }
    }
    var isEditable: Bool { gw >= firstEditableGw }
    static let pitchOrder: [Position] = [.gk, .def, .mid, .fwd]
    /// The starters grouped into pitch rows, goalkeeper first, with the empty places to show.
    func rows() -> [(position: Position, picks: [Pick], empty: Int)] {
        Self.pitchOrder.map { position in
            (position, starting.filter { player($0.playerId)?.position == position }, emptyStarting(position))
        }
    }
    func emptyStarting(_ position: Position) -> Int { emptySlots.starting[position.rawValue] ?? 0 }
    func emptyBench(_ position: Position) -> Int { emptySlots.bench[position.rawValue] ?? 0 }
}

/// One edit, sent as-is; the server answers with the draft or the reason it refused (§13.3).
struct PlannerAction: Encodable, Sendable {
    struct RestorePick: Encodable, Sendable, Hashable {
        let playerId: Int
        let slot: Int
        let isCaptain: Bool
        let isVice: Bool
    }

    let type: String
    var gw: Int?
    var playerId: Int?
    var replacePlayerId: Int?
    var withPlayerId: Int?
    var chip: String?
    var picks: [RestorePick]?

    static func pick(_ playerId: Int, replacing: Int?, gw: Int) -> Self {
        .init(type: "pick", gw: gw, playerId: playerId, replacePlayerId: replacing)
    }
    static func swap(_ playerId: Int, with other: Int, gw: Int) -> Self {
        .init(type: "swap", gw: gw, playerId: playerId, withPlayerId: other)
    }
    static func remove(_ playerId: Int, gw: Int) -> Self { .init(type: "remove", gw: gw, playerId: playerId) }
    static func captain(_ playerId: Int, gw: Int) -> Self { .init(type: "captain", gw: gw, playerId: playerId) }
    static func vice(_ playerId: Int, gw: Int) -> Self { .init(type: "vice", gw: gw, playerId: playerId) }
    static func chip(_ key: String, gw: Int) -> Self { .init(type: "chip", gw: gw, chip: key) }
    static func restore(_ draft: PlannerDraft) -> Self { restore(draft.restorePicks, gw: draft.gw) }
    static func restore(_ picks: [RestorePick], gw: Int) -> Self { .init(type: "restore", gw: gw, picks: picks) }
    /// Edits to the squad itself: the ones undo and redo cover.
    var isSquadEdit: Bool { ["pick", "swap", "remove", "captain", "vice"].contains(type) }
    static let reset = Self(type: "reset")
}

struct PlannerNewDraft: Encodable, Sendable {
    let source: String
    var entryId: Int?
    var fromId: String?
    var name: String?

    static func `import`(_ entryId: Int) -> Self { .init(source: "import", entryId: entryId) }
    static let blank = Self(source: "blank")
    static func copy(_ id: String) -> Self { .init(source: "copy", fromId: id) }
}

struct PlannerDraftPatch: Encodable, Sendable {
    var name: String?
    var startBudget: Double?
    var startingFt: Int?
}

struct PlannerPicker: Decodable, Sendable {
    struct Candidate: Decodable, Sendable, Identifiable, Hashable {
        let player: PlayerSummary
        let totalPoints: Int
        let form: Double?
        let pointsPerGame: Double?
        let expectedGoalInvolvements: Double?
        let fdrNext6: Double?
        let inSquad: Bool
        /// Why he can't be chosen for this slot, or nil.
        let reason: String?
        var id: Int { player.id }
    }
    let candidates: [Candidate]
    let total: Int
    let bank: Double
    let outgoingSellingPrice: Double?
}
