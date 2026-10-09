import Foundation
import Testing
@testable import FPLToolkit

struct RoundupTests {
    @Test func decodesAndShares() throws {
        let json = """
        {"gameweek": 6, "available": true, "average": 51, "highest": 112, "headline": "GW6 round-up: 38 pts",
         "you": {"entryId": 1, "points": 38, "cost": 4, "chip": null, "captain": {"playerId": 2, "points": 18}, "bench": 6,
                 "transfers": {"net": 3, "text": "Isak in for Wissa: +7, after a −4 hit: +3"},
                 "best": {"playerId": 2, "points": 18}, "worst": null,
                 "rank": {"before": 63100, "after": 41200, "text": "63.1k → 41.2k ↑21.9k"}, "total": 338},
         "rivals": [{"entryId": 9, "name": "Andy", "featured": true, "you": 38, "them": 25, "margin": 13, "result": "RIVALRY WON",
                     "areas": [{"label": "Captains", "text": "Salah 18 v 4 Haaland", "edge": 14}],
                     "biggestSwing": "Salah +9 to you", "seasonText": "Season: 18 pts ahead of Andy"}],
         "leagues": [{"id": 1, "name": "LEAGUE OF EXPERTS", "before": 3, "now": 2, "text": "3rd → 2nd"}], "players": {}}
        """
        let r = try APIClient.decode(Roundup.self, from: Data(json.utf8))
        #expect(r.rivals.first?.result == "RIVALRY WON" && r.leagues.first?.text == "3rd → 2nd")
        #expect(RoundupText.rivalLines(r.rivals[0]).first == "Biggest swing: Salah +9 to you")
        #expect(RoundupText.youLines(r.you!, r).first == "Rank: 63.1k → 41.2k ↑21.9k")
        #expect(DeepLink(url: try #require(URL(string: "fpltoolkit://roundup"))) == .roundup)
    }
}
