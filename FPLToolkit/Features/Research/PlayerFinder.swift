import SwiftUI

/// Every player, filtered and sorted (batch 3): the Shortlist's "All players" and Player Insights
/// share it. Filters are position, club, price and availability; points, form and the rest are
/// sorts. A star adds the player to your shortlist, which is also your watch list; "+" adds him
/// to the draft last opened in the Planner, as the website's "+" does. `advanced` (Player
/// Insights) sorts by any of the website's columns, in either order, per 90 minutes, and sets the
/// fixture difficulty horizon.
struct PlayerFinder: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The headshot's text scaling (as PlayerPhoto), to line the details up under the name.
    @ScaledMetric(relativeTo: .body) private var photoUnit: CGFloat = 1
    let advanced: Bool

    @State private var search = ""
    @State private var position: Position?
    @State private var club: Int?
    @State private var maxPrice: Double?
    @State private var availableOnly = false
    @State private var sort = "total_points"
    /// nil: the website's default for the column (easiest first for FDR, else highest).
    @State private var ascending: Bool?
    @State private var per90 = false
    @State private var fdrHorizon = 6
    @State private var table = ResearchTable<PlayerInsights>()
    @State private var added: String?
    @State private var addError: String?
    @State private var adding: Int?

    static let horizons = [1, 3, 6, 10]
    /// The simple finder's sorts, the figures Dan asked for first.
    static let quickSorts: [(key: String, label: String)] = [
        ("total_points", "Total points"), ("form", "Form"), ("now_cost_m", "Price"),
        ("points_per_million", "Points per £m"), ("selected_by_percent", "Ownership"),
        ("event_points", "Last GW points"),
    ]

    private struct Options: Hashable {
        let search: String
        let position: Position?
        let club: Int?
        let maxPrice: Double?
        let availableOnly: Bool
        let sort: String
        let ascending: Bool?
        let per90: Bool
        let fdrHorizon: Int
    }

    private var options: Options {
        Options(search: search, position: position, club: club, maxPrice: maxPrice, availableOnly: availableOnly,
                sort: sort, ascending: ascending, per90: per90, fdrHorizon: fdrHorizon)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                PositionPicker(position: $position)
                filters
                if let added {
                    Label(added, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.positive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let addError {
                    Label(addError, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = appModel.starError {
                    ErrorBanner(copy: ErrorCopy(title: "Your shortlist wasn't changed", message: error.message,
                                                canRetry: error.canRetry))
                }
                ResearchTableView(table: table, caption: "Loading players…", retry: reload) { insights in
                    list(insights)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .searchable(text: $search, prompt: "Search players")
        .task { await appModel.mergeStarLists() }
        .task(id: options) {
            // A short pause while typing a search.
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.playersResearchRepository.insights(
            position: position, club: club, search: search, sort: sort, ascending: advanced ? ascending : nil,
            per90: advanced && per90, fdrHorizon: fdrHorizon, maxPrice: maxPrice, availableOnly: availableOnly))
    }

    private var loaded: PlayerInsights? { (table.current?.loaded ?? table.previous)?.value }

    // MARK: Filters

    private var filters: some View {
        FlowLayout(spacing: 8) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    if advanced {
                        ForEach(loaded?.columns ?? []) { Text(columnLabel($0)).tag($0.key) }
                    } else {
                        ForEach(Self.quickSorts, id: \.key) { Text($0.label).tag($0.key) }
                    }
                }
                if advanced {
                    Picker("Order", selection: $ascending) {
                        Text("Website's order").tag(Bool?.none)
                        Text("Highest first").tag(Bool?.some(false))
                        Text("Lowest first").tag(Bool?.some(true))
                    }
                }
            } label: {
                FilterChipLabel(text: sortLabel, active: false, menu: true)
            }
            .accessibilityLabel("Sort by \(sortLabel)")
            Menu {
                Picker("Club", selection: $club) {
                    Text("All clubs").tag(Int?.none)
                    ForEach(clubs, id: \.id) { Text($0.name).tag(Int?.some($0.id)) }
                }
            } label: {
                FilterChipLabel(text: club.flatMap { appModel.club($0)?.shortName } ?? "All clubs", active: club != nil, menu: true)
            }
            .accessibilityLabel("Club: \(club.flatMap { appModel.club($0)?.name } ?? "all clubs")")
            Menu {
                Picker("Max price", selection: $maxPrice) {
                    Text("Any price").tag(Double?.none)
                    ForEach(Array(stride(from: 4.5, through: 15.0, by: 0.5)), id: \.self) { price in
                        Text("Up to \(Format.price(price))").tag(Double?.some(price))
                    }
                }
            } label: {
                FilterChipLabel(text: maxPrice.map { "Up to \(Format.price($0))" } ?? "Any price", active: maxPrice != nil, menu: true)
            }
            .accessibilityLabel("Price: \(maxPrice.map { "up to \(Format.price($0))" } ?? "any")")
            Button { availableOnly.toggle() } label: {
                FilterChipLabel(text: "Available", active: availableOnly, menu: false)
            }
            .accessibilityAddTraits(availableOnly ? .isSelected : [])
            .accessibilityHint("Only players with no injury, suspension or doubt")
            if advanced {
                Menu {
                    Picker("Fixture difficulty over", selection: $fdrHorizon) {
                        ForEach(Self.horizons, id: \.self) { Text($0 == 1 ? "Next gameweek" : "Next \($0) gameweeks").tag($0) }
                    }
                } label: {
                    FilterChipLabel(text: "FDR: next \(fdrHorizon)", active: false, menu: true)
                }
                .accessibilityLabel("FPL difficulty over the next \(fdrHorizon) gameweeks")
                Button { per90.toggle() } label: {
                    FilterChipLabel(text: "Per 90", active: per90, menu: false)
                }
                .accessibilityAddTraits(per90 ? .isSelected : [])
                .accessibilityHint("Shows counting figures per 90 minutes played")
            }
        }
        .padding(.vertical, 2)
    }

    private var clubs: [Bootstrap.Club] {
        (appModel.bootstrap?.value.clubs ?? []).sorted { $0.shortName < $1.shortName }
    }

    private func columnLabel(_ column: PlayerInsights.Column) -> String {
        per90 && column.per90 ? "\(column.label)/90" : column.label
    }

    private var sortLabel: String {
        if !advanced { return Self.quickSorts.first { $0.key == sort }?.label ?? sort }
        let label = loaded?.column(sort).map(columnLabel) ?? sort
        let order = ascending.map { $0 ? "lowest first" : "highest first" }
            ?? (loaded?.sort.dir == "asc" ? "lowest first" : "highest first")
        return "\(label), \(order)"
    }

    // MARK: List

    private func list(_ insights: PlayerInsights) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            MarketList(title: "\(insights.count) players", rows: insights.rows,
                       empty: "No players match these filters.", initial: 30) { row($0, insights) }
            if insights.count > insights.rows.count {
                Text("Showing the first \(insights.rows.count) of \(insights.count). Narrow it with the filters or search.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(footnote(insights))
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footnote(_ insights: PlayerInsights) -> String {
        var parts = ["The star adds a player to your shortlist, and shortlisted players are watched for alerts."]
        if let name = LastDraft.name { parts.append("+ adds him to \u{201C}\(name)\u{201D}, the draft you last opened.") }
        if advanced {
            parts.append("Per-90 figures need at least 720 minutes. FDR adds up FPL's own difficulty over the next \(insights.fdrHorizon == 1 ? "gameweek" : "\(insights.fdrHorizon) gameweeks"), from GW\(insights.gw); lower is easier.")
        }
        return parts.joined(separator: " ")
    }

    /// The sort figure first, then two of the website's default columns.
    private func figures(_ row: PlayerInsights.Row, _ insights: PlayerInsights) -> (main: String, mainLabel: String, others: [String]) {
        let key = insights.sort.key
        let main = row.values[key]?.display ?? "–"
        let mainLabel = insights.column(key).map(columnLabel) ?? key
        let others = insights.shown.filter { $0 != key }.prefix(2).compactMap { k -> String? in
            guard let value = row.values[k]?.display, let column = insights.column(k) else { return nil }
            return k == "now_cost_m" ? value : "\(columnLabel(column)) \(value)"
        }
        return (main, mainLabel, others)
    }

    private func row(_ row: PlayerInsights.Row, _ insights: PlayerInsights) -> some View {
        let player = insights.player(row.playerId)
        let name = player?.webName ?? "player"
        let f = figures(row, insights)
        let starred = appModel.isStarred(row.playerId)
        // At the largest text sizes the details get a full-width line under the name, rather than
        // a narrow column beside the figure and buttons (Dan's phone at xxxLarge, 1 Oct).
        let stacked = typeSize.stacksRows
        let detail = detailLine(player, others: f.others)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: ToolkitSpace.xs) {
                Button {
                    appModel.router.openPlayer(row.playerId)
                } label: {
                    HStack(spacing: ToolkitSpace.sm) {
                        PlayerPhoto(path: player?.photo, clubLogo: appModel.club(player?.clubId)?.logo)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: ToolkitSpace.sm) {
                                Text(player?.webName ?? "Player \(row.playerId)")
                                    .font(.headline)
                                    .foregroundStyle(ToolkitColor.primaryText)
                                if let player { AvailabilityBadge(availability: player.availability).fixedSize(horizontal: stacked, vertical: false) }
                            }
                            if !stacked {
                                ClubLabel(clubId: player?.clubId, text: detail)
                                    .font(.subheadline)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: ToolkitSpace.sm)
                        if !stacked { figure(f) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(([player?.webName ?? "Player", "\(f.mainLabel) \(f.main)"] as [String] + f.others).joined(separator: ", "))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the player")

                // At the large sizes the star and "+" stay on the name's line and the figure moves
                // down beside the details, so neither line is squeezed.
                rowButtons(row, name: name, starred: starred, player: player)
            }
            if stacked {
                HStack(alignment: .center, spacing: ToolkitSpace.xs) {
                    // Also opens the player; VoiceOver already reads it on the row above.
                    Button {
                        appModel.router.openPlayer(row.playerId)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            ClubLogo(clubId: player?.clubId, size: 16)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                            Text(Format.unbroken(detail))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: ToolkitSpace.sm)
                            figure(f)
                                .fixedSize()
                        }
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, (32 * min(photoUnit, 1.5)).rounded() + ToolkitSpace.sm)
                    .accessibilityHidden(true)
                }
                .padding(.bottom, ToolkitSpace.xs)
            }
        }
        .padding(.vertical, ToolkitSpace.xs)
    }

    /// The sort figure and its label, e.g. "47" over "Pts".
    private func figure(_ f: (main: String, mainLabel: String, others: [String])) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(f.main)
                .font(.headline.monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
            Text(f.mainLabel)
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
    }

    /// The star (shortlist) and "+" (last draft) buttons.
    @ViewBuilder
    private func rowButtons(_ row: PlayerInsights.Row, name: String, starred: Bool, player: PlayerSummary?) -> some View {
        Button {
            Task { await appModel.toggleStar(row.playerId) }
        } label: {
            Image(systemName: starred ? "star.fill" : "star")
                .font(.body)
                .foregroundStyle(starred ? ToolkitColor.accent : ToolkitColor.secondaryText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(starred ? "Remove \(name) from your shortlist" : "Add \(name) to your shortlist")

        if LastDraft.id != nil {
            Button {
                Task { await add(row.playerId, name: player?.webName ?? "Player") }
            } label: {
                Group {
                    if adding == row.playerId { ProgressView() } else { Image(systemName: "plus.circle") }
                }
                .font(.body)
                .foregroundStyle(ToolkitColor.link)
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(adding != nil)
            .accessibilityLabel("Add \(name) to \(LastDraft.name ?? "your draft")")
        }
    }


    private func detailLine(_ player: PlayerSummary?, others: [String]) -> String {
        var parts: [String] = []
        if let player {
            if let club = appModel.club(player.clubId)?.shortName { parts.append(club) }
            parts.append(player.position.rawValue)
        }
        parts.append(contentsOf: others)
        return parts.joined(separator: " · ")
    }

    /// Adds the player to the last-opened draft in the next gameweek, the way the website's "+" does.
    private func add(_ playerId: Int, name: String) async {
        guard let draftId = LastDraft.id else { return }
        let gameweek = appModel.bootstrap?.value.gameweek
        let gw = gameweek?.next?.id ?? (gameweek.map { $0.locked + 1 } ?? 1)
        adding = playerId
        added = nil
        addError = nil
        defer { adding = nil }
        do {
            _ = try await appModel.plannerRepository.apply(.pick(playerId, replacing: nil, gw: gw), to: draftId)
            added = "Added \(name) to \(LastDraft.name ?? "your draft") for GW\(gw)."
        } catch let error as APIError {
            addError = "\(name) wasn't added: \(ErrorCopy(error).message)"
        } catch {}
    }
}

extension LastDraft {
    static var id: String? { UserDefaults.standard.string(forKey: idKey) }
    static var name: String? { UserDefaults.standard.string(forKey: nameKey) }
}
