import Foundation
import OSLog

/// This install's identity on the server (§6). Registers lazily on the first device-scoped call,
/// re-registers once if the server no longer knows the device, and keeps the server told which
/// team this device follows. Reads (team, today, players) never need it.
actor DeviceSession {
    private static let log = Logger(subsystem: "uk.co.fpltoolkit.app", category: "device")
    private let client: APIClient
    private let store: DeviceCredentialsStore
    private let defaults: UserDefaults
    private var credentials: DeviceCredentials?
    private var registering: Task<DeviceCredentials, Error>?
    /// What was last sent this launch. Kept in memory only, so every launch tells the server once:
    /// a remembered value could drift from the server (a server-side change, a new registration).
    private var lastSync: String?
    /// The team the app last asked for (nil inside means "none"); replayed onto a new registration.
    private var followed: Int??

    private enum Keys {
        static let legacyLastSync = "device.lastSync"
        static let apnsToken = "device.apnsToken"
    }

    /// Xcode builds talk to Apple's sandbox push servers; TestFlight and App Store builds to production.
    static let apnsEnvironment: String = {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }()

    init(client: APIClient, store: DeviceCredentialsStore = DeviceCredentialsStore(), defaults: UserDefaults = .standard) {
        self.client = client
        self.store = store
        self.defaults = defaults
        self.credentials = store.load()
        defaults.removeObject(forKey: Keys.legacyLastSync)
    }

    /// A device-scoped request. On 401 the saved identity is dropped and the call retried once
    /// with a fresh registration (e.g. after "Reset app data" on another build).
    func send<T: Decodable & Sendable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        as type: T.Type
    ) async throws -> Fetched<T> {
        let first = try await ensureRegistered()
        do {
            return try await client.send(method, path, query: query, body: body, authorization: first.authorizationHeader, as: type)
        } catch APIError.server(.unauthorized, _, _) {
            Self.log.notice("device unknown to the server; registering again")
            forget()
            let fresh = try await ensureRegistered()
            // A new registration has no team yet: say which one before retrying, or the retried call
            // (e.g. the watch list) would answer for a device without a squad.
            if path != "devices/me", let followed {
                let (update, signature) = syncUpdate(entryId: followed)
                if (try? await client.send("PUT", "devices/me", body: update, authorization: fresh.authorizationHeader, as: DeviceInfo.self)) != nil {
                    lastSync = signature
                }
            }
            return try await client.send(method, path, query: query, body: body, authorization: fresh.authorizationHeader, as: type)
        }
    }

    /// Tells the server which team this device follows, its time zone and app version.
    /// Skipped when nothing has changed since the last successful sync.
    func sync(entryId: Int?) async {
        followed = .some(entryId)
        // Never register a device just to say "no team" (e.g. straight after Reset app data).
        if entryId == nil && credentials == nil { return }
        let (update, signature) = syncUpdate(entryId: entryId)
        guard lastSync != signature else {
            Self.log.debug("sync skipped, unchanged: \(signature, privacy: .public)")
            return
        }
        // Claimed before the request, so a second caller at launch doesn't send the same update.
        lastSync = signature
        do {
            let info = try await send("PUT", "devices/me", body: update, as: DeviceInfo.self).envelope.data
            Self.log.debug("synced \(signature, privacy: .public); server entry \(String(describing: info.entryId), privacy: .public)")
        } catch {
            // Tried again on the next call, launch or foreground.
            if lastSync == signature { lastSync = nil }
            Self.log.error("sync failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func syncUpdate(entryId: Int?) -> (DeviceUpdate, String) {
        let token = defaults.string(forKey: Keys.apnsToken)
        let update = DeviceUpdate(
            entryId: .some(entryId),
            timeZone: TimeZone.current.identifier,
            appVersion: Self.appVersion,
            apnsToken: .some(token),
            apnsEnvironment: token == nil ? nil : Self.apnsEnvironment)
        let signature = "\(entryId.map(String.init) ?? "none")|\(update.timeZone ?? "")|\(update.appVersion ?? "")|\(token ?? "no-token")"
        return (update, signature)
    }

    /// The push token iOS handed us (hex), or nil when notifications are off. Sent on the next sync,
    /// which happens straight away. The server only accepts it with a team connected.
    func setPushToken(_ token: String?, entryId: Int?) async {
        if defaults.string(forKey: Keys.apnsToken) == token { return }
        if let token { defaults.set(token, forKey: Keys.apnsToken) } else { defaults.removeObject(forKey: Keys.apnsToken) }
        await sync(entryId: entryId)
    }

    /// This device's settings on the server (notification preferences).
    func device() async throws -> DeviceInfo {
        try await send("GET", "devices/me", as: DeviceInfo.self).envelope.data
    }

    /// Changes notification preferences; returns what the server saved.
    func updatePrefs(_ patch: DeviceUpdate.PrefsPatch) async throws -> DeviceInfo {
        try await send("PUT", "devices/me", body: DeviceUpdate(prefs: patch), as: DeviceInfo.self).envelope.data
    }

    /// "Reset app data": deletes the device and everything tied to it on the server, then locally.
    func reset() async throws {
        if let credentials {
            do {
                _ = try await client.send("DELETE", "devices/me", authorization: credentials.authorizationHeader, as: DeleteResult.self)
            } catch APIError.server(.unauthorized, _, _) {
                // Already gone on the server.
            }
        }
        forget()
    }

    private func ensureRegistered() async throws -> DeviceCredentials {
        if let credentials { return credentials }
        if let registering { return try await registering.value }
        let task = Task { [client] in
            let fetched = try await client.send("POST", "devices", as: DeviceRegistration.self)
            return DeviceCredentials(deviceId: fetched.envelope.data.deviceId, secret: fetched.envelope.data.deviceSecret)
        }
        registering = task
        defer { registering = nil }
        let fresh = try await task.value
        store.save(fresh)
        credentials = fresh
        return fresh
    }

    private func forget() {
        store.delete()
        credentials = nil
        lastSync = nil
        defaults.removeObject(forKey: Keys.apnsToken)
    }

    private static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }()
}
