import Foundation
import Observation

/// App-wide state: which FPL team is connected, the bootstrap data, and the repositories.
@MainActor
@Observable
final class AppModel {
    static let fallbackDisclosure =
        "FPLToolkit is an unofficial, fan-made app. It is not affiliated with the Premier League or Fantasy Premier League."

    private(set) var entryId: Int?
    /// "Explore without a team": the app is usable (watch, search, players) with no team connected.
    private(set) var exploring = false
    private(set) var bootstrap: Loaded<Bootstrap>?
    /// The device's watch list; nil before a team is connected or exploring starts.
    private(set) var watch: WatchStore?
    /// Alert history for the device; nil before a team is connected or exploring starts.
    private(set) var alerts: Resource<AlertHistory>?
    /// The published squad's players, set when Today or Team loads it, so any player list can
    /// mark "in your team" (Dan, 29 Sep). Empty without a team.
    var squadIds: Set<Int> = []
    let router = Router()
    let push = PushManager()

    let bootstrapRepository: BootstrapRepository
    let teamRepository: TeamRepository
    let playerRepository: PlayerRepository
    let researchRepository: ResearchRepository
    let marketRepository: MarketRepository
    let playersResearchRepository: PlayersResearchRepository
    let eliteRepository: EliteRepository
    let liveRepository: LiveRepository
    let deviceSession: DeviceSession
    let plannerRepository: PlannerRepository
    /// The device's shortlist (the planner's star and Shortlist screen).
    let shortlist: ShortlistStore
    /// The device's mini-leagues (Team tab).
    let leagues: LeaguesStore

    private let cache: ResponseCache
    private let defaults: UserDefaults
    private enum Keys {
        static let entryId = "entryId"
        static let exploring = "exploring"
    }

    init(client: APIClient = .configured, cache: ResponseCache = .shared, defaults: UserDefaults = .standard) {
        self.bootstrapRepository = BootstrapRepository(client: client, cache: cache)
        self.teamRepository = TeamRepository(client: client, cache: cache)
        self.playerRepository = PlayerRepository(client: client, cache: cache)
        self.researchRepository = ResearchRepository(client: client, cache: cache)
        self.marketRepository = MarketRepository(client: client, cache: cache)
        self.playersResearchRepository = PlayersResearchRepository(client: client, cache: cache)
        self.eliteRepository = EliteRepository(client: client, cache: cache)
        self.liveRepository = LiveRepository(client: client, cache: cache)
        let session = DeviceSession(client: client)
        self.deviceSession = session
        let planner = PlannerRepository(session: session, cache: cache)
        self.plannerRepository = planner
        self.shortlist = ShortlistStore(repository: planner)
        self.leagues = LeaguesStore(repository: LeaguesRepository(session: session))
        self.cache = cache
        self.defaults = defaults
        let stored = defaults.integer(forKey: Keys.entryId)
        self.entryId = stored > 0 ? stored : nil
        self.exploring = entryId == nil && defaults.bool(forKey: Keys.exploring)
        self.bootstrap = bootstrapRepository.bootstrap.cached()
        if entryId != nil || exploring { makeWatchStore() }
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
        defaults.removeObject(forKey: Keys.exploring)
        self.entryId = entryId
        exploring = false
        squadIds = []
        router.selectedTab = .today
        makeWatchStore()
        Task { await syncDevice() }
    }

    /// Uses the app without a team: Watch, search and player pages work; Today and Team invite a team.
    /// A watch list made while exploring stays with the device if a team is added later.
    func startExploring() {
        defaults.set(true, forKey: Keys.exploring)
        exploring = true
        router.selectedTab = .watch
        makeWatchStore()
    }

    /// Forgets the team and everything saved for it, back to the first screen.
    /// Manual watches stay with the device.
    func disconnect() {
        defaults.removeObject(forKey: Keys.entryId)
        defaults.removeObject(forKey: Keys.exploring)
        cache.removeAll()
        RecentResponses.shared.removeAll()
        entryId = nil
        exploring = false
        squadIds = []
        watch = nil
        alerts = nil
        Task { await deviceSession.sync(entryId: nil) }
    }

    /// "Reset app data": deletes this device on the server (watch list included), then everything local.
    func resetAppData() async throws {
        try await deviceSession.reset()
        shortlist.reset()
        leagues.reset()
        disconnect()
    }

    /// Keeps the server told which team this device follows (none while exploring). Cheap when
    /// nothing changed. Exploring matters too: a device kept in the Keychain from an earlier
    /// install may still be linked to an old team on the server.
    func syncDevice() async {
        if let entryId {
            await deviceSession.sync(entryId: entryId)
        } else if exploring {
            await deviceSession.sync(entryId: nil)
        }
    }

    // MARK: Stars (batch 3: the shortlist and the watch list are one list)

    /// Stars not yet confirmed by the server, shown straight away: player → starred, with a
    /// number so an older reply doesn't clear a newer tap.
    private var pendingStars: [Int: (on: Bool, tap: Int)] = [:]
    private var starTaps = 0
    private var starListsMerged = false

    /// On your shortlist, which is also your watch list.
    func isStarred(_ playerId: Int) -> Bool {
        if let pending = pendingStars[playerId] { return pending.on }
        return shortlist.contains(playerId) || (watch?.isManual(playerId) ?? false)
    }

    /// A star anywhere: adds the player to (or takes him off) the shortlist and the watch list.
    func setStarred(_ on: Bool, playerId: Int) async {
        starTaps += 1
        let tap = starTaps
        pendingStars[playerId] = (on, tap)
        async let listed: Void = shortlist.set(on, playerId: playerId)
        async let watched: Void = watch?.setWatched(on, playerId: playerId) ?? ()
        _ = await (listed, watched)
        if pendingStars[playerId]?.tap == tap { pendingStars[playerId] = nil }
    }

    func toggleStar(_ playerId: Int) async {
        await setStarred(!isStarred(playerId), playerId: playerId)
    }

    /// Why the last star didn't stick, from either list.
    var starError: ErrorCopy? { shortlist.updateError ?? watch?.updateError }

    /// Once per launch: makes the two lists one, keeping every player starred or watched before
    /// they were merged (the shortlist has a cap; anything over it stays watched).
    func mergeStarLists() async {
        guard !starListsMerged, let watchStore = watch else { return }
        await watchStore.loadIfNeeded()
        await shortlist.loadIfNeeded()
        guard !starListsMerged, let watched = watchStore.watch, let list = shortlist.list else { return }
        starListsMerged = true
        let listed = list.items.map(\.playerId)
        let watchOnly = watched.manual.filter { !listed.contains($0) }
        let listOnly = listed.filter { !watched.manual.contains($0) }
        if !listOnly.isEmpty { await watchStore.watchAll(listOnly) }
        for id in watchOnly.prefix(max(0, list.max - list.items.count)) {
            await shortlist.set(true, playerId: id)
        }
    }

    private func makeWatchStore() {
        let key = entryId.map(String.init) ?? "explore"
        starListsMerged = false
        watch = WatchStore(repository: WatchRepository(session: deviceSession, cache: cache, cacheKeySuffix: key)) { [weak self] in
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

    /// The server can require a newer app (bootstrap.config.minSupportedAppVersion, contract §2.4).
    var updateRequired: Bool {
        guard let minimum = bootstrap?.value.config.minSupportedAppVersion else { return false }
        return AppVersion.current < AppVersion(minimum)
    }

    /// Whether the server offers an ability newer apps rely on, e.g. "plannerPreview".
    func supports(_ capability: String) -> Bool {
        bootstrap?.value.config.capabilities?.contains(capability) ?? false
    }

    func club(_ id: Int?) -> Bootstrap.Club? {
        guard let id else { return nil }
        return bootstrap?.value.clubs.first { $0.id == id }
    }
}
