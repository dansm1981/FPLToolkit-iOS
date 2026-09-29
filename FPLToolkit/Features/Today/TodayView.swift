import SwiftUI

/// S05/S06, to the v2 style (Dan, 29 Sep): the team, the deadline, the gameweek card with the
/// season's standing and money, then the next move, research and leagues. Healthy checks aren't
/// repeated here; their detail lives in Settings › Data & sources.
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
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
    @State private var showingSource = false
    @State private var showingSources = false

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
                                onSource: { showingSource = true },
                                onSources: { showingSources = true })
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, ToolkitSpace.section)
                    }
                    .refreshable {
                        async let liveReload: Void = live?.load(bypassCache: true) ?? ()
                        async let teamReload: Void = team?.load(bypassCache: true) ?? ()
                        async let draftsReload: Void = drafts?.load(bypassCache: true) ?? ()
                        await resource.load(bypassCache: true)
                        _ = await (liveReload, teamReload, draftsReload)
                    }
                }
            }
        }
        .toolkitScreen()
        .navigationTitle("Today")
        .settingsButton(entryId: entryId)
        .navigationDestination(item: $pushedPlayer) { ref in PlayerDetailView(playerId: ref.id, context: ref.context) }
        .navigationDestination(item: $pushedLeague) { league in LeagueView(league: league) }
        .navigationDestination(isPresented: $showingLeagues) { LeaguesListView() }
        .navigationDestination(isPresented: $showingSources) { DataSourcesView(entryId: entryId) }
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
                await resource.load()
                _ = await (liveLoad, teamLoad, draftsLoad, leaguesLoad)
            }
        }
    }
}

struct TodayContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let loaded: Loaded<Today>
    /// False while showing a saved copy or after a failed refresh: never claim anything is clear then.
    var isCurrent = true
    var live: Resource<LiveTeam>?
    var team: Team?
    var drafts: [PlannerDraftSummary]?
    let onPlayer: (Int, String?) -> Void
    let onLeague: (LeagueList.League) -> Void
    let onLeagues: () -> Void
    let onSource: () -> Void
    let onSources: () -> Void

    private var today: Today { loaded.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TeamIdentity(name: today.entry.name, manager: today.entry.manager)

            if let next = today.gameweek.next {
                DeadlineCard(next: next)
            }

            GameweekCard(live: live, entry: today.entry, snapshot: team?.snapshot,
                         onOpen: { appModel.router.showingMatchday = true })

            status

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

            Button { appModel.router.selectedTab = .research } label: {
                HStack {
                    Text("Explore research")
                        .font(.subheadline.weight(.medium))
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
            Divider().overlay(ToolkitColor.border)

            SectionHeader(title: "Your leagues", actionTitle: "View all", action: onLeagues)
            leagues

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
        Array(live.moments.filter { $0.state != .withdrawn }.suffix(2).reversed())
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

    @ViewBuilder private var nextMoveTiles: some View {
        let next = today.gameweek.next?.id
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        layout {
            NextMoveTile(systemImage: "arrow.left.arrow.right",
                         title: latestDraft == nil ? "Start a plan" : "Plan transfers",
                         detail: planDetail(next)) {
                if let draft = latestDraft { appModel.router.pendingDraftId = draft.id }
                appModel.router.selectedTab = .planner
            }
            NextMoveTile(systemImage: "calendar", title: "View fixtures", detail: "Your next 6 GWs") {
                UserDefaults.standard.set(TeamLayout.fixtures.rawValue, forKey: "team.layout")
                appModel.router.selectedTab = .team
            }
        }
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

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: ToolkitSpace.md) {
                Image(systemName: "clock")
                    .font(.body.weight(.medium))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GW\(next.id) deadline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(Format.deadline(next.deadline))
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                Spacer()
                Text(Format.compactCountdown(to: next.deadline, now: context.date))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
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
    let onOpen: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 58
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let team = live?.loaded?.value {
            HeroCard {
                VStack(alignment: .leading, spacing: 12) {
                    header(team)
                    scoreRow(team)
                    let week = weekStats(team)
                    if !week.isEmpty {
                        Divider().overlay(ToolkitColor.heroLine)
                        // Side by side; stacked at the accessibility text sizes.
                        let layout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: ToolkitSpace.md))
                        layout {
                            ForEach(week, id: \.label) { stat in
                                miniStat(stat.label, stat.value, spoken: stat.spoken)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
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
                        Text("\(team.total.confirmed)")
                            .font(.system(size: scoreSize, weight: .bold).monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("pts")
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    if team.status != .finished {
                        Text(TodayText.recordedLine(team))
                            .font(.caption)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            let season = seasonStats
            if !season.isEmpty {
                Rectangle().fill(ToolkitColor.heroLine).frame(width: 1).frame(maxHeight: 80)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(season, id: \.label) { stat in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stat.label)
                                .font(.caption)
                                .foregroundStyle(ToolkitColor.secondaryText)
                            Text(stat.value)
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(ToolkitColor.primaryText)
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
    }

    /// Overall rank and season points (FPL's entry summary).
    private var seasonStats: [Stat] {
        var stats: [Stat] = []
        if let rank = entry.overallRank {
            stats.append(Stat(label: "Overall rank", value: Format.rank(rank), spoken: rank.formatted()))
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
        if let value = snapshot?.value {
            stats.append(Stat(label: "Team value", value: Format.price(value), spoken: Format.price(value)))
        }
        if let bank = snapshot?.bank {
            stats.append(Stat(label: "In the bank", value: Format.price(bank), spoken: Format.price(bank)))
        }
        return stats
    }

    private func miniStat(_ label: String, _ value: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(spoken)")
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

/// One of "Your next move"'s two tiles.
private struct NextMoveTile: View {
    let systemImage: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(ToolkitColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
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
    static func statusTag(_ team: LiveTeam) -> String {
        switch team.status {
        case .finished: "Final"
        case .awaitingBonus: "Awaiting bonus"
        case .upcoming: "Not started"
        default: MatchdayText.status(team.status)
        }
    }

    /// "FPL recorded · +3 provisional bonus not included", or "bonus may change".
    static func recordedLine(_ team: LiveTeam) -> String {
        if team.total.provisionalBonus > 0 {
            return "FPL recorded · +\(team.total.provisionalBonus) provisional bonus not included"
        }
        return team.status == .finished ? "FPL final score" : "FPL recorded · bonus may change"
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
