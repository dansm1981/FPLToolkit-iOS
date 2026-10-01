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

/// A short fact on a player row ("Cap 81%", "+10pp this GW"): grey, or green and red for a
/// direction, gold for "yours". Uses the tag colour pairs, so it keeps its contrast.
struct RowChip: Hashable {
    enum Tone: Hashable { case neutral, up, down, warn, accent }
    let text: String
    var tone: Tone = .neutral

    /// Green for a rise, red for a fall, grey for none.
    static func change(_ text: String, _ value: Double) -> RowChip {
        RowChip(text: text, tone: value > 0 ? .up : value < 0 ? .down : .neutral)
    }
}

struct RowChipView: View {
    let chip: RowChip

    var body: some View {
        Text(chip.text)
            .font(.caption.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
    }

    private var foreground: Color {
        switch chip.tone {
        case .neutral: ToolkitColor.secondaryText
        case .up: ToolkitColor.positive
        case .down: ToolkitColor.error
        case .warn: ToolkitColor.warning
        case .accent: ToolkitColor.accent
        }
    }

    private var fill: Color {
        switch chip.tone {
        case .neutral: ToolkitColor.raised
        case .up: ToolkitColor.positiveFill
        case .down: ToolkitColor.errorFill
        case .warn: ToolkitColor.warningFill
        case .accent: ToolkitColor.goldTag
        }
    }
}

/// The app's one player row (Dan, 29 Sep: "a standard format … well designed and compact"):
/// photo; the name, with a gold shirt when he's in your team; badge, club, position and price;
/// a few short facts as chips; the key figure on the right, with an optional chip under it (e.g.
/// Elite against all managers). Opens the player; VoiceOver reads it as one row.
struct MarketPlayerRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The headshot's text scaling (as PlayerPhoto), to line the details up under the name.
    @ScaledMetric(relativeTo: .body) private var photoUnit: CGFloat = 1
    let playerId: Int
    let player: PlayerSummary?
    /// After club and position, e.g. "£6.2m". Keep it short: longer facts go in `chips`.
    let details: [String]
    /// A line of words under the details, for facts that aren't chips.
    var extra: String?
    var chips: [RowChip] = []
    let trailing: String
    var trailingColor: Color = ToolkitColor.primaryText
    /// Under the figure on the right, e.g. "+8pp vs all".
    var trailingChip: RowChip?
    var badge: String?
    /// The whole row for VoiceOver; the visible words when nil.
    var spoken: String?

    private var yours: Bool { appModel.squadIds.contains(playerId) }

    var body: some View {
        Button {
            appModel.router.openPlayer(playerId)
        } label: {
            Group {
                if typeSize.stacksRows {
                    // The large sizes (Dan's phone, 1 Oct): the figure stays beside the name and the
                    // details take the full width under it, rather than a column a word or two wide.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 10) {
                            photo
                            nameLine
                                .layoutPriority(1)
                            Spacer(minLength: ToolkitSpace.sm)
                            figure
                                .fixedSize()
                        }
                        detailsBlock
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, (32 * min(photoUnit, 1.5)).rounded() + 10)
                    }
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        photo
                        VStack(alignment: .leading, spacing: 2) {
                            nameLine
                            detailsBlock
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: ToolkitSpace.sm)
                        figure
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken.map { yours ? $0 + ", in your team" : $0 } ?? visibleWords)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the player")
    }

    private var photo: some View {
        PlayerPhoto(path: player?.photo, clubLogo: appModel.club(player?.clubId)?.logo, size: 32)
    }

    private var nameLine: some View {
        HStack(spacing: 4) {
            Text(player?.webName ?? "Player \(playerId)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
            if yours {
                Image(systemName: "tshirt.fill")
                    .font(.caption2)
                    .foregroundStyle(ToolkitColor.accent)
                    .accessibilityHidden(true)
            }
        }
    }

    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            ClubLabel(clubId: player?.clubId, text: detailLine, logoSize: 12)
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
            if let extra {
                Text(typeSize.stacksRows ? Format.unbroken(extra) : extra)
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            if !chips.isEmpty {
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(chips, id: \.self) { RowChipView(chip: $0) }
                }
                .padding(.top, 1)
            }
            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.warning)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var figure: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(trailing)
                .font(.headline.monospacedDigit())
                .foregroundStyle(trailingColor)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            if let trailingChip { RowChipView(chip: trailingChip) }
        }
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
        ([player?.webName ?? "Player \(playerId)", yours ? "in your team" : nil, detailLine, extra]
            + chips.map(\.text) + [trailing, trailingChip?.text, badge])
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// A titled list of market rows on a card, with "Show all" once it's longer than `initial`. With
/// `playerOf`, a long list gets a filter bar: position, club and top price (Dan, 29 Sep).
struct MarketList<Row: Identifiable, Content: View>: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    let rows: [Row]
    var empty = "Nothing to show."
    var initial = 10
    /// The row's player, for the filters; nil for lists that aren't of players.
    var playerOf: ((Row) -> PlayerSummary?)?
    @ViewBuilder let row: (Row) -> Content
    @State private var expanded = false
    @State private var position: Position?
    @State private var club: Int?
    @State private var maxPrice: Double?

    /// Lists this long get the filter bar.
    static var filterFrom: Int { 15 }

    private var filtering: Bool { playerOf != nil && rows.count >= Self.filterFrom }

    private var shownRows: [Row] {
        guard filtering, let playerOf, position != nil || club != nil || maxPrice != nil else { return rows }
        return rows.filter { item in
            guard let p = playerOf(item) else { return false }
            if let position, p.position != position { return false }
            if let club, p.clubId != club { return false }
            if let maxPrice, p.price > maxPrice + 0.001 { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: title)
            if filtering { filterBar }
            VStack(alignment: .leading, spacing: 0) {
                let all = shownRows
                if all.isEmpty {
                    Text(rows.isEmpty ? empty : "No players match these filters.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .padding(.vertical, ToolkitSpace.sm)
                }
                let shown = expanded ? all : Array(all.prefix(initial))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    row(item)
                }
                if all.count > initial {
                    Divider().overlay(ToolkitColor.border)
                    // The frame goes on the label: outside it, the tappable area stays the text's height.
                    Button {
                        expanded.toggle()
                    } label: {
                        Text(expanded ? "Show fewer" : "Show all \(all.count)")
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

    private var filterBar: some View {
        let clubs = (appModel.bootstrap?.value.clubs ?? []).sorted { $0.name < $1.name }
        return FlowLayout(spacing: 8) {
            Menu {
                Picker("Position", selection: $position) {
                    Text("All positions").tag(Position?.none)
                    ForEach([Position.gk, .def, .mid, .fwd], id: \.self) { Text($0.plural).tag(Position?.some($0)) }
                }
            } label: {
                FilterChipLabel(text: position?.rawValue ?? "All positions", active: position != nil, menu: true)
            }
            .accessibilityLabel("Position: \(position?.plural ?? "all")")
            Menu {
                Picker("Club", selection: $club) {
                    Text("All clubs").tag(Int?.none)
                    ForEach(clubs) { Text($0.name).tag(Int?.some($0.id)) }
                }
            } label: {
                FilterChipLabel(text: club.flatMap { appModel.club($0)?.shortName } ?? "All clubs", active: club != nil, menu: true)
            }
            .accessibilityLabel("Club: \(club.flatMap { appModel.club($0)?.name } ?? "all clubs")")
            Menu {
                Picker("Top price", selection: $maxPrice) {
                    Text("Any price").tag(Double?.none)
                    ForEach(Array(stride(from: 4.5, through: 14.5, by: 0.5)), id: \.self) { price in
                        Text("Up to \(Format.price(price))").tag(Double?.some(price))
                    }
                }
            } label: {
                FilterChipLabel(text: maxPrice.map { "Up to \(Format.price($0))" } ?? "Any price", active: maxPrice != nil, menu: true)
            }
            .accessibilityLabel("Price: \(maxPrice.map { "up to \(Format.price($0))" } ?? "any")")
        }
        .onChange(of: position) { expanded = false }
        .onChange(of: club) { expanded = false }
        .onChange(of: maxPrice) { expanded = false }
    }
}

/// Two by two figures, or one column at accessibility sizes.
struct MarketFigures: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let items: [ResearchFigure]

    var body: some View {
        // One a row from xxLarge, so a name or figure never breaks mid-word in half the width.
        let pair = typeSize.stacksRows
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
            Label {
                Text(club.flatMap { appModel.club($0)?.name } ?? "All clubs")
            } icon: {
                if let club, appModel.club(club)?.logo != nil {
                    ClubLogo(clubId: club, size: 18)
                } else {
                    Image(systemName: "shield")
                }
            }
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
