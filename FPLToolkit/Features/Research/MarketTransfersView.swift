import SwiftUI

/// The website's transfers and ownership hubs: this gameweek's most bought, sold and net; the most
/// owned overall and by position; and the week's biggest ownership moves.
struct MarketTransfersView: View {
    @Environment(AppModel.self) private var appModel
    @State private var ownership = false
    @State private var position = Position.mid
    @State private var table = ResearchTable<MarketTransfers>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                Picker("Show", selection: $ownership) {
                    Text("Transfers").tag(false)
                    Text("Ownership").tag(true)
                }
                .pickerStyle(.segmented)
                ResearchTableView(table: table, caption: "Loading transfers…", retry: reload) { data in
                    if ownership { ownershipContent(data) } else { transfersContent(data) }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Transfers and ownership")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.marketRepository.transfers)
    }

    private func transfersContent(_ d: MarketTransfers) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketList(title: "Most bought" + (d.gw.map { " · GW\($0)" } ?? ""), rows: d.bought, playerOf: { d.player($0.playerId) }) { row in
                transferRow(row, d, figure: MarketFormat.count(row.transfersIn), words: "\(MarketFormat.count(row.transfersIn)) in")
            }
            MarketList(title: "Most sold", rows: d.sold, playerOf: { d.player($0.playerId) }) { row in
                transferRow(row, d, figure: MarketFormat.count(row.transfersOut), words: "\(MarketFormat.count(row.transfersOut)) out")
            }
            MarketList(title: "Net transfers", rows: d.net, playerOf: { d.player($0.playerId) }) { row in
                transferRow(row, d, figure: MarketFormat.count(row.net, signed: true), words: "net \(MarketFormat.count(row.net, signed: true))",
                            tint: row.net > 0 ? ToolkitColor.positive : row.net < 0 ? ToolkitColor.error : ToolkitColor.primaryText)
            }
            Text("This gameweek's transfers so far. Net is in minus out, the clearest sign of price pressure.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func transferRow(_ row: MarketRow, _ d: MarketTransfers, figure: String, words: String,
                             tint: Color = ToolkitColor.primaryText) -> some View {
        let player = d.player(row.playerId)
        let details = ["£\(row.price.formatted(.number.precision(.fractionLength(1))))m", "\(MarketFormat.percent(row.own)) owned"]
        return MarketPlayerRow(
            playerId: row.playerId, player: player, details: details,
            trailing: figure, trailingColor: tint,
            spoken: ([player?.webName ?? "Player", words] + details).joined(separator: ", ")
        )
    }

    private func ownershipContent(_ d: MarketTransfers) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketList(title: "Most owned", rows: d.mostOwned, playerOf: { d.player($0.playerId) }) { ownRow($0, d) }
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                Picker("Position", selection: $position) {
                    ForEach([Position.gk, .def, .mid, .fwd], id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                MarketList(title: "Most owned \(position.plural.lowercased())", rows: d.byPosition[position.rawValue] ?? []) { ownRow($0, d) }
            }
            MarketList(title: "Ownership risers this week", rows: d.ownershipRisers) { weekRow($0, d) }
            MarketList(title: "Ownership fallers this week", rows: d.ownershipFallers) { weekRow($0, d) }
            Text("Ownership is the share of FPL teams that pick the player; the week's change compares with the daily snapshot a week ago.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ownRow(_ row: MarketRow, _ d: MarketTransfers) -> some View {
        let player = d.player(row.playerId)
        let details = ["£\(row.price.formatted(.number.precision(.fractionLength(1))))m", "\(MarketFormat.points(row.weekOwn)) this week"]
        return MarketPlayerRow(
            playerId: row.playerId, player: player, details: details,
            trailing: MarketFormat.percent(row.own),
            spoken: "\(player?.webName ?? "Player"), \(MarketFormat.percent(row.own)) owned, \(MarketFormat.spokenPoints(row.weekOwn)) this week, £\(row.price.formatted(.number.precision(.fractionLength(1))))m"
        )
    }

    private func weekRow(_ row: MarketRow, _ d: MarketTransfers) -> some View {
        let player = d.player(row.playerId)
        return MarketPlayerRow(
            playerId: row.playerId, player: player,
            details: ["\(MarketFormat.percent(row.own)) owned", "£\(row.price.formatted(.number.precision(.fractionLength(1))))m"],
            trailing: MarketFormat.points(row.weekOwn),
            trailingColor: MarketFormat.tint(row.weekOwn),
            spoken: "\(player?.webName ?? "Player"), \(MarketFormat.spokenPoints(row.weekOwn)) this week, now \(MarketFormat.percent(row.own)) owned"
        )
    }
}
