import SwiftUI

/// Research → Expected stats (Dan, 3 Oct 2026; happy-backend-pal#73): the xG league table and
/// players by xG and xA, over the season or the last 5 or 10. FPL's per-match figures (from Opta);
/// no xPts (Dan: xG and xGA only). The server builds both tables.
struct ExpectedStatsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case teams = "Teams", players = "Players"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .teams
    @State private var window: ExpectedWindow = .season

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Tab.allCases) { t in
                        chip(t.rawValue, active: tab == t) { tab = t }
                    }
                }
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(ExpectedWindow.allCases) { w in
                        chip(w.label, active: window == w) { window = w }
                    }
                }
                switch tab {
                case .teams: ExpectedTeamsTable(window: window)
                case .players: ExpectedPlayersTable(window: window)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Expected stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FilterChipLabel(text: text, active: active, menu: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

enum ExpectedText {
    /// "+0.58", "−0.51", "0.00".
    nonisolated static func delta(_ v: Double) -> String {
        let text = abs(v).formatted(.number.precision(.fractionLength(2)))
        return v > 0.004 ? "+\(text)" : v < -0.004 ? "−\(text)" : text
    }

    nonisolated static func two(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(2))) }

    /// Goals against xG in words, for VoiceOver.
    nonisolated static func spokenDelta(_ v: Double, above: String, below: String) -> String {
        abs(v) < 0.005 ? "in line with expected" : "\(two(abs(v))) \(v > 0 ? above : below)"
    }
}

/// A delta beside its figure: green when it's good for the club or player, red when not.
private struct DeltaText: View {
    let value: Double
    /// True when a positive delta is good (goals above xG); false when it's bad (conceded above xGA).
    let positiveIsGood: Bool

    var body: some View {
        let good = positiveIsGood ? value > 0.004 : value < -0.004
        let bad = positiveIsGood ? value < -0.004 : value > 0.004
        Text(ExpectedText.delta(value))
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(good ? ToolkitColor.positive : bad ? ToolkitColor.error : ToolkitColor.secondaryText)
    }
}

// MARK: - Teams

private struct ExpectedTeamsTable: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let window: ExpectedWindow
    @State private var venue: ExpectedVenue = .all
    @State private var sort: Sort = .table
    @State private var table = ResearchTable<ExpectedTeams>()

    enum Sort: String, CaseIterable, Identifiable {
        case table = "Table", xg = "xG", xga = "xGA (fewest)", goalsVsXg = "Goals − xG", againstVsXga = "Conceded − xGA"
        var id: String { rawValue }
    }

    private struct Key: Hashable {
        let window: ExpectedWindow
        let venue: ExpectedVenue
    }

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(ExpectedVenue.allCases) { v in
                Button { venue = v } label: { FilterChipLabel(text: v.label, active: venue == v, menu: false) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(v.label)
                    .accessibilityAddTraits(venue == v ? .isSelected : [])
            }
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                FilterChipLabel(text: "Sort: \(sort.rawValue)", active: false, menu: true)
            }
            .accessibilityLabel("Sort by \(sort.rawValue)")
        }
        ResearchTableView(table: table, caption: "Building the xG table…", retry: reload) { data in
            CardGroup {
                ForEach(Array(sorted(data.rows).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider() }
                    teamRow(row)
                }
            }
            Text("xG and xGA are FPL's per-match figures (from Opta), added up for each club's players, so they differ a little from other models. Goals − xG above zero is finishing above the chances; conceded − xGA below zero is conceding fewer than the chances allowed.\(window == .season ? "" : " Last 5 and 10 count each club's own latest matches\(venue == .all ? "" : " \(venue.label.lowercased())").")")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: Key(window: window, venue: venue)) { await load() }
    }

    private func sorted(_ rows: [ExpectedTeams.Row]) -> [ExpectedTeams.Row] {
        switch sort {
        case .table: rows
        case .xg: rows.sorted { $0.xg > $1.xg }
        case .xga: rows.sorted { $0.xga < $1.xga }
        case .goalsVsXg: rows.sorted { $0.goalsVsXg > $1.goalsVsXg }
        case .againstVsXga: rows.sorted { $0.againstVsXga < $1.againstVsXga }
        }
    }

    private func teamRow(_ r: ExpectedTeams.Row) -> some View {
        let club = appModel.club(r.teamId)
        return VStack(alignment: .leading, spacing: 4) {
            NameFigureRow {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(r.rank)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .frame(minWidth: 22, alignment: .trailing)
                    ClubLabel(clubId: r.teamId, text: club?.name ?? "Club \(r.teamId)", logoSize: 18)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                }
            } details: {
                FactLine("M\(r.played) · W\(r.won) D\(r.drawn) L\(r.lost) · \(r.goals)–\(r.against)")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            } figure: {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(r.points)").font(.headline.monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
                    Text("pts").font(.caption).foregroundStyle(ToolkitColor.secondaryText)
                }
            }
            // At the large sizes xG and xGA always take a line each, so every row scans the same
            // (left to flow, some clubs' figures fit on one line and others don't).
            let stats = typeSize.stacksRows
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(FlowLayout(spacing: 12, lineSpacing: 2))
            stats {
                stat("xG", r.xg, delta: r.goalsVsXg, positiveIsGood: true)
                stat("xGA", r.xga, delta: r.againstVsXga, positiveIsGood: false)
            }
            .padding(.leading, 30)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(r, club: club?.name))
    }

    private func stat(_ label: String, _ value: Double, delta: Double, positiveIsGood: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(ToolkitColor.secondaryText)
            Text(ExpectedText.two(value)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
            DeltaText(value: delta, positiveIsGood: positiveIsGood)
        }
    }

    private func spoken(_ r: ExpectedTeams.Row, club: String?) -> String {
        "\(r.rank), \(club ?? "Club"), \(r.points) points from \(r.played) matches, \(r.won) won, \(r.drawn) drawn, \(r.lost) lost, goals \(r.goals) for \(r.against) against. xG \(ExpectedText.two(r.xg)), goals \(ExpectedText.spokenDelta(r.goalsVsXg, above: "above xG", below: "below xG")). xGA \(ExpectedText.two(r.xga)), conceded \(ExpectedText.spokenDelta(r.againstVsXga, above: "above xGA", below: "below xGA"))"
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.researchRepository.expectedTeams(window: window, venue: venue))
    }
}

// MARK: - Players

private struct ExpectedPlayersTable: View {
    @Environment(AppModel.self) private var appModel
    let window: ExpectedWindow
    @State private var position: Position?
    @State private var club: Int?
    @State private var maxPrice: Double?
    @State private var minMinutes = 0
    @State private var sort: Sort = .xg
    @State private var lowestFirst = false
    @State private var search = ""
    @State private var table = ResearchTable<ExpectedPlayers>()

    enum Sort: String, CaseIterable, Identifiable {
        case xg, xa, xgi, goalsVsXg, assistsVsXa, xg90, xa90, xgi90, goals, assists, minutes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .xg: "xG"
            case .xa: "xA"
            case .xgi: "xGI"
            case .goalsVsXg: "Goals − xG"
            case .assistsVsXa: "Assists − xA"
            case .xg90: "xG per 90"
            case .xa90: "xA per 90"
            case .xgi90: "xGI per 90"
            case .goals: "Goals"
            case .assists: "Assists"
            case .minutes: "Minutes"
            }
        }
    }

    private struct Key: Hashable {
        let window: ExpectedWindow, position: Position?, club: Int?, maxPrice: Double?
        let minMinutes: Int, sort: Sort, lowestFirst: Bool, search: String
    }

    var body: some View {
        PositionPicker(position: $position)
        TextField("Search players", text: $search)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 10))
            .submitLabel(.search)
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Menu {
                Picker("Sort", selection: $sort) { ForEach(Sort.allCases) { Text($0.label).tag($0) } }
                Picker("Order", selection: $lowestFirst) {
                    Text("Highest first").tag(false)
                    Text("Lowest first").tag(true)
                }
            } label: {
                FilterChipLabel(text: "Sort: \(sort.label)\(lowestFirst ? " ↑" : "")", active: false, menu: true)
            }
            .accessibilityLabel("Sort by \(sort.label), \(lowestFirst ? "lowest" : "highest") first")
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
            Menu {
                Picker("Minimum minutes", selection: $minMinutes) {
                    ForEach([0, 90, 180, 270, 450, 900], id: \.self) { Text($0 == 0 ? "Any minutes" : "\($0)+ minutes").tag($0) }
                }
            } label: {
                FilterChipLabel(text: minMinutes == 0 ? "Any minutes" : "\(minMinutes)+ min", active: minMinutes > 0, menu: true)
            }
            .accessibilityLabel("Minimum minutes: \(minMinutes == 0 ? "any" : String(minMinutes))")
        }
        ResearchTableView(table: table, caption: "Adding up xG and xA…", retry: reload) { data in
            if data.rows.isEmpty {
                RivalNote(text: "No players match these filters.")
            } else {
                CardGroup {
                    ForEach(Array(data.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider() }
                        playerRow(row, data: data, rank: index + 1)
                    }
                }
            }
            Text(footnote(data))
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: Key(window: window, position: position, club: club, maxPrice: maxPrice, minMinutes: minMinutes,
                      sort: sort, lowestFirst: lowestFirst, search: search)) {
            // A short pause while typing a search.
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private var clubs: [Bootstrap.Club] {
        (appModel.bootstrap?.value.clubs ?? []).sorted { $0.shortName < $1.shortName }
    }

    @ViewBuilder
    private func playerRow(_ r: ExpectedPlayers.Row, data: ExpectedPlayers, rank: Int) -> some View {
        if let summary = data.player(r.playerId) {
            Button { appModel.router.openPlayer(r.playerId) } label: {
                PlayerListRow(player: summary,
                              detail: Format.unbroken(detail(r)),
                              value: value(r),
                              valueDetail: sort.label,
                              spokenDetail: spoken(r),
                              wrapsDetail: true)
                    .padding(.horizontal, 15)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the player")
        }
    }

    /// "G 5 · xG 4.42 (+0.58) · A 0 · xA 0.53 (−0.53) · 450 min".
    private func detail(_ r: ExpectedPlayers.Row) -> String {
        "G \(r.goals) · xG \(ExpectedText.two(r.xg)) (\(ExpectedText.delta(r.goalsVsXg))) · A \(r.assists) · xA \(ExpectedText.two(r.xa)) (\(ExpectedText.delta(r.assistsVsXa))) · \(r.minutes) min"
    }

    private func value(_ r: ExpectedPlayers.Row) -> String {
        switch sort {
        case .xg: ExpectedText.two(r.xg)
        case .xa: ExpectedText.two(r.xa)
        case .xgi: ExpectedText.two(r.xgi)
        case .goalsVsXg: ExpectedText.delta(r.goalsVsXg)
        case .assistsVsXa: ExpectedText.delta(r.assistsVsXa)
        case .xg90: r.xg90.map(ExpectedText.two) ?? "–"
        case .xa90: r.xa90.map(ExpectedText.two) ?? "–"
        case .xgi90: r.xgi90.map(ExpectedText.two) ?? "–"
        case .goals: "\(r.goals)"
        case .assists: "\(r.assists)"
        case .minutes: "\(r.minutes)"
        }
    }

    private func spoken(_ r: ExpectedPlayers.Row) -> String {
        "\(sort.label) \(value(r)). \(r.goals) goals from \(ExpectedText.two(r.xg)) xG, \(ExpectedText.spokenDelta(r.goalsVsXg, above: "above", below: "below")). \(r.assists) assists from \(ExpectedText.two(r.xa)) xA. \(r.minutes) minutes in \(r.apps) appearances"
    }

    private func footnote(_ data: ExpectedPlayers) -> String {
        var parts: [String] = []
        if data.total > data.rows.count { parts.append("Showing the top \(data.rows.count) of \(data.total) players.") }
        if window != .season, let first = data.gameweeks.last, let last = data.gameweeks.first {
            parts.append("Gameweeks \(first)–\(last).")
        }
        parts.append("FPL's xG and xA (from Opta). Per 90 needs 90 minutes or more.")
        return parts.joined(separator: " ")
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.researchRepository.expectedPlayers(
            window: window, position: position, club: club, maxPrice: maxPrice, minMinutes: minMinutes,
            sort: sort.rawValue, ascending: lowestFirst, search: search))
    }
}
