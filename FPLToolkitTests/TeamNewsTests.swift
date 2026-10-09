import Foundation
import Testing
@testable import FPLToolkit

struct TeamNewsTests {
    @Test func decodesTheWebsitesPayload() throws {
        let json = """
        {"gameweek": 6, "deadline": "2026-10-10T10:00:00+00:00", "read_at": null, "since": "2026-10-06", "sources": [],
         "counts": {"claims": 1, "players": 1, "flagged": 3, "clubs": 1},
         "clubs": [{"id": 1, "code": 3, "name": "Arsenal", "short_name": "ARS",
           "players": [{"id": 7, "web_name": "Saka", "slug": "saka", "position": 3, "now_cost": 100,
             "fpl_status": "d", "fpl_chance": 75, "fpl_news": "Knock - 75% chance of playing", "fpl_news_added": null,
             "fpl_effect": "75% available", "claims": [{"id": "c1", "claim": "fit", "label": "Fit", "tone": "good",
             "quote": "Bukayo trained today", "source_name": "theguardian.com", "source_url": "https://example.com",
             "observed_at": "2026-10-09T13:05:12.123456+00:00", "effect": "100% available for GW6"}]}]}]}
        """
        let page = try APIClient.decode(TeamNewsPage.self, from: Data(json.utf8))
        #expect(page.clubs.first?.players.first?.claims.first?.effect == "100% available for GW6")
        #expect(TeamNewsText.summary(page) == "GW6 · 1 claim about 1 player · 3 flagged by FPL")
        #expect(TeamNewsText.when("2026-10-09T13:05:12.123456+00:00") != "2026-10-09T13:05:12.123456+00:00")
    }
}
