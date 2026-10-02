import Foundation
import Testing
@testable import FPLToolkit

private final class WatchBundleToken {}

/// Matchday's players to watch (happy-backend-pal#66): the settings, what the live request asks
/// for, and decoding the groups and watched feed items.
struct PlayersToWatchTests {
    private typealias Prefs = DevicePrefs.MatchdayPrefs

    @Test func asksForHighlyOwnedByDefault() {
        #expect(Prefs.standard.queryItems == [URLQueryItem(name: "watch", value: "owned")])
        #expect(Prefs.standard.watchesAnyone)
    }

    @Test func asksForEveryGroup() {
        let prefs = Prefs(highlyOwned: true, eliteDifferentials: true, rivals: false, rivalsLeague: nil,
                          rivalsAbove: 2, rivalsBelow: 2, rivalsLeader: true, inFeed: false)
        #expect(prefs.queryItems == [
            URLQueryItem(name: "watch", value: "owned,elite"),
            URLQueryItem(name: "feed", value: "0"),
        ])
    }

    @Test func leaguePositionRivalsAreRetiredAndNothingOnAsksForNothing() {
        // Rivals are your saved ones now (happy-backend-pal#68): old settings ask for nothing extra.
        var prefs = Prefs.standard
        prefs.rivals = true
        prefs.rivalsLeague = 41119
        #expect(prefs.queryItems == [URLQueryItem(name: "watch", value: "owned")])
        prefs.highlyOwned = false
        #expect(prefs.queryItems.isEmpty && !prefs.watchesAnyone)
    }

    @Test func liveRequestCarriesThem() {
        let repo = LiveRepository(client: .production, cache: .shared)
        let endpoint = repo.team(entryId: 22615, gw: 5, watch: .standard)
        #expect(endpoint.base.query == [URLQueryItem(name: "gw", value: "5"), URLQueryItem(name: "watch", value: "owned")])
        #expect(repo.team(entryId: 22615).base.query.isEmpty)
    }

    @Test func settingsSaveWithTheDevicePrefs() throws {
        let patch = DeviceUpdate(prefs: .init(matchday: .standard))
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
        let prefs = try #require(json["prefs"] as? [String: Any])
        // Only the matchday settings: the notification switches are left as they are.
        #expect(Set(prefs.keys) == ["matchday"])
        let matchday = try #require(prefs["matchday"] as? [String: Any])
        #expect(matchday["highlyOwned"] as? Bool == true && matchday["rivalsAbove"] as? Int == 2)
        // A cleared league is sent as null, so the server clears it.
        #expect(matchday["rivalsLeague"] is NSNull)
        let decoded = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(Prefs.standard))
        #expect(decoded == .standard)
    }

    @Test func olderServersHaveNoMatchdaySettings() throws {
        let url = try #require(Bundle(for: WatchBundleToken.self).url(forResource: "device-me", withExtension: "json"))
        let info = try APIClient.decode(Envelope<DeviceInfo>.self, from: Data(contentsOf: url)).data
        #expect(try #require(info.prefs).matchday == nil)
    }

    // MARK: Live team

    private func live(watching: [String: Any]?, feed: [[String: Any]]? = nil) throws -> LiveTeam {
        let url = try #require(Bundle(for: WatchBundleToken.self).url(forResource: "live-team-gw5", withExtension: "json"))
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var data = try #require(envelope["data"] as? [String: Any])
        data["watching"] = watching
        data["feed"] = feed
        envelope["data"] = data
        return try APIClient.decode(Envelope<LiveTeam>.self, from: JSONSerialization.data(withJSONObject: envelope)).data
    }

    private func player(_ id: Int, _ reason: String, points: Int = 2, minutes: Int = 60, state: String = "inPlay",
                        bonus: Int = 0) -> [String: Any] {
        ["playerId": id, "reason": reason, "points": points, "minutes": minutes, "state": state, "provisionalBonus": bonus]
    }

    private var watching: [String: Any] {
        ["groups": [
            ["kind": "highlyOwned", "title": "Highly owned", "detail": "Owned by 20% or more of managers, not in your team",
             "players": [player(8, "51% owned", points: 6, bonus: 2)], "rivals": []],
            ["kind": "rivals", "title": "LEAGUE OF EXPERTS", "detail": "Live from their teams this gameweek", "players": [],
             "rivals": [
                ["entryId": 7, "manager": "Andy Smith", "team": "Andy's XI", "rank": 1, "label": "1st · leader · 12 pts ahead of you",
                 "total": 362, "live": 51, "provisionalBonus": 3, "captainId": 411,
                 "players": [player(411, "Andy's captain ×2 · also in your team", points: 13, state: "done")]],
                ["entryId": 9, "manager": NSNull(), "team": "Late FC", "rank": 4, "label": "4th · level with you",
                 "total": 350, "live": NSNull(), "provisionalBonus": 0, "captainId": NSNull(), "players": []],
             ]],
            ["kind": "somethingNew", "title": "Later", "detail": NSNull(), "players": [], "rivals": []],
        ]]
    }

    @Test func decodesTheGroupsAndStaysOptional() throws {
        #expect(try live(watching: nil).watching == nil)
        let groups = try #require(try live(watching: watching).watching).groups
        #expect(groups.map(\.kind) == [.highlyOwned, .rivals, .unknown])
        #expect(groups[0].players.first == .init(playerId: 8, reason: "51% owned", points: 6, minutes: 60,
                                                 state: .inPlay, provisionalBonus: 2))
        let leader = try #require(groups[1].rivals.first)
        #expect(leader.live == 51 && leader.provisionalBonus == 3 && leader.captainId == 411 && leader.players.count == 1)
        #expect(groups[1].rivals[1].live == nil && groups[1].rivals[1].manager == nil)
    }

    @Test func wording() throws {
        let live = try live(watching: watching)
        let groups = try #require(live.watching).groups
        let owned = try #require(groups[0].players.first)
        #expect(WatchText.state(owned) == "Playing · 60 min")
        #expect(WatchText.spoken(owned) == "51% owned, Playing · 60 min, 6 FPL-recorded points, plus 2 estimated bonus, not included")
        #expect(WatchText.state(.init(playerId: 1, reason: "", points: 0, minutes: 0, state: .done, provisionalBonus: 0)) == "Didn't play")
    }

    @Test func watchedFeedItemsHaveTheirOwnFilter() throws {
        let items: [[String: Any]] = [
            ["id": "w-41-goal-8-1", "kind": "goal", "group": "watching", "fixtureId": 41, "playerId": 8,
             "minute": 23, "at": "2026-09-18T19:23:00.000Z", "state": "confirmed",
             "text": "Calafiori scores", "detail": NSNull(), "points": 6, "watching": "51% owned"],
            ["id": "41-dc-93-10", "kind": "defcon", "group": "defence", "fixtureId": 41, "playerId": 93,
             "minute": 57, "at": "2026-09-18T20:14:00.000Z", "state": "confirmed",
             "text": "Schuster reaches DEFCON", "detail": "10/10 defensive contributions", "points": 2],
        ]
        let feed = try #require(try live(watching: watching, feed: items).feed)
        #expect(feed[0].group == .watching && feed[0].watching == "51% owned" && feed[1].watching == nil)
        #expect(feed.filter(MatchdayFeedFilter.watching.includes).map(\.id) == ["w-41-goal-8-1"])
        #expect(feed.filter(MatchdayFeedFilter.goals.includes).isEmpty)
        #expect(MatchdayText.spoken(feed[0], isNew: false) == "Minute 23. Calafiori scores. Watching: 51% owned. Plus 6 points")
    }
}
