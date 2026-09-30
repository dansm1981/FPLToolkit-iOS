import Foundation
import os
import Testing
@testable import FPLToolkit

/// Batch 3 A: recent answers kept in memory, and watch changes that wait their turn.
@Suite(.serialized)
struct FreshnessTests {
    // MARK: Recent responses

    @Test func maxAgeFollowsTheServersCacheControl() {
        #expect(RecentResponses.maxAge("public, max-age=15, s-maxage=15, stale-while-revalidate=30") == 15)
        #expect(RecentResponses.maxAge("public, max-age=300, s-maxage=600") == 300)
        #expect(RecentResponses.maxAge("private, no-store") == nil)
        #expect(RecentResponses.maxAge("public, max-age=60, no-cache") == nil)
        #expect(RecentResponses.maxAge(nil) == nil)
    }

    @Test func keptAnswersExpire() {
        let recent = RecentResponses()
        let start = Date(timeIntervalSince1970: 0)
        recent.keep(Data("a".utf8), for: "k", cacheControl: "max-age=60", now: start)
        #expect(recent.fresh("k", now: start.addingTimeInterval(59)) == Data("a".utf8))
        #expect(recent.fresh("k", now: start.addingTimeInterval(60)) == nil)
        recent.keep(Data("b".utf8), for: "n", cacheControl: "private, no-store", now: start)
        #expect(recent.fresh("n", now: start) == nil)
    }

    @Test func aRepeatGetIsAnsweredFromMemoryUntilRefreshOrAChange() async throws {
        let body = try fixtureData("bootstrap")
        let stub = StubServer(routes: [
            "GET bootstrap": .init(cacheControl: "public, max-age=60", body: body),
            "PUT devices/me/watch": .init(cacheControl: "private, no-store", body: body),
        ])
        let client = stub.client(recent: RecentResponses())

        _ = try await client.get("bootstrap", as: Bootstrap.self)
        _ = try await client.get("bootstrap", as: Bootstrap.self)
        #expect(stub.requests == ["GET bootstrap"])

        _ = try await client.get("bootstrap", as: Bootstrap.self, bypassCache: true)
        #expect(stub.requests.count == 2)

        _ = try await client.send("PUT", "devices/me/watch", as: Bootstrap.self)
        _ = try await client.get("bootstrap", as: Bootstrap.self)
        #expect(stub.requests == ["GET bootstrap", "GET bootstrap", "PUT devices/me/watch", "GET bootstrap"])
    }

    @Test func privateAnswersAreNeverKept() async throws {
        let body = try fixtureData("bootstrap")
        let stub = StubServer(routes: ["GET bootstrap": .init(cacheControl: "private, no-store", body: body)])
        let client = stub.client(recent: RecentResponses())
        _ = try await client.get("bootstrap", as: Bootstrap.self)
        _ = try await client.get("bootstrap", as: Bootstrap.self)
        #expect(stub.requests.count == 2)
    }

    // MARK: Watch changes

    @MainActor @Test func quickTapsOnTwoPlayersBothStick() async throws {
        let server = try FakeWatchService(manual: [1])
        let store = WatchStore(repository: server)
        await store.loadIfNeeded()

        async let first: Void = store.setWatched(true, playerId: 10)
        async let second: Void = store.setWatched(true, playerId: 11)
        _ = await (first, second)

        // Either tap may go first; the second is always built on the first's result.
        #expect(server.sent.count == 2)
        #expect(Set(server.sent[1]) == [1, 10, 11])
        #expect(Set(store.watch?.manual ?? []) == [1, 10, 11])
        #expect(!store.isUpdating)
    }

    @MainActor @Test func aTapShowsStraightAwayAndWaitsForTheList() async throws {
        let server = try FakeWatchService(manual: [])
        let store = WatchStore(repository: server)

        let tap = Task { await store.setWatched(true, playerId: 7) }
        while !store.isUpdating { await Task.yield() }
        #expect(store.isManual(7))
        await tap.value

        #expect(server.sent == [[7]])
        #expect(store.isManual(7))
        #expect(store.updateError == nil)
    }

    @MainActor @Test func aTapWhenTheListCantLoadSaysSo() async throws {
        let server = try FakeWatchService(manual: [], failFetch: true)
        let store = WatchStore(repository: server)
        await store.setWatched(true, playerId: 7)
        #expect(server.sent.isEmpty)
        #expect(store.updateError != nil)
        #expect(!store.isManual(7))
    }

    // MARK: Helpers

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: FreshnessBundleToken.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

private final class FreshnessBundleToken {}

/// A watch list server in memory: replies after a short delay, recording each list sent.
private final class FakeWatchService: WatchService, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var manual: [Int]
    private var sentLists: [[Int]] = []
    private let failFetch: Bool
    private let meta: Meta

    init(manual: [Int], failFetch: Bool = false) throws {
        self.manual = manual
        self.failFetch = failFetch
        let url = try #require(Bundle(for: FreshnessBundleToken.self).url(forResource: "watch-squad", withExtension: "json"))
        meta = try APIClient.decode(Envelope<Watch>.self, from: Data(contentsOf: url)).meta
    }

    var sent: [[Int]] { lock.withLock { sentLists } }

    func fetch(bypassCache: Bool) async throws -> Loaded<Watch> {
        try await Task.sleep(for: .milliseconds(20))
        if failFetch { throw APIError.server(code: .dataUnavailable, message: "down", retryable: true) }
        return try loaded(lock.withLock { manual })
    }

    func cached() -> Loaded<Watch>? { nil }

    func update(manual next: [Int], autoTrackSquad: Bool?) async throws -> Loaded<Watch> {
        lock.withLock {
            sentLists.append(next)
            manual = next
        }
        try await Task.sleep(for: .milliseconds(30))
        return try loaded(next)
    }

    private func loaded(_ manual: [Int]) throws -> Loaded<Watch> {
        let json = #"{"autoTrackSquad":false,"manual":\#(manual),"squad":null,"effective":[],"players":{}}"#
        return Loaded(value: try APIClient.decode(Watch.self, from: Data(json.utf8)), meta: meta, savedAt: nil)
    }
}

/// Answers "METHOD path" from a table through URLProtocol, and records what was asked.
private final class StubServer: @unchecked Sendable {
    struct Route {
        let cacheControl: String
        let body: Data
    }

    static let base = URL(string: "https://stub.test/api/mobile/v1/")!
    private static let lock = OSAllocatedUnfairLock()
    nonisolated(unsafe) private static var current: StubServer?

    let routes: [String: Route]
    private var asked: [String] = []

    init(routes: [String: Route]) {
        self.routes = routes
        Self.lock.withLock { Self.current = self }
    }

    var requests: [String] { Self.lock.withLock { asked } }

    func client(recent: RecentResponses) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.urlCache = nil
        return APIClient(baseURL: Self.base, session: URLSession(configuration: config), recent: recent)
    }

    static func answer(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        let path = request.url!.absoluteString.replacingOccurrences(of: base.absoluteString, with: "")
        let key = "\(request.httpMethod ?? "GET") \(path)"
        return lock.withLock {
            current?.asked.append(key)
            let route = current?.routes[key]
            let response = HTTPURLResponse(url: request.url!, statusCode: route == nil ? 404 : 200, httpVersion: nil,
                                           headerFields: ["Cache-Control": route?.cacheControl ?? "no-store"])!
            return (response, route?.body ?? Data())
        }
    }
}

private final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (response, body) = StubServer.answer(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
