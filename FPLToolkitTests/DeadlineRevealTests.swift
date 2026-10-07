import Foundation
import Testing
@testable import FPLToolkit

/// The Deadline reveal (tasks/deadline-reveal.md): decoding, its wording, and the link to it.
struct DeadlineRevealTests {
    static let json = """
    {"gameweek": 6, "deadline": "2026-10-10T10:00:00Z", "ready": false,
     "readyText": "1 of 2 leagues updated · usually 20–40 minutes after the deadline",
     "headline": {"title": "Deadline reveal: Andy took a −4 and captained Haaland", "body": "See who did what."},
     "you": {"entryId": 1, "name": "Dan", "teamName": "All priced in", "rank": 3, "transfers": [{"out": 5, "in": 4}],
             "cost": 0, "chip": null, "captainId": 2, "viceId": 6, "isMe": true, "summary": "1 transfer · Salah (C)"},
     "rivals": [{"entryId": 9, "name": "Andy", "teamName": "Andiletic", "transfers": [{"out": 5, "in": 4}, {"out": 6, "in": 1}],
                 "cost": 4, "chip": {"chip": "bboost", "label": "Bench Boost"}, "captainId": 1, "viceId": 3,
                 "summary": "2 transfers · −4 hit · Haaland (C) · Bench Boost", "featured": true,
                 "theirs": [1, 4], "mine": [2, 6], "differenceText": "2 players different from you"}],
     "leagues": [{"id": 783382, "name": "LEAGUE OF EXPERTS", "managers": 21, "synced": true,
                  "headline": "9 of 21 made transfers · 3 took hits · 2 chips",
                  "chips": [{"chip": "bboost", "label": "Bench Boost", "count": 2}],
                  "mostBought": [{"playerId": 4, "count": 8}], "mostSold": [{"playerId": 5, "count": 6}],
                  "captains": [{"playerId": 1, "count": 13, "pct": 62}],
                  "captainText": "62% captained Haaland; you went Salah, with 4 others",
                  "rows": [{"entryId": 9, "name": "Andy Bride", "teamName": null, "rank": 1, "transfers": [], "cost": 0,
                            "chip": null, "captainId": 1, "viceId": null, "isMe": false, "summary": "No transfers · Haaland (C)"}]}],
     "elite": null,
     "players": {"1": {"id": 1, "webName": "Haaland", "photo": null, "clubId": 1, "position": "FWD", "price": 10.0, "availability": {"code": "a", "level": "ok", "chanceNext": null, "news": null}, "selectedByPct": 10.0, "nextFixture": null}, "4": {"id": 4, "webName": "Isak", "photo": null, "clubId": 1, "position": "FWD", "price": 10.0, "availability": {"code": "a", "level": "ok", "chanceNext": null, "news": null}, "selectedByPct": 10.0, "nextFixture": null}, "5": {"id": 5, "webName": "Wissa", "photo": null, "clubId": 1, "position": "FWD", "price": 10.0, "availability": {"code": "a", "level": "ok", "chanceNext": null, "news": null}, "selectedByPct": 10.0, "nextFixture": null}}}
    """

    @Test func decodesAndReads() throws {
        let r = try APIClient.decode(Reveal.self, from: Data(Self.json.utf8))
        #expect(!r.ready && r.rivals.first?.featured == true && r.leagues.first?.captains.first?.pct == 62)
        #expect(RevealText.move(r.rivals[0].transfers[0], r) == "Wissa → Isak")
        #expect(RevealText.difference(r.rivals[0], r) == "2 players different from you: Haaland, Isak")
        #expect(RevealText.counts(r.leagues[0].mostBought, r) == "Isak (8)")
    }

    @Test func linkOpensTheReveal() throws {
        #expect(DeepLink(url: try #require(URL(string: "fpltoolkit://reveal"))) == .reveal)
    }

    @Test func revealSwitchReadsOnUntilTurnedOff() throws {
        let n = try JSONDecoder().decode(DevicePrefs.Notifications.self, from: Data(#"{"price": true, "availability": true, "deadline24h": false, "deadline3h": true}"#.utf8))
        #expect(n.revealOn && n.reveal == nil)
        var off = n
        off.revealOn = false
        #expect(off.reveal == false)
    }
}
