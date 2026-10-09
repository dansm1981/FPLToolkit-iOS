import SwiftUI

/// S05/S06, to the v2 style (Dan, 29 Sep): the team, the deadline, the gameweek card with the
/// season's standing and money, then the next move, research and leagues. Healthy checks aren't
/// repeated here; their detail lives in Settings › Data & sources.
struct TodayView: View {
    /// Set by onboarding: Today offers notifications once, as soon as it first shows.
    static let askNotificationsKey = "onboarding.askNotifications"
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    let entryId: Int
    @State private var resource: Resource<Today>?
    /// The gameweek score for the card.
    @State private var live: Resource<LiveTeam>?
    /// The published squad: team value and bank for the card.
    @State private var team: Resource<Team>?
    /// This device's drafts, for "Plan transfers".
    @State private var drafts: Resource<PlannerDraftList>?
    @State private var pushedPlayer: PlayerRef?
    @State private var pushedLeague: LeagueList.League?
    @State private var showingLeagues = false
    /// The featured rival's page, and all rivals (happy-backend-pal#67).
    @State private var pushedRival: Int?
    @State private var showingRivals = false
    @State private var showingSource = false
    @State private var showingSources = false
    @State private var showingHistory = false
    @State private var showingAlertsPrimer = false

    var body: some View {
        Group {
            switch resource?.phase {
            case .loading?, nil:
                ScrollView {
                    SkeletonCards(caption: "Loading your latest checks…")
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
                            TodayContent(
                                loaded: loaded,
                                isCurrent: resource.isCurrent,
                                live: live,
                                team: team?.loaded?.value,
                                drafts: drafts?.loaded?.value.drafts,
                                onPlayer: { id, context in pushedPlayer = PlayerRef(id: id, context: context) },
                                onLeague: { pushedLeague = $0 },
                                onLeagues: { showingLeagues = true },
                                onRival: { pushedRival = $0 },
                                onRivals: { showingRivals = true },
                                onSource: { showingSource = true },
                                onSources: { showingSources = true },
                                onHistory: { showingHistory = true },
                                onOfferAlerts: { showingAlertsPrimer = true })
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, ToolkitSpace.section)
                    }
                    .refreshable {
                        async let liveReload: Void = live?.load(bypassCache: true) ?? ()
                        async let teamReload: Void = team?.load(bypassCache: true) ?? ()
                        async let draftsReload: Void = drafts?.load(bypassCache: true) ?? ()
                        async let rivalsReload: Void = appModel.rivals.load()
                        await resource.load(bypassCache: true)
                        _ = await (liveReload, teamReload, draftsReload, rivalsReload)
                    }
                }
            }
        }
        .toolkitScreen()
        .navigationTitle("Today")
        // The title in the top bar, so the team and the gameweek sit higher (Dan's mock, 30 Sep).
        .navigationBarTitleDisplayMode(.inline)
        .settingsButton(entryId: entryId)
        .navigationDestination(item: $pushedPlayer) { ref in PlayerDetailView(playerId: ref.id, context: ref.context) }
        .navigationDestination(item: $pushedLeague) { league in LeagueView(league: league) }
        .navigationDestination(isPresented: $showingLeagues) { LeaguesListView() }
        .navigationDestination(item: $pushedRival) { id in RivalView(entryId: id) }
        .navigationDestination(isPresented: $showingRivals) { RivalsScreen() }
        .navigationDestination(isPresented: $showingSources) { DataSourcesView(entryId: entryId) }
        .navigationDestination(isPresented: $showingHistory) { SeasonHistoryView(entryId: entryId) }
        // Presented by the screen, so it survives the card going once the user answers.
        .sheet(isPresented: $showingAlertsPrimer) { NotificationPrimerView() }
        .sheet(isPresented: $showingSource) {
            if let snapshot = resource?.loaded?.value.snapshot {
                InfoSheet(title: "Your published squad", message: TodayText.sourceMessage(snapshot), links: [
                    InfoSheetLink(title: "Data & sources", detail: "Published and fetched times", systemImage: "icloud") {
                        showingSources = true
                    },
                ])
            }
        }
        .task {
            if resource == nil {
                let resource = Resource(appModel.teamRepository.today(entryId: entryId))
                let live = Resource(appModel.liveRepository.team(entryId: entryId))
                let team = Resource(appModel.teamRepository.team(entryId: entryId))
                let drafts = Resource(appModel.plannerRepository.list)
                self.resource = resource
                self.live = live
                self.team = team
                self.drafts = drafts
                async let liveLoad: Void = live.load()
                async let teamLoad: Void = team.load()
                async let draftsLoad: Void = drafts.load()
                async let leaguesLoad: Void = appModel.leagues.loadIfNeeded()
                async let rivalsLoad: Void = appModel.rivals.load()
                await resource.load()
                _ = await (liveLoad, teamLoad, draftsLoad, leaguesLoad, rivalsLoad)
                if let picks = team.loaded?.value.snapshot?.picks {
                    appModel.squadIds = Set(picks.map(\.playerId))
                }
            } else {
                await refreshIfStale()
            }
        }
        .task {
            // Straight after connecting a team: one explanation, then iOS's prompt (Dan, 7 Oct).
            guard UserDefaults.standard.bool(forKey: Self.askNotificationsKey) else { return }
            UserDefaults.standard.removeObject(forKey: Self.askNotificationsKey)
            if appModel.anyPushFeature, appModel.push.permission == .notDetermined {
                showingAlertsPrimer = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshIfStale() } }
        }
    }

    /// Back on Today from another tab or the app: reload whatever is out of date (the score after
    /// 15 seconds, the rest after a minute), keeping the current copy on screen meanwhile.
    private func refreshIfStale() async {
        async let liveLoad: Void = live?.refreshIfStale(maxAge: 15) ?? ()
        async let teamLoad: Void = team?.refreshIfStale() ?? ()
        async let draftsLoad: Void = drafts?.refreshIfStale() ?? ()
        // Also catches a first load that failed or was cancelled, which used to hide "Your rival"
        // until the app was relaunched.
        async let rivalsLoad: Void = appModel.rivals.refreshIfStale()
        await resource?.refreshIfStale()
        _ = await (liveLoad, teamLoad, draftsLoad, rivalsLoad)
        if let picks = team?.loaded?.value.snapshot?.picks {
            appModel.squadIds = Set(picks.map(\.playerId))
        }
    }
}

struct TodayContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    /// "Not now" on the pick-a-rival suggestion.
    @AppStorage("today.rivalPromptDismissed") private var rivalPromptDismissed = false
    /// This device's settings, for "Follow your FPL day live" (loaded with the deadline card).
    @State private var activationPrefs: DevicePrefs?
    let loaded: Loaded<Today>
    /// False while showing a saved copy or after a failed refresh: never claim anything is clear then.
    var isCurrent = true
    var live: Resource<LiveTeam>?
    var team: Team?
    var drafts: [PlannerDraftSummary]?
    let onPlayer: (Int, String?) -> Void
    let onLeague: (LeagueList.League) -> Void
    let onLeagues: () -> Void
    var onRival: (Int) -> Void = { _ in }
    var onRivals: () -> Void = {}
    let onSource: () -> Void
    let onSources: () -> Void
    let onHistory: () -> Void
    /// "Get alerts for your players": shown once alerts are live and until the user answers.
    var onOfferAlerts: () -> Void = {}

    private var today: Today { loaded.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TeamIdentity(name: today.entry.name, manager: today.entry.manager, prominent: true)
                .padding(.bottom, 2)

            if let next = today.gameweek.next {
                DeadlineCard(next: next)
                    .task(id: next.id) {
                        guard appModel.pushFeatures?.matchdayAlerts == true else { return }
                        activationPrefs = try? await appModel.deviceSession.device().prefs
                    }
                MatchdayActivationCard(next: next, prefs: activationPrefs) { saved in
                    activationPrefs = saved ?? activationPrefs
                }
            }

            if let replay = live?.loaded?.value.replay {
                ReplayBanner(replay: replay) {
                    LiveReplay.end()
                    Task { await live?.load(bypassCache: true) }
                }
            }

            // The Deadline reveal between the deadline and the first kick-off (tasks/deadline-reveal.md).
            if let live = live?.loaded?.value, live.status == .upcoming, live.replay == nil {
                DeadlineRevealLink(gameweek: live.gameweek, prominent: true) {
                    appModel.router.open(.reveal)
                }
            }
            // The round-up once FPL confirms the gameweek, until the next deadline.
            if let live = live?.loaded?.value, live.status == .finished, live.replay == nil {
                RoundupLink(gameweek: live.gameweek) { appModel.router.open(.roundup) }
            }

            GameweekCard(live: live, entry: today.entry, snapshot: team?.snapshot,
                         squadValue: team.flatMap(TeamText.squadValue),
                         onOpen: { appModel.router.showingMatchday = true }, onHistory: onHistory)

            status

            AlertsOfferCard(open: onOfferAlerts)

            if isLive, let liveTeam = live?.loaded?.value, !latestMoments(liveTeam).isEmpty {
                SectionHeader(title: "Latest for your team")
                CardGroup {
                    ForEach(Array(latestMoments(liveTeam).enumerated()), id: \.element.id) { index, moment in
                        if index > 0 { RowDivider() }
                        LinkRow(title: MatchdayText.moment(moment, live: liveTeam),
                                detail: moment.minute.map { "\($0)′" },
                                systemImage: MatchdayText.symbol(moment.kind)) {
                            appModel.router.showingMatchday = true
                        }
                    }
                }
            }

            SectionHeader(title: "Your next move")
            nextMoveTiles

            SectionHeader(title: "Your leagues", actionTitle: "View all", action: onLeagues)
            leagues

            // The featured rival, once one is chosen (brief: one compact line, not a second table).
            if let list = appModel.rivals.list, let rival = list.featured {
                SectionHeader(title: "Your rival", actionTitle: list.rivals.count > 1 ? "All rivals" : nil,
                              action: list.rivals.count > 1 ? onRivals : nil)
                FeaturedRivalCard(rival: rival, gameweek: list.gameweek) { onRival(rival.entryId) }
            } else if let list = appModel.rivals.list, !rivalPromptDismissed {
                // No starred rival: say how to get one rather than leaving the section to vanish.
                let prompt = TodayText.rivalPrompt(hasRivals: !list.rivals.isEmpty)
                SectionHeader(title: "Your rival")
                CardGroup {
                    LinkRow(title: prompt.title, detail: prompt.detail, systemImage: "person.2", action: onRivals)
                }
                Button { rivalPromptDismissed = true } label: {
                    // The frame on the label, so the whole 44 points is the button.
                    Text("Not now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Hides this suggestion on Today")
            }

            if let snapshot = today.snapshot {
                Button(action: onSource) {
                    HStack(spacing: 4) {
                        Text(TodayText.footer(snapshot))
                        Image(systemName: "info.circle").imageScale(.small).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .accessibilityHint("Shows which squad this is based on")
            }
        }
    }

    private var isLive: Bool {
        guard let status = live?.loaded?.value.status else { return false }
        return status == .live || status == .between
    }

    private func latestMoments(_ live: LiveTeam) -> [LiveTeam.Moment] {
        // The server sends moments newest first.
        Array(live.moments.filter { $0.state != .withdrawn }.prefix(2))
    }

    // MARK: Status (only when something needs saying)

    @ViewBuilder private var status: some View {
        switch today.status {
        case .attention:
            ForEach(today.attentionInsights) { insight in
                AttentionRow(insight: insight, player: today.player(insight.playerId), gw: today.snapshot?.gw) {
                    onPlayer(insight.playerId, today.snapshot.map { "In your GW\($0.gw) squad" })
                }
            }
        case .clear where !isCurrent:
            InlineNotice(text: "Latest checks unavailable. Nothing needed attention when these results were saved, but new injuries or price changes can't be confirmed until we reconnect.",
                         systemImage: "wifi.slash")
        case .clear:
            EmptyView()
        case .unverified:
            if today.snapshot == nil {
                ToolkitCard {
                    VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                        Text("No published squad yet")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(TodayText.noSnapshotMessage(today))
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    InlineNotice(text: "Some of the data we rely on is missing or out of date, so we can't confirm your squad is clear yet.")
                    Button(action: onSources) {
                        Text("See Data & sources")
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                }
            }
        }
    }

    // MARK: Next move

    /// Three tiles of one size (v2 mock) side by side; from the larger text sizes, three rows of one
    /// size instead, so no word is broken (Dan's Pro Max, 29 Sep).
    @ViewBuilder private var nextMoveTiles: some View {
        let next = today.gameweek.next?.id
        let rows = typeSize >= .xxLarge
        let layout = rows
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        layout {
            NextMoveTile(systemImage: "arrow.left.arrow.right",
                         title: latestDraft == nil ? "Start a plan" : "Plan transfers",
                         detail: planDetail(next), asRow: rows) {
                if let draft = latestDraft { appModel.router.pendingDraftId = draft.id }
                appModel.router.openPlans()
            }
            NextMoveTile(systemImage: "tshirt", title: "View fixtures", detail: "Your squad, next 10 GWs", asRow: rows) {
                UserDefaults.standard.set(TeamLayout.fixtures.rawValue, forKey: "team.layout")
                appModel.router.openTeam()
            }
            NextMoveTile(systemImage: "chart.bar.fill", title: "Check research", detail: "Form, stats & more", asRow: rows) {
                appModel.router.selectedTab = .research
            }
        }
        // Every tile as tall as the tallest.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func planDetail(_ next: Int?) -> String {
        guard let draft = latestDraft else { return next.map { "Try GW\($0) moves safely" } ?? "Try moves safely" }
        let base = next.map { "Your GW\($0) draft" } ?? "Your draft"
        return draft.plannedGws.isEmpty ? base : base + " · changes planned"
    }

    /// The most recently changed draft (the server's timestamps sort as text).
    private var latestDraft: PlannerDraftSummary? {
        drafts?.max { ($0.updatedAt ?? $0.createdAt ?? "") < ($1.updatedAt ?? $1.createdAt ?? "") }
    }

    // MARK: Leagues

    @ViewBuilder private var leagues: some View {
        let saved = (appModel.leagues.list?.leagues ?? []).filter { !$0.isElite }
        CardGroup {
            if saved.isEmpty {
                LinkRow(title: "Add a league", detail: "Follow your mini-leagues here", systemImage: "trophy", action: onLeagues)
            } else {
                ForEach(Array(saved.prefix(3).enumerated()), id: \.element.id) { index, league in
                    if index > 0 { RowDivider() }
                    LinkRow(title: league.name, detail: TodayText.leagueDetail(league), systemImage: "trophy") {
                        onLeague(league)
                    }
                }
            }
        }
    }
}

// MARK: - Deadline

/// The deadline in a small card with a compact countdown ("10d 8h"), ticking every minute.
private struct DeadlineCard: View {
    let next: NextDeadline
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        TimelineView(.everyMinute) { context in
            // The countdown in a pill beside the date (Dan's mock, 30 Sep); under it only at the
            // accessibility sizes. One layout that changes shape keeps the same views.
            let stacked = typeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: ToolkitSpace.sm))
            HStack(alignment: stacked ? .top : .center, spacing: ToolkitSpace.md) {
                Image(systemName: "clock")
                    .font(.body.weight(.medium))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityHidden(true)
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GW\(next.id) deadline")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(Format.deadline(next.deadline))
                            .font(.caption)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)
                    Text(Format.compactCountdown(to: next.deadline, now: context.date))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ToolkitColor.raised, in: Capsule())
                        .overlay(Capsule().strokeBorder(ToolkitColor.cardLine))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolkitCard(radius: 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("GW\(next.id) deadline, \(Format.deadline(next.deadline)), \(Format.spokenCountdown(to: next.deadline, now: context.date))")
        }
    }
}

// MARK: - Gameweek card

/// The gameweek (v2): the score beside the season's standing, then this week's rank and the
/// squad's money, then the way into Matchday. The score is FPL-recorded; provisional bonus is
/// never folded in.
struct GameweekCard: View {
    let live: Resource<LiveTeam>?
    let entry: Entry
    /// The published squad, for team value and bank.
    let snapshot: Team.Snapshot?
    /// The squad at today's prices (not FPL's deadline figure, which includes the bank).
    let squadValue: Double?
    let onOpen: () -> Void
    /// The season history page (tapping the score, rank or points).
    let onHistory: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 58
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppModel.self) private var appModel
    /// Matchday v2 (Settings → Developer): the card adds your rival's gap and the latest moment.

    var body: some View {
        if let team = live?.loaded?.value {
            HeroCard {
                VStack(alignment: .leading, spacing: 12) {
                    header(team)
                    // The score and the season's standing open the season history (Dan, 29 Sep).
                    Button(action: onHistory) {
                        VStack(alignment: .leading, spacing: 8) {
                            scoreRow(team)
                            // At the large sizes this line is wider than the score's column, which
                            // keeps its own width: it runs under the whole row instead (the card
                            // spilled off the screen in a live gameweek at xxxLarge, 1 Oct).
                            if typeSize.stacksRows, team.status != .finished, team.status != .upcoming {
                                Text(TodayText.recordedLine(team))
                                    .font(.caption)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens your season history")
                        .accessibilityIdentifier("season-history")
                    let week = weekStats(team)
                    if !week.isEmpty {
                        Divider().overlay(ToolkitColor.heroLine)
                        // A row each, label and figure (Dan's mock, 30 Sep): a figure never breaks.
                        VStack(spacing: 8) {
                            ForEach(week, id: \.label) { stat in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(stat.label)
                                        .font(.subheadline)
                                        .foregroundStyle(ToolkitColor.secondaryText)
                                    Spacer(minLength: ToolkitSpace.sm)
                                    Text(stat.value)
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(ToolkitColor.primaryText)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(stat.label): \(stat.spoken)")
                            }
                        }
                        // Read together: one element rather than three short ones.
                        .accessibilityElement(children: .combine)
                    }
                    if let headline = team.headline, team.status == .live || team.status == .between {
                        Divider().overlay(ToolkitColor.heroLine)
                        HStack(spacing: ToolkitSpace.md) {
                            IconBadge(systemImage: "sportscourt")
                            Text(headline.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if team.status == .live || team.status == .between {
                        if let gap = appModel.rivals.list?.featured?.gapText {
                            HStack(spacing: ToolkitSpace.md) {
                                IconBadge(systemImage: "person.2")
                                Text(gap)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ToolkitColor.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let moment = team.pulse?.justHappened.first {
                            HStack(spacing: ToolkitSpace.md) {
                                IconBadge(systemImage: "bolt")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(moment.text)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ToolkitColor.primaryText)
                                    if let detail = moment.detail {
                                        Text(detail)
                                            .font(.footnote)
                                            .foregroundStyle(ToolkitColor.secondaryText)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Divider().overlay(ToolkitColor.heroLine)
                    openRow(team)
                }
            }
        } else if isLoading {
            HeroCard {
                Text("Loading your gameweek…")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            }
        }
    }

    private var isLoading: Bool {
        guard let live else { return true }
        if case .loading = live.phase { return true }
        return false
    }

    private func header(_ team: LiveTeam) -> some View {
        HStack {
            Label {
                Text("GW\(team.gameweek)")
            } icon: {
                Image(systemName: "trophy").foregroundStyle(ToolkitColor.accent)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ToolkitColor.primaryText)
            Spacer()
            switch team.status {
            case .live, .between:
                HStack(spacing: 5) {
                    Circle().frame(width: 6, height: 6)
                    Text("\(team.playing) playing")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.positive)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(ToolkitColor.positiveFill, in: RoundedRectangle(cornerRadius: 8))
            default:
                Tag(text: TodayText.statusTag(team))
            }
        }
    }

    private func scoreRow(_ team: LiveTeam) -> some View {
        HStack(alignment: .center, spacing: ToolkitSpace.lg) {
            VStack(alignment: .leading, spacing: 4) {
                if team.status == .upcoming {
                    Text("\(team.toPlay)")
                        .font(.system(size: scoreSize * 0.7, weight: .bold).monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("to play")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(team.total.estimated)")
                            .font(.system(size: scoreSize, weight: .bold).monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(LiveScoreText.unit(status: team.status.rawValue))
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    if team.status != .finished, !typeSize.stacksRows {
                        Text(TodayText.recordedLine(team))
                            .font(.caption)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // Its own width: the season figures take what is left and stay on one line.
            .fixedSize()
            let season = seasonStats
            if !season.isEmpty {
                Rectangle().fill(ToolkitColor.heroLine).frame(width: 1).frame(maxHeight: 80)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(season, id: \.label) { stat in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stat.label)
                                .font(.caption)
                                .foregroundStyle(ToolkitColor.secondaryText)
                            // One line (Dan's mock): the score gives way first.
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(stat.value)
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(ToolkitColor.primaryText)
                                if let move = stat.move {
                                    RankMoveArrow(current: move.current, previous: move.previous)
                                }
                            }
                            .fixedSize()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(stat.label): \(stat.spoken)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private struct Stat {
        let label: String
        let value: String
        let spoken: String
        /// A rank and last week's, for the up/down arrow.
        var move: (current: Int, previous: Int?)?
    }

    /// Overall rank and season points (FPL's entry summary).
    private var seasonStats: [Stat] {
        var stats: [Stat] = []
        if let rank = entry.overallRank {
            let moved = RankMoveArrow.spoken(current: rank, previous: entry.previousOverallRank)
            stats.append(Stat(label: "Overall rank", value: Format.rank(rank),
                              spoken: [rank.formatted(), moved].compactMap { $0 }.joined(separator: ", "),
                              move: (rank, entry.previousOverallRank)))
        }
        if let points = entry.totalPoints {
            stats.append(Stat(label: "Season points", value: points.formatted(), spoken: points.formatted()))
        }
        return stats
    }

    /// This gameweek's rank, and the published squad's value and bank.
    private func weekStats(_ team: LiveTeam) -> [Stat] {
        var stats: [Stat] = []
        if let rank = entry.gwRank, entry.summaryGw == team.gameweek {
            stats.append(Stat(label: "GW\(team.gameweek) rank", value: Format.rank(rank), spoken: rank.formatted()))
        }
        if let value = squadValue {
            stats.append(Stat(label: "Squad value", value: Format.price(value), spoken: Format.price(value)))
        }
        if let bank = snapshot?.bank {
            stats.append(Stat(label: "In the bank", value: Format.price(bank), spoken: Format.price(bank)))
        }
        return stats
    }

    @ViewBuilder private func openRow(_ team: LiveTeam) -> some View {
        if team.status == .live || team.status == .between {
            Button(action: onOpen) {
                Label("Open Matchday", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(ToolkitPrimaryButtonStyle())
        } else {
            Button(action: onOpen) {
                HStack {
                    Text("View gameweek")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View gameweek")
        }
    }
}

// MARK: - Pieces

/// One of "Your next move"'s three tiles.
private struct NextMoveTile: View {
    let systemImage: String
    let title: String
    let detail: String
    /// A full-width row (icon, words, chevron) for the larger text sizes.
    var asRow = false
    let action: () -> Void

    var body: some View {
        if asRow {
            Button(action: action) {
                HStack(spacing: ToolkitSpace.md) {
                    IconBadge(systemImage: systemImage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .toolkitCard(radius: 16)
                .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        } else {
            tile
        }
    }

    private var tile: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                IconBadge(systemImage: systemImage)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 4) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 132)
            .toolkitCard(radius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A real problem in the squad, with one Review action (S06).
private struct AttentionRow: View {
    let insight: TeamInsight
    let player: PlayerSummary?
    let gw: Int?
    let onReview: () -> Void

    var body: some View {
        Button(action: onReview) {
            AttentionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: ToolkitSpace.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ToolkitColor.warning)
                            .frame(width: 35, height: 35)
                            .background(ToolkitColor.raised, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(insight.title)
                                .font(.headline)
                                .foregroundStyle(ToolkitColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(insight.summary)
                                .font(.subheadline)
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack {
                        if let gw {
                            Text("In your GW\(gw) squad")
                                .font(.footnote)
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Text("Review")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the player")
    }
}

enum TodayText {
    /// With no starred rival: what Today suggests instead.
    nonisolated static func rivalPrompt(hasRivals: Bool) -> (title: String, detail: String) {
        hasRivals
            ? ("Star a rival", "Follow them here and on Matchday: the gap, and who's ahead live")
            : ("Pick a rival", "Someone from your mini-leagues to race all season, live on Matchday")
    }

    static func statusTag(_ team: LiveTeam) -> String { MatchdayText.status(team.status) }

    /// "52 confirmed + 3 estimated" (one score convention, Matchday v2 item 10).
    static func recordedLine(_ team: LiveTeam) -> String {
        LiveScoreText.breakdown(estimated: team.total.estimated, provisionalBonus: team.total.provisionalBonus,
                                status: team.status.rawValue)
    }

    static func footer(_ snapshot: Today.Snapshot) -> String {
        if let freeHit = snapshot.freeHitGw {
            return "Based on your GW\(snapshot.gw) squad (after your GW\(freeHit) Free Hit)"
        }
        return "Based on your GW\(snapshot.gw) squad"
    }

    static func sourceMessage(_ snapshot: Today.Snapshot) -> String {
        "Today checks your GW\(snapshot.gw) deadline squad, as published at the deadline on \(Format.deadline(snapshot.deadline)). Team value and bank are from that squad. Transfers or captain changes you've made since then aren't visible until the next deadline passes. Overall rank and season points are FPL's, as they stand."
    }

    static func noSnapshotMessage(_ today: Today) -> String {
        if let next = today.gameweek.next {
            return "This team hasn't been through a deadline yet. We'll check your squad once the GW\(next.id) deadline passes."
        }
        return "This team hasn't been through a deadline yet. We'll check your squad once the next deadline passes."
    }

    /// "12th · 30 points off the lead", or "Top of the league".
    static func leagueDetail(_ league: LeagueList.League) -> String? {
        guard let rank = league.myRank else { return league.synced ? nil : "Reading the league…" }
        var parts = [ordinal(rank) + (league.managers.map { " of \($0)" } ?? "")]
        if let gap = league.gapToFirst { parts.append(gap == 0 ? "top of the league" : "\(gap) points off the lead") }
        return parts.joined(separator: " · ")
    }

    static func ordinal(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// "GW6 deadline · Sat 10 Oct, 11:00 · in 13 days", ticking every minute (Explore's Today).
struct DeadlineLine: View {
    let next: NextDeadline

    var body: some View {
        TimelineView(.everyMinute) { context in
            Label {
                Text("GW\(next.id) deadline · \(Format.deadline(next.deadline)) · \(Format.countdown(to: next.deadline, now: context.date))")
            } icon: {
                Image(systemName: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
        }
    }
}
