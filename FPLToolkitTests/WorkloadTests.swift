import Foundation
import Testing
@testable import FPLToolkit

private final class WorkloadBundleToken {}

/// Minutes in all competitions (happy-backend-pal#40, #41). Captured 29 Sep 2026 from production:
/// /workload for the GW5 squad of entry 22615 plus Trafford, Branthwaite and Lindelöf.
struct WorkloadTests {
    @Test func decodesEveryCompetition() throws {
        let page = try fixture()
        #expect(page.players.count == 18)
        let konsa = try #require(page.workload(31))
        #expect(konsa.last7 == 90 && konsa.last14 == 225)
        #expect(konsa.lastMatch?.kind == .international && konsa.lastMatch?.team == "England")
        #expect(konsa.otherCompetitions.map(\.kind) == [.international, .cup, .europe])
        let cup = konsa.otherCompetitions[1]
        #expect(cup.competition == "League Cup" && cup.opponent == "Ipswich" && cup.minutes == 45 && !cup.started)
    }

    @Test func premierLeagueMatchesHaveNoTeamName() throws {
        let palmer = try #require(try fixture().workload(154))
        let last = try #require(palmer.lastMatch)
        #expect(last.kind == .league && last.team == nil && last.opponent == "BRE")
        #expect(WorkloadText.match(last).hasSuffix(" · Premier League · v BRE · 90 min"))
    }

    @Test func marksSubstituteAppearances() throws {
        let page = try fixture()
        let branthwaite = try #require(page.workload(230)?.lastMatch)
        #expect(WorkloadText.match(branthwaite).hasSuffix(" · UEFA Nations League · England v Spain · 1 min (sub)"))
        let trafford = try #require(page.workload(385)?.lastMatch)
        #expect(WorkloadText.match(trafford).hasSuffix(" · England v Spain · 90 min"))
        #expect(WorkloadText.summary(try #require(page.workload(230)))
                == "91 min in the last 14 days · 1 in the last 7 (all competitions)")
    }

    @Test func unknownCompetitionKindsStillDecode() throws {
        let json = #"{"players":{"1":{"last7":0,"last14":0,"lastMatch":{"date":"2026-09-26T18:45:00+00:00","competition":"Club World Cup","kind":"worldClub","team":null,"opponent":null,"minutes":30,"started":false},"otherCompetitions":[]}}}"#
        let page = try APIClient.decode(WorkloadPage.self, from: Data(json.utf8))
        #expect(page.workload(1)?.lastMatch?.kind == .unknown)
        #expect(page.workload(2) == nil)
    }

    private func fixture() throws -> WorkloadPage {
        let url = try #require(Bundle(for: WorkloadBundleToken.self).url(forResource: "workload-players", withExtension: "json"))
        return try APIClient.decode(Envelope<WorkloadPage>.self, from: Data(contentsOf: url)).data
    }
}
