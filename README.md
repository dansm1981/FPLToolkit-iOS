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
| Bundle ID | `uk.co.fpltoolkit.app` |
| Display name | FPLToolkit |
| Minimum iOS | 17.0 |
| UI | SwiftUI, `@Observable`, async/await, URLSession, Codable |
| Dependencies | none (ask before adding any) |
| Signing | Personal team (free Apple ID) until the Apple Developer Program membership arrives. Builds last 7 days; push notifications need the paid membership. |

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

Every response carries `meta.freshness`. Show it; never present stale or unknown data as fresh.
