import Charts
import SwiftUI

/// Lines over the season, one per player. VoiceOver reads it as one element saying what it shows;
/// each player's row below reads out his line week by week.
struct EliteLineChart: View {
    struct Line: Identifiable {
        let id: Int
        let label: String
        let values: [Double?]
        let colour: Color
    }

    let weeks: [Int]
    let lines: [Line]
    /// "%" for shares of the cohort, "pp" for the elite edge.
    var unit = "%"

    static let colours: [Color] = [
        ToolkitColor.accent, ToolkitColor.information, ToolkitColor.positive, .pink,
        .purple, .orange, .teal, ToolkitColor.error,
    ]

    static func colour(_ index: Int) -> Color { colours[index % colours.count] }

    var body: some View {
        Chart {
            ForEach(lines) { line in
                ForEach(points(line), id: \.week) { point in
                    LineMark(x: .value("Gameweek", point.week), y: .value("Share", point.value),
                             series: .value("Player", line.label))
                        .foregroundStyle(line.colour)
                    PointMark(x: .value("Gameweek", point.week), y: .value("Share", point.value))
                        .foregroundStyle(line.colour)
                        .symbolSize(20)
                }
            }
        }
        .chartLegend(.hidden)
        // Padding at the ends, so the first and last weeks' labels fit.
        .chartXScale(domain: (weeks.first ?? 1)...max(weeks.last ?? 1, (weeks.first ?? 1) + 1),
                     range: .plotDimension(padding: 16))
        .chartXAxis {
            AxisMarks(values: weeks) { value in
                AxisGridLine()
                // Centred on the week, so the last label doesn't run into the percentages.
                AxisValueLabel(anchor: .top) { Text("GW\(value.as(Int.self) ?? 0)") }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { Text("\((value.as(Double.self) ?? 0).formatted(.number.precision(.fractionLength(0))))\(unit)") }
            }
        }
        .frame(height: 240)
        // One element, not the chart's own tree (building that for every mark is slow).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        let span = weeks.count > 1 ? "GW\(weeks.first ?? 1) to GW\(weeks.last ?? 1)" : "GW\(weeks.first ?? 1)"
        let count = lines.count == 1 ? "1 player" : "\(lines.count) players"
        return "Chart, \(span), \(count). Each player's figures are listed below."
    }

    private func points(_ line: Line) -> [(week: Int, value: Double)] {
        zip(weeks, line.values).compactMap { week, value in value.map { (week, $0) } }
    }

    /// "GW1 30%, GW2 45%": a line for VoiceOver. Weeks with no figure are left out.
    nonisolated static func spoken(weeks: [Int], values: [Double?], unit: String = "%") -> String {
        zip(weeks, values).compactMap { week, value in
            value.map { "GW\(week) \($0.formatted(.number.precision(.fractionLength(0...1))))\(unit)" }
        }.joined(separator: ", ")
    }
}

/// A coloured key dot, matching a chart line.
private struct KeyDot: View {
    let colour: Color

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

/// A player whose elite ownership moved: the change on the right, where he is now below.
struct EliteMoverRowView: View {
    let row: EliteMoverRow
    let player: PlayerSummary?
    /// "this gameweek", "over three gameweeks".
    let span: String

    var body: some View {
        let spoken = [EliteFormat.name(player, row.playerId), "\(row.change.spoken) \(span)",
                      "now \(row.now) of elite managers", EliteFormat.price(player)].compactMap { $0 }.joined(separator: ", ")
        MarketPlayerRow(
            playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            extra: "now \(row.now)", trailing: row.change.shown, trailingColor: MarketFormat.tint(row.change.value),
            spoken: spoken
        )
    }
}

/// A plain row of figures that doesn't open anything: a gameweek in a season table.
private struct EliteTableRow: View {
    let title: String
    let lines: [String]
    /// The whole row for VoiceOver.
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, ToolkitSpace.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: - Template race

/// The website's Elite Template Race (/elite/race): the template players and the challengers
/// closing in, by position, over the season.
struct EliteRaceView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var position: Position?
    @State private var table = ResearchTable<ElitePage<EliteRace>>()

    private struct Options: Hashable {
        let gw: Int?
        let position: Position?
    }

    var body: some View {
        EliteScreen(title: "Elite template race", caption: "Loading the race…", table: table, gw: $gw,
                    retry: reload) {
            PositionPicker(position: $position)
        } content: { page, race in
            content(page, race)
        }
        .task(id: Options(gw: gw, position: position)) { await load() }
    }

    private func reload() { Task { await load() } }
    private func load() async { await table.load(appModel.eliteRepository.race(gw: gw, position: position)) }

    private func content(_ page: ElitePage<EliteRace>, _ race: EliteRace) -> some View {
        let lines = race.contenders.enumerated().map { index, c in
            EliteLineChart.Line(id: c.playerId, label: EliteFormat.name(page.player(c.playerId), c.playerId),
                                values: c.series.map { Optional($0) }, colour: EliteLineChart.colour(index))
        }
        return VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Elite ownership race · \(race.title)")
                EliteLineChart(weeks: race.weeks, lines: lines)
            }
            MarketList(title: "Standings", rows: Array(race.contenders.enumerated().map { Indexed(index: $0, value: $1) }),
                       initial: 10) { item in
                standing(item.value, index: item.index, page: page, weeks: race.weeks)
            }
            EliteNote(text: "Current elite ownership with the three-gameweek change, and each player's ownership band. The chart follows the season from GW1.")
        }
    }

    private func standing(_ c: EliteRace.Contender, index: Int, page: ElitePage<EliteRace>, weeks: [Int]) -> some View {
        let player = page.player(c.playerId)
        let season = EliteLineChart.spoken(weeks: weeks, values: c.series.map { Optional($0) })
        let spoken = [EliteFormat.name(player, c.playerId), "\(c.owned.display) of elite managers", c.band,
                      "\(c.change.spoken) over three gameweeks", "season: \(season)"].joined(separator: ", ")
        return HStack(spacing: ToolkitSpace.sm) {
            KeyDot(colour: EliteLineChart.colour(index))
            MarketPlayerRow(
                playerId: c.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
                extra: "\(c.band) · \(c.change.shown) over 3 GWs", trailing: c.owned.display, spoken: spoken
            )
        }
    }
}

/// An item and its place in a list, for rows that need their colour.
struct Indexed<Value: Identifiable>: Identifiable {
    let index: Int
    let value: Value
    var id: Value.ID { value.id }
}

// MARK: - Movers

/// The website's Elite Movers (/elite/movers): the sharpest ownership swings, first-time picks,
/// and every template entry and exit.
struct EliteMoversView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var table = ResearchTable<ElitePage<EliteMovers>>()

    var body: some View {
        EliteScreen(title: "Elite movers", caption: "Loading elite movers…", table: table, gw: $gw,
                    retry: reload) { page, m in
            content(page, m)
        }
        .task(id: gw) { await table.load(appModel.eliteRepository.movers(gw: gw)) }
    }

    private func reload() { Task { await table.load(appModel.eliteRepository.movers(gw: gw)) } }

    private func content(_ page: ElitePage<EliteMovers>, _ m: EliteMovers) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            EliteStats(stats: m.stats)
            MarketList(title: "Biggest 1 GW risers · GW\(page.gw)", rows: m.risers, empty: "No gains this gameweek.") {
                EliteMoverRowView(row: $0, player: page.player($0.playerId), span: "this gameweek")
            }
            MarketList(title: "Biggest 3 GW risers", rows: m.risers3, empty: "Not enough history yet.") {
                EliteMoverRowView(row: $0, player: page.player($0.playerId), span: "over three gameweeks")
            }
            MarketList(title: "Biggest fallers", rows: m.fallers, empty: "No drops this gameweek.") {
                EliteMoverRowView(row: $0, player: page.player($0.playerId), span: "this gameweek")
            }
            MarketList(title: "New elite entrants", rows: m.entrants, empty: "No first-time elite picks this gameweek.") {
                EliteMoverRowView(row: $0, player: page.player($0.playerId), span: "this gameweek")
            }
            EliteNote(text: "New entrants are owned by at least one elite manager for the first time this season.")
            MarketList(title: "Template entries and exits", rows: m.bandMoves, empty: "No band changes this gameweek.") { move in
                bandRow(move, page)
            }
        }
    }

    private func bandRow(_ move: EliteMovers.BandMove, _ page: ElitePage<EliteMovers>) -> some View {
        let player = page.player(move.playerId)
        let spoken = [EliteFormat.name(player, move.playerId), move.text, "now \(move.band)", EliteFormat.price(player)]
            .compactMap { $0 }.joined(separator: ", ")
        return MarketPlayerRow(
            playerId: move.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            extra: move.text, trailing: move.band,
            trailingColor: move.direction == "in" ? ToolkitColor.positive : ToolkitColor.error, spoken: spoken
        )
    }
}

// MARK: - Trends

/// The website's Elite Trends (/elite/trends): the cohort's season, gameweek by gameweek, and who
/// they're piling into or abandoning.
struct EliteTrendsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var table = ResearchTable<ElitePage<EliteTrends>>()

    var body: some View {
        EliteScreen(title: "Elite trends", caption: "Loading elite trends…", table: table, gw: $gw,
                    retry: reload) { page, t in
            content(page, t)
        }
        .task(id: gw) { await table.load(appModel.eliteRepository.trends(gw: gw)) }
    }

    private func reload() { Task { await table.load(appModel.eliteRepository.trends(gw: gw)) } }

    private func content(_ page: ElitePage<EliteTrends>, _ t: EliteTrends) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Season shape")
                EliteStats(stats: t.stats)
            }
            MarketList(title: "Gameweek by gameweek", rows: t.rows, initial: 38) { row in
                EliteTableRow(
                    title: "GW\(row.gameweek)",
                    lines: ["Mean \(row.meanPoints) pts · median \(row.medianPoints) · total \(row.medianTotal)",
                            "Rank \(row.medianRank) · top 10k \(row.top10k) · hits \(row.hits) · template \(row.template)"],
                    spoken: "Gameweek \(row.gameweek): mean \(row.meanPoints) points, median \(row.medianPoints), median total \(row.medianTotal), median rank \(row.medianRank), \(row.top10k) inside the top 10k, \(row.hits) took a hit, template strength \(row.template)"
                )
            }
            MarketList(title: "Elite rising", rows: t.rising, empty: "Not enough history yet.") {
                EliteMoverRowView(row: $0, player: page.player($0.playerId), span: "over three gameweeks")
            }
            MarketList(title: "Elite cooling", rows: t.cooling, empty: "Not enough history yet.") {
                EliteMoverRowView(row: $0, player: page.player($0.playerId), span: "over three gameweeks")
            }
            EliteNote(text: "Rising and cooling compare elite ownership with three gameweeks earlier.")
        }
    }
}

// MARK: - Compare

/// The website's Elite Ownership Comparison (/elite/compare): up to eight players' elite
/// ownership, starts, captaincy, edge or overall ownership across the season.
struct EliteCompareView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @AppStorage("eliteCompareIds") private var stored = ""
    @State private var metric = "owned"
    @State private var adding = false
    @State private var table = ResearchTable<ElitePage<EliteCompare>>()

    let entryId: Int?
    static let maxPlayers = 8

    private var ids: [Int] { stored.split(separator: ",").compactMap { Int($0) } }

    private func setIds(_ list: [Int]) { stored = list.prefix(Self.maxPlayers).map(String.init).joined(separator: ",") }

    private struct Options: Hashable {
        let gw: Int?
        let ids: [Int]
    }

    var body: some View {
        EliteScreen(title: "Elite comparison", caption: "Loading the comparison…", table: table, gw: $gw,
                    retry: reload) {
            controls
        } content: { page, c in
            content(page, c)
        }
        .task(id: Options(gw: gw, ids: ids)) { await load() }
        .sheet(isPresented: $adding) {
            AddPlayerSheet(entryId: entryId, chosen: Set(ids), addHint: "Adds to the comparison",
                           chosenHint: "Already in the comparison") { player in
                guard ids.count < Self.maxPlayers, !ids.contains(player.id) else { return }
                setIds(ids + [player.id])
            }
        }
    }

    private func reload() { Task { await load() } }
    private func load() async { await table.load(appModel.eliteRepository.compare(gw: gw, ids: ids)) }

    private var loaded: ElitePage<EliteCompare>? { (table.current?.loaded ?? table.previous)?.value }

    private var metricLabel: String {
        loaded?.body?.metrics.first { $0.key == metric }?.label ?? "Elite ownership"
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                adding = true
            } label: {
                Label(ids.count >= Self.maxPlayers ? "Eight players chosen" : "Add player", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .disabled(ids.count >= Self.maxPlayers)
            .accessibilityHint("Adds a player to the chart, up to eight")
            Menu {
                Picker("Measure", selection: $metric) {
                    ForEach(loaded?.body?.metrics ?? []) { Text($0.label).tag($0.key) }
                }
            } label: {
                Label(metricLabel, systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Measure: \(metricLabel)")
        }
    }

    private func content(_ page: ElitePage<EliteCompare>, _ c: EliteCompare) -> some View {
        let unit = metric == "edge" ? "pp" : "%"
        let lines = c.rows.enumerated().map { index, row in
            EliteLineChart.Line(id: row.playerId, label: EliteFormat.name(page.player(row.playerId), row.playerId),
                                values: row.series.values(metric), colour: EliteLineChart.colour(index))
        }
        return VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            if c.rows.isEmpty {
                EliteNote(text: "Add a player to start the comparison.")
            } else {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    SectionLabel(text: metricLabel)
                    EliteLineChart(weeks: c.weeks, lines: lines, unit: unit)
                }
                MarketList(title: "Players", rows: Array(c.rows.enumerated().map { Indexed(index: $0, value: $1) }),
                           initial: Self.maxPlayers) { item in
                    row(item.value, index: item.index, page: page, weeks: c.weeks, unit: unit)
                }
            }
            EliteNote(text: "Up to eight players, saved on this device. Edge and overall ownership are only known in weeks the cohort owned or traded the player.")
        }
    }

    private func row(_ row: EliteCompare.Row, index: Int, page: ElitePage<EliteCompare>, weeks: [Int], unit: String) -> some View {
        let player = page.player(row.playerId)
        let name = EliteFormat.name(player, row.playerId)
        let season = EliteLineChart.spoken(weeks: weeks, values: row.series.values(metric), unit: unit)
        let spoken = [name, "\(row.now.display) of elite managers", row.band, "\(row.trend.display) over three gameweeks",
                      "\(metricLabel): \(season)"].joined(separator: ", ")
        return HStack(spacing: ToolkitSpace.sm) {
            KeyDot(colour: EliteLineChart.colour(index))
            MarketPlayerRow(
                playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
                extra: "\(row.band) · 3GW \(row.trend.display)", trailing: row.now.display, spoken: spoken
            )
            Button {
                setIds(ids.filter { $0 != row.playerId })
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title3)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(name)")
        }
    }
}

// MARK: - Chips

/// The website's Elite Chip Strategy (/elite/chips): when the cohort plays its chips, and how many
/// it has left.
struct EliteChipsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var table = ResearchTable<ElitePage<EliteChips>>()

    var body: some View {
        EliteScreen(title: "Elite chips", caption: "Loading elite chips…", table: table, gw: $gw,
                    retry: reload) { page, c in
            content(page, c)
        }
        .task(id: gw) { await table.load(appModel.eliteRepository.chips(gw: gw)) }
    }

    private func reload() { Task { await table.load(appModel.eliteRepository.chips(gw: gw)) } }

    private func content(_ page: ElitePage<EliteChips>, _ c: EliteChips) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Chips played in GW\(page.gw)")
                EliteStats(stats: c.played)
            }
            MarketList(title: "Chips still available", rows: c.available) { chip in
                EliteTableRow(title: chip.label, lines: ["\(chip.display) of the cohort still hold it"],
                              spoken: "\(chip.label): \(chip.display) of the cohort still hold it")
            }
            MarketList(title: "Chip timeline", rows: c.timeline, initial: 38) { row in
                let cells = zip(c.labels, row.cells).map { "\($0) \($1)" }
                EliteTableRow(title: "GW\(row.gameweek)", lines: [cells.joined(separator: " · ")],
                              spoken: "Gameweek \(row.gameweek): " + zip(c.labels, row.cells)
                                .map { "\($0) \($1 == "—" ? "none" : $1)" }.joined(separator: ", "))
            }
            EliteNote(text: "The share of the cohort that played each chip in every published gameweek; — means nobody did.")
        }
    }
}

// MARK: - Squad structure

/// The website's Elite Squad Structure (/elite/structure): formations, spend by position, and team
/// value over the season.
struct EliteStructureView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var table = ResearchTable<ElitePage<EliteStructure>>()

    var body: some View {
        EliteScreen(title: "Elite squad structure", caption: "Loading squad structure…", table: table, gw: $gw,
                    retry: reload) { page, s in
            content(page, s)
        }
        .task(id: gw) { await table.load(appModel.eliteRepository.structure(gw: gw)) }
    }

    private func reload() { Task { await table.load(appModel.eliteRepository.structure(gw: gw)) } }

    private func content(_ page: ElitePage<EliteStructure>, _ s: EliteStructure) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Value and shape · GW\(page.gw)")
                EliteStats(stats: s.stats)
            }
            MarketList(title: "Formations", rows: s.formations, empty: "No formation data for this gameweek.") { f in
                EliteTableRow(title: f.formation, lines: ["\(f.display) of the cohort"],
                              spoken: "\(f.formation), \(f.display) of elite managers")
            }
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Spend by position")
                EliteStats(stats: s.spend)
            }
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Premium vs budget")
                EliteStats(stats: s.squad)
            }
            MarketList(title: "Team value over the season", rows: s.timeline, initial: 38) { row in
                EliteTableRow(title: "GW\(row.gameweek)",
                              lines: ["Value \(row.value) · bank \(row.bank) · bench \(row.bench) · \(row.formation)"],
                              spoken: "Gameweek \(row.gameweek): team value \(row.value), bank \(row.bank), bench \(row.bench), most common formation \(row.formation)")
            }
        }
    }
}
