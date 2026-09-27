import SwiftUI

/// The website's confirmed price changes (/price-changes): one day's risers and fallers, with the
/// days to step through, then the season's biggest movers.
struct MarketChangesView: View {
    @Environment(AppModel.self) private var appModel
    /// nil: the latest day with a change.
    @State private var day: String?
    @State private var table = ResearchTable<MarketChanges>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                dayControls
                ResearchTableView(table: table, caption: "Loading price changes…", retry: reload) { changes in
                    content(changes)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Price changes")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: day) { await load() }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.marketRepository.changes(day: day))
    }

    private var loaded: MarketChanges? { (table.current?.loaded ?? table.previous)?.value }

    // MARK: Days

    private var dayControls: some View {
        let days = loaded?.days ?? []
        let shown = loaded?.day
        let index = shown.flatMap { days.firstIndex(of: $0) }
        return HStack(spacing: ToolkitSpace.sm) {
            Button {
                if let index, index + 1 < days.count { day = days[index + 1] }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(index.map { $0 + 1 >= days.count } ?? true)
            .accessibilityLabel("Earlier day")

            Menu {
                Picker("Day", selection: Binding(get: { shown ?? "" }, set: { day = $0 })) {
                    ForEach(Array(days.enumerated()), id: \.element) { i, d in
                        Text(i == 0 ? "Latest (\(MarketFormat.day(d)))" : MarketFormat.day(d)).tag(d)
                    }
                }
            } label: {
                Label(dayTitle(shown, days: days), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Day: \(dayTitle(shown, days: days))")

            Button {
                if let index, index > 0 { day = days[index - 1] }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(index.map { $0 == 0 } ?? true)
            .accessibilityLabel("Later day")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(ToolkitColor.link)
    }

    private func dayTitle(_ shown: String?, days: [String]) -> String {
        guard let shown else { return "Latest" }
        return shown == days.first ? "Latest · \(MarketFormat.day(shown))" : MarketFormat.day(shown)
    }

    // MARK: Lists

    private func content(_ changes: MarketChanges) -> some View {
        let when = changes.day.map { changes.latest ? "latest" : "on \(MarketFormat.day($0))" } ?? ""
        return VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketList(title: "Price rises · \(changes.risersCount)", rows: changes.risers,
                       empty: "No price rises \(when).", initial: 20) { dayRow($0, changes) }
            MarketList(title: "Price falls · \(changes.fallersCount)", rows: changes.fallers,
                       empty: "No price falls \(when).", initial: 20) { dayRow($0, changes) }
            MarketList(title: "Season risers · \(changes.seasonRisersCount)", rows: changes.seasonRisers,
                       empty: "No rises yet this season.") { seasonRow($0, changes) }
            MarketList(title: "Season fallers · \(changes.seasonFallersCount)", rows: changes.seasonFallers,
                       empty: "No falls yet this season.") { seasonRow($0, changes) }
            Text("Confirmed at FPL's nightly price update, from a daily record of every player's price. Net is this gameweek's transfers in minus out. Lists show up to 50 players.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dayRow(_ row: MarketRow, _ changes: MarketChanges) -> some View {
        let player = changes.player(row.playerId)
        return MarketPlayerRow(
            playerId: row.playerId, player: player,
            details: ["now £\(row.price.formatted(.number.precision(.fractionLength(1))))m", "\(MarketFormat.percent(row.own)) owned"],
            extra: "Net \(MarketFormat.count(row.net, signed: true)) this gameweek",
            trailing: MarketFormat.moneyChange(row.dayPrice),
            trailingColor: MarketFormat.tint(row.dayPrice),
            spoken: "\(player?.webName ?? "Player"), \(MarketFormat.spokenMoney(row.dayPrice)) to £\(row.price.formatted(.number.precision(.fractionLength(1))))m, \(MarketFormat.percent(row.own)) owned, net transfers \(MarketFormat.count(row.net, signed: true))"
        )
    }

    private func seasonRow(_ row: MarketRow, _ changes: MarketChanges) -> some View {
        let player = changes.player(row.playerId)
        return MarketPlayerRow(
            playerId: row.playerId, player: player,
            details: ["now £\(row.price.formatted(.number.precision(.fractionLength(1))))m", "\(MarketFormat.percent(row.own)) owned"],
            trailing: MarketFormat.moneyChange(row.seasonPrice),
            trailingColor: MarketFormat.tint(row.seasonPrice),
            spoken: "\(player?.webName ?? "Player"), \(MarketFormat.spokenMoney(row.seasonPrice)) this season, now £\(row.price.formatted(.number.precision(.fractionLength(1))))m, \(MarketFormat.percent(row.own)) owned"
        )
    }
}
