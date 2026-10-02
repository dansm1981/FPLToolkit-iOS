import SwiftUI

/// Settings: the connected team, Data & sources, "Change team", and About (the unofficial
/// disclosure and who makes the app).
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    /// nil while exploring without a team.
    let entryId: Int?
    @State private var addingTeam = false
    @State private var confirmingChange = false
    @State private var confirmingReset = false
    @State private var resetError: ErrorCopy?
    @State private var resetting = false

    var body: some View {
        NavigationStack {
            List {
                Section("Your team") {
                    if let entryId {
                        LabeledContent("Team ID", value: String(entryId))
                        NavigationLink {
                            DataSourcesView(entryId: entryId)
                        } label: {
                            Label("Data & sources", systemImage: "icloud")
                        }
                        NavigationLink {
                            MatchdayWatchSettingsView()
                        } label: {
                            Label("Live matchday", systemImage: "eye")
                        }
                        Button("Change team", role: .destructive) {
                            confirmingChange = true
                        }
                    } else {
                        Text("No team added. You're exploring: watch any player and open their page.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                        Button("Add my FPL team") { addingTeam = true }
                    }
                }
                .listRowBackground(ToolkitColor.surface)

                if appModel.anyPushFeature {
                    Section {
                        NavigationLink {
                            NotificationSettingsView()
                        } label: {
                            Label("Notifications", systemImage: "bell")
                        }
                    }
                    .listRowBackground(ToolkitColor.surface)
                }

                Section {
                    Text(appModel.disclosure)
                        .font(.callout)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    Text(Self.company)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    Link("Help & support", destination: webURL("app/support"))
                    Link("Privacy policy", destination: webURL("app/privacy"))
                    Link("Open fpltoolkit.co.uk", destination: webURL(""))
                } header: {
                    Text("About")
                }
                .listRowBackground(ToolkitColor.surface)

                Section {
                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        HStack {
                            Text("Reset app data")
                            if resetting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(resetting)
                } footer: {
                    Text(resetError.map { "Couldn't reset: \($0.message)" }
                         ?? "Deletes this device's shortlist, drafts, leagues and settings from our server, and everything saved on this phone.")
                }
                .listRowBackground(ToolkitColor.surface)

                Section {
                    LabeledContent("Version", value: Self.version)
                }
                .listRowBackground(ToolkitColor.surface)

                #if DEBUG
                if entryId != nil {
                    Section("Developer") {
                        NavigationLink {
                            LiveReplayPicker {
                                dismiss()
                                // After the sheet has gone, so the full-screen Matchday can open.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    appModel.router.showingMatchday = true
                                }
                            }
                        } label: {
                            Label("Live matchday replay", systemImage: "play.circle")
                        }
                    }
                    .listRowBackground(ToolkitColor.surface)
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $addingTeam) { AddTeamSheet() }
            .confirmationDialog("Change team?", isPresented: $confirmingChange, titleVisibility: .visible) {
                Button("Change team", role: .destructive) {
                    dismiss()
                    appModel.disconnect()
                }
            } message: {
                Text("You'll go back to the start and can enter a different Team ID.")
            }
            .confirmationDialog("Reset app data?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset app data", role: .destructive) {
                    Task {
                        resetting = true
                        defer { resetting = false }
                        do {
                            try await appModel.resetAppData()
                            dismiss()
                        } catch let error as APIError {
                            resetError = ErrorCopy(error)
                        } catch {}
                    }
                }
            } message: {
                Text("This removes your team, your shortlist, your drafts, your leagues and your settings. It can't be undone.")
            }
        }
    }

    private func webURL(_ path: String) -> URL {
        let base = URL(string: appModel.bootstrap?.value.config.webBaseUrl ?? "https://www.fpltoolkit.co.uk")
            ?? URL(string: "https://www.fpltoolkit.co.uk")!
        return path.isEmpty ? base : base.appending(path: path)
    }

    /// Who makes the app (Companies House: Plainfield Works Limited, 17490511).
    static let company = "FPLToolkit is made by Plainfield Works Ltd, registered in England and Wales, company number 17490511."

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// The person icon at the top right of each tab, opening Settings.
private struct SettingsButton: ViewModifier {
    let entryId: Int?
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showing = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showing) {
                SettingsView(entryId: entryId)
            }
    }
}

extension View {
    func settingsButton(entryId: Int?) -> some View {
        modifier(SettingsButton(entryId: entryId))
    }
}
