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
