import SwiftUI

/// S10. The players this device watches: the published squad (if followed) plus manual picks,
/// each with why it's watched. Alerts for them arrive once pushes are switched on (Step 4).
struct WatchView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int

    var body: some View {
        Group {
            if let store = appModel.watch {
                WatchContent(store: store)
                    .task { await store.loadIfNeeded() }
            }
        }
        .toolkitScreen()
        .navigationTitle("Watch")
        .settingsButton(entryId: entryId)
    }
}

private struct WatchContent: View {
    @Environment(AppModel.self) private var appModel
    let store: WatchStore

    var body: some View {
        switch store.resource.phase {
        case .loading:
            ScrollView {
                SkeletonCards(caption: "Loading your watch list…")
                    .padding(.horizontal, ToolkitSpace.page)
            }
        case .failed(let copy):
            ErrorStateView(copy: copy) {
                Task { await store.resource.retry() }
            }
        case .loaded(let loaded):
            list(loaded)
        }
    }

    private func list(_ loaded: Loaded<Watch>) -> some View {
        let watch = loaded.value
        let squadItems = watch.effective.filter { $0.reasons.contains(.squad) }
        let manualOnly = watch.effective.filter { !$0.reasons.contains(.squad) }
        return List {
            Section {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    Text("Your squad and the players you follow.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                    SavedDataBanner(resource: store.resource)
                    if let error = store.updateError {
                        ErrorBanner(copy: ErrorCopy(title: "Your watch list wasn't changed", message: error.message, canRetry: error.canRetry))
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: ToolkitSpace.sm, trailing: 0))
            }

            Section {
                Toggle(isOn: Binding(
                    get: { watch.autoTrackSquad },
                    set: { on in Task { await store.setAutoTrackSquad(on) } }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Follow my published squad")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(squadCaption(watch))
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                .tint(ToolkitColor.accent)
                .disabled(store.isUpdating || loaded.isFromCache)
                .padding(.vertical, ToolkitSpace.xs)
            }
            .listRowBackground(ToolkitColor.surface)

            if !squadItems.isEmpty {
                Section {
                    ForEach(squadItems) { item in
                        row(item, watch: watch)
                            .swipeActions(edge: .trailing) {
                                if watch.isManual(item.playerId) {
                                    Button("Unpin") { Task { await store.setWatched(false, playerId: item.playerId) } }
                                        .tint(ToolkitColor.raised)
                                } else {
                                    Button("Keep if sold") { Task { await store.setWatched(true, playerId: item.playerId) } }
                                        .tint(ToolkitColor.information)
                                }
                            }
                    }
                } header: {
                    SectionLabel(text: "In your squad")
                } footer: {
                    Text("Swipe left on a player to keep watching him even after you sell him.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .listRowBackground(ToolkitColor.surface)
            }

            Section {
                if manualOnly.isEmpty {
                    Text("To watch a player who isn't in your squad, open him from Today or Team and tap Watch.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                } else {
                    ForEach(manualOnly) { item in
                        row(item, watch: watch)
                            .swipeActions(edge: .trailing) {
                                Button("Stop watching", role: .destructive) {
                                    Task { await store.setWatched(false, playerId: item.playerId) }
                                }
                            }
                    }
                }
            } header: {
                SectionLabel(text: "Also watching")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    Label("No alerts yet", systemImage: "bell.badge")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("Price, availability and deadline alerts for these players aren't switched on yet. Once they are, every alert we send will be listed here.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .padding(.vertical, ToolkitSpace.xs)
            } header: {
                SectionLabel(text: "Alerts")
            }
            .listRowBackground(ToolkitColor.surface)

            if let freshness = loaded.meta.freshness, !freshness.isEmpty {
                Section {
                    WhatWeCheckedSection(sources: freshness, savedAt: loaded.savedAt)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await store.resource.load(bypassCache: true) }
    }

    private func squadCaption(_ watch: Watch) -> String {
        guard let squad = watch.squad else {
            return "No published squad yet. It's followed from your first deadline."
        }
        if let freeHit = squad.freeHitGw {
            return "\(squad.playerIds.count) players · the GW\(squad.gw) squad your GW\(freeHit) Free Hit reverted to"
        }
        return "\(squad.playerIds.count) players · your GW\(squad.gw) squad, updated after each deadline"
    }

    private func row(_ item: Watch.Item, watch: Watch) -> some View {
        Button {
            appModel.router.openPlayer(item.playerId)
        } label: {
            WatchRow(item: item, player: watch.player(item.playerId), isManual: watch.isManual(item.playerId))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the player")
    }
}

private struct WatchRow: View {
    @Environment(AppModel.self) private var appModel
    let item: Watch.Item
    let player: PlayerSummary?
    let isManual: Bool

    var body: some View {
        HStack(spacing: ToolkitSpace.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: ToolkitSpace.sm) {
                    Text(player?.webName ?? "Player \(item.playerId)")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    if let player { AvailabilityBadge(availability: player.availability) }
                }
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            Spacer(minLength: ToolkitSpace.sm)
            if isManual && item.reasons.contains(.squad) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(ToolkitColor.link)
                    .accessibilityLabel("Kept if sold")
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        guard let player else { return "" }
        var parts: [String] = []
        if let club = appModel.club(player.clubId) { parts.append(club.shortName) }
        parts.append(player.position.rawValue)
        parts.append(Format.price(player.price))
        return parts.joined(separator: " · ")
    }
}
