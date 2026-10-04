import Foundation
import Testing
@testable import FPLToolkit

/// Expected stats (happy-backend-pal#73): decoding and the deltas' wording.
struct ExpectedStatsTests {
    private let meta = #""meta":{"apiVersion":"1","generatedAt":"2026-10-03T08:00:00Z"}"#

    @Test func decodesTheTeamTable() throws {
        let json = #"{"data":{"window":"season","venue":"all","rows":[{"rank":1,"teamId":13,"played":5,"won":5,"drawn":0,"lost":0,"goals":13,"against":5,"points":15,"xg":10.49,"xga":7.33,"goalsVsXg":2.51,"againstVsXga":-2.33}]},"# + meta + "}"
        let t = try APIClient.decode(Envelope<ExpectedTeams>.self, from: Data(json.utf8)).data
        #expect(t.rows.first?.points == 15 && t.rows.first?.xg == 10.49 && t.rows.first?.againstVsXga == -2.33)
    }

    @Test func decodesThePlayerTable() throws {
        let json = #"{"data":{"window":"last5","gameweeks":[5,4,3,2,1],"total":412,"rows":[{"playerId":430,"apps":5,"minutes":450,"goals":5,"assists":0,"xg":4.42,"xa":0.53,"xgi":4.95,"goalsVsXg":0.58,"assistsVsXa":-0.53,"xg90":0.88,"xa90":0.11,"xgi90":0.99},{"playerId":1,"apps":1,"minutes":30,"goals":0,"assists":0,"xg":0.1,"xa":0,"xgi":0.1,"goalsVsXg":-0.1,"assistsVsXa":0,"xg90":null,"xa90":null,"xgi90":null}],"players":{}},"# + meta + "}"
        let p = try APIClient.decode(Envelope<ExpectedPlayers>.self, from: Data(json.utf8)).data
        #expect(p.total == 412 && p.gameweeks.first == 5 && p.rows[0].xg90 == 0.88 && p.rows[1].xg90 == nil)
    }

    @Test func deltaWording() {
        #expect(ExpectedText.delta(2.51) == "+2.51" && ExpectedText.delta(-0.5) == "−0.50" && ExpectedText.delta(0.001) == "0.00")
        #expect(ExpectedText.spokenDelta(0.58, above: "above xG", below: "below xG") == "0.58 above xG")
        #expect(ExpectedText.spokenDelta(0.002, above: "above", below: "below") == "in line with expected")
    }
}
