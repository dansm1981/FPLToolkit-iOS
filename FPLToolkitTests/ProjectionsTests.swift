import Foundation
import Testing
@testable import FPLToolkit

private final class ProjectionsBundleToken {}

/// Projections (happy-backend-pal#74): decoding the server's answers (captured from the branch's
/// code on production data, 4 Oct), the wording, and the request.
struct ProjectionsTests {
    @Test func decodesTheList() throws {
        let p = try fixture("projections-gw6", as: Projections.self)
        let run = try #require(p.run)
        #expect(run.fromGw == 6 && run.toGw == 11 && run.sims == 2000 && run.stage.key == "odds")
        #expect(run.finishedAt != nil && run.deadline != nil && run.context.market == 120)
        #expect(p.horizons.first?.label == "GW6" && p.horizons.count == 6 && p.horizon == 1)
        #expect(p.knew?.inputs.contains { $0.status == .stale && $0.observedAt != nil } == true)
        // Likely starters only by default, as on the website: 152 players.
        #expect(p.total == p.rows.count && p.rows.count == 152)
        let saka = try #require(p.rows.first)
        #expect(p.player(saka.playerId)?.webName == "Saka")
        #expect(saka.mean == 6.8 && saka.median == 6 && saka.mode == 2 && saka.p10 == 1 && saka.p90 == 15)
        #expect(saka.haulPct == 29 && saka.blankPct == 29 && saka.sixtyPct == 84 && saka.fplEp != nil)
        // The fixture was captured with Raya's forecast at 100% (model 93%).
        let raya = try #require(p.rows.first { $0.playerId == 1 })
        #expect(raya.adjusted && raya.sixtyPct == 100 && raya.modelSixtyPct == 93)
    }

    @Test func overAHorizonTheOneWeekColumnsGo() throws {
        let p = try fixture("projections-h3-def", as: Projections.self)
        #expect(p.horizon == 3 && p.rows.count == 76)
        #expect(p.rows.allSatisfy { $0.blankPct == nil && $0.fplEp == nil && $0.haulPct != nil })
        #expect(p.rows.allSatisfy { p.player($0.playerId)?.position == .def })
    }

    @Test func decodesTheBreakdown() throws {
        let b = try fixture("projection-player-12", as: ProjectionPlayer.self)
        #expect(b.player.webName == "Saka" && b.availabilityText == "No availability flag")
        #expect(b.gameweeks.map(\.gameweek) == [6, 7, 8, 9, 10, 11])
        let gw = try #require(b.gameweeks.first)
        #expect(gw.mean == 6.8 && gw.mode == 2 && gw.fixtureCount == 1)
        #expect(gw.chart.first == 0 && gw.chart.bars.count == 31)
        #expect(gw.minutes.figures.map(\.value) == ["100%", "87%", "84%", "1%", "72"])
        #expect(gw.fixtures.first?.source == .market && gw.fixtures.first?.teamXg == 2.01)
        #expect(gw.rates?.figures.first { $0.label == "Finishing" }?.value == "×0.98")
        #expect(gw.components.map(\.key) == ["appearance", "goals", "assists", "clean_sheet", "defcon", "bonus", "cards"])
        #expect(b.horizons.first?.label == "GW6–7" && b.horizons.first?.anyHaulPct == 45)
        // A keeper's rates show saves, not DefCon.
        let raya = try fixture("projection-player-1", as: ProjectionPlayer.self)
        #expect(raya.gameweeks.first?.rates?.figures.contains { $0.label == "Saves" } == true)
        #expect(raya.gameweeks.first?.chart.first == -1)
    }

    @Test func wording() throws {
        #expect(ProjectionText.pct(29) == "29%" && ProjectionText.pct(nil) == "—")
        #expect(ProjectionText.signed(2.79) == "+2.79" && ProjectionText.signed(-0.1) == "−0.10")
        #expect(ProjectionText.one(6.8) == "6.8" && ProjectionText.two(1.02) == "1.02")
        let run = try #require(try fixture("projections-gw6", as: Projections.self).run)
        #expect(ProjectionText.deadline(run) == "142h to the GW6 deadline")
        #expect(ProjectionSort.blank.gameweekOnly && ProjectionSort.fplEp.gameweekOnly && !ProjectionSort.haul.gameweekOnly)
    }

    @Test func request() {
        let repo = ResearchRepository(client: .production, cache: .shared)
        let plain = repo.projections(horizon: 1, position: nil, search: " ", startersOnly: true, allNailed: false,
                                     minutes: [:], sort: .mean, ascending: false)
        #expect(plain.path == "projections" && plain.query.map(\.name) == ["horizon", "sort"])
        let all = repo.projections(horizon: 3, position: .def, search: "Saka", startersOnly: false, allNailed: true,
                                   minutes: [45: 55, 12: 100], sort: .haul, ascending: true)
        #expect(all.query.map { "\($0.name)=\($0.value ?? "")" } == [
            "horizon=3", "sort=haul", "position=DEF", "starters=0", "nailed=1", "minutes=12:100,45:55", "dir=asc", "q=Saka",
        ])
        #expect(repo.projectionPlayer(12).path == "projections/players/12")
    }

    @MainActor @Test func tweaks() {
        let t = ProjectionTweaks()
        t.allNailed = true
        t.set(12, to: 90)
        // Changing one player turns "All nailed" off, as on the website.
        #expect(!t.allNailed && t.minutes == [12: 90])
        t.set(12, to: nil)
        #expect(t.minutes.isEmpty)
        t.set(1, to: 50)
        t.reset()
        #expect(t.minutes.isEmpty)
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        let url = try #require(Bundle(for: ProjectionsBundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }
}
