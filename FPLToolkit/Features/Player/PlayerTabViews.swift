import SwiftUI

/// The website's player page tabs as "More" rows on the player sheet. Each opens its own screen and
/// loads only then, so the sheet stays quick.
struct PlayerMoreSection: View {
    let playerId: Int
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "More on \(name)")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(PlayerTab.allCases.enumerated()), id: \.element) { index, tab in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    NavigationLink {
                        PlayerTabDestination(playerId: playerId, name: name, tab: tab)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.md) {
                            Image(systemName: tab.systemImage)
                                .foregroundStyle(ToolkitColor.link)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.title)
                                    .font(.headline)
                                    .foregroundStyle(ToolkitColor.primaryText)
                                Text(tab.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.vertical, ToolkitSpace.xs)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ToolkitSpace.lg)
            .padding(.vertical, ToolkitSpace.xs)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.border, lineWidth: 1))
        }
    }

}

/// One of the player's focused pages (history, form, underlying, fixtures, price, DEFCON,
/// similar players), for pushing from anywhere.
struct PlayerTabDestination: View {
    let playerId: Int
    let name: String
    let tab: PlayerTab

    var body: some View {
        switch tab {
        case .history: PlayerTabScreen(playerId: playerId, name: name, tab: tab, as: PlayerHistoryTab.self) { HistoryTabView(tab: $0) }
        case .form: PlayerTabScreen(playerId: playerId, name: name, tab: tab, as: PlayerFormTab.self) { FormTabView(tab: $0) }
        case .underlying: PlayerTabScreen(playerId: playerId, name: name, tab: tab, as: PlayerUnderlyingTab.self) { UnderlyingTabView(tab: $0) }
        case .fixtures: PlayerTabScreen(playerId: playerId, name: name, tab: tab, as: PlayerFixturesTab.self) { FixturesTabView(tab: $0) }
        case .price: PlayerTabScreen(playerId: playerId, name: name, tab: tab, as: PlayerPriceTab.self) { PriceTabView(tab: $0) }
        case .defensive: PlayerTabScreen(playerId: playerId, name: name, tab: tab, as: PlayerDefensiveTab.self) { DefensiveTabView(tab: $0) }
        case .compare: PlayerTabScreen(playerId: playerId, name: name, tab: tab, as: PlayerCompareTab.self) { CompareTabView(tab: $0) }
        }
    }
}

/// Loads one tab and lays it out (saved copies first, labelled).
private struct PlayerTabScreen<T: Decodable & Sendable, Content: View>: View {
    @Environment(AppModel.self) private var appModel
    let playerId: Int
    let name: String
    let tab: PlayerTab
    let type: T.Type
    let content: (T) -> Content
    @State private var table = ResearchTable<T>()

    init(playerId: Int, name: String, tab: PlayerTab, as type: T.Type, @ViewBuilder content: @escaping (T) -> Content) {
        self.playerId = playerId
        self.name = name
        self.tab = tab
        self.type = type
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                ResearchTableView(table: table, caption: "Loading…", retry: reload) { value in
                    content(value)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("\(name): \(tab.title)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func reload() { Task { await load() } }
    private func load() async { await table.load(appModel.playerRepository.tab(playerId, tab, as: type)) }
}

/// "BRE (A)" or "Brentford, away" for VoiceOver.
private struct Opponent {
    let short: String
    let spoken: String

    @MainActor init(_ appModel: AppModel, clubId: Int?, home: Bool) {
        let club = appModel.club(clubId)
        short = "\(club?.shortName ?? "TBC") (\(home ? "H" : "A"))"
        spoken = "\(club?.name ?? "opponent to be confirmed") \(home ? "at home" : "away")"
    }
}

/// A simple two-column line: words on the left, a figure on the right, and the opponent's logo
/// first when the line is about a match.
private struct TabRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var detail: String?
    let value: String
    var tint: Color = ToolkitColor.primaryText
    var spoken: String?
    var opponentClubId: Int?

    var body: some View {
        // At the large sizes the logo sits by the first line, not halfway down a wrapped block.
        let layout = typeSize.stacksRows
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm))
            : AnyLayout(HStackLayout(spacing: ToolkitSpace.sm))
        layout {
            if let opponentClubId {
                ClubLogo(clubId: opponentClubId, size: 20)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - $0.height * 0.2 }
            }
            line
        }
        .padding(.vertical, ToolkitSpace.xs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .modifier(OptionalLabel(label: spoken))
    }

    private var line: some View {
        NameFigureRow {
            Text(title)
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
        } details: {
            if let detail {
                FactLine(detail)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        } figure: {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OptionalLabel: ViewModifier {
    let label: String?
    func body(content: Content) -> some View {
        if let label { content.accessibilityLabel(label) } else { content }
    }
}

/// A titled card of rows.
private struct TabCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: title)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, ToolkitSpace.lg)
                .padding(.vertical, ToolkitSpace.xs)
                .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
                .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.border, lineWidth: 1))
        }
    }
}

// MARK: - History

private struct HistoryTabView: View {
    @Environment(AppModel.self) private var appModel
    let tab: PlayerHistoryTab

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketFigures(items: [
                ResearchFigure(label: "Appearances", value: "\(tab.appearances)", hint: "\(tab.squadGameweeks) squad gameweeks"),
                ResearchFigure(label: "Hauls (10+)", value: "\(tab.hauls)", hint: "\(tab.blanks) returns of 2 or fewer"),
                ResearchFigure(label: "Best gameweek", value: tab.best.map { "\($0.points) pts" } ?? "—",
                               hint: tab.best?.gameweek.map { "GW\($0)" }),
                ResearchFigure(label: "Home points", value: "\(tab.home.points)", hint: "\(tab.home.minutes) mins"),
                ResearchFigure(label: "Away points", value: "\(tab.away.points)", hint: "\(tab.away.minutes) mins"),
            ])
            TabCard(title: "Every gameweek") {
                if tab.rows.isEmpty {
                    Text("No gameweek data yet this season.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .padding(.vertical, ToolkitSpace.sm)
                }
                ForEach(Array(tab.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    let opponent = Opponent(appModel, clubId: row.opponentClubId, home: row.home)
                    let detail = "\(row.minutes) min · \(row.goals) G · \(row.assists) A · \(row.cleanSheets) CS · xG \(row.xg) · xA \(row.xa) · \(row.bonus) bonus · \(row.bps) BPS" + (row.price.map { " · \($0)" } ?? "")
                    TabRow(title: "GW\(row.gw.map(String.init) ?? "–") \(opponent.short)", detail: detail, value: Self.points(row.points),
                           spoken: "Gameweek \(row.gw.map(String.init) ?? "unknown"), \(opponent.spoken), \(row.points) points, \(detail)",
                           opponentClubId: row.opponentClubId)
                }
            }
        }
    }
}

// MARK: - Form

private struct FormTabView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let tab: PlayerFormTab

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketFigures(items: [
                ResearchFigure(label: "FPL form", value: tab.fplForm, hint: "Official 30-day average"),
                ResearchFigure(label: "Starts (last 6)", value: "\(tab.startsLast6)/6", hint: "Nailed-on check"),
                ResearchFigure(label: "Points per game", value: tab.pointsPerGame, hint: "Season average"),
                ResearchFigure(label: "Minutes", value: "\(tab.minutes)", hint: "\(tab.starts) starts"),
            ])
            TabCard(title: "Rolling windows") {
                ForEach(Array(tab.windows.enumerated()), id: \.offset) { index, w in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    TabRow(title: "Last \(w.last) gameweeks", detail: "\(w.points) pts · \(w.minutes) mins · \(w.xgi) xGI",
                           value: w.ppg.map { "\($0) ppg" } ?? "—")
                }
            }
            if !tab.bars.isEmpty {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    SectionLabel(text: "Points by gameweek")
                    bars
                    Text(tab.bars.map { "GW\($0.gw.map(String.init) ?? "–") \($0.points)" }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var bars: some View {
        let most = max(4, tab.bars.map(\.points).max() ?? 4)
        return ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(tab.bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 2) {
                        Text("\(bar.points)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(ToolkitColor.secondaryText)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colour(bar.band))
                            .frame(width: 24, height: max(4, CGFloat(max(bar.points, 0)) / CGFloat(most) * 96))
                        Text(bar.gw.map(String.init) ?? "–")
                            .font(.caption2)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
            }
            .frame(height: 140, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func colour(_ band: PlayerFormTab.Bar.Band) -> Color {
        switch band {
        case .haul: ToolkitColor.positive
        case .good: ToolkitColor.accent
        case .ok: ToolkitColor.secondaryText
        case .poor, .unknown: ToolkitColor.error
        }
    }
}

// MARK: - Underlying

private struct UnderlyingTabView: View {
    let tab: PlayerUnderlyingTab

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketFigures(items: [
                ResearchFigure(label: "Goals vs xG", value: tab.goalsVsXg.display, hint: "\(tab.goalsVsXg.goals) goals from \(tab.goalsVsXg.xg) xG"),
                ResearchFigure(label: "Assists vs xA", value: tab.assistsVsXa.display, hint: "\(tab.assistsVsXa.assists) assists from \(tab.assistsVsXa.xa) xA"),
                ResearchFigure(label: "xGI / 90", value: tab.xgi90, hint: "\(tab.minutes) minutes played"),
                ResearchFigure(label: "xGI last 6 GW", value: tab.recentXgi, hint: "\(tab.recentGames) gameweeks"),
            ])
            VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
                Label(tab.finishing.text, systemImage: tab.finishing.tone == "warn" ? "exclamationmark.triangle" : tab.finishing.tone == "good" ? "arrow.up.right.circle" : "equal.circle")
                    .foregroundStyle(tab.finishing.tone == "warn" ? ToolkitColor.warning : tab.finishing.tone == "good" ? ToolkitColor.positive : ToolkitColor.secondaryText)
                Label(tab.meaningfulSample ? "Sample size is meaningful" : "Small minutes sample",
                      systemImage: tab.meaningfulSample ? "checkmark.circle" : "hourglass")
                    .foregroundStyle(tab.meaningfulSample ? ToolkitColor.positive : ToolkitColor.warning)
            }
            .font(.subheadline.weight(.semibold))
            TabCard(title: "Season totals and per 90") {
                ForEach(Array(tab.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    TabRow(title: row.label, detail: "\(row.per90) per 90", value: row.total)
                }
            }
        }
    }
}

// MARK: - Fixtures

private struct FixturesTabView: View {
    @Environment(AppModel.self) private var appModel
    let tab: PlayerFixturesTab

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketFigures(items: [
                ResearchFigure(label: "Average FDR", value: tab.averageFdr ?? "—", hint: "Next \(tab.upcoming.count) fixtures"),
                ResearchFigure(label: "Easy fixtures", value: "\(tab.easy)", hint: "FDR 1-2"),
                ResearchFigure(label: "Hard fixtures", value: "\(tab.hard)", hint: "FDR 4-5"),
            ])
            TabCard(title: "Next fixtures (FPL difficulty)") {
                if tab.upcoming.isEmpty {
                    Text("No fixtures left this season.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .padding(.vertical, ToolkitSpace.sm)
                }
                ForEach(Array(tab.upcoming.enumerated()), id: \.offset) { index, f in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    let opponent = Opponent(appModel, clubId: f.opponentClubId, home: f.home)
                    HStack(spacing: ToolkitSpace.sm) {
                        ClubLogo(clubId: f.opponentClubId, size: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GW\(f.gw.map(String.init) ?? "–") \(opponent.short)")
                                .font(.headline)
                                .foregroundStyle(ToolkitColor.primaryText)
                            Text(f.home ? "Home" : "Away")
                                .font(.subheadline)
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                        Spacer(minLength: ToolkitSpace.sm)
                        Text("\(f.fdr)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(DifficultyColor.text(f.fdr))
                            .frame(minWidth: 36, minHeight: 30)
                            .background(DifficultyColor.fill(f.fdr), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, ToolkitSpace.xs)
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Gameweek \(f.gw.map(String.init) ?? "unknown"), \(opponent.spoken), difficulty \(f.fdr) out of 5")
                }
            }
            TabCard(title: "Returns by fixture difficulty") {
                ForEach(Array(tab.byDifficulty.enumerated()), id: \.offset) { index, b in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    TabRow(title: b.label, detail: "\(b.points) pts in \(b.games) \(b.games == 1 ? "game" : "games")",
                           value: b.ppg.map { "\($0) ppg" } ?? "—")
                }
            }
        }
    }
}

// MARK: - Price

private struct PriceTabView: View {
    let tab: PlayerPriceTab

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketFigures(items: [
                ResearchFigure(label: "Current price", value: tab.current, hint: "Started at \(tab.started)"),
                ResearchFigure(label: "Season change", value: tab.seasonChange, hint: "\(tab.rises) rises · \(tab.falls) falls"),
                ResearchFigure(label: "Ownership", value: tab.ownership, hint: "Selected by managers"),
                ResearchFigure(label: "Net transfers (GW)", value: MarketFormat.count(tab.netTransfers),
                               hint: tab.netTransfers >= 0 ? "Being bought" : "Being sold"),
            ])
            TabCard(title: "Price changes") {
                if tab.events.isEmpty {
                    Text("No price changes yet this season.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .padding(.vertical, ToolkitSpace.sm)
                }
                ForEach(Array(tab.events.enumerated()), id: \.offset) { index, e in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    TabRow(title: MarketFormat.day(e.date), detail: "\(e.from) to \(e.to)",
                           value: e.direction == "up" ? "Rise" : "Fall",
                           tint: e.direction == "up" ? ToolkitColor.positive : ToolkitColor.error)
                }
            }
            TabCard(title: "Recent daily snapshots") {
                if tab.snapshots.isEmpty {
                    Text("No snapshots yet.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .padding(.vertical, ToolkitSpace.sm)
                }
                ForEach(Array(tab.snapshots.enumerated()), id: \.offset) { index, s in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    TabRow(title: MarketFormat.day(s.date), detail: "\(s.ownership) owned · net \(MarketFormat.count(s.netTransfers, signed: true))",
                           value: s.price)
                }
            }
        }
    }
}

// MARK: - Defensive

private struct DefensiveTabView: View {
    @Environment(AppModel.self) private var appModel
    let tab: PlayerDefensiveTab

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            if !tab.eligible {
                Text("Goalkeepers can't score DEFCON points: their defensive contributions are always 0.")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                MarketFigures(items: [
                    ResearchFigure(label: "DEFCON hits", value: "\(tab.hits)/\(tab.starts)",
                                   hint: tab.hitStreak >= 2 ? "On a \(tab.hitStreak)-game hit streak" : "Hits in starts"),
                    ResearchFigure(label: "Hit rate in starts", value: tab.hitRateStarts ?? "—",
                                   hint: "\(tab.starts) starts · \(tab.appearances) apps"),
                    ResearchFigure(label: "DC / 90", value: tab.dcPer90, hint: "\(tab.dcTotal) total contributions"),
                    ResearchFigure(label: "CBIT / 90", value: tab.cbitPer90 ?? "—", hint: "\(tab.tackles) tackles · \(tab.recoveries) recoveries"),
                ])
                Text("The threshold is \(tab.threshold)+ contributions in a match for 2 points.\(tab.rank.map { " That per-90 rate ranks \($0.rank) of \($0.of) with 180+ minutes." } ?? "")")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                TabCard(title: "Match by match\(tab.gwRange.isEmpty ? "" : " (\(tab.gwRange))")") {
                    if tab.matches.isEmpty {
                        Text("No matches yet.")
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .padding(.vertical, ToolkitSpace.sm)
                    }
                    ForEach(Array(tab.matches.enumerated()), id: \.offset) { index, m in
                        if index > 0 { Divider().overlay(ToolkitColor.border) }
                        let opponent = Opponent(appModel, clubId: m.opponentClubId, home: m.home)
                        let status = m.hit ? "DEFCON hit" : m.short.map { "\($0) short" } ?? "—"
                        TabRow(title: "GW\(m.gw.map(String.init) ?? "–") \(opponent.short)",
                               detail: "\(m.minutes) min · CBIT \(m.cbit) · \(m.tackles) tkl · \(m.recoveries) rec · \(status) · \(Self.points(m.points))",
                               value: "\(m.dc) DC",
                               tint: m.hit ? ToolkitColor.positive : m.nearMiss ? ToolkitColor.warning : ToolkitColor.primaryText,
                               spoken: "Gameweek \(m.gw.map(String.init) ?? "unknown"), \(opponent.spoken), \(m.dc) defensive contributions, \(status), \(m.minutes) minutes, \(m.points) points",
                               opponentClubId: m.opponentClubId)
                    }
                }
            }
        }
    }
}

// MARK: - Compare

private struct CompareTabView: View {
    @Environment(AppModel.self) private var appModel
    let tab: PlayerCompareTab

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketFigures(items: [
                ResearchFigure(label: "Price", value: tab.price, hint: "\(tab.peersCount) peers within £0.5m"),
                ResearchFigure(label: "Total points", value: "\(tab.totalPoints)", hint: "\(tab.pointsPerGame) per game"),
                ResearchFigure(label: "Ownership", value: tab.ownership),
                ResearchFigure(label: "Same position", value: "\(tab.played)", hint: "played this season"),
            ])
            TabCard(title: "Percentile ranks") {
                ForEach(Array(tab.ranks.enumerated()), id: \.offset) { index, r in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    VStack(alignment: .leading, spacing: 4) {
                        TabRow(title: r.label, detail: r.value, value: "\(r.ordinal) pct",
                               tint: r.percentile >= 75 ? ToolkitColor.positive : r.percentile >= 40 ? ToolkitColor.primaryText : ToolkitColor.error,
                               spoken: "\(r.label) \(r.value), \(r.ordinal) percentile")
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ToolkitColor.raised)
                                Capsule().fill(r.percentile >= 75 ? ToolkitColor.positive : r.percentile >= 40 ? ToolkitColor.accent : ToolkitColor.error)
                                    .frame(width: geo.size.width * CGFloat(max(2, r.percentile)) / 100)
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                        .padding(.bottom, ToolkitSpace.xs)
                    }
                }
            }
            MarketList(title: "Best alternatives at this price", rows: tab.peers, empty: "No similarly priced players found.") { peer in
                MarketPlayerRow(playerId: peer.playerId, player: tab.player(peer.playerId),
                                details: [peer.price, "form \(peer.form)", "xGI/90 \(peer.xgi90)", "\(peer.ownership) owned"],
                                trailing: "\(peer.points) pts")
            }
        }
    }
}

extension View {
    /// "1 pt", "6 pts".
    nonisolated static func points(_ n: Int) -> String { n == 1 ? "1 pt" : "\(n) pts" }
}

