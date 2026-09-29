import SwiftUI

/// The website's congestion page: every club's games in all competitions day by day, from three
/// days ago, with the rest between them coloured by how tight it is. At accessibility sizes it
/// reads club by club.
struct CongestionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize

    @AppStorage("research.congestion.days") private var days = 28
    @State private var restFirst = false
    @State private var table = ResearchTable<ResearchCongestion>()

    static let windows = [14, 21, 28, 42]

    private struct Options: Hashable {
        let days: Int
        let restFirst: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                if let entryId = appModel.entryId {
                    SquadMinutesCard(entryId: entryId)
                }
                controls
                ResearchTableView(table: table, caption: "Loading every club's games…", retry: reload) { congestion in
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        legend
                        if typeSize.isAccessibilitySize {
                            clubList(congestion)
                        } else {
                            grid(congestion)
                        }
                        notes(congestion)
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Congestion")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Options(days: days, restFirst: restFirst)) { await load() }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.researchRepository.congestion(days: days, shortestRestFirst: restFirst))
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            Picker("Window", selection: $days) {
                ForEach(Self.windows, id: \.self) { Text("\($0) days").tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Sort", selection: $restFirst) {
                Text("Most matches").tag(false)
                Text("Shortest rest").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    /// The website's recovery key: 1, 2, 3, 4, 5–6, 7–8, 9+ days.
    private var legend: some View {
        let steps: [(String, Int)] = [("1", 7), ("2", 6), ("3", 5), ("4", 4), ("5–6", 3), ("7–8", 2), ("9+", 1)]
        return VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
            Text("Days between games")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
            HStack(spacing: 2) {
                ForEach(steps, id: \.0) { label, level in
                    Text(label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(RestColor.text(level))
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(RestColor.fill(level))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colours show the days between games, from red for 1 day to blue for 9 or more.")
    }

    // MARK: Grid

    @ScaledMetric(relativeTo: .caption) private var clubWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .caption) private var dayWidth: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 50

    private func grid(_ congestion: ResearchCongestion) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Club")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(width: clubWidth, height: headerHeight, alignment: .bottomLeading)
                    .accessibilityHidden(true)
                ForEach(congestion.clubs) { club in
                    clubCell(club)
                        .frame(width: clubWidth, height: rowHeight, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spoken(club, congestion))
                }
            }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(0..<congestion.days, id: \.self) { day in
                            header(day, congestion)
                                .frame(width: dayWidth, height: headerHeight)
                        }
                    }
                    ForEach(congestion.clubs) { club in
                        HStack(spacing: 2) {
                            ForEach(club.days, id: \.day) { day in
                                dayCell(day, today: day.day == congestion.todayIndex)
                                    .frame(width: dayWidth, height: rowHeight)
                            }
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func header(_ day: Int, _ congestion: ResearchCongestion) -> some View {
        let date = Self.date(congestion.dates[safe: day])
        let gw = congestion.gameweeks.first { $0.day == day }?.gw
        let isToday = day == congestion.todayIndex
        return VStack(spacing: 0) {
            Text(gw.map { "GW\($0)" } ?? " ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(ToolkitColor.link)
            Text(date?.formatted(.dateTime.weekday(.abbreviated)).uppercased() ?? "")
                .font(.caption2)
            Text(date?.formatted(.dateTime.day()) ?? "")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(isToday ? ToolkitColor.onAccent : ToolkitColor.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isToday ? ToolkitColor.accent : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private func clubCell(_ club: ResearchCongestion.Club) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                ClubLogo(clubId: club.clubId, size: 14)
                Text(appModel.club(club.clubId)?.shortName ?? "?")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
            }
            Text(summary(club))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// "4 · 3d · 13d", as the website: games in the window, shortest rest, days to the next game.
    private func summary(_ club: ResearchCongestion.Club) -> String {
        var parts = ["\(club.count)", club.shortest.map { "\($0)d" } ?? "–"]
        if let next = club.daysToNext { parts.append("\(next)d") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func dayCell(_ day: ResearchCongestion.Day, today: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        Group {
            if day.matches.isEmpty {
                Text(day.gap.map(String.init) ?? "")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(RestColor.text(day.level))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RestColor.fill(day.level), in: shape)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(day.matches.enumerated()), id: \.offset) { _, match in
                        matchLabel(match)
                    }
                }
            }
        }
        .overlay(shape.strokeBorder(ToolkitColor.accent, lineWidth: today ? 2 : 0))
    }

    /// As on the website: league games show the opponent, cup games the competition and opponent;
    /// upper case at home, lower case away.
    private func matchLabel(_ match: ResearchCongestion.Match) -> some View {
        let cased: (String) -> String = { match.home ? $0.uppercased() : $0.lowercased() }
        return VStack(spacing: 0) {
            Text(cased(match.isLeague ? match.opponent : match.competition))
                .font(.caption2.weight(.bold))
            if !match.isLeague {
                Text(cased(String(match.opponent.prefix(7))))
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(match.isLeague ? ToolkitColor.canvas : .white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(match.isLeague ? ToolkitColor.primaryText : Color(red: 0.278, green: 0.333, blue: 0.412),
                    in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Club by club (accessibility sizes)

    private func clubList(_ congestion: ResearchCongestion) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            ForEach(congestion.clubs) { club in
                VStack(alignment: .leading, spacing: 2) {
                    Text(appModel.club(club.clubId)?.name ?? "Club")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(clubLines(club, congestion).joined(separator: "\n"))
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(club, congestion))
            }
        }
    }

    // MARK: Words

    private func clubLines(_ club: ResearchCongestion.Club, _ congestion: ResearchCongestion) -> [String] {
        var lines = [countWords(club)]
        for day in club.days {
            for match in day.matches {
                lines.append("\(dayWords(day.day, congestion)): \(matchWords(match))")
            }
        }
        return lines
    }

    private func countWords(_ club: ResearchCongestion.Club) -> String {
        var parts = ["\(club.count) \(club.count == 1 ? "game" : "games") in the window"]
        if let shortest = club.shortest { parts.append("shortest rest \(shortest) \(shortest == 1 ? "day" : "days")") }
        if let next = club.daysToNext { parts.append(next == 0 ? "plays today" : "next game in \(next) \(next == 1 ? "day" : "days")") }
        return parts.joined(separator: ", ")
    }

    private func dayWords(_ day: Int, _ congestion: ResearchCongestion) -> String {
        guard let date = Self.date(congestion.dates[safe: day]) else { return "Day \(day + 1)" }
        let text = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return day == congestion.todayIndex ? "Today, \(text)" : text
    }

    private func matchWords(_ match: ResearchCongestion.Match) -> String {
        let opponent = match.isLeague ? (clubName(short: match.opponent) ?? match.opponent) : match.opponent
        let competition = match.isLeague ? "Premier League" : Self.competitionName(match.competition)
        return "\(competition), \(opponent) \(match.home ? "at home" : "away")"
    }

    private func spoken(_ club: ResearchCongestion.Club, _ congestion: ResearchCongestion) -> String {
        ([appModel.club(club.clubId)?.name ?? "Club"] + clubLines(club, congestion)).joined(separator: ". ")
    }

    private func clubName(short: String) -> String? {
        appModel.bootstrap?.value.clubs.first { $0.shortName == short }?.name
    }

    nonisolated static func competitionName(_ abbreviation: String) -> String {
        switch abbreviation {
        case "UCL": "Champions League"
        case "UEL": "Europa League"
        case "UECL": "Conference League"
        case "FAC": "FA Cup"
        case "EFL": "Carabao Cup"
        default: abbreviation
        }
    }

    /// A column's calendar date ("2026-09-24"), at midday so the day never slips.
    nonisolated static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    private func notes(_ congestion: ResearchCongestion) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
            Text("Under each club: its games in the window, its shortest rest, and the days to its next game. The coloured days between games are the recovery period.")
            if !congestion.missingCompetitions.isEmpty {
                Text("No \(ListFormatter.localizedString(byJoining: congestion.missingCompetitions)) games in this window.")
            }
            if congestion.feed.stale {
                Text(congestion.feed.updatedAt.map { "Cup and European fixtures were last updated \(Format.ago($0)), so recent changes may be missing." }
                     ?? "Cup and European fixtures aren't available right now, so only league games may show.")
                    .foregroundStyle(ToolkitColor.warning)
            }
        }
        .font(.footnote)
        .foregroundStyle(ToolkitColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The website's recovery colours, level 1 (9+ days) to 7 (a day or less). Solid versions of its
/// tints, with dark or white text chosen so every step reads at 4.5:1 or better.
enum RestColor {
    static func fill(_ level: Int) -> Color {
        switch level {
        case 1: Color(red: 0.490, green: 0.827, blue: 0.988)  // sky
        case 2: Color(red: 0.431, green: 0.906, blue: 0.718)  // light emerald
        case 3: Color(red: 0.063, green: 0.725, blue: 0.506)  // emerald
        case 4: Color(red: 0.639, green: 0.902, blue: 0.208)  // lime
        case 5: Color(red: 0.984, green: 0.749, blue: 0.141)  // amber
        case 6: Color(red: 0.976, green: 0.451, blue: 0.086)  // orange
        case 7: Color(red: 0.863, green: 0.149, blue: 0.149)  // red
        default: ToolkitColor.raised
        }
    }

    static func text(_ level: Int) -> Color {
        switch level {
        case 7: .white
        case 1...6: Color(red: 0.047, green: 0.063, blue: 0.086)
        default: ToolkitColor.secondaryText
        }
    }
}
