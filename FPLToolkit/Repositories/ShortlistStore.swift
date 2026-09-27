import Foundation
import Observation

/// The device's shortlist (the website's Shortlist), shared by the picker's star, the player menu
/// and the Shortlist screen, so a change in one shows in the others. The server keeps it.
@MainActor
@Observable
final class ShortlistStore {
    private let repository: PlannerRepository
    private(set) var list: PlannerShortlist?
    private(set) var loadError: ErrorCopy?
    /// Why the last change didn't go through.
    private(set) var updateError: ErrorCopy?
    private(set) var isUpdating = false

    init(repository: PlannerRepository) {
        self.repository = repository
    }

    var ids: Set<Int> { Set(list?.items.map(\.playerId) ?? []) }
    func contains(_ playerId: Int) -> Bool { list?.items.contains { $0.playerId == playerId } ?? false }

    func load() async {
        loadError = nil
        do {
            list = try await repository.shortlist()
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }

    func loadIfNeeded() async {
        if list == nil { await load() }
    }

    func toggle(_ playerId: Int) async {
        let on = contains(playerId)
        await change { on ? try await self.repository.removeShortlisted(playerId) : try await self.repository.saveShortlisted(playerId) }
    }

    func setVibe(_ vibe: Bool, for playerId: Int) async {
        await change { try await self.repository.saveShortlisted(playerId, vibe: vibe) }
    }

    func remove(_ playerId: Int) async {
        await change { try await self.repository.removeShortlisted(playerId) }
    }

    func clearError() { updateError = nil }

    /// After "Reset app data": the server's copy is gone too.
    func reset() {
        list = nil
        loadError = nil
        updateError = nil
    }

    private func change(_ work: @escaping () async throws -> PlannerShortlist) async {
        isUpdating = true
        updateError = nil
        defer { isUpdating = false }
        do {
            list = try await work()
        } catch let error as APIError {
            updateError = ErrorCopy(error)
        } catch {}
    }
}
