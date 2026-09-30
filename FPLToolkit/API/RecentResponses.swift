import Foundation
import os

/// GET responses from this session, kept in memory for as long as the server's Cache-Control
/// max-age allows (15 seconds for live, a minute for your team, up to 5 minutes for research), so
/// coming back to a screen doesn't ask the server again (batch 3). Pull to refresh skips it;
/// "no-store" answers (the device's own lists and drafts) are never kept; anything the app sends
/// (POST, PUT, DELETE) clears it all, so nothing it changed is shown out of date.
final class RecentResponses: Sendable {
    static let shared = RecentResponses()

    private struct Entry: Sendable {
        let data: Data
        let until: Date
    }

    private struct State: Sendable {
        var entries: [String: Entry] = [:]
        var bytes = 0
    }

    private static let maxBytes = 20_000_000
    private static let longest: TimeInterval = 300
    private let state = OSAllocatedUnfairLock(initialState: State())

    func fresh(_ key: String, now: Date = .now) -> Data? {
        state.withLock { state in
            guard let entry = state.entries[key], entry.until > now else { return nil }
            return entry.data
        }
    }

    func keep(_ data: Data, for key: String, cacheControl: String?, now: Date = .now) {
        guard let seconds = Self.maxAge(cacheControl), seconds > 0 else { return }
        state.withLock { state in
            if let old = state.entries[key] { state.bytes -= old.data.count }
            if state.bytes + data.count > Self.maxBytes { state = State() }
            state.entries[key] = Entry(data: data, until: now.addingTimeInterval(min(seconds, Self.longest)))
            state.bytes += data.count
        }
    }

    func removeAll() {
        state.withLock { $0 = State() }
    }

    /// The max-age in a Cache-Control header; nil when it says no-store or no-cache, or has none.
    static func maxAge(_ header: String?) -> TimeInterval? {
        guard let header else { return nil }
        let parts = header.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.contains("no-store") || parts.contains("no-cache") { return nil }
        guard let maxAge = parts.first(where: { $0.hasPrefix("max-age=") }) else { return nil }
        return TimeInterval(maxAge.dropFirst("max-age=".count))
    }
}
