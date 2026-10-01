import SwiftUI

/// A deep-dive screen: the website's intro, then its list, built on the server with its code.
private struct DeepDiveScreen<T: Decodable & Sendable, Content: View>: View {
    let title: String
    let caption: String
    let table: ResearchTable<T>
    let retry: () -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                ResearchTableView(table: table, caption: caption, retry: retry) { data in
                    content(data)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// An item and its place in a list, for rows with no identity of their own.
/// "1 haul", "3 hauls".
private func counted(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

struct Ranked<Value>: Identifiable {
    let rank: Int
    let value: Value
    var id: Int { rank }
}

/// The website's /hauls: the most 10+ point gameweeks.
struct HaulsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var table = ResearchTable<Hauls>()

    var body: some View {
        DeepDiveScreen(title: "Hauls", caption: "Loading hauls…", table: table, retry: reload) { h in
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                EliteNote(text: "A haul is a gameweek of 10 or more FPL points. These are the players delivering them most often, with their best single score and how often they return a goal or assist.")
                MarketList(title: "Most 10+ point gameweeks", rows: h.rows,
                           empty: "No gameweek history has been recorded yet this season.", initial: 25) { row in
                    let player = h.player(row.playerId)
                    let figures = "Best \(row.best) · \(counted(row.returns, "return")) · \(counted(row.appearances, "app")) · \(row.points) pts"
                    MarketPlayerRow(
                        playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
                        extra: figures, trailing: "\(row.hauls)",
                        spoken: [EliteFormat.name(player, row.playerId), counted(row.hauls, "haul"), "best score \(row.best)",
                                 "\(row.returns) games with a goal or assist", "\(row.appearances) appearances",
                                 "\(row.points) points", EliteFormat.price(player)].compactMap { $0 }.joined(separator: ", ")
                    )
                }
            }
        }
        .task { await load() }
    }

    private func reload() { Task { await load() } }
    private func load() async { await table.load(appModel.researchRepository.hauls) }
}

/// The website's /consistency: the share of appearances returning 4+ points.
struct ConsistencyView: View {
    @Environment(AppModel.self) private var appModel
    @State private var table = ResearchTable<Consistency>()

    var body: some View {
        DeepDiveScreen(title: "Consistency", caption: "Loading consistency…", table: table, retry: reload) { c in
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                EliteNote(text: "Consistency is the share of a player's appearances that return 4 or more FPL points. Only players with at least \(c.minApps) appearance\(c.minApps == 1 ? "" : "s") are shown, so the table is not skewed by one-off cameos.")
                MarketList(title: "Most consistent returners", rows: c.rows,
                           empty: "No gameweek history has been recorded yet this season.", initial: 25) { row in
                    let player = c.player(row.playerId)
                    let figures = "\(row.goodGames)/\(row.appearances) games of 4+ · \(counted(row.blanks, "blank")) · \(counted(row.hauls, "haul")) · \(row.pointsPerGame) pts/game"
                    MarketPlayerRow(
                        playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
                        extra: figures, trailing: row.consistency.display, trailingColor: colour(row.tone),
                        spoken: [EliteFormat.name(player, row.playerId), "consistency \(row.consistency.display)",
                                 "\(row.goodGames) of \(row.appearances) games returned 4 or more", "\(row.blanks) blanks",
                                 counted(row.hauls, "haul"), "\(row.pointsPerGame) points per game", EliteFormat.price(player)]
                            .compactMap { $0 }.joined(separator: ", ")
                    )
                }
            }
        }
        .task { await load() }
    }

    private func colour(_ tone: Consistency.Row.Tone) -> Color {
        switch tone {
        case .good: ToolkitColor.positive
        case .bad: ToolkitColor.error
        case .neutral: ToolkitColor.primaryText
        }
    }

    private func reload() { Task { await load() } }
    private func load() async { await table.load(appModel.researchRepository.consistency) }
}

/// The website's /home-away: points per game at home and away.
struct HomeAwayView: View {
    @Environment(AppModel.self) private var appModel
    @State private var table = ResearchTable<HomeAway>()

    var body: some View {
        DeepDiveScreen(title: "Home and away", caption: "Loading home and away…", table: table, retry: reload) { h in
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                EliteNote(text: "Points per game split by venue, for every player with at least one home and one away appearance. Useful when a fixture run is heavily weighted one way.")
                if h.count == 0 {
                    EliteNote(text: "Not enough gameweeks have been played yet to split home and away form.")
                } else {
                    MarketList(title: "Home specialists", rows: h.homeSpecialists, initial: 25) { row($0, h) }
                    EliteNote(text: "Biggest positive gap between home and away points per game.")
                    MarketList(title: "Best travellers", rows: h.travellers, initial: 25) { row($0, h) }
                    EliteNote(text: "Players who score more on the road than at home.")
                }
            }
        }
        .task { await load() }
    }

    private func row(_ row: HomeAway.Row, _ h: HomeAway) -> some View {
        let player = h.player(row.playerId)
        let figures = "Home \(row.home) · away \(row.away) pts/game · \(row.homeGames)H / \(row.awayGames)A"
        let gap = row.diff.value > 0 ? "\(row.diff.display.dropFirst()) more at home" : row.diff.value < 0
            ? "\(row.diff.display.dropFirst()) more away" : "the same home and away"
        return MarketPlayerRow(
            playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            extra: figures, trailing: row.diff.display, trailingColor: MarketFormat.tint(row.diff.value),
            spoken: [EliteFormat.name(player, row.playerId), "\(gap) points per game",
                     "\(row.home) at home in \(row.homeGames) games", "\(row.away) away in \(row.awayGames)",
                     EliteFormat.price(player)].compactMap { $0 }.joined(separator: ", ")
        )
    }

    private func reload() { Task { await load() } }
    private func load() async { await table.load(appModel.researchRepository.homeAway) }
}

/// The website's /records: the season's extremes.
struct RecordsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var table = ResearchTable<SeasonRecords>()

    var body: some View {
        DeepDiveScreen(title: "Records", caption: "Loading records…", table: table, retry: reload) { r in
            VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
                EliteNote(text: "The season's extremes: the biggest single gameweek scores, the most frequent haulers, the largest price swings and the most-owned players in the game.")
                MarketFigures(items: r.tiles.map { ResearchFigure(label: $0.label, value: $0.value, hint: $0.sub) })
                MarketList(title: "Biggest single gameweek scores",
                           rows: r.topScores.enumerated().map { Ranked(rank: $0 + 1, value: $1) },
                           empty: "No gameweek history has been recorded yet this season.", initial: 20) { item in
                    let s = item.value
                    let player = r.player(s.playerId)
                    MarketPlayerRow(
                        playerId: s.playerId, player: player, details: ["GW\(s.gameweek)"],
                        extra: "\(s.goals) G · \(s.assists) A · \(s.bonus) bonus", trailing: "\(s.points) pts",
                        spoken: [EliteFormat.name(player, s.playerId), "\(s.points) points in gameweek \(s.gameweek)",
                                 "\(s.goals) goals", "\(s.assists) assists", "\(s.bonus) bonus"].joined(separator: ", ")
                    )
                }
                MarketList(title: "Most price rises", rows: r.mostRises, empty: "No price rises recorded yet.") {
                    countRow($0, r, sign: "+", words: "rises", tint: ToolkitColor.positive)
                }
                MarketList(title: "Most price falls", rows: r.mostFalls, empty: "No price falls recorded yet.") {
                    countRow($0, r, sign: "-", words: "falls", tint: ToolkitColor.error)
                }
            }
        }
        .task { await load() }
    }

    private func countRow(_ row: SeasonRecords.Count, _ r: SeasonRecords, sign: String, words: String, tint: Color) -> some View {
        let player = r.player(row.playerId)
        return MarketPlayerRow(
            playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            trailing: "\(sign)\(row.count)", trailingColor: tint,
            spoken: [EliteFormat.name(player, row.playerId), "\(row.count) price \(words)", EliteFormat.price(player)]
                .compactMap { $0 }.joined(separator: ", ")
        )
    }

    private func reload() { Task { await load() } }
    private func load() async { await table.load(appModel.researchRepository.records) }
}
