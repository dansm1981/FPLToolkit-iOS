import Foundation
import Testing
@testable import FPLToolkit

/// Matchday v2 phase 0 (tasks/matchday-v2.md): one score convention, status words, the acting
/// captain, links that open a moment, and Pulse's decoding.
struct MatchdayV2Tests {
    @Test func oneScoreConvention() {
        #expect(LiveScoreText.unit(status: "live") == "live pts")
        #expect(LiveScoreText.unit(status: "awaitingBonus") == "live pts")
        #expect(LiveScoreText.unit(status: "finished") == "pts")
        #expect(LiveScoreText.breakdown(estimated: 55, provisionalBonus: 3, status: "live") == "52 confirmed + 3 estimated")
        #expect(LiveScoreText.breakdown(estimated: 52, provisionalBonus: 0, status: "between") == "All confirmed by FPL so far")
        #expect(LiveScoreText.breakdown(estimated: 68, provisionalBonus: 0, status: "finished") == "Final, confirmed by FPL")
        #expect(["upcoming", "live", "between", "awaitingBonus", "finished"].map(LiveScoreText.status)
                == ["Not started", "Live", "Between matches", "Awaiting bonus", "Final"])
    }

    @Test func actingCaptain() throws {
        let live = try decode(Self.team(captainId: 2))
        let captain = try #require(live.squad.first { $0.playerId == 1 })
        let vice = try #require(live.squad.first { $0.playerId == 2 })
        // The captain didn't play: the vice scores as captain.
        #expect(MatchdayText.role(captain, live: live) == nil)
        #expect(MatchdayText.role(vice, live: live) == "C")
        let normal = try decode(Self.team(captainId: 1))
        #expect(MatchdayText.role(try #require(normal.squad.first { $0.playerId == 1 }), live: normal) == "C")
        #expect(MatchdayText.role(try #require(normal.squad.first { $0.playerId == 2 }), live: normal) == "V")
    }

    @Test func alertLinksOpenTheirMoment() throws {
        #expect(DeepLink(url: try #require(URL(string: "fpltoolkit://matchday?item=200-goal-7-1"))) == .matchday(item: "200-goal-7-1"))
        #expect(DeepLink(url: try #require(URL(string: "fpltoolkit://matchday"))) == .matchday(item: nil))
    }

    @Test func decodesPulse() throws {
        let live = try decode(Self.team(captainId: 1))
        let pulse = try #require(live.pulse)
        #expect(pulse.whatMattersNow.map(\.title) == ["Hall · 9/10 DEFCON"])
        #expect(pulse.whatMattersNow.first?.tone == .upside && pulse.whatMattersNow.first?.progress == 0.9)
        #expect(pulse.justHappened.first?.detail == "+10 points as captain")
    }

    @Test func ifNothingChangesWording() {
        typealias R = LiveTeam.Pulse.EndState.Rival
        #expect(IfNothingChangesCard.rivalText(R(entryId: 9, name: "Andy", points: 58, margin: 9)) == "You'd beat Andy by 9 this gameweek")
        #expect(IfNothingChangesCard.rivalText(R(entryId: 9, name: "Andy", points: 70, margin: -3)) == "Andy would beat you by 3 this gameweek")
        #expect(IfNothingChangesCard.rivalText(R(entryId: 9, name: "Andy", points: 67, margin: 0)) == "You'd draw the gameweek with Andy")
    }

    @Test func stillToComeOncePerPlayer() throws {
        let json = """
        [{"fixtureId": 2, "kickoff": "2026-10-10T16:30:00Z", "yours": [10, 11], "theirs": [10], "text": ""},
         {"fixtureId": 1, "kickoff": "2026-10-10T14:00:00Z", "yours": [], "theirs": [20], "text": ""}]
        """
        let next = try APIClient.decode([LiveTeam.Rivals.ComingUp].self, from: Data(json.utf8))
        let rows = MatchdayHeadToHead.stillToCome(next)
        #expect(rows.map(\.playerId) == [20, 10, 11])
        #expect(rows.map { $0.side("Andy") } == ["Andy only", "Both", "You only"])
    }

    @Test func lockScreenStateDecodesWithAndWithoutTheRival() throws {
        let base = #"{"points": 55, "provisionalBonus": 3, "playing": 4, "toPlay": 6, "headline": "Hall: 9/10", "status": "live", "updatedAt": 781700000"#
        let old = try JSONDecoder().decode(MatchdayActivityAttributes.ContentState.self, from: Data((base + "}").utf8))
        #expect(old.rival == nil)
        let new = try JSONDecoder().decode(MatchdayActivityAttributes.ContentState.self,
                                           from: Data((base + #", "rival": "4 pts ahead of Andy"}"#).utf8))
        #expect(new.rival == "4 pts ahead of Andy")
    }

    @Test func notificationPresets() throws {
        typealias A = DevicePrefs.MatchdayAlerts
        let standard = A.standard
        #expect(standard.preset == .normal)
        let essential = standard.applying(.essential)
        #expect(essential.preset == .essential && essential.goals && !essential.lineups && !essential.subs)
        let everything = standard.applying(.everything)
        #expect(everything.preset == .everything && everything.subs && everything.saves && everything.cleanSheets)
        var custom = standard
        custom.saves = true
        #expect(custom.preset == nil)
        // An older server's prefs (no new keys) read as the Normal preset.
        let old = try JSONDecoder().decode(A.self, from: Data(#"{"enabled": true, "lineups": true, "goals": true, "assists": true, "cards": true, "subs": false, "defcon": true, "final": true}"#.utf8))
        #expect(old.enabled && old.preset == .normal)
    }

    @Test func recapsDecodeAndRead() throws {
        let json = """
        {"spell": {"start": "2026-10-10T11:30:00Z", "title": "Lunchtime matches finished", "points": 12,
                   "rival": {"entryId": 9, "name": "Andy", "swing": 9},
                   "best": {"id": "1-goal-7", "text": "Saka scores", "detail": "+10 points as captain"},
                   "next": {"kickoff": "2026-10-10T14:00:00Z", "playerIds": [9]}},
         "final": {"gameweek": 6, "points": 68, "confirmed": true,
                   "rival": {"entryId": 9, "name": "Andy", "you": 68, "them": 57, "margin": 11},
                   "decided": null, "biggestGain": {"playerId": 7, "points": 24}, "benchPain": null}}
        """
        let recap = try APIClient.decode(LiveTeam.Pulse.Recap.self, from: Data(json.utf8))
        #expect(recap.spell?.rival?.swing == 9 && recap.spell?.next?.playerIds == [9])
        let rival = try #require(recap.final?.rival)
        #expect(FinalRecapCard.rivalLine(rival) == "You 68 – 57 Andy · you win by 11")
        #expect(FinalRecapCard.rivalLine(.init(entryId: 9, name: "Andy", you: 50, them: 53, margin: -3)) == "You 50 – 53 Andy · Andy wins by 3")
    }

    // MARK: Phase 3

    @Test func decodesRankLeaguesAndWinProbability() throws {
        let base = Self.team(captainId: 1)
        let json = String(base.dropLast(1)) + """
        , "rank": {"estimate": 327412, "previous": 345600, "movement": 18188, "text": "~327k",
                   "movementText": "↑18k", "sample": 1187, "basis": "FPL doesn't publish a live overall rank."},
          "leagues": [{"id": 783382, "name": "LEAGUE OF EXPERTS", "members": 14, "before": 3, "now": 2,
                       "above": {"name": "Pete", "gap": 5}, "below": null, "movement": 1,
                       "text": "2nd, up from 3rd", "detail": "5 behind Pete"}]}
        """
        let live = try decode(json)
        let rank = try #require(live.rank)
        #expect(rank.text == "~327k" && rank.movementText == "↑18k" && rank.sample == 1187)
        #expect(live.leagues?.first?.text == "2nd, up from 3rd" && live.leagues?.first?.above?.gap == 5)
        // Older servers: none of it.
        let old = try decode(base)
        #expect(old.rank == nil && old.leagues == nil && old.pulse?.winProbability == nil)
        #expect(old.pulse?.justHappened.first?.rankChangeText == nil)

        let chance = try APIClient.decode(LiveTeam.Pulse.WinProbability.self, from: Data("""
        {"entryId": 9, "name": "Andy", "you": 0.62, "draw": 0.04, "basis": "Played out 4,000 times."}
        """.utf8))
        #expect(chance.youPercent == 62 && chance.themPercent == 38)
        let close = LiveTeam.Pulse.WinProbability(entryId: 9, name: "Andy", you: 0.005, draw: 0, basis: "")
        #expect(close.youPercent + close.themPercent == 100)
    }

    @Test func rankReadsAloudAsAnEstimate() throws {
        let rank = try APIClient.decode(LiveTeam.Rank.self, from: Data("""
        {"estimate": 327412, "previous": 345600, "movement": 18188, "text": "~327k",
         "movementText": "↑18k", "sample": 1187, "basis": ""}
        """.utf8))
        #expect(RankText.spoken(rank) == "Estimated overall rank about 327,000, up 18,200 places since last gameweek")
        #expect(RankText.rounded(1_234_567) == 1_230_000 && RankText.rounded(840) == 840)
        #expect(RankText.spokenChange("↑18k") == "rank up 18 thousand")
        #expect(RankText.spokenChange("↓2.1k") == "rank down 2.1 thousand")
        #expect(RankText.spokenChange("↑1.2m") == "rank up 1.2 million")
        #expect(RankText.spokenChange("↓640") == "rank down 640")
    }

    @Test func recapsCarryTheRank() throws {
        let json = """
        {"spell": {"start": "2026-10-10T11:30:00Z", "title": "Lunchtime matches finished", "points": 21,
                   "rankChange": 41000, "rankChangeText": "↑41k", "rival": null, "best": null, "next": null},
         "final": {"gameweek": 6, "points": 68, "rank": {"before": 345600, "after": 327412, "text": "~327k",
                   "movementText": "↑18k"}, "confirmed": true, "rival": null, "decided": null,
                   "biggestGain": null, "benchPain": null}}
        """
        let recap = try APIClient.decode(LiveTeam.Pulse.Recap.self, from: Data(json.utf8))
        #expect(recap.spell?.rankChangeText == "↑41k")
        #expect(recap.final?.rank?.text == "~327k" && recap.final?.rank?.before == 345600)
    }

    private func decode(_ json: String) throws -> LiveTeam {
        try APIClient.decode(LiveTeam.self, from: Data(json.utf8))
    }

    private static func player(_ id: Int, captain: Bool = false, vice: Bool = false, multiplier: Int = 1) -> String {
        """
        {"playerId": \(id), "position": \(id), "counted": true, "multiplier": \(multiplier), "isCaptain": \(captain),
         "isViceCaptain": \(vice), "autoSub": null, "state": "inPlay", "minutes": 50, "points": 2,
         "provisionalBonus": 0, "lineup": null, "fixtureIds": [100],
         "next": {"defcon": null, "saves": null, "bonus": null, "cleanSheet": null}, "breakdown": []}
        """
    }

    private static func team(captainId: Int) -> String {
        """
        {"entryId": 22615, "gameweek": 6, "status": "live",
         "headline": {"text": "Hall: 9/10 defensive contributions", "kind": "threshold"},
         "chip": null,
         "total": {"estimated": 55, "confirmed": 52, "provisionalBonus": 3, "transferCost": 0, "benchPoints": 0},
         "captainId": \(captainId), "playing": 2, "toPlay": 9, "autoSubs": [],
         "squad": [\(player(1, captain: true, multiplier: captainId == 1 ? 2 : 0)), \(player(2, vice: true, multiplier: captainId == 2 ? 2 : 1))],
         "fixtures": [], "moments": [], "feed": [], "players": {},
         "pulse": {
           "whatMattersNow": [{"id": "defcon-3", "kind": "defcon", "playerId": 3, "title": "Hall · 9/10 DEFCON",
                               "detail": "One more action = +2", "stake": 2, "tone": "upside", "progress": 0.9, "closeness": 1}],
           "nextPoints": [],
           "justHappened": [{"id": "g1", "playerId": 1, "text": "Saka scores", "detail": "+10 points as captain",
                             "at": "2026-10-10T14:30:00Z"}]
         }}
        """
    }
}
