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

    let bootstrapRepository: BootstrapRepository
    let teamRepository: TeamRepository
    let playerRepository: PlayerRepository

    private let defaults: UserDefaults
    private enum Keys { static let entryId = "entryId" }

    init(client: APIClient = .production, defaults: UserDefaults = .standard) {
        self.bootstrapRepository = BootstrapRepository(client: client)
        self.teamRepository = TeamRepository(client: client)
        self.playerRepository = PlayerRepository(client: client)
        self.defaults = defaults
        let stored = defaults.integer(forKey: Keys.entryId)
        self.entryId = stored > 0 ? stored : nil
    }

    func connect(entryId: Int) {
        defaults.set(entryId, forKey: Keys.entryId)
        self.entryId = entryId
    }

    func disconnect() {
        defaults.removeObject(forKey: Keys.entryId)
        entryId = nil
    }

    /// Called at launch and on foreground (§3.1). A failure keeps whatever we had.
    func refreshBootstrap() async {
        if let loaded = try? await bootstrapRepository.load() {
            bootstrap = loaded
        }
    }

    var disclosure: String { bootstrap?.value.config.disclosure ?? Self.fallbackDisclosure }

    func club(_ id: Int?) -> Bootstrap.Club? {
        guard let id else { return nil }
        return bootstrap?.value.clubs.first { $0.id == id }
    }
}
