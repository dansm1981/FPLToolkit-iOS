import Foundation

// MARK: - Workload (contract §26; happy-backend-pal#40)

/// Minutes in all competitions: the Premier League from FPL, cups, Europe and internationals from
/// the daily API-Football job. Evidence, not a fatigue claim.
struct WorkloadPage: Decodable, Sendable {
    let players: [String: Workload]
    func workload(_ id: Int) -> Workload? { players[String(id)] }
}

struct Workload: Decodable, Sendable, Hashable {
    struct Match: Decodable, Sendable, Hashable, Identifiable {
        enum Kind: String, FallbackDecodable {
            case league, cup, europe, international
            case unknown
            static let fallback = Self.unknown
        }
        let date: Date
        let competition: String
        let kind: Kind
        let team: String?
        let opponent: String?
        let minutes: Int
        let started: Bool
        var id: String { "\(date.timeIntervalSince1970)-\(competition)" }
    }

    /// Minutes in all competitions in the last 7 and 14 days.
    let last7: Int
    let last14: Int
    let lastMatch: Match?
    /// Recent matches outside the Premier League, newest first.
    let otherCompetitions: [Match]
}

enum WorkloadText {
    nonisolated static func kind(_ kind: Workload.Match.Kind) -> String {
        switch kind {
        case .league: "Premier League"
        case .cup: "Cup"
        case .europe: "Europe"
        case .international: "International"
        case .unknown: "Match"
        }
    }

    /// "Tue · UEFA Nations League · England v Czechia · 90 min (sub)"
    nonisolated static func match(_ m: Workload.Match) -> String {
        let day = m.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        var parts = [day, m.competition]
        if let team = m.team, let opponent = m.opponent { parts.append("\(team) v \(opponent)") }
        else if let opponent = m.opponent { parts.append("v \(opponent)") }
        parts.append("\(m.minutes) min" + (m.started ? "" : " (sub)"))
        return parts.joined(separator: " · ")
    }

    /// "265 min in the last 14 days (all competitions)"
    nonisolated static func summary(_ w: Workload) -> String {
        "\(w.last14) min in the last 14 days · \(w.last7) in the last 7 (all competitions)"
    }
}
