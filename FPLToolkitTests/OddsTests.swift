import Foundation
import Testing
@testable import FPLToolkit

private final class OddsBundleToken {}

/// Odds (happy-backend-pal#38). Captured 28 Sep 2026 from production: /odds?gw=6.
struct OddsTests {
    @Test func decodesChancesAndNeverABookmaker() throws {
        let (odds, raw) = try fixture()
        #expect(odds.gameweek == 6 && odds.available && odds.label == "Betting-market estimate")
        #expect(odds.fixtures.count == 10 && odds.players.count == 412)
        let arsenal = try #require(odds.fixtures.first { $0.fixtureId == 51 })
        #expect(arsenal.result == Odds.Result(home: 0.714, draw: 0.184, away: 0.102, bookmakers: 7))
        #expect(arsenal.cleanSheet == Odds.CleanSheet(home: 0.513, away: 0.119, sources: 8))
        #expect(!String(decoding: raw, as: UTF8.self).contains("Bet365"))
    }

    @Test func picksTheChanceForThePosition() throws {
        let (odds, _) = try fixture()
        let haaland = try summary(id: 411, club: 14, position: "FWD")
        let striker = try #require(OddsChance.of(haaland, in: odds))
        #expect(striker == OddsChance(kind: .scorer, value: 0.524, previous: nil, scoreOrAssist: 0.617))
        #expect(striker.text == "52% to score · 62% score or assist" && striker.movement == nil)
        let arsenalDefender = try summary(id: 999_001, club: 1, position: "DEF")
        #expect(OddsChance.of(arsenalDefender, in: odds)?.text == "51% clean sheet")
        let leedsKeeper = try summary(id: 999_002, club: 13, position: "GK")
        #expect(OddsChance.of(leedsKeeper, in: odds)?.value == 0.119)
    }

    @Test func showsMovementOfTwoPointsOrMore() {
        #expect(OddsChance(kind: .cleanSheet, value: 0.45, previous: 0.41, scoreOrAssist: nil).movement == "↑4")
        #expect(OddsChance(kind: .cleanSheet, value: 0.40, previous: 0.41, scoreOrAssist: nil).movement == nil)
        #expect(OddsChance(kind: .scorer, value: 0.30, previous: 0.36, scoreOrAssist: nil).movement == "↓6")
    }

    private func summary(id: Int, club: Int, position: String) throws -> PlayerSummary {
        let json = #"{"id":\#(id),"webName":"P","photo":null,"clubId":\#(club),"position":"\#(position)","price":5.0,"availability":{"code":"a","level":"ok","chanceNext":null,"news":null},"selectedByPct":1.0,"nextFixture":null}"#
        return try APIClient.decode(PlayerSummary.self, from: Data(json.utf8))
    }

    private func fixture() throws -> (Odds, Data) {
        let url = try #require(Bundle(for: OddsBundleToken.self).url(forResource: "odds-gw6", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return (try APIClient.decode(Envelope<Odds>.self, from: data).data, data)
    }
}
