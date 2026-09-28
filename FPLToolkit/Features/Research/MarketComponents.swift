import SwiftUI

/// Words and numbers for the Market screens, written the way the website writes them.
enum MarketFormat {
    /// "+£0.1m", "−£0.2m", "£0.0m".
    nonisolated static func moneyChange(_ value: Double) -> String {
        let size = abs(value).formatted(.number.precision(.fractionLength(1)))
        return value > 0 ? "+£\(size)m" : value < 0 ? "−£\(size)m" : "£\(size)m"
    }

    /// "11.3%".
    nonisolated static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    /// "+0.2pp", "−1.4pp", "0.0pp" (percentage points of ownership).
    nonisolated static func points(_ value: Double, digits: Int = 1) -> String {
        let size = abs(value).formatted(.number.precision(.fractionLength(digits)))
        return value > 0 ? "+\(size)pp" : value < 0 ? "−\(size)pp" : "\(size)pp"
    }

    /// "755,117" or "+346,605" / "−8,860" when signed.
    nonisolated static func count(_ value: Int, signed: Bool = false) -> String {
        let size = abs(value).formatted(.number.grouping(.automatic))
        guard signed else { return value < 0 ? "−\(size)" : size }
        return value > 0 ? "+\(size)" : value < 0 ? "−\(size)" : size
    }

    /// For VoiceOver: "up £0.1m", "down 1.4 points".
    nonisolated static func spokenMoney(_ value: Double) -> String {
        let size = abs(value).formatted(.number.precision(.fractionLength(1)))
        return value > 0 ? "up £\(size)m" : value < 0 ? "down £\(size)m" : "no change"
    }

    nonisolated static func spokenPoints(_ value: Double, digits: Int = 1) -> String {
        let size = abs(value).formatted(.number.precision(.fractionLength(digits)))
        return value > 0 ? "up \(size) points" : value < 0 ? "down \(size) points" : "no change"
    }

    /// "Sat 19 Sep" for a YYYY-MM-DD day.
    nonisolated static func day(_ string: String) -> String {
        guard let date = CongestionView.date(string) else { return string }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func tint(_ value: Double) -> Color {
        value > 0 ? ToolkitColor.positive : value < 0 ? ToolkitColor.error : ToolkitColor.secondaryText
    }
}

/// A player in a market list: name, then club, position and figures, with one figure picked out on
/// the right. Opens the player. VoiceOver reads it as one row.
struct MarketPlayerRow: View {
    @Environment(AppModel.self) private var appModel
    let playerId: Int
    let player: PlayerSummary?
    /// Shown after club and position, e.g. "£6.2m", "11.3% owned".
    let details: [String]
    var extra: String?
    let trailing: String
    var trailingColor: Color = ToolkitColor.primaryText
    var badge: String?
    /// The whole row for VoiceOver; the visible words when nil.
    var spoken: String?

    var body: some View {
        Button {
            appModel.router.openPlayer(playerId)
        } label: {
            HStack(alignment: .center, spacing: ToolkitSpace.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player?.webName ?? "Player \(playerId)")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(detailLine)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    if let extra {
                        Text(extra)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ToolkitColor.warning)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                Spacer(minLength: ToolkitSpace.sm)
                Text(trailing)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(trailingColor)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, ToolkitSpace.xs)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken ?? visibleWords)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the player")
    }

    private var detailLine: String {
        var parts: [String] = []
        if let player {
            if let club = appModel.club(player.clubId)?.shortName { parts.append(club) }
            parts.append(player.position.rawValue)
        }
        return (parts + details).joined(separator: " · ")
    }

    private var visibleWords: String {
        [player?.webName ?? "Player \(playerId)", detailLine, extra, trailing, badge].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A titled list of market rows on a card, with "Show all" once it's longer than `initial`.
struct MarketList<Row: Identifiable, Content: View>: View {
    let title: String
    let rows: [Row]
    var empty = "Nothing to show."
    var initial = 10
    @ViewBuilder let row: (Row) -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: title)
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text(empty)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .padding(.vertical, ToolkitSpace.sm)
                }
                let shown = expanded ? rows : Array(rows.prefix(initial))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    row(item)
                }
                if rows.count > initial {
                    Divider().overlay(ToolkitColor.border)
                    // The frame goes on the label: outside it, the tappable area stays the text's height.
                    Button {
                        expanded.toggle()
                    } label: {
                        Text(expanded ? "Show fewer" : "Show all \(rows.count)")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                }
            }
            .padding(.horizontal, ToolkitSpace.lg)
            .padding(.vertical, ToolkitSpace.xs)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.border, lineWidth: 1))
        }
    }
}

/// Two by two figures, or one column at accessibility sizes.
struct MarketFigures: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let items: [ResearchFigure]

    var body: some View {
        let pair = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: ToolkitSpace.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: ToolkitSpace.sm))
        VStack(spacing: ToolkitSpace.sm) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                pair {
                    items[start]
                    if start + 1 < items.count { items[start + 1] }
                }
            }
        }
    }
}

/// A club filter: all clubs, or one, by name.
struct ClubMenu: View {
    @Environment(AppModel.self) private var appModel
    @Binding var club: Int?

    var body: some View {
        let clubs = (appModel.bootstrap?.value.clubs ?? []).sorted { $0.name < $1.name }
        Menu {
            Picker("Club", selection: $club) {
                Text("All clubs").tag(Int?.none)
                ForEach(clubs) { Text($0.name).tag(Int?.some($0.id)) }
            }
        } label: {
            Label(club.flatMap { appModel.club($0)?.name } ?? "All clubs", systemImage: "shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Club: \(club.flatMap { appModel.club($0)?.name } ?? "all clubs")")
    }
}

/// All positions, or one.
struct PositionPicker: View {
    @Binding var position: Position?

    var body: some View {
        Picker("Position", selection: $position) {
            Text("All").tag(Position?.none)
            ForEach([Position.gk, .def, .mid, .fwd], id: \.self) { Text($0.rawValue).tag(Position?.some($0)) }
        }
        .pickerStyle(.segmented)
    }
}
