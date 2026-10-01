import Foundation

/// Words for Matchday. Only phrasing: every fact and judgement comes from the API.
enum MatchdayText {
    nonisolated static func status(_ status: LiveTeam.Status) -> String {
        switch status {
        case .upcoming: "Not started"
        case .live: "Live"
        case .between: "Between matches"
        case .awaitingBonus: "Awaiting bonus"
        case .finished: "Complete"
        case .unknown: "Matchday"
        }
    }

    nonisolated static func chip(_ chip: String?) -> String? {
        switch chip {
        case "bboost": "Bench Boost"
        case "3xc": "Triple Captain"
        case "wildcard": "Wildcard"
        case "freehit": "Free Hit"
        default: nil
        }
    }

    nonisolated static func lineup(_ lineup: LiveTeam.Player.Lineup) -> String? {
        switch lineup {
        case .starting: "Starting"
        case .bench: "On the bench"
        case .notInSquad: "Not in the squad"
        case .unknown: nil
        }
    }

    nonisolated static func symbol(_ kind: LiveTeam.Moment.Kind) -> String {
        switch kind {
        case .goal: "soccerball"
        case .ownGoal: "soccerball.inverse"
        case .assist: "arrowshape.turn.up.right"
        case .penaltyMissed: "xmark.circle"
        case .redCard: "exclamationmark.octagon"
        case .subbedOff: "arrow.down.circle"
        case .subbedOn: "arrow.up.circle"
        case .defcon: "shield.lefthalf.filled"
        case .cleanSheetLost: "shield.slash"
        case .bonus: "star.fill"
        case .unknown: "circle"
        }
    }

    nonisolated static func moment(_ m: LiveTeam.Moment, live: LiveTeam) -> String {
        let name = live.player(m.playerId)?.webName ?? "Your player"
        switch m.kind {
        case .goal:
            switch m.state {
            case .withdrawn: return "\(name)'s goal was disallowed"
            case .reported: return "Goal reported: \(name)"
            default: return "\(name) scored"
            }
        case .ownGoal: return "\(name) scored an own goal"
        case .assist: return "\(name) assisted"
        case .penaltyMissed: return "\(name) missed a penalty"
        case .redCard: return "\(name) was sent off"
        case .subbedOff: return "\(name) came off"
        case .subbedOn: return "\(name) came on"
        case .defcon: return "\(name) reached DEFCON"
        case .cleanSheetLost:
            let names = (m.players ?? []).compactMap { live.player($0)?.webName }
            return names.isEmpty ? "Clean sheet lost" : "Clean sheet lost: \(names.joined(separator: ", "))"
        case .bonus:
            return m.points.map { "\(name): \($0) bonus confirmed" } ?? "\(name): bonus confirmed"
        case .unknown: return "Update for \(name)"
        }
    }

    nonisolated static func stat(_ identifier: String, value: Double) -> String {
        let n = value.rounded() == value ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(1)))
        let count = Int(value)
        switch identifier {
        case "minutes": return "\(n) minutes"
        case "goals_scored": return count == 1 ? "Goal" : "\(n) goals"
        case "assists": return count == 1 ? "Assist" : "\(n) assists"
        case "clean_sheets": return "Clean sheet"
        case "goals_conceded": return "\(n) conceded"
        case "own_goals": return count == 1 ? "Own goal" : "\(n) own goals"
        case "penalties_saved": return count == 1 ? "Penalty saved" : "\(n) penalties saved"
        case "penalties_missed": return count == 1 ? "Penalty missed" : "\(n) penalties missed"
        case "yellow_cards": return "Yellow card"
        case "red_cards": return "Red card"
        case "saves": return "\(n) saves"
        case "bonus": return "Bonus"
        case "defensive_contribution": return "DEFCON (\(n) contributions)"
        default: return identifier.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    nonisolated static func context(_ c: LiveTeam.Player.Context) -> String? {
        var parts: [String] = []
        if let shots = c.shots, shots > 0 {
            parts.append("\(shots) shot\(shots == 1 ? "" : "s")" + (c.shotsOn.map { " (\($0) on target)" } ?? ""))
        }
        if let k = c.keyPasses, k > 0 { parts.append("\(k) key pass\(k == 1 ? "" : "es")") }
        if let t = c.tackles, t > 0 { parts.append("\(t) tackle\(t == 1 ? "" : "s")") }
        if let s = c.saves, s > 0 { parts.append("\(s) save\(s == 1 ? "" : "s")") }
        if let r = c.rating { parts.append("rating \(r)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The live feed's time column: the match minute, or KO, HT and FT for the markers.
    nonisolated static func feedTime(_ item: LiveTeam.FeedItem) -> String {
        switch item.kind {
        case .kickOff: return "KO"
        case .halfTime: return "HT"
        case .fullTime: return "FT"
        default: return item.minute.map { "\($0)′" } ?? ""
        }
    }

    nonisolated static func symbol(_ item: LiveTeam.FeedItem) -> String {
        switch item.kind {
        case .lineup:
            switch item.lineup {
            case .starting: "checkmark.circle"
            case .bench: "chair.lounge"
            default: "person.slash"
            }
        case .kickOff: "play.circle"
        case .halfTime: "pause.circle"
        case .fullTime: "flag.checkered"
        case .goal: "soccerball"
        case .ownGoal: "soccerball.inverse"
        case .assist: "arrowshape.turn.up.right"
        case .penaltyMissed: "xmark.circle"
        case .penaltySaved, .save: "hand.raised"
        case .yellowCard, .redCard: "rectangle.portrait"
        case .subbedOff: "arrow.down.circle"
        case .subbedOn: "arrow.up.circle"
        case .defcon: "shield.lefthalf.filled"
        case .sixtyMinutes: "clock"
        case .cleanSheet: "shield"
        case .cleanSheetLost: "shield.slash"
        case .bonusPosition: "star.leadinghalf.filled"
        case .bonus: "star.fill"
        case .unknown: "circle"
        }
    }

    /// "+2", "−1" (a true minus sign).
    nonisolated static func signedPoints(_ points: Int) -> String {
        points > 0 ? "+\(points)" : "−\(-points)"
    }

    /// One feed line for VoiceOver: when, what, the detail, and the points.
    nonisolated static func spoken(_ item: LiveTeam.FeedItem, isNew: Bool) -> String {
        var parts: [String] = []
        if isNew { parts.append("New") }
        switch item.kind {
        case .kickOff, .halfTime, .fullTime: break
        default: if let minute = item.minute { parts.append("Minute \(minute)") }
        }
        parts.append(item.text)
        if let detail = item.detail { parts.append(detail) }
        if let points = item.points, points != 0 {
            let n = abs(points)
            parts.append("\(points > 0 ? "Plus" : "Minus") \(n) point\(n == 1 ? "" : "s")")
        }
        return parts.joined(separator: ". ")
    }

    nonisolated static func fixtureName(_ f: LiveTeam.Fixture, club: (Int) -> String?) -> String {
        "\(club(f.homeClubId) ?? "Home") v \(club(f.awayClubId) ?? "Away")"
    }
}

/// "Since you last checked": what this phone saw on its last visit, per team and gameweek. Kept
/// on the phone only (never sent anywhere), per the privacy note in tasks/phase-3.md §5.
enum MatchdayMemory {
    struct Seen: Codable, Sendable, Equatable {
        let total: Int
        let momentIds: [String]
        let at: Date
        /// The live feed's items (nil when saved by a build before the feed).
        var feedIds: [String]?
    }

    private nonisolated static func key(_ entryId: Int, _ gameweek: Int) -> String {
        "matchday.seen.\(entryId).\(gameweek)"
    }

    static func read(entryId: Int, gameweek: Int) -> Seen? {
        guard let data = UserDefaults.standard.data(forKey: key(entryId, gameweek)) else { return nil }
        return try? JSONDecoder().decode(Seen.self, from: data)
    }

    static func save(_ live: LiveTeam, entryId: Int, now: Date = .now) {
        let seen = Seen(total: live.total.estimated, momentIds: live.moments.map(\.id), at: now,
                        feedIds: live.feed?.map(\.id))
        if let data = try? JSONEncoder().encode(seen) {
            UserDefaults.standard.set(data, forKey: key(entryId, live.gameweek))
        }
    }

    /// One line on what's new since `since`, or nil when nothing changed.
    nonisolated static func catchUp(_ live: LiveTeam, since: Seen) -> String? {
        let seen = Set(since.momentIds)
        let new = live.moments.filter { !seen.contains($0.id) && $0.state != .withdrawn }
        let delta = live.total.estimated - since.total
        guard !new.isEmpty || delta != 0 else { return nil }
        var text = "Since you last checked"
        if !new.isEmpty {
            let shown = new.prefix(3).map { MatchdayText.moment($0, live: live) }
            let more = new.count - shown.count
            text += ": " + shown.joined(separator: ", ") + (more > 0 ? " and \(more) more" : "")
        }
        text += delta > 0 ? ". Up \(delta)." : delta < 0 ? ". Down \(-delta)." : ". No change to your score."
        return text
    }
}
