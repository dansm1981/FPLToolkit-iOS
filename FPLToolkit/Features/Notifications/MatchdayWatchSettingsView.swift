import SwiftUI

/// Live matchday (Dan, 2 Oct 2026): who Matchday watches beside your team. Highly owned players
/// are on to begin with; Elite differentials and mini-league rivals are switched on here, with how
/// many rivals above and below you and whether to add the leader. Saved on the server with the
/// device's prefs (matchday alerts will follow them once push is live) and kept on the phone for
/// the live requests. Changes save straight away.
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
                toggle("Mini-league rivals", "Their live score, captain and the players they have that you don't", \.rivals) { next in
                    if next.rivals, !leagues.contains(where: { $0.id == next.rivalsLeague }) {
                        next.rivalsLeague = leagues.first?.id
                    }
                }
                if prefs.rivals {
                    rivalsSettings
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
        .task {
            async let leagues: Void = appModel.leagues.loadIfNeeded()
            await refresh()
            await leagues
        }
    }

    /// The device's saved mini-leagues (the Elite 100 has its own group).
    private var leagues: [LeagueList.League] {
        appModel.leagues.list?.leagues.filter { !$0.isElite } ?? []
    }

    @ViewBuilder
    private var rivalsSettings: some View {
        if leagues.isEmpty {
            Text(appModel.leagues.list == nil ? "Loading your leagues…" : "Add a mini-league from Team → Your leagues to follow its rivals here.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
        } else {
            Picker("League", selection: Binding<Int?>(
                get: { prefs.rivalsLeague },
                set: { id in
                    var next = prefs
                    next.rivalsLeague = id
                    save(next)
                }
            )) {
                if !leagues.contains(where: { $0.id == prefs.rivalsLeague }) {
                    Text("Choose a league").tag(Int?.none)
                }
                ForEach(leagues) { league in
                    Text(league.name).tag(Int?.some(league.id))
                }
            }
            .disabled(saving)
        }
        stepper("Managers above you", \.rivalsAbove)
        stepper("Managers below you", \.rivalsBelow)
        toggle("Include the league leader", "Wherever you are in the table", \.rivalsLeader)
    }

    private func stepper(_ title: String, _ path: WritableKeyPath<Prefs, Int>) -> some View {
        let value = prefs[keyPath: path]
        return Stepper(value: Binding(
            get: { value },
            set: { n in
                var next = prefs
                next[keyPath: path] = n
                save(next)
            }
        ), in: 0...Prefs.maxEachSide) {
            Text("\(title): \(value)")
                .monospacedDigit()
        }
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .disabled(saving)
    }

    /// `adjust` makes any follow-on change before saving (a league for the rivals).
    private func toggle(_ title: String, _ detail: String, _ path: WritableKeyPath<Prefs, Bool>,
                        adjust: ((inout Prefs) -> Void)? = nil) -> some View {
        Toggle(isOn: Binding(
            get: { prefs[keyPath: path] },
            set: { on in
                var next = prefs
                next[keyPath: path] = on
                adjust?(&next)
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
        // A league no longer saved on the device would be refused.
        if appModel.leagues.list != nil, let league = next.rivalsLeague, !leagues.contains(where: { $0.id == league }) {
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
