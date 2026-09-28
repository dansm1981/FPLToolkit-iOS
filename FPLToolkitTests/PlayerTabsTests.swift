import Foundation
import Testing
@testable import FPLToolkit

private final class PlayerTabsBundleToken {}

/// The player sheet's "More" sections (happy-backend-pal#28), for Tarkowski (229) and Haaland (411).
/// Captured 28 Sep 2026 from production; each checked against the website's tab page.
struct PlayerTabsTests {
    @Test func history() throws {
        let h = try fixture("history", as: PlayerHistoryTab.self)
        #expect(h.appearances == 5 && h.hauls == 2 && h.blanks == 0)
        #expect(h.best?.points == 14 && h.best?.gameweek == 5)
        #expect(h.home.points == 23 && h.home.minutes == 270 && h.rows.count == 5)
        #expect(h.rows[0].xg == "0.05" && h.rows[0].price == "£6.0m" && h.rows[0].cleanSheets == 1)
    }

    @Test func form() throws {
        let f = try fixture("form", as: PlayerFormTab.self)
        #expect(f.fplForm == "9.2" && f.pointsPerGame == "8.6" && f.windows.map(\.last) == [4, 6, 10])
        #expect(f.windows[0].ppg == "9.3" && f.windows[0].points == 37)
        #expect(f.bars.map(\.band) == [.good, .haul, .ok, .good, .haul])
    }

    @Test func underlying() throws {
        let u = try fixture("underlying", as: PlayerUnderlyingTab.self)
        #expect(u.goalsVsXg.display == "+0.82" && u.finishing.tone == "warn")
        #expect(u.finishing.text == "Finishing above xG — regression risk" && u.meaningfulSample)
        #expect(u.rows.count == 9 && u.rows[0].total == "0.18")
    }

    @Test func fixtures() throws {
        let x = try fixture("fixtures", as: PlayerFixturesTab.self)
        #expect(x.averageFdr == "3.20" && x.easy == 3 && x.hard == 4 && x.upcoming.count == 10)
        #expect(x.byDifficulty.map(\.label) == ["Easy (FDR 1-2)", "Average (FDR 3)", "Hard (FDR 4-5)"])
        #expect(x.byDifficulty.map(\.ppg) == ["10.0", "10.0", "3.0"])
    }

    @Test func price() throws {
        let p = try fixture("price", as: PlayerPriceTab.self)
        #expect(p.current == "£6.1m" && p.started == "£6.0m" && p.seasonChange == "+0.1m")
        #expect(p.rises == 1 && p.falls == 0 && p.snapshots.count == 14)
        #expect(p.events.first?.direction == "up" && p.events.first?.to == "£6.1m")
    }

    @Test func defensive() throws {
        let d = try fixture("defensive", as: PlayerDefensiveTab.self)
        #expect(d.eligible && d.threshold == 10 && d.hits == 3 && d.starts == 5)
        #expect(d.hitRateStarts == "60%" && d.dcPer90 == "10.2" && d.rank?.rank == 1 && d.rank?.of == 96)
        #expect(d.matches[0].dc == 9 && !d.matches[0].hit && d.matches[0].nearMiss && d.matches[0].short == 1)
        // Midfielders and forwards have a higher threshold.
        let forward = try fixture("defensive", id: 411, as: PlayerDefensiveTab.self)
        #expect(forward.threshold == 12 && forward.rank?.of == 126)
    }

    @Test func compare() throws {
        let c = try fixture("compare", as: PlayerCompareTab.self)
        #expect(c.played == 148 && c.price == "£6.1m" && c.peersCount == 9 && c.peers.count == 9)
        #expect(c.ranks.map(\.ordinal) == ["100th", "90th", "37th", "84th", "100th"])
        #expect(c.peers.allSatisfy { c.player($0.playerId) != nil })
    }

    @Test func tabPaths() {
        let repo = PlayerRepository(client: .production, cache: .shared)
        #expect(PlayerTab.allCases.map { repo.tab(229, $0, as: PlayerHistoryTab.self).path } == [
            "players/229/history", "players/229/form", "players/229/underlying", "players/229/fixtures",
            "players/229/price", "players/229/defensive", "players/229/compare",
        ])
    }

    private func fixture<T: Decodable & Sendable>(_ tab: String, id: Int = 229, as type: T.Type) throws -> T {
        let url = try #require(Bundle(for: PlayerTabsBundleToken.self).url(forResource: "player-tab-\(tab)-\(id)", withExtension: "json"))
        return try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }
}
