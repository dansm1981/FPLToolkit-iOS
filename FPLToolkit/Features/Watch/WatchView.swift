import SwiftUI

/// S10. The players this device watches: the published squad (if followed) plus manual picks,
/// each with why it's watched. Alerts for them arrive once pushes are switched on (Step 4).
struct WatchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    /// nil while exploring without a team.
    let entryId: Int?
    @State private var searchAvailable = false
    @State private var query = ""
    @State private var search: PlayerSearchModel?

    var body: some View {
        Group {
            if let store = appModel.watch {
                if let search, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResults(search: search, store: store)
                } else {
                    WatchContent(store: store, searchAvailable: searchAvailable)
                }
            }
        }
        // The search field is added once search is known to be live, which swaps the view inside
        // this modifier; tasks attached after it keep running through that swap.
        .modifier(PlayerSearchField(isOn: searchAvailable, query: $query))
        .task {
            await appModel.watch?.refreshIfStale()
            await appModel.mergeStarLists()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await appModel.watch?.refreshIfStale() } }
        }
        .task {
            if search == nil {
                search = PlayerSearchModel(repository: appModel.playerRepository)
                searchAvailable = await appModel.playerRepository.searchIsAvailable()
            }
        }
        .task(id: query) { await search?.run(query) }
        .navigationDestination(isPresented: Binding(
            get: { appModel.router.showingAlerts && appModel.alerts != nil },
            set: { appModel.router.showingAlerts = $0 }
        )) {
            if let alerts = appModel.alerts { AlertHistoryView(resource: alerts) }
        }
        .toolkitScreen()
        .navigationTitle("Watch")
        // In the top bar, as on Today (Dan, 30 Sep).
        .navigationBarTitleDisplayMode(.inline)
        .settingsButton(entryId: entryId)
    }
}

/// Only shows the search field once the server has player search.
private struct PlayerSearchField: ViewModifier {
    let isOn: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if isOn {
            content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all players")
        } else {
            content
        }
    }
}

@MainActor
@Observable
final class PlayerSearchModel {
    enum Phase {
        case idle
        case tooShort
        case searching
        case results(query: String, players: [PlayerSummary])
        case failed(ErrorCopy)
    }

    private(set) var phase: Phase = .idle
    private let repository: PlayerRepository

    init(repository: PlayerRepository) {
        self.repository = repository
    }

    /// Runs a search after a short pause in typing; a newer query cancels this one.
    func run(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { phase = .idle; return }
        guard trimmed.count >= 2 else { phase = .tooShort; return }
        do {
            try await Task.sleep(for: .milliseconds(300))
            phase = .searching
            let result = try await repository.search(trimmed)
            phase = .results(query: trimmed, players: result.players)
        } catch let error as APIError {
            phase = .failed(ErrorCopy(error))
        } catch {
            // Cancelled by a newer query.
        }
    }
}

private struct SearchResults: View {
    @Environment(AppModel.self) private var appModel
    let search: PlayerSearchModel
    let store: WatchStore

    var body: some View {
        List {
            switch search.phase {
            case .idle, .tooShort:
                note("Type at least 2 letters of a player's name.")
            case .searching:
                HStack(spacing: ToolkitSpace.sm) {
                    ProgressView()
                    Text("Searching…").foregroundStyle(ToolkitColor.secondaryText)
                }
                .listRowBackground(ToolkitColor.surface)
            case .failed(let copy):
                note("\(copy.title). \(copy.message)")
            case .results(let query, let players):
                if players.isEmpty {
                    note("No players match \u{201C}\(query)\u{201D}.")
                } else {
                    Section {
                        ForEach(players) { player in
                            SearchResultRow(player: player, store: store)
                        }
                    } footer: {
                        if let error = appModel.starError {
                            Text("Your shortlist wasn't changed: \(error.message)")
                                .foregroundStyle(ToolkitColor.error)
                        }
                    }
                    .listRowBackground(ToolkitColor.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
            .listRowBackground(ToolkitColor.surface)
    }
}

private struct SearchResultRow: View {
    @Environment(AppModel.self) private var appModel
    let player: PlayerSummary
    let store: WatchStore

    var body: some View {
        let watch = store.watch
        let starred = appModel.isStarred(player.id)
        let inSquad = watch?.reasons(for: player.id).contains(.squad) ?? false
        HStack(spacing: ToolkitSpace.md) {
            Button {
                appModel.router.openPlayer(player.id)
            } label: {
                HStack(spacing: ToolkitSpace.md) {
                    PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: ToolkitSpace.sm) {
                            Text(player.webName)
                                .font(.headline)
                                .foregroundStyle(ToolkitColor.primaryText)
                            AvailabilityBadge(availability: player.availability)
                        }
                        ClubLabel(clubId: player.clubId, text: details(inSquad: inSquad))
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the player")

            Button {
                Task { await appModel.toggleStar(player.id) }
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(starred ? ToolkitColor.accent : ToolkitColor.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(starred ? "Remove \(player.webName) from your shortlist" : "Add \(player.webName) to your shortlist")
        }
    }

    private func details(inSquad: Bool) -> String {
        var parts: [String] = []
        if let club = appModel.club(player.clubId) { parts.append(club.shortName) }
        parts.append(player.position.rawValue)
        parts.append(Format.price(player.price))
        if inSquad { parts.append("in your squad") }
        return parts.joined(separator: " · ")
    }
}

private struct WatchContent: View {
    @Environment(AppModel.self) private var appModel
    let store: WatchStore
    var searchAvailable = false

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
                    Text(appModel.entryId == nil ? "Your shortlist." : "Your squad and your shortlist.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                    SavedDataBanner(resource: store.resource)
                    if let error = appModel.starError {
                        ErrorBanner(copy: ErrorCopy(title: "Your shortlist wasn't changed", message: error.message, canRetry: error.canRetry))
                    }
                }
                .listRowBackground(Color.clear)
                // A little room above: with none, the row clips the top of the first line's capitals.
                .listRowInsets(EdgeInsets(top: ToolkitSpace.sm, leading: 0, bottom: ToolkitSpace.sm, trailing: 0))
            }

            // Every alert in one place (Dan, 29 Sep).
            Section {
                NavigationLink {
                    AlertsView()
                } label: {
                    LinkRowLabel(title: "Manage alerts", detail: "Choose what we tell you about", systemImage: "bell.badge",
                                 showsChevron: false)
                }
            }
            .listRowBackground(ToolkitColor.surface)

            if appModel.entryId != nil {
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
            }

            if !squadItems.isEmpty {
                // Players with news as the team news cards (batch 3), most urgent first.
                let withNews = squadItems.filter { $0.topInsight != nil }
                    .sorted { ($0.topInsight?.needsAttention == true ? 0 : 1) < ($1.topInsight?.needsAttention == true ? 0 : 1) }
                let quiet = squadItems.filter { $0.topInsight == nil }
                if !withNews.isEmpty {
                    Section {
                        ForEach(withNews) { item in
                            newsCard(item, watch: watch)
                                .swipeActions(edge: .trailing) { squadSwipe(item) }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: ToolkitSpace.xs, leading: 0, bottom: ToolkitSpace.xs, trailing: 0))
                        }
                    } header: {
                        SectionLabel(text: "In your squad")
                    }
                }
                if !quiet.isEmpty {
                    Section {
                        ForEach(quiet) { item in
                            row(item, watch: watch)
                                .swipeActions(edge: .trailing) { squadSwipe(item) }
                        }
                    } header: {
                        SectionLabel(text: withNews.isEmpty ? "In your squad" : "In your squad: no news")
                    } footer: {
                        Text("Swipe left on a player to add him to your shortlist: he's still watched after you sell him.")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .listRowBackground(ToolkitColor.surface)
                }
            }

            Section {
                if manualOnly.isEmpty {
                    Text(emptyManualText)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                } else {
                    ForEach(manualOnly) { item in
                        row(item, watch: watch)
                            .swipeActions(edge: .trailing) {
                                Button("Remove", role: .destructive) {
                                    Task { await appModel.setStarred(false, playerId: item.playerId) }
                                }
                                .tint(ToolkitColor.destructiveAction)
                            }
                    }
                }
            } header: {
                SectionLabel(text: "Your shortlist")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                if appModel.anyPushFeature, let alerts = appModel.alerts {
                    RecentAlerts(resource: alerts)
                } else {
                    VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                        Label("No alerts yet", systemImage: "bell.badge")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text("Price, availability and deadline alerts for these players aren't switched on yet. Once they are, every alert we send will be listed here.")
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .padding(.vertical, ToolkitSpace.xs)
                }
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

    private var emptyManualText: String {
        searchAvailable
            ? "Tap the star on any player, or search for one above, to add him to your shortlist. Shortlisted players are watched for alerts."
            : "Tap the star on any player to add him to your shortlist. Shortlisted players are watched for alerts."
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

    @ViewBuilder private func squadSwipe(_ item: Watch.Item) -> some View {
        if appModel.isStarred(item.playerId) {
            Button("Remove from shortlist") { Task { await appModel.setStarred(false, playerId: item.playerId) } }
                .tint(ToolkitColor.raised)
        } else {
            Button("Add to shortlist") { Task { await appModel.setStarred(true, playerId: item.playerId) } }
                .tint(ToolkitColor.information)
        }
    }

    /// A squad player's latest news as the team news card, with his price and ownership trend.
    @ViewBuilder private func newsCard(_ item: Watch.Item, watch: Watch) -> some View {
        if let insight = item.topInsight {
            let trends = WatchRow.trends(item)
            Button {
                appModel.router.openPlayer(item.playerId)
            } label: {
                InsightCard(insight: insight, player: watch.player(item.playerId), showsChevron: true,
                            note: trends.isEmpty ? nil : trends.map(\.text).joined(separator: " · "))
                    .accessibilityLabel([watch.player(item.playerId)?.webName ?? "Player", insight.title, insight.summary,
                                         appModel.isStarred(item.playerId) ? "on your shortlist" : nil,
                                         trends.isEmpty ? nil : trends.map(\.spoken).joined(separator: ". ")]
                        .compactMap { $0 }.joined(separator: ", "))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the player")
        }
    }

    private func row(_ item: Watch.Item, watch: Watch) -> some View {
        Button {
            appModel.router.openPlayer(item.playerId)
        } label: {
            WatchRow(item: item, player: watch.player(item.playerId), isManual: appModel.isStarred(item.playerId))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the player")
    }
}

private struct WatchRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: Watch.Item
    let player: PlayerSummary?
    let isManual: Bool

    var body: some View {
        HStack(spacing: ToolkitSpace.md) {
            PlayerPhoto(path: player?.photo, clubLogo: appModel.club(player?.clubId)?.logo)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: ToolkitSpace.sm) {
                    Text(player?.webName ?? "Player \(item.playerId)")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    if let player { AvailabilityBadge(availability: player.availability) }
                }
                ClubLabel(clubId: player?.clubId, text: details)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                if let insight = item.topInsight {
                    // The note's wording and tone come from the API; an icon as well as colour.
                    Label {
                        Text(insight.summary)
                            .foregroundStyle(ToolkitColor.primaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: insight.symbol)
                            .foregroundStyle(insight.tone.foreground)
                    }
                    .font(.subheadline)
                    .padding(.top, ToolkitSpace.xs)
                }
                if !trends.isEmpty {
                    // One a line from xxLarge, each kept whole ("Owned" / "-0.5 pts (7d)" split).
                    let layout = typeSize.stacksRows
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                        : AnyLayout(HStackLayout(spacing: ToolkitSpace.md))
                    layout {
                        ForEach(trends, id: \.text) { FactLine($0.text) }
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .padding(.top, 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(trends.map(\.spoken).joined(separator: ". "))
                }
            }
            Spacer(minLength: ToolkitSpace.sm)
            if isManual && item.reasons.contains(.squad) {
                Image(systemName: "star.fill")
                    .foregroundStyle(ToolkitColor.accent)
                    .accessibilityLabel("On your shortlist")
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

    private var trends: [(text: String, spoken: String)] { Self.trends(item) }

    /// Price progress (tonight's projection when there is one, as on the player page) and ownership trend.
    static func trends(_ item: Watch.Item) -> [(text: String, spoken: String)] {
        var parts: [(String, String)] = []
        // A price note already says this, in words.
        if item.topInsight?.category != .price, let price = item.price, let value = price.tonightPct ?? price.progressPct {
            let side = value < 0 ? "fall" : "rise"
            let when = price.tonightPct != nil ? "tonight" : "now"
            parts.append(("Price \(Format.signedPercent(value)) \(when)",
                          "Price \(when): \(Format.spokenPercent(value)) of the \(side) threshold"))
        }
        if let change = item.ownershipChange7d {
            let points = change.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
            let spoken = change == 0 ? "no change" : "\(change > 0 ? "up" : "down") \(abs(change).formatted(.number.precision(.fractionLength(1)))) points"
            parts.append(("Owned \(points) pts (7d)", "Ownership over 7 days: \(spoken)"))
        }
        return parts
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

/// The latest few alerts on the Watch tab, with a link to the full history (S11).
private struct RecentAlerts: View {
    @Environment(AppModel.self) private var appModel
    let resource: Resource<AlertHistory>

    var body: some View {
        Group {
            switch resource.phase {
            case .loading:
                ProgressView()
            case .failed(let copy):
                Text("\(copy.title). \(copy.message)")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            case .loaded(let loaded):
                if loaded.value.alerts.isEmpty {
                    Text("No alerts yet. When something changes for these players, it'll be listed here.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                } else {
                    ForEach(loaded.value.alerts.prefix(3)) { alert in
                        AlertRow(alert: alert)
                    }
                    Button("See all alerts") { appModel.router.showingAlerts = true }
                        .frame(minHeight: 44)
                }
            }
        }
        .task { if case .loading = resource.phase { await resource.load() } }
    }
}
