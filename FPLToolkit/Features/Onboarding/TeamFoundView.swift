import SwiftUI

/// S03. Confirms the right team was found and what it's based on, before saving it.
struct TeamFoundView: View {
    @Environment(AppModel.self) private var appModel
    let found: FoundTeam

    private var team: Team { found.team }

    var body: some View {
        ScrollView {
            VStack(spacing: ToolkitSpace.xl) {
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(ToolkitColor.positive)
                    .frame(width: 96, height: 96)
                    .background(ToolkitColor.positiveFill, in: Circle())
                    .accessibilityHidden(true)
                    .padding(.top, ToolkitSpace.xl)

                VStack(spacing: ToolkitSpace.sm) {
                    Text(team.entry.name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Team ID \(String(team.entry.id))")
                        .foregroundStyle(ToolkitColor.secondaryText)
                }

                if let snapshot = team.snapshot {
                    Pill(text: "Last published · GW\(snapshot.gw)")
                    squadCard(snapshot)
                    Text(snapshotNote(snapshot))
                        .font(.callout)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Pill(text: "No published squad yet", foreground: ToolkitColor.warning, fill: ToolkitColor.warningFill)
                    ToolkitCard {
                        Text(noSnapshotMessage)
                            .foregroundStyle(ToolkitColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
        }
        .safeAreaInset(edge: .bottom) {
            Button("See what matters") {
                appModel.connect(entryId: found.entryId)
            }
            .buttonStyle(ToolkitPrimaryButtonStyle())
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.vertical, ToolkitSpace.sm)
            .background(ToolkitColor.canvas)
        }
        .toolkitScreen()
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Team found")
    }

    private func squadCard(_ snapshot: Team.Snapshot) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                Text("\(snapshot.picks.count) players loaded")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                if let captain = snapshot.picks.first(where: \.isCaptain).flatMap({ team.player($0.playerId) }) {
                    Text("Captain: \(captain.webName)")
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                if let today = found.today {
                    attentionLine(today)
                        .padding(.top, ToolkitSpace.sm)
                }
            }
        }
    }

    @ViewBuilder
    private func attentionLine(_ today: Today) -> some View {
        switch today.status {
        case .attention:
            Text(today.attentionCount == 1 ? "1 thing to review" : "\(today.attentionCount) things to review")
                .font(.title3.weight(.bold))
                .foregroundStyle(ToolkitColor.link)
        case .clear:
            Text("Nothing needs your attention right now")
                .font(.headline)
                .foregroundStyle(ToolkitColor.positive)
        case .unverified:
            EmptyView()
        }
    }

    private func snapshotNote(_ snapshot: Team.Snapshot) -> String {
        if let freeHit = snapshot.freeHitGw {
            return "You played your Free Hit in GW\(freeHit), so this is the GW\(snapshot.gw) squad it reverts to. It isn't a confirmation of your next deadline choices."
        }
        return "This is your published GW\(snapshot.gw) squad, not a confirmation of your next deadline choices."
    }

    private var noSnapshotMessage: String {
        if let next = appModel.bootstrap?.value.gameweek.next {
            return "This team hasn't been through a deadline yet, so there's no published squad to check. We'll show it once the GW\(next.id) deadline (\(Format.deadline(next.deadline))) passes."
        }
        return "This team hasn't been through a deadline yet, so there's no published squad to check. We'll show it once the next deadline passes."
    }
}

#if DEBUG
#Preview("Found") {
    NavigationStack {
        TeamFoundView(found: FoundTeam(
            entryId: 3612045,
            team: PreviewFixtures.load("team-71191", as: Team.self).value,
            today: PreviewFixtures.load("today-3612045-attention", as: Today.self).value))
    }
    .environment(AppModel())
}

#Preview("No published team") {
    NavigationStack {
        TeamFoundView(found: FoundTeam(
            entryId: 10000001,
            team: PreviewFixtures.load("team-no-published-team", as: Team.self).value,
            today: nil))
    }
    .environment(AppModel())
}
#endif
