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

    @Test func sideBySidePairsSharedPlayersFirst() throws {
        let d = try fixture("rival-1699334", as: RivalComparison.self)
        let teams = try #require(d.teams)
        let position: (Int) -> Position? = { d.player($0)?.position }
        let fwd = RivalSideBySide.lines(teams.rows, group: .fwd, position: position)
        // Haaland is both captains: one row, first.
        let first = try #require(fwd.first)
        #expect(first.shared && d.player(first.you?.row.playerId)?.webName == "Haaland" && first.you?.value == 12)
        // Green when the same player counts the same; red for two different players.
        #expect(first.match == .same)
        #expect(xiLines(teams, position).filter { !$0.shared }.allSatisfy { $0.match != .same })
        // Each side has its XI once across the four groups, and its bench in the last.
        let xi = [RivalSideBySide.Band.gk, .def, .mid, .fwd].flatMap { RivalSideBySide.lines(teams.rows, group: $0, position: position) }
        #expect(xi.compactMap(\.you).count == 11 && xi.compactMap(\.them).count == 11)
        let bench = RivalSideBySide.lines(teams.rows, group: .bench, position: position)
        #expect(bench.compactMap(\.you).count == 4 && bench.allSatisfy { ($0.you?.side.multiplier ?? 0) == 0 })
        // Points by group match the server's figures for the gameweek.
        let def = RivalSideBySide.lines(teams.rows, group: .def, position: position)
        #expect(def.compactMap(\.you).reduce(0) { $0 + $1.value } == d.stats.gw?.you.byPosition?.def)
        // Pairs within a group run biggest first.
        let mine = def.filter { !$0.shared }.compactMap(\.you).map(\.value)
        #expect(mine == mine.sorted(by: >))
        // Their moves (happy-backend-pal#70): GW5 as picked, and the season's transfers.
        let latest = try #require(d.latest)
        #expect(latest.gameweek == 5 && d.player(latest.captainId)?.webName == "Haaland" && latest.captainMultiplier == 2)
        #expect(latest.transfers.isEmpty && latest.chip == nil && latest.hits == 0)
        let history = try #require(d.transfers)
        #expect(history.total == 11 && history.weeks.map(\.gw) == [4, 3])
        #expect(history.weeks[0].note == "Free Hit: their team went back afterwards" && history.weeks[0].moves.count == 9)
        #expect(history.weeks[1].moves.first?.outCost == 4.5 && history.weeks[1].chipLabel == "Triple Captain")
        // GW Audit and how you stack up (happy-backend-pal#71).
        let audit = try #require(d.audit)
        #expect(audit.weeks.map(\.gw) == [5, 4, 3, 2, 1] && audit.weeks[4].chipLabel == "Bench Boost")
        #expect(d.player(audit.weeks[1].captainId)?.webName == "João Pedro" && audit.weeks[1].transfers.count == 9)
        let outlook = try #require(d.outlook)
        #expect(outlook.gameweek == 6 && outlook.threats.count == 3 && outlook.opportunities.count == 3)
        #expect(d.player(outlook.threats.first?.playerId)?.webName == "Groß")
    }

    private func xiLines(_ teams: RivalComparison.Teams, _ position: (Int) -> Position?) -> [RivalSideBySide.Line] {
        [RivalSideBySide.Band.gk, .def, .mid, .fwd].flatMap { RivalSideBySide.lines(teams.rows, group: $0, position: position) }
    }

    @Test func outlookWording() {
        let captain = RivalComparison.Outlook.Player(playerId: 1, expected: 6.2, multiplier: 2)
        #expect(RivalMovesText.expected(captain) == "12.4 xP")
        let o = RivalComparison.Outlook(gameweek: 6, theirGameweek: 5, yourGameweek: 5, threats: [captain], opportunities: [])
        #expect(RivalMovesText.outlookNote(o, name: "Andy")
            == "xP is FPL's expected points for GW6, doubled for a captain. Compares Andy's GW5 team with your GW5 team: transfers before the deadline may change it.")
        // Without the model's simulations there's no head-to-head.
        #expect(o.headToHead == nil)
    }

    /// The head-to-head on the projection model's simulations (Dan's other session, 4 Oct). The
    /// database time comes back with "+00:00"; it must decode, or the whole rival page fails.
    @Test func headToHead() throws {
        let json = #"{"gameweek":6,"theirGameweek":5,"yourGameweek":5,"threats":[],"opportunities":[],"headToHead":{"win":0.541,"draw":0.043,"loss":0.416,"you":{"mean":52.3,"median":52,"p10":38,"p90":67},"them":{"mean":49.1,"median":49,"p10":35,"p90":64},"gap":{"median":3,"p10":-14,"p90":19},"sims":2000,"stage":"Odds in","modelRunAt":"2026-10-04T18:24:42.771+00:00"}}"#
        let o = try APIClient.decode(RivalComparison.Outlook.self, from: Data(json.utf8))
        let h = try #require(o.headToHead)
        #expect(h.win == 0.541 && h.you.median == 52 && h.gap.p10 == -14 && h.modelRunAt != nil)
        #expect(RivalHeadToHeadText.pct(h.win) == "54%" && RivalHeadToHeadText.pct(h.loss) == "42%")
        #expect(RivalHeadToHeadText.range(h.you) == "Median 52 (38–67)")
        #expect(RivalHeadToHeadText.gap(h.gap) == "+3 (−14 to +19)")
        #expect(RivalHeadToHeadText.spokenOdds(h, name: "Andy") == "You win 54%, draw 4%, Andy wins 42%")
        #expect(RivalHeadToHeadText.note(h, gameweek: 6).hasPrefix("From 2,000 simulations of GW6 by the projection model (Odds in), run "))
        // Older answers have no headToHead (or null): still fine.
        let null = try APIClient.decode(RivalComparison.Outlook.self, from: Data(json.replacingOccurrences(
            of: #""headToHead":{"#, with: #""headToHead":null,"x":{"#).utf8))
        #expect(null.headToHead == nil)
    }

    @Test func transferWording() {
        let week = RivalComparison.TransferHistory.Week(gw: 4, chip: "freehit", chipLabel: "Free Hit", hits: 0,
                                                       note: "Free Hit: their team went back afterwards", moves: [])
        #expect(RivalMovesText.weekTitle(week) == "GW4 · Free Hit")
        #expect(RivalMovesText.weekTitle(.init(gw: 5, chip: nil, chipLabel: nil, hits: 4, note: nil, moves: [])) == "GW5 · −4 hit")
        #expect(RivalMovesText.summary(.init(total: 11, hits: 0, weeks: [week])) == "11 transfers this season · no hits")
        #expect(RivalMovesText.summary(.init(total: 1, hits: 4, weeks: [])) == "1 transfer this season · 4 pts on hits")
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

    @Test func todaySuggestsARivalWhenNoneIsStarred() {
        #expect(TodayText.rivalPrompt(hasRivals: false).title == "Pick a rival")
        #expect(TodayText.rivalPrompt(hasRivals: true).title == "Star a rival")
    }
}
