import SwiftUI

/// S05 (attention), S06 (clear), S22 (light), S23 (offline), S27 (loading) and the unverified state.
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int
    @State private var resource: Resource<Today>?
    /// The published squad (picks order, captaincy) for the squad strip.
    @State private var team: Resource<Team>?
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
                        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                            SavedDataBanner(resource: resource)
                            MatchdayCard(entryId: entryId)
                            TodayContent(
                                loaded: loaded,
                                isCurrent: resource.isCurrent,
                                isRefreshing: resource.isRefreshing,
                                squad: team?.loaded?.value,
                                onSelectPlayer: { appModel.router.openPlayer($0) },
                                onOfferAlerts: { showingAlertsPrimer = true })
                        }
                        .padding(.horizontal, ToolkitSpace.page)
                        .padding(.bottom, ToolkitSpace.section)
                    }
                    .refreshable {
                        async let squad: Void = team?.load(bypassCache: true) ?? ()
                        await resource.load(bypassCache: true)
                        await squad
                    }
                }
            }
        }
        .toolkitScreen()
        .navigationTitle("Today")
        .settingsButton(entryId: entryId)
        .sheet(isPresented: $showingAlertsPrimer) { NotificationPrimerView() }
        .task {
            if resource == nil {
                let resource = Resource(appModel.teamRepository.today(entryId: entryId))
                let team = Resource(appModel.teamRepository.team(entryId: entryId))
                self.resource = resource
                self.team = team
                async let squad: Void = team.load()
                await resource.load()
                await squad
            }
        }
    }
}

struct TodayContent: View {
    let loaded: Loaded<Today>
    /// False while showing a saved copy or after a failed refresh: never claim "good shape" then.
    var isCurrent = true
    var isRefreshing = false
    /// The published squad, for the strip; nil until loaded (the strip is simply left out).
    var squad: Team?
    var onSelectPlayer: ((Int) -> Void)?
    var onOfferAlerts: (() -> Void)?

    private var today: Today { loaded.value }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            if let next = today.gameweek.next {
                DeadlineLine(next: next)
            }

            StatusCard(today: today, isCurrent: isCurrent, isRefreshing: isRefreshing)

            if let onOfferAlerts {
                AlertsOfferCard(open: onOfferAlerts)
            }

            if today.status == .attention {
                ForEach(today.attentionInsights) { insight in
                    Button {
                        onSelectPlayer?(insight.playerId)
                    } label: {
                        InsightCard(insight: insight, player: today.player(insight.playerId), showsChevron: onSelectPlayer != nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the player")
                }
            }

            if let squad, let snapshot = squad.snapshot {
                SquadStrip(team: squad, snapshot: snapshot, onSelectPlayer: onSelectPlayer)
            }

            if !checkedSources.isEmpty {
                WhatWeCheckedSection(sources: checkedSources, savedAt: loaded.savedAt)
                    .padding(.top, ToolkitSpace.sm)
            }

            Text(footer)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .padding(.top, ToolkitSpace.sm)
        }
    }

    /// With no published squad there's no squad to have checked, whatever the label says.
    private var checkedSources: [FreshnessSource] {
        let all = loaded.meta.freshness ?? []
        return today.snapshot == nil ? all.filter { $0.source != .picks } : all
    }

    private var footer: String {
        let checked = "Checked \(Format.deadline(loaded.meta.generatedAt))."
        guard let snapshot = today.snapshot else { return checked }
        if let freeHit = snapshot.freeHitGw {
            return "Based on your GW\(snapshot.gw) squad, which your GW\(freeHit) Free Hit reverted to. \(checked)"
        }
        return "Based on your published GW\(snapshot.gw) squad. \(checked)"
    }
}

/// "GW6 deadline · Sat 10 Oct, 11:00 · in 13 days", ticking every minute.
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

struct StatusCard: View {
    let today: Today
    var isCurrent = true
    var isRefreshing = false

    var body: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                switch today.status {
                case .clear where !isCurrent:
                    // A saved "clear" is not a current all-clear (S23).
                    statusIcon(isRefreshing ? "arrow.clockwise" : "wifi.slash", ToolkitColor.warning, ToolkitColor.warningFill)
                    Text(isRefreshing ? "Checking for changes…" : "Latest checks unavailable")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("Nothing needed attention when these results were saved, but we can't confirm new injuries or price changes until we reconnect.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                case .attention:
                    Text(today.attentionCount == 1 ? "1 thing to review" : "\(today.attentionCount) things to review")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ToolkitColor.primaryText)
                    if let snapshot = today.snapshot {
                        Text("Based on your published GW\(snapshot.gw) squad")
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                case .clear:
                    statusIcon("checkmark", ToolkitColor.positive, ToolkitColor.positiveFill)
                    Text("You're in good shape")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("Nothing in your squad needs attention in the feeds we checked.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                case .unverified:
                    statusIcon("questionmark", ToolkitColor.warning, ToolkitColor.warningFill)
                    if today.noSnapshotReason == .noPublishedTeamYet || today.snapshot == nil {
                        Text("No published squad yet")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(noSnapshotMessage)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    } else {
                        Text("We couldn't check everything")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text("Some of the data we rely on is missing or out of date, so we can't say you're in good shape yet. See what we checked below.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var noSnapshotMessage: String {
        if let next = today.gameweek.next {
            return "This team hasn't been through a deadline yet. We'll check your squad once the GW\(next.id) deadline passes."
        }
        return "This team hasn't been through a deadline yet. We'll check your squad once the next deadline passes."
    }

    private func statusIcon(_ symbol: String, _ foreground: Color, _ fill: Color) -> some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(width: 48, height: 48)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Attention") {
    NavigationStack {
        ScrollView {
            TodayContent(loaded: PreviewFixtures.load("today-3612045-attention", as: Today.self))
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Today")
    }
}

#Preview("Clear") {
    NavigationStack {
        ScrollView {
            TodayContent(loaded: PreviewFixtures.load("today-71191", as: Today.self))
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Today")
    }
}

#Preview("Saved clear, offline") {
    NavigationStack {
        ScrollView {
            TodayContent(loaded: PreviewFixtures.load("today-71191", as: Today.self), isCurrent: false)
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Today")
    }
}

#Preview("No published team") {
    NavigationStack {
        ScrollView {
            TodayContent(loaded: PreviewFixtures.load("today-no-published-team", as: Today.self))
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Today")
    }
}
#endif
