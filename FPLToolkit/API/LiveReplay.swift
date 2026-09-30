import Foundation

/// A live matchday replay (developer tool, 30 Sep 2026): a past gameweek's live data, played
/// through the live screens in about 20 minutes from the server's log (`GET /live/replays`,
/// happy-backend-pal#58). While one runs, live requests ask for its current moment; the server
/// answers through the same code as a real matchday.
struct LiveReplay: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let durationSeconds: Int
    let startedAt: Date
    /// UI tests: a fixed number of seconds in, instead of the clock.
    var frozenAt: Int?

    static let storageKey = "live.replay"
    /// A replay stops counting as running this long after it ends.
    private static let grace: TimeInterval = 120

    var elapsedSeconds: Int { frozenAt ?? max(0, Int(Date.now.timeIntervalSince(startedAt))) }
    var remainingSeconds: Int { max(0, durationSeconds - elapsedSeconds) }
    var isOver: Bool { frozenAt == nil && Double(elapsedSeconds) > Double(durationSeconds) + Self.grace }

    nonisolated var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "replay", value: id), URLQueryItem(name: "t", value: String(elapsedSeconds))]
    }

    /// The replay running now, if any. Launch arguments `-liveReplayId <id> -liveReplayFreeze
    /// <seconds>` give a frozen one (UI tests); otherwise the one started in Settings, until it ends.
    nonisolated static var current: LiveReplay? {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "liveReplayId"), !id.isEmpty {
            return LiveReplay(id: id, label: "Replay", durationSeconds: 1200, startedAt: .distantPast,
                              frozenAt: defaults.integer(forKey: "liveReplayFreeze"))
        }
        guard let data = defaults.data(forKey: storageKey),
              let replay = try? JSONDecoder().decode(LiveReplay.self, from: data), !replay.isOver
        else { return nil }
        return replay
    }

    static func start(id: String, label: String, durationSeconds: Int) {
        let replay = LiveReplay(id: id, label: label, durationSeconds: durationSeconds, startedAt: .now)
        if let data = try? JSONEncoder().encode(replay) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func end() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

/// `GET /live/replays`: the past matchdays the server can replay.
struct LiveReplays: Decodable, Sendable {
    struct Item: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let gameweek: Int
        let label: String
        let durationSeconds: Int
        /// How much faster than the original it plays.
        let speed: Double
        let from: Date
        let to: Date
    }

    let replays: [Item]
}
