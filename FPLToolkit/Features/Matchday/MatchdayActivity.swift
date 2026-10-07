import ActivityKit
import Foundation

/// Starts, updates and ends the Matchday Live Activity (Phase 3, P3-4). The app updates it whenever
/// Matchday refreshes; with the app closed, the server pushes updates every 15 seconds to each
/// activity's push token (tasks/push.md, stage 1; happy-backend-pal#84). A stale date lets iOS
/// show it's out of date if updates stop (never claiming to be live when it isn't).
@MainActor
enum MatchdayActivity {
    nonisolated static let staleAfter: TimeInterval = 5 * 60

    static var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    nonisolated static func running(entryId: Int) -> Activity<MatchdayActivityAttributes>? {
        Activity<MatchdayActivityAttributes>.activities.first {
            $0.attributes.entryId == entryId && $0.activityState == .active
        }
    }

    nonisolated static func state(_ live: LiveTeam, updated: Date?) -> MatchdayActivityAttributes.ContentState {
        .init(
            points: live.total.estimated,
            provisionalBonus: live.total.provisionalBonus,
            playing: live.playing,
            toPlay: live.toPlay,
            headline: live.headline?.text ?? "\(live.playing) playing · \(live.toPlay) to play",
            status: live.status.rawValue,
            updatedAt: updated ?? .now,
            rival: live.rivals?.featured.flatMap { featured in
                live.rivals?.rows.first { $0.entryId == featured.entryId }?.gapText
            }
        )
    }

    static func start(_ live: LiveTeam, entryId: Int, updated: Date?, session: DeviceSession) throws {
        // One at a time: a new gameweek replaces any older one.
        for activity in Activity<MatchdayActivityAttributes>.activities where activity.attributes.entryId == entryId {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let attributes = MatchdayActivityAttributes(entryId: entryId, gameweek: live.gameweek)
        let content = ActivityContent(state: state(live, updated: updated), staleDate: Date.now.addingTimeInterval(staleAfter))
        let activity: Activity<MatchdayActivityAttributes>
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
        } catch {
            // No push token on offer (e.g. a simulator without push): updates from the app only.
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        }
        sendPushTokens(activity, session: session)
    }

    /// Sends the activity's push token to the server whenever Apple issues one, so the server can
    /// update it with the app closed. A replay's activity carries the replay, so the server plays it.
    static func sendPushTokens(_ activity: Activity<MatchdayActivityAttributes>, session: DeviceSession) {
        guard tokenTasks[activity.id] == nil else { return }
        let attributes = activity.attributes
        let replay = LiveReplay.current.flatMap { $0.frozenAt == nil ? $0 : nil }
            .map { LiveActivityRegistration.Replay(id: $0.id, startedAt: $0.startedAt) }
        tokenTasks[activity.id] = Task {
            for await data in activity.pushTokenUpdates {
                let registration = LiveActivityRegistration(
                    entryId: attributes.entryId,
                    gameweek: attributes.gameweek,
                    pushToken: data.map { String(format: "%02x", $0) }.joined(),
                    apnsEnvironment: DeviceSession.apnsEnvironment,
                    replay: replay
                )
                _ = try? await session.send("PUT", "live/activity", body: registration, as: LiveActivityAck.self)
            }
        }
    }

    /// At launch: picks up activities still running from before, so a new token still reaches the
    /// server; and, for Follow my matchdays, sends the push-to-start token and picks up activities
    /// the server starts (Matchday v2 phase 2).
    static func resume(session: DeviceSession) {
        for activity in Activity<MatchdayActivityAttributes>.activities where activity.activityState == .active {
            sendPushTokens(activity, session: session)
        }
        guard startObservers.isEmpty else { return }
        startObservers.append(Task {
            for await activity in Activity<MatchdayActivityAttributes>.activityUpdates {
                sendPushTokens(activity, session: session)
            }
        })
        if #available(iOS 17.2, *) {
            startObservers.append(Task {
                for await data in Activity<MatchdayActivityAttributes>.pushToStartTokenUpdates {
                    let token = data.map { String(format: "%02x", $0) }.joined()
                    _ = try? await session.send("PUT", "devices/me", body: DeviceUpdate(liveStartToken: .some(token)),
                                                as: DeviceInfo.self)
                }
            })
        }
    }

    private static var startObservers: [Task<Void, Never>] = []

    /// Follow my matchdays needs push-to-start (iOS 17.2).
    static var canFollowMatchdays: Bool {
        if #available(iOS 17.2, *) { return isEnabled }
        return false
    }

    private static var tokenTasks: [String: Task<Void, Never>] = [:]

    /// Brings a running activity up to date; ends it an hour after FPL confirms the gameweek.
    nonisolated static func update(_ live: LiveTeam, entryId: Int, updated: Date?) async {
        guard let activity = running(entryId: entryId), activity.attributes.gameweek == live.gameweek else { return }
        let content = ActivityContent(state: state(live, updated: updated), staleDate: Date.now.addingTimeInterval(staleAfter))
        if live.status == .finished {
            await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(60 * 60)))
        } else {
            await activity.update(content)
        }
    }

    static func stop(entryId: Int, session: DeviceSession) async {
        for activity in Activity<MatchdayActivityAttributes>.activities where activity.attributes.entryId == entryId {
            tokenTasks.removeValue(forKey: activity.id)?.cancel()
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        _ = try? await session.send("DELETE", "live/activity", as: LiveActivityAck.self)
    }
}

/// `PUT /live/activity`: a running activity's push token (happy-backend-pal#84).
struct LiveActivityRegistration: Encodable, Sendable {
    struct Replay: Encodable, Sendable {
        let id: String
        let startedAt: Date
    }

    let entryId: Int
    let gameweek: Int
    let pushToken: String
    let apnsEnvironment: String
    let replay: Replay?

    private enum CodingKeys: String, CodingKey { case entryId, gameweek, pushToken, apnsEnvironment, replay }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entryId, forKey: .entryId)
        try c.encode(gameweek, forKey: .gameweek)
        try c.encode(pushToken, forKey: .pushToken)
        try c.encode(apnsEnvironment, forKey: .apnsEnvironment)
        if let replay {
            var r = c.nestedContainer(keyedBy: ReplayKeys.self, forKey: .replay)
            try r.encode(replay.id, forKey: .id)
            try r.encode(replay.startedAt.formatted(.iso8601), forKey: .startedAt)
        }
    }

    private enum ReplayKeys: String, CodingKey { case id, startedAt }
}

/// The server's answer to PUT and DELETE /live/activity.
struct LiveActivityAck: Decodable, Sendable {
    let registered: Bool?
    let ended: Bool?
}
