import SwiftUI

/// S05 (attention), S06 (clear), S22 (light) and the unverified state.
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int
    @State private var model: TodayModel?
    @State private var showingSettings = false

    var body: some View {
        Group {
            switch model?.phase {
            case .loading?, nil:
                LoadingStateView(message: "Checking your squad…")
            case .failed(let copy)?:
                ErrorStateView(copy: copy) {
                    Task { await model?.retry() }
                }
            case .loaded(let loaded)?:
                ScrollView {
                    TodayContent(loaded: loaded, refreshError: model?.refreshError)
                        .padding(.horizontal, ToolkitSpace.page)
                        .padding(.bottom, ToolkitSpace.section)
                }
                .refreshable { await model?.load(bypassCache: true) }
            }
        }
        .toolkitScreen()
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(entryId: entryId)
        }
        .task {
            if model == nil {
                let model = TodayModel(entryId: entryId, repository: appModel.teamRepository)
                self.model = model
                await model.load()
            }
        }
    }
}

struct TodayContent: View {
    let loaded: Loaded<Today>
    let refreshError: ErrorCopy?

    private var today: Today { loaded.value }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            if let next = today.gameweek.next {
                DeadlineLine(next: next)
            }

            if let refreshError {
                RefreshFailedBanner(copy: refreshError, generatedAt: loaded.meta.generatedAt)
            }

            StatusCard(today: today)

            if today.status == .attention {
                ForEach(today.attentionInsights) { insight in
                    InsightCard(insight: insight, player: today.player(insight.playerId))
                }
            }

            if let freshness = loaded.meta.freshness, !freshness.isEmpty {
                WhatWeCheckedSection(sources: freshness)
                    .padding(.top, ToolkitSpace.sm)
            }

            Text(footer)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .padding(.top, ToolkitSpace.sm)
        }
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

    var body: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                switch today.status {
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

struct RefreshFailedBanner: View {
    let copy: ErrorCopy
    let generatedAt: Date

    var body: some View {
        Label {
            Text("Couldn't refresh: \(copy.title.lowercasedFirst). Showing results from \(Format.deadline(generatedAt)).")
        } icon: {
            Image(systemName: "wifi.exclamationmark")
        }
        .font(.footnote)
        .foregroundStyle(ToolkitColor.warning)
        .padding(ToolkitSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.warningFill, in: RoundedRectangle(cornerRadius: ToolkitRadius.pill))
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

#if DEBUG
#Preview("Attention") {
    NavigationStack {
        ScrollView {
            TodayContent(loaded: PreviewFixtures.load("today-3612045-attention", as: Today.self), refreshError: nil)
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Today")
    }
}

#Preview("Clear") {
    NavigationStack {
        ScrollView {
            TodayContent(loaded: PreviewFixtures.load("today-71191", as: Today.self), refreshError: nil)
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Today")
    }
}

#Preview("No published team") {
    NavigationStack {
        ScrollView {
            TodayContent(loaded: PreviewFixtures.load("today-no-published-team", as: Today.self), refreshError: .init(.offline))
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Today")
    }
}
#endif
