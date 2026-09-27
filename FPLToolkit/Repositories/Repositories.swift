import Foundation

/// A decoded response plus where it came from. `savedAt` is set only when it was
/// served from the offline cache, so screens can say "Saved at …" and never pass it off as fresh.
struct Loaded<T: Sendable>: Sendable {
    let value: T
    let meta: Meta
    let savedAt: Date?

    var isFromCache: Bool { savedAt != nil }
}

/// Something a screen can load: network first, with the last saved copy available.
protocol LoadableEndpoint<Value>: Sendable {
    associatedtype Value: Decodable & Sendable
    func fetch(bypassCache: Bool) async throws -> Loaded<Value>
    func cached() -> Loaded<Value>?
}

/// Network first; every good response is saved. `cached` returns the last saved copy, if any.
struct CachedEndpoint<T: Decodable & Sendable>: LoadableEndpoint {
    let client: APIClient
    let cache: ResponseCache
    let path: String

    func fetch(bypassCache: Bool = false) async throws -> Loaded<T> {
        let fetched = try await client.get(path, as: T.self, bypassCache: bypassCache)
        cache.write(fetched.raw, for: path)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    func cached() -> Loaded<T>? {
        guard let (data, savedAt) = cache.read(path) else { return nil }
        guard let envelope = try? APIClient.decode(Envelope<T>.self, from: data) else {
            // Saved by an older build with a different shape: drop it.
            cache.remove(path)
            return nil
        }
        return Loaded(value: envelope.data, meta: envelope.meta, savedAt: savedAt)
    }
}

struct BootstrapRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    var bootstrap: CachedEndpoint<Bootstrap> { .init(client: client, cache: cache, path: "bootstrap") }
}

struct TeamRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    func team(entryId: Int) -> CachedEndpoint<Team> {
        .init(client: client, cache: cache, path: "team/\(entryId)")
    }

    func today(entryId: Int) -> CachedEndpoint<Today> {
        .init(client: client, cache: cache, path: "team/\(entryId)/today")
    }
}

struct PlayerRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    func player(id: Int) -> CachedEndpoint<PlayerSheet> {
        .init(client: client, cache: cache, path: "players/\(id)")
    }
}
