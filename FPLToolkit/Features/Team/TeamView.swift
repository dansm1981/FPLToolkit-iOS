import SwiftUI

/// How the Team tab shows the squad; the choice is remembered.
enum TeamLayout: String, CaseIterable, Identifiable {
    case pitch = "Pitch", list = "List", fixtures = "Fixtures"
    var id: String { rawValue }
}

/// The one metric each tile or row shows; one layer at a time (design pack p.11), remembered.
enum SquadMetric: String, CaseIterable, Identifiable {
    case fixtures = "Fixtures", price = "Price", odds = "Odds"
    var id: String { rawValue }
}

/// S07–S09, S19 (design pack pp.9–12): the published squad, read-only. The team itself is the
/// screen; its source context is one line, and the exact times open on tap.
struct TeamView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int
    @State private var resource: Resource<Team>?
    /// Chances from bookmaker odds (P3-5), for the Odds layer.
    @State private var odds: Resource<Odds>?
    @AppStorage("team.layout") private var layout: TeamLayout = .pitch
    @AppStorage("team.metric") private var metric: SquadMetric = .fixtures
    @State private var sheet: TeamSheet?
    @State private var pushedPlayer: PlayerRef?
    @State private var showingLeagues = false
    @State private var showingSources = false

    enum TeamSheet: String, Identifiable {
        case source, fdr, odds, oddsCheck
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch resource?.phase {
            case .loading?, nil:
                ScrollView {
                    SkeletonCards(caption: "Loading your squad…", count: 4)
                        .padding(.horizontal, ToolkitSpace.page)
                }
            case .failed(let copy)?:
                ErrorStateView(copy: copy) {
                    Task { await resource?.retry() }
                }
            case .loaded(let loaded)?:
                if let resource {
                    ScrollView {
                        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                            SavedDataBanner(resource: resource)
                            TeamOverview(
                                team: loaded.value,
                                odds: odds?.loaded?.value,
                                layout: $layout,
                                metric: $metric,
                                onPlayer: { id in
                                    pushedPlayer = PlayerRef(id: id, context: loaded.value.snapshot.map { "In your GW\($0.gw) squad" })
                                },
                                onSheet: { sheet = $0 },
                                onPlan: { appModel.router.selectedTab = .planner })
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, ToolkitSpace.section)
                    }
                    .refreshable { await resource.load(bypassCache: true) }
                }
            }
        }
        .toolkitScreen()
        .navigationTitle("My team")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingLeagues = true } label: {
                    Label("Your leagues", systemImage: "trophy")
                }
                .tint(ToolkitColor.accent)
            }
        }
        .navigationDestination(isPresented: $showingLeagues) { LeaguesListView() }
        .navigationDestination(isPresented: $showingSources) { DataSourcesView(entryId: entryId) }
        .navigationDestination(item: $pushedPlayer) { ref in PlayerDetailView(playerId: ref.id, context: ref.context) }
        .sheet(item: $sheet) { which in
            sheetView(which)
        }
        .task {
            if odds == nil {
                let odds = Resource(appModel.liveRepository.odds())
                self.odds = odds
                Task { await odds.load() }
            }
            if resource == nil {
                let resource = Resource(appModel.teamRepository.team(entryId: entryId))
                self.resource = resource
                await resource.load()
            }
        }
    }

    @ViewBuilder private func sheetView(_ which: TeamSheet) -> some View {
        switch which {
        case .source:
            if let team = resource?.loaded?.value, let snapshot = team.snapshot {
                InfoSheet(
                    title: "Your published squad",
                    message: TeamText.sourceMessage(snapshot, nextGw: appModel.bootstrap?.value.gameweek.next?.id),
                    links: [
                        InfoSheetLink(title: "Data & sources", detail: "Published and fetched times", systemImage: "icloud") { showingSources = true },
                        InfoSheetLink(title: "Plan changes", detail: "Keep a separate draft", systemImage: "calendar") { appModel.router.selectedTab = .planner },
                    ])
            }
        case .fdr:
            InfoSheet(title: "Fixture difficulty", message: TeamText.fdrMessage)
        case .odds:
            InfoSheet(title: "Betting-market estimate", message: TeamText.oddsMessage(odds?.loaded?.value))
        case .oddsCheck:
            if let team = resource?.loaded?.value, let odds = odds?.loaded?.value {
                NavigationStack { OddsCheckView(team: team, odds: odds) }
            }
        }
    }
}

// MARK: - Content

struct TeamOverview: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let team: Team
    let odds: Odds?
    @Binding var layout: TeamLayout
    @Binding var metric: SquadMetric
    let onPlayer: (Int) -> Void
    let onSheet: (TeamView.TeamSheet) -> Void
    let onPlan: () -> Void
    /// The fixture choice is the app's one (shared with the Planner).
    @AppStorage(FixtureView.modelKey) private var fixtureModel = FixtureView.Model.xfdr
    @AppStorage(FixtureView.lensKey) private var fixtureLens = FixtureView.Lens.position
    /// Club runs for a view other than xFDR by position (which comes with the team).
    @State private var ticker: Resource<ResearchTicker>?

    private var fixtureView: FixtureView { FixtureView(model: fixtureModel, lens: fixtureLens) }
    /// xFDR by position: the team's own next fixtures, rated for each player's position.
    private var usesTeamFixtures: Bool { fixtureModel == .xfdr && fixtureLens == .position }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = team.snapshot {
                VStack(alignment: .leading, spacing: 4) {
                    TeamIdentity(name: team.entry.name, manager: team.entry.manager)
                    ContextLine(lead: "GW\(snapshot.gw) squad", parts: contextParts(snapshot)) {
                        onSheet(.source)
                    }
                }
                if let freeHit = snapshot.freeHitGw {
                    InlineNotice(text: "You played your Free Hit in GW\(freeHit), so this is the GW\(snapshot.gw) squad it reverts to.",
                                 systemImage: "arrow.uturn.backward")
                }
                if let chip = snapshot.activeChip {
                    Tag(text: "GW\(snapshot.gw) chip: \(TeamText.chipName(chip))", foreground: ToolkitColor.accent, fill: ToolkitColor.goldTag)
                }
                Picker("View", selection: $layout) {
                    ForEach(TeamLayout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                switch layout {
                case .pitch:
                    if typeSize.isAccessibilitySize {
                        // Large text: readable rows instead of tiny five-across tiles (design pack p.29).
                        Text("Showing the list at this text size.")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                        listView(snapshot)
                    } else {
                        pitchView(snapshot)
                    }
                case .list:
                    listView(snapshot)
                case .fixtures:
                    TeamFixturesView(team: team, snapshot: snapshot, view: fixtureView, menu: { squadMenu },
                                     onPlayer: onPlayer)
                }
            } else {
                noSnapshot
            }
        }
        .task(id: fixtureView) {
            guard !usesTeamFixtures else { ticker = nil; return }
            let clubs = Array(Set(team.players.values.map(\.clubId)))
            let ticker = Resource(appModel.researchRepository.ticker(horizon: 6, fuzzy: false, sort: .sum, hardestFirst: false,
                                                                     clubs: clubs, view: fixtureView))
            self.ticker = ticker
            await ticker.load()
        }
    }

    private func contextParts(_ snapshot: Team.Snapshot) -> [String] {
        var parts: [String] = []
        if let next = nextGw { parts.append("GW\(next) fixtures") }
        if let bank = snapshot.bank { parts.append("\(Format.price(bank)) ITB") }
        return parts
    }

    private var nextGw: Int? {
        appModel.bootstrap?.value.gameweek.next?.id ?? team.players.values.compactMap(\.nextFixture?.gw).min()
    }

    // MARK: Pitch

    private func metricBar(_ snapshot: Team.Snapshot) -> some View {
        HStack {
            Text([nextGw.map { "GW\($0)" }, TeamSquad.formation(snapshot, team: team)].compactMap { $0 }.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .accessibilityLabel("Formation \(TeamSquad.formation(snapshot, team: team))")
            Spacer()
            squadMenu
        }
    }

    /// What the tiles show, and which fixture difficulty: one gold menu (design v2).
    private var squadMenu: some View {
        Menu {
            Section("Show on tiles") {
                ForEach(SquadMetric.allCases) { option in
                    Button {
                        metric = option
                    } label: {
                        if metric == option { Label(option.rawValue, systemImage: "checkmark") } else { Text(option.rawValue) }
                    }
                }
            }
            Section("Fixture difficulty") {
                ForEach(TeamText.fixtureChoices, id: \.label) { choice in
                    Button {
                        fixtureModel = choice.view.model
                        fixtureLens = choice.view.lens
                        metric = .fixtures
                    } label: {
                        if metric == .fixtures && fixtureView == choice.view {
                            Label(choice.label, systemImage: "checkmark")
                        } else {
                            Text(choice.label)
                        }
                    }
                }
            }
            Section {
                Button { onSheet(metric == .odds ? .odds : .fdr) } label: {
                    Label(metric == .odds ? "About betting-market estimates" : "About fixture difficulty", systemImage: "info.circle")
                }
                if odds?.available == true {
                    Button { onSheet(.oddsCheck) } label: {
                        Label("Odds check", systemImage: "chart.bar.xaxis")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(menuTitle)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ToolkitColor.link)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Show on tiles: \(menuTitle)")
        .accessibilityHint("Choose fixtures, price or odds, and the fixture difficulty")
    }

    private var menuTitle: String {
        switch metric {
        case .fixtures: fixtureView.summary
        case .price: "Price"
        case .odds: "Odds"
        }
    }

    private func pitchView(_ snapshot: Team.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metricBar(snapshot)
            SquadPitch(rows: TeamSquad.rows(snapshot, team: team).map { $0.map(tile) }) { onPlayer($0.playerId) }
            BenchStrip(tiles: TeamSquad.bench(snapshot).map(tile)) { onPlayer($0.playerId) }
            if metric == .odds, odds?.available == true {
                Button { onSheet(.oddsCheck) } label: {
                    Label("Odds check: captain, defence, bench", systemImage: "chart.bar.xaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button(action: onPlan) {
                Label("Plan changes", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(ToolkitSecondaryButtonStyle())
            .padding(.top, 4)
        }
    }

    private func tile(_ pick: Team.Pick) -> PitchTileModel {
        let player = team.player(pick.playerId)
        let club = appModel.club(player?.clubId)
        let role: String? = pick.isCaptain ? "C" : pick.isViceCaptain ? "V" : nil
        let flagged = player.map { $0.availability.level == .doubt || $0.availability.level == .out } ?? false
        var spoken = [player?.webName ?? "Player", player?.position.displayName ?? ""]
        if role == "C" { spoken.append("captain") }
        if role == "V" { spoken.append("vice-captain") }
        if pick.role == .bench { spoken.append("bench") }
        if flagged, let availability = player?.availability {
            spoken.append(availability.chanceNext.map { "\($0)% chance of playing" } ?? "availability concern")
        }
        let metricModel: PitchTileModel.Metric
        switch metric {
        case .fixtures where !usesTeamFixtures:
            if let player, let cell = tickerCell(for: player) {
                if cell.games.isEmpty {
                    metricModel = .text("No fixture")
                } else {
                    let first = cell.games[0]
                    metricModel = .fixture(label: cell.games.count > 1 ? first.label + " +\(cell.games.count - 1)" : first.label,
                                           value: cell.games.count > 1 ? nil : first.value, tone: first.tone)
                }
                spoken.append(cell.accessibilityLabel.replacingOccurrences(of: "\(player.webName), ", with: ""))
            } else {
                metricModel = .text("–")
            }
        case .fixtures:
            if let fixture = player?.nextFixture {
                if fixture.blank {
                    metricModel = .text("No fixture")
                    spoken.append("no fixture")
                } else {
                    let opponent = appModel.club(fixture.opponentClubId)
                    let venue = fixture.home.map { $0 ? "H" : "A" }
                    metricModel = .fixture(label: [opponent?.shortName ?? "TBC", venue].compactMap { $0 }.joined(separator: " "),
                                           value: fixture.xfdr?.display,
                                           tone: DifficultyTone(band: fixture.xfdr?.band))
                    spoken.append("next \(opponent?.name ?? "opponent to be confirmed") \(fixture.home.map { $0 ? "at home" : "away" } ?? "")")
                    if let xfdr = fixture.xfdr { spoken.append("\(xfdr.modelLabel) \(xfdr.display)") }
                }
            } else {
                metricModel = .text("–")
            }
        case .price:
            let price = player.map { Format.price($0.price) } ?? "–"
            metricModel = .text(price)
            spoken.append(price)
        case .odds:
            let text = player.map { TeamText.oddsTile($0, odds: odds) } ?? "–"
            metricModel = .text(text)
            spoken.append(player.map { TeamText.oddsSpoken($0, odds: odds) } ?? "")
        }
        return PitchTileModel(playerId: pick.playerId, name: player?.webName ?? "Player", colors: club?.colors,
                              isGoalkeeper: player?.position == .gk, role: role, flagged: flagged,
                              metric: metricModel,
                              accessibilityLabel: spoken.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// This player's next gameweek in the chosen view's club runs.
    private func tickerCell(for player: PlayerSummary) -> FixtureCellModel? {
        guard let ticker = ticker?.loaded?.value,
              let cell = ticker.rows.first(where: { $0.clubId == player.clubId })?.cells.first else { return nil }
        return FixtureCellModel(tickerCell: cell, club: appModel.club, model: fixtureView.summary, subject: player.webName)
    }

    // MARK: List

    private func listView(_ snapshot: Team.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metricBar(snapshot)
            rows(TeamSquad.rows(snapshot, team: team).flatMap { $0 })
            SectionHeader(title: "Bench")
            rows(TeamSquad.bench(snapshot))
        }
    }

    private func rows(_ picks: [Team.Pick]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(picks.enumerated()), id: \.element.playerId) { index, pick in
                if let player = team.player(pick.playerId) {
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    Button { onPlayer(pick.playerId) } label: {
                        row(pick, player)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the player")
                }
            }
        }
        .padding(.horizontal, 14)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func row(_ pick: Team.Pick, _ player: PlayerSummary) -> PlayerListRow {
        let role: String? = pick.isCaptain ? "C" : pick.isViceCaptain ? "V" : nil
        let price = Format.price(player.price)
        switch metric {
        case .fixtures:
            let fixture = player.nextFixture
            let opponent = fixture.flatMap { $0.blank ? nil : appModel.club($0.opponentClubId) }
            let value: String? = fixture.map { f in
                if f.blank { return "No fixture" }
                return [opponent?.shortName ?? "TBC", f.home.map { $0 ? "H" : "A" }].compactMap { $0 }.joined(separator: " ")
            }
            let variant = fixture?.xfdr.map { $0.modelLabel.replacingOccurrences(of: " · ", with: " ") }
            let chip = fixture?.xfdr.map { (text: $0.display, tone: DifficultyTone(band: $0.band)) }
            let spoken = [price, value.map { "next \($0)" }, fixture?.xfdr.map { "\($0.modelLabel) \($0.display)" }]
            return PlayerListRow(player: player, role: role,
                                 detail: [price, variant].compactMap { $0 }.joined(separator: " · "),
                                 value: value, valueChip: chip,
                                 spokenDetail: spoken.compactMap { $0 }.joined(separator: ", "))
        case .price:
            return PlayerListRow(player: player, role: role, detail: player.position.displayName, value: price)
        case .odds:
            return PlayerListRow(player: player, role: role, detail: price,
                                 value: TeamText.oddsTile(player, odds: odds),
                                 spokenDetail: "\(price), \(TeamText.oddsSpoken(player, odds: odds))")
        }
    }

    private var noSnapshot: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                Text("No published squad yet")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                Text(noSnapshotMessage)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noSnapshotMessage: String {
        if let next = appModel.bootstrap?.value.gameweek.next {
            return "\(team.entry.name) hasn't been through a deadline yet. Your squad will appear here once the GW\(next.id) deadline passes."
        }
        return "\(team.entry.name) hasn't been through a deadline yet. Your squad will appear here once the next deadline passes."
    }
}

/// A label with its icon after the text ("Plan changes →").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

// MARK: - Squad order (presentation only: slots and positions come from the API)

enum TeamSquad {
    /// Starters in lines: goalkeeper, defenders, midfielders, forwards (any unknown position last).
    static func rows(_ snapshot: Team.Snapshot, team: Team) -> [[Team.Pick]] {
        let starters = snapshot.picks.filter { $0.role != .bench }.sorted { $0.slot < $1.slot }
        let order: [Position] = [.gk, .def, .mid, .fwd]
        var lines = order.map { position in starters.filter { team.player($0.playerId)?.position == position } }
        let rest = starters.filter { !order.contains(team.player($0.playerId)?.position ?? .unknown) }
        if !rest.isEmpty { lines.append(rest) }
        return lines.filter { !$0.isEmpty }
    }

    /// The bench in its order: goalkeeper, then substitutes 1–3.
    static func bench(_ snapshot: Team.Snapshot) -> [Team.Pick] {
        snapshot.picks.filter { $0.role == .bench }.sorted { $0.slot < $1.slot }
    }

    /// "4–4–2" from the starters' positions.
    static func formation(_ snapshot: Team.Snapshot, team: Team) -> String {
        let starters = snapshot.picks.filter { $0.role != .bench }
        let counts = [Position.def, .mid, .fwd].map { position in
            starters.filter { team.player($0.playerId)?.position == position }.count
        }
        return counts.map(String.init).joined(separator: "–")
    }
}

// MARK: - Words

enum TeamText {
    static func chipName(_ code: String) -> String {
        switch code {
        case "wildcard": "Wildcard"
        case "freehit": "Free Hit"
        case "bboost": "Bench Boost"
        case "3xc": "Triple Captain"
        default: code
        }
    }

    static func sourceMessage(_ snapshot: Team.Snapshot, nextGw: Int?) -> String {
        var text = "This is your GW\(snapshot.gw) deadline squad, as published at the deadline on \(Format.deadline(snapshot.deadline))."
        if let nextGw { text += " The fixtures shown are for GW\(nextGw)." }
        text += " Transfers or captain changes made since that deadline aren't visible here yet, and refreshing doesn't make this your current, unpublished team."
        if let value = snapshot.value { text += "\n\nSquad value \(Format.price(value))" + (snapshot.bank.map { ", \(Format.price($0)) in the bank." } ?? ".") }
        return text
    }

    /// The fixture views the Team menu offers: xFDR's variants, then FPL's own rating.
    static let fixtureChoices: [(label: String, view: FixtureView)] = [
        ("xFDR · By position", FixtureView(model: .xfdr, lens: .position)),
        ("xFDR · Overall", FixtureView(model: .xfdr, lens: .match)),
        ("xFDR · Attack", FixtureView(model: .xfdr, lens: .attack)),
        ("xFDR · Defence", FixtureView(model: .xfdr, lens: .cleanSheet)),
        ("Official FDR", FixtureView(model: .fpl, lens: .position)),
    ]

    static let fdrMessage = "xFDR is FPLToolkit's fixture difficulty: lower is easier, from 1 to 5. Each player gets the variant for their position: xFDR · Defence (clean-sheet difficulty) for goalkeepers and defenders, and xFDR · Attack for midfielders and forwards. FPL's official FDR is a separate rating; it's never made by rounding xFDR."

    static func oddsMessage(_ odds: Odds?) -> String {
        var text = "Chances from bookmakers' odds, with their margin removed: a clean sheet for goalkeepers and defenders, and scoring for midfielders and forwards. A dash means there's no market for that player, not a 0% chance."
        if let odds, let fetched = odds.fetchedAt { text += " GW\(odds.gameweek) odds, checked \(Format.ago(fetched))." }
        if odds?.available != true { text += " Odds for the next gameweek arrive 48 hours before its deadline." }
        return text
    }

    /// "CS 29%" or "Goal 52%"; "CS —" when there's no market.
    static func oddsTile(_ player: PlayerSummary, odds: Odds?) -> String {
        let prefix = player.position == .gk || player.position == .def ? "CS" : "Goal"
        guard let odds, odds.available, let chance = OddsChance.of(player, in: odds) else { return "\(prefix) —" }
        return "\(prefix) \(OddsChance.percent(chance.value))"
    }

    static func oddsSpoken(_ player: PlayerSummary, odds: Odds?) -> String {
        guard let odds, odds.available, let chance = OddsChance.of(player, in: odds) else {
            return "no betting-market estimate"
        }
        return chance.spoken
    }
}
