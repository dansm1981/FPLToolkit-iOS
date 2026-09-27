import SwiftUI

/// Today's compact squad strip (product brief): the published XI then the bench, each with
/// captaincy, availability and the next opponent with xFDR. Tapping a player opens the sheet.
struct SquadStrip: View {
    let team: Team
    let snapshot: Team.Snapshot
    var onSelectPlayer: ((Int) -> Void)?

    private var picks: [Team.Pick] {
        snapshot.picks.sorted { ($0.role == .bench ? 1 : 0, $0.slot) < ($1.role == .bench ? 1 : 0, $1.slot) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            SectionLabel(text: "Your squad · next fixtures")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ToolkitSpace.sm) {
                    ForEach(picks, id: \.playerId) { pick in
                        if let player = team.player(pick.playerId) {
                            Button {
                                onSelectPlayer?(player.id)
                            } label: {
                                SquadChip(pick: pick, player: player)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the player")
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }
}

private struct SquadChip: View {
    @Environment(AppModel.self) private var appModel
    let pick: Team.Pick
    let player: PlayerSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(player.webName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .lineLimit(1)
                if pick.isCaptain { badge("C") }
                if pick.isViceCaptain { badge("V") }
            }
            if player.availability.level != .ok {
                AvailabilityBadge(availability: player.availability)
            }
            Text(opponent)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
            if let xfdr = player.nextFixture?.xfdr {
                Text("xFDR \(xfdr.value.formatted(.number.precision(.fractionLength(1))))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            if pick.role == .bench {
                Text("Bench")
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .padding(ToolkitSpace.md)
        .frame(minWidth: 104, minHeight: 44, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ToolkitColor.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func badge(_ letter: String) -> some View {
        Text(letter)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(ToolkitColor.onAccent)
            .frame(width: 18, height: 18)
            .background(ToolkitColor.accent, in: Circle())
    }

    private var opponent: String {
        guard let fixture = player.nextFixture else { return "–" }
        if fixture.blank { return "No game" }
        let name = appModel.club(fixture.opponentClubId)?.shortName ?? "TBC"
        return fixture.home.map { "\(name) (\($0 ? "H" : "A"))" } ?? name
    }

    private var accessibilityText: String {
        var parts = [player.webName]
        if pick.isCaptain { parts.append("captain") }
        if pick.isViceCaptain { parts.append("vice-captain") }
        if pick.role == .bench { parts.append("on the bench") }
        if player.availability.level != .ok {
            parts.append(player.availability.chanceNext.map { "\($0) percent chance of playing" } ?? "flagged")
        }
        if let fixture = player.nextFixture, !fixture.blank {
            let name = appModel.club(fixture.opponentClubId)?.name ?? "opponent to be confirmed"
            let venue = fixture.home.map { $0 ? "at home" : "away" } ?? ""
            parts.append("next: \(name) \(venue)")
            if let xfdr = fixture.xfdr {
                parts.append("difficulty \(xfdr.value.formatted(.number.precision(.fractionLength(1)))) out of 5")
            }
        } else if player.nextFixture?.blank == true {
            parts.append("no fixture next gameweek")
        }
        return parts.joined(separator: ", ")
    }
}
