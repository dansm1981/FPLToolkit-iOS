import Foundation
import Testing
@testable import FPLToolkit

private final class DefconBundleToken {}

/// The DEFCON screen (happy-backend-pal#32). Captured 28 Sep 2026 from the branch run locally; the
/// endpoint was checked against the website's hub.
struct DefconTests {
    @Test func hub() throws {
        let d = try fixture("defcon")
        #expect(d.stats.map(\.value) == ["50", "164", "17%", "Mainoo"])
        #expect(d.stats[2].sub == "164 of 939 eligible starts")
        #expect(d.filter == Defcon.Filter(position: nil, minStarts: 1, maxPrice: 0, sort: "hits"))
        #expect(d.options.minStarts == [1, 2, 3, 5] && d.options.prices.count == 6 && d.options.sorts.count == 6)
        let top = try #require(d.leaderboard.first)
        #expect(d.player(top.playerId)?.webName == "Mainoo" && d.leaderboard.count == 60)
        #expect(top.hitRate == "100%" && top.dcPer90 == "14.2" && top.cbitPer90 == "2.5" && top.minutes == 354)
        #expect(top.next == Defcon.Next(opponentClubId: 19, home: true, fdr: 2))
    }

    @Test func map() throws {
        let d = try fixture("defcon")
        #expect(d.map.points.count == 279 && d.map.medianDcPer90 == 7.229)
        #expect(d.map.points.filter(\.labelled).count == 6 && d.map.top.count == 12)
        #expect(d.map.points.allSatisfy { [.def, .mid, .fwd].contains($0.position) })
    }

    @Test func reliableLeakyTough() throws {
        let d = try fixture("defcon")
        #expect(d.mostReliable.minSample == 3 && !d.mostReliable.smallSample)
        #expect(d.mostReliable.rows.map { d.player($0.playerId)?.webName } == ["Mainoo", "Pinnock", "Schuster", "M.Sangaré", "Silva"])
        #expect(d.mostReliable.answer.hasPrefix("Mainoo has the highest hit rate of any eligible player with 3+ starts"))
        #expect(d.leakiness.count == 20)
        #expect(d.leakiness[0] == Defcon.Leak(clubId: 4, defHitRate: "53%", defHighlight: true, avgDcVsDef: "10.4",
                                              attackHitRate: "12%", avgDcVsAttack: "6.6"))
        #expect(d.tough.first == Defcon.Tough(playerId: 173, toughStarts: 2, hitRate: "100%"))
    }

    @Test func filtered() throws {
        let d = try fixture("defcon-def-filtered")
        #expect(d.filter == Defcon.Filter(position: .def, minStarts: 3, maxPrice: 5, sort: "cbitPer90"))
        #expect(d.map.filter == Defcon.MapFilter(position: .fwd, minStarts: 5) && d.map.points.count == 11)
        #expect(d.leaderboard.allSatisfy { d.player($0.playerId)?.position == .def && $0.starts >= 3 })
    }

    @Test func query() {
        let repo = ResearchRepository(client: .production, cache: .shared)
        let plain = repo.defcon(position: nil, minStarts: 1, maxPrice: 0, sort: "hits", mapPosition: nil, mapMinStarts: 1)
        #expect(plain.path == "defcon" && plain.query.isEmpty)
        let full = repo.defcon(position: .def, minStarts: 3, maxPrice: 4.5, sort: "cost", mapPosition: .mid, mapMinStarts: 5)
        #expect(full.query.map { "\($0.name)=\($0.value ?? "")" }
            == ["position=DEF", "minStarts=3", "maxPrice=4.5", "sort=cost", "mapPosition=MID", "mapMinStarts=5"])
        #expect(repo.defcon(position: nil, minStarts: 1, maxPrice: 5, sort: "hits", mapPosition: nil, mapMinStarts: 1)
            .query == [URLQueryItem(name: "maxPrice", value: "5.0")])
    }

    private func fixture(_ name: String) throws -> Defcon {
        let url = try #require(Bundle(for: DefconBundleToken.self).url(forResource: name, withExtension: "json"))
        return try APIClient.decode(Envelope<Defcon>.self, from: Data(contentsOf: url)).data
    }
}
