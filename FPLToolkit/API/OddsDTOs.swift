import Foundation

// MARK: - Odds (contract §25; happy-backend-pal#38)

/// Chances from bookmaker odds for the next gameweek, labelled "Betting-market estimate". The
/// server never sends bookmaker names, prices or links.
struct Odds: Decodable, Sendable {
    struct Result: Decodable, Sendable, Hashable {
        let home: Double
        let draw: Double
        let away: Double
        let bookmakers: Int
    }
    struct CleanSheet: Decodable, Sendable, Hashable {
        let home: Double?
        let away: Double?
        let sources: Int
    }
    struct Chances: Decodable, Sendable, Hashable {
        let result: Result?
        let cleanSheet: CleanSheet
    }
    struct Fixture: Decodable, Sendable, Hashable, Identifiable {
        let fixtureId: Int
        let homeClubId: Int?
        let awayClubId: Int?
        let kickoff: Date?
        let result: Result?
        let cleanSheet: CleanSheet
        let previous: Chances?
        let providerUpdatedAt: Date?
        var id: Int { fixtureId }
    }
    struct Player: Decodable, Sendable, Hashable {
        let fixtureId: Int
        /// Approximate: one bookmaker, margin included.
        let scorer: Double?
        let scoreOrAssist: Double?
        let previousScorer: Double?
        let previousScoreOrAssist: Double?
    }

    let gameweek: Int
    let available: Bool
    let label: String
    let fetchedAt: Date?
    let previousFetchedAt: Date?
    let fixtures: [Fixture]
    let players: [String: Player]
    let unmatched: Int

    func player(_ id: Int) -> Player? { players[String(id)] }
}

/// The one chance that matters for a player's position, joined from the fixtures and players.
struct OddsChance: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case cleanSheet, scorer }
    let kind: Kind
    let value: Double
    let previous: Double?
    /// Midfielders and forwards: the chance to score or assist too.
    let scoreOrAssist: Double?

    /// Clean sheet for goalkeepers and defenders, scoring for midfielders and forwards.
    static func of(_ player: PlayerSummary, in odds: Odds) -> OddsChance? {
        switch player.position {
        case .gk, .def:
            for f in odds.fixtures {
                let home = f.homeClubId == player.clubId
                guard home || f.awayClubId == player.clubId else { continue }
                guard let value = home ? f.cleanSheet.home : f.cleanSheet.away else { return nil }
                let previous = home ? f.previous?.cleanSheet.home : f.previous?.cleanSheet.away
                return OddsChance(kind: .cleanSheet, value: value, previous: previous, scoreOrAssist: nil)
            }
            return nil
        case .mid, .fwd:
            guard let p = odds.player(player.id), let scorer = p.scorer else { return nil }
            return OddsChance(kind: .scorer, value: scorer, previous: p.previousScorer, scoreOrAssist: p.scoreOrAssist)
        case .unknown:
            return nil
        }
    }

    nonisolated static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// "↑4" or "↓3" when the chance moved by at least 2 points since the last refresh.
    var movement: String? {
        guard let previous else { return nil }
        let points = Int(((value - previous) * 100).rounded())
        guard abs(points) >= 2 else { return nil }
        return points > 0 ? "↑\(points)" : "↓\(-points)"
    }

    var text: String {
        switch kind {
        case .cleanSheet:
            return "\(Self.percent(value)) clean sheet"
        case .scorer:
            let involvement = scoreOrAssist.map { " · \(Self.percent($0)) score or assist" } ?? ""
            return "\(Self.percent(value)) to score\(involvement)"
        }
    }

    var spoken: String {
        let move = movement.map { $0.hasPrefix("↑") ? ", up \($0.dropFirst()) points" : ", down \($0.dropFirst()) points" } ?? ""
        switch kind {
        case .cleanSheet: return "Betting-market estimate: \(Self.percent(value)) chance of a clean sheet\(move)"
        case .scorer:
            let involvement = scoreOrAssist.map { ", \(Self.percent($0)) to score or assist" } ?? ""
            return "Betting-market estimate: \(Self.percent(value)) chance to score\(involvement)\(move)"
        }
    }
}
