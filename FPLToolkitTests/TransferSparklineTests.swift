import Foundation
import Testing
@testable import FPLToolkit

/// Team news sparklines (happy-backend-pal#65): the daily transfers on Today, and their words.
struct TransferSparklineTests {
    private func day(_ date: String, _ ins: Int, _ outs: Int) -> Today.TransferDay {
        try! JSONDecoder().decode(Today.TransferDay.self,
                                  from: Data(#"{"date":"\#(date)","in":\#(ins),"out":\#(outs)}"#.utf8))
    }

    @Test func decodesTheTrendsAndStaysOptional() throws {
        let json = #"{"transferTrends":{"8":[{"date":"2026-09-30","in":1200,"out":300},{"date":"2026-10-01","in":900,"out":1500}]}}"#
        struct Wrapper: Decodable { let transferTrends: [String: [Today.TransferDay]]? }
        let trends = try #require(try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8)).transferTrends)
        #expect(trends["8"]?.map(\.in) == [1200, 900] && trends["8"]?.last?.out == 1500)
        #expect(try JSONDecoder().decode(Wrapper.self, from: Data("{}".utf8)).transferTrends == nil)
    }

    @Test func shortCounts() {
        #expect(Format.compactCount(820) == "820")
        #expect(Format.compactCount(12_340) == "12.3k")
        #expect(Format.compactCount(250_400) == "250k")
        #expect(Format.compactCount(1_234_000) == "1.2m")
        #expect(Format.compactCount(-4_100) == "−4.1k")
    }

    @Test func netAndSpokenSummary() {
        let days = [day("2026-09-29", 1_000, 200), day("2026-09-30", 5_000, 300), day("2026-10-01", 800, 900)]
        #expect(TransferSparkline.netText(5_400) == "+5.4k net in")
        #expect(TransferSparkline.netText(-900) == "−900 net out")
        #expect(TransferSparkline.netText(0) == "Level")
        #expect(TransferSparkline.spoken(days)
            == "Transfers over the last 3 days: 6,800 in, 1,400 out, 5,400 more in than out. Busiest: Wednesday 30 September, 5,000 in.")
    }
}
