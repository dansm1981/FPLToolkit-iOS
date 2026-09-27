import Foundation
import Testing
@testable import FPLToolkit

private final class MarketBundleToken {}

/// The Market screens (happy-backend-pal#25). Responses captured 27 Sep 2026 from the branch, each
/// checked against the website's page.
struct MarketTests {
    @Test func changes() throws {
        let changes = try fixture("market-changes-0919", as: MarketChanges.self)
        #expect(changes.day == "2026-09-19" && !changes.latest && changes.days.count == 31)
        #expect(changes.risersCount == 5 && changes.fallersCount == 31)
        #expect(changes.risers.prefix(3).compactMap { changes.player($0.playerId)?.webName } == ["Konsa", "Dewsbury-Hall", "Barnes"])
        #expect(changes.risers.allSatisfy { $0.dayPrice > 0 } && changes.fallers.allSatisfy { $0.dayPrice < 0 })
        #expect(changes.seasonRisersCount == 36 && changes.seasonFallersCount == 271 && changes.seasonFallers.count == 50)
    }

    @Test func predictions() throws {
        let p = try fixture("market-predictions", as: MarketPredictions.self)
        #expect(p.tracked == 667 && p.headingUp == 177 && p.headingDown == 351 && p.locked == 11)
        #expect(p.risersCount == 177 && p.risers.count == 100 && p.fallers.count == 100)
        let top = try #require(p.risers.first)
        #expect(p.player(top.playerId)?.webName == "Barry" && top.progressDisplay == "100.4%")
        #expect(top.nights.map(\.offset) == [0, 1, 2])
        #expect(p.risers.allSatisfy { $0.progress > 0 } && p.fallers.allSatisfy { $0.progress < 0 })
    }

    @Test func trends() throws {
        let t = try fixture("market-trends", as: MarketTrends.self)
        #expect(t.count == 667 && t.rows.count == 200 && t.hasDaily)
        #expect(t.upFlow.prefix(3).compactMap { t.player($0.playerId)?.webName } == ["Affengruber", "Kostoulas", "Salia"])
        #expect(t.upFlow.first?.likelihood == 67 && t.upFlow.first?.band == .watchUp)
        #expect(t.fallers.first.map { t.player($0.playerId)?.webName } == "Zepa")
        #expect(t.rows.allSatisfy { !$0.history.isEmpty })
    }

    @Test func transfers() throws {
        let d = try fixture("market-transfers", as: MarketTransfers.self)
        #expect(d.gw == 6 && d.bought.count == 20 && d.mostOwned.count == 25)
        #expect(d.bought.prefix(2).compactMap { d.player($0.playerId)?.webName } == ["Groß", "Schade"])
        #expect(d.bought.first?.transfersIn == 755_117)
        #expect(d.byPosition["GK"]?.prefix(2).compactMap { d.player($0.playerId)?.webName } == ["Raya", "Verbruggen"])
        #expect(Set(d.byPosition.keys) == ["GK", "DEF", "MID", "FWD"])
    }

    @Test func words() {
        #expect(MarketFormat.moneyChange(0.1) == "+£0.1m" && MarketFormat.moneyChange(-0.2) == "−£0.2m")
        #expect(MarketFormat.moneyChange(0) == "£0.0m")
        #expect(MarketFormat.points(4.8) == "+4.8pp" && MarketFormat.points(-0.12, digits: 2) == "−0.12pp")
        #expect(MarketFormat.count(755_117) == "755,117" && MarketFormat.count(-8_860, signed: true) == "−8,860")
        #expect(MarketFormat.spokenMoney(-0.1) == "down £0.1m")
        #expect(MarketFormat.day("2026-09-19").contains("19"))
    }

    @Test func queries() {
        let repo = MarketRepository(client: .production, cache: .shared)
        #expect(repo.changes(day: nil).query.isEmpty)
        #expect(repo.predictions(club: 14, position: .def, maxPrice: 6).query.map(\.description)
            == ["club=14", "position=DEF", "maxPrice=6"])
        #expect(repo.trends(position: nil, club: nil, band: 2, ids: [9, 3], sort: "own", ascending: true).query.map(\.description)
            == ["band=2", "sort=own", "dir=asc", "ids=3,9"])
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        let url = try #require(Bundle(for: MarketBundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }
}
