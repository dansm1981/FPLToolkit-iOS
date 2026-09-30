import SwiftUI

/// Today while exploring without a team: the next deadline, the players being watched, and an
/// invitation to add a team. Nothing here is invented: it's the real deadline and real players.
struct ExploreTodayView: View {
    @Environment(AppModel.self) private var appModel
    @State private var addingTeam = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                if let next = appModel.bootstrap?.value.gameweek.next {
                    DeadlineLine(next: next)
                }
                AddTeamCard { addingTeam = true }
                if let store = appModel.watch {
                    WatchedSummary(store: store)
                }
                Text(appModel.disclosure)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .padding(.top, ToolkitSpace.sm)
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Today")
        // In the top bar, as on Today (Dan, 30 Sep).
        .navigationBarTitleDisplayMode(.inline)
        .settingsButton(entryId: nil)
        .sheet(isPresented: $addingTeam) { AddTeamSheet() }
    }
}

/// The Team tab (and similar) with no team yet.
struct NoTeamView: View {
    let title: String
    let message: String
    @State private var addingTeam = false

    var body: some View {
        ScrollView {
            AddTeamCard(message: message) { addingTeam = true }
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle(title)
        // In the top bar, as on Today (Dan, 30 Sep).
        .navigationBarTitleDisplayMode(.inline)
        .settingsButton(entryId: nil)
        .sheet(isPresented: $addingTeam) { AddTeamSheet() }
    }
}

struct AddTeamCard: View {
    var message = "Add your team to have your squad checked for injuries, price moves and your deadline. You only need your public Team ID, never your FPL password."
    let add: () -> Void

    var body: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                Label("Add your FPL team", systemImage: "tshirt")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                Text(message)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add my FPL team", action: add)
                    .buttonStyle(ToolkitPrimaryButtonStyle())
            }
        }
    }
}

/// Connecting a team from inside the app (explore mode or Settings).
struct AddTeamSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ConnectTeamView(repository: appModel.teamRepository)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}

/// The players being watched, most recent first, with availability; a way into Watch.
private struct WatchedSummary: View {
    @Environment(AppModel.self) private var appModel
    let store: WatchStore

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            SectionLabel(text: "Players you're watching")
            if let watch = store.watch, !watch.effective.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(watch.effective.prefix(6).enumerated()), id: \.element.playerId) { index, item in
                        if let player = watch.player(item.playerId) {
                            Button {
                                appModel.router.openPlayer(player.id)
                            } label: {
                                HStack(spacing: ToolkitSpace.sm) {
                                    Text(player.webName)
                                        .font(.headline)
                                        .foregroundStyle(ToolkitColor.primaryText)
                                    AvailabilityBadge(availability: player.availability)
                                    Spacer(minLength: ToolkitSpace.sm)
                                    Text(Format.price(player.price))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(ToolkitColor.secondaryText)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < min(watch.effective.count, 6) - 1 {
                                Divider().overlay(ToolkitColor.border)
                            }
                        }
                    }
                }
                .padding(.horizontal, ToolkitSpace.lg)
                .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
                .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.border))
                // The frame goes on the label: outside it, the tappable area stays the text's height.
                Button {
                    appModel.router.selectedTab = .watch
                } label: {
                    Text("Open Watch")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            } else {
                Text("Search for any player on the Watch tab and tap + to watch them.")
                    .foregroundStyle(ToolkitColor.secondaryText)
                Button("Go to Watch") { appModel.router.selectedTab = .watch }
                    .buttonStyle(ToolkitSecondaryButtonStyle())
            }
        }
        .task { await store.loadIfNeeded() }
    }
}
