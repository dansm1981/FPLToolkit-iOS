import SwiftUI

/// Matchday (Phase 3, P3-3; tasks/phase-3.md §4.2): the whole team as one live event. The score as
/// it stands, what changed since you last looked, the points within reach, the moments, the live
/// squad and the fixtures. Everything is the server's (contract §24); this lays it out, with
/// every number labelled FPL-recorded, Toolkit estimate or football context.
struct MatchdayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let entryId: Int
    @State private var table = ResearchTable<LiveTeam>()
    /// What the previous visit saw, captured once when this visit's first data arrives.
    @State private var since: MatchdayMemory.Seen?
    @State private var capturedSince = false
    @State private var expanded: Set<Int> = []
    /// Whether the Live Activity is on the Lock Screen.
    @State private var following = false
    @State private var followError: String?

    static let refreshSeconds: UInt64 = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                ResearchTableView(table: table, caption: "Loading your matchday…", retry: reload) { live in
                    content(live)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
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
        }
        .task(id: entryId) {
            await load()
            // Keep it live while matches are on; the server refreshes every 15 seconds.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.refreshSeconds * 1_000_000_000)
                guard !Task.isCancelled, let status = table.current?.loaded?.value.status,
                      [.live, .between, .awaitingBonus].contains(status) else { continue }
                await table.refresh()
                remember()
            }
        }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.liveRepository.team(entryId: entryId))
        remember()
    }

    /// Captures the previous visit once, saves what this one has seen, and brings the Live Activity
    /// up to date.
    private func remember() {
        guard let live = table.current?.loaded?.value else { return }
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
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MatchdayScoreCard(live: live, updated: updated)
            if Self.canFollow(live.status) {
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
            }
            if let since, let catchUp = MatchdayMemory.catchUp(live, since: since) {
                MatchdayCatchUp(text: catchUp)
            }
            if live.status == .live {
                MatchdayNextPoints(live: live)
            }
            MatchdayMoments(live: live)
            MatchdaySquad(live: live, expanded: $expanded)
            MatchdayFixtures(live: live)
            MatchdayTrustKey()
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

// MARK: - Score

struct MatchdayScoreCard: View {
    let live: LiveTeam
    let updated: Date?

    var body: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                HStack(spacing: ToolkitSpace.sm) {
                    Text("GW\(live.gameweek)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                    MatchdayStatusPill(status: live.status)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm) {
                    Text("\(live.total.estimated)")
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(live.total.provisionalBonus > 0 ? "estimated points" : "points")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                if live.total.provisionalBonus > 0 {
                    TrustLine(kind: .estimate, text: "Includes \(live.total.provisionalBonus) projected bonus")
                } else {
                    TrustLine(kind: .fpl, text: live.status == .finished ? "Confirmed by FPL" : "FPL-recorded")
                }
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let updated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts: [String] = []
        if live.status == .live || live.status == .between || live.status == .upcoming {
            parts.append("\(live.playing) playing · \(live.toPlay) to play")
        }
        if let chip = MatchdayText.chip(live.chip) { parts.append(chip) }
        if live.total.transferCost > 0 { parts.append("−\(live.total.transferCost) transfer cost") }
        parts.append("Bench \(live.total.benchPoints)")
        return parts.joined(separator: " · ")
    }
}

struct MatchdayStatusPill: View {
    let status: LiveTeam.Status

    var body: some View {
        Text(MatchdayText.status(status))
            .font(.caption.weight(.bold))
            .foregroundStyle(status == .live ? ToolkitColor.positive : ToolkitColor.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status == .live ? ToolkitColor.positiveFill : ToolkitColor.raised,
                        in: RoundedRectangle(cornerRadius: ToolkitRadius.pill))
    }
}

/// A line tagged with where its number comes from.
struct TrustLine: View {
    enum Kind { case fpl, estimate, context }
    let kind: Kind
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(colour)
    }

    private var symbol: String {
        switch kind {
        case .fpl: "checkmark.seal"
        case .estimate: "hourglass"
        case .context: "sportscourt"
        }
    }

    private var colour: Color {
        switch kind {
        case .fpl: ToolkitColor.positive
        case .estimate: ToolkitColor.warning
        case .context: ToolkitColor.information
        }
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
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                if !enabled {
                    Label("Live Activities are off for FPLToolkit. Turn them on in Settings → FPLToolkit to follow your team on the Lock Screen.",
                          systemImage: "lock.iphone")
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if following {
                    HStack {
                        Label("On your Lock Screen", systemImage: "lock.iphone")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.positive)
                        Spacer()
                        Button("Stop", action: stop)
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    Text("It updates while FPLToolkit is open. Once alerts are switched on it will update by itself.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button(action: start) {
                        Label("Follow on your Lock Screen", systemImage: "lock.iphone")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.link)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text("Your score and the moment that matters most, on the Lock Screen and in the Dynamic Island.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Next points

/// The points within reach for counted players whose match is on: thresholds from FPL's own counts.
struct MatchdayNextPoints: View {
    let live: LiveTeam

    var body: some View {
        let rows = live.squad.filter { $0.counted && $0.state == .inPlay }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                MatchdaySectionTitle(title: "Next points")
                ToolkitCard {
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        ForEach(rows) { p in
                            NextPointsRow(player: p, summary: live.player(p.playerId))
                            if p.id != rows.last?.id { Divider().overlay(ToolkitColor.border) }
                        }
                    }
                }
            }
        }
    }
}

private struct NextPointsRow: View {
    let player: LiveTeam.Player
    let summary: PlayerSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary?.webName ?? "Player \(player.playerId)")
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
            if let d = player.next.defcon {
                ProgressLine(label: d.reached ? "DEFCON reached" : "DEFCON \(d.count)/\(d.threshold)",
                             value: Double(min(d.count, d.threshold)), total: Double(d.threshold),
                             done: d.reached)
            }
            if let s = player.next.saves {
                Text(s.toNextPoint == 1 ? "\(s.count) saves · one more for a save point" : "\(s.count) saves")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            if let b = player.next.bonus {
                TrustLine(kind: .estimate, text: bonusText(b))
            }
            if let cs = player.next.cleanSheet, summary?.position == .gk || summary?.position == .def || summary?.position == .mid {
                Text(cs.alive ? "Clean sheet still on" : "Clean sheet gone (\(cs.conceded) conceded)")
                    .font(.subheadline)
                    .foregroundStyle(cs.alive ? ToolkitColor.positive : ToolkitColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bonusText(_ b: LiveTeam.NextPoints.Bonus) -> String {
        if b.provisional > 0 {
            let gap = b.bpsToNext.map { $0 == 0 ? " · level for more" : " · \($0) BPS off more" } ?? ""
            return "On \(b.provisional) bonus (\(b.bps) BPS)\(gap)"
        }
        return b.bpsToNext.map { "\(b.bps) BPS · \($0) off bonus" } ?? "\(b.bps) BPS"
    }
}

private struct ProgressLine: View {
    let label: String
    let value: Double
    let total: Double
    let done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(done ? .semibold : .regular))
                .foregroundStyle(done ? ToolkitColor.positive : ToolkitColor.primaryText)
            ProgressView(value: value, total: total)
                .tint(done ? ToolkitColor.positive : ToolkitColor.accent)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Moments

struct MatchdayMoments: View {
    let live: LiveTeam

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            MatchdaySectionTitle(title: "What changed for you")
            ToolkitCard {
                if live.moments.isEmpty {
                    Text(live.status == .upcoming ? "Nothing yet: moments appear here once your players' matches start." : "No moments for your players yet.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        ForEach(live.moments) { m in
                            MomentRow(moment: m, live: live)
                            if m.id != live.moments.last?.id { Divider().overlay(ToolkitColor.border) }
                        }
                    }
                }
            }
        }
    }
}

private struct MomentRow: View {
    @Environment(AppModel.self) private var appModel
    let moment: LiveTeam.Moment
    let live: LiveTeam

    var body: some View {
        HStack(alignment: .top, spacing: ToolkitSpace.md) {
            Image(systemName: MatchdayText.symbol(moment.kind))
                .font(.body.weight(.semibold))
                .foregroundStyle(moment.state == .withdrawn ? ToolkitColor.secondaryText : ToolkitColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(MatchdayText.moment(moment, live: live))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .strikethrough(moment.state == .withdrawn)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        var parts: [String] = []
        if let minute = moment.minute { parts.append("\(minute)′") }
        if let f = live.fixture(moment.fixtureId) {
            parts.append(MatchdayText.fixtureName(f) { appModel.club($0)?.shortName })
        }
        switch moment.state {
        case .reported: parts.append(moment.kind == .goal ? "FPL points updating" : "Football context")
        case .withdrawn: parts.append("Disallowed")
        default: break
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Squad

struct MatchdaySquad: View {
    @Environment(AppModel.self) private var appModel
    let live: LiveTeam
    @Binding var expanded: Set<Int>

    var body: some View {
        let starting = live.squad.filter { $0.position <= 11 }
        let bench = live.squad.filter { $0.position > 11 }
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            MatchdaySectionTitle(title: "Your team")
            ToolkitCard { rows(starting) }
            MatchdaySectionTitle(title: live.chip == "bboost" ? "Bench (Bench Boost)" : "Bench")
            ToolkitCard { rows(bench) }
        }
    }

    private func rows(_ players: [LiveTeam.Player]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(players) { p in
                SquadLiveRow(player: p, live: live, isExpanded: expanded.contains(p.id)) {
                    if expanded.contains(p.id) { expanded.remove(p.id) } else { expanded.insert(p.id) }
                }
                if p.id != players.last?.id { Divider().overlay(ToolkitColor.border) }
            }
        }
    }
}

private struct SquadLiveRow: View {
    @Environment(AppModel.self) private var appModel
    let player: LiveTeam.Player
    let live: LiveTeam
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        let summary = live.player(player.playerId)
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            Button(action: toggle) {
                HStack(spacing: ToolkitSpace.md) {
                    PlayerPhoto(path: summary?.photo, clubLogo: appModel.club(summary?.clubId)?.logo, size: 36)
                        .opacity(player.counted ? 1 : 0.55)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: ToolkitSpace.sm) {
                            Text(summary?.webName ?? "Player \(player.playerId)")
                                .font(.headline)
                                .foregroundStyle(player.counted ? ToolkitColor.primaryText : ToolkitColor.secondaryText)
                            if player.isCaptain { RoleBadge(letter: "C") }
                            if player.isViceCaptain { RoleBadge(letter: "V") }
                        }
                        Text(stateText)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ToolkitSpace.sm)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(player.points * max(player.multiplier, 1))")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(player.counted ? ToolkitColor.primaryText : ToolkitColor.secondaryText)
                        if player.provisionalBonus > 0 {
                            Text("+\(player.provisionalBonus * max(player.multiplier, 1)) bonus")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ToolkitColor.warning)
                        } else if player.multiplier > 1 {
                            Text("×\(player.multiplier)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .padding(.vertical, ToolkitSpace.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(summary))
            .accessibilityHint(isExpanded ? "Hides the points breakdown" : "Shows how the points add up")
            // Combining the row into one element drops the button role; put it back.
            .accessibilityAddTraits(isExpanded ? [.isButton, .isSelected] : .isButton)
            if isExpanded {
                breakdown
                    .padding(.leading, 48)
                    .padding(.bottom, ToolkitSpace.sm)
            }
        }
    }

    private var stateText: String {
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
            parts.append(fixture?.minute.map { "Playing · \($0)′" } ?? "Playing")
        case .done:
            parts.append(player.minutes > 0 ? "Finished · \(player.minutes) min" : "Didn't play")
        case .unknown: break
        }
        if !player.counted && player.position > 11 && player.autoSub == nil { parts.append("Bench") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            if player.breakdown.isEmpty {
                Text("No points yet.")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            ForEach(Array(player.breakdown.enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(MatchdayText.stat(line.stat, value: line.value))
                    Spacer()
                    Text("\(line.points > 0 ? "+" : "")\(line.points)")
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.primaryText)
            }
            if player.multiplier > 1 {
                Text("×\(player.multiplier) as captain")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            if !player.breakdown.isEmpty {
                TrustLine(kind: .fpl, text: "FPL-recorded")
                    .font(.footnote)
            }
            if let c = player.context, let text = MatchdayText.context(c) {
                TrustLine(kind: .context, text: text)
                    .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func spoken(_ summary: PlayerSummary?) -> String {
        var parts = [summary?.webName ?? "Player"]
        if player.isCaptain { parts.append("captain") }
        if player.isViceCaptain { parts.append("vice-captain") }
        parts.append(stateText)
        let points = player.points * max(player.multiplier, 1)
        parts.append("\(points) point\(points == 1 ? "" : "s")")
        if player.provisionalBonus > 0 { parts.append("plus \(player.provisionalBonus) projected bonus") }
        if !player.counted { parts.append("not counting") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - Fixtures

struct MatchdayFixtures: View {
    @Environment(AppModel.self) private var appModel
    let live: LiveTeam

    var body: some View {
        if !live.fixtures.isEmpty {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                MatchdaySectionTitle(title: "Your players' matches")
                ToolkitCard {
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        ForEach(live.fixtures.sorted { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) }) { f in
                            row(f)
                        }
                    }
                }
            }
        }
    }

    private func row(_ f: LiveTeam.Fixture) -> some View {
        HStack(spacing: ToolkitSpace.sm) {
            ClubLabel(clubId: f.homeClubId, text: appModel.club(f.homeClubId)?.shortName ?? "?", logoSize: 18)
            Spacer(minLength: 0)
            Text(centre(f))
                .font(.headline.monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
            Spacer(minLength: 0)
            ClubLabel(clubId: f.awayClubId, text: appModel.club(f.awayClubId)?.shortName ?? "?", logoSize: 18)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(ToolkitColor.primaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(f))
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

    private func centre(_ f: LiveTeam.Fixture) -> String {
        switch f.state {
        case .notStarted: return f.kickoff.map { $0.formatted(date: .omitted, time: .shortened) } ?? "TBC"
        case .inPlay: return "\(f.homeScore ?? 0)–\(f.awayScore ?? 0)  \(f.minute.map { "\($0)′" } ?? "")"
        default: return "\(f.homeScore ?? 0)–\(f.awayScore ?? 0)  FT"
        }
    }
}

// MARK: - Trust key

struct MatchdayTrustKey: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            TrustLine(kind: .fpl, text: "FPL-recorded: official, can still be corrected")
            TrustLine(kind: .estimate, text: "Toolkit estimate: projected bonus and automatic subs as they stand")
            TrustLine(kind: .context, text: "Football context: match events and stats from our data provider, never points")
            Text("Full time isn't final until FPL adds bonus.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .font(.footnote)
    }
}

struct MatchdaySectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(ToolkitColor.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Entry card (Today)

/// Today's way into Matchday: the score as it stands and the gameweek's state, one tap from the
/// full screen.
struct MatchdayCard: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int
    @State private var resource: Resource<LiveTeam>?

    var body: some View {
        Button {
            appModel.router.showingMatchday = true
        } label: {
            ToolkitCard {
                HStack(spacing: ToolkitSpace.md) {
                    Image(systemName: "sportscourt")
                        .font(.title2)
                        .foregroundStyle(ToolkitColor.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ToolkitSpace.sm)
                    if let live = resource?.loaded?.value {
                        Text("\(live.total.estimated)")
                            .font(.title.weight(.bold).monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                    }
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Matchday")
        .task(id: entryId) {
            let resource = Resource(appModel.liveRepository.team(entryId: entryId))
            self.resource = resource
            await resource.load()
        }
    }

    private var title: String {
        guard let live = resource?.loaded?.value else { return "Matchday" }
        return "GW\(live.gameweek) · \(MatchdayText.status(live.status))"
    }

    private var subtitle: String {
        guard let live = resource?.loaded?.value else { return "Your team, live, on match days" }
        switch live.status {
        case .live, .between: return "\(live.playing) playing · \(live.toPlay) to play"
        case .upcoming: return "\(live.toPlay) players to play"
        case .awaitingBonus: return "All played · waiting for FPL's bonus"
        default: return live.total.provisionalBonus > 0 ? "Includes projected bonus" : "Points, moments and your team"
        }
    }
}
