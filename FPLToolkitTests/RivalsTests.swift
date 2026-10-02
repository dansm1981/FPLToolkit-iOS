import Foundation
import Testing
@testable import FPLToolkit

private final class RivalsBundleToken {}

/// Rivals (happy-backend-pal#67). Captured 2 Oct 2026 from production with a throwaway device:
/// Dan's team (22615) in League of Experts, Andy McBride featured and Paul McBride nicknamed
/// "Big Paul"; GW5 finished.
struct RivalsTests {
    private func fixture<T: Decodable & Sendable>(_ name: String, as: T.Type) throws -> T {
        let url = try #require(Bundle(for: RivalsBundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }

    @Test func decodesTheList() throws {
        let list = try fixture("rivals", as: RivalsList.self)
        #expect(list.season == "2026/27" && list.gameweek == 5 && list.status == .finished && list.max == 10)
        #expect(list.rivals.map(\.name) == ["Andy", "Big Paul"])
        let andy = try #require(list.featured)
        #expect(andy.entryId == 1699334 && andy.state == .ok && andy.gap == -30 && andy.gapBefore == -19)
        #expect(andy.you == 45 && andy.them == 56 && andy.gapText == "30 pts behind Andy")
        #expect(andy.leagues.first?.name == "LEAGUE OF EXPERTS" && andy.leagues.first?.rank == 1)
        let paul = list.rivals[1]
        #expect(paul.nickname == "Big Paul" && paul.identity == "Paul Mcbride · \(paul.team ?? "")" && paul.gap == 11)
        #expect(list.contains(7409161) && !list.contains(22615))
    }

    @Test func decodesTheCandidates() throws {
        let c = try fixture("rivals-candidates", as: RivalCandidates.self)
        #expect(c.count == 2 && c.max == 10 && c.managers.count == 20)
        #expect(c.managers.filter(\.isRival).map(\.entryId).sorted() == [1699334, 7409161])
        #expect(!c.managers.contains { $0.entryId == 22615 })
    }

    @Test func decodesTheComparison() throws {
        let d = try fixture("rival-1699334", as: RivalComparison.self)
        #expect(d.rival.featured && d.startText == "Started GW5 19 behind")
        #expect(d.explanation == "Andy has gained 30 pts over the last 5 gameweeks")
        let teams = try #require(d.teams)
        #expect(teams.summary == .init(yours: 30, theirs: 41, multiplier: 0, shared: 3) && !teams.provisional)
        // The differences add up to the gameweek's swing: 45 v 56.
        #expect(teams.summary.yours - teams.summary.theirs + teams.summary.multiplier == 45 - 56)
        let hall = try #require(teams.rows.first { d.player($0.playerId)?.webName == "Hall" })
        #expect(hall.group == .yours && hall.effect == 13 && hall.you?.multiplier == 1 && hall.them == nil)
        let haaland = try #require(teams.rows.first { d.player($0.playerId)?.webName == "Haaland" })
        #expect(haaland.group == .shared && haaland.you?.multiplier == 2 && haaland.them?.multiplier == 2)
        let last5 = d.stats.last5
        #expect(last5.gameweeks == [1, 2, 3, 4, 5] && last5.gapChange == -30)
        #expect(last5.outscored == .init(won: 1, lost: 4, drawn: 0, of: 5))
        #expect(last5.you.captainPoints == 95 && last5.them.captainPoints == 113 && last5.captains?.count == 5)
        #expect(d.stats.season.captains == nil && d.stats.season.you.byPosition == nil)
        #expect(d.stats.gw?.you.byPosition == .init(gk: 2, def: 19, mid: 6, fwd: 18))
        #expect(d.chipsAvailable == .init(you: ["Free Hit"], them: ["Wildcard"]))
    }

    @Test func playerPageNamesYourRivals() throws {
        let leagues = try fixture("player-411-leagues", as: PlayerLeagues.self)
        let rivals = try #require(leagues.rivals)
        #expect(RivalText.holding(rivals) == "Andy captains him · Big Paul captains him (GW5)")
        let mixed = [PlayerLeagues.Rival(entryId: 1, name: "Chris", started: true, captain: false, gameweek: 6),
                     PlayerLeagues.Rival(entryId: 2, name: "Ann", started: false, captain: false, gameweek: 6)]
        #expect(RivalText.holding(mixed) == "Chris starts him · Ann has him on the bench (GW6)")
    }

    @Test func wording() throws {
        #expect(RivalText.figure(-30) == ("30", "behind") && RivalText.figure(4) == ("4", "ahead"))
        #expect(RivalText.figure(0) == ("0", "level") && RivalText.figure(nil) == ("–", "not synced"))
        #expect(["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "112th"]
            == [1, 2, 3, 4, 11, 12, 13, 21, 112].map(RivalText.ordinal))
        let list = try fixture("rivals", as: RivalsList.self)
        #expect(RivalText.detail(list.rivals[0], gameweek: 5) == "LEAGUE OF EXPERTS 1st · GW5: you 45, Andy 56")
        #expect(RivalText.thisWeek(list.rivals[0]) == "This gameweek: you 45 · Andy 56")
        #expect(RivalText.bonus(list.rivals[0]) == nil)
        #expect(RivalViewText.state(.finished) == "Final" && RivalViewText.state(.live) == "Live")
        #expect(RivalStatsText.outscored(.init(won: 1, lost: 3, drawn: 1, of: 5), name: "Andy") == "1 of 5 · Andy 3 · 1 level")
        #expect(RivalTeamsText.summary(.init(yours: 30, theirs: 41, multiplier: -10, shared: 3), name: "Andy")
            == "Only you: 30 pts · Only Andy: 41 pts · Different multipliers: 10 for Andy · 3 cancel out")
    }

    @Test func patchesSendOnlyWhatChanges() throws {
        func json(_ patch: RivalPatch) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
        }
        #expect(try json(RivalPatch()).isEmpty)
        #expect(try json(RivalPatch(featured: true))["featured"] as? Bool == true)
        #expect(try json(RivalPatch(nickname: .some("Big Andy")))["nickname"] as? String == "Big Andy")
        // A cleared nickname is sent as null.
        let cleared = try json(RivalPatch(nickname: .some(nil)))
        #expect(cleared.keys.contains("nickname") && cleared["nickname"] is NSNull)
    }

    @Test func toleratesNewStates() throws {
        // A later server's state or status falls back rather than failing the list.
        let raw = #"{"data":{"season":"2026/27","gameweek":6,"status":"live","max":10,"rivals":[{"entryId":7,"manager":null,"team":"X","nickname":null,"name":"X","featured":false,"state":"somethingNew","leagues":[],"gap":null,"gapBefore":null,"you":null,"them":null,"youBonus":0,"themBonus":0,"gapText":null,"swingText":null}]},"meta":{"apiVersion":"1","generatedAt":"2026-10-02T08:00:00Z"}}"#
        let list = try APIClient.decode(Envelope<RivalsList>.self, from: Data(raw.utf8)).data
        #expect(list.rivals[0].state == .unknown && list.status == .live)
    }
}
