import Foundation
import Testing
@testable import FPLToolkit

private final class PlayersBundleToken {}

/// The Players screens (happy-backend-pal#27). Responses captured 28 Sep 2026 from the branch, each
/// checked against the website's page.
struct PlayersResearchTests {
    @Test func insights() throws {
        let d = try fixture("players-insights", as: PlayerInsights.self)
        #expect(d.gw == 6 && d.fdrHorizon == 6 && !d.per90)
        #expect(d.sort.key == "total_points" && d.sort.dir == "desc")
        #expect(d.count == 250 && d.rows.count == 100 && d.columns.count == 27)
        // The website's default columns, in its table order.
        #expect(d.shown == ["now_cost_m", "total_points", "form", "points_per_million", "selected_by_percent",
                            "expected_goal_involvements", "bps", "defensive_contribution", "fdr_sum"])
        #expect(d.rows.prefix(3).compactMap { d.player($0.playerId)?.webName } == ["Groß", "Tarkowski", "Bogle"])
        #expect(d.rows.first?.values["total_points"] == ShownValue(value: 47, display: "47"))
        #expect(d.column("fdr_sum")?.label == "FDR6")
        #expect(d.rows.allSatisfy { row in d.shown.allSatisfy { row.values[$0] != nil } })
    }

    @Test func insightsByDifficulty() throws {
        let d = try fixture("players-insights-def-fdr", as: PlayerInsights.self)
        // Sorting by the difficulty sum defaults to easiest first, as the website's column does.
        #expect(d.sort.key == "fdr_sum" && d.sort.dir == "asc" && d.per90 && d.fdrHorizon == 3)
        #expect(d.rows.allSatisfy { d.player($0.playerId)?.position == .def })
        #expect(d.column("fdr_sum")?.label == "FDR3")
        let sums = d.rows.compactMap { $0.values["fdr_sum"]?.value }
        #expect(sums == sums.sorted())
    }

    @Test func opportunity() throws {
        let map = try fixture("players-opportunity", as: OpportunityMap.self)
        #expect(map.metric.key == "xgi90" && map.metric.per90 && map.metrics.count == 5)
        #expect(map.filter.maxOwn == 15 && map.filter.minMins == 0 && map.filter.position == nil)
        #expect(map.points.count == 298 && map.points.filter(\.labelled).count == 6)
        #expect(map.points.allSatisfy { $0.own <= 15 })
        #expect(map.top.count == 12 && map.player(map.top[0].playerId)?.webName == "Hinshelwood" && map.top[0].display == "2.04")
        #expect(map.medianOwnership == 0.7)
    }

    @Test func template() throws {
        let team = try fixture("players-template", as: TemplateTeam.self)
        #expect(team.formation == "3-5-2" && team.cost.display == "£86.1m" && team.points == 367)
        #expect(team.averageOwnership.display == "41.4%")
        #expect(team.xi.count == 11 && team.essential.count == 17)
        #expect(team.player(team.xi[0].playerId)?.webName == "Raya")
        #expect(team.essential.allSatisfy { $0.own >= 20 })
    }

    @Test func injuries() throws {
        let list = try fixture("players-injuries", as: InjuryList.self)
        #expect(list.counts.flagged == 209 && list.counts.owned == 11 && list.counts.doubtful == 29 && list.counts.ruledOut == 180)
        #expect(list.groups.map(\.key) == ["i", "s", "u", "d"])
        #expect(list.groups.map(\.rows.count) == [71, 4, 105, 29])
        for group in list.groups {
            let owned = group.rows.map(\.own)
            #expect(owned == owned.sorted(by: >))
        }
    }

    @Test func queries() {
        let repo = PlayersResearchRepository(client: .production, cache: .shared)
        #expect(repo.insights(position: .def, club: 14, search: " sa ", sort: "fdr_sum", ascending: nil, per90: true, fdrHorizon: 3)
            .query.map(\.description) == ["sort=fdr_sum", "fdr=3", "per90=1", "position=DEF", "club=14", "q=sa"])
        #expect(repo.insights(position: nil, club: nil, search: "", sort: "form", ascending: true, per90: false, fdrHorizon: 6)
            .query.map(\.description) == ["sort=form", "fdr=6", "dir=asc"])
        #expect(repo.opportunity(metric: "ppm", position: .fwd, maxOwn: 50, minMins: 450).query.map(\.description)
            == ["metric=ppm", "maxOwn=50", "minMins=450", "position=FWD"])
    }

    @Test func lastDraft() {
        let defaults = UserDefaults.standard
        let saved = (defaults.string(forKey: LastDraft.idKey), defaults.string(forKey: LastDraft.nameKey))
        defer {
            defaults.set(saved.0, forKey: LastDraft.idKey)
            defaults.set(saved.1, forKey: LastDraft.nameKey)
        }
        LastDraft.remember(id: "abc", name: "Wildcard")
        #expect(LastDraft.id == "abc" && LastDraft.name == "Wildcard")
        LastDraft.forget(id: "other")
        #expect(LastDraft.id == "abc")
        LastDraft.forget(id: "abc")
        #expect(LastDraft.id == nil && LastDraft.name == nil)
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        let url = try #require(Bundle(for: PlayersBundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }
}
