import Foundation

/// A decoded response plus where it came from. `savedAt` is set only when it was
/// served from the offline cache, so screens can say "Saved at …" and never pass it off as fresh.
struct Loaded<T: Sendable>: Sendable {
    let value: T
    let meta: Meta
    let savedAt: Date?

    var isFromCache: Bool { savedAt != nil }
}

struct BootstrapRepository: Sendable {
    let client: APIClient

    func load(bypassCache: Bool = false) async throws -> Loaded<Bootstrap> {
        let fetched = try await client.get("bootstrap", as: Bootstrap.self, bypassCache: bypassCache)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }
}

struct TeamRepository: Sendable {
    let client: APIClient

    func team(entryId: Int, bypassCache: Bool = false) async throws -> Loaded<Team> {
        let fetched = try await client.get("team/\(entryId)", as: Team.self, bypassCache: bypassCache)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    func today(entryId: Int, bypassCache: Bool = false) async throws -> Loaded<Today> {
        let fetched = try await client.get("team/\(entryId)/today", as: Today.self, bypassCache: bypassCache)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }
}

struct PlayerRepository: Sendable {
    let client: APIClient

    func player(id: Int, bypassCache: Bool = false) async throws -> Loaded<PlayerSheet> {
        let fetched = try await client.get("players/\(id)", as: PlayerSheet.self, bypassCache: bypassCache)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }
}
