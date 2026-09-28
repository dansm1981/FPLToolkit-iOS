import Charts
import SwiftUI

/// The website's player insights (/insights): the differential opportunity map, then every player
/// sorted by any of the website's columns. A star shortlists; "+" adds to the draft last opened in
/// the Planner, as the website's "+" adds to its current draft.
struct PlayerInsightsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var position: Position?
    @State private var club: Int?
    @State private var search = ""
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

    private struct Options: Hashable {
        let position: Position?
        let club: Int?
        let search: String
        let sort: String
        let ascending: Bool?
        let per90: Bool
        let fdrHorizon: Int
    }

    private var options: Options {
        Options(position: position, club: club, search: search, sort: sort, ascending: ascending,
                per90: per90, fdrHorizon: fdrHorizon)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
                OpportunityMapSection()
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    SectionLabel(text: "All players")
                    controls
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
                    ResearchTableView(table: table, caption: "Loading players…", retry: reload) { insights in
                        list(insights)
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Player insights")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search players")
        .task { await appModel.shortlist.loadIfNeeded() }
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
            position: position, club: club, search: search, sort: sort, ascending: ascending,
            per90: per90, fdrHorizon: fdrHorizon))
    }

    private var loaded: PlayerInsights? { (table.current?.loaded ?? table.previous)?.value }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            PositionPicker(position: $position)
                .padding(.bottom, ToolkitSpace.xs)
            ClubMenu(club: $club)
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(loaded?.columns ?? []) { Text(columnLabel($0)).tag($0.key) }
                }
                Picker("Order", selection: $ascending) {
                    Text("Website's order").tag(Bool?.none)
                    Text("Highest first").tag(Bool?.some(false))
                    Text("Lowest first").tag(Bool?.some(true))
                }
            } label: {
                Label(sortSummary, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Sort: \(sortSummary)")
            Menu {
                Picker("Fixture difficulty over", selection: $fdrHorizon) {
                    ForEach(Self.horizons, id: \.self) { Text($0 == 1 ? "Next gameweek" : "Next \($0) gameweeks").tag($0) }
                }
            } label: {
                Label("FPL difficulty: next \(fdrHorizon)", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("FPL difficulty over the next \(fdrHorizon) gameweeks")
            Toggle("Per 90 minutes", isOn: $per90)
                .font(.subheadline.weight(.semibold))
                .tint(ToolkitColor.accent)
                .frame(minHeight: 44)
        }
    }

    private func columnLabel(_ column: PlayerInsights.Column) -> String {
        per90 && column.per90 ? "\(column.label)/90" : column.label
    }

    private var sortSummary: String {
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
                Text("Showing the first \(insights.rows.count) of \(insights.count).")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            Text("Per-90 figures need at least 720 minutes. FDR adds up FPL's own difficulty over the next \(insights.fdrHorizon == 1 ? "gameweek" : "\(insights.fdrHorizon) gameweeks"), from GW\(insights.gw); lower is easier.\(LastDraft.name.map { " + adds a player to \u{201C}\($0)\u{201D}, the draft you last opened." } ?? "")")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        let f = figures(row, insights)
        let starred = appModel.shortlist.contains(row.playerId)
        return HStack(spacing: ToolkitSpace.xs) {
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
                            if let player { AvailabilityBadge(availability: player.availability) }
                        }
                        ClubLabel(clubId: player?.clubId, text: detailLine(player, others: f.others))
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ToolkitSpace.sm)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(f.main)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(f.mainLabel)
                            .font(.caption)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(([player?.webName ?? "Player", "\(f.mainLabel) \(f.main)"] as [String] + f.others).joined(separator: ", "))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the player")

            Button {
                Task { await appModel.shortlist.toggle(row.playerId) }
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(starred ? ToolkitColor.accent : ToolkitColor.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(starred ? "Remove \(player?.webName ?? "player") from shortlist" : "Shortlist \(player?.webName ?? "player")")

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
                .accessibilityLabel("Add \(player?.webName ?? "player") to \(LastDraft.name ?? "your draft")")
            }
        }
        .padding(.vertical, ToolkitSpace.xs)
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

/// The website's differential opportunity map: ownership against a measure, split at the medians,
/// with the leaders listed below (the chart's accessible form).
private struct OpportunityMapSection: View {
    @Environment(AppModel.self) private var appModel
    @State private var metric = "xgi90"
    @State private var position: Position?
    @State private var maxOwn = 15
    @State private var minMins = 0
    @State private var table = ResearchTable<OpportunityMap>()

    private struct Options: Hashable {
        let metric: String
        let position: Position?
        let maxOwn: Int
        let minMins: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Differential opportunity map")
            ResearchTableView(table: table, caption: "Plotting players…", retry: reload) { map in
                content(map)
            }
        }
        .task(id: Options(metric: metric, position: position, maxOwn: maxOwn, minMins: minMins)) { await load() }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.playersResearchRepository.opportunity(metric: metric, position: position,
                                                                        maxOwn: maxOwn, minMins: minMins))
    }

    private func content(_ map: OpportunityMap) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            Text("Ownership against \(map.metric.label). Top left is the opportunity: little owned, doing a lot. Tap a point for the player.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            controls(map)
            if map.points.isEmpty {
                Text("No players match these filters. Try raising the ownership ceiling or lowering the minutes.")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            } else {
                chart(map)
                legend(map)
                Text("\(map.points.count) players plotted. Median ownership \(MarketFormat.percent(map.medianOwnership)), median \(map.metric.label) \(map.medianValue.formatted(.number.precision(.fractionLength(0...3)))). The dashed lines mark them.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                MarketList(title: "Top \(map.top.count) by \(map.metric.label)", rows: map.top, initial: 12) { top in
                    let player = map.player(top.playerId)
                    let own = map.points.first { $0.playerId == top.playerId }?.own ?? 0
                    MarketPlayerRow(playerId: top.playerId, player: player,
                                    details: ["\(MarketFormat.percent(own)) owned"],
                                    trailing: top.display,
                                    spoken: "\(player?.webName ?? "Player"), \(map.metric.label) \(top.display), \(MarketFormat.percent(own)) owned")
                }
            }
        }
    }

    private func controls(_ map: OpportunityMap) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PositionPicker(position: $position)
                .padding(.bottom, ToolkitSpace.xs)
            Menu {
                Picker("Measure", selection: $metric) {
                    ForEach(map.metrics) { Text($0.label).tag($0.key) }
                }
            } label: {
                Label(map.metric.label, systemImage: "chart.dots.scatter")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Measure: \(map.metric.label)")
            Menu {
                Picker("Owned by at most", selection: $maxOwn) {
                    ForEach(map.ownershipCeilings, id: \.self) { Text("Owned by \($0)% or less").tag($0) }
                }
                Picker("Minutes", selection: $minMins) {
                    ForEach(map.minuteFloors, id: \.self) { Text($0 == 0 ? "Any minutes" : "\($0)+ minutes").tag($0) }
                }
            } label: {
                Label("Owned ≤ \(maxOwn)% · \(minMins == 0 ? "any minutes" : "\(minMins)+ mins")", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Owned by \(maxOwn)% or less, \(minMins == 0 ? "any minutes" : "at least \(minMins) minutes")")
        }
    }

    private func chart(_ map: OpportunityMap) -> some View {
        Chart {
            RuleMark(x: .value("Median ownership", map.medianOwnership))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(ToolkitColor.secondaryText)
            RuleMark(y: .value("Median \(map.metric.label)", map.medianValue))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(ToolkitColor.secondaryText)
            ForEach(map.points) { point in
                let position = map.player(point.playerId)?.position ?? .unknown
                PointMark(x: .value("Owned %", point.own), y: .value(map.metric.label, point.value))
                    .symbol(by: .value("Position", position.rawValue))
                    .foregroundStyle(by: .value("Position", position.rawValue))
                    .symbolSize(40)
            }
            // Names on the six leaders only, as the website labels them.
            ForEach(map.points.filter(\.labelled)) { point in
                PointMark(x: .value("Owned %", point.own), y: .value(map.metric.label, point.value))
                    .opacity(0)
                    .annotation(position: .top, spacing: 2) {
                        Text(map.player(point.playerId)?.webName ?? "")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ToolkitColor.primaryText)
                    }
            }
        }
        .chartForegroundStyleScale(Self.positionColours)
        .chartLegend(.hidden)
        .chartXAxisLabel("Owned %")
        .chartYAxisLabel(map.metric.label)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let frame = proxy.plotFrame.map({ geometry[$0] }) else { return }
                        let x = location.x - frame.origin.x
                        let y = location.y - frame.origin.y
                        // The nearest point on screen.
                        let nearest = map.points.min { a, b in
                            distance(proxy, a, x, y) < distance(proxy, b, x, y)
                        }
                        if let nearest, distance(proxy, nearest, x, y) < 30 {
                            appModel.router.openPlayer(nearest.playerId)
                        }
                    }
            }
        }
        .frame(height: 300)
        // Hidden from VoiceOver (building its data for hundreds of points is slow); the legend
        // carries a summary and the list below has the leaders.
        .accessibilityHidden(true)
    }

    static let positionColours: KeyValuePairs<String, Color> = [
        "GK": ToolkitColor.accent, "DEF": ToolkitColor.information,
        "MID": ToolkitColor.positive, "FWD": ToolkitColor.error,
    ]

    /// The chart's key, in text that scales (the chart's own legend doesn't). VoiceOver reads it as
    /// the chart's summary.
    private func legend(_ map: OpportunityMap) -> some View {
        HStack(spacing: ToolkitSpace.md) {
            ForEach(Array(Self.positionColours), id: \.key) { key, colour in
                HStack(spacing: 4) {
                    Circle().fill(colour).frame(width: 8, height: 8)
                    Text(key)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func distance(_ proxy: ChartProxy, _ point: OpportunityMap.Point, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
        guard let px = proxy.position(forX: point.own), let py = proxy.position(forY: point.value) else { return .infinity }
        return hypot(px - x, py - y)
    }
}
