import SwiftUI

/// "Show on squad": one metric layer at a time (design pack p.11).
struct MetricLayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var metric: SquadMetric
    let oddsAvailable: Bool
    let onOddsCheck: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                    CardGroup {
                        ForEach(Array(SquadMetric.allCases.enumerated()), id: \.element) { index, option in
                            if index > 0 { RowDivider() }
                            Button {
                                metric = option
                                dismiss()
                            } label: {
                                HStack(spacing: ToolkitSpace.md) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option.rawValue)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(ToolkitColor.primaryText)
                                        if let detail = detail(option) {
                                            Text(detail)
                                                .font(.caption)
                                                .foregroundStyle(ToolkitColor.secondaryText)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    Spacer()
                                    if metric == option {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(ToolkitColor.accent)
                                    }
                                }
                                .padding(.horizontal, 15)
                                .padding(.vertical, ToolkitSpace.md)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(metric == option ? .isSelected : [])
                        }
                    }
                    Text("One layer at a time. A missing chance shows a dash, not 0%.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    if oddsAvailable {
                        CardGroup {
                            LinkRow(title: "Odds check", detail: "Captain options, defence and bench by chance",
                                    systemImage: "chart.bar.xaxis", action: onOddsCheck)
                        }
                    }
                }
                .padding(.horizontal, ToolkitSpace.page)
                .padding(.bottom, ToolkitSpace.xl)
            }
            .toolkitScreen()
            .navigationTitle("Show on squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func detail(_ option: SquadMetric) -> String? {
        switch option {
        case .fixtures: "Next opponent and xFDR"
        case .price: "Current price"
        case .odds: oddsAvailable
            ? "Clean sheet for goalkeepers and defenders; scoring chance for midfielders and forwards"
            : "Arrives 48 hours before the deadline"
        }
    }
}

/// Team → Fixtures (design pack p.10): each squad member's next six gameweeks, names pinned, with
/// the xFDR variant for their position. Built from the fixture ticker's club runs.
struct TeamFixturesView: View {
    @Environment(AppModel.self) private var appModel
    let team: Team
    let snapshot: Team.Snapshot
    let onPlayer: (Int) -> Void
    let onInfo: () -> Void
    @State private var defence: Resource<ResearchTicker>?
    @State private var attack: Resource<ResearchTicker>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Next 6 gameweeks")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                Spacer()
                Button(action: onInfo) {
                    HStack(spacing: 4) {
                        Text("xFDR")
                        Image(systemName: "info.circle").imageScale(.small)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .accessibilityHint("What fixture difficulty means")
            }
            if let d = defence?.loaded?.value, let a = attack?.loaded?.value {
                FixtureRunGrid(heading: "Player", gameweeks: d.gws, rows: rows(defence: d, attack: a)) { onPlayer($0.id) }
                HStack {
                    Text("Lower is easier · xFDR")
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
        .task { await load(force: false) }
    }

    private func load(force: Bool) async {
        let clubs = Array(Set(team.players.values.map(\.clubId)))
        let research = appModel.researchRepository
        func endpoint(_ lens: FixtureView.Lens) -> CachedEndpoint<ResearchTicker> {
            research.ticker(horizon: 6, fuzzy: false, sort: .sum, hardestFirst: false, clubs: clubs,
                            view: FixtureView(model: .xfdr, lens: lens))
        }
        if defence == nil || force { defence = Resource(endpoint(.cleanSheet)) }
        if attack == nil || force { attack = Resource(endpoint(.attack)) }
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
            let variant = defensive ? "Defence" : "Attack"
            let club = appModel.club(player.clubId)
            let cells = ticker.rows.first { $0.clubId == player.clubId }?.cells ?? []
            let subject = player.webName
            return FixtureRunGrid.Row(
                id: player.id,
                title: player.webName,
                subtitle: [club?.shortName, variant, pick.role == .bench ? "Bench" : nil].compactMap { $0 }.joined(separator: " · "),
                cells: cells.map { FixtureCellModel(tickerCell: $0, club: appModel.club, model: "xFDR · \(variant)", subject: subject) })
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
