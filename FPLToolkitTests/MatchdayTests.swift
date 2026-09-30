import Foundation
import Testing
@testable import FPLToolkit

private final class MatchdayBundleToken {}

/// Matchday (happy-backend-pal#36, #37). Captured 28 Sep 2026 from production:
/// /live/team/22615?gw=5 (Dan's team; FPL's official GW5 score is 45).
struct MatchdayTests {
    @Test func decodesTheLiveTeam() throws {
        let live = try fixture()
        #expect(live.gameweek == 5 && live.status == .finished && live.chip == nil)
        #expect(live.total == LiveTeam.Total(estimated: 45, confirmed: 45, provisionalBonus: 0, transferCost: 0, benchPoints: 14))
        #expect(live.squad.count == 15 && live.squad.filter(\.counted).count == 11)
        let captain = try #require(live.squad.first { $0.playerId == live.captainId })
        #expect(captain.multiplier == 2 && live.player(captain.playerId)?.webName == "Haaland")
        let hall = try #require(live.squad.first { live.player($0.playerId)?.webName == "Hall" })
        #expect(hall.next.defcon == LiveTeam.NextPoints.Defcon(count: 10, threshold: 10, reached: true))
        #expect(hall.next.saves == nil && hall.lineup == .starting && hall.context != nil)
        #expect(live.moments.map(\.kind).contains(.goal) && live.moments.allSatisfy { $0.state != .unknown })
        #expect(live.fixtures.contains { $0.bonusConfirmed && $0.state == .finished })
    }

    @Test func pointsAddUpToTheTotal() throws {
        let live = try fixture()
        let counted = live.squad.filter(\.counted).reduce(0) { $0 + $1.points * $1.multiplier }
        #expect(counted - live.total.transferCost == live.total.confirmed)
        #expect(live.squad.filter { !$0.counted }.reduce(0) { $0 + $1.points } == live.total.benchPoints)
    }

    @Test func catchUpSaysWhatChanged() throws {
        let live = try fixture()
        #expect(MatchdayMemory.catchUp(live, since: .init(total: 45, momentIds: live.moments.map(\.id), at: .now)) == nil)
        let first = try #require(live.moments.last)
        let text = try #require(MatchdayMemory.catchUp(
            live, since: .init(total: 38, momentIds: live.moments.dropLast().map(\.id), at: .now)))
        #expect(text.hasPrefix("Since you last checked: \(MatchdayText.moment(first, live: live))"))
        #expect(text.hasSuffix("Up 7."))
    }

    @Test func wording() throws {
        let live = try fixture()
        let goal = try #require(live.moments.first { $0.kind == .goal })
        #expect(MatchdayText.moment(goal, live: live).hasSuffix("scored"))
        #expect(MatchdayText.status(.awaitingBonus) == "Awaiting bonus")
        #expect(MatchdayText.status(.finished) == "Complete")
        #expect(MatchdayText.chip("3xc") == "Triple Captain" && MatchdayText.chip(nil) == nil)
        #expect(MatchdayText.stat("defensive_contribution", value: 13) == "DEFCON (13 contributions)")
        #expect(MatchdayText.stat("minutes", value: 90) == "90 minutes")
    }

    @Test func matchdayLink() throws {
        #expect(DeepLink(url: try #require(URL(string: "fpltoolkit://matchday"))) == .matchday)
        let repo = LiveRepository(client: .production, cache: .shared)
        #expect(repo.team(entryId: 22615).base.path == "live/team/22615" && repo.team(entryId: 22615).base.query.isEmpty)
        #expect(repo.team(entryId: 22615, gw: 5).base.query == [URLQueryItem(name: "gw", value: "5")])
    }

    private func fixture() throws -> LiveTeam {
        let url = try #require(Bundle(for: MatchdayBundleToken.self).url(forResource: "live-team-gw5", withExtension: "json"))
        return try APIClient.decode(Envelope<LiveTeam>.self, from: Data(contentsOf: url)).data
    }
}
