import SwiftUI

/// The player sheet's workload (Phase 3, P3-6): minutes in all competitions over the last 7 and
/// 14 days, and the latest cup, European and international matches.
///
/// Something is always drawn until the answer arrives (a skeleton), so `.task` has a view to run
/// on: a Group with nothing in it never runs its task. A failure hides the section.
struct WorkloadSection: View {
    @Environment(AppModel.self) private var appModel
    let playerId: Int
    @State private var resource: Resource<WorkloadPage>?

    var body: some View {
        Group {
            switch resource?.phase {
            case nil, .loading?:
                SkeletonCards(caption: "Loading minutes in all competitions…", count: 1)
            case .loaded(let loaded)?:
                section(loaded.value.workload(playerId))
            case .failed?:
                EmptyView()
            }
        }
        .task(id: playerId) {
            let resource = Resource(appModel.researchRepository.workload(playerIds: [playerId]))
            self.resource = resource
            await resource.load()
        }
    }

    private func section(_ w: Workload?) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            SectionLabel(text: "Minutes in all competitions")
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    if let w, w.lastMatch != nil {
                        Text(WorkloadText.summary(w))
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(w.otherCompetitions.prefix(3)) { m in
                            Label {
                                Text(WorkloadText.match(m))
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: m.kind == .international ? "globe.europe.africa" : "trophy")
                                    .accessibilityHidden(true)
                            }
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                        }
                    } else {
                        Text("No recent minutes in any competition.")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                    }
                    Text("Premier League minutes from FPL; cups, Europe and internationals from our data provider. Evidence of workload, not a fitness verdict.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Congestion's player view: your squad by minutes in all competitions over the last 14 days.
/// A skeleton until both answers are in (see WorkloadSection); a failure hides the card.
struct SquadMinutesCard: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int
    @State private var team: Resource<Team>?
    @State private var workload: Resource<WorkloadPage>?

    private struct Row: Identifiable {
        let player: PlayerSummary
        let workload: Workload?
        var id: Int { player.id }
    }

    var body: some View {
        Group {
            if let squad = team?.loaded?.value, let page = workload?.loaded?.value {
                let rows = (squad.snapshot?.picks ?? [])
                    .compactMap { pick in squad.player(pick.playerId).map { Row(player: $0, workload: page.workload(pick.playerId)) } }
                    .sorted { ($0.workload?.last14 ?? 0) > ($1.workload?.last14 ?? 0) }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                        MarketList(title: "Your squad's minutes", rows: rows, initial: 5) { row($0.player, $0.workload) }
                        Text("Minutes in all competitions over the last 14 days, most first. Evidence of workload, not a fitness verdict.")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if !failed {
                SkeletonCards(caption: "Loading your squad's minutes…", count: 1)
            }
        }
        .task(id: entryId) {
            let team = Resource(appModel.teamRepository.team(entryId: entryId))
            self.team = team
            await team.load()
            guard let ids = team.loaded?.value.snapshot?.picks.map(\.playerId), !ids.isEmpty else { return }
            let workload = Resource(appModel.researchRepository.workload(playerIds: ids))
            self.workload = workload
            await workload.load()
        }
    }

    /// Either answer failed, or the team has no squad to look up.
    private var failed: Bool {
        if case .failed? = team?.phase { return true }
        if case .failed? = workload?.phase { return true }
        if let squad = team?.loaded?.value, squad.snapshot?.picks.isEmpty ?? true { return true }
        return false
    }

    private func row(_ player: PlayerSummary, _ w: Workload?) -> some View {
        HStack(spacing: ToolkitSpace.md) {
            PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.webName)
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                if let last = w?.lastMatch {
                    Text("Last: \(WorkloadText.match(last))")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: ToolkitSpace.sm)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(w?.last14 ?? 0)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
                Text("min")
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .padding(.vertical, ToolkitSpace.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.webName), \(w?.last14 ?? 0) minutes in the last 14 days" + (w?.lastMatch.map { ", last match \(WorkloadText.match($0))" } ?? ""))
    }
}
