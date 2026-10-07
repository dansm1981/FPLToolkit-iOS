import Foundation

// MARK: - The Deadline reveal (tasks/deadline-reveal.md; happy-backend-pal#92)

/// Who did what after the deadline: you, your rivals, your saved leagues and the Elite 100, for the
/// gameweek just locked. Every word and figure is the server's.
struct Reveal: Decodable, Sendable {
    struct Move: Decodable, Sendable, Hashable {
        let out: Int
        let `in`: Int
    }
    struct Chip: Decodable, Sendable, Hashable {
        let chip: String
        let label: String
    }
    struct Manager: Decodable, Sendable, Hashable, Identifiable {
        let entryId: Int
        let name: String
        let teamName: String?
        let rank: Int?
        let transfers: [Move]
        let cost: Int
        let chip: Chip?
        let captainId: Int?
        let viceId: Int?
        let isMe: Bool
        /// "2 transfers · −4 hit · Haaland (C) · Bench Boost"
        let summary: String
        var id: Int { entryId }
    }
    struct Rival: Decodable, Sendable, Hashable, Identifiable {
        let entryId: Int
        let name: String
        let teamName: String?
        let transfers: [Move]
        let cost: Int
        let chip: Chip?
        let captainId: Int?
        let viceId: Int?
        let summary: String
        let featured: Bool
        /// Players in their squad you don't have, and in yours they don't.
        let theirs: [Int]
        let mine: [Int]
        /// "4 players different from you"
        let differenceText: String
        var id: Int { entryId }
    }
    struct Count: Decodable, Sendable, Hashable {
        let playerId: Int
        let count: Int
        var pct: Int?
    }
    struct ChipCount: Decodable, Sendable, Hashable {
        let chip: String
        let label: String
        let count: Int
    }
    struct League: Decodable, Sendable, Hashable, Identifiable {
        let id: Int
        let name: String
        let managers: Int
        let synced: Bool
        /// "9 of 21 made transfers · 3 took hits · 2 chips"
        let headline: String
        let chips: [ChipCount]
        let mostBought: [Count]
        let mostSold: [Count]
        let captains: [Count]
        /// "62% captained Haaland; you went Salah, with 4 others"
        let captainText: String?
        /// The leader and the three around you (you included).
        let rows: [Manager]
    }
    struct Elite: Decodable, Sendable, Hashable {
        let gw: Int
        let bought: [EliteShareRow]
        let sold: [EliteShareRow]
        let captains: [EliteShareRow]
        let chips: [EliteStat]
    }
    struct Headline: Decodable, Sendable, Hashable {
        let title: String
        let body: String
    }

    let gameweek: Int
    let deadline: Date?
    let ready: Bool
    let readyText: String?
    let headline: Headline?
    let you: Manager?
    let rivals: [Rival]
    let leagues: [League]
    let elite: Elite?
    let players: [String: PlayerSummary]

    func player(_ id: Int?) -> PlayerSummary? { id.flatMap { players[String($0)] } }
    func name(_ id: Int?) -> String { player(id)?.webName ?? "Player" }
}
