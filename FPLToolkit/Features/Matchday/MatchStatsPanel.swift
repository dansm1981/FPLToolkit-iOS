import SwiftUI

/// One match's FPL stats under its row in Matches (Dan, 29 Sep): goals, assists, own goals,
/// penalties, cards, saves, bonus (the Toolkit's estimate until FPL adds it), the top BPS, and
/// every outfield player's DEFCON count, misses included. Your players are marked.
struct MatchStatsPanel: View {
    @Environment(AppModel.self) private var appModel
    let fixtureId: Int
    let gameweek: Int
    /// Your fifteen, marked in the lists.
    let squad: Set<Int>
    @State private var resource: Resource<MatchStats>?

    var body: some View {
        Group {
            switch resource?.phase {
            case .loading?, nil:
                ProgressView("Loading the match…")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, minHeight: 60)
            case .failed(let copy)?:
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    Text("\(copy.title). \(copy.message)")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    Button("Try again") { Task { await resource?.retry() } }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            case .loaded(let loaded)?:
                content(loaded.value)
            }
        }
        .task(id: fixtureId) {
            let resource = Resource(appModel.liveRepository.match(fixtureId: fixtureId, gw: gameweek))
            self.resource = resource
            await resource.load()
        }
    }

    @ViewBuilder private func content(_ stats: MatchStats) -> some View {
        let sections: [(String, [MatchStats.Entry])] = [
            ("Goals", stats.goals),
            ("Assists", stats.assists),
            ("Own goals", stats.ownGoals),
            ("Penalties saved", stats.penaltiesSaved),
            ("Penalties missed", stats.penaltiesMissed),
            ("Yellow cards", stats.yellowCards),
            ("Red cards", stats.redCards),
            ("Saves", stats.saves),
            (stats.bonusProvisional ? "Bonus (estimate from BPS)" : "Bonus", stats.bonus),
            ("Top BPS", stats.bps),
        ].filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: 14) {
            if sections.isEmpty && stats.defcon.isEmpty {
                Text("No stats from FPL for this match yet.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            ForEach(sections, id: \.0) { title, entries in
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: title)
                    ForEach(entries, id: \.self) { entry in
                        row(entry.playerId, stats: stats, value: "\(entry.value)",
                            spokenValue: "\(entry.value)")
                    }
                }
            }
            if !stats.defcon.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "DEFCON (count / needed)")
                    ForEach(stats.defcon, id: \.self) { entry in
                        row(entry.playerId, stats: stats, value: "\(entry.value)/\(entry.threshold)",
                            spokenValue: "\(entry.value) of \(entry.threshold)\(entry.reached ? ", 2 points" : "")",
                            reached: entry.reached)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func row(_ playerId: Int, stats: MatchStats, value: String, spokenValue: String,
                     reached: Bool = false) -> some View {
        let player = stats.player(playerId)
        let yours = squad.contains(playerId)
        return HStack(spacing: 8) {
            ClubLogo(clubId: player?.clubId, size: 14)
            Text(player?.webName ?? "Player \(playerId)")
                .font(.subheadline.weight(yours ? .bold : .regular))
                .foregroundStyle(ToolkitColor.primaryText)
            if yours {
                Image(systemName: "tshirt.fill")
                    .font(.caption2)
                    .foregroundStyle(ToolkitColor.accent)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            if reached {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.positive)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(reached ? ToolkitColor.positive : ToolkitColor.primaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([player?.webName ?? "Player", appModel.club(player?.clubId)?.name,
                             yours ? "in your team" : nil, spokenValue].compactMap { $0 }.joined(separator: ", "))
    }
}
