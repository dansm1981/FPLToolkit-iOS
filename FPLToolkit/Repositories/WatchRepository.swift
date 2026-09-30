import Foundation

/// What WatchStore needs from the server: WatchRepository, or a stand-in in tests.
protocol WatchService: LoadableEndpoint where Value == Watch {
    func update(manual: [Int], autoTrackSquad: Bool?) async throws -> Loaded<Watch>
}

/// The device's watch list (§6.1). Private to this device; saved offline like everything else.
struct WatchRepository: WatchService {
    let session: DeviceSession
    let cache: ResponseCache
    private let path = "devices/me/watch"
    /// Saved per team, so a saved list can never show another team's squad.
    private let cacheKey: String

    /// `cacheKeySuffix` is the team ID, or "explore" when there's no team.
    init(session: DeviceSession, cache: ResponseCache, cacheKeySuffix: String) {
        self.session = session
        self.cache = cache
        self.cacheKey = "devices/me/watch-\(cacheKeySuffix)"
    }

    func fetch(bypassCache: Bool = false) async throws -> Loaded<Watch> {
        let fetched = try await session.send("GET", path, as: Watch.self)
        cache.write(fetched.raw, for: cacheKey)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    /// Sends the full manual list (and optionally the squad toggle); returns the new watch set.
    func update(manual: [Int], autoTrackSquad: Bool? = nil) async throws -> Loaded<Watch> {
        let fetched = try await session.send("PUT", path, body: WatchUpdate(manual: manual, autoTrackSquad: autoTrackSquad), as: Watch.self)
        cache.write(fetched.raw, for: cacheKey)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    func cached() -> Loaded<Watch>? {
        CachedEndpoint<Watch>(client: .production, cache: cache, path: cacheKey).cached()
    }
}

/// This device's alert history (contract §12.4): what was sent, held or not sent, and why.
struct AlertsRepository: LoadableEndpoint {
    let session: DeviceSession
    let cache: ResponseCache
    private let path = "devices/me/alerts"

    init(session: DeviceSession, cache: ResponseCache) {
        self.session = session
        self.cache = cache
    }

    func fetch(bypassCache: Bool = false) async throws -> Loaded<AlertHistory> {
        let fetched = try await session.send("GET", path, as: AlertHistory.self)
        cache.write(fetched.raw, for: path)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    func cached() -> Loaded<AlertHistory>? {
        CachedEndpoint<AlertHistory>(client: .production, cache: cache, path: path).cached()
    }
}
