import SwiftUI

/// The website's price and transfer trends (/tools/prices): today's movers, the strongest flows,
/// then every player with the same filters (Everyone, My squad, Shortlist) and sorts.
struct MarketTrendsView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int?

    enum Scope: String, Hashable { case everyone, squad, shortlist }
    enum Highlight: Hashable { case risers, fallers, up, down }

    @State private var scope = Scope.everyone
    @State private var position: Position?
    @State private var club: Int?
    @State private var band = 0
    @State private var sort = "likelihood"
    @State private var ascending = false
    @State private var highlight = Highlight.up
    @State private var squadIds: [Int]?
    @State private var table = ResearchTable<MarketTrends>()

    static let bands = ["All prices", "Under £5.0m", "£5.0–7.5m", "£7.5–10m", "£10m+"]
    static let sorts: [(String, String)] = [
        ("likelihood", "Change likelihood"), ("price", "Price"), ("dayPrice", "Price change today"),
        ("seasonPrice", "Price change this season"), ("own", "Ownership"), ("dayOwn", "Ownership change today"),
        ("net", "Net transfers"), ("dayNet", "Net transfers today"),
    ]

    private struct Options: Hashable {
        let ids: [Int]?
        let position: Position?
        let club: Int?
        let band: Int
        let sort: String
        let ascending: Bool
    }

    private var ids: [Int]? {
        switch scope {
        case .everyone: nil
        case .squad: squadIds ?? []
        case .shortlist: Array(appModel.shortlist.ids)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                ResearchTableView(table: table, caption: "Loading price trends…", retry: reload) { trends in
                    content(trends)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Price trends")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            squadIds = loadSquadIds()
            await appModel.shortlist.loadIfNeeded()
        }
        .task(id: Options(ids: ids, position: position, club: club, band: band, sort: sort, ascending: ascending)) {
            await load()
        }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.marketRepository.trends(position: position, club: club, band: band, ids: ids,
                                                          sort: sort, ascending: ascending))
    }

    /// Your last published squad, from the saved Team tab.
    private func loadSquadIds() -> [Int]? {
        guard let entryId, let team = appModel.teamRepository.team(entryId: entryId).cached()?.value,
              let picks = team.snapshot?.picks, !picks.isEmpty else { return nil }
        return picks.map(\.playerId)
    }

    // MARK: Content

    private func content(_ t: MarketTrends) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            MarketFigures(items: [
                ResearchFigure(label: "Risers today", value: t.hasDaily ? "\(t.risersCount)" : "Not yet"),
                ResearchFigure(label: "Fallers today", value: t.hasDaily ? "\(t.fallersCount)" : "Not yet"),
                ResearchFigure(label: "Biggest riser", value: t.risers.first.map { name($0, t) } ?? "None"),
                ResearchFigure(label: "Biggest faller", value: t.fallers.first.map { name($0, t) } ?? "None"),
            ])
            if !t.hasDaily {
                Text("Daily history is still being collected. Until there's a snapshot from yesterday, the likelihood uses this gameweek's transfers.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Highlight", selection: $highlight) {
                Text("Up flow").tag(Highlight.up)
                Text("Down flow").tag(Highlight.down)
                Text("Risers").tag(Highlight.risers)
                Text("Fallers").tag(Highlight.fallers)
            }
            .pickerStyle(.segmented)
            highlightList(t)
            tableSection(t)
            Text("The likelihood is the website's approximation of FPL's private price algorithm: net transfers against the player's owner base, 0 to 100 with 50 stable. * means it's worked out from this gameweek's transfers rather than today's.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func highlightList(_ t: MarketTrends) -> some View {
        switch highlight {
        case .up:
            MarketList(title: "Strongest upward flow", rows: t.upFlow) { flowRow($0, t) }
        case .down:
            MarketList(title: "Strongest downward flow", rows: t.downFlow) { flowRow($0, t) }
        case .risers:
            MarketList(title: "Risers today", rows: t.risers, empty: "No price rises recorded yet.") { moveRow($0, t) }
        case .fallers:
            MarketList(title: "Fallers today", rows: t.fallers, empty: "No price falls recorded yet.") { moveRow($0, t) }
        }
    }

    private func tableSection(_ t: MarketTrends) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "All players")
            Picker("Players", selection: $scope) {
                Text("Everyone").tag(Scope.everyone)
                if squadIds != nil { Text("My squad").tag(Scope.squad) }
                Text("Shortlist").tag(Scope.shortlist)
            }
            .pickerStyle(.segmented)
            PositionPicker(position: $position)
            ClubMenu(club: $club)
            Menu {
                Picker("Price", selection: $band) {
                    ForEach(Self.bands.indices, id: \.self) { Text(Self.bands[$0]).tag($0) }
                }
            } label: {
                Label(Self.bands[band], systemImage: "sterlingsign.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Price: \(Self.bands[band])")
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(Self.sorts, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Order", selection: $ascending) {
                    Text("Highest first").tag(false)
                    Text("Lowest first").tag(true)
                }
            } label: {
                Label(sortSummary, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Sort: \(sortSummary)")
            MarketList(title: "\(t.count) players", rows: t.rows,
                       empty: scope == .shortlist ? "Your shortlist is empty, or no one on it matches." : "No players match these filters.",
                       initial: 30) { tableRow($0, t) }
            if t.count > t.rows.count {
                Text("Showing the first \(t.rows.count) of \(t.count). Narrow it with the filters.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
    }

    private var sortSummary: String {
        let label = Self.sorts.first { $0.0 == sort }?.1 ?? sort
        return "\(label), \(ascending ? "lowest" : "highest") first"
    }

    // MARK: Rows

    private func name(_ row: MarketTrends.Row, _ t: MarketTrends) -> String {
        "\(t.player(row.playerId)?.webName ?? "Player") £\(row.price.formatted(.number.precision(.fractionLength(1))))m"
    }

    private func moveRow(_ row: MarketTrends.Row, _ t: MarketTrends) -> some View {
        let player = t.player(row.playerId)
        let change = row.dayPrice ?? 0
        return MarketPlayerRow(
            playerId: row.playerId, player: player,
            details: ["£\(row.price.formatted(.number.precision(.fractionLength(1))))m"],
            trailing: MarketFormat.moneyChange(change),
            trailingColor: MarketFormat.tint(change),
            spoken: "\(player?.webName ?? "Player"), \(MarketFormat.spokenMoney(change)) today, now £\(row.price.formatted(.number.precision(.fractionLength(1))))m"
        )
    }

    private func flowRow(_ row: MarketTrends.Row, _ t: MarketTrends) -> some View {
        let player = t.player(row.playerId)
        return MarketPlayerRow(
            playerId: row.playerId, player: player,
            details: ["£\(row.price.formatted(.number.precision(.fractionLength(1))))m", row.bandLabel],
            trailing: "\(row.likelihood)\(row.estimated ? "*" : "")",
            trailingColor: bandColor(row.band),
            spoken: "\(player?.webName ?? "Player"), likelihood \(row.likelihood) of 100, \(row.bandLabel)\(row.estimated ? ", estimated from this gameweek's transfers" : "")"
        )
    }

    private func tableRow(_ row: MarketTrends.Row, _ t: MarketTrends) -> some View {
        let player = t.player(row.playerId)
        var extra = ["Own \(MarketFormat.percent(row.own))"]
        if let dayOwn = row.dayOwn { extra.append("\(MarketFormat.points(dayOwn, digits: 2)) today") }
        extra.append("net \(MarketFormat.count(row.net, signed: true))")
        if let dayNet = row.dayNet { extra.append("\(MarketFormat.count(dayNet, signed: true)) today") }
        var details = ["£\(row.price.formatted(.number.precision(.fractionLength(1))))m"]
        if let day = row.dayPrice { details.append("\(MarketFormat.moneyChange(day)) today") }
        details.append("\(MarketFormat.moneyChange(row.seasonPrice)) season")
        return MarketPlayerRow(
            playerId: row.playerId, player: player, details: details,
            extra: extra.joined(separator: " · "),
            trailing: row.bandLabel + (row.estimated ? "*" : ""),
            trailingColor: bandColor(row.band),
            spoken: ([player?.webName ?? "Player", row.bandLabel, "likelihood \(row.likelihood) of 100"] + details + extra).joined(separator: ", ")
        )
    }

    private func bandColor(_ band: MarketTrends.Row.Band) -> Color {
        switch band {
        case .rising, .watchUp: ToolkitColor.positive
        case .falling, .watchDown: ToolkitColor.error
        case .stable, .unknown: ToolkitColor.secondaryText
        }
    }
}
