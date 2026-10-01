import SwiftUI

/// The live feed's filters (Dan, 30 Sep 2026). The server says which group each item is in;
/// kick-off, half-time, full-time, cards and 60 minutes show under All only.
enum MatchdayFeedFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case goals = "Goals"
    case defence = "DEFCON & saves"
    case bonus = "Bonus"
    case lineups = "Line-ups & subs"

    var id: String { rawValue }

    func includes(_ item: LiveTeam.FeedItem) -> Bool {
        switch self {
        case .all: true
        case .goals: item.group == .goals
        case .defence: item.group == .defence
        case .bonus: item.group == .bonus
        case .lineups: item.group == .lineups
        }
    }
}

/// Matchday → Live feed (happy-backend-pal#61): everything that happened to your 15 players,
/// newest first: line-ups, goals, cards, subs, every DEFCON step and save, bonus positions.
/// The server writes each line and its points; this lays them out.
struct MatchdayFeed: View {
    let live: LiveTeam
    let feed: [LiveTeam.FeedItem]
    /// Items already seen when this visit began; later ones are marked new.
    let seen: Set<String>?
    @State private var filter: MatchdayFeedFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            FlowLayout(spacing: 8) {
                ForEach(MatchdayFeedFilter.allCases) { f in
                    Button { filter = f } label: {
                        FilterChipLabel(text: f.rawValue, active: filter == f, menu: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(f.rawValue)")
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
            let shown = feed.filter(filter.includes)
            if shown.isEmpty {
                Text(emptyText)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            } else {
                let days = Self.spansDays(shown)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        if days, index == 0 || !Self.sameDay(shown[index - 1].at, item.at) {
                            Text(Self.day.string(from: item.at))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .padding(.top, index == 0 ? 12 : 16)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                        } else if index > 0 {
                            Divider().overlay(ToolkitColor.border)
                        }
                        MatchdayFeedRow(item: item, live: live, isNew: seen.map { !$0.contains(item.id) } ?? false)
                    }
                }
                .padding(.horizontal, 15)
                .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            }
        }
    }

    private var emptyText: String {
        if filter != .all { return "Nothing under \(filter.rawValue) yet." }
        return live.status == .upcoming
            ? "Nothing yet: line-ups arrive about an hour before kick-off, then everything that happens to your players shows here."
            : "Nothing for your players yet."
    }

    /// Match days are UK days.
    private static let london = TimeZone(identifier: "Europe/London") ?? .current

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = london
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private static func sameDay(_ a: Date, _ b: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar.isDate(a, inSameDayAs: b)
    }

    private static func spansDays(_ items: [LiveTeam.FeedItem]) -> Bool {
        guard let first = items.first, let last = items.last else { return false }
        return !sameDay(first.at, last.at)
    }
}

struct MatchdayFeedRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: LiveTeam.FeedItem
    let live: LiveTeam
    let isNew: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(MatchdayText.feedTime(item))
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
                .frame(minWidth: 34, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let club = clubId {
                        ClubLogo(clubId: club, size: 16)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                    }
                    Text(item.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .strikethrough(item.state == .withdrawn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isNew || item.detail != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if isNew {
                            Tag(text: "New", foreground: ToolkitColor.onAccent, fill: ToolkitColor.accent)
                        }
                        if let detail = item.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if typeSize.isAccessibilitySize, let points = item.points, points != 0 {
                    pointsTag(points)
                }
            }
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize {
                if let points = item.points, points != 0 {
                    pointsTag(points)
                } else {
                    IconBadge(systemImage: MatchdayText.symbol(item))
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MatchdayText.spoken(item, isNew: isNew))
    }

    /// The player's club badge, so a scan down the feed finds a club's items.
    private var clubId: Int? {
        if let id = item.playerId ?? item.players?.first { return live.player(id)?.clubId }
        return nil
    }

    private func pointsTag(_ points: Int) -> some View {
        Tag(text: MatchdayText.signedPoints(points),
            foreground: points > 0 ? ToolkitColor.positive : ToolkitColor.error,
            fill: points > 0 ? ToolkitColor.positiveFill : ToolkitColor.errorFill)
            .monospacedDigit()
    }
}
