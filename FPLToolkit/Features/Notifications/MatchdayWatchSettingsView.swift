import SwiftUI

/// Live matchday (Dan, 2 Oct 2026): who Matchday watches beside your team. Highly owned players
/// are on to begin with; Elite differentials are switched on here. Rivals are the ones you add in
/// Watch → Rivals (they replaced the league-position rivals, Stage B). Saved on the server with
/// the device's prefs (matchday alerts will follow them once push is live) and kept on the phone
/// for the live requests. Changes save straight away.
struct MatchdayWatchSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var prefs = MatchdayWatch.current
    @State private var saving = false
    @State private var error: ErrorCopy?

    private typealias Prefs = DevicePrefs.MatchdayPrefs

    var body: some View {
        List {
            Section {
                toggle("Highly owned players", "Owned by 20% or more of managers, and not in your team", \.highlyOwned)
                toggle("Elite differentials", "Players the Elite 100 own far more than everyone else", \.eliteDifferentials)
            } header: {
                Text("Players")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                NavigationLink {
                    RivalsScreen()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your rivals")
                        Text("Managers you add from your mini-leagues show on Matchday with your contest against them")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
            } header: {
                Text("Rivals")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                toggle("Show them in the Live feed", "Their goals, assists, cards, penalties and bonus, marked with an eye", \.inFeed)
            } footer: {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    if let error { Text("Couldn't save: \(error.message)").foregroundStyle(ToolkitColor.error) }
                    Text("Shown on Matchday under your bench. Matchday alerts, when they arrive, will follow these too.")
                }
            }
            .listRowBackground(ToolkitColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(ToolkitColor.canvas.ignoresSafeArea())
        .navigationTitle("Live matchday")
        .task { await refresh() }
    }

    private func toggle(_ title: String, _ detail: String, _ path: WritableKeyPath<Prefs, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { prefs[keyPath: path] },
            set: { on in
                var next = prefs
                next[keyPath: path] = on
                save(next)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .tint(ToolkitColor.accent)
        .disabled(saving)
    }

    /// The server's copy, when it has one (the phone's copy shows meanwhile).
    private func refresh() async {
        guard let saved = try? await appModel.deviceSession.device().prefs?.matchday else { return }
        MatchdayWatch.remember(saved)
        if !saving { prefs = saved }
    }

    /// Optimistic: shows the change, saves it, and puts it back if saving fails.
    private func save(_ proposed: Prefs) {
        var next = proposed
        // The league-position rivals are retired: a league no longer saved would be refused.
        if next.rivalsLeague != nil {
            next.rivals = false
            next.rivalsLeague = nil
        }
        let previous = prefs
        prefs = next
        error = nil
        saving = true
        Task {
            defer { saving = false }
            do {
                let saved = try await appModel.deviceSession.updatePrefs(.init(matchday: next))
                // A server before happy-backend-pal#66 doesn't keep them; the phone's copy still does.
                let kept = saved.prefs?.matchday ?? next
                prefs = kept
                MatchdayWatch.remember(kept)
            } catch let e as APIError {
                prefs = previous
                error = ErrorCopy(e)
            } catch {
                prefs = previous
            }
        }
    }
}
