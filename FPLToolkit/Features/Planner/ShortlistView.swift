import SwiftUI

/// The website's Shortlist: players you're keeping an eye on, with position, club and price
/// filters, the "vibe" favourites flag, "Watch all" for price alerts, and "+" to add one to the
/// draft. The list lives on the server, per device.
struct ShortlistView: View {
    @Environment(AppModel.self) private var appModel
    /// The draft "+" adds to (its gameweek on screen); nil opens without one.
    let draftModel: DraftModel?

    @State private var position: Position?
    @State private var club: Int?
    @State private var maxPrice: Double?
    @State private var vibeOnly = false
    @State private var notice: String?

    private var store: ShortlistStore { appModel.shortlist }

    private var shown: [PlannerShortlist.Item] {
        guard let list = store.list else { return [] }
        return list.items.filter { item in
            guard let player = list.player(item.playerId) else { return false }
            if let position, player.position != position { return false }
            if let club, player.clubId != club { return false }
            if let maxPrice, player.price > maxPrice + 0.001 { return false }
            if vibeOnly && !item.vibe { return false }
            return true
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Position", selection: $position) {
                    Text("All").tag(Position?.none)
                    ForEach([Position.gk, .def, .mid, .fwd], id: \.self) { Text($0.rawValue).tag(Position?.some($0)) }
                }
                .pickerStyle(.segmented)
                Toggle("Vibe only", isOn: $vibeOnly)
                    .tint(ToolkitColor.accent)
                if let error = store.updateError ?? store.loadError {
                    ErrorBanner(copy: error)
                }
                if let error = appModel.watch?.updateError {
                    ErrorBanner(copy: error)
                }
                if let error = draftModel?.actionError {
                    ErrorBanner(copy: error)
                }
                if let notice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.positive)
                }
            }
            .listRowBackground(ToolkitColor.surface)

            if let list = store.list {
                Section {
                    if list.items.isEmpty {
                        Text("Nothing shortlisted yet. Tap the star next to a player in the picker to keep him here.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                    } else if shown.isEmpty {
                        Text("No shortlisted players match these filters.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    ForEach(shown) { item in
                        row(item, list: list)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { shown[$0].playerId }
                        Task { for id in ids { await store.remove(id) } }
                    }
                } header: {
                    SectionLabel(text: shown.count == list.items.count
                                 ? "\(list.items.count) of up to \(list.max)"
                                 : "Showing \(shown.count) of \(list.items.count)")
                } footer: {
                    if !list.items.isEmpty {
                        Text("Vibe marks your favourites. Swipe left to take a player off.")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                .listRowBackground(ToolkitColor.surface)
            } else if store.loadError == nil {
                Section {
                    HStack(spacing: ToolkitSpace.sm) {
                        ProgressView()
                        Text("Loading your shortlist…").foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                .listRowBackground(ToolkitColor.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ToolkitColor.canvas.ignoresSafeArea())
        .navigationTitle("Shortlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { filterMenu }
        }
        .task {
            store.clearError()
            await store.load()
            await appModel.watch?.loadIfNeeded()
        }
        .refreshable { await store.load() }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Club", selection: $club) {
                Text("All clubs").tag(Int?.none)
                ForEach(clubs, id: \.id) { Text($0.shortName).tag(Int?.some($0.id)) }
            }
            Picker("Max price", selection: $maxPrice) {
                Text("Any price").tag(Double?.none)
                ForEach(Array(stride(from: 4.5, through: 15.0, by: 0.5)), id: \.self) { price in
                    Text("Up to \(Format.price(price))").tag(Double?.some(price))
                }
            }
            if appModel.watch != nil {
                Divider()
                Button {
                    Task {
                        await appModel.watch?.watchAll(shown.map(\.playerId))
                        if appModel.watch?.updateError == nil {
                            notice = "Watching \(shown.count) shortlisted player\(shown.count == 1 ? "" : "s") for alerts."
                        }
                    }
                } label: {
                    Label("Watch all shown for alerts", systemImage: "bell.badge")
                }
                .disabled(shown.isEmpty)
            }
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var clubs: [Bootstrap.Club] {
        (appModel.bootstrap?.value.clubs ?? []).sorted { $0.shortName < $1.shortName }
    }

    private func row(_ item: PlannerShortlist.Item, list: PlannerShortlist) -> some View {
        let player = list.player(item.playerId)
        let name = player?.webName ?? "Player \(item.playerId)"
        let watched = appModel.watch?.watch?.isManual(item.playerId) ?? false
        return HStack(alignment: .center, spacing: ToolkitSpace.md) {
            Button {
                appModel.router.openPlayer(item.playerId)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: ToolkitSpace.sm) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        if let player { AvailabilityBadge(availability: player.availability) }
                    }
                    Text(details(player))
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Opens the player")

            Button {
                Task { await store.setVibe(!item.vibe, for: item.playerId) }
            } label: {
                Image(systemName: item.vibe ? "flame.fill" : "flame")
                    .foregroundStyle(item.vibe ? ToolkitColor.accent : ToolkitColor.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.vibe ? "Vibe: on for \(name)" : "Vibe: off for \(name)")
            .accessibilityHint("Marks him as a favourite")

            if let watch = appModel.watch {
                Button {
                    Task { await watch.setWatched(!watched, playerId: item.playerId) }
                } label: {
                    Image(systemName: watched ? "bell.fill" : "bell")
                        .foregroundStyle(watched ? ToolkitColor.accent : ToolkitColor.secondaryText)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(watched ? "Stop watching \(name)" : "Watch \(name) for alerts")
            }

            if let draftModel, draftModel.draft?.isEditable == true {
                Button {
                    Task { await add(item.playerId, name: name, to: draftModel) }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ToolkitColor.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(draftModel.isApplying)
                .accessibilityLabel("Add \(name) to the draft")
            }
        }
    }

    private func details(_ player: PlayerSummary?) -> String {
        guard let player else { return "" }
        var parts: [String] = []
        if let club = appModel.club(player.clubId) { parts.append(club.shortName) }
        parts.append(player.position.rawValue)
        parts.append(Format.price(player.price))
        if let f = player.nextFixture {
            if f.blank {
                parts.append("no game")
            } else {
                let opponent = appModel.club(f.opponentClubId)?.shortName ?? "TBC"
                var text = "\(opponent) (\(f.home.map { $0 ? "H" : "A" } ?? ""))"
                if let x = f.xfdr { text += " \(x.display)" }
                parts.append(text)
            }
        }
        return parts.joined(separator: " · ")
    }

    private func add(_ playerId: Int, name: String, to model: DraftModel) async {
        notice = nil
        guard let gw = model.draft?.gw else { return }
        if await model.apply(.pick(playerId, replacing: nil, gw: gw)) {
            notice = "Added \(name) to GW\(gw)."
        }
    }
}
