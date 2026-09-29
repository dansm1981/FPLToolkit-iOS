import SwiftUI

/// S05/S06 (design pack pp.7–8): the gameweek first, then only what's worth a decision. Healthy
/// checks are one quiet line; their detail lives in Settings › Data & sources.
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int
    @State private var resource: Resource<Today>?
    /// The gameweek score for the hero.
    @State private var live: Resource<LiveTeam>?
    /// This device's drafts, for "Continue your plan".
    @State private var drafts: Resource<PlannerDraftList>?
    @State private var pushedPlayer: PlayerRef?
    @State private var pushedLeague: LeagueList.League?
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
                                drafts: drafts?.loaded?.value.drafts,
                                onPlayer: { id, context in pushedPlayer = PlayerRef(id: id, context: context) },
                                onLeague: { pushedLeague = $0 },
                                onSource: { showingSource = true },
                                onSources: { showingSources = true })
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, ToolkitSpace.section)
                    }
                    .refreshable {
                        async let liveReload: Void = live?.load(bypassCache: true) ?? ()
                        async let draftsReload: Void = drafts?.load(bypassCache: true) ?? ()
                        await resource.load(bypassCache: true)
                        _ = await (liveReload, draftsReload)
                    }
                }
            }
        }
        .toolkitScreen()
        .navigationTitle("Today")
        .settingsButton(entryId: entryId)
        .navigationDestination(item: $pushedPlayer) { ref in PlayerDetailView(playerId: ref.id, context: ref.context) }
        .navigationDestination(item: $pushedLeague) { league in LeagueView(league: league) }
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
                let drafts = Resource(appModel.plannerRepository.list)
                self.resource = resource
                self.live = live
                self.drafts = drafts
                async let liveLoad: Void = live.load()
                async let draftsLoad: Void = drafts.load()
                async let watchLoad: Void = appModel.watch?.loadIfNeeded() ?? ()
                async let leaguesLoad: Void = appModel.leagues.loadIfNeeded()
                await resource.load()
                _ = await (liveLoad, draftsLoad, watchLoad, leaguesLoad)
            }
        }
    }
}

struct TodayContent: View {
    @Environment(AppModel.self) private var appModel
    let loaded: Loaded<Today>
    /// False while showing a saved copy or after a failed refresh: never claim "no alerts" then.
    var isCurrent = true
    var live: Resource<LiveTeam>?
    var drafts: [PlannerDraftSummary]?
    let onPlayer: (Int, String?) -> Void
    let onLeague: (LeagueList.League) -> Void
    let onSource: () -> Void
    let onSources: () -> Void

    private var today: Today { loaded.value }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(today.entry.name)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                if let next = today.gameweek.next {
                    DeadlineRow(next: next)
                }
            }

            PhaseHero(live: live, onOpen: { appModel.router.showingMatchday = true })

            status

            if !isLive {
                SectionHeader(title: "Your next move")
                CardGroup {
                    planRow
                    RowDivider()
                    LinkRow(title: "See your fixture run", detail: "Your squad, next six gameweeks", systemImage: "chart.bar.xaxis") {
                        UserDefaults.standard.set(TeamLayout.fixtures.rawValue, forKey: "team.layout")
                        appModel.router.selectedTab = .team
                    }
                }
            } else if let liveTeam = live?.loaded?.value, !latestMoments(liveTeam).isEmpty {
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

            let watching = keepAnEyeOn
            if !watching.isEmpty {
                SectionHeader(title: "Keep an eye on", actionTitle: "Watch") { appModel.router.selectedTab = .watch }
                CardGroup {
                    ForEach(Array(watching.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        LinkRow(title: item.title, detail: item.detail, systemImage: item.systemImage, action: item.action)
                    }
                }
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

    // MARK: Status

    @ViewBuilder private var status: some View {
        switch today.status {
        case .attention:
            ForEach(today.attentionInsights) { insight in
                AttentionRow(insight: insight, player: today.player(insight.playerId), gw: today.snapshot?.gw) {
                    onPlayer(insight.playerId, today.snapshot.map { "In your GW\($0.gw) squad" })
                }
            }
        case .clear where isCurrent:
            Label("No new squad alerts", systemImage: "checkmark")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .padding(.vertical, 6)
        case .clear:
            InlineNotice(text: "Latest checks unavailable. Nothing needed attention when these results were saved, but new injuries or price changes can't be confirmed until we reconnect.",
                         systemImage: "wifi.slash")
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

    @ViewBuilder private var planRow: some View {
        let next = today.gameweek.next?.id
        if let draft = latestDraft {
            LinkRow(title: next.map { "Continue your GW\($0) plan" } ?? "Continue your plan",
                    detail: TodayText.planDetail(draft), systemImage: "calendar") {
                appModel.router.pendingDraftId = draft.id
                appModel.router.selectedTab = .planner
            }
        } else {
            LinkRow(title: next.map { "Start a GW\($0) plan" } ?? "Start a plan",
                    detail: "Try transfers without touching your FPL team", systemImage: "calendar") {
                appModel.router.selectedTab = .planner
            }
        }
    }

    /// The most recently changed draft (the server's timestamps sort as text).
    private var latestDraft: PlannerDraftSummary? {
        drafts?.max { ($0.updatedAt ?? $0.createdAt ?? "") < ($1.updatedAt ?? $1.createdAt ?? "") }
    }

    private func latestMoments(_ live: LiveTeam) -> [LiveTeam.Moment] {
        Array(live.moments.filter { $0.state != .withdrawn }.suffix(2).reversed())
    }

    // MARK: Keep an eye on

    private struct EyeItem: Identifiable {
        let id: String
        let title: String
        let detail: String?
        let systemImage: String
        let action: () -> Void
    }

    /// At most two: the watched player closest to a price change, and your first mini-league.
    private var keepAnEyeOn: [EyeItem] {
        var items: [EyeItem] = []
        if let watch = appModel.watch?.watch {
            let priced = watch.effective.compactMap { item -> (Watch.Item, Double)? in
                guard let value = item.price?.tonightPct ?? item.price?.progressPct else { return nil }
                return (item, value)
            }
            if let (item, value) = priced.max(by: { abs($0.1) < abs($1.1) }), abs(value) >= 50,
               let player = watch.players[String(item.playerId)] {
                items.append(EyeItem(
                    id: "price",
                    title: "\(player.webName) · price watch",
                    detail: "\(abs(value).formatted(.number.precision(.fractionLength(0))))% of \(value >= 0 ? "rise" : "fall") threshold",
                    systemImage: value >= 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis") {
                        onPlayer(item.playerId, nil)
                    })
            }
        }
        if let league = appModel.leagues.list?.leagues.first(where: { !$0.isElite && $0.myRank != nil }),
           let rank = league.myRank {
            let gap = league.gapToFirst.map { $0 == 0 ? "top of the league" : "\($0) points off the lead" }
            items.append(EyeItem(id: "league", title: league.name,
                                 detail: [TodayText.ordinal(rank), gap].compactMap { $0 }.joined(separator: " · "),
                                 systemImage: "trophy") { onLeague(league) })
        }
        return items
    }
}

/// "GW6 deadline      Sat 10 Oct, 11:00 · in 11 days", ticking every minute (the countdown stays,
/// per Dan's note of 29 Sep).
private struct DeadlineRow: View {
    let next: NextDeadline

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack {
                Text("GW\(next.id) deadline")
                Spacer()
                Text("\(Format.deadline(next.deadline)) · \(Format.countdown(to: next.deadline, now: context.date))")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
            .accessibilityElement(children: .combine)
        }
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

/// The gameweek, as the phase allows (design pack p.8): the final score after a gameweek, the
/// FPL-recorded score with Matchday during one, and what's next before one starts. Provisional
/// bonus is never folded into the headline number.
struct PhaseHero: View {
    let live: Resource<LiveTeam>?
    let onOpen: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 58

    var body: some View {
        if let team = live?.loaded?.value {
            HeroCard {
                switch team.status {
                case .live, .between:
                    liveContent(team)
                default:
                    settledContent(team)
                }
            }
        } else if isLoading {
            HeroCard {
                Text("Loading your gameweek…")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            }
        }
    }

    private var isLoading: Bool {
        guard let live else { return true }
        if case .loading = live.phase { return true }
        return false
    }

    private func liveContent(_ team: LiveTeam) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Circle().frame(width: 6, height: 6)
                    Text("GW\(team.gameweek) live")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.positive)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(ToolkitColor.positiveFill, in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text("\(team.playing) playing")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            score(team.total.confirmed, unit: "points")
            Text(TodayText.recordedLine(team))
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
            if let headline = team.headline {
                Divider().overlay(ToolkitColor.heroLine)
                HStack(spacing: ToolkitSpace.md) {
                    IconBadge(systemImage: "sportscourt")
                    Text(headline.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: onOpen) {
                Label("Open Matchday", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(ToolkitPrimaryButtonStyle())
            .padding(.top, 4)
        }
    }

    private func settledContent(_ team: LiveTeam) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(TodayText.eyebrow(team))
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(ToolkitColor.secondaryText)
                Spacer()
                Text(team.status == .upcoming ? "Not started" : "Your points")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            HStack(alignment: .lastTextBaseline) {
                if team.status == .upcoming {
                    Text("\(team.toPlay) to play")
                        .font(.title.weight(.bold))
                        .foregroundStyle(ToolkitColor.primaryText)
                } else {
                    score(team.total.confirmed, unit: nil)
                }
                Spacer()
                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        Text("View gameweek")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
            }
            if team.status == .awaitingBonus || team.total.provisionalBonus > 0 {
                Text(TodayText.recordedLine(team))
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
    }

    private func score(_ value: Int, unit: String?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(String(value))
                .font(.system(size: scoreSize, weight: .bold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let unit {
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum TodayText {
    static func eyebrow(_ team: LiveTeam) -> String {
        switch team.status {
        case .finished: "GW\(team.gameweek) · FINAL"
        case .awaitingBonus: "GW\(team.gameweek) · AWAITING BONUS"
        case .upcoming: "GW\(team.gameweek)"
        default: "GW\(team.gameweek)"
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
        "Today checks your GW\(snapshot.gw) deadline squad, as published at the deadline on \(Format.deadline(snapshot.deadline)). Transfers or captain changes you've made since then aren't visible until the next deadline passes."
    }

    static func noSnapshotMessage(_ today: Today) -> String {
        if let next = today.gameweek.next {
            return "This team hasn't been through a deadline yet. We'll check your squad once the GW\(next.id) deadline passes."
        }
        return "This team hasn't been through a deadline yet. We'll check your squad once the next deadline passes."
    }

    static func planDetail(_ draft: PlannerDraftSummary) -> String {
        guard !draft.plannedGws.isEmpty else { return "No transfers planned" }
        let weeks = draft.plannedGws.sorted().map { "GW\($0)" }
        return "Changes planned for " + ListFormatter.localizedString(byJoining: weeks)
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
