import SwiftUI

/// One mini-league, as on the website: the Overview (what matters to you, threats, opportunities,
/// closest rivals) and the Standings, compared with your FPL team or a planner draft. Tap a
/// manager for "vs me".
struct LeagueView: View {
    @Environment(AppModel.self) private var appModel
    let league: LeagueList.League

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview", standings = "Standings", rivals = "Rivals", players = "Players"
        case captains = "Captains", chips = "Chips", transfers = "Transfers", history = "History", report = "Report"
        var id: String { rawValue }
        /// Tabs whose numbers depend on whose squad the league is compared with.
        var usesBaseline: Bool { self == .overview || self == .rivals || self == .players }
    }

    @State private var tab: Tab = .overview
    @State private var baseline: LeagueBaseline = .team
    @State private var drafts: [PlannerDraftSummary] = []
    @State private var overview: LeagueOverview?
    @State private var standings: LeagueStandings?
    @State private var rivals: LeagueRivals?
    @State private var players: LeaguePlayers?
    @State private var captains: LeagueCaptains?
    @State private var chips: LeagueChips?
    @State private var transfers: LeagueTransfers?
    @State private var history: LeagueHistory?
    @State private var report: LeagueReport?
    @State private var transfersRecent = false
    @State private var reportGw: Int?
    @State private var loadError: ErrorCopy?
    @State private var vs: VsTarget?

    struct VsTarget: Identifiable, Hashable {
        let entryId: Int
        var id: Int { entryId }
    }

    private var repository: LeaguesRepository { appModel.leagues.repository }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                tabBar
                if let loadError {
                    ErrorStateView(copy: loadError) { Task { await load(force: true) } }
                } else {
                    content
                }
                footnote
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle(league.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Compare with", selection: $baseline) {
                        Text("My FPL team").tag(LeagueBaseline.team)
                        ForEach(drafts) { draft in
                            Text(draft.name).tag(LeagueBaseline.draft(id: draft.id, name: draft.name))
                        }
                    }
                } label: {
                    Label("Compare with: \(baseline.label)", systemImage: "person.2")
                }
            }
        }
        .task(id: TaskKey(tab: tab, baseline: baseline, recent: transfersRecent, reportGw: reportGw)) { await load() }
        .task { drafts = (try? await appModel.plannerRepository.list.fetch().value.drafts) ?? [] }
        .onChange(of: baseline) {
            overview = nil
            rivals = nil
            players = nil
        }
        .onChange(of: transfersRecent) { transfers = nil }
        .onChange(of: reportGw) { report = nil }
        .refreshable { await load(force: true) }
        .sheet(item: $vs) { target in
            NavigationStack {
                LeagueVsView(leagueId: league.id, entryId: target.entryId, baseline: baseline)
            }
        }
    }

    private struct TaskKey: Hashable {
        let tab: Tab
        let baseline: LeagueBaseline
        let recent: Bool
        let reportGw: Int?
    }

    /// The website's tab row, scrolling sideways.
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ToolkitSpace.sm) {
                ForEach(Tab.allCases) { t in
                    Button { tab = t } label: {
                        Text(t.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(t == tab ? ToolkitColor.onAccent : ToolkitColor.primaryText)
                            .padding(.horizontal, ToolkitSpace.md)
                            .frame(minHeight: 44)
                            .background(t == tab ? ToolkitColor.accent : ToolkitColor.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(t == tab ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let open: (Int) -> Void = { vs = VsTarget(entryId: $0) }
        switch tab {
        case .overview:
            if let overview { OverviewSection(overview: overview, onManager: open) } else { loading }
        case .standings:
            if let standings { StandingsSection(standings: standings, onManager: open) } else { loading }
        case .rivals:
            if let rivals { LeagueRivalsSection(data: rivals, onManager: open) } else { loading }
        case .players:
            if let players { LeaguePlayersSection(data: players) } else { loading }
        case .captains:
            if let captains { LeagueCaptainsSection(data: captains, onManager: open) } else { loading }
        case .chips:
            if let chips { LeagueChipsSection(data: chips, onManager: open) } else { loading }
        case .transfers:
            if let transfers { LeagueTransfersSection(data: transfers, recent: $transfersRecent, onManager: open) } else { loading }
        case .history:
            if let history { LeagueHistorySection(data: history, onManager: open) } else { loading }
        case .report:
            if let report { LeagueReportSection(data: report, gw: $reportGw) } else { loading }
        }
    }

    private var loading: some View { SkeletonCards(caption: "Reading the league…", count: 3) }

    private var footnote: some View {
        var parts: [String] = []
        if league.isElite {
            parts.append("Elite 100 is a fixed, anonymous group of 100 historically strong managers, shown as Elite Manager #1–#100.")
        } else if let managers = league.managers, managers > league.tracked {
            parts.append("This league has \(managers) managers; the top \(league.tracked) are tracked.")
        }
        parts.append("Updated after each deadline.")
        if tab.usesBaseline { parts.append("Compared with: \(baseline.label).") }
        if tab == .players { parts.append("Threat and opportunity scores (0–100) come from current league data only; no future points are projected.") }
        return Text(parts.joined(separator: " "))
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func load(force: Bool = false) async {
        loadError = nil
        let id = league.id
        do {
            switch tab {
            case .overview:
                if force || overview == nil { overview = try await repository.overview(id, baseline: baseline) }
            case .standings:
                if force || standings == nil { standings = try await repository.standings(id) }
            case .rivals:
                if force || rivals == nil { rivals = try await repository.rivals(id, baseline: baseline) }
            case .players:
                if force || players == nil { players = try await repository.players(id, baseline: baseline) }
            case .captains:
                if force || captains == nil { captains = try await repository.captains(id) }
            case .chips:
                if force || chips == nil { chips = try await repository.chips(id) }
            case .transfers:
                if force || transfers == nil { transfers = try await repository.transfers(id, recent: transfersRecent) }
            case .history:
                if force || history == nil { history = try await repository.history(id) }
            case .report:
                if force || report == nil { report = try await repository.report(id, gw: reportGw) }
            }
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }
}

// MARK: - Overview

private struct OverviewSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let overview: LeagueOverview
    let onManager: (Int) -> Void

    /// Two figures a row, stacked at accessibility text sizes so no heading is cut off.
    private var row: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: ToolkitSpace.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: ToolkitSpace.sm))
    }

    var body: some View {
        let h = overview.headline
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "What matters to you")
                if overview.me == nil && overview.baseline == "team" {
                    Text("Connect your FPL team to personalise this section.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                VStack(spacing: ToolkitSpace.sm) {
                    row {
                        tile("Your position",
                             value: h.position.rank.map { "\($0)/\(h.position.of)" } ?? "—/\(h.position.of)",
                             note: h.position.behindFirst.map { $0 == 0 ? "Top of the league" : "\($0) pts behind 1st" } ?? "—")
                        tile("Team similarity",
                             value: h.similarityPct.map { "\($0)%" } ?? "—",
                             note: "similar to league template")
                    }
                    row {
                        tile("Biggest threat",
                             value: h.biggestThreat.map { name($0.playerId) } ?? "—",
                             note: h.biggestThreat.map { "\(Int($0.eo.rounded()))% league EO" } ?? "—")
                        tile("Best differential",
                             value: h.bestDifferential.map { name($0.playerId) } ?? "—",
                             note: h.bestDifferential.map { "\(Int($0.leagueOwnPct.rounded()))% league ownership" } ?? "—")
                    }
                    row {
                        tile("Chip activity",
                             value: "\(h.chips.total)",
                             note: h.chips.top.prefix(2).map { "\($0.count)× \($0.label)" }.joined(separator: " · ").nonEmpty ?? "None used")
                        tile("League leader",
                             value: h.leader?.displayName ?? "—",
                             note: h.leader?.total.map { "\($0) pts" } ?? "—")
                    }
                }
            }

            intelList("Biggest threats", overview.threats, empty: "Nothing to show yet.")
            intelList("Biggest opportunities", overview.opportunities, empty: "Connect your team or build a draft.")

            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Closest rivals")
                if overview.rivals.isEmpty {
                    Text("Connect your FPL team to find your rivals.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                ForEach(overview.rivals.prefix(3)) { rival in
                    RivalCard(rival: rival, name: name) { onManager(rival.entryId) }
                }
            }
        }
    }

    private func name(_ id: Int) -> String { overview.player(id)?.webName ?? "Player \(id)" }

    private func tile(_ title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(ToolkitColor.primaryText)
            Text(note)
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ToolkitSpace.md)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.button))
        .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.button).strokeBorder(ToolkitColor.border))
        .accessibilityElement(children: .combine)
    }

    private func intelList(_ title: String, _ rows: [LeagueIntel], empty: String) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: title)
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    if rows.isEmpty {
                        Text(empty).font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
                    }
                    ForEach(rows.prefix(5)) { row in
                        Button { appModel.router.openPlayer(row.playerId) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name(row.playerId))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ToolkitColor.primaryText)
                                    Text("\(row.band) · league EO \(Int(row.eo.rounded()))% · owned \(Int(row.leagueOwnPct.rounded()))% here, \(Int(row.globalPct.rounded()))% overall")
                                        .font(.footnote)
                                        .foregroundStyle(ToolkitColor.secondaryText)
                                }
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: ToolkitSpace.sm)
                                Text("\(row.score)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(ToolkitColor.primaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Opens the player")
                    }
                }
            }
        }
    }
}

/// One rival: who, the gap, why they're a rival, and how your squads differ (the website's card).
private struct RivalCard: View {
    let rival: LeagueRival
    let name: (Int) -> String
    let compare: () -> Void

    var body: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rival.displayName).font(.headline).foregroundStyle(ToolkitColor.primaryText)
                        if let team = rival.teamName, rival.managerName != nil {
                            Text(team).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
                        }
                    }
                    Spacer(minLength: ToolkitSpace.sm)
                    Text(gapText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                }
                Text((rival.reasons + ["\(rival.shared)/15 shared"]).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                HStack(alignment: .top, spacing: ToolkitSpace.md) {
                    differences("Your differences", rival.yourDifferences, colour: ToolkitColor.positive)
                    differences("Their differences", rival.theirDifferences, colour: ToolkitColor.error)
                }
                // The frame goes on the label: outside it, the tappable area stays the text's height.
                Button(action: compare) {
                    Text("Compare")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gapText: String {
        rival.pointsDiff == 0 ? "Level on points" : rival.pointsDiff > 0 ? "\(rival.pointsDiff) pts ahead" : "\(-rival.pointsDiff) pts behind"
    }

    private func differences(_ title: String, _ ids: [Int], colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(colour)
            ForEach(ids.prefix(5), id: \.self) { Text(name($0)).font(.subheadline).foregroundStyle(ToolkitColor.primaryText) }
            if ids.isEmpty { Text("None").font(.subheadline).foregroundStyle(ToolkitColor.secondaryText) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Standings

private struct StandingsSection: View {
    let standings: LeagueStandings
    let onManager: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Standings")
            ToolkitCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(standings.rows.enumerated()), id: \.element.id) { index, row in
                        Button { onManager(row.entryId) } label: { rowView(row) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Compares their team with yours")
                        if index < standings.rows.count - 1 { Divider().overlay(ToolkitColor.border) }
                    }
                }
            }
        }
    }

    private func rowView(_ row: LeagueStandings.Row) -> some View {
        HStack(alignment: .top, spacing: ToolkitSpace.md) {
            VStack(spacing: 2) {
                Text(row.rank.map(String.init) ?? "–").font(.headline.monospacedDigit())
                Image(systemName: movementSymbol(row)).font(.caption).foregroundStyle(movementColour(row))
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 28)
            .foregroundStyle(ToolkitColor.primaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.teamName ?? "Team \(row.entryId)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(row.isMe ? ToolkitColor.accent : ToolkitColor.primaryText)
                Text(row.managerName ?? "")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                Text(details(row))
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ToolkitSpace.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.total.map(String.init) ?? "–").font(.headline.monospacedDigit())
                Text("GW \(row.gwPoints.map(String.init) ?? "–")").font(.footnote.monospacedDigit())
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .foregroundStyle(ToolkitColor.primaryText)
        }
        .padding(.vertical, ToolkitSpace.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func details(_ row: LeagueStandings.Row) -> String {
        var parts: [String] = []
        if let c = row.captainId, let name = standings.player(c)?.webName { parts.append("C \(name)") }
        if row.hits > 0 { parts.append("hits −\(row.hits)") }
        parts.append("bench \(row.benchPoints)")
        if let v = row.value { parts.append(Format.price(v)) }
        if !row.chips.isEmpty { parts.append(row.chips.map { "\($0.label)\($0.gw)" }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    private func movementSymbol(_ row: LeagueStandings.Row) -> String {
        guard let rank = row.rank, let last = row.lastRank, last != rank else { return "minus" }
        return last > rank ? "arrow.up" : "arrow.down"
    }

    private func movementColour(_ row: LeagueStandings.Row) -> Color {
        guard let rank = row.rank, let last = row.lastRank, last != rank else { return ToolkitColor.secondaryText }
        return last > rank ? ToolkitColor.positive : ToolkitColor.error
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
