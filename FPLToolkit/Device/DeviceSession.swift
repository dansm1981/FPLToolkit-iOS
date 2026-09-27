import Foundation

/// This install's identity on the server (§6). Registers lazily on the first device-scoped call,
/// re-registers once if the server no longer knows the device, and keeps the server told which
/// team this device follows. Reads (team, today, players) never need it.
actor DeviceSession {
    private let client: APIClient
    private let store: DeviceCredentialsStore
    private let defaults: UserDefaults
    private var credentials: DeviceCredentials?
    private var registering: Task<DeviceCredentials, Error>?

    private enum Keys {
        static let lastSync = "device.lastSync"
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
    }

    /// A device-scoped request. On 401 the saved identity is dropped and the call retried once
    /// with a fresh registration (e.g. after "Reset app data" on another build).
    func send<T: Decodable & Sendable>(
        _ method: String,
        _ path: String,
        body: (any Encodable & Sendable)? = nil,
        as type: T.Type
    ) async throws -> Fetched<T> {
        let first = try await ensureRegistered()
        do {
            return try await client.send(method, path, body: body, authorization: first.authorizationHeader, as: type)
        } catch APIError.server(.unauthorized, _, _) {
            forget()
            let fresh = try await ensureRegistered()
            return try await client.send(method, path, body: body, authorization: fresh.authorizationHeader, as: type)
        }
    }

    /// Tells the server which team this device follows, its time zone and app version.
    /// Skipped when nothing has changed since the last successful sync.
    func sync(entryId: Int?) async {
        // Never register a device just to say "no team" (e.g. straight after Reset app data).
        if entryId == nil && credentials == nil { return }
        let token = defaults.string(forKey: Keys.apnsToken)
        let update = DeviceUpdate(
            entryId: .some(entryId),
            timeZone: TimeZone.current.identifier,
            appVersion: Self.appVersion,
            apnsToken: .some(token),
            apnsEnvironment: token == nil ? nil : Self.apnsEnvironment)
        let signature = "\(entryId.map(String.init) ?? "none")|\(update.timeZone ?? "")|\(update.appVersion ?? "")|\(token ?? "no-token")"
        guard credentials == nil || defaults.string(forKey: Keys.lastSync) != signature else { return }
        do {
            _ = try await send("PUT", "devices/me", body: update, as: DeviceInfo.self)
            defaults.set(signature, forKey: Keys.lastSync)
        } catch {
            // Tried again on the next launch or foreground.
        }
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
        defaults.removeObject(forKey: Keys.lastSync)
        return fresh
    }

    private func forget() {
        store.delete()
        credentials = nil
        defaults.removeObject(forKey: Keys.lastSync)
        defaults.removeObject(forKey: Keys.apnsToken)
    }

    private static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }()
}
