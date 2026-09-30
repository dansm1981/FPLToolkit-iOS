import Foundation
import Observation

/// The watch list shared by the Watch tab and every player sheet, so a change in one shows in the other.
@MainActor
@Observable
final class WatchStore {
    let resource: Resource<Watch>
    private let repository: any WatchService
    /// Why the last change didn't go through, shown until the next attempt.
    private(set) var updateError: ErrorCopy?
    /// True while changes are waiting or being sent.
    private(set) var isUpdating = false

    /// Runs before the first load: tells the server which team this device follows, so the
    /// squad in the watch list is never the previous team's.
    private let prepare: @MainActor () async -> Void

    /// Changes wait their turn, so quick taps on several players all go through, each built on
    /// the list the one before it left (batch 3: a second tap used to undo the first).
    private var queue: Task<Void, Never>?
    private var queued = 0
    /// Taps not yet confirmed by the server, shown straight away: player → watched, with a
    /// number so an older reply doesn't clear a newer tap.
    private var pending: [Int: (watched: Bool, tap: Int)] = [:]
    private var taps = 0

    init(repository: some WatchService, prepare: @escaping @MainActor () async -> Void = {}) {
        self.repository = repository
        self.resource = Resource(repository)
        self.prepare = prepare
    }

    var watch: Watch? { resource.loaded?.value }

    /// Watched by hand, counting taps still on their way to the server.
    func isManual(_ playerId: Int) -> Bool {
        pending[playerId]?.watched ?? watch?.isManual(playerId) ?? false
    }

    /// Loads once, and again if the last load was cut off and left only the saved copy on screen.
    func loadIfNeeded() async {
        let interrupted = resource.loaded?.isFromCache == true && !resource.isRefreshing && resource.refreshError == nil
        guard resource.isInitial || interrupted else { return }
        await prepare()
        await resource.load()
    }

    /// Reloads when the list on screen is more than a minute old (back to the tab or the app).
    func refreshIfStale() async {
        if resource.isInitial { return await loadIfNeeded() }
        guard !isUpdating else { return }
        await resource.refreshIfStale()
    }

    func setWatched(_ watched: Bool, playerId: Int) async {
        taps += 1
        let tap = taps
        pending[playerId] = (watched, tap)
        await enqueue { manual in
            var next = manual.filter { $0 != playerId }
            if watched { next.append(playerId) }
            return next == manual ? nil : (next, nil)
        }
        if pending[playerId]?.tap == tap { pending[playerId] = nil }
    }

    /// Adds several players at once (the shortlist's "Watch all"), keeping the ones already watched.
    func watchAll(_ playerIds: [Int]) async {
        await enqueue { manual in
            let new = playerIds.filter { !manual.contains($0) }
            return new.isEmpty ? nil : (manual + new, nil)
        }
    }

    func setAutoTrackSquad(_ on: Bool) async {
        await enqueue { manual in (manual, on) }
    }

    /// Runs `change` after every earlier one, on the latest list. `change` returns the new manual
    /// list (and squad setting), or nil when there's nothing to send.
    private func enqueue(_ change: @escaping @MainActor ([Int]) -> (manual: [Int], autoTrack: Bool?)?) async {
        let earlier = queue
        queued += 1
        isUpdating = true
        let task = Task { @MainActor in
            await earlier?.value
            await self.send(change)
        }
        queue = task
        await task.value
        queued -= 1
        if queued == 0 {
            isUpdating = false
            queue = nil
        }
    }

    private func send(_ change: @MainActor ([Int]) -> (manual: [Int], autoTrack: Bool?)?) async {
        updateError = nil
        // A tap before the list arrived waits for it rather than doing nothing.
        if watch == nil { await loadIfNeeded() }
        guard let watch else {
            updateError = resource.refreshError ?? {
                if case .failed(let copy) = resource.phase { return copy }
                return ErrorCopy(title: "Your watch list hasn't loaded",
                                 message: "Check your connection and try again.", canRetry: true)
            }()
            return
        }
        guard let next = change(watch.manual) else { return }
        do {
            resource.replace(with: try await repository.update(manual: next.manual, autoTrackSquad: next.autoTrack))
        } catch let error as APIError {
            updateError = ErrorCopy(error)
        } catch {}
    }
}
