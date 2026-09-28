import Foundation
import Testing
@testable import FPLToolkit

private final class DeepDiveBundleToken {}

/// The deep dives (happy-backend-pal#33). Captured 28 Sep 2026 from production; each endpoint was
/// checked against the website's page.
struct DeepDiveTests {
    @Test func hauls() throws {
        let h = try fixture("deep-dive-hauls", as: Hauls.self)
        #expect(h.rows.count == 100 && h.player(h.rows[0].playerId)?.webName == "Groß")
        #expect(h.rows[0] == Hauls.Row(playerId: 124, hauls: 3, best: 17, returns: 3, appearances: 5, points: 47))
    }

    @Test func consistency() throws {
        let c = try fixture("deep-dive-consistency", as: Consistency.self)
        #expect(c.minApps == 3 && c.rows.count == 100)
        let top = c.rows[0]
        #expect(c.player(top.playerId)?.webName == "Gvardiol" && top.consistency.display == "100%" && top.tone == .good)
        #expect(top.goodGames == 5 && top.appearances == 5 && top.pointsPerGame == "7.4")
        // The website's "default" colour decodes as neutral.
        #expect(c.rows.last?.tone == .neutral)
    }

    @Test func homeAway() throws {
        let h = try fixture("deep-dive-home-away", as: HomeAway.self)
        #expect(h.count == 346 && h.homeSpecialists.count == 25 && h.travellers.count == 25)
        #expect(h.homeSpecialists[0] == HomeAway.Row(playerId: 426, home: "12.5", away: "2.0",
                                                     diff: ShownValue(value: 10.5, display: "+10.5"), homeGames: 2, awayGames: 3))
        #expect(h.travellers[0].diff.display == "-12.0" && h.player(53)?.webName == "Manzambi")
    }

    @Test func records() throws {
        let r = try fixture("deep-dive-records", as: SeasonRecords.self)
        #expect(r.tiles.map(\.label) == ["Highest gameweek score", "Most hauls", "Top scorer", "Most owned",
                                         "Biggest price rise", "Biggest price fall", "Best value", "Price changes logged"])
        #expect(r.tiles[0] == SeasonRecords.Tile(label: "Highest gameweek score", playerId: 426, value: "B.Fernandes", sub: "23 pts in GW2"))
        #expect(r.tiles[7].playerId == nil && r.tiles[7].value == "442")
        #expect(r.topScores.count == 20 && r.topScores[0] == SeasonRecords.Score(playerId: 426, gameweek: 2, points: 23, goals: 3, assists: 1, bonus: 3))
        #expect(r.mostRises.first == SeasonRecords.Count(playerId: 115, count: 5) && r.mostFalls.first?.count == 4)
    }

    @Test func paths() {
        let repo = ResearchRepository(client: .production, cache: .shared)
        #expect([repo.hauls.path, repo.consistency.path, repo.homeAway.path, repo.records.path]
            == ["deep-dives/hauls", "deep-dives/consistency", "deep-dives/home-away", "deep-dives/records"])
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        let url = try #require(Bundle(for: DeepDiveBundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }
}
