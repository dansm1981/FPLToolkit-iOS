// Fixture difficulty, one way everywhere (design pack pp.10, 20, 30): opponent, venue and the
// named model's value on a three-tone fill. Doubles stack within one gameweek, a blank says
// "No fixture", and missing data says so; none of them is shown as zero or as easy.
import SwiftUI

/// One gameweek for one player or club.
struct FixtureCellModel: Identifiable, Hashable {
    struct Game: Hashable {
        /// "LIV A".
        let label: String
        /// "3.1", or nil when there's no difficulty for it.
        let value: String?
        let tone: DifficultyTone
    }
    let gw: Int
    /// Empty for a blank gameweek.
    let games: [Game]
    let accessibilityLabel: String
    var id: Int { gw }
}

extension FixtureCellModel {
    /// From the API's per-gameweek fixtures (one entry per game; a blank has `blank`).
    init(gw: Int, fixtures: [FixtureDifficulty], club: (Int?) -> Bootstrap.Club?, model: String, subject: String) {
        let real = fixtures.filter { !$0.blank }
        let games = real.map { f -> Game in
            let name = club(f.opponentClubId)?.shortName ?? "TBC"
            let venue = f.home.map { $0 ? " H" : " A" } ?? ""
            return Game(label: name + venue,
                        value: f.xfdr.map { $0.value.formatted(.number.precision(.fractionLength(1))) },
                        tone: DifficultyTone(band: f.xfdr?.band))
        }
        let spoken: String
        if real.isEmpty {
            spoken = "\(subject), gameweek \(gw), no fixture"
        } else {
            spoken = "\(subject), gameweek \(gw), " + real.map { f in
                let name = club(f.opponentClubId)?.name ?? "opponent to be confirmed"
                let venue = f.home.map { $0 ? "at home" : "away" } ?? ""
                let value = f.xfdr.map { ", \(model) \($0.value.formatted(.number.precision(.fractionLength(1))))" } ?? ", difficulty unavailable"
                return "\(name) \(venue)\(value)"
            }.joined(separator: "; then ")
        }
        self.init(gw: gw, games: games, accessibilityLabel: spoken)
    }
}

/// A cell's content: each game's label and value on its tone.
struct FixtureCell: View {
    let model: FixtureCellModel
    var minWidth: CGFloat = 62
    /// Narrow cells: a blank shows "–" (its label still says "no fixture").
    var compact = false

    var body: some View {
        VStack(spacing: 2) {
            if model.games.isEmpty {
                Text(compact ? "–" : "No fixture")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ToolkitColor.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            } else {
                ForEach(Array(model.games.enumerated()), id: \.offset) { _, game in
                    VStack(spacing: 1) {
                        Text(game.label)
                            .font(.caption2.weight(.medium))
                        Text(game.value ?? "–")
                            .font(compact ? Font.caption.weight(.bold)
                                  : (model.games.count > 1 ? Font.caption2 : Font.footnote).weight(.bold).monospacedDigit())
                    }
                    .foregroundStyle(game.tone.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(game.tone.fill, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .frame(minWidth: minWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }
}

/// The next few gameweeks in a row, each labelled "GW6" above its cell (player detail).
struct FixtureRunStrip: View {
    let cells: [FixtureCellModel]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(cells) { cell in
                VStack(spacing: 5) {
                    Text("GW\(cell.gw)")
                        .font(.caption2)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                    FixtureCell(model: cell, minWidth: 0)
                        .frame(height: cell.games.count > 1 ? 64 : 44)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Rows of fixture runs: names pinned on the left, gameweeks scrolling sideways (Team → Fixtures,
/// the fixture ticker). Each row is one player or club.
/// Players (or clubs) down the side, gameweeks across (Team → Fixtures). Compact (Dan, 29 Sep:
/// "more GW fixtures on the one screen"): narrow two-line cells, a small photo and club badge
/// beside each name, the names pinned while the weeks scroll.
struct FixtureRunGrid: View {
    struct Row: Identifiable, Hashable {
        let id: Int
        let title: String
        /// e.g. "ARS · Defence" (the club's badge goes before it).
        let subtitle: String?
        var photo: String?
        var clubId: Int?
        let cells: [FixtureCellModel]
    }
    let heading: String
    let gameweeks: [Int]
    let rows: [Row]
    var onSelectRow: ((Row) -> Void)?

    @ScaledMetric(relativeTo: .caption2) private var cellWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .caption2) private var rowHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var nameWidth: CGFloat = 112
    private let spacing: CGFloat = 4

    private func height(_ row: Row) -> CGFloat {
        (row.cells.map(\.games.count).max() ?? 1) > 1 ? rowHeight * 1.6 : rowHeight
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Pinned names.
            VStack(alignment: .leading, spacing: spacing) {
                Text(heading)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(height: 24, alignment: .leading)
                ForEach(rows) { row in
                    Button { onSelectRow?(row) } label: {
                        HStack(spacing: 6) {
                            if row.photo != nil || row.clubId != nil {
                                PlayerPhoto(path: row.photo, size: 24, scalesWithText: false)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ToolkitColor.primaryText)
                                    .lineLimit(1)
                                if let subtitle = row.subtitle {
                                    ClubLabel(clubId: row.clubId, text: subtitle, logoSize: 10)
                                        .font(.caption2)
                                        .foregroundStyle(ToolkitColor.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(width: nameWidth, height: height(row), alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelectRow == nil)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .background(ToolkitColor.surface)
            .zIndex(1)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: spacing) {
                    HStack(spacing: spacing) {
                        ForEach(gameweeks, id: \.self) { gw in
                            Text("GW\(gw)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .frame(width: cellWidth, height: 24)
                        }
                    }
                    .accessibilityHidden(true)
                    ForEach(rows) { row in
                        HStack(spacing: spacing) {
                            ForEach(row.cells) { cell in
                                FixtureCell(model: cell, minWidth: cellWidth, compact: true)
                                    .frame(width: cellWidth, height: height(row))
                            }
                        }
                    }
                }
                .padding(.trailing, 8)
            }
        }
        .padding(.vertical, 6)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 15))
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }
}
