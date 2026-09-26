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
