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
}
