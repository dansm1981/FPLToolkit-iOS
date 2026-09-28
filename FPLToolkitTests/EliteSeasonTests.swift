import Foundation
import Testing
@testable import FPLToolkit

private final class EliteSeasonBundleToken {}

/// The Elite group's season screens (happy-backend-pal#31), GW5. Captured 28 Sep 2026 from
/// production; each page checked against the website's.
struct EliteSeasonTests {
    @Test func race() throws {
        let page = try fixture("elite-race-5", as: EliteRace.self)
        let r = try #require(page.body)
        #expect(r.position == nil && r.title == "Top 10 overall" && r.weeks == [1, 2, 3, 4, 5])
        #expect(r.tabs.map(\.count) == [10, 6, 10, 10, 8] && r.tabs[1].position == .gk)
        let top = try #require(r.contenders.first)
        #expect(page.player(top.playerId)?.webName == "Palmer" && top.owned.display == "85%")
        #expect(top.change.shown == "+54.0pp" && top.band == "Elite Core" && top.series == [31, 31, 32, 95, 85])
        let keepers = try #require(try fixture("elite-race-5-gk", as: EliteRace.self).body)
        #expect(keepers.position == .gk && keepers.title == "Goalkeepers" && keepers.contenders.count == 6)
    }

    @Test func movers() throws {
        let page = try fixture("elite-movers-5", as: EliteMovers.self)
        let m = try #require(page.body)
        #expect(m.stats.map(\.value) == ["39.0%", "-39.0%", "12", "44"])
        #expect(m.stats[0].sub == "Barry" && m.stats[1].sub == "João Pedro")
        #expect(m.risers[0] == EliteMoverRow(playerId: 249, change: EliteChange(value: 39, display: "39.0pp"), now: "51%"))
        #expect(m.risers.count == 10 && m.risers3.count == 10 && m.fallers.count == 10 && m.entrants.count == 10)
        #expect(m.bandMoves.count == 44 && m.bandMoves[0].text == "entered Template (40%)" && m.bandMoves[0].band == "Template")
    }

    @Test func trends() throws {
        let t = try #require(try fixture("elite-trends-5", as: EliteTrends.self).body)
        #expect(t.stats.map(\.value) == ["41.5", "372k", "93%", "1%"])
        #expect(t.rows.map(\.gameweek) == [1, 2, 3, 4, 5])
        #expect(t.rows[0].meanPoints == "70.0" && t.rows[0].medianRank == "399k" && t.rows[0].template == "66%")
        #expect(t.rising[0].change.shown == "+73.0pp" && t.rising[0].now == "75%" && t.cooling.count == 10)
    }

    @Test func compare() throws {
        let c = try #require(try fixture("elite-compare-5", as: EliteCompare.self).body)
        #expect(c.ids == [411, 154, 249] && c.metrics.map(\.key) == ["owned", "start", "captain", "edge", "overall"])
        let haaland = c.rows[0]
        #expect(haaland.now.display == "82%" && haaland.trend.display == "+50pp" && haaland.band == "Elite Core")
        #expect(haaland.series.values("captain") == [16, 4, 97, 1, 81])
        #expect(haaland.series.values("edge") == [-37.4, -39.2, 24.1, -1.8, 8.2])
        #expect(haaland.series.values("unknown") == haaland.series.values("owned"))
    }

    @Test func chips() throws {
        let c = try #require(try fixture("elite-chips-5", as: EliteChips.self).body)
        #expect(c.played[0] == EliteStat(label: "Wildcard", value: "11%", sub: "38% still hold it", accent: true))
        #expect(c.labels == ["Wildcard", "Free Hit", "Bench Boost", "Triple Captain"])
        #expect(c.timeline[2].cells == ["38%", "29%", "—", "27%"] && c.available.count == 4)
    }

    @Test func structure() throws {
        let s = try #require(try fixture("elite-structure-5", as: EliteStructure.self).body)
        #expect(s.stats.map(\.value) == ["£101.1m", "£0.8m", "£20.3m", "3-5-2"])
        #expect(s.formations[0].formation == "3-5-2" && s.formations[0].display == "34%")
        #expect(s.spend.map(\.label) == ["Goalkeepers", "Defenders", "Midfielders", "Forwards", "Starting XI", "Bench"])
        #expect(s.squad.count == 3 && s.timeline.last?.bench == "£20.3m")
    }

    @Test func paths() {
        let repo = EliteRepository(client: .production, cache: .shared)
        #expect(repo.race(gw: nil, position: nil).path == "elite/race" && repo.race(gw: nil, position: nil).query.isEmpty)
        #expect(repo.race(gw: 3, position: .def).query.map { "\($0.name)=\($0.value ?? "")" } == ["gw=3", "position=DEF"])
        #expect(repo.compare(gw: nil, ids: [411, 154]).query == [URLQueryItem(name: "ids", value: "411,154")])
        #expect(repo.compare(gw: nil, ids: []).query.isEmpty)
        #expect([repo.movers(gw: nil).path, repo.trends(gw: nil).path, repo.chips(gw: nil).path, repo.structure(gw: nil).path]
            == ["elite/movers", "elite/trends", "elite/chips", "elite/structure"])
    }

    @Test func spokenLine() {
        #expect(EliteLineChart.spoken(weeks: [1, 2, 3], values: [30, nil, 45.5]) == "GW1 30%, GW3 45.5%")
        #expect(EliteLineChart.spoken(weeks: [4], values: [-1.8], unit: "pp") == "GW4 -1.8pp")
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> ElitePage<T> {
        let url = try #require(Bundle(for: EliteSeasonBundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decode(Envelope<ElitePage<T>>.self, from: Data(contentsOf: url)).data
    }
}
