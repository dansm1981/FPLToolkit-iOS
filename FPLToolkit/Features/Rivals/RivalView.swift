import Charts
import SwiftUI

/// One rival against you (brief §5): the season gap and this gameweek up top, then Overview, Teams
/// (what separates you, by each player's effective multiplier) and Stats (this gameweek, the last
/// 5, the season). Every figure is the server's, from the same engine as the list and Today.
struct RivalView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let entryId: Int

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview", teams = "Teams", stats = "Stats", transfers = "GW Audit"
        var id: String { rawValue }
    }

    @State private var data: RivalComparison?
    @State private var loadError: ErrorCopy?
    @State private var tab: Tab = .overview
    @State private var renaming = false
    @State private var nickname = ""
    @State private var confirmingRemove = false

    private var store: RivalsStore { appModel.rivals }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let data {
                    content(data)
                } else if let loadError {
                    ErrorStateView(copy: loadError) { Task { await load() } }
                } else {
                    SkeletonCards(caption: "Comparing your teams…", count: 3)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await load() }
        .toolkitScreen()
        .navigationTitle(data?.rival.name ?? "Rival")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let rival = data?.rival {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await change(RivalPatch(featured: !rival.featured)) }
                        } label: {
                            Label(rival.featured ? "Stop featuring" : "Feature on Today", systemImage: rival.featured ? "star.slash" : "star")
                        }
                        Button {
                            nickname = rival.nickname ?? ""
                            renaming = true
                        } label: {
                            Label(rival.nickname == nil ? "Add a nickname" : "Change nickname", systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmingRemove = true } label: {
                            Label("Remove rival", systemImage: "person.badge.minus")
                        }
                    } label: {
                        Label("Rival options", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Nickname", isPresented: $renaming) {
            TextField("e.g. Big Andy", text: $nickname)
            Button("Save") {
                let name = nickname.trimmingCharacters(in: .whitespaces)
                Task { await change(RivalPatch(nickname: .some(name.isEmpty ? nil : name))) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only you see it. Leave it empty to use their name.")
        }
        .confirmationDialog("Remove \(data?.rival.name ?? "this rival")?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove rival", role: .destructive) {
                Task {
                    await store.remove(entryId)
                    if store.updateError == nil { dismiss() }
                }
            }
        } message: {
            Text("Their league data stays; you can add them again from the league.")
        }
        .task(id: entryId) { await load() }
    }

    @ViewBuilder
    private func content(_ d: RivalComparison) -> some View {
        let r = d.rival
        if !r.identity.isEmpty || !r.leagues.isEmpty {
            FactLine(([r.identity] + r.leagues.map { l in l.rank.map { "\(l.name) \(RivalText.ordinal($0))" } ?? l.name })
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        if let error = store.updateError { ErrorBanner(copy: error) }
        stateNotice(d)
        // Gold pills, as the rivalry design (Dan, 2 Oct).
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    FilterChipLabel(text: t.rawValue, active: tab == t, menu: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.rawValue)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        switch tab {
        case .overview: RivalOverview(data: d)
        case .teams: RivalTeams(data: d)
        case .stats: RivalStats(data: d)
        case .transfers:
            if d.audit != nil { RivalAuditTab(data: d) } else { RivalTransfersTab(data: d) }
        }
    }

    @ViewBuilder
    private func stateNotice(_ d: RivalComparison) -> some View {
        switch d.rival.state {
        case .otherSeason:
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                InlineNotice(text: "You saved \(d.rival.name) last season. Team IDs can belong to someone else in a new season, so add them again if they're in your leagues.")
                Button("Add them for \(d.season)") { Task { await change(RivalPatch()) } }
                    .buttonStyle(ToolkitSecondaryButtonStyle())
            }
        case .notInLeagues:
            InlineNotice(text: "\(d.rival.name) isn't in any of your saved leagues now, so their data has stopped updating. Add their league back to follow them again.",
                         systemImage: "info.circle")
        case .ok, .unknown:
            EmptyView()
        }
    }

    private func change(_ patch: RivalPatch) async {
        if await store.save(entryId, patch) { await load() }
    }

    private func load() async {
        loadError = nil
        do {
            data = try await store.repository.comparison(entryId)
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }
}

enum RivalViewText {
    /// The comparison's scoring state, once: recorded so far, live, or final.
    nonisolated static func state(_ status: LiveTeam.Status) -> String {
        switch status {
        case .upcoming: "Recorded"
        case .live, .between: "Live"
        case .awaitingBonus: "Bonus to come"
        case .finished: "Final"
        case .unknown: "Recorded"
        }
    }

    /// "×2 captain", "×1", "bench", "×1, auto-sub in".
    nonisolated static func role(_ side: RivalComparison.Side?) -> String {
        guard let side else { return "not in the team" }
        var text = side.multiplier == 0 ? "bench" : "×\(side.multiplier)"
        if side.multiplier >= 2 { text += side.multiplier == 3 ? " triple captain" : " captain" }
        if side.autoSub == .in { text += ", auto-sub in" }
        if side.autoSub == .out { text += ", auto-sub out" }
        return text
    }

    nonisolated static func state(_ row: RivalComparison.PlayerRow) -> String {
        switch row.state {
        case .blank: "No match"
        case .notStarted: "Yet to play"
        case .inPlay: "Playing · \(row.minutes) min"
        case .done: row.minutes > 0 ? "Finished · \(row.minutes) min" : "Didn't play"
        case .unknown: ""
        }
    }
}

// MARK: - Overview

private struct RivalOverview: View {
    let data: RivalComparison

    var body: some View {
        let name = data.rival.name
        RivalVersusHero(rival: data.rival)
        RivalStatusCard(data: data)
        if data.stats.season.gapTrend.count >= 2 {
            RivalMomentumChart(trend: data.stats.season.gapTrend, name: name)
        }
        if let explanation = data.explanation {
            RivalInsightCard(text: explanation)
        }
        // How you stack up for the next gameweek (Dan, 2 Oct).
        if let outlook = data.outlook {
            RivalOutlookCard(data: data, outlook: outlook)
        }
        // Their latest moves (Dan, 2 Oct): captain, chip, transfers, hits.
        if let moves = data.latest {
            RivalLatestMovesCard(data: data, moves: moves)
        }
        SectionHeader(title: "Across the season")
        CardGroup {
            let season = data.stats.season
            // Not repeated when it's already the insight above.
            if data.explanation != data.stats.last5.summary {
                fact("Last 5 gameweeks", data.stats.last5.summary ?? "Not enough gameweeks yet")
                RowDivider()
            }
            fact("Gameweeks you outscored \(name)", RivalStatsText.outscored(season.outscored, name: name))
            RowDivider()
            fact("Chips you could play now", data.chipsAvailable.you.isEmpty ? "None" : data.chipsAvailable.you.joined(separator: ", "))
            RowDivider()
            fact("Chips \(name) could play now", data.chipsAvailable.them.isEmpty ? "None" : data.chipsAvailable.them.joined(separator: ", "))
        }
        if let note = data.teamsNote {
            Text(note)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Teams

/// Side by side first (Dan, 2 Oct): both teams in two columns by position. Differences on a tap:
/// what only you have, what only they have, shared players at different multipliers, then the
/// ones that cancel as one quiet line (brief §5).
private struct RivalTeams: View {
    @Environment(AppModel.self) private var appModel
    let data: RivalComparison
    @State private var sideBySide = true

    var body: some View {
        if let teams = data.teams {
            let name = data.rival.name
            // "3 Shared · 7 You only · 5 Andy only" (Dan's rivalry design).
            RivalTeamTiles(summary: (
                shared: teams.rows.filter { $0.group == .shared || $0.group == .multiplier }.count,
                yours: teams.rows.filter { $0.group == .yours }.count,
                theirs: teams.rows.filter { $0.group == .theirs }.count
            ), name: name)
            HStack(spacing: 8) {
                chip("Side by side", active: sideBySide) { sideBySide = true }
                chip("Differences", active: !sideBySide) { sideBySide = false }
            }
            if sideBySide {
                RivalSideBySide(data: data, teams: teams)
            } else {
                Text(RivalTeamsText.summary(teams.summary, name: name))
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                group("Matters more to one of you", teams.rows.filter { $0.group == .multiplier }, name: name)
                group("Only you have", teams.rows.filter { $0.group == .yours }, name: name)
                group("Only \(name) has", teams.rows.filter { $0.group == .theirs }, name: name)
                let shared = teams.rows.filter { $0.group == .shared }
                if !shared.isEmpty {
                    SectionHeader(title: "Cancelling out")
                    Text(shared.map { data.player($0.playerId)?.webName ?? "Player \($0.playerId)" }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if teams.provisional {
                Text("Automatic subs and captaincy are as they stand until the matches finish.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let note = data.teamsNote {
            RivalNote(text: note)
        }
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FilterChipLabel(text: text, active: active, menu: false)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [RivalComparison.PlayerRow], name: String) -> some View {
        if !rows.isEmpty {
            SectionHeader(title: title)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    differenceRow(row, name: name)
                }
            }
            .padding(.horizontal, 14)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }

    @ViewBuilder
    private func differenceRow(_ row: RivalComparison.PlayerRow, name: String) -> some View {
        if let summary = data.player(row.playerId) {
            let detail = [row.note ?? RivalTeamsText.sides(row, name: name), RivalViewText.state(row)]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            Button { appModel.router.openPlayer(row.playerId) } label: {
                PlayerListRow(player: summary,
                              detail: Format.unbroken(detail),
                              value: "\(abs(row.effect))",
                              valueDetail: row.effect > 0 ? "for you" : row.effect < 0 ? "for \(name)" : "\(row.points) pts",
                              spokenDetail: RivalTeamsText.spoken(row, name: name, detail: detail),
                              wrapsDetail: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the player")
        }
    }
}

enum RivalTeamsText {
    /// "Only you: 30 pts · Only Andy: 41 pts · Different multipliers: 8 for you".
    nonisolated static func summary(_ s: RivalComparison.Teams.Summary, name: String) -> String {
        var parts = ["Only you: \(s.yours) pts", "Only \(name): \(s.theirs) pts"]
        if s.multiplier != 0 {
            parts.append("Different multipliers: \(abs(s.multiplier)) for \(s.multiplier > 0 ? "you" : name)")
        }
        if s.shared > 0 { parts.append("\(s.shared) cancel out") }
        return parts.joined(separator: " · ")
    }

    /// "You ×1 · Andy bench".
    nonisolated static func sides(_ row: RivalComparison.PlayerRow, name: String) -> String {
        switch row.group {
        case .yours: return row.them == nil ? "Yours" : "Yours · \(name)'s bench"
        case .theirs: return row.you == nil ? "\(name)'s" : "\(name)'s · your bench"
        default: return "You \(RivalViewText.role(row.you)) · \(name) \(RivalViewText.role(row.them))"
        }
    }

    nonisolated static func spoken(_ row: RivalComparison.PlayerRow, name: String, detail: String) -> String {
        let effect = row.effect == 0
            ? "\(row.points) FPL-recorded points, no difference"
            : "\(abs(row.effect)) point\(abs(row.effect) == 1 ? "" : "s") for \(row.effect > 0 ? "you" : name)"
        var parts = [detail, effect]
        if row.provisionalBonus > 0 { parts.append("plus \(row.provisionalBonus) estimated bonus, not included") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Stats

private struct RivalStats: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let data: RivalComparison
    @State private var period: RivalComparison.Stats.Period = .last5

    private var stats: RivalComparison.Stats {
        switch period {
        case .gw: data.stats.gw ?? data.stats.last5
        case .season: data.stats.season
        default: data.stats.last5
        }
    }

    var body: some View {
        let name = data.rival.name
        let s = stats
        FlowLayout(spacing: 8) {
            if data.stats.gw != nil { chip("This gameweek", .gw) }
            chip("Last 5", .last5)
            chip("Season", .season)
        }
        // Season totals, the leader crowned (Dan's rivalry design).
        RivalTotalsTiles(you: data.stats.season.you.points, them: data.stats.season.them.points,
                         name: name, label: "Season points")
        CardGroup {
            if s.outscored.of > 0 {
                RivalTugRow(title: "Gameweeks outscored", you: s.outscored.won, them: s.outscored.lost, name: name)
                RowDivider()
            }
            RivalTugRow(title: "Points", you: s.you.points, them: s.them.points, name: name)
            if let you = s.you.captainPoints, let them = s.them.captainPoints {
                RowDivider()
                RivalTugRow(title: "Captain points (×2 or ×3 in)", you: you, them: them, name: name)
            }
            RowDivider()
            RivalTugRow(title: "Transfers", you: s.you.transfers, them: s.them.transfers, name: name)
            RowDivider()
            RivalTugRow(title: "Points on hits", you: s.you.hits, them: s.them.hits, name: name)
            RowDivider()
            RivalTugRow(title: "Bench points (not counted)", you: s.you.bench, them: s.them.bench, name: name)
            if let you = s.you.byPosition, let them = s.them.byPosition {
                RowDivider()
                RivalTugRow(title: "Goalkeepers", you: you.gk, them: them.gk, name: name)
                RowDivider()
                RivalTugRow(title: "Defenders", you: you.def, them: them.def, name: name)
                RowDivider()
                RivalTugRow(title: "Midfielders", you: you.mid, them: them.mid, name: name)
                RowDivider()
                RivalTugRow(title: "Forwards", you: you.fwd, them: them.fwd, name: name)
            }
        }
        if let weekly = s.weekly, weekly.count >= 2 {
            RivalWeeklyChart(weekly: weekly, name: name)
        } else if s.gapTrend.count >= 2 {
            gapChart(s, name: name)
        }
        if let summary = s.summary {
            RivalInsightCard(text: summary, title: s.outscored.of > 0 ? "\(s.outscored.won) OF \(s.outscored.of) GAMEWEEKS WON" : "SO FAR",
                             systemImage: "trophy")
        }
        CardGroup {
            line("Your chips", s.you.chips.isEmpty ? "None" : s.you.chips.map { "\($0.label) GW\($0.gw)" }.joined(separator: ", "))
            RowDivider()
            line("\(name)'s chips", s.them.chips.isEmpty ? "None" : s.them.chips.map { "\($0.label) GW\($0.gw)" }.joined(separator: ", "))
        }
        if let captains = s.captains, !captains.isEmpty {
            SectionHeader(title: "Captains")
            CardGroup {
                ForEach(Array(captains.enumerated()), id: \.element.gw) { index, week in
                    if index > 0 { RowDivider() }
                    line("GW\(week.gw)", "You: \(captain(week.you)) · \(name): \(captain(week.them))")
                }
            }
        }
        Text(footnote(name: name))
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func chip(_ text: String, _ value: RivalComparison.Stats.Period) -> some View {
        Button { period = value } label: {
            FilterChipLabel(text: text, active: period == value, menu: false)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(period == value ? .isSelected : [])
    }

    private func captain(_ c: RivalComparison.Captain?) -> String {
        guard let c else { return "–" }
        return "\(data.player(c.playerId)?.webName ?? "Player \(c.playerId)") \(c.points)"
    }

    private func gapChart(_ s: RivalComparison.Stats, name: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                RuleMark(y: .value("Level", 0))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ForEach(s.gapTrend, id: \.gw) { point in
                    LineMark(x: .value("Gameweek", point.gw), y: .value("Gap", point.gap))
                        .foregroundStyle(ToolkitColor.accent)
                    PointMark(x: .value("Gameweek", point.gw), y: .value("Gap", point.gap))
                        .foregroundStyle(ToolkitColor.accent)
                }
            }
            .chartXScale(range: .plotDimension(padding: 16))
            .chartXAxis {
                AxisMarks(values: s.gapTrend.map(\.gw)) { value in
                    AxisValueLabel(anchor: .top) { Text("GW\(value.as(Int.self) ?? 0)") }
                }
            }
            .frame(height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The gap after each gameweek")
            .accessibilityValue(s.gapTrend.map { "GW\($0.gw) \(RivalStatsText.gap($0.gap, name: name))" }.joined(separator: "; "))
            Text("Above the dashed line you're ahead of \(name); below it, \(name) is ahead.")
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    /// A figure for each of you; from xxLarge the two sit under the title.
    private func factRow(_ title: String, _ you: Int, _ them: Int, name: String) -> some View {
        let layout = typeSize.stacksRows
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm))
        return layout {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: typeSize.stacksRows ? nil : .infinity, alignment: .leading)
            Text("You \(you) · \(name) \(them)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func line(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func footnote(name: String) -> String {
        var parts = ["Points are net of transfer hits, as FPL records them.",
                     "Gameweeks outscored compares each week's points; it isn't a head-to-head league record."]
        if period == .season {
            parts.append("Captains and points by position cover the last 5 gameweeks, the picks kept for every league.")
        }
        return parts.joined(separator: " ")
    }
}

enum RivalStatsText {
    /// "1 of 5 · Andy 4" ("· 1 level" when there are draws).
    nonisolated static func outscored(_ o: RivalComparison.Stats.Outscored, name: String) -> String {
        guard o.of > 0 else { return "No completed gameweeks yet" }
        var text = "\(o.won) of \(o.of) · \(name) \(o.lost)"
        if o.drawn > 0 { text += " · \(o.drawn) level" }
        return text
    }

    /// "4 ahead", "6 behind", "level".
    nonisolated static func gap(_ gap: Int, name: String) -> String {
        gap == 0 ? "level" : gap > 0 ? "you \(gap) ahead" : "\(name) \(-gap) ahead"
    }
}
