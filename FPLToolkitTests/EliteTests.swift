import Foundation
import Testing
@testable import FPLToolkit

private final class EliteBundleToken {}

/// The Research tab's Elite group (happy-backend-pal#29), GW5 and GW1. Captured 28 Sep 2026 from
/// production; each page checked against the website's.
struct EliteTests {
    @Test func overview() throws {
        let page = try fixture("elite-overview-5", as: EliteOverview.self)
        let o = try #require(page.body)
        #expect(page.gw == 5 && page.gameweeks == [5, 4, 3, 2, 1])
        #expect(o.signals.map(\.title) == ["Captain consensus", "Mass sell-off", "Elite stampede", "Chip surge"])
        #expect(o.signals[0].tone == .green)
        #expect(o.snapshot.count == 12 && o.snapshot[0] == EliteStat(label: "Median GW points", value: "42", sub: "Mean 41.5", accent: true))
        #expect(o.bought[0].display == "36%" && o.bought[0].change?.shown == "+39.0pp" && page.player(249)?.webName == "Barry")
        #expect(o.cooling[0].change.shown == "−71.0pp" && o.cooling[0].change.spoken == "down 71.0pp")
        #expect(o.favourites[0].edge == "+59.2pp" && o.favourites[0].detail == "85% vs 26%")
        #expect(o.captains[0].detail == "conviction 99%")
        #expect(o.positions[0].position == .gk && o.positions[0].averageSpend == "£9.5m" && o.positions[0].top.count == 3)
        #expect(o.formations.map(\.formation) == ["3-5-2", "3-4-3", "4-4-2", "4-3-3"])
        #expect(o.chips[0] == EliteStat(label: "Wildcard", value: "11%", sub: "38% still available", accent: false))
        #expect(o.pitch.rows.map(\.count) == [1, 3, 5, 2] && o.pitch.bench.count == 4)
        #expect(o.pitch.rows[3][0].captain == "81%" && o.pitch.rows[3][0].price == "£15.6m")
    }

    @Test func ownership() throws {
        let page = try fixture("elite-ownership-5", as: EliteOwnership.self)
        let o = try #require(page.body)
        #expect(o.count == 115 && o.rows.count == 115 && o.priceCap == 16)
        #expect(o.filter.position == nil && o.filter.view == "all" && o.filter.sort == "owned_pct" && o.filter.dir == "desc")
        let top = o.rows[0]
        #expect(page.player(top.playerId)?.webName == "Palmer" && top.owned.display == "85%")
        #expect(top.overall == "25.8%" && top.edge == "+59.2pp" && top.change.shown == "−10.0pp")
        let mid = try #require(try fixture("elite-ownership-5-mid-core", as: EliteOwnership.self).body)
        #expect(mid.filter.position == .mid && mid.filter.view == "core" && mid.filter.dir == "asc" && mid.count == 5)
    }

    @Test func transfers() throws {
        let page = try fixture("elite-transfers-5", as: EliteTransfers.self)
        let t = try #require(page.body)
        #expect(t.stats.map(\.value) == ["0.60", "1%", "0.0 pts", "100"])
        #expect(t.bought.count == 15 && t.sold.count == 15 && t.net.count == 12 && t.moves.count == 20)
        #expect(page.player(t.moves[0].outId)?.webName == "João Pedro" && page.player(t.moves[0].inId)?.webName == "Barry")
        #expect(t.moves[0].display == "25%")
    }

    @Test func captaincy() throws {
        let page = try fixture("elite-captaincy-5", as: EliteCaptaincy.self)
        let c = try #require(page.body)
        #expect(c.stats.map(\.value) == ["Haaland", "High consensus", "99%", "0%"])
        #expect(c.stats[1].sub == "5 different captains" && c.stats[3].sub == nil)
        #expect(c.captains.count == 5 && c.conviction.count == 5 && c.vices.count == 10)
        #expect(c.vices[0].display == "36%" && page.player(c.vices[0].playerId)?.webName == "Palmer")
    }

    @Test func template() throws {
        let t = try #require(try fixture("elite-template-5", as: EliteTemplate.self).body)
        #expect(t.consensus == "Moderate consensus" && t.stats.map(\.value) == ["54%", "93%", "£98.6m", "3-5-2"])
        #expect(t.changes?.from == 4 && t.changes?.movedIn.first?.change == "+29.0pp")
        #expect(t.changes?.movedOut.first?.change == "-26.0pp")
        // Prices in £m (the website's page shows them ten times too high).
        #expect(t.positions[0].rows[0].detail == "£4.5m · start 42%")
        let first = try #require(try fixture("elite-template-1", as: EliteTemplate.self).body)
        #expect(first.changes == nil)
    }

    @Test func unpublished() throws {
        let json = #"{"data":{"gw":6,"gameweeks":[5,4],"published":false,"players":{}},"meta":{"apiVersion":"1","generatedAt":"2026-09-28T08:00:00Z"}}"#
        let page = try APIClient.decode(Envelope<ElitePage<EliteOverview>>.self, from: Data(json.utf8)).data
        #expect(page.gw == 6 && page.gameweeks == [5, 4] && page.body == nil)
    }

    @Test func paths() {
        let repo = EliteRepository(client: .production, cache: .shared)
        #expect(repo.overview(gw: nil).path == "elite/overview" && repo.overview(gw: nil).query.isEmpty)
        #expect(repo.template(gw: 4).query == [URLQueryItem(name: "gw", value: "4")])
        let own = repo.ownership(gw: 3, position: .mid, club: 12, maxPrice: 7.5, view: .core, sort: "price",
                                 ascending: true, search: " Saka ")
        #expect(own.path == "elite/ownership")
        #expect(own.query.map { "\($0.name)=\($0.value ?? "")" } == [
            "gw=3", "position=MID", "club=12", "maxPrice=7.5", "view=core", "sort=price", "dir=asc", "q=Saka",
        ])
        let plain = repo.ownership(gw: nil, position: nil, club: nil, maxPrice: nil, view: .all, sort: "owned_pct",
                                   ascending: false, search: "")
        #expect(plain.query.isEmpty)
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> ElitePage<T> {
        let url = try #require(Bundle(for: EliteBundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decode(Envelope<ElitePage<T>>.self, from: Data(contentsOf: url)).data
    }
}
