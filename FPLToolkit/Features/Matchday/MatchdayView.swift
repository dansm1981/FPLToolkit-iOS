import SwiftUI

enum MatchdayMode: String, CaseIterable, Identifiable {
    case team = "Your team", feed = "Live feed", matches = "Matches"
    var id: String { rawValue }
}

/// Matchday (S30/S31; design pack pp.24–25): one score, several clear ways to inspect it. The
/// FPL-recorded total leads; provisional bonus is kept apart and never added to it. Everything is
/// the server's (contract §24); this lays it out.
struct MatchdayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let entryId: Int
    @State private var table = ResearchTable<LiveTeam>()
    /// What the previous visit saw, captured once when this visit's first data arrives.
    @State private var since: MatchdayMemory.Seen?
    @State private var capturedSince = false
    /// The live feed's items already seen when this visit began (the previous visit's, else this
    /// visit's first load): items after them are marked new.
    @State private var feedSeen: Set<String>?
    @State private var mode: MatchdayMode = .team
    @State private var sheet: MatchdaySheet?
    /// Whether the Live Activity is on the Lock Screen.
    @State private var following = false
    @State private var followError: String?
    @State private var showingHistory = false
    /// Players to watch: the player opened, the settings, and what the last load asked for.
    @State private var pushedPlayer: PlayerRef?
    @State private var showingWatchSettings = false
    @State private var watched: DevicePrefs.MatchdayPrefs?
    /// A rival opened from Your rivals.
    @State private var pushedRival: Int?

    static let refreshSeconds: UInt64 = 30
    /// A replay moves several match minutes a second: refresh more often.
    static let replayRefreshSeconds: UInt64 = 10

    enum MatchdaySheet: Identifiable, Hashable {
        case points(Int), bench, follow, estimates, sources
        var id: String {
            switch self {
            case .points(let id): "points-\(id)"
            case .bench: "bench"
            case .follow: "follow"
            case .estimates: "estimates"
            case .sources: "sources"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                ResearchTableView(table: table, caption: "Loading your matchday…", retry: reload) { live in
                    content(live)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable {
            await table.refresh()
            remember()
        }
        .toolkitScreen()
        .navigationTitle("Matchday")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { sheet = .sources } label: {
                    Label("Score sources and definitions", systemImage: "info.circle")
                }
            }
        }
        .sheet(item: $sheet) { which in
            if let live = table.current?.loaded?.value {
                sheetView(which, live: live)
            }
        }
        .navigationDestination(isPresented: $showingHistory) { SeasonHistoryView(entryId: entryId) }
        .navigationDestination(item: $pushedPlayer) { ref in PlayerDetailView(playerId: ref.id, context: ref.context) }
        .navigationDestination(isPresented: $showingWatchSettings) { MatchdayWatchSettingsView() }
        .navigationDestination(item: $pushedRival) { id in RivalView(entryId: id) }
        .onChange(of: showingWatchSettings) { _, showing in
            // Back from the settings: load again if who's watched changed.
            if !showing, watched != MatchdayWatch.current { reload() }
        }
        .task(id: entryId) {
            await load()
            // Keep it live while matches are on; the server refreshes every 15 seconds. A replay
            // refreshes throughout.
            while !Task.isCancelled {
                let replaying = LiveReplay.current != nil
                try? await Task.sleep(nanoseconds: (replaying ? Self.replayRefreshSeconds : Self.refreshSeconds) * 1_000_000_000)
                guard !Task.isCancelled else { continue }
                if !replaying {
                    guard let status = table.current?.loaded?.value.status,
                          [.live, .between, .awaitingBonus].contains(status) else { continue }
                }
                await table.refresh()
                remember()
            }
        }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        let watch = MatchdayWatch.current
        watched = watch
        // Your saved rivals come with your own team's live data, from this device (Stage B).
        await appModel.rivals.loadIfNeeded()
        let withRivals = entryId == appModel.entryId && !(appModel.rivals.list?.rivals.isEmpty ?? true)
        await table.load(appModel.liveRepository.team(entryId: entryId, watch: watch,
                                                      rivalsVia: withRivals ? appModel.deviceSession : nil))
        remember()
    }

    /// Captures the previous visit once, saves what this one has seen, and brings the Live Activity
    /// up to date.
    private func remember() {
        guard let live = table.current?.loaded?.value else { return }
        if feedSeen == nil, let feed = live.feed {
            let previous = live.replay == nil
                ? MatchdayMemory.read(entryId: entryId, gameweek: live.gameweek)?.feedIds
                : nil
            feedSeen = Set(previous ?? feed.map(\.id))
        }
        // A replay is past data: it leaves the "since you last checked" memory alone.
        if live.replay != nil {
            let updated = self.updated
            Task { await MatchdayActivity.update(live, entryId: entryId, updated: updated) }
            return
        }
        if !capturedSince {
            since = MatchdayMemory.read(entryId: entryId, gameweek: live.gameweek)
            capturedSince = true
        }
        MatchdayMemory.save(live, entryId: entryId)
        let updated = self.updated
        Task {
            await MatchdayActivity.update(live, entryId: entryId, updated: updated)
            following = MatchdayActivity.running(entryId: entryId) != nil
        }
    }

    private func follow(_ live: LiveTeam) {
        do {
            try MatchdayActivity.start(live, entryId: entryId, updated: updated)
            following = true
            followError = nil
        } catch {
            followError = "Couldn't start it on the Lock Screen. Check Live Activities are on in Settings → FPLToolkit."
        }
    }

    @ViewBuilder
    private func content(_ live: LiveTeam) -> some View {
        if let replay = live.replay {
            ReplayBanner(replay: replay) {
                LiveReplay.end()
                reload()
            }
        }
        Text("GW\(live.gameweek) · \(MatchdayText.status(live.status))")
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
        MatchdayScoreHero(live: live, updated: updated,
                          canFollow: Self.canFollow(live.status),
                          onFollow: { sheet = .follow })
        if let since, let catchUp = MatchdayMemory.catchUp(live, since: since) {
            MatchdayCatchUp(text: catchUp)
        }
        // The season behind this week (Dan, 29 Sep): points and rank over time.
        CardGroup {
            LinkRow(title: "Season history", detail: "Points and rank, week by week", systemImage: "chart.xyaxis.line") {
                showingHistory = true
            }
        }
        Picker("Show", selection: $mode) {
            ForEach(MatchdayMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 4)
        switch mode {
        case .team:
            MatchdayTeamRows(live: live, players: live.squad.filter { $0.position <= 11 }) { sheet = .points($0) }
            SectionHeader(title: live.chip == "bboost" ? "Bench (Bench Boost)" : "Bench")
            CardGroup {
                LinkRow(title: benchTitle(live), detail: benchDetail(live), systemImage: "tshirt") { sheet = .bench }
            }
            if let rivals = live.rivals {
                MatchdayRivalsSection(live: live, rivals: rivals) { pushedRival = $0 }
            }
            MatchdayWatchingSection(live: live,
                                    onPlayer: { id, reason in pushedPlayer = PlayerRef(id: id, context: reason) },
                                    onSettings: { showingWatchSettings = true })
        case .feed:
            if let feed = live.feed {
                MatchdayFeed(live: live, feed: feed, seen: feedSeen)
            } else {
                MatchdayMoments(live: live)
            }
        case .matches:
            MatchdayFixtures(live: live)
        }
        if live.total.provisionalBonus > 0 {
            Button { sheet = .estimates } label: {
                HStack {
                    Text("Estimated additions")
                        .foregroundStyle(ToolkitColor.secondaryText)
                    Spacer()
                    Text("+\(live.total.provisionalBonus) bonus")
                        .foregroundStyle(ToolkitColor.link)
                    Image(systemName: "info.circle").foregroundStyle(ToolkitColor.link).accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 15)
                .frame(minHeight: 52)
                .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Estimated additions: \(live.total.provisionalBonus) provisional bonus, not included in the score")
            .padding(.top, ToolkitSpace.sm)
        }
    }

    private func benchTitle(_ live: LiveTeam) -> String {
        let bench = live.squad.filter { $0.position > 11 }
        switch live.status {
        case .finished, .awaitingBonus: return "\(live.total.benchPoints) bench point\(live.total.benchPoints == 1 ? "" : "s")"
        default: return "\(bench.count) players on your bench"
        }
    }

    private func benchDetail(_ live: LiveTeam) -> String {
        if live.chip == "bboost" { return "Counting this gameweek" }
        if !live.autoSubs.isEmpty { return "\(live.autoSubs.count) automatic sub\(live.autoSubs.count == 1 ? "" : "s") as it stands" }
        switch live.status {
        case .finished, .awaitingBonus: return "Not included in your \(live.total.confirmed) points"
        default: return "Automatic subs are decided as matches finish"
        }
    }

    @ViewBuilder private func sheetView(_ which: MatchdaySheet, live: LiveTeam) -> some View {
        switch which {
        case .points(let id):
            if let player = live.squad.first(where: { $0.playerId == id }) {
                PointsBreakdownSheet(player: player, live: live, onSources: { sheet = .sources })
            }
        case .bench:
            NavigationStack {
                ScrollView {
                    MatchdayTeamRows(live: live, players: live.squad.filter { $0.position > 11 }) { sheet = .points($0) }
                        .padding(.horizontal, 18)
                }
                .toolkitScreen()
                .navigationTitle("Bench")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
            }
            .presentationDetents([.medium, .large])
        case .follow:
            NavigationStack {
                ScrollView {
                    MatchdayFollowCard(
                        following: following,
                        enabled: MatchdayActivity.isEnabled,
                        error: followError,
                        start: { follow(live) },
                        stop: {
                            Task {
                                await MatchdayActivity.stop(entryId: entryId)
                                following = false
                            }
                        })
                        .padding(.horizontal, ToolkitSpace.page)
                }
                .toolkitScreen()
                .navigationTitle("Follow Matchday")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
            }
            .presentationDetents([.medium])
        case .estimates:
            InfoSheet(title: "Estimated additions", message: MatchdayCopy.estimates)
        case .sources:
            InfoSheet(title: "Where the points come from", message: MatchdayCopy.sources)
        }
    }

    /// Following makes sense until FPL confirms the gameweek (debug builds allow it any time, to test).
    static func canFollow(_ status: LiveTeam.Status) -> Bool {
        #if DEBUG
        return true
        #else
        return status != .finished
        #endif
    }

    private var updated: Date? {
        table.current?.loaded?.meta.freshness?.first { $0.source == .livePoints }?.asOf
    }
}

enum MatchdayCopy {
    static let estimates = "Provisional bonus is Toolkit's estimate from the live BPS, kept apart from the FPL-recorded score. When FPL records the bonus, the estimate goes rather than being added a second time. Automatic subs are shown as they stand until the matches finish."
    static let sources = """
    FPL recorded: the points FPL has published, including the captain's multiplier and any transfer cost. FPL can still correct them.

    Toolkit estimate: provisional bonus and automatic subs as they stand, never added to the recorded score.

    Football context: match events and stats from our data provider. They explain what happened; they're never points.

    Full time isn't final until FPL adds the bonus.
    """
}

// MARK: - Score

struct MatchdayScoreHero: View {
    let live: LiveTeam
    let updated: Date?
    let canFollow: Bool
    let onFollow: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 52

    var body: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .lastTextBaseline) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(live.total.confirmed)")
                            .font(.system(size: scoreSize, weight: .bold).monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text("pts")
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    Spacer()
                    stateTag
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(recordedLine)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if canFollow {
                        Button(action: onFollow) {
                            Image(systemName: "lock.iphone")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ToolkitColor.link)
                        .accessibilityLabel("Follow on your Lock Screen")
                    }
                }
                if !details.isEmpty {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var stateTag: some View {
        switch live.status {
        case .live, .between:
            HStack(spacing: 5) {
                Circle().frame(width: 6, height: 6)
                Text("\(live.playing) playing")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ToolkitColor.positive)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(ToolkitColor.positiveFill, in: RoundedRectangle(cornerRadius: 8))
        default:
            Tag(text: MatchdayText.status(live.status))
        }
    }

    private var recordedLine: String {
        var line: String
        switch live.status {
        case .finished: line = "FPL final score"
        case .awaitingBonus: line = "FPL recorded · bonus to come"
        case .upcoming: line = "\(live.toPlay) players to play"
        default: line = "FPL recorded · bonus may change"
        }
        if let updated, live.status == .live || live.status == .between {
            line += " · \(updated.formatted(date: .omitted, time: .shortened))"
        }
        return line
    }

    private var details: String {
        var parts: [String] = []
        if let chip = MatchdayText.chip(live.chip) { parts.append(chip) }
        if live.total.transferCost > 0 { parts.append("includes −\(live.total.transferCost) transfer cost") }
        return parts.joined(separator: " · ")
    }
}

struct MatchdayCatchUp: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(ToolkitColor.information)
        }
        .font(.subheadline)
        .padding(ToolkitSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.informationFill, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Lock Screen

struct MatchdayFollowCard: View {
    let following: Bool
    let enabled: Bool
    let error: String?
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            if !enabled {
                Label("Live Activities are off for FPLToolkit. Turn them on in Settings → FPLToolkit to follow your team on the Lock Screen.",
                      systemImage: "lock.iphone")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if following {
                Label("On your Lock Screen", systemImage: "lock.iphone")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.positive)
                Text("It updates while FPLToolkit is open. Once alerts are switched on it will update by itself.")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Stop following", action: stop)
                    .buttonStyle(ToolkitSecondaryButtonStyle())
            } else {
                Text("Your whole squad's score and the moment that matters most, on the Lock Screen and in the Dynamic Island.")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Follow on your Lock Screen", action: start)
                    .buttonStyle(ToolkitPrimaryButtonStyle())
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, ToolkitSpace.sm)
    }
}

// MARK: - Your team

/// Squad rows: live players first by relevance is the server's order; finished players are quieter.
struct MatchdayTeamRows: View {
    @Environment(AppModel.self) private var appModel
    let live: LiveTeam
    let players: [LiveTeam.Player]
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                if index > 0 { Divider().overlay(ToolkitColor.border) }
                if let summary = live.player(player.playerId) {
                    Button { onSelect(player.playerId) } label: {
                        PlayerListRow(player: summary,
                                      role: player.isCaptain ? "C" : player.isViceCaptain ? "V" : nil,
                                      detail: MatchdayRowText.state(player, live: live),
                                      value: "\(player.points * max(player.multiplier, 1))",
                                      valueDetail: player.provisionalBonus > 0 ? "+\(player.provisionalBonus * max(player.multiplier, 1)) est." : nil,
                                      spokenDetail: MatchdayRowText.spoken(player, live: live))
                            .opacity(player.counted || player.position > 11 ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows how the points add up")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }
}

enum MatchdayRowText {
    /// "67′ · DEFCON 8/10", "Finished · 90 min", "Kick-off Sat 15:00".
    static func state(_ player: LiveTeam.Player, live: LiveTeam) -> String {
        var parts: [String] = []
        if player.autoSub == .in { parts.append("Auto-sub in") }
        if player.autoSub == .out { parts.append("Auto-sub out") }
        let fixture = player.fixtureIds.compactMap { live.fixture($0) }.first
        switch player.state {
        case .blank: parts.append("No fixture")
        case .notStarted:
            if let kickoff = fixture?.kickoff { parts.append("Kick-off \(Format.deadline(kickoff))") }
            if let lineup = player.lineup, let text = MatchdayText.lineup(lineup) { parts.append(text) }
        case .inPlay:
            parts.append(fixture?.minute.map { "\($0)′" } ?? "Playing")
            if let d = player.next.defcon, !d.reached { parts.append("DEFCON \(d.count)/\(d.threshold)") }
            else if player.isCaptain { parts.append("captain ×\(max(player.multiplier, 2))") }
        case .done:
            parts.append(player.minutes > 0 ? "Finished · \(player.minutes) min" : "Didn't play")
        case .unknown: break
        }
        return parts.joined(separator: " · ")
    }

    static func spoken(_ player: LiveTeam.Player, live: LiveTeam) -> String {
        let points = player.points * max(player.multiplier, 1)
        var parts = [state(player, live: live), "\(points) FPL-recorded point\(points == 1 ? "" : "s")"]
        if player.provisionalBonus > 0 { parts.append("plus \(player.provisionalBonus) estimated bonus, not included") }
        if !player.counted && player.position <= 11 { parts.append("not counting") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - Points breakdown (S31)

/// One player's points: the FPL-recorded total and its contributions, with provisional bonus in its
/// own band ("not included") and the thresholds still in play.
/// Everything the player did in FPL's counts (Dan, 29 Sep: "almost the total action for the
/// player"): the scoring stats, then DEFCON and its parts, BPS and expected goals, points or not.
private struct StatLineGrid: View {
    let line: LiveTeam.Player.Line
    let goalkeeper: Bool
    let defconThreshold: Int?

    private var items: [FigureGrid.Item] {
        var items: [FigureGrid.Item] = [.init(label: "Minutes", value: "\(line.minutes)")]
        func add(_ label: String, _ value: Int, always: Bool = false) {
            if always || value != 0 { items.append(.init(label: label, value: "\(value)")) }
        }
        add("Goals", line.goals)
        add("Assists", line.assists)
        add("Clean sheets", line.cleanSheets)
        add("Goals conceded", line.goalsConceded)
        add("Saves", line.saves, always: goalkeeper)
        add("Penalties saved", line.penaltiesSaved)
        add("Penalties missed", line.penaltiesMissed)
        add("Own goals", line.ownGoals)
        add("Yellow cards", line.yellowCards)
        add("Red cards", line.redCards)
        add("Bonus", line.bonus)
        add("BPS", line.bps, always: true)
        if !goalkeeper {
            items.append(.init(label: "DEFCON actions",
                               value: defconThreshold.map { "\(line.defensiveContribution)/\($0)" } ?? "\(line.defensiveContribution)",
                               spoken: defconThreshold.map { "\(line.defensiveContribution) of \($0)" } ?? "\(line.defensiveContribution)"))
            add("Clearances, blocks, interceptions", line.clearancesBlocksInterceptions, always: true)
            add("Tackles", line.tackles, always: true)
            add("Recoveries", line.recoveries, always: true)
        }
        let xg = line.expectedGoals.formatted(.number.precision(.fractionLength(2)))
        let xa = line.expectedAssists.formatted(.number.precision(.fractionLength(2)))
        items.append(.init(label: "xG", value: xg, spoken: "expected goals \(xg)"))
        items.append(.init(label: "xA", value: xa, spoken: "expected assists \(xa)"))
        return items
    }

    var body: some View {
        FigureGrid(items: items)
    }
}

struct PointsBreakdownSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let player: LiveTeam.Player
    let live: LiveTeam
    let onSources: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 52

    var body: some View {
        let summary = live.player(player.playerId)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    HeroCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("FPL-recorded")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ToolkitColor.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                                        Text("\(player.points * max(player.multiplier, 1))")
                                            .font(.system(size: scoreSize, weight: .bold).monospacedDigit())
                                            .foregroundStyle(ToolkitColor.primaryText)
                                        Text("pts")
                                            .font(.headline)
                                            .foregroundStyle(ToolkitColor.secondaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                                if let summary {
                                    PlayerPhoto(path: summary.photo, clubLogo: appModel.club(summary.clubId)?.logo, size: 56, scalesWithText: false)
                                }
                            }
                            if player.provisionalBonus > 0 {
                                Divider().overlay(ToolkitColor.heroLine)
                                HStack {
                                    Text("Provisional bonus")
                                        .foregroundStyle(ToolkitColor.secondaryText)
                                    Spacer()
                                    Text("+\(player.provisionalBonus * max(player.multiplier, 1)) not included")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(ToolkitColor.accent)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                    SectionHeader(title: "Points breakdown")
                    VStack(spacing: 0) {
                        if player.breakdown.isEmpty {
                            Text("No points yet.")
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        }
                        ForEach(Array(player.breakdown.enumerated()), id: \.offset) { index, line in
                            if index > 0 { Divider().overlay(ToolkitColor.border) }
                            HStack {
                                Text(MatchdayText.stat(line.stat, value: line.value))
                                Spacer()
                                Text("\(line.points > 0 ? "+" : "")\(line.points)")
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.primaryText)
                            .frame(minHeight: 44)
                        }
                        if player.multiplier > 1 {
                            Divider().overlay(ToolkitColor.border)
                            HStack {
                                Text(player.multiplier == 3 ? "Triple captain" : "Captain")
                                Spacer()
                                Text("×\(player.multiplier)").fontWeight(.semibold)
                            }
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.primaryText)
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 15)
                    .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))

                    if let line = player.line, line.minutes > 0 {
                        SectionHeader(title: player.fixtureIds.count > 1 ? "Match stats (both matches)" : "Match stats")
                        StatLineGrid(line: line, goalkeeper: summary?.position == .gk,
                                     defconThreshold: player.next.defcon?.threshold)
                    }

                    if player.state == .inPlay, player.next.defcon != nil || player.next.saves != nil || player.next.bonus != nil {
                        SectionHeader(title: "Still in play")
                        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                            if let d = player.next.defcon {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(d.reached ? "DEFCON reached" : "\(d.threshold - d.count) away from DEFCON")
                                        .font(.headline)
                                        .foregroundStyle(ToolkitColor.primaryText)
                                    Text("\(d.count) / \(d.threshold) defensive contributions")
                                        .font(.subheadline)
                                        .foregroundStyle(ToolkitColor.secondaryText)
                                    ProgressLine(fraction: Double(d.count) / Double(max(d.threshold, 1)), tint: ToolkitColor.positive)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            if let s = player.next.saves {
                                Text(s.toNextPoint == 1 ? "\(s.count) saves · one more for a save point" : "\(s.count) saves")
                                    .font(.subheadline)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                            if let b = player.next.bonus {
                                Text(bonusText(b))
                                    .font(.subheadline)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                        }
                        .padding(17)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
                    }
                    if let c = player.context, let text = MatchdayText.context(c) {
                        Label(text, systemImage: "sportscourt")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.information)
                    }
                    Button {
                        dismiss()
                        onSources()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Score sources & definitions")
                            Image(systemName: "info.circle").imageScale(.small).accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, ToolkitSpace.xl)
            }
            .toolkitScreen()
            .navigationTitle(summary?.webName ?? "Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private var subtitle: String {
        var parts = ["GW\(live.gameweek)"]
        parts.append(MatchdayRowText.state(player, live: live))
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func bonusText(_ b: LiveTeam.NextPoints.Bonus) -> String {
        if b.provisional > 0 {
            let gap = b.bpsToNext.map { $0 == 0 ? " · level for more" : " · \($0) BPS off more" } ?? ""
            return "Estimated \(b.provisional) bonus (\(b.bps) BPS)\(gap)"
        }
        return b.bpsToNext.map { "\(b.bps) BPS · \($0) off bonus" } ?? "\(b.bps) BPS"
    }
}

// MARK: - Moments

struct MatchdayMoments: View {
    let live: LiveTeam

    var body: some View {
        if live.moments.isEmpty {
            Text(live.status == .upcoming ? "Nothing yet: moments appear here once your players' matches start." : "No moments for your players yet.")
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(live.moments.reversed().enumerated()), id: \.element.id) { index, m in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    MomentRow(moment: m, live: live)
                }
            }
            .padding(.horizontal, 15)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }
}

private struct MomentRow: View {
    @Environment(AppModel.self) private var appModel
    let moment: LiveTeam.Moment
    let live: LiveTeam

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Text(moment.minute.map { "\($0)′" } ?? "")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(ToolkitColor.secondaryText)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                // The player's club badge first, so a scan down the list finds a club's moments.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ClubLogo(clubId: live.player(moment.playerId)?.clubId, size: 16)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                    Text(MatchdayText.moment(moment, live: live))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .strikethrough(moment.state == .withdrawn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            Spacer(minLength: 0)
            IconBadge(systemImage: MatchdayText.symbol(moment.kind))
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        var parts: [String] = []
        if let f = live.fixture(moment.fixtureId) {
            parts.append(MatchdayText.fixtureName(f) { appModel.club($0)?.shortName })
        }
        switch moment.state {
        case .reported: parts.append(moment.kind == .goal ? "FPL points updating" : "Football context")
        case .confirmed: parts.append("Recorded by FPL")
        case .withdrawn: parts.append("Disallowed")
        case .unknown: break
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Matches

struct MatchdayFixtures: View {
    @Environment(AppModel.self) private var appModel
    let live: LiveTeam
    /// The match opened to show its stats (Dan, 29 Sep: "click a particular game").
    @State private var expanded: Int?

    var body: some View {
        if live.fixtures.isEmpty {
            Text("No matches for your players this gameweek.")
                .foregroundStyle(ToolkitColor.secondaryText)
        } else {
            VStack(spacing: 0) {
                let sorted = live.fixtures.sorted { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) }
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, f in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    if f.state == .notStarted {
                        // Nothing to open yet: a plain row, not a disabled (greyed-out) button,
                        // so the kick-off time keeps its contrast (found by the replay audit).
                        row(f)
                            .accessibilityElement(children: .combine)
                    } else {
                        Button {
                            withAnimation(.snappy) { expanded = expanded == f.id ? nil : f.id }
                        } label: {
                            row(f)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(expanded == f.id ? "Hides the match stats" : "Shows the match stats")
                        .accessibilityAddTraits(expanded == f.id ? .isSelected : [])
                    }
                    if expanded == f.id {
                        MatchStatsPanel(fixtureId: f.id, gameweek: live.gameweek, squad: Set(live.squad.map(\.playerId)))
                            .padding(.bottom, ToolkitSpace.md)
                    }
                }
            }
            .padding(.horizontal, 15)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            Text("Tap a match for its goals, assists, cards, saves, bonus and DEFCON counts.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
    }

    private func row(_ f: LiveTeam.Fixture) -> some View {
        HStack(spacing: ToolkitSpace.sm) {
            ClubLabel(clubId: f.homeClubId, text: appModel.club(f.homeClubId)?.shortName ?? "?", logoSize: 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(score(f))
                .font(.headline.monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
            ClubLabel(clubId: f.awayClubId, text: appModel.club(f.awayClubId)?.shortName ?? "?", logoSize: 18)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Tag(text: state(f))
            if f.state != .notStarted {
                Image(systemName: expanded == f.id ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(ToolkitColor.primaryText)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(f))
    }

    private func score(_ f: LiveTeam.Fixture) -> String {
        f.state == .notStarted ? "v" : "\(f.homeScore ?? 0) – \(f.awayScore ?? 0)"
    }

    private func state(_ f: LiveTeam.Fixture) -> String {
        switch f.state {
        case .notStarted: return f.kickoff.map { $0.formatted(date: .omitted, time: .shortened) } ?? "TBC"
        case .inPlay: return f.minute.map { "\($0)′" } ?? "Live"
        case .finished: return f.bonusConfirmed ? "FT" : "FT · bonus to come"
        case .unknown: return ""
        }
    }

    private func spoken(_ f: LiveTeam.Fixture) -> String {
        let home = appModel.club(f.homeClubId)?.name ?? "Home"
        let away = appModel.club(f.awayClubId)?.name ?? "Away"
        switch f.state {
        case .notStarted:
            return "\(home) against \(away), kick-off \(f.kickoff.map { Format.deadline($0) } ?? "to be confirmed")"
        case .inPlay:
            return "\(home) \(f.homeScore ?? 0), \(away) \(f.awayScore ?? 0), \(f.minute.map { "\($0) minutes" } ?? "in play")"
        default:
            return "\(home) \(f.homeScore ?? 0), \(away) \(f.awayScore ?? 0), full time"
        }
    }
}
