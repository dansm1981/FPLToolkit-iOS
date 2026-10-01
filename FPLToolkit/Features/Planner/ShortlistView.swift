import SwiftUI

/// The website's Shortlist, and since batch 3 simple player discovery: "My shortlist" (with
/// position, club and price filters and "+" to add one to the draft) and "All players" (the
/// shared finder: filters, sorts and a star on every player). The shortlist is also the watch
/// list, so shortlisted players are watched for alerts. The list lives on the server, per device.
struct ShortlistView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The headshot's text scaling (as PlayerPhoto), to line the details up under the name.
    @ScaledMetric(relativeTo: .body) private var photoUnit: CGFloat = 1
    @Environment(AppModel.self) private var appModel
    /// The draft "+" adds to (its gameweek on screen); nil opens without one.
    let draftModel: DraftModel?

    enum Mode: String, CaseIterable, Identifiable {
        case shortlist = "My shortlist", all = "All players"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .shortlist
    @State private var position: Position?
    @State private var club: Int?
    @State private var maxPrice: Double?
    @State private var notice: String?

    private var store: ShortlistStore { appModel.shortlist }

    private var shown: [PlannerShortlist.Item] {
        guard let list = store.list else { return [] }
        return list.items.filter { item in
            guard let player = list.player(item.playerId) else { return false }
            if let position, player.position != position { return false }
            if let club, player.clubId != club { return false }
            if let maxPrice, player.price > maxPrice + 0.001 { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.vertical, ToolkitSpace.sm)
            switch mode {
            case .shortlist: shortlist
            case .all: PlayerFinder(advanced: false)
            }
        }
        .background(ToolkitColor.canvas.ignoresSafeArea())
        .navigationTitle("Shortlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == .shortlist {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
        }
        .task {
            store.clearError()
            await store.load()
            await appModel.mergeStarLists()
        }
    }

    private var shortlist: some View {
        List {
            Section {
                Picker("Position", selection: $position) {
                    Text("All").tag(Position?.none)
                    ForEach([Position.gk, .def, .mid, .fwd], id: \.self) { Text($0.rawValue).tag(Position?.some($0)) }
                }
                .pickerStyle(.segmented)
                if let error = appModel.starError ?? store.loadError {
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
                        Text("Nothing shortlisted yet. Tap the star on any player, or find one in All players.")
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
                        Task { for id in ids { await appModel.setStarred(false, playerId: id) } }
                    }
                } header: {
                    SectionLabel(text: shown.count == list.items.count
                                 ? "\(list.items.count) of up to \(list.max)"
                                 : "Showing \(shown.count) of \(list.items.count)")
                }
                .listRowBackground(ToolkitColor.surface)
                if !list.items.isEmpty {
                    // A plain row, not a section footer: footers don't scale fully with text size.
                    Text("Shortlisted players are watched for alerts. Swipe left to take a player off.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .listRowBackground(Color.clear)
                }
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
        // At the large sizes the details get a full-width line under the name and buttons, rather
        // than a narrow column between them (Dan's phone at xxxLarge, 1 Oct).
        let stacked = typeSize.stacksRows
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: ToolkitSpace.md) {
                Button {
                    appModel.router.openPlayer(item.playerId)
                } label: {
                    HStack(spacing: ToolkitSpace.md) {
                        PlayerPhoto(path: player?.photo, clubLogo: appModel.club(player?.clubId)?.logo)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: ToolkitSpace.sm) {
                                Text(name)
                                    .font(.headline)
                                    .foregroundStyle(ToolkitColor.primaryText)
                                if let player { AvailabilityBadge(availability: player.availability).fixedSize(horizontal: stacked, vertical: false) }
                            }
                            if !stacked {
                                ClubLabel(clubId: player?.clubId, text: details(player))
                                    .font(.subheadline)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(ifGiven: stacked ? "\(name), \(details(player))" : nil)
                .accessibilityHint("Opens the player")

                Button {
                    Task { await appModel.setStarred(false, playerId: item.playerId) }
                } label: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(ToolkitColor.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(name) from your shortlist")

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
            if stacked {
                // Also opens the player; VoiceOver reads it on the row above.
                Button {
                    appModel.router.openPlayer(item.playerId)
                } label: {
                    ClubLabel(clubId: player?.clubId, text: details(player))
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(.leading, (32 * min(photoUnit, 1.5)).rounded() + ToolkitSpace.md)
                .padding(.bottom, ToolkitSpace.xs)
                .accessibilityHidden(true)
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
