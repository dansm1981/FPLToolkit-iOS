import Foundation
import Observation

/// The device's shortlist (the website's Shortlist), shared by every star, the player menu and the
/// Shortlist screen, so a change in one shows in the others. The server keeps it. Since batch 3 it
/// is also the watch list: stars go through `AppModel.setStarred`, which changes both.
@MainActor
@Observable
final class ShortlistStore {
    private let repository: PlannerRepository
    private(set) var list: PlannerShortlist?
    private(set) var loadError: ErrorCopy?
    /// Why the last change didn't go through.
    private(set) var updateError: ErrorCopy?
    private(set) var isUpdating = false
    /// Changes wait their turn, so the list on screen is always the server's latest answer.
    private var queue: Task<Void, Never>?
    private var queued = 0

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

    /// Adds or removes one player; nothing is sent when the list already says so.
    func set(_ on: Bool, playerId: Int) async {
        await enqueue {
            if self.list == nil { await self.load() }
            guard self.contains(playerId) != on else { return nil }
            return on ? try await self.repository.saveShortlisted(playerId)
                : try await self.repository.removeShortlisted(playerId)
        }
    }

    func remove(_ playerId: Int) async {
        await set(false, playerId: playerId)
    }

    func clearError() { updateError = nil }

    /// After "Reset app data": the server's copy is gone too.
    func reset() {
        list = nil
        loadError = nil
        updateError = nil
    }

    private func enqueue(_ work: @escaping @MainActor () async throws -> PlannerShortlist?) async {
        let earlier = queue
        queued += 1
        isUpdating = true
        let task = Task { @MainActor in
            await earlier?.value
            self.updateError = nil
            do {
                if let updated = try await work() { self.list = updated }
            } catch let error as APIError {
                self.updateError = ErrorCopy(error)
            } catch {}
        }
        queue = task
        await task.value
        queued -= 1
        if queued == 0 {
            isUpdating = false
            queue = nil
        }
    }
}
