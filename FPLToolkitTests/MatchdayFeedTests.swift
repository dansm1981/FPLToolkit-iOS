import Foundation
import Testing
@testable import FPLToolkit

private final class FeedBundleToken {}

/// Matchday's live feed (happy-backend-pal#61): decoding, the filters and the wording around the
/// server's lines.
struct MatchdayFeedTests {
    private func live(feed: [[String: Any]]?) throws -> LiveTeam {
        let url = try #require(Bundle(for: FeedBundleToken.self).url(forResource: "live-team-gw5", withExtension: "json"))
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var data = try #require(envelope["data"] as? [String: Any])
        data["feed"] = feed
        envelope["data"] = data
        return try APIClient.decode(Envelope<LiveTeam>.self, from: JSONSerialization.data(withJSONObject: envelope)).data
    }

    private let items: [[String: Any]] = [
        ["id": "41-dc-93-10", "kind": "defcon", "group": "defence", "fixtureId": 41, "playerId": 93,
         "minute": 57, "at": "2026-09-18T20:14:00.000Z", "state": "confirmed",
         "text": "Schuster reaches DEFCON", "detail": "10/10 defensive contributions", "points": 2],
        ["id": "41-yellowCard-106-1", "kind": "yellowCard", "group": "match", "fixtureId": 41, "playerId": 106,
         "minute": 84, "at": "2026-09-18T20:41:00.000Z", "state": "reported",
         "text": "Thiago is booked", "detail": "FPL points updating", "points": NSNull()],
        ["id": "41-halfTime", "kind": "halfTime", "group": "match", "fixtureId": 41, "playerId": NSNull(),
         "minute": NSNull(), "at": "2026-09-18T19:47:00.000Z", "state": "confirmed",
         "text": "Half-time: BRE 0–0 CHE", "detail": NSNull(), "points": NSNull()],
        ["id": "41-lineup-105", "kind": "lineup", "group": "lineups", "fixtureId": 41, "playerId": 105,
         "minute": NSNull(), "at": "2026-09-18T18:00:00.000Z", "state": "confirmed",
         "text": "Anthony starts", "detail": "Your captain", "points": NSNull(), "lineup": "starting"],
        ["id": "41-future", "kind": "somethingNew", "group": "somewhere", "fixtureId": 41, "playerId": NSNull(),
         "minute": NSNull(), "at": "2026-09-18T18:00:00.000Z", "state": "confirmed",
         "text": "A later server's line", "detail": NSNull(), "points": -1],
    ]

    @Test func decodesTheFeedAndStaysOptional() throws {
        #expect(try live(feed: nil).feed == nil)
        let feed = try #require(try live(feed: items).feed)
        #expect(feed.map(\.kind) == [.defcon, .yellowCard, .halfTime, .lineup, .unknown])
        #expect(feed[0].points == 2 && feed[0].group == .defence && feed[0].minute == 57)
        #expect(feed[1].state == .reported && feed[1].points == nil)
        #expect(feed[3].lineup == .starting && feed[4].group == .unknown)
        #expect(feed[0].at == Date(timeIntervalSince1970: 1_789_762_440))
    }

    @Test func filtersByTheServersGroups() throws {
        let feed = try #require(try live(feed: items).feed)
        #expect(feed.filter(MatchdayFeedFilter.all.includes).count == 5)
        #expect(feed.filter(MatchdayFeedFilter.defence.includes).map(\.id) == ["41-dc-93-10"])
        #expect(feed.filter(MatchdayFeedFilter.lineups.includes).map(\.id) == ["41-lineup-105"])
        #expect(feed.filter(MatchdayFeedFilter.goals.includes).isEmpty)
    }

    @Test func wording() throws {
        let feed = try #require(try live(feed: items).feed)
        #expect(feed.map(MatchdayText.feedTime) == ["57′", "84′", "HT", "", ""])
        #expect(MatchdayText.signedPoints(2) == "+2" && MatchdayText.signedPoints(-1) == "−1")
        #expect(MatchdayText.spoken(feed[0], isNew: true)
            == "New. Minute 57. Schuster reaches DEFCON. 10/10 defensive contributions. Plus 2 points")
        #expect(MatchdayText.spoken(feed[2], isNew: false) == "Half-time: BRE 0–0 CHE")
        #expect(MatchdayText.symbol(feed[3]) == "checkmark.circle")
    }

    @Test func remembersTheFeedItemsSeen() throws {
        let live = try live(feed: items)
        let seen = MatchdayMemory.Seen(total: 45, momentIds: [], at: .now, feedIds: live.feed?.map(\.id))
        let decoded = try JSONDecoder().decode(MatchdayMemory.Seen.self, from: JSONEncoder().encode(seen))
        #expect(decoded.feedIds?.count == 5)
        // Saved by a build before the feed.
        let old = #"{"total":45,"momentIds":[],"at":0}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(MatchdayMemory.Seen.self, from: old).feedIds == nil)
    }
}
