import Foundation
import Testing
@testable import FPLToolkit

struct CacheTests {
    private let cache = ResponseCache(
        directory: FileManager.default.temporaryDirectory.appending(path: "cache-tests-\(UUID().uuidString)"))

    @Test func savedResponseComesBackLabelledWithItsAge() throws {
        let raw = try fixtureData("today-3612045-attention")
        cache.write(raw, for: "team/3612045/today")

        let endpoint = CachedEndpoint<Today>(client: .production, cache: cache, path: "team/3612045/today")
        let loaded = try #require(endpoint.cached())
        #expect(loaded.isFromCache)
        #expect(loaded.value.status == .attention)
        #expect(abs(try #require(loaded.savedAt).timeIntervalSinceNow) < 60)
        cache.removeAll()
    }

    @Test func unreadableCacheIsDropped() {
        cache.write(Data("not json".utf8), for: "team/1/today")
        let endpoint = CachedEndpoint<Today>(client: .production, cache: cache, path: "team/1/today")
        #expect(endpoint.cached() == nil)
        #expect(cache.read("team/1/today") == nil)
    }

    @Test func removeAllForgetsEverything() throws {
        cache.write(try fixtureData("bootstrap"), for: "bootstrap")
        cache.removeAll()
        #expect(cache.read("bootstrap") == nil)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: CacheBundleToken.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

private final class CacheBundleToken {}
