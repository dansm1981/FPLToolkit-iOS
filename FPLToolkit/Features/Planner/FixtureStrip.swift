import SwiftUI

/// The pitch card's six-week strip, as on the website: one cell per gameweek, coloured by its
/// hardest fixture (the server's band), with the band written in it so colour is never the only
/// signal. A double gameweek is outlined; a blank shows a dash. VoiceOver reads it from the tile.
struct FixtureStrip: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var cell: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2) private var digit: CGFloat = 8
    let weeks: [PlannerDraft.StripWeek]
    /// Bigger cells in one row: the full-width list shown at accessibility sizes.
    var roomy = false

    var body: some View {
        // Two rows of three once six cells would be wider than the card.
        let perRow = !roomy && typeSize >= .xxLarge ? 3 : 6
        let rows = stride(from: 0, to: weeks.count, by: perRow).map {
            Array(weeks[$0 ..< min($0 + perRow, weeks.count)])
        }
        VStack(spacing: 1.5) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 1.5) {
                    ForEach(rows[row], id: \.gw) { week in
                        cellView(week)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func cellView(_ week: PlannerDraft.StripWeek) -> some View {
        let side = roomy ? cell * 1.8 : cell
        // The roomy strip (list rows) uses a text style, so the audit sees it follow Dynamic Type;
        // the pitch tiles' tiny cells keep a scaled point size.
        return Text(week.band.map(String.init) ?? "–")
            .font(roomy ? .footnote.weight(.bold).monospacedDigit() : .system(size: digit, weight: .bold).monospacedDigit())
            .foregroundStyle(week.band.map(DifficultyColor.text) ?? ToolkitColor.secondaryText)
            .frame(width: side, height: side * 1.2)
            .background(week.band.map(DifficultyColor.fill) ?? ToolkitColor.raised,
                        in: RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2)
                .strokeBorder(ToolkitColor.primaryText, lineWidth: week.isDouble ? 1 : 0))
    }

    /// What VoiceOver says for the strip, e.g. "Next 6 gameweeks, difficulty out of 5: GW7 3,
    /// GW8 5, two games, GW9 no game".
    nonisolated static func spoken(_ weeks: [PlannerDraft.StripWeek]) -> String? {
        guard !weeks.isEmpty else { return nil }
        let parts = weeks.map { week -> String in
            guard let band = week.band else { return "GW\(week.gw) no game" }
            return "GW\(week.gw) \(band)\(week.isDouble ? ", two games" : "")"
        }
        return "Next \(weeks.count) gameweeks, difficulty out of 5: " + parts.joined(separator: ", ")
    }
}
