import SwiftUI

/// Matchday → Your team → Your rivals (Stage B; happy-backend-pal#68): the featured rival's live
/// contest (what changed, what matters now, what comes next), then every other rival's gap and
/// gameweek. Tapping one opens their page. Every line is the server's.
struct MatchdayRivalsSection: View {
    let live: LiveTeam
    let rivals: LiveTeam.Rivals
    let onRival: (Int) -> Void

    var body: some View {
        if !rivals.rows.isEmpty {
            SectionHeader(title: "Your rivals")
            if let featured = rivals.featured, let row = rivals.rows.first(where: { $0.entryId == featured.entryId }) {
                FeaturedContestCard(live: live, row: row, contest: featured) { onRival(row.entryId) }
            }
            let others = rivals.rows.filter { $0.entryId != rivals.featured?.entryId }
            if !others.isEmpty {
                CardGroup {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, rival in
                        if index > 0 { RowDivider() }
                        Button { onRival(rival.entryId) } label: {
                            RivalRow(rival: rival, gameweek: live.gameweek)
                                .padding(.horizontal, 15)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Compares their team with yours")
                    }
                }
            }
            if rivals.featured == nil {
                Text("Feature a rival from their page to follow your contest here as it happens.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The featured rivalry as it happens (brief §6): the gap and this gameweek, what changed, what
/// matters now and what comes next.
private struct FeaturedContestCard: View {
    @Environment(AppModel.self) private var appModel
    let live: LiveTeam
    let row: RivalSummary
    let contest: LiveTeam.Rivals.Featured
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You v \(row.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ToolkitColor.secondaryText)
                        Text(row.gapText ?? "\(row.name)'s team isn't synced yet")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(ToolkitColor.primaryText)
                        if let week = RivalText.thisWeek(row) {
                            Text(week)
                                .font(.subheadline)
                                .foregroundStyle(ToolkitColor.primaryText)
                        }
                        if let swing = row.swingText {
                            Text(swing)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                        }
                        if let bonus = RivalText.bonus(row) {
                            Text(bonus)
                                .font(.footnote)
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ToolkitSpace.sm)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens your rivalry")

            if let changed = contest.changed {
                Divider().overlay(ToolkitColor.border)
                block("What changed", systemImage: "arrow.left.arrow.right") {
                    Text(changed)
                }
            }
            if !contest.now.isEmpty {
                Divider().overlay(ToolkitColor.border)
                block("What matters now", systemImage: "scope") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(contest.now) { Text($0.text) }
                        Text("If nothing else changes.")
                            .font(.caption)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
            }
            if !contest.next.isEmpty {
                Divider().overlay(ToolkitColor.border)
                block("Still to come", systemImage: "clock") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(contest.next) { item in
                            Text(next(item))
                        }
                    }
                }
            }
        }
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func block<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            content()
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .accessibilityElement(children: .combine)
    }

    /// "Sat 17:30 · ARS v CHE · you have Saka; Andy has Palmer ×2" (the time once it's known).
    private func next(_ item: LiveTeam.Rivals.ComingUp) -> String {
        let state = live.fixture(item.fixtureId)?.state
        if state == .inPlay { return "Playing now · \(item.text)" }
        guard let kickoff = item.kickoff else { return item.text }
        return "\(Format.deadline(kickoff)) · \(item.text)"
    }
}

extension MatchdayMemory {
    /// "Your lead over Andy grew from 3 to 9", "You've gone from 3 behind Andy to 4 ahead".
    nonisolated static func rivalLine(name: String, was: Int, now: Int) -> String? {
        guard was != now else { return nil }
        func standing(_ gap: Int) -> String { gap == 0 ? "level with \(name)" : gap > 0 ? "\(gap) ahead of \(name)" : "\(-gap) behind \(name)" }
        if was > 0 && now > 0 { return "Your lead over \(name) \(now > was ? "grew" : "fell") from \(was) to \(now)" }
        if was < 0 && now < 0 { return "\(name)'s lead \(now < was ? "grew" : "fell") from \(-was) to \(-now)" }
        return "You've gone from \(standing(was)) to \(standing(now))"
    }
}
