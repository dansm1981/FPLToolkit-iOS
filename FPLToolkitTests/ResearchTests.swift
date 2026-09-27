import Foundation
import Testing
@testable import FPLToolkit

private final class ResearchBundleToken {}

/// The Research tab (happy-backend-pal#24). Responses captured 27 Sep 2026 from the branch, each
/// checked against the website's page with the same settings.
struct ResearchTests {
    @Test func ticker() throws {
        let ticker = try fixture("research-fixtures-6", as: ResearchTicker.self)
        #expect(ticker.gws == [6, 7, 8, 9, 10, 11] && ticker.lens == "match" && !ticker.fuzzy)
        #expect(ticker.sort.key == .sum && ticker.sort.dir == "asc")
        #expect(ticker.rows.count == 20)
        // Easiest run first, with the total as the website writes it.
        #expect(ticker.rows.prefix(3).map(\.sumDisplay) == ["10.3", "10.9", "13.1"])
        #expect(ticker.rows.first?.cells.first?.fixtures.first?.display == "1.2")
        #expect(ticker.rows.allSatisfy { $0.cells.count == 6 })

        let fuzzy = try fixture("research-fixtures-10-fuzzy-fpl", as: ResearchTicker.self)
        #expect(fuzzy.fuzzy && fuzzy.dropCount == 5)
        #expect(fuzzy.rows.allSatisfy { row in row.cells.filter(\.ignored).count == 5 })
        // FPL's own difficulty is whole.
        #expect(fuzzy.rows.first?.sumDisplay == "10")
        #expect(fuzzy.rows.allSatisfy { $0.cells.allSatisfy { $0.fixtures.allSatisfy { $0.source == "fpl" } } })
    }

    @Test func sortKeyDecodes() throws {
        let json = #"[{"key":"sum","dir":"asc"},{"key":8,"dir":"desc"}]"#
        let sorts = try JSONDecoder().decode([ResearchTicker.Sort].self, from: Data(json.utf8))
        #expect(sorts.map(\.key) == [.sum, .gw(8)])
        #expect(sorts.map(\.key.queryValue) == ["sum", "8"])
    }

    @Test func tickerQuery() {
        let endpoint = ResearchRepository(client: .production, cache: .shared)
            .ticker(horizon: 10, fuzzy: true, sort: .gw(7), hardestFirst: true, clubs: [14, 1],
                    view: FixtureView(model: .fpl, lens: .match))
        #expect(endpoint.path == "research/fixtures")
        #expect(endpoint.query.map(\.description) == [
            "model=fpl", "lens=match", "horizon=10", "sort=7", "dir=desc", "fuzzy=1", "clubs=1,14",
        ])
    }

    /// Three midfielders, two starts a week, over 8 gameweeks: the website shows 30.4, 31.8, -1.4
    /// and £22.0m, and the same gold cells.
    @Test func rotation() throws {
        let rotation = try fixture("research-rotation-mids", as: ResearchRotation.self)
        #expect(rotation.playerIds == [124, 399, 397] && rotation.starters == 2 && rotation.weeks.count == 8)
        #expect(rotation.display.rotationTotal == "30.4" && rotation.display.bestSolo == "31.8")
        #expect(rotation.display.gain == "-1.4" && rotation.display.combinedCost == "£22.0m")
        #expect(rotation.startCounts == ["124": 3, "399": 5, "397": 8])
        #expect(rotation.player(124)?.webName == "Groß")
        #expect(rotation.weeks.allSatisfy { $0.starterIds.count == 2 })
        #expect(rotation.weeks.map { $0.starterIds.contains(124) } == [true, false, false, false, true, false, true, false])
    }

    @Test func congestion() throws {
        let congestion = try fixture("research-congestion-28", as: ResearchCongestion.self)
        #expect(congestion.days == 28 && congestion.dates.count == 28 && congestion.todayIndex == 3)
        #expect(congestion.clubs.count == 20 && congestion.clubs.allSatisfy { $0.days.count == 28 })
        #expect(congestion.missingCompetitions == ["FA Cup", "Carabao Cup"] && !congestion.feed.stale)
        let arsenal = try #require(congestion.clubs.first)
        #expect(arsenal.clubId == 1 && arsenal.count == 4 && arsenal.shortest == 3 && arsenal.daysToNext == 13)
        #expect(arsenal.days.filter { !$0.matches.isEmpty }.flatMap(\.matches).map(\.competition)
            == ["Premier League", "UCL", "Premier League", "UCL"])
        // Rest days carry their block's length and the website's heat step.
        #expect(arsenal.days.allSatisfy { $0.matches.isEmpty || $0.gap == nil })
        #expect(arsenal.days.compactMap(\.gap).allSatisfy { $0 >= 1 })
    }

    @Test func congestionWords() throws {
        let date = try #require(CongestionView.date("2026-09-24"))
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2026 && parts.month == 9 && parts.day == 24)
        #expect(CongestionView.date("nonsense") == nil)
        #expect(CongestionView.competitionName("UECL") == "Conference League")
        #expect(CongestionView.competitionName("Premier League") == "Premier League")
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        let url = try #require(Bundle(for: ResearchBundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }
}
