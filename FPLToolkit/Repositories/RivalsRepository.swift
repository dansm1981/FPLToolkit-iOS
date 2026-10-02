import Foundation
import Observation

/// Rivals (happy-backend-pal#67): managers you've added from your saved mini-leagues, and one
/// rival against you. Device-scoped, like Leagues; every figure is the server's.
struct RivalsRepository: Sendable {
    let session: DeviceSession

    func list() async throws -> RivalsList {
        try await session.send("GET", "rivals", as: RivalsList.self).envelope.data
    }

    /// Everyone in your saved leagues you could add.
    func candidates() async throws -> RivalCandidates {
        try await session.send("GET", "rivals/candidates", as: RivalCandidates.self).envelope.data
    }

    func comparison(_ entryId: Int) async throws -> RivalComparison {
        try await session.send("GET", "rivals/\(entryId)", as: RivalComparison.self).envelope.data
    }

    /// Adds a rival, or changes their nickname or featured state; answers with the list.
    func save(_ entryId: Int, _ patch: RivalPatch = .init()) async throws -> RivalsList {
        try await session.send("PUT", "rivals/\(entryId)", body: patch, as: RivalsList.self).envelope.data
    }

    func remove(_ entryId: Int) async throws -> RivalsList {
        try await session.send("DELETE", "rivals/\(entryId)", as: RivalsList.self).envelope.data
    }
}

/// The device's rivals, shared by Watch, Today, the league screens and the player page.
@MainActor
@Observable
final class RivalsStore {
    let repository: RivalsRepository
    private(set) var list: RivalsList?
    private(set) var loadError: ErrorCopy?
    private(set) var updateError: ErrorCopy?
    /// The rival being added, changed or removed.
    private(set) var changing: Int?

    init(repository: RivalsRepository) {
        self.repository = repository
    }

    var featured: RivalSummary? { list?.featured }

    func contains(_ entryId: Int) -> Bool { list?.contains(entryId) ?? false }

    func load() async {
        loadError = nil
        do {
            list = try await repository.list()
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }

    func loadIfNeeded() async {
        if list == nil { await load() }
    }

    /// True when it was saved.
    @discardableResult
    func save(_ entryId: Int, _ patch: RivalPatch = .init()) async -> Bool {
        changing = entryId
        updateError = nil
        defer { changing = nil }
        do {
            list = try await repository.save(entryId, patch)
            return true
        } catch let error as APIError {
            updateError = ErrorCopy(error)
            return false
        } catch {
            return false
        }
    }

    func remove(_ entryId: Int) async {
        changing = entryId
        updateError = nil
        defer { changing = nil }
        do {
            list = try await repository.remove(entryId)
        } catch let error as APIError {
            updateError = ErrorCopy(error)
        } catch {}
    }

    func clearError() { updateError = nil }

    func reset() {
        list = nil
        loadError = nil
        updateError = nil
    }
}
