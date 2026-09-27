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

    /// §12.6 rows, captured live for team 22615 on 27 Sep 2026: most urgent first.
    @Test func watchRowsCarryNotePriceAndOwnership() throws {
        let watch = try fixture("watch-rows-22615", as: Watch.self)
        let first = try #require(watch.effective.first)
        #expect(first.needsAttention == false)
        #expect(first.topInsight?.tone == .warn)
        #expect(first.price?.progressPct == -10)
        #expect(first.price?.tonightPct == -10.7)
        #expect(first.ownershipChange7d == -1)
        let severities = watch.effective.map { $0.topInsight?.severity ?? -1 }
        #expect(severities == severities.sorted(by: >))
        #expect(watch.effective.last?.topInsight == nil)
        #expect(watch.effective.contains { $0.reasons == [.manual] })
    }

    @Test func olderWatchResponsesStillDecode() throws {
        let watch = try fixture("watch-squad", as: Watch.self)
        #expect(watch.effective.allSatisfy { $0.needsAttention == nil && $0.topInsight == nil && $0.price == nil })
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
        ("fpltoolkit://research", DeepLink.research),
        ("fpltoolkit://watch", DeepLink.watch),
        ("fpltoolkit://watch/alerts", DeepLink.alerts),
        ("fpltoolkit://player/154", DeepLink.player(154)),
        ("fpltoolkit://player/593?insight=593-availability-Availability%3Agw5", DeepLink.player(593)),
        ("fpltoolkit://player/154?event=avail%3A154%3Ad%3A50%3A1790374210", DeepLink.player(154, event: "avail:154:d:50:1790374210")),
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

struct PushContractTests {
    @Test func devicePrefsDecodeFromTheLiveShape() throws {
        let url = try #require(Bundle(for: PushBundleToken.self).url(forResource: "device-me", withExtension: "json"))
        let info = try APIClient.decode(Envelope<DeviceInfo>.self, from: Data(contentsOf: url)).data
        let prefs = try #require(info.prefs)
        #expect(prefs.notifications.price)
        #expect(prefs.notifications.deadline3h)
        #expect(!prefs.notifications.deadline24h)
        #expect(prefs.quietHours == .init(start: "22:30", end: "07:30"))
    }

    @Test func pushTokenAndPrefsEncode() throws {
        let clear = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DeviceUpdate(apnsToken: .some(nil)))) as? [String: Any]
        #expect(clear?["apnsToken"] is NSNull)
        let set = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            DeviceUpdate(apnsToken: .some("abcd"), apnsEnvironment: "sandbox",
                         prefs: .init(notifications: nil, quietHours: .init(start: "23:00", end: "07:00"))))) as? [String: Any]
        #expect(set?["apnsToken"] as? String == "abcd")
        #expect(set?["apnsEnvironment"] as? String == "sandbox")
        let prefs = set?["prefs"] as? [String: Any]
        #expect(prefs?.keys.contains("autoTrackSquad") == false)
        #expect((prefs?["quietHours"] as? [String: String])?["start"] == "23:00")
    }

    @Test func alertHistoryDecodesAndToleratesNewValues() throws {
        let json = """
        {"data":{"alerts":[
          {"eventKey":"price:417:2026-09-27:up","category":"price","playerId":417,"gameweek":null,
           "title":"Hall may rise tonight","body":"104% of the rise threshold. A projection, not a guarantee.",
           "status":"sent","reason":null,"detectedAt":"2026-09-27T17:00:00.000Z","sentAt":"2026-09-27T17:00:03.000Z",
           "expiresAt":"2026-09-28T00:30:00.000Z","deepLink":"fpltoolkit://player/417?event=price%3A417%3A2026-09-27%3Aup"},
          {"eventKey":"moved:1:2026-09-28","category":"moved","playerId":1,"gameweek":null,"title":"t","body":"b",
           "status":"archived","reason":"something_new","detectedAt":"2026-09-28T07:30:00Z","sentAt":null,
           "expiresAt":"2026-09-28T12:00:00Z","deepLink":"fpltoolkit://player/1"}
        ]},"meta":{"apiVersion":"1","generatedAt":"2026-09-28T08:00:00Z","freshness":[]}}
        """
        let history = try APIClient.decode(Envelope<AlertHistory>.self, from: Data(json.utf8)).data
        #expect(history.alerts.count == 2)
        #expect(history.alerts[0].category == .price)
        #expect(history.alerts[0].status == .sent)
        #expect(history.alerts[1].category == .other)
        #expect(history.alerts[1].status == .unknown)
        #expect(AlertRow.statusText(history.alerts[0]) == "Sent")
    }

    @Test func notSentReasonsReadPlainly() {
        func alert(_ status: AlertItem.Status, _ reason: String?) -> AlertItem {
            AlertItem(eventKey: "k", category: .availability, playerId: 1, gameweek: nil, title: "t", body: "b",
                      status: status, reason: reason, detectedAt: .now, sentAt: nil, expiresAt: .now, deepLink: "fpltoolkit://today")
        }
        #expect(AlertRow.statusText(alert(.suppressed, "quiet_hours")) == "Not sent: found during quiet hours")
        #expect(AlertRow.statusText(alert(.suppressed, "daily_cap")) == "Not sent: daily alert limit reached")
        #expect(AlertRow.statusText(alert(.deferred, "quiet_hours")) == "Held until quiet hours end")
        #expect(AlertRow.statusText(alert(.suppressed, "notifications_off")) == "Not sent: notifications are off on this iPhone")
        #expect(AlertRow.statusText(alert(.superseded, "status_changed")).hasPrefix("Not sent: the status changed back"))
    }
}

private final class PushBundleToken {}
