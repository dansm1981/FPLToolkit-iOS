import SwiftUI

/// The website's fixture ticker (/forecast): every club's run, sorted by its total. Same controls:
/// weeks, Fuzzy, the fixture model, sorting by the run or one gameweek, and your squad's clubs.
/// At accessibility sizes it reads club by club.
struct FixtureTickerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let entryId: Int?

    @AppStorage(FixtureView.modelKey) private var model = FixtureView.Model.xfdr
    @AppStorage(FixtureView.lensKey) private var lens = FixtureView.Lens.position
    @AppStorage("research.ticker.horizon") private var horizon = 6
    @AppStorage("research.ticker.fuzzy") private var fuzzy = false
    @State private var sort: ResearchTicker.SortKey = .sum
    @State private var hardestFirst = false
    @State private var squadOnly = false
    @State private var squadClubs: [Int]?
    @State private var table = ResearchTable<ResearchTicker>()

    static let horizons = [1, 2, 3, 4, 5, 6, 10, 16, 24]

    private struct Options: Hashable {
        let horizon: Int
        let fuzzy: Bool
        let sort: ResearchTicker.SortKey
        let hardestFirst: Bool
        let clubs: [Int]?
        let view: FixtureView
    }

    private var options: Options {
        Options(horizon: horizon, fuzzy: fuzzy && horizon >= 2, sort: sort, hardestFirst: hardestFirst,
                clubs: squadOnly ? squadClubs : nil, view: FixtureView(model: model, lens: lens))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                controls
                ResearchTableView(table: table, caption: "Loading every club's run…", retry: reload) { ticker in
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        if typeSize.isAccessibilitySize {
                            clubList(ticker)
                        } else {
                            grid(ticker)
                        }
                        notes(ticker)
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Fixture ticker")
        .navigationBarTitleDisplayMode(.inline)
        .task { squadClubs = loadSquadClubs() }
        .task(id: options) { await load(options) }
        .onChange(of: horizon) { sort = .sum }
    }

    private func reload() { Task { await load(options) } }

    private func load(_ options: Options) async {
        await table.load(appModel.researchRepository.ticker(
            horizon: options.horizon, fuzzy: options.fuzzy, sort: options.sort,
            hardestFirst: options.hardestFirst, clubs: options.clubs, view: options.view))
    }

    /// The clubs in your last published squad, from the saved Team tab.
    private func loadSquadClubs() -> [Int]? {
        guard let entryId, let team = appModel.teamRepository.team(entryId: entryId).cached()?.value,
              let picks = team.snapshot?.picks else { return nil }
        let clubs = Set(picks.compactMap { team.players[String($0.playerId)]?.clubId })
        return clubs.isEmpty ? nil : clubs.sorted()
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            menusLayout {
                weeksMenu
                sortMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ResearchFixtureMenu(model: $model, lens: $lens, clubs: true)
            if horizon >= 2 {
                Toggle("Fuzzy", isOn: $fuzzy)
                    .font(.subheadline.weight(.semibold))
                    .tint(ToolkitColor.accent)
                    .frame(minHeight: 44)
                    .accessibilityHint("Judges each club on its easier half of the run")
            }
            if squadClubs != nil {
                Picker("Clubs", selection: $squadOnly) {
                    Text("All clubs").tag(false)
                    Text("My squad's clubs").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, ToolkitSpace.sm)
            }
        }
    }

    /// Side by side, or stacked from the larger text sizes.
    private var menusLayout: AnyLayout {
        typeSize >= .xLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: ToolkitSpace.lg))
    }

    private var weeksMenu: some View {
        Menu {
            Picker("Gameweeks", selection: $horizon) {
                ForEach(Self.horizons, id: \.self) { Text($0 == 1 ? "Next gameweek" : "Next \($0) gameweeks").tag($0) }
            }
        } label: {
            Label(horizon == 1 ? "1 gameweek" : "\(horizon) gameweeks", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Gameweeks: \(horizon)")
    }

    private var sortMenu: some View {
        let gws = (table.current?.loaded ?? table.previous)?.value.gws ?? []
        return Menu {
            Picker("Sort by", selection: $sort) {
                Text("Run total").tag(ResearchTicker.SortKey.sum)
                ForEach(gws, id: \.self) { Text("GW\($0)").tag(ResearchTicker.SortKey.gw($0)) }
            }
            Picker("Order", selection: $hardestFirst) {
                Text("Easiest first").tag(false)
                Text("Hardest first").tag(true)
            }
        } label: {
            Label(sortSummary, systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Sort: \(sortSummary)")
    }

    private var sortSummary: String {
        let key = switch sort {
        case .sum: "Run total"
        case .gw(let gw): "GW\(gw)"
        }
        return "\(key), \(hardestFirst ? "hardest" : "easiest") first"
    }

    // MARK: Grid

    @ScaledMetric(relativeTo: .caption) private var clubWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var cellWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .caption) private var fixtureHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 22

    private func rowHeight(_ row: ResearchTicker.Row) -> CGFloat {
        let most = max(1, row.cells.map(\.fixtures.count).max() ?? 1)
        return fixtureHeight * CGFloat(most) + CGFloat(most - 1) * 2
    }

    /// The club column stays put; the weeks scroll sideways beside it.
    private func grid(_ ticker: ResearchTicker) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Club")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(width: clubWidth, height: headerHeight, alignment: .leading)
                    .accessibilityHidden(true)
                ForEach(ticker.rows) { row in
                    clubCell(row)
                        .frame(width: clubWidth, height: rowHeight(row), alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spoken(row, ticker))
                }
            }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        ForEach(ticker.gws, id: \.self) { gw in
                            Text("GW\(gw)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ToolkitColor.primaryText)
                                .frame(width: cellWidth, height: headerHeight)
                        }
                    }
                    ForEach(ticker.rows) { row in
                        HStack(spacing: 3) {
                            ForEach(row.cells, id: \.gw) { cell in
                                cellView(cell)
                                    .frame(width: cellWidth, height: rowHeight(row))
                            }
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func clubCell(_ row: ResearchTicker.Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(appModel.club(row.clubId)?.shortName ?? "?")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ToolkitColor.primaryText)
            Text("Σ \(row.sumDisplay)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func cellView(_ cell: ResearchTicker.Cell) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        if cell.blank {
            Text("—")
                .font(.caption.weight(.bold))
                .foregroundStyle(ToolkitColor.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ToolkitColor.raised, in: shape)
                .opacity(cell.ignored ? 0.4 : 1)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(cell.fixtures.enumerated()), id: \.offset) { _, fixture in
                    VStack(spacing: 0) {
                        Text(opponent(fixture))
                            .font(.caption2.weight(.semibold))
                        Text(fixture.display)
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                    .strikethrough(cell.ignored)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(fixture.band.map(DifficultyColor.text) ?? ToolkitColor.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(fixture.band.map(DifficultyColor.fill) ?? ToolkitColor.raised, in: shape)
                }
            }
            .opacity(cell.ignored ? 0.4 : 1)
        }
    }

    /// "NEW (H)", as the website writes it.
    private func opponent(_ fixture: ResearchTicker.Fixture) -> String {
        let name = fixture.opponentClubId.flatMap { appModel.club($0)?.shortName } ?? "TBC"
        return "\(name) (\(fixture.home ? "H" : "A"))"
    }

    // MARK: Club by club (accessibility sizes)

    private func clubList(_ ticker: ResearchTicker) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            ForEach(ticker.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(appModel.club(row.clubId)?.name ?? "Club") · total \(row.sumDisplay)")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(row.cells.map { weekText($0) }.joined(separator: "\n"))
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(row, ticker))
            }
        }
    }

    // MARK: Words

    private func weekText(_ cell: ResearchTicker.Cell) -> String {
        let games = cell.blank ? "no game" : cell.fixtures.map { "\(opponent($0)) \($0.display)" }.joined(separator: ", ")
        return "GW\(cell.gw): \(games)\(cell.ignored ? " (left out)" : "")"
    }

    private func spoken(_ row: ResearchTicker.Row, _ ticker: ResearchTicker) -> String {
        var parts = ["\(appModel.club(row.clubId)?.name ?? "Club"), run total \(row.sumDisplay)"]
        for cell in row.cells {
            if cell.blank {
                parts.append("GW\(cell.gw) no game")
            } else {
                let games = cell.fixtures.map { fixture -> String in
                    let name = fixture.opponentClubId.flatMap { appModel.club($0)?.name } ?? "opponent to be confirmed"
                    return "\(name) \(fixture.home ? "at home" : "away") \(fixture.display)"
                }
                parts.append("GW\(cell.gw) " + games.joined(separator: " and "))
            }
            if cell.ignored { parts[parts.count - 1] += ", left out in Fuzzy mode" }
        }
        return parts.joined(separator: ", ")
    }

    private func notes(_ ticker: ResearchTicker) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
            Text(modelNote(ticker))
            Text("Each week adds up its fixtures, so a double counts twice and a blank adds nothing. Lower totals are easier runs.")
            if ticker.fuzzy && ticker.dropCount > 0 {
                Text("Fuzzy: the \(ticker.dropCount) hardest \(ticker.dropCount == 1 ? "week is" : "weeks are") left out of each total (faded), and a blank counts as the hardest.")
            }
        }
        .font(.footnote)
        .foregroundStyle(ToolkitColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func modelNote(_ ticker: ResearchTicker) -> String {
        let usesMarket = ticker.rows.contains { $0.cells.contains { $0.fixtures.contains { $0.source == "market" } } }
        guard usesMarket else { return "Difficulty is FPL's own, 1 (easiest) to 5." }
        let view = switch ticker.lens {
        case "attack": "attack (how hard it is to score)"
        case "clean_sheet": "clean sheet (how hard it is to keep one)"
        default: "match"
        }
        return "Difficulty is xFDR, our model from bookmaker prices and results, read for \(view), 1.0 (easiest) to 5.0."
    }
}
