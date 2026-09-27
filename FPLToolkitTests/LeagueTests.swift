import Foundation
import Testing
@testable import FPLToolkit

/// Leagues (happy-backend-pal#21): shapes and the baseline switch.
struct LeagueTests {
    @Test func baselineQuery() {
        #expect(LeagueBaseline.team.queryItems.map(\.description) == ["baseline=team"])
        let draft = LeagueBaseline.draft(id: "abc", name: "Wildcard GW8")
        #expect(draft.queryItems.map(\.description) == ["baseline=draft", "draftId=abc"])
        #expect(draft.label == "Wildcard GW8" && LeagueBaseline.team.label == "My FPL team")
    }

    @Test func leagueList() throws {
        let json = #"""
        {"leagues":[
          {"id":900000000,"name":"Elite 100","isElite":true,"managers":100,"tracked":100,"syncedGw":5,"lastSyncedAt":null,"synced":true,"myRank":null,"gapToFirst":null},
          {"id":783382,"name":"LEAGUE OF EXPERTS","isElite":false,"managers":21,"tracked":21,"syncedGw":5,"lastSyncedAt":"2026-09-27T10:30:06Z","synced":true,"myRank":2,"gapToFirst":30}],
         "sharedRivals":[{"entryId":5,"name":"Jamie McBride","leagues":[{"id":783382,"name":"LEAGUE OF EXPERTS","rank":9,"total":343},{"id":12,"name":"Classic 26/27","rank":47,"total":343}]}],
         "max":10}
        """#
        let list = try JSONDecoder().decode(LeagueList.self, from: Data(json.utf8))
        #expect(list.leagues.first?.isElite == true)
        #expect(list.leagues.last?.myRank == 2 && list.leagues.last?.gapToFirst == 30)
        #expect(list.sharedRivals.first?.leagues.count == 2 && list.max == 10)
    }

    /// Live responses (27 Sep, after happy-backend-pal#22) for team 22615 and LEAGUE OF EXPERTS:
    /// the same figures the website shows.
    @Test func liveLeague() throws {
        let list = try fixture("leagues-list-783382", as: LeagueList.self)
        #expect(list.leagues.map(\.name) == ["Elite 100", "LEAGUE OF EXPERTS"])
        let overview = try fixture("league-overview-783382", as: LeagueOverview.self)
        #expect(overview.headline.position.rank == 2 && overview.headline.position.of == 21)
        #expect(overview.headline.similarityPct == 67 && overview.headline.chips.total == 22)
        #expect(overview.player(overview.headline.biggestThreat!.playerId)?.webName == "B.Fernandes")
        #expect(overview.threats.prefix(5).map(\.score) == [35, 33, 30, 25, 18])
        let standings = try fixture("league-standings-783382", as: LeagueStandings.self)
        #expect(standings.rows.first?.teamName == "Andiletic BilBride" && standings.rows.contains { $0.isMe })
        let vs = try fixture("league-vs-783382", as: LeagueVs.self)
        #expect(vs.them.starting.count == 11 && vs.headToHead != nil)
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        let bundle = Bundle(for: LeagueBundleToken.self)
        let url = try #require(
            bundle.url(forResource: name, withExtension: "json")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "api-v1"))
        return try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }
}
private final class LeagueBundleToken {}
