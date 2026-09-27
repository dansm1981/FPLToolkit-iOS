# FPLToolkit for iPhone

Native SwiftUI companion for FPLToolkit: **your FPL team, watching itself.**
Unofficial and fan-made; not affiliated with the Premier League or Fantasy Premier League.

- **Plan:** `tasks/phase-1.md` in [fpltoolkit-mobile](https://github.com/dansm1981/fpltoolkit-mobile). This repo is Step 2 onwards.
- **API:** `https://www.fpltoolkit.co.uk/api/mobile/v1/`. Contract in `docs/mobile/api-contract.md` (workspace).
- **Design:** `design/visual-development-pack/` (workspace): tokens, `Assets.xcassets` colour sets, `ToolkitTheme.swift`, screen references S01–S29.

## Set up on the Mac

The iOS app is built with Xcode, so this work runs in Claude Code on the Mac, inside the workspace:

```sh
mkdir -p ~/Code && cd ~/Code
git clone https://github.com/dansm1981/fpltoolkit-mobile
cd fpltoolkit-mobile
git clone https://github.com/dansm1981/FPLToolkit-iOS
git clone https://github.com/dansm1981/happy-backend-pal   # reference only
claude                                                     # Claude Code, started in the workspace root
```

Then ask: **"Do tasks/phase-1.md Step 2."**

## Project settings

| Setting | Value |
|---|---|
| Bundle ID | `uk.co.fpltoolkit.app` (Release). Debug builds use `uk.co.fpltoolkit.app.dev` while signing with the free Personal Team, so the real ID stays unregistered until the paid team exists. |
| Display name | FPLToolkit |
| Minimum iOS | 17.0 |
| UI | SwiftUI, `@Observable`, async/await, URLSession, Codable |
| Dependencies | none (ask before adding any) |
| Signing | Personal team (free Apple ID) until the Apple Developer Program membership arrives. Builds last 7 days; push notifications need the paid membership. |

## The Xcode project

Open `FPLToolkit.xcodeproj`. The groups are synchronised with the folders, so a new `.swift` file in `FPLToolkit/` is picked up without editing the project.

```
FPLToolkit/
  App/            FPLToolkitApp (root, tabs), AppModel (connected team, bootstrap, repositories)
  API/            APIClient (the only networking), DTOs (v1 contract, fallback enums)
  Device/         DeviceSession (register once, secret in the Keychain, sync team/time zone, reset)
  Repositories/   CachedEndpoint + ResponseCache (last good response on disk), Resource (screen loader),
                  WatchRepository + WatchStore (the device's watch list, shared by Watch and player sheets)
  Design/         ToolkitTheme (colours from Assets.xcassets, spacing, buttons, pills)
  Components/     InsightCard, "What we checked", skeletons, saved-data banner, error state
  Features/       Onboarding (S01–S03, S24), Today (S05/S06/S23/S27), Team (S07), Player (S08/S09/S29),
                  Watch (S10), Settings (disclosure, change team, reset app data)
  Support/        Formatting, Team ID input parsing, error copy, preview fixtures
FPLToolkitTests/  decoding of every fixture, cache, input parsing, error copy (Swift Testing)
```

- **Run on the iPhone:** in Xcode, pick the phone in the device menu and press ▶. Free signing lasts 7 days, then re-install.
- **Tests:** `xcodebuild test -project FPLToolkit.xcodeproj -scheme FPLToolkit -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Debug launch arguments** (Xcode: Product → Scheme → Edit Scheme → Run → Arguments):
  - `-entryId 71191` opens straight on Today for that team;
  - `-apiBaseURL http://127.0.0.1:9/` points at an unreachable host to see the offline states. Debug builds only.
  - `-forcePushFeatures YES` shows the notification screens (alert offer, permission prompt, settings, alert history) before the server switches push types on. Debug builds only.
- **Deep links:** `fpltoolkit://today`, `team`, `watch`, `watch/alerts`, `player/{id}` (contract §5). Try one in the simulator with `xcrun simctl openurl booted fpltoolkit://player/154`.

## UI tests and screenshots

`FPLToolkitUITests` (its own scheme, so the unit tests stay fast) opens each main screen against the live API, attaches a screenshot, and runs Apple's accessibility audit: VoiceOver labels, contrast, hit areas, Dynamic Type and clipped text. Known false alarms are listed in `ScreenAuditTests.check`.

```sh
xcodebuild test -project FPLToolkit.xcodeproj -scheme FPLToolkitUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO \
  -resultBundlePath /tmp/audit.xcresult
xcrun xcresulttool export attachments --path /tmp/audit.xcresult --output-path /tmp/audit-shots
```

To try screens before their endpoints are deployed, run the backend branch locally and pass its address through `TEST_RUNNER_auditApiBaseURL` (for example `http://127.0.0.1:5199/api/mobile/v1/`). The Research test uses it; the others always use the live API.

For App Store screenshots, run the same tests on the iPhone 17 Pro Max simulator (6.9", 1320 × 2868) after `xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`, with `-auditTeam <Team ID>` passed through `TEST_RUNNER_auditTeam`. See `scripts/app-store-screenshots.sh`.

## Push notifications

Built and waiting for the paid Apple Developer team (see `docs/mobile/push-launch.md` in the workspace):
- `Push/PushManager.swift`: permission, the APNs token (sent to the server as `apnsToken` + `apnsEnvironment`: `sandbox` for Xcode builds, `production` for TestFlight/App Store), foreground presentation, and opening a notification's `deepLink`.
- `Features/Notifications`: the offer card on Today, the primer (S04) and "notifications off" (S28), and settings (S15). `Features/Watch/AlertHistoryView.swift`: alert history (S11).
- Everything appears only for push types `bootstrap.config.features` reports as live.
- `Config/FPLToolkit.entitlements` holds `aps-environment`. It's wired in (`CODE_SIGN_ENTITLEMENTS`) on membership day, with the paid team and the real bundle ID for Debug; the free Personal Team can't sign with it.

## Fixtures

`Fixtures/api-v1/` holds **real responses** from the live API, captured on 26 Sep 2026 (GW5 published, GW6 next) with team names anonymised. Use them for `Codable` decoding tests and SwiftUI previews, so screens can be built without a network.

| File | Shows |
|---|---|
| `bootstrap.json` | current/locked/next gameweek, clubs, config, disclosure, feature flags (all off) |
| `team-71191.json` | a normal published squad with next-fixture xFDR |
| `team-895045-freehit.json` | a squad **reverted after a Free Hit** (`snapshot.freeHitGw = 5`) |
| `team-no-published-team.json` | a new team: `snapshot: null`, `noSnapshotReason: "no_published_team_yet"` |
| `today-71191.json` | **`status: "clear"`**: nothing needs attention, context notes only |
| `today-3612045-attention.json` | **`status: "attention"`**: one player ruled out |
| `today-no-published-team.json` | `status: "unverified"` for a team with no squad yet |
| `player-palmer.json`, `player-haaland.json` | full player sheets: insights, 5 fixtures, market, price prediction, elite, DEFCON |
| `error-invalid-entry.json`, `error-entry-not-found.json` | the v1 error shape (`invalid_entry_id`, `entry_not_found`) |
| `device-register.json`, `device-me.json` | `POST /devices` and `PUT /devices/me` (captured 27 Sep; ID and secret scrubbed, device deleted) |
| `watch-squad.json`, `watch-squad-and-manual.json`, `watch-squad-off.json` | the watch list following the squad; with manual picks (one also in the squad); with the squad switched off (manual watch kept) |
| `players-search-pal.json` | `GET /players/search?q=pal` (from happy-backend-pal#4, before it was merged) |
| `alerts-empty.json`, `error-unauthorized.json` | the alert history before pushes exist; a wrong device secret (401) |

Every response carries `meta.freshness`. Show it; never present stale or unknown data as fresh.
