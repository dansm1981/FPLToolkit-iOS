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

    /// Players whose names match, best first. Not saved offline: results are only useful live.
    func search(_ text: String) async throws -> PlayerSearchResult {
        try await client.get("players/search", query: [URLQueryItem(name: "q", value: text)], as: PlayerSearchResult.self).envelope.data
    }

    /// Whether the server has player search yet (it arrives with a backend release). Before
    /// then the address is caught by `players/{id}` ("invalid_player_id"), or doesn't exist (404).
    /// Any other failure (offline, FPL down) counts as available, so search isn't hidden by accident.
    func searchIsAvailable() async -> Bool {
        do {
            _ = try await search("aa")
            return true
        } catch APIError.server(.invalidPlayerId, _, _), APIError.unexpected(status: 404?) {
            return false
        } catch {
            return true
        }
    }
}
