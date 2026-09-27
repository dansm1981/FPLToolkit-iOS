import Foundation
import Observation

/// App-wide state: which FPL team is connected, the bootstrap data, and the repositories.
@MainActor
@Observable
final class AppModel {
    static let fallbackDisclosure =
        "FPLToolkit is an unofficial, fan-made app. It is not affiliated with the Premier League or Fantasy Premier League."

    private(set) var entryId: Int?
    private(set) var bootstrap: Loaded<Bootstrap>?
    /// The watch list for the connected team's device; nil when no team is connected.
    private(set) var watch: WatchStore?
    /// Alert history for the connected device; nil when no team is connected.
    private(set) var alerts: Resource<AlertHistory>?
    let router = Router()
    let push = PushManager()

    let bootstrapRepository: BootstrapRepository
    let teamRepository: TeamRepository
    let playerRepository: PlayerRepository
    let deviceSession: DeviceSession

    private let cache: ResponseCache
    private let defaults: UserDefaults
    private enum Keys { static let entryId = "entryId" }

    init(client: APIClient = .configured, cache: ResponseCache = .shared, defaults: UserDefaults = .standard) {
        self.bootstrapRepository = BootstrapRepository(client: client, cache: cache)
        self.teamRepository = TeamRepository(client: client, cache: cache)
        self.playerRepository = PlayerRepository(client: client, cache: cache)
        self.deviceSession = DeviceSession(client: client)
        self.cache = cache
        self.defaults = defaults
        let stored = defaults.integer(forKey: Keys.entryId)
        self.entryId = stored > 0 ? stored : nil
        self.bootstrap = bootstrapRepository.bootstrap.cached()
        if entryId != nil { makeWatchStore() }
        push.openLink = { [weak self] link in self?.router.open(link) }
        push.tokenChanged = { [weak self] token in
            guard let self else { return }
            Task { await self.deviceSession.setPushToken(token, entryId: self.entryId) }
        }
    }

    /// The push types the server says are live (bootstrap features). Nothing is offered otherwise.
    var pushFeatures: Bootstrap.Config.Features? {
        #if DEBUG
        // `-forcePushFeatures YES` shows the notification screens before the server switches them on.
        if UserDefaults.standard.bool(forKey: "forcePushFeatures") {
            return .init(priceAlerts: true, availabilityAlerts: true, deadlineReminders: true)
        }
        #endif
        return bootstrap?.value.config.features
    }

    var anyPushFeature: Bool {
        guard let f = pushFeatures else { return false }
        return f.priceAlerts || f.availabilityAlerts || f.deadlineReminders
    }

    func connect(entryId: Int) {
        defaults.set(entryId, forKey: Keys.entryId)
        self.entryId = entryId
        router.selectedTab = .today
        makeWatchStore()
        Task { await syncDevice() }
    }

    /// Forgets the team and everything saved for it. Manual watches stay with the device.
    func disconnect() {
        defaults.removeObject(forKey: Keys.entryId)
        cache.removeAll()
        entryId = nil
        watch = nil
        alerts = nil
        Task { await deviceSession.sync(entryId: nil) }
    }

    /// "Reset app data": deletes this device on the server (watch list included), then everything local.
    func resetAppData() async throws {
        try await deviceSession.reset()
        disconnect()
    }

    /// Keeps the server told which team this device follows. Cheap when nothing changed.
    func syncDevice() async {
        guard let entryId else { return }
        await deviceSession.sync(entryId: entryId)
    }

    private func makeWatchStore() {
        watch = WatchStore(repository: WatchRepository(session: deviceSession, cache: cache)) { [weak self] in
            await self?.syncDevice()
        }
        alerts = Resource(AlertsRepository(session: deviceSession, cache: cache))
    }

    /// Called at launch and on foreground (§3.1). A failure keeps whatever we had.
    func refreshBootstrap() async {
        if let loaded = try? await bootstrapRepository.bootstrap.fetch() {
            bootstrap = loaded
        }
    }

    var disclosure: String { bootstrap?.value.config.disclosure ?? Self.fallbackDisclosure }

    func club(_ id: Int?) -> Bootstrap.Club? {
        guard let id else { return nil }
        return bootstrap?.value.clubs.first { $0.id == id }
    }
}
