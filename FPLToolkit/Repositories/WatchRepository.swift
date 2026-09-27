import Foundation

/// The device's watch list (§6.1). Private to this device; saved offline like everything else.
struct WatchRepository: LoadableEndpoint {
    let session: DeviceSession
    let cache: ResponseCache
    private let path = "devices/me/watch"

    init(session: DeviceSession, cache: ResponseCache) {
        self.session = session
        self.cache = cache
    }

    func fetch(bypassCache: Bool = false) async throws -> Loaded<Watch> {
        let fetched = try await session.send("GET", path, as: Watch.self)
        cache.write(fetched.raw, for: path)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    /// Sends the full manual list (and optionally the squad toggle); returns the new watch set.
    func update(manual: [Int], autoTrackSquad: Bool? = nil) async throws -> Loaded<Watch> {
        let fetched = try await session.send("PUT", path, body: WatchUpdate(manual: manual, autoTrackSquad: autoTrackSquad), as: Watch.self)
        cache.write(fetched.raw, for: path)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    func cached() -> Loaded<Watch>? {
        CachedEndpoint<Watch>(client: .production, cache: cache, path: path).cached()
    }
}
