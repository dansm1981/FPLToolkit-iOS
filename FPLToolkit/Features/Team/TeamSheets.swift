import SwiftUI

/// Team → Fixtures (design pack p.10): each squad member's next six gameweeks, names pinned, with
/// the xFDR variant for their position. Built from the fixture ticker's club runs.
struct TeamFixturesView<Menu: View>: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    let snapshot: Team.Snapshot
    /// The chosen fixture view; "By position" uses Defence or Attack per player.
    let view: FixtureView
    @ViewBuilder let menu: () -> Menu
    let onPlayer: (Int) -> Void
    @State private var defence: Resource<ResearchTicker>?
    @State private var attack: Resource<ResearchTicker>?

    private var byPosition: Bool { view.model == .xfdr && view.lens == .position }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Next 6 gameweeks")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                Spacer()
                menu()
            }
            if let d = defence?.loaded?.value, let a = attack?.loaded?.value {
                FixtureRunGrid(heading: "Player", gameweeks: d.gws, rows: rows(defence: d, attack: a)) { onPlayer($0.id) }
                HStack {
                    Text("Lower is easier · \(view.model == .fpl ? "Official FDR" : "xFDR")")
                    Spacer()
                    Text("Swipe for more weeks")
                }
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
            } else if case .failed(let copy)? = defence?.phase ?? attack?.phase {
                ErrorBanner(copy: copy)
                Button("Try again") { Task { await load(force: true) } }
                    .buttonStyle(ToolkitSecondaryButtonStyle())
            } else {
                SkeletonCards(caption: "Loading fixtures…", count: 1)
            }
        }
        .task(id: view) { await load(force: true) }
    }

    private func load(force: Bool) async {
        let clubs = Array(Set(team.players.values.map(\.clubId)))
        let research = appModel.researchRepository
        func endpoint(_ lens: FixtureView.Lens) -> CachedEndpoint<ResearchTicker> {
            research.ticker(horizon: 6, fuzzy: false, sort: .sum, hardestFirst: false, clubs: clubs,
                            view: FixtureView(model: .xfdr, lens: lens))
        }
        func chosen() -> CachedEndpoint<ResearchTicker> {
            research.ticker(horizon: 6, fuzzy: false, sort: .sum, hardestFirst: false, clubs: clubs, view: view)
        }
        // By position needs both variants; any other view is one set of club runs.
        if defence == nil || force { defence = Resource(byPosition ? endpoint(.cleanSheet) : chosen()) }
        if attack == nil || force { attack = Resource(byPosition ? endpoint(.attack) : chosen()) }
        async let d: Void = defence?.load() ?? ()
        async let a: Void = attack?.load() ?? ()
        _ = await (d, a)
    }

    private func rows(defence: ResearchTicker, attack: ResearchTicker) -> [FixtureRunGrid.Row] {
        let picks = TeamSquad.rows(snapshot, team: team).flatMap { $0 } + TeamSquad.bench(snapshot)
        return picks.compactMap { pick in
            guard let player = team.player(pick.playerId) else { return nil }
            let defensive = player.position == .gk || player.position == .def
            let ticker = defensive ? defence : attack
            let variant = byPosition ? (defensive ? "Defence" : "Attack")
                : view.model == .fpl ? "Official FDR" : view.lens.label
            let club = appModel.club(player.clubId)
            let cells = ticker.rows.first { $0.clubId == player.clubId }?.cells ?? []
            let subject = player.webName
            return FixtureRunGrid.Row(
                id: player.id,
                title: player.webName,
                subtitle: [club?.shortName, variant, pick.role == .bench ? "Bench" : nil].compactMap { $0 }.joined(separator: " · "),
                cells: cells.map { FixtureCellModel(tickerCell: $0, club: appModel.club,
                                                    model: view.model == .fpl ? "Official FDR" : "xFDR · \(variant)", subject: subject) })
        }
    }
}

extension FixtureCellModel {
    /// From a fixture-ticker cell (the club's games in one gameweek).
    init(tickerCell cell: ResearchTicker.Cell, club: (Int?) -> Bootstrap.Club?, model: String, subject: String) {
        let games = cell.blank ? [] : cell.fixtures.map { f in
            Game(label: (club(f.opponentClubId)?.shortName ?? "TBC") + (f.home ? " H" : " A"),
                 value: f.value == nil ? nil : f.display,
                 tone: DifficultyTone(band: f.band))
        }
        let spoken: String
        if games.isEmpty {
            spoken = "\(subject), gameweek \(cell.gw), no fixture"
        } else {
            spoken = "\(subject), gameweek \(cell.gw), " + cell.fixtures.map { f in
                "\(club(f.opponentClubId)?.name ?? "opponent to be confirmed") \(f.home ? "at home" : "away"), "
                    + (f.value == nil ? "difficulty unavailable" : "\(model) \(f.display)")
            }.joined(separator: "; then ")
        }
        self.init(gw: cell.gw, games: games, accessibilityLabel: spoken)
    }
}

/// "Your leagues" (S19), one tap from the Team header. The league rows and "Add a league" are
/// the existing leagues card; P1 restyles them.
struct LeaguesListView: View {
    var body: some View {
        ScrollView {
            LeaguesCard()
                .padding(.horizontal, 18)
                .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Your leagues")
    }
}
