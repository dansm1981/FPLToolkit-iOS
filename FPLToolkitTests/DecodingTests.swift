import Foundation
import Testing
@testable import FPLToolkit

/// Decodes every captured real response in Fixtures/api-v1 (26 Sep 2026, GW5 published, GW6 next).
struct DecodingTests {
    @Test func bootstrap() throws {
        let envelope = try fixture("bootstrap", as: Bootstrap.self)
        #expect(envelope.data.season == "2026/27")
        #expect(envelope.data.gameweek.locked == 5)
        #expect(envelope.data.gameweek.next?.id == 6)
        #expect(envelope.data.clubs.count == 20)
        #expect(envelope.data.config.disclosure.contains("unofficial"))
        #expect(envelope.data.config.features.priceAlerts == false)
        #expect(envelope.meta.freshness?.map(\.source) == [.fplCore, .availability])
    }

    @Test func publishedTeam() throws {
        let team = try fixture("team-71191", as: Team.self).data
        let snapshot = try #require(team.snapshot)
        #expect(snapshot.picks.count == 15)
        #expect(snapshot.picks.filter { $0.role == .starter }.count == 11)
        #expect(snapshot.picks.filter(\.isCaptain).count == 1)
        #expect(snapshot.freeHitGw == nil)
        #expect(team.noSnapshotReason == nil)
        #expect(team.players.count == 15)
        for pick in snapshot.picks {
            #expect(team.player(pick.playerId) != nil, "missing player \(pick.playerId)")
        }
    }

    @Test func freeHitTeam() throws {
        let team = try fixture("team-895045-freehit", as: Team.self).data
        let snapshot = try #require(team.snapshot)
        #expect(snapshot.freeHitGw == 5)
        #expect(snapshot.gw == 4)
        #expect(snapshot.picks.count == 15)
    }

    @Test func teamWithNoPublishedSquad() throws {
        let envelope = try fixture("team-no-published-team", as: Team.self)
        #expect(envelope.data.snapshot == nil)
        #expect(envelope.data.noSnapshotReason == .noPublishedTeamYet)
        #expect(envelope.data.players.isEmpty)
        // picks and xfdr have no fixed max age
        #expect(envelope.meta.freshness?.first { $0.source == .picks }?.expectedMaxAgeSeconds == nil)
    }

    @Test func todayClear() throws {
        let today = try fixture("today-71191", as: Today.self).data
        #expect(today.status == .clear)
        #expect(today.attentionCount == 0)
        #expect(today.attentionInsights.isEmpty)
        #expect(!today.insights.isEmpty)
    }

    @Test func todayAttention() throws {
        let envelope = try fixture("today-3612045-attention", as: Today.self)
        let today = envelope.data
        #expect(today.status == .attention)
        #expect(today.attentionCount == 1)
        #expect(today.attentionInsights.count == 1)
        let insight = try #require(today.attentionInsights.first)
        #expect(insight.category == .availability)
        #expect(insight.tone == .bad)
        #expect(insight.supportingValue?.kind == .chanceOfPlaying)
        #expect(insight.supportingValue?.unit == .percent)
        #expect(today.player(insight.playerId) != nil)
        // Every insight's player is in the players map (§3.3).
        for insight in today.insights {
            #expect(today.player(insight.playerId) != nil, "missing player \(insight.playerId)")
        }
        #expect(envelope.meta.freshness?.first { $0.source == .pricePredictions }?.state == .unknown)
    }

    @Test func todayWithNoPublishedSquad() throws {
        let today = try fixture("today-no-published-team", as: Today.self).data
        #expect(today.status == .unverified)
        #expect(today.snapshot == nil)
        #expect(today.noSnapshotReason == .noPublishedTeamYet)
        #expect(today.gameweek.next?.id == 6)
    }

    @Test(arguments: ["player-palmer", "player-haaland"])
    func playerSheet(name: String) throws {
        let sheet = try fixture(name, as: PlayerSheet.self).data
        #expect(sheet.fixtures.count == 5)
        #expect(sheet.market.ownershipTrend7d.count == 8)
        #expect(sheet.links.web.hasPrefix("https://www.fpltoolkit.co.uk/players/"))
        #expect(sheet.elite?.cohortSize == 100)
    }

    @Test func playerSheetDetail() throws {
        let sheet = try fixture("player-palmer", as: PlayerSheet.self).data
        #expect(sheet.player.summary.webName == "Palmer")
        #expect(sheet.player.summary.position == .mid)
        #expect(sheet.player.summary.availability.level == .doubt)
        #expect(sheet.player.summary.availability.chanceNext == 75)
        #expect(sheet.player.totalPoints == 28)
        #expect(sheet.pricePrediction?.projections.count == 3)
        #expect(sheet.pricePrediction?.projections.first?.likelihood == nil)
        #expect(sheet.defcon?.threshold == 12)
    }

    @Test(arguments: [
        ("error-invalid-entry", APIErrorCode.invalidEntryId),
        ("error-entry-not-found", APIErrorCode.entryNotFound),
    ])
    func errors(name: String, code: APIErrorCode) throws {
        let body = try APIClient.decode(ErrorEnvelope.self, from: data(name))
        #expect(body.error.code == code)
        #expect(body.error.retryable == false)
    }

    // MARK: - Tolerance (§2.4: additive changes only)

    @Test func unknownEnumValuesFallBack() throws {
        let json = """
        {"id":"x","playerId":1,"category":"new_kind","severity":50,"tone":"sparkly","needsAttention":false,
         "title":"T","summary":"S","supportingValue":{"kind":"new","value":1,"unit":"pts","label":"L"},
         "sourceTimestamp":"2026-09-26T03:20:17Z","expiresAt":null,"deepLink":"fpltoolkit://player/1","extraField":true}
        """
        let insight = try APIClient.decode(TeamInsight.self, from: Data(json.utf8))
        #expect(insight.category == .other)
        #expect(insight.tone == .info)
        #expect(insight.supportingValue?.kind == .unknown)
        #expect(insight.supportingValue?.unit == .unknown)
        #expect(insight.sourceTimestamp != nil)
    }

    @Test func unknownStatusIsNeverClear() throws {
        let status = try APIClient.decode(Today.Status.self, from: Data(#""all_good""#.utf8))
        #expect(status == .unverified)
    }

    // MARK: - Helpers

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> Envelope<T> {
        try APIClient.decode(Envelope<T>.self, from: data(name))
    }

    private func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(
            bundle.url(forResource: name, withExtension: "json")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "api-v1"),
            "fixture \(name).json is not in the test bundle")
        return try Data(contentsOf: url)
    }
}

private final class BundleToken {}

struct PriceFormatTests {
    @Test func negativeBankReadsAsMinus() {
        #expect(Format.price(2.2) == "£2.2m")
        #expect(Format.price(-0.2) == "−£0.2m")
        #expect(Format.price(0) == "£0.0m")
    }
}

struct CompactFormatTests {
    @Test func countdownAndRank() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(Format.compactCountdown(to: now.addingTimeInterval(10 * 86_400 + 8 * 3_600 + 59), now: now) == "10d 8h")
        #expect(Format.compactCountdown(to: now.addingTimeInterval(8 * 3_600 + 20 * 60), now: now) == "8h 20m")
        #expect(Format.compactCountdown(to: now.addingTimeInterval(-5), now: now) == "Passed")
        #expect(Format.spokenCountdown(to: now.addingTimeInterval(86_400 + 3_600), now: now) == "in 1 day 1 hour")
        #expect(Format.rank(1_203_456) == 1_203_456.formatted())
        #expect(Format.rank(345_726) == 345_726.formatted())
    }
}

struct SeasonHistoryDecodingTests {
    /// The shape happy-backend-pal#46 sends (made by its seasonHistoryDto from FPL's history).
    @Test func decodesSeasonHistory() throws {
        let json = #"""
        {"entryId":22615,"weeks":[
          {"gw":1,"points":63,"totalPoints":63,"gwRank":1282719,"overallRank":1282717,"benchPoints":0,
           "transfers":0,"hitPoints":0,"value":100,"bank":1.5,"chip":"bboost","average":51,"highest":121},
          {"gw":2,"points":102,"totalPoints":165,"gwRank":null,"overallRank":724567,"benchPoints":13,
           "transfers":0,"hitPoints":0,"value":100.1,"bank":1.5,"chip":null,"average":null,"highest":null}],
         "past":[{"season":"2025/26","totalPoints":2242,"rank":516192}]}
        """#
        let history = try APIClient.decode(SeasonHistory.self, from: Data(json.utf8))
        #expect(history.weeks.count == 2)
        #expect(history.weeks[0].chip == "bboost")
        #expect(history.weeks[0].value == 100)
        #expect(history.weeks[1].gwRank == nil)
        #expect(history.weeks[1].average == nil)
        #expect(history.past.first?.rank == 516192)
    }

    @Test func rankMoveSpeaksTheChange() {
        #expect(RankMoveArrow.spoken(current: 345_727, previous: 219_072) == "down \(126_655.formatted()) places")
        #expect(RankMoveArrow.spoken(current: 219_072, previous: 463_077) == "up \(244_005.formatted()) places")
        #expect(RankMoveArrow.spoken(current: 5, previous: nil) == nil)
        #expect(SeasonText.axisRank(1_282_717) == "1.3m")
        #expect(SeasonText.axisRank(345_727) == "346k")
    }
}

struct MatchStatsDecodingTests {
    /// The shape happy-backend-pal#47 sends for GET live/fixtures/{id}.
    @Test func decodesMatchStats() throws {
        let json = #"""
        {"fixtureId":51,"homeClubId":1,"awayClubId":2,"homeScore":2,"awayScore":1,"state":"inPlay","minute":70,
         "goals":[{"playerId":10,"side":"home","value":2}],"assists":[],"ownGoals":[],"penaltiesSaved":[],
         "penaltiesMissed":[],"yellowCards":[],"redCards":[],"saves":[{"playerId":22,"side":"away","value":4}],
         "bonus":[{"playerId":10,"side":"home","value":3}],"bonusProvisional":true,
         "bps":[{"playerId":10,"side":"home","value":40}],
         "defcon":[{"playerId":13,"side":"home","value":9,"threshold":10,"reached":false}],
         "players":{}}
        """#
        let stats = try APIClient.decode(MatchStats.self, from: Data(json.utf8))
        #expect(stats.state == .inPlay)
        #expect(stats.goals.first?.value == 2)
        #expect(stats.bonusProvisional)
        #expect(stats.defcon.first?.reached == false)
        #expect(stats.defcon.first?.side == .home)
    }
}

struct SuspensionRiskDecodingTests {
    @Test func decodesTheRiskWhenPresentAndNotOtherwise() throws {
        let base = #""id":1,"webName":"A","photo":null,"clubId":1,"position":"DEF","price":5.0,"availability":{"code":"a","level":"ok","chanceNext":null,"news":null},"selectedByPct":1.0,"nextFixture":null"#
        let plain = try APIClient.decode(PlayerSummary.self, from: Data("{\(base)}".utf8))
        #expect(plain.suspensionRisk == nil)
        let risky = try APIClient.decode(PlayerSummary.self, from: Data(
            "{\(base),\"suspensionRisk\":{\"yellowCards\":4,\"threshold\":5,\"banMatches\":1,\"matchesLeft\":14}}".utf8))
        #expect(risky.suspensionRisk?.chip == "4 yellows · ban at 5")
        #expect(risky.suspensionRisk?.spoken == "one yellow card from a 1-match ban, 14 matches before the cut-off")
    }
}
