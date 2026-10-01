import SwiftUI

/// The odds check (Phase 3, P3-5; tasks/phase-3.md §7): what the betting market says about your
/// squad for the next gameweek. Chances only, never prices or bookmakers, and framed as help with
/// FPL decisions.
struct OddsCheckView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let team: Team
    let odds: Odds

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
                Text("Betting-market estimate for GW\(odds.gameweek)")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                if !odds.available {
                    Text("Odds for GW\(odds.gameweek) arrive 48 hours before the deadline, then refresh every 6 hours.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    section("Captain options", rows: captains, empty: "No scorer odds for your midfielders and forwards yet.")
                    section("Your defence", rows: defence, empty: "No clean-sheet odds for your defence yet.")
                    section("Your bench", rows: bench, empty: "No odds for your bench yet.")
                    footnote
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Odds check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private struct Row: Identifiable {
        let player: PlayerSummary
        let chance: OddsChance
        var id: Int { player.id }
    }

    private var squad: [(pick: Team.Pick, player: PlayerSummary)] {
        (team.snapshot?.picks ?? []).compactMap { pick in team.player(pick.playerId).map { (pick, $0) } }
    }

    private var captains: [Row] {
        squad.filter { $0.pick.role != .bench && ($0.player.position == .mid || $0.player.position == .fwd) }
            .compactMap { s in OddsChance.of(s.player, in: odds).map { Row(player: s.player, chance: $0) } }
            .sorted { $0.chance.value > $1.chance.value }
            .prefix(5).map { $0 }
    }

    private var defence: [Row] {
        squad.filter { $0.pick.role != .bench && ($0.player.position == .gk || $0.player.position == .def) }
            .compactMap { s in OddsChance.of(s.player, in: odds).map { Row(player: s.player, chance: $0) } }
            .sorted { $0.chance.value > $1.chance.value }
    }

    private var bench: [Row] {
        squad.filter { $0.pick.role == .bench }
            .compactMap { s in OddsChance.of(s.player, in: odds).map { Row(player: s.player, chance: $0) } }
    }

    private func section(_ title: String, rows: [Row], empty: String) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionHeader(title: title)
            ToolkitCard {
                if rows.isEmpty {
                    Text(empty).foregroundStyle(ToolkitColor.secondaryText)
                } else {
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        ForEach(rows) { row in
                            Group {
                                if typeSize.stacksRows {
                                    // The large sizes: the chance stays beside the name, and its
                                    // explanation takes the full width under them.
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: ToolkitSpace.md) {
                                            PlayerPhoto(path: row.player.photo, clubLogo: appModel.club(row.player.clubId)?.logo)
                                            Text(row.player.webName)
                                                .font(.headline)
                                                .foregroundStyle(ToolkitColor.primaryText)
                                            Spacer(minLength: ToolkitSpace.sm)
                                            figure(row).fixedSize()
                                        }
                                        FactLine(row.chance.text)
                                            .font(.subheadline)
                                            .foregroundStyle(ToolkitColor.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                } else {
                                    HStack(spacing: ToolkitSpace.md) {
                                        PlayerPhoto(path: row.player.photo, clubLogo: appModel.club(row.player.clubId)?.logo)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.player.webName)
                                                .font(.headline)
                                                .foregroundStyle(ToolkitColor.primaryText)
                                            Text(row.chance.text)
                                                .font(.subheadline)
                                                .foregroundStyle(ToolkitColor.secondaryText)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: ToolkitSpace.sm)
                                        figure(row)
                                    }
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(row.player.webName). \(row.chance.spoken)")
                        }
                    }
                }
            }
        }
    }

    private func figure(_ row: Row) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(OddsChance.percent(row.chance.value))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
            if let move = row.chance.movement {
                Text(move)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(move.hasPrefix("↑") ? ToolkitColor.positive : ToolkitColor.error)
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            Text("Chances from bookmakers' prices, with their margin removed where the market allows. Scorer and score-or-assist chances come from a single market and include its margin, so read them as approximate.")
            if let at = odds.fetchedAt {
                Text("Updated \(Format.deadline(at)). Refreshed every 6 hours until the deadline; arrows show the move since the previous refresh.")
            }
        }
        .font(.footnote)
        .foregroundStyle(ToolkitColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
}
