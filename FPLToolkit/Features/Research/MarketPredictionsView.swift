import SwiftUI

/// The website's price change predictions: FPL's own figures for who is closest to a rise or a
/// fall tonight, with the next three nights. The app's Watch tab uses the same figures.
struct MarketPredictionsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var club: Int?
    @State private var position: Position?
    @State private var maxPrice: Int?
    @State private var falls = false
    @State private var table = ResearchTable<MarketPredictions>()

    static let maxPrices = [5, 6, 7, 8, 9, 10, 12]

    private struct Options: Hashable {
        let club: Int?
        let position: Position?
        let maxPrice: Int?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                ResearchTableView(table: table, caption: "Loading predictions…", retry: reload) { predictions in
                    content(predictions)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Predictions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Options(club: club, position: position, maxPrice: maxPrice)) { await load() }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.marketRepository.predictions(club: club, position: position, maxPrice: maxPrice))
    }

    private func content(_ p: MarketPredictions) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            MarketFigures(items: [
                ResearchFigure(label: "Players tracked", value: "\(p.tracked)"),
                ResearchFigure(label: "Heading up", value: "\(p.headingUp)"),
                ResearchFigure(label: "Heading down", value: "\(p.headingDown)"),
                ResearchFigure(label: "Locked", value: "\(p.locked)", hint: "Frozen by FPL"),
            ])
            filters
            Picker("List", selection: $falls) {
                Text("Nearest a rise (\(p.risersCount))").tag(false)
                Text("Nearest a fall (\(p.fallersCount))").tag(true)
            }
            .pickerStyle(.segmented)
            let rows = falls ? p.fallers : p.risers
            let total = falls ? p.fallersCount : p.risersCount
            MarketList(title: falls ? "Closest to a fall" : "Closest to a rise", rows: rows,
                       empty: "No players match these filters.", initial: 25) { row($0, p) }
            if total > rows.count {
                Text("Showing the first \(rows.count) of \(total).")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            Text("Progress runs to 100% (or −100%), when the player rises (or falls) at the nightly update, about 01:30 UK time. The hourly rate is how fast it's moving. The next three nights are FPL's own projections, with its likelihood out of 5. Calibrating figures aren't yet treated as reliable by FPL, and a locked player can't change price until the time shown.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 0) {
            PositionPicker(position: $position)
                .padding(.bottom, ToolkitSpace.xs)
            ClubMenu(club: $club)
            Menu {
                Picker("Price", selection: $maxPrice) {
                    Text("No price limit").tag(Int?.none)
                    ForEach(Self.maxPrices, id: \.self) { Text("Up to £\($0).0m").tag(Int?.some($0)) }
                }
            } label: {
                Label(maxPrice.map { "Up to £\($0).0m" } ?? "No price limit", systemImage: "sterlingsign.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Price: \(maxPrice.map { "up to £\($0) million" } ?? "no limit")")
        }
    }

    private func row(_ row: MarketPredictions.Row, _ p: MarketPredictions) -> some View {
        let player = p.player(row.playerId)
        let nights = zip(["Tonight", "Tomorrow", "Night 3"], row.nights).map { label, night in
            "\(label) \(night.display)" + (night.likelihood.map { " (\($0)/5)" } ?? "")
        }
        let status = row.lockedDisplay.map { "Locked to \($0)" } ?? (row.calibrating ? "Calibrating" : nil)
        var details = ["£\(row.price.formatted(.number.precision(.fractionLength(1))))m", "\(MarketFormat.percent(row.own)) owned"]
        if let hourly = row.hourly { details.append("\(hourly.formatted())/h") }
        return MarketPlayerRow(
            playerId: row.playerId, player: player, details: details,
            extra: nights.joined(separator: " · "),
            trailing: row.progressDisplay,
            trailingColor: row.progress >= 0 ? ToolkitColor.positive : ToolkitColor.error,
            badge: status,
            spoken: ([player?.webName ?? "Player", "progress \(row.progressDisplay)"] + details + nights + [status].compactMap { $0 })
                .joined(separator: ", ")
        )
    }
}
