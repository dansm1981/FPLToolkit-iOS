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
