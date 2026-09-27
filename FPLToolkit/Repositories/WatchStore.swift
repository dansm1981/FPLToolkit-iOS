import Foundation
import Observation

/// The watch list shared by the Watch tab and every player sheet, so a change in one shows in the other.
@MainActor
@Observable
final class WatchStore {
    let resource: Resource<Watch>
    private let repository: WatchRepository
    /// Why the last change didn't go through, shown until the next attempt.
    private(set) var updateError: ErrorCopy?
    private(set) var isUpdating = false

    /// Runs before the first load: tells the server which team this device follows, so the
    /// squad in the watch list is never the previous team's.
    private let prepare: @MainActor () async -> Void

    init(repository: WatchRepository, prepare: @escaping @MainActor () async -> Void = {}) {
        self.repository = repository
        self.resource = Resource(repository)
        self.prepare = prepare
    }

    var watch: Watch? { resource.loaded?.value }

    /// Loads once, and again if the last load was cut off and left only the saved copy on screen.
    func loadIfNeeded() async {
        let interrupted = resource.loaded?.isFromCache == true && !resource.isRefreshing && resource.refreshError == nil
        guard resource.isInitial || interrupted else { return }
        await prepare()
        await resource.load()
    }

    func setWatched(_ watched: Bool, playerId: Int) async {
        guard let watch else { return }
        var manual = watch.manual.filter { $0 != playerId }
        if watched { manual.append(playerId) }
        await apply { try await self.repository.update(manual: manual) }
    }

    func setAutoTrackSquad(_ on: Bool) async {
        guard let watch else { return }
        await apply { try await self.repository.update(manual: watch.manual, autoTrackSquad: on) }
    }

    private func apply(_ change: @escaping () async throws -> Loaded<Watch>) async {
        isUpdating = true
        updateError = nil
        defer { isUpdating = false }
        do {
            resource.replace(with: try await change())
        } catch let error as APIError {
            updateError = ErrorCopy(error)
        } catch {}
    }
}
