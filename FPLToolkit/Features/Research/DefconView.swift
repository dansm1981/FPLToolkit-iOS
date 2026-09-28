import Charts
import SwiftUI

/// The website's DEFCON hub (/defensive-contributions): the season's figures, the leaderboard, the
/// reliability map, the most reliable hitters, team leakiness and tough-fixture DEFCON. The server
/// summarises the season's fixture rows with the website's code.
struct DefconView: View {
    @Environment(AppModel.self) private var appModel
    @State private var position: Position?
    @State private var minStarts = 1
    @State private var maxPrice = 0.0
    @State private var sort = "hits"
    @State private var mapPosition: Position?
    @State private var mapMinStarts = 1
    @State private var table = ResearchTable<Defcon>()

    static let intro = "Defenders earn 2 points for 10+ defensive contributions (clearances, blocks, interceptions, tackles, recoveries) in a match; midfielders and forwards need 12+. Goalkeepers are not eligible."

    static let positionColours: KeyValuePairs<String, Color> = [
        "DEF": ToolkitColor.information, "MID": ToolkitColor.positive, "FWD": ToolkitColor.error,
    ]

    /// The key's shapes, matching the chart's symbols (so position isn't told by colour alone).
    static let positionSymbols: [String: String] = ["DEF": "circle.fill", "MID": "xmark", "FWD": "triangle.fill"]

    private struct Options: Hashable {
        let position: Position?
        let minStarts: Int
        let maxPrice: Double
        let sort: String
        let mapPosition: Position?
        let mapMinStarts: Int
    }

    private var options: Options {
        Options(position: position, minStarts: minStarts, maxPrice: maxPrice, sort: sort,
                mapPosition: mapPosition, mapMinStarts: mapMinStarts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                EliteNote(text: Self.intro)
                ResearchTableView(table: table, caption: "Loading DEFCON…", retry: reload) { hub in
                    content(hub)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("DEFCON")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: options) { await load() }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.researchRepository.defcon(
            position: position, minStarts: minStarts, maxPrice: maxPrice, sort: sort,
            mapPosition: mapPosition, mapMinStarts: mapMinStarts))
    }

    private func content(_ hub: Defcon) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            EliteStats(stats: hub.stats)
            leaderboard(hub)
            reliability(hub)
            mostReliable(hub)
            MarketList(title: "Team leakiness", rows: hub.leakiness, initial: 20) { leakRow($0) }
            EliteNote(text: "How often opponents hit DEFCON against each club. Target defenders and defensive midfielders facing the leakiest teams.")
            MarketList(title: "Tough-fixture DEFCON", rows: hub.tough, empty: "No tough-fixture starts recorded yet.") { row in
                let player = hub.player(row.playerId)
                let starts = "\(row.toughStarts) tough start\(row.toughStarts == 1 ? "" : "s")"
                MarketPlayerRow(
                    playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
                    extra: starts, trailing: row.hitRate,
                    spoken: [EliteFormat.name(player, row.playerId), "hit rate \(row.hitRate) against FDR 4 to 5", starts]
                        .joined(separator: ", ")
                )
            }
            EliteNote(text: "Hit rate in starts against FDR 4–5 opposition: players who rack up defensive actions even when their team is under pressure.")
        }
    }

    // MARK: Leaderboard

    private func leaderboard(_ hub: Defcon) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "DEFCON leaderboard")
            OutfieldPicker(position: $position)
            HStack(spacing: ToolkitSpace.lg) {
                Menu {
                    Picker("Minimum starts", selection: $minStarts) {
                        ForEach(hub.options.minStarts, id: \.self) { Text("\($0)+ start\($0 == 1 ? "" : "s")").tag($0) }
                    }
                } label: {
                    Label("\(minStarts)+ start\(minStarts == 1 ? "" : "s")", systemImage: "figure.run")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Minimum starts: \(minStarts)")
                Menu {
                    Picker("Maximum price", selection: $maxPrice) {
                        ForEach(hub.options.prices) { Text($0.label).tag($0.value) }
                    }
                } label: {
                    Label(priceLabel(hub), systemImage: "sterlingsign.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Price: \(priceLabel(hub))")
            }
            Menu {
                Picker("Rank by", selection: $sort) {
                    ForEach(hub.options.sorts) { Text($0.label).tag($0.key) }
                }
            } label: {
                Label("Rank by \(sortLabel(hub))", systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Rank by \(sortLabel(hub))")
            MarketList(title: "\(hub.leaderboard.count) players", rows: hub.leaderboard,
                       empty: "No players match these filters yet — the season is young.", initial: 20) { leaderRow($0, hub) }
            EliteNote(text: "Every eligible player ranked by DEFCON output. Hit rate is measured in starts (60+ minutes).")
        }
    }

    private func priceLabel(_ hub: Defcon) -> String {
        hub.options.prices.first { $0.value == maxPrice }?.label ?? "Any price"
    }

    private func sortLabel(_ hub: Defcon) -> String {
        hub.options.sorts.first { $0.key == sort }?.label ?? "DEFCON hits"
    }

    private func nextText(_ next: Defcon.Next?) -> String? {
        guard let next else { return nil }
        let club = appModel.club(next.opponentClubId)?.shortName ?? "?"
        return "Next \(club) (\(next.home ? "H" : "A")) · FDR \(next.fdr.map(String.init) ?? "?")"
    }

    private func leaderRow(_ row: Defcon.Row, _ hub: Defcon) -> some View {
        let player = hub.player(row.playerId)
        let figures = "\(row.startHits)/\(row.starts) hits · DC/90 \(row.dcPer90) · CBIT/90 \(row.cbitPer90) · \(row.minutes) mins"
        let next = nextText(row.next)
        let spokenNext = row.next.map { n in
            "next \(appModel.club(n.opponentClubId)?.name ?? "opponent") \(n.home ? "at home" : "away"), difficulty \(n.fdr.map(String.init) ?? "unknown")"
        }
        let spoken = [EliteFormat.name(player, row.playerId), "hit rate \(row.hitRate)",
                      "\(row.startHits) hits in \(row.starts) starts", "\(row.dcPer90) defensive contributions per 90",
                      "\(row.cbitPer90) CBIT per 90", "\(row.minutes) minutes", spokenNext, EliteFormat.price(player)]
            .compactMap { $0 }.joined(separator: ", ")
        return MarketPlayerRow(
            playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            extra: [figures, next].compactMap { $0 }.joined(separator: "\n"), trailing: row.hitRate, spoken: spoken
        )
    }

    // MARK: Reliability map

    private func reliability(_ hub: Defcon) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "DEFCON reliability map")
            OutfieldPicker(position: $mapPosition)
            Menu {
                Picker("Minimum starts", selection: $mapMinStarts) {
                    ForEach(hub.options.minStarts, id: \.self) { Text("\($0)+ start\($0 == 1 ? "" : "s")").tag($0) }
                }
            } label: {
                Label("\(mapMinStarts)+ start\(mapMinStarts == 1 ? "" : "s")", systemImage: "figure.run")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Map minimum starts: \(mapMinStarts)")
            if hub.map.points.isEmpty {
                EliteNote(text: "No players match these filters — try lowering the starts minimum.")
            } else {
                chart(hub)
                legend
            }
            MarketList(title: "Most reliable · hit rate in starts", rows: hub.map.top, initial: 12) { row in
                let player = hub.player(row.playerId)
                MarketPlayerRow(
                    playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
                    extra: "\(row.hits)/\(row.starts) hits", trailing: row.hitRate,
                    spoken: [EliteFormat.name(player, row.playerId), "hit rate \(row.hitRate)", "\(row.hits) hits in \(row.starts) starts"]
                        .joined(separator: ", ")
                )
            }
            EliteNote(text: "Hit rate in starts against defensive contributions per 90. The dashed lines mark 50% and the median DC per 90; the larger points are the most reliable, listed here.")
        }
    }

    private func chart(_ hub: Defcon) -> some View {
        Chart {
            RuleMark(x: .value("Half", 50))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(ToolkitColor.secondaryText)
            RuleMark(y: .value("Median DC per 90", hub.map.medianDcPer90))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(ToolkitColor.secondaryText)
            // The six the website means to name are drawn larger; the list below names them (at the
            // top of the chart the names would sit on top of each other).
            ForEach(hub.map.points) { point in
                PointMark(x: .value("Hit rate", point.hitRate), y: .value("DC per 90", point.dcPer90))
                    .symbol(by: .value("Position", point.position.rawValue))
                    .foregroundStyle(by: .value("Position", point.position.rawValue))
                    .symbolSize(point.labelled ? 90 : 36)
            }
        }
        .chartForegroundStyleScale(Self.positionColours)
        .chartSymbolScale(["DEF": .circle, "MID": .cross, "FWD": .triangle] as KeyValuePairs<String, BasicChartSymbolShape>)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...100, range: .plotDimension(padding: 12))
        .chartXAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                // Centred on the value, so 100 doesn't run into the axis on the right.
                AxisValueLabel(anchor: .top) { Text("\(value.as(Int.self) ?? 0)") }
            }
        }
        .chartXAxisLabel("Hit rate in starts, %")
        .chartYAxisLabel("DC per 90")
        .frame(height: 300)
        // One element: its figures are in the list below.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reliability chart of \(hub.map.points.count) players: hit rate in starts against defensive contributions per 90. The most reliable are listed below.")
    }

    private var legend: some View {
        HStack(spacing: ToolkitSpace.md) {
            ForEach(Array(Self.positionColours), id: \.key) { key, colour in
                HStack(spacing: 4) {
                    Image(systemName: Self.positionSymbols[key] ?? "circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(colour)
                    Text(key)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Most reliable, leakiness

    private func mostReliable(_ hub: Defcon) -> some View {
        let r = hub.mostReliable
        return VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Who reaches DEFCON most reliably?")
            Text(r.answer)
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if r.smallSample {
                Label("Small sample: fewer than four starts so far.", systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ToolkitColor.warning)
            }
            MarketList(title: "The most reliable", rows: r.rows, empty: "No hits in starts yet.") { row in
                let player = hub.player(row.playerId)
                MarketPlayerRow(
                    playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
                    extra: "\(row.startHits) of \(row.starts) starts · DC/90 \(row.dcPer90)", trailing: row.hitRate,
                    spoken: [EliteFormat.name(player, row.playerId), "hit rate \(row.hitRate)", "\(row.startHits) of \(row.starts) starts",
                             "\(row.dcPer90) defensive contributions per 90"].joined(separator: ", ")
                )
            }
            EliteNote(text: r.coverage)
        }
    }

    private func leakRow(_ leak: Defcon.Leak) -> some View {
        let club = appModel.club(leak.clubId)
        return TextFigureRow(
            title: club?.name ?? "Club \(leak.clubId)",
            lines: ["Defenders: \(leak.defHitRate) hit · avg DC \(leak.avgDcVsDef)",
                    "Midfielders and forwards: \(leak.attackHitRate) hit · avg DC \(leak.avgDcVsAttack)"],
            spoken: "\(club?.name ?? "Club"): defenders hit DEFCON \(leak.defHitRate) of the time against them, averaging \(leak.avgDcVsDef); midfielders and forwards \(leak.attackHitRate), averaging \(leak.avgDcVsAttack)"
        )
    }
}

/// All outfield positions, or one: DEFCON has no goalkeepers.
struct OutfieldPicker: View {
    @Binding var position: Position?

    var body: some View {
        Picker("Position", selection: $position) {
            Text("All").tag(Position?.none)
            ForEach([Position.def, .mid, .fwd], id: \.self) { Text($0.rawValue).tag(Position?.some($0)) }
        }
        .pickerStyle(.segmented)
    }
}
