import Foundation
import Testing
@testable import FPLToolkit

/// Device and watch responses captured from the live API on 27 Sep 2026 (IDs and secret scrubbed).
struct DeviceTests {
    @Test func registration() throws {
        let data = try fixture("device-register", as: DeviceRegistration.self)
        #expect(data.deviceSecret.count == 43)
        #expect(UUID(uuidString: data.deviceId) != nil)
    }

    @Test func deviceInfo() throws {
        let info = try fixture("device-me", as: DeviceInfo.self)
        #expect(info.entryId == 71191)
        #expect(info.apnsRegistered == false)
        #expect(info.timeZone == "Europe/London")
    }

    @Test func watchFollowingSquad() throws {
        let watch = try fixture("watch-squad", as: Watch.self)
        #expect(watch.autoTrackSquad)
        #expect(watch.manual.isEmpty)
        #expect(watch.squad?.playerIds.count == 15)
        #expect(watch.effective.count == 15)
        #expect(watch.effective.allSatisfy { $0.reasons == [.squad] })
        for item in watch.effective { #expect(watch.player(item.playerId) != nil) }
    }

    @Test func manualWatchOfASquadPlayerKeepsBothReasons() throws {
        let watch = try fixture("watch-squad-and-manual", as: Watch.self)
        #expect(watch.manual == [154, 1])
        #expect(watch.reasons(for: 1) == [.squad, .manual])
        #expect(watch.isManual(154))
    }

    @Test func turningOffTheSquadKeepsManualWatches() throws {
        let watch = try fixture("watch-squad-off", as: Watch.self)
        #expect(!watch.autoTrackSquad)
        #expect(watch.effective.map(\.playerId) == [154])
        #expect(watch.reasons(for: 154) == [.manual])
    }

    @Test func emptyAlerts() throws {
        struct Alerts: Decodable, Sendable { let alerts: [String] }
        #expect(try fixture("alerts-empty", as: Alerts.self).alerts.isEmpty)
    }

    @Test func unauthorizedError() throws {
        let body = try APIClient.decode(ErrorEnvelope.self, from: data("error-unauthorized"))
        #expect(body.error.code == .unauthorized)
    }

    @Test func deviceUpdateSendsExplicitNullForNoTeam() throws {
        let none = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DeviceUpdate(entryId: .some(nil)))) as? [String: Any]
        #expect(none?.keys.contains("entryId") == true)
        #expect(none?["entryId"] is NSNull)

        let omitted = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DeviceUpdate(timeZone: "Europe/London"))) as? [String: Any]
        #expect(omitted?.keys.contains("entryId") == false)
        #expect(omitted?["timeZone"] as? String == "Europe/London")
    }

    @Test func watchUpdateOmitsTheToggleUnlessSet() throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WatchUpdate(manual: [1, 2], autoTrackSquad: nil))) as? [String: Any]
        #expect(body?["manual"] as? [Int] == [1, 2])
        #expect(body?.keys.contains("autoTrackSquad") == false)
    }

    @Test func credentialsRoundTripThroughTheKeychain() {
        let store = DeviceCredentialsStore(service: "uk.co.fpltoolkit.tests.\(UUID().uuidString)")
        #expect(store.load() == nil)
        let credentials = DeviceCredentials(deviceId: "00000000-0000-4000-8000-000000000001", secret: String(repeating: "a", count: 43))
        #expect(store.save(credentials))
        #expect(store.load() == credentials)
        #expect(credentials.authorizationHeader == "Device 00000000-0000-4000-8000-000000000001.\(String(repeating: "a", count: 43))")
        store.delete()
        #expect(store.load() == nil)
    }

    private func fixture<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
        try APIClient.decode(Envelope<T>.self, from: data(name)).data
    }

    private func data(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: DeviceBundleToken.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

private final class DeviceBundleToken {}

struct DeepLinkTests {
    @Test(arguments: [
        ("fpltoolkit://today", DeepLink.today),
        ("fpltoolkit://team", DeepLink.team),
        ("fpltoolkit://watch", DeepLink.watch),
        ("fpltoolkit://watch/alerts", DeepLink.alerts),
        ("fpltoolkit://player/154", DeepLink.player(154)),
        ("fpltoolkit://player/593?insight=593-availability-Availability%3Agw5", DeepLink.player(593)),
        ("fpltoolkit://player/abc", DeepLink.today),
        ("fpltoolkit://something-new", DeepLink.today),
    ])
    func parses(url: String, expected: DeepLink) throws {
        #expect(DeepLink(url: try #require(URL(string: url))) == expected)
    }

    @Test func ignoresOtherSchemes() throws {
        #expect(DeepLink(url: try #require(URL(string: "https://www.fpltoolkit.co.uk/players/cole-palmer"))) == nil)
    }
}

struct SearchTests {
    @Test func searchResultsDecodeInOrder() throws {
        let url = try #require(Bundle(for: SearchBundleToken.self).url(forResource: "players-search-pal", withExtension: "json"))
        let result = try APIClient.decode(Envelope<PlayerSearchResult>.self, from: Data(contentsOf: url)).data
        #expect(result.query == "pal")
        #expect(result.players.first?.webName == "Palmer")
        #expect(result.players.count <= 20)
    }
}

private final class SearchBundleToken {}
