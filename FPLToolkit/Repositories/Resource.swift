import Foundation
import Observation

/// Loads one endpoint for a screen: the saved copy first (labelled), then the network.
/// A transient failure keeps the saved copy on screen; skeletons are only for "nothing known yet".
@MainActor
@Observable
final class Resource<T: Decodable & Sendable> {
    enum Phase {
        case loading
        case loaded(Loaded<T>)
        case failed(ErrorCopy)
    }

    private(set) var phase: Phase = .loading
    private(set) var isRefreshing = false
    /// Why the latest refresh failed while older data stays on screen.
    private(set) var refreshError: ErrorCopy?
    /// When the network last answered (not the saved copy).
    private(set) var fetchedAt: Date?

    private let endpoint: any LoadableEndpoint<T>

    init(_ endpoint: some LoadableEndpoint<T>) {
        self.endpoint = endpoint
    }

    /// Nothing loaded or attempted yet.
    var isInitial: Bool {
        if case .loading = phase { return !isRefreshing }
        return false
    }

    var loaded: Loaded<T>? {
        if case .loaded(let loaded) = phase { return loaded }
        return nil
    }

    /// True only when what's on screen came from the network just now.
    var isCurrent: Bool {
        guard let loaded else { return false }
        return !loaded.isFromCache && refreshError == nil
    }

    func load(bypassCache: Bool = false) async {
        if case .loading = phase, let cached = endpoint.cached() {
            phase = .loaded(cached)
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            phase = .loaded(try await endpoint.fetch(bypassCache: bypassCache))
            refreshError = nil
            fetchedAt = .now
        } catch let error as APIError {
            let copy = ErrorCopy(error)
            if loaded != nil && copy.canRetry {
                refreshError = copy
            } else {
                phase = .failed(copy)
            }
        } catch {
            // Cancelled (the view went away): leave the state as it was.
        }
    }

    /// Loads again when what's on screen is older than `maxAge` or came from the saved copy, e.g.
    /// on coming back to a tab or the app (batch 3). Screens loaded once and then never refreshed.
    func refreshIfStale(maxAge: TimeInterval = 60) async {
        guard !isRefreshing else { return }
        if let fetchedAt, refreshError == nil, Date.now.timeIntervalSince(fetchedAt) < maxAge { return }
        await load()
    }

    /// Shows a response obtained another way (e.g. the result of a PUT).
    func replace(with loaded: Loaded<T>) {
        phase = .loaded(loaded)
        refreshError = nil
        fetchedAt = .now
    }

    func retry() async {
        if case .failed = phase { phase = .loading }
        await load(bypassCache: true)
    }
}
