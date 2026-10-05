import SwiftUI

/// Team → Fixtures (design pack p.10; compact, Dan 29 Sep): each squad member's next ten
/// gameweeks, names pinned with photo and badge, and the difficulty model chosen in plain view:
/// Official FDR or xFDR, and which xFDR (Auto, Overall, Attack or Defence). Built from the
/// fixture ticker's club runs.
struct TeamFixturesView: View {
    let team: Team
    let snapshot: Team.Snapshot
    @Binding var model: FixtureView.Model
    @Binding var lens: FixtureView.Lens
    let onInfo: () -> Void
    let onPlayer: (Int) -> Void

    var body: some View {
        let picks = TeamSquad.rows(snapshot, team: team).flatMap { $0 } + TeamSquad.bench(snapshot)
        SquadFixturesView(members: picks.compactMap { pick in
            team.player(pick.playerId).map { SquadFixturesView.Member(player: $0, onBench: pick.role == .bench) }
        }, model: $model, lens: $lens, onInfo: onInfo, onPlayer: onPlayer)
    }
}

/// Any squad's next ten gameweeks (the team's, or a plan's since 5 Oct), names pinned with photo
/// and badge, with the difficulty model in plain view. Built from the fixture ticker's club runs.
struct SquadFixturesView: View {
    struct Member {
        let player: PlayerSummary
        let onBench: Bool
    }
    @Environment(AppModel.self) private var appModel
    let members: [Member]
    @Binding var model: FixtureView.Model
    @Binding var lens: FixtureView.Lens
    let onInfo: () -> Void
    let onPlayer: (Int) -> Void
    @State private var defence: Resource<ResearchTicker>?
    @State private var attack: Resource<ResearchTicker>?

    static let horizon = 10

    private var view: FixtureView { FixtureView(model: model, lens: lens) }
    private var byPosition: Bool { model == .xfdr && lens == .position }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            if let d = defence?.loaded?.value, let a = attack?.loaded?.value {
                FixtureRunGrid(heading: "Player", gameweeks: d.gws, rows: rows(defence: d, attack: a)) { onPlayer($0.id) }
                    // A table: text and cells stay at the standard size (as the pitch's do), so five or
                    // six weeks fit across even at the largest text size (Dan's phone, 29 Sep). The List
                    // view and the player pages show the same fixtures at any size.
                    .dynamicTypeSize(...DynamicTypeSize.large)
                HStack {
                    Text("Lower is easier · \(model == .fpl ? "Official FDR" : "xFDR")")
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

    /// Official FDR or xFDR, then xFDR's variants, as chips that wrap.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 8) {
                ForEach(FixtureView.Model.allCases) { option in
                    Button { model = option } label: {
                        FilterChipLabel(text: option.label, active: model == option, menu: false)
                    }
                    .accessibilityAddTraits(model == option ? .isSelected : [])
                }
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(ToolkitColor.link)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("About fixture difficulty")
            }
            if model == .xfdr {
                FlowLayout(spacing: 8) {
                    ForEach(FixtureView.Lens.allCases) { option in
                        Button { lens = option } label: {
                            FilterChipLabel(text: option.label, active: lens == option, menu: false)
                        }
                        .accessibilityAddTraits(lens == option ? .isSelected : [])
                        .accessibilityLabel("xFDR \(option.label)")
                    }
                }
            }
        }
    }

    private func load(force: Bool) async {
        let clubs = Array(Set(members.map(\.player.clubId)))
        let research = appModel.researchRepository
        func endpoint(_ lens: FixtureView.Lens) -> CachedEndpoint<ResearchTicker> {
            research.ticker(horizon: Self.horizon, fuzzy: false, sort: .sum, hardestFirst: false, clubs: clubs,
                            view: FixtureView(model: .xfdr, lens: lens))
        }
        func chosen() -> CachedEndpoint<ResearchTicker> {
            research.ticker(horizon: Self.horizon, fuzzy: false, sort: .sum, hardestFirst: false, clubs: clubs, view: view)
        }
        // Auto needs both variants; any other view is one set of club runs.
        if defence == nil || force { defence = Resource(byPosition ? endpoint(.cleanSheet) : chosen()) }
        if attack == nil || force { attack = Resource(byPosition ? endpoint(.attack) : chosen()) }
        async let d: Void = defence?.load() ?? ()
        async let a: Void = attack?.load() ?? ()
        _ = await (d, a)
    }

    private func rows(defence: ResearchTicker, attack: ResearchTicker) -> [FixtureRunGrid.Row] {
        members.map { member in
            let player = member.player
            let defensive = player.position == .gk || player.position == .def
            let ticker = defensive ? defence : attack
            let variant = byPosition ? (defensive ? "Defence" : "Attack")
                : model == .fpl ? "Official FDR" : lens.label
            let club = appModel.club(player.clubId)
            let cells = ticker.rows.first { $0.clubId == player.clubId }?.cells ?? []
            let subject = player.webName
            return FixtureRunGrid.Row(
                id: player.id,
                title: player.webName,
                subtitle: [club?.shortName, variant, member.onBench ? "Bench" : nil].compactMap { $0 }.joined(separator: " · "),
                photo: player.photo,
                clubId: player.clubId,
                cells: cells.map { FixtureCellModel(tickerCell: $0, club: appModel.club,
                                                    model: model == .fpl ? "Official FDR" : "xFDR · \(variant)", subject: subject) })
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
