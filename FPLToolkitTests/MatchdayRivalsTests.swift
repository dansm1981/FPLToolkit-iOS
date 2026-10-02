import Foundation
import Testing
@testable import FPLToolkit

private final class MatchdayRivalsBundleToken {}

/// Rivals on the live matchday (happy-backend-pal#68): the rivals block, each event's effect on
/// your rivalries, the Rivals filter and the catch-up line. The rows are the captured /rivals ones.
struct MatchdayRivalsTests {
    private func json(_ name: String) throws -> [String: Any] {
        let url = try #require(Bundle(for: MatchdayRivalsBundleToken.self).url(forResource: name, withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private var featured: [String: Any] {
        ["entryId": 1699334, "name": "Andy",
         "changed": "Groß scores · gains Andy 6 on you",
         "now": [["kind": "defcon", "playerId": 449, "effect": 2,
                  "text": "One more defensive action for Hall would gain you 2 on Andy"],
                 ["kind": "later", "playerId": 1, "effect": 0, "text": "A later server's situation"]],
         "next": [["fixtureId": 41, "kickoff": "2026-10-10T16:30:00.000Z", "yours": [449], "theirs": [],
                   "text": "NEW v ARS · you have Hall"]]]
    }

    private func live(rivals: Bool = true, feed: [[String: Any]]? = nil) throws -> LiveTeam {
        var envelope = try json("live-team-gw5")
        var data = try #require(envelope["data"] as? [String: Any])
        if rivals {
            let rows = try #require((try json("rivals")["data"] as? [String: Any])?["rivals"])
            data["rivals"] = ["rows": rows, "featured": featured]
        }
        data["feed"] = feed
        envelope["data"] = data
        return try APIClient.decode(Envelope<LiveTeam>.self, from: JSONSerialization.data(withJSONObject: envelope)).data
    }

    private let items: [[String: Any]] = [
        ["id": "r-41-goal-124-1", "kind": "goal", "group": "rivals", "fixtureId": 41, "playerId": 124,
         "minute": 23, "at": "2026-09-18T19:23:00.000Z", "state": "confirmed", "text": "Groß scores",
         "detail": NSNull(), "points": 6,
         "rivals": [["entryId": 1699334, "name": "Andy", "effect": -6, "text": "Gains Andy 6 on you"],
                    ["entryId": 7409161, "name": "Big Paul", "effect": -6, "text": "Gains Big Paul 6 on you"],
                    ["entryId": 9, "name": "Chris", "effect": -6, "text": "Gains Chris 6 on you"]]],
        ["id": "41-dc-93-10", "kind": "defcon", "group": "defence", "fixtureId": 41, "playerId": 93,
         "minute": 57, "at": "2026-09-18T20:14:00.000Z", "state": "confirmed",
         "text": "Schuster reaches DEFCON", "detail": "10/10 defensive contributions", "points": 2],
    ]

    @Test func decodesTheRivalsAndStaysOptional() throws {
        #expect(try live(rivals: false).rivals == nil)
        let r = try #require(try live().rivals)
        #expect(r.rows.map(\.name) == ["Andy", "Big Paul"])
        let f = try #require(r.featured)
        #expect(f.changed == "Groß scores · gains Andy 6 on you" && f.now.count == 2 && f.now[1].kind == .unknown)
        #expect(f.next.first?.yours == [449] && f.next.first?.kickoff != nil)
        #expect(MatchdayMemory.featuredRow(try live())?.gap == -30)
    }

    @Test func feedItemsCarryTheirEffectAndHaveAFilter() throws {
        let feed = try #require(try live(feed: items).feed)
        #expect(feed[0].group == .rivals && feed[0].rivals?.count == 3 && feed[1].rivals == nil)
        #expect(feed.filter(MatchdayFeedFilter.rivals.includes).map(\.id) == ["r-41-goal-124-1"])
        #expect(feed.filter(MatchdayFeedFilter.goals.includes).isEmpty)
        #expect(MatchdayText.spoken(feed[0], isNew: false)
            == "Minute 23. Groß scores. Gains Andy 6 on you. Gains Big Paul 6 on you. Gains Chris 6 on you. Plus 6 points")
    }

    @Test func catchUpSaysHowTheFeaturedRivalryMoved() throws {
        let live = try live()
        let seen = MatchdayMemory.Seen(total: live.total.estimated, momentIds: live.moments.map(\.id), at: .now,
                                       feedIds: nil, rivalId: 1699334, rivalGap: -24)
        #expect(MatchdayMemory.catchUp(live, since: seen) == "Since you last checked. No change to your score. Andy's lead grew from 24 to 30.")
        // Another featured rival then: no rivalry line.
        let other = MatchdayMemory.Seen(total: live.total.estimated, momentIds: live.moments.map(\.id), at: .now,
                                        feedIds: nil, rivalId: 7409161, rivalGap: 5)
        #expect(MatchdayMemory.catchUp(live, since: other) == nil)
        // Saved by a build before rivals.
        let old = #"{"total":45,"momentIds":[],"at":0}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(MatchdayMemory.Seen.self, from: old).rivalGap == nil)
    }

    @Test func rivalryLines() {
        #expect(MatchdayMemory.rivalLine(name: "Andy", was: 3, now: 9) == "Your lead over Andy grew from 3 to 9")
        #expect(MatchdayMemory.rivalLine(name: "Andy", was: 9, now: 3) == "Your lead over Andy fell from 9 to 3")
        #expect(MatchdayMemory.rivalLine(name: "Andy", was: -9, now: -3) == "Andy's lead fell from 9 to 3")
        #expect(MatchdayMemory.rivalLine(name: "Andy", was: -3, now: 4) == "You've gone from 3 behind Andy to 4 ahead of Andy")
        #expect(MatchdayMemory.rivalLine(name: "Andy", was: 2, now: 0) == "You've gone from 2 ahead of Andy to level with Andy")
        #expect(MatchdayMemory.rivalLine(name: "Andy", was: 4, now: 4) == nil)
    }

    @Test func rivalsRequestHasItsOwnAddress() {
        let repo = LiveRepository(client: .production, cache: .shared)
        let session = DeviceSession(client: .production)
        let endpoint = repo.team(entryId: 22615, watch: .standard, rivalsVia: session)
        #expect(endpoint.base.query.last == URLQueryItem(name: "rivals", value: "1"))
        #expect(endpoint.session != nil)
        #expect(repo.team(entryId: 22615).session == nil)
    }
}
