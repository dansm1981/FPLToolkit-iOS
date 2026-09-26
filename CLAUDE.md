# FPLToolkit-iOS

The workspace `CLAUDE.md` (one folder up, in fpltoolkit-mobile) holds the project rules; they all apply here. iOS-specific rules:

- **The app talks only to `/api/mobile/v1/*`.** Views never build requests: `APIClient` → repositories → `@Observable` models → views.
- **No FPL rules in Swift.** Urgency, severity, wording, xFDR and Free Hit handling all come from the API. If a screen needs a judgement the API doesn't give, change the backend.
- **Decode exactly the v1 contract.** Tolerate unknown fields; map unknown enum values to a fallback. Keep the `Fixtures/api-v1` decoding tests passing.
- **Honest freshness:** show `meta.freshness`. Only say "You're in good shape" when `status == "clear"`.
- **No player photos, club badges, or Premier League/FPL branding.** Show the unofficial disclosure on Welcome and in Settings.
- **No secrets in the bundle.** Ask before adding any dependency.
- **Build and run on Dan's iPhone** before calling anything done. Also test Dynamic Type (large sizes) and VoiceOver on new screens.
