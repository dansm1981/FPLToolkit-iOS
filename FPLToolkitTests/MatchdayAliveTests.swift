import Foundation
import Testing
@testable import FPLToolkit

struct MatchdayAliveTests {
    @Test func decodesTickerSwingsAndFixtures() throws {
        let ticker = try APIClient.decode([LiveTeam.Pulse.TickerItem].self, from: Data("""
        [{"id": "b-g1", "kind": "breaking", "text": "Haaland scores", "detail": "Owned by 62% · 71% near your rank",
          "impact": {"points": null, "rival": null, "rank": {"value": -24000, "text": "Rank ↓24k"}}, "playerId": 1, "itemId": "a-g1"},
         {"id": "p-7", "kind": "player", "text": "Saka · 67' · 9 pts", "detail": null}]
        """.utf8))
        #expect(ticker.first?.impact?.rank?.text == "Rank ↓24k" && ticker[1].itemId == nil)
        #expect(LiveTickerText.label("around") == "AROUND THE GAME")
        let swing = try APIClient.decode(LiveTeam.Pulse.Swing.self, from: Data("""
        {"id": "threat-1", "kind": "threat", "text": "A Haaland goal would cost you ~24k places",
         "detail": "Not in your team · started by 71% near your rank · 62'", "playerId": 1, "rankEffect": -24000}
        """.utf8))
        #expect(swing.rankEffect < 0)
        let group = try JSONDecoder().decode(LiveTeam.FeedItem.Group.self, from: Data(#""around""#.utf8))
        #expect(group == .around)
    }
}
