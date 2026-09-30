import Foundation
import Testing
@testable import FPLToolkit

/// Planner responses captured from the live API (27 Sep 2026, team 22615, a test device since deleted).
struct PlannerTests {
    @Test func importedDraft() throws {
        let draft = try fixture("planner-draft-22615", as: PlannerDraft.self)
        #expect(draft.name == "All priced in")
        #expect(draft.gw == 6 && draft.firstEditableGw == 6 && draft.baseGw == 5)
        #expect(draft.isEditable)
        #expect(draft.starting.count == 11 && draft.bench.count == 4)
        #expect(draft.formation == "4-4-2")
        #expect(draft.money.bank == 2.2 && draft.money.startBudget == 99.8)
        #expect(draft.check.ok)
        #expect(draft.freeTransfers == .init(starting: 2, estimated: true))
        #expect(draft.chips.first { $0.key == "wildcard1" }?.state == .played)
        #expect(draft.chips.first { $0.key == "freehit1" }?.state == .available)
        let rows = draft.rows()
        #expect(rows.map(\.position) == [.gk, .def, .mid, .fwd])
        #expect(rows.map(\.picks.count) == [1, 4, 4, 2])
        for pick in draft.starting + draft.bench { #expect(draft.player(pick.playerId) != nil) }
    }

    /// The six-week strip (happy-backend-pal#13): a single, a double coloured by its harder game, a blank.
    @Test func fixtureStrip() throws {
        let json = """
        [{"gw":7,"band":2,"fixtures":[{"gw":7,"blank":false,"opponentClubId":2,"home":true,"kickoff":null,
           "xfdr":{"value":2.14,"lens":"attack","source":"market","band":2}}]},
         {"gw":8,"band":5,"fixtures":[
           {"gw":8,"blank":false,"opponentClubId":3,"home":true,"kickoff":null,"xfdr":{"value":2,"lens":"attack","source":"fpl","band":2}},
           {"gw":8,"blank":false,"opponentClubId":4,"home":false,"kickoff":null,"xfdr":{"value":5,"lens":"attack","source":"fpl","band":5}}]},
         {"gw":9,"band":null,"fixtures":[{"gw":9,"blank":true,"opponentClubId":null,"home":null,"kickoff":null,"xfdr":null}]}]
        """
        let weeks = try JSONDecoder().decode([PlannerDraft.StripWeek].self, from: Data(json.utf8))
        #expect(weeks.map(\.band) == [2, 5, nil])
        #expect(weeks.map(\.isDouble) == [false, true, false])
        #expect(weeks[0].fixtures[0].xfdr?.band == 2)
        #expect(FixtureStrip.spoken(weeks) == "Next 3 gameweeks, difficulty out of 5: GW7 2, GW8 5, two games, GW9 no game")
        // Live (27 Sep, after #13): every player has six weeks from the shown gameweek, each banded.
        let live = try fixture("planner-draft-22615-strip", as: PlannerDraft.self)
        for pick in live.starting + live.bench {
            let strip = live.strip(for: pick.playerId)
            #expect(strip.map(\.gw) == Array(live.gw ..< live.gw + 6))
            #expect(strip.allSatisfy { week in week.band.map { (1...5).contains($0) } ?? true })
        }
        #expect(live.player(live.starting[0].playerId)?.nextFixture?.xfdr?.band != nil)
        // Servers before #13 send no strip: the draft still reads, with nothing to draw.
        let older = try fixture("planner-draft-22615", as: PlannerDraft.self)
        #expect(older.fixtureStrip == nil && older.strip(for: older.starting[0].playerId).isEmpty)
    }

    /// Undo and redo keep one stack per gameweek, as the website does; a new edit clears redo.
    @Test func squadHistory() {
        let squad = { (id: Int) in [PlannerAction.RestorePick(playerId: id, slot: 1, isCaptain: false, isVice: false)] }
        var history = SquadHistory()
        #expect(!history.canUndo(gw: 6) && !history.canRedo(gw: 6))
        history.record(squad(1), gw: 6)         // squad 1 → 2
        history.record(squad(2), gw: 6)         // squad 2 → 3
        history.record(squad(9), gw: 7)         // another week keeps its own stack
        #expect(history.previous(gw: 6) == squad(2))
        history.didUndo(gw: 6, from: squad(3))  // back to 2
        #expect(history.canRedo(gw: 6) && history.next(gw: 6) == squad(3))
        #expect(history.previous(gw: 6) == squad(1))
        history.didRedo(gw: 6, from: squad(2))  // forward to 3 again
        #expect(history.previous(gw: 6) == squad(2) && !history.canRedo(gw: 6))
        history.didUndo(gw: 6, from: squad(3))
        history.record(squad(2), gw: 6)         // a new edit after an undo
        #expect(!history.canRedo(gw: 6))
        #expect(history.previous(gw: 7) == squad(9))
        for i in 0..<60 { history.record(squad(i), gw: 8) }
        var undone = 0
        while let previous = history.previous(gw: 8) { history.didUndo(gw: 8, from: previous); undone += 1 }
        #expect(undone == SquadHistory.limit)
        history.clear()
        #expect(!history.canUndo(gw: 7) && !history.canRedo(gw: 6))
    }

    @Test func shareText() throws {
        let draft = try fixture("planner-draft-22615-strip", as: PlannerDraft.self)
        let text = DraftShareText.make(draft)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.first == "All priced in: GW6 plan")
        #expect(lines.contains { $0.hasPrefix("GK: ") })
        #expect(lines.contains { $0.hasPrefix("FWD: ") })
        #expect(text.contains("(C)") && text.contains("(VC)"))
        #expect(lines.contains { $0.hasPrefix("Bench: ") && $0.components(separatedBy: ", ").count == 4 })
        #expect(lines.contains { $0.hasPrefix("Bank £2.2m · Squad value £99.8m · 2 free transfers") })
        #expect(lines.last == "Planned with FPLToolkit: \(draft.shareUrl)")
    }

    /// The website's fixture switches: xFDR · Auto (by position) until chosen, sent as the contract says.
    @Test func fixtureView() {
        let fresh = FixtureView()
        #expect(fresh.summary == "xFDR · Auto")
        #expect(fresh.queryItems.map(\.description) == ["model=xfdr", "lens=position"])
        let fpl = FixtureView(model: .fpl, lens: .cleanSheet)
        #expect(fpl.summary == "Official FDR")
        #expect(fpl.queryItems.map(\.description) == ["model=fpl", "lens=clean_sheet"])
        let json = #"[{"value":2.14,"lens":"match","source":"market","band":2},{"value":4,"lens":"attack","source":"fpl","band":4}]"#
        let values = try? JSONDecoder().decode([FixtureDifficulty.XFDR].self, from: Data(json.utf8))
        #expect(values?.map(\.display) == ["2.1", "4"])
        #expect(values?.first?.lens == .match)
    }

    /// Team news for a draft (live, 27 Sep, after happy-backend-pal#15): Today's notes, attention first.
    @Test func draftNews() throws {
        let news = try fixture("planner-news-22615", as: PlannerNews.self)
        #expect(news.gw == 6 && !news.insights.isEmpty)
        #expect(news.insights.first?.needsAttention == true)
        #expect(news.insights.allSatisfy { news.player($0.playerId) != nil })
        let firstCalm = news.insights.firstIndex { !$0.needsAttention } ?? news.insights.count
        #expect(news.insights[firstCalm...].allSatisfy { !$0.needsAttention })
    }

    /// Squad evolution and the timeline (live, 27 Sep, after happy-backend-pal#16; Slater → Saka in
    /// GW6 and a Free Hit in GW7 planned on a test device).
    @Test func evolutionAndPlan() throws {
        let evo = try fixture("planner-evolution-22615", as: PlannerEvolution.self)
        #expect(evo.weeks.map(\.gw) == Array(6...11))
        #expect(evo.groups.map(\.position) == [.gk, .def, .mid, .fwd])
        for group in evo.groups {
            for id in group.playerIds {
                #expect(evo.cells(for: id).count == evo.weeks.count && evo.player(id) != nil)
            }
        }
        // Each week's suggested XI has eleven players.
        for (i, _) in evo.weeks.enumerated() {
            let xi = evo.groups.flatMap(\.playerIds).filter { evo.cells(for: $0)[i].suggested }
            #expect(xi.count == 11)
        }
        let plan = try fixture("planner-plan-22615", as: PlannerPlan.self)
        #expect(plan.events.map(\.gw) == [1, 3, 4, 6, 7])
        let gw6 = try #require(plan.events.first { $0.gw == 6 })
        let outs: [String] = gw6.out.map(plan.name)
        let ins: [String] = gw6.in.map(plan.name)
        #expect(outs == ["Slater"] && ins == ["Saka"])
        #expect(plan.events.first { $0.gw == 7 }?.chips.first?.label == "Free Hit 1")
        #expect(plan.ledger.first?.freeTransfers == 2 && plan.totals.hits == 0)
    }

    /// The shortlist (happy-backend-pal#17): items with the vibe flag; a save sends only what changes.
    @Test func shortlist() throws {
        let json = #"{"items":[{"playerId":5,"vibe":true,"addedAt":"2026-09-27T18:10:00.123456+00:00"},{"playerId":7,"vibe":false,"addedAt":null}],"players":{},"max":100}"#
        let list = try JSONDecoder().decode(PlannerShortlist.self, from: Data(json.utf8))
        #expect(list.items.map(\.playerId) == [5, 7] && list.items.first?.vibe == true && list.max == 100)
        let add = try JSONEncoder().encode(PlannerShortlistSave())
        #expect(String(decoding: add, as: UTF8.self) == "{}")
        let vibe = try JSONEncoder().encode(PlannerShortlistSave(vibe: true))
        #expect(String(decoding: vibe, as: UTF8.self) == #"{"vibe":true}"#)
    }

    @Test func afterATransfer() throws {
        let draft = try fixture("planner-draft-22615-transfer", as: PlannerDraft.self)
        #expect(draft.transfers.out == [290] && draft.transfers.in == [12])
        #expect(draft.money.bank == -2.8)
        #expect(draft.ledger.first?.freeTransfers == 2)
    }

    @Test func listAndPicker() throws {
        let list = try fixture("planner-drafts", as: PlannerDraftList.self)
        #expect(list.drafts.map(\.source) == [.blank, .import, .import])
        let picker = try fixture("planner-picker-mid", as: PlannerPicker.self)
        #expect(picker.candidates.first?.player.webName == "Saka")
        #expect(picker.candidates.first?.reason == nil)
        #expect(picker.candidates.contains { $0.reason == "New player must match position" })
    }

    @Test func actionsEncodeAsTheContractSays() throws {
        let json = try String(decoding: JSONEncoder().encode(PlannerAction.pick(12, replacing: 290, gw: 6)), as: UTF8.self)
        #expect(json.contains("\"type\":\"pick\"") && json.contains("\"replacePlayerId\":290") && !json.contains("chip"))
        let reset = try String(decoding: JSONEncoder().encode(PlannerAction.reset), as: UTF8.self)
        #expect(reset == #"{"type":"reset"}"#)
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        let bundle = Bundle(for: PlannerBundleToken.self)
        let url = try #require(
            bundle.url(forResource: name, withExtension: "json")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "api-v1"))
        return try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url)).data
    }
}
private final class PlannerBundleToken {}
