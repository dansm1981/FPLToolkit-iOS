import Foundation
import Testing
@testable import FPLToolkit

private final class ReplayBundleToken {}

/// Live matchday replay (happy-backend-pal#58): the session on the phone and the `replay` field.
@Suite(.serialized)
struct LiveReplayTests {
    @Test func aReplayAsksForItsMomentAndEnds() {
        let started = Date.now.addingTimeInterval(-300)
        let replay = LiveReplay(id: "gw5-2", label: "GW5", durationSeconds: 1200, startedAt: started)
        #expect((299...301).contains(replay.elapsedSeconds))
        #expect(replay.queryItems.map(\.name) == ["replay", "t"])
        #expect(replay.queryItems.first?.value == "gw5-2")
        #expect(!replay.isOver && (899...901).contains(replay.remainingSeconds))

        let finished = LiveReplay(id: "gw5-2", label: "GW5", durationSeconds: 1200,
                                  startedAt: .now.addingTimeInterval(-1200 - 121))
        #expect(finished.isOver && finished.remainingSeconds == 0)
    }

    @Test func aFrozenReplayStaysAtItsMoment() {
        let frozen = LiveReplay(id: "gw5-all", label: "", durationSeconds: 1200, startedAt: .distantPast, frozenAt: 600)
        #expect(frozen.elapsedSeconds == 600 && !frozen.isOver)
        #expect(frozen.queryItems.last?.value == "600")
    }

    @Test func startingAndEndingAReplay() {
        LiveReplay.end()
        #expect(LiveReplay.current == nil)
        LiveReplay.start(id: "gw5-1", label: "GW5: Sat 26 Sep", durationSeconds: 1200)
        #expect(LiveReplay.current?.id == "gw5-1")
        LiveReplay.end()
        #expect(LiveReplay.current == nil)
    }

    @Test func decodesTheReplayOnTheLiveTeam() throws {
        let url = try #require(Bundle(for: ReplayBundleToken.self).url(forResource: "live-team-gw5", withExtension: "json"))
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var data = try #require(envelope["data"] as? [String: Any])
        #expect(try APIClient.decode(Envelope<LiveTeam>.self, from: Data(contentsOf: url)).data.replay == nil)

        data["replay"] = ["id": "gw5-2", "label": "GW5: Sat 26 Sep, 15:00 kick-offs (4 matches)",
                          "at": "2026-09-26T14:42:00.000Z", "elapsedSeconds": 312, "durationSeconds": 1200]
        envelope["data"] = data
        let live = try APIClient.decode(Envelope<LiveTeam>.self, from: JSONSerialization.data(withJSONObject: envelope)).data
        let replay = try #require(live.replay)
        #expect(replay.id == "gw5-2" && replay.elapsedSeconds == 312 && replay.durationSeconds == 1200)
        #expect(replay.at == Date(timeIntervalSince1970: 1_790_433_720))
    }
}
