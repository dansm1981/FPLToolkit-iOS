import Charts
import SwiftUI

/// The season so far (Dan, 29 Sep): points each gameweek against FPL's average, overall and
/// gameweek rank over time, and the squad's value, with chips marked; then week by week and
/// earlier seasons. Opened from the score on Today's gameweek card, and from Matchday.
struct SeasonHistoryView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int
    @State private var resource: Resource<SeasonHistory>?

    var body: some View {
        Group {
            switch resource?.phase {
            case .loading?, nil:
                ScrollView {
                    SkeletonCards(caption: "Loading your season…", count: 3)
                        .padding(.horizontal, ToolkitSpace.page)
                }
            case .failed(let copy)?:
                ErrorStateView(copy: copy) {
                    Task { await resource?.retry() }
                }
            case .loaded(let loaded)?:
                ScrollView {
                    SeasonHistoryContent(history: loaded.value)
                        .padding(.horizontal, 18)
                        .padding(.bottom, ToolkitSpace.section)
                }
                .refreshable { await resource?.load(bypassCache: true) }
            }
        }
        .toolkitScreen()
        .navigationTitle("Season history")
        .task {
            if resource == nil {
                let resource = Resource(appModel.teamRepository.history(entryId: entryId))
                self.resource = resource
                await resource.load()
            }
        }
    }
}

private struct SeasonHistoryContent: View {
    let history: SeasonHistory

    private var weeks: [SeasonHistory.Week] { history.weeks }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            if weeks.isEmpty {
                InlineNotice(text: "No gameweeks played yet this season.")
            } else {
                FigureGrid(items: summary)

                SectionHeader(title: "Points")
                ChartCard(caption: "Bars are your points; the dashed line is FPL's average. Chips are marked above their week.") {
                    pointsChart
                }

                if weeks.contains(where: { $0.overallRank != nil }) {
                    SectionHeader(title: "Overall rank")
                    ChartCard(caption: "Higher on the chart is better.") {
                        rankChart(\.overallRank, name: "Overall rank")
                    }
                }

                if weeks.contains(where: { $0.gwRank != nil }) {
                    SectionHeader(title: "Gameweek rank")
                    ChartCard(caption: "Your rank for each gameweek's points alone.") {
                        rankChart(\.gwRank, name: "Gameweek rank")
                    }
                }

                if weeks.contains(where: { $0.value != nil }) {
                    SectionHeader(title: "Team value")
                    ChartCard(caption: "The squad's value at each deadline, bank not included.") {
                        valueChart
                    }
                }

                SectionHeader(title: "Week by week")
                CardGroup {
                    ForEach(Array(weeks.reversed().enumerated()), id: \.element.id) { index, week in
                        if index > 0 { RowDivider() }
                        WeekRow(week: week, previous: weeks.first { $0.gw == week.gw - 1 })
                    }
                }
            }

            if !history.past.isEmpty {
                SectionHeader(title: "Earlier seasons")
                CardGroup {
                    ForEach(Array(history.past.reversed().enumerated()), id: \.element.season) { index, season in
                        if index > 0 { RowDivider() }
                        HStack {
                            Text(season.season)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(season.totalPoints.formatted()) pts")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(ToolkitColor.primaryText)
                                if let rank = season.rank {
                                    Text("Rank \(Format.rank(rank))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(ToolkitColor.secondaryText)
                                }
                            }
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: Summary

    private var summary: [FigureGrid.Item] {
        guard let last = weeks.last else { return [] }
        var items = [FigureGrid.Item(label: "Season points", value: last.totalPoints.formatted())]
        if let rank = last.overallRank {
            items.append(.init(label: "Overall rank", value: Format.rank(rank)))
        }
        if let best = weeks.max(by: { $0.points < $1.points }) {
            items.append(.init(label: "Best gameweek", value: "\(best.points) · GW\(best.gw)",
                               spoken: "\(best.points) points in gameweek \(best.gw)"))
        }
        let hits = weeks.reduce(0) { $0 + $1.hitPoints }
        items.append(.init(label: "Points on hits", value: hits == 0 ? "0" : "−\(hits)",
                           spoken: hits == 0 ? "none" : "minus \(hits)"))
        return items
    }

    // MARK: Charts

    private var gwAxis: [Int] {
        let gws = weeks.map(\.gw)
        guard gws.count > 10 else { return gws }
        return gws.filter { $0 == gws.first || $0 % 5 == 0 }
    }

    private var pointsChart: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Gameweek", week.gw), y: .value("Points", week.points), width: .fixed(barWidth))
                    .foregroundStyle(ToolkitColor.accent)
                    .annotation(position: .top, spacing: 2) {
                        if let chip = week.chip {
                            Text(SeasonText.chipShort(chip))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(ToolkitColor.primaryText)
                        }
                    }
            }
            ForEach(weeks.filter { $0.average != nil }) { week in
                LineMark(x: .value("Gameweek", week.gw), y: .value("Average", week.average ?? 0),
                         series: .value("Series", "Average"))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
        }
        .chartXScale(domain: (weeks.first?.gw ?? 1) - 1 ... (weeks.last?.gw ?? 1) + 1)
        .chartXAxis {
            AxisMarks(values: gwAxis) { value in
                AxisValueLabel { Text("GW\(value.as(Int.self) ?? 0)") }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 200)
        // One element with the figures read out, not a tree of marks.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Points by gameweek")
        .accessibilityValue(weeks.map { week in
            "GW\(week.gw) \(week.points)" + (week.average.map { ", average \($0)" } ?? "")
                + (week.chip.map { ", \(TeamText.chipName($0))" } ?? "")
        }.joined(separator: "; "))
    }

    private var barWidth: CGFloat { weeks.count > 20 ? 6 : weeks.count > 10 ? 10 : 18 }

    private func rankChart(_ rank: KeyPath<SeasonHistory.Week, Int?>, name: String) -> some View {
        let ranked = weeks.filter { $0[keyPath: rank] != nil }
        return Chart(ranked) { week in
            LineMark(x: .value("Gameweek", week.gw), y: .value(name, week[keyPath: rank] ?? 0))
                .foregroundStyle(ToolkitColor.link)
            PointMark(x: .value("Gameweek", week.gw), y: .value(name, week[keyPath: rank] ?? 0))
                .foregroundStyle(ToolkitColor.link)
                .symbolSize(24)
        }
        // Rank 1 at the top.
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartXScale(domain: (ranked.first?.gw ?? 1)...max(ranked.last?.gw ?? 1, (ranked.first?.gw ?? 1) + 1),
                     range: .plotDimension(padding: 12))
        .chartXAxis {
            AxisMarks(values: gwAxis) { value in
                AxisValueLabel { Text("GW\(value.as(Int.self) ?? 0)") }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { Text(SeasonText.axisRank(value.as(Int.self) ?? 0)) }
            }
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) by gameweek")
        .accessibilityValue(ranked.map { "GW\($0.gw) \(($0[keyPath: rank] ?? 0).formatted())" }.joined(separator: "; "))
    }

    private var valueChart: some View {
        let valued = weeks.filter { $0.value != nil }
        return Chart(valued) { week in
            LineMark(x: .value("Gameweek", week.gw), y: .value("Value", week.value ?? 0))
                .foregroundStyle(ToolkitColor.positive)
            PointMark(x: .value("Gameweek", week.gw), y: .value("Value", week.value ?? 0))
                .foregroundStyle(ToolkitColor.positive)
                .symbolSize(24)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(domain: (valued.first?.gw ?? 1)...max(valued.last?.gw ?? 1, (valued.first?.gw ?? 1) + 1),
                     range: .plotDimension(padding: 12))
        .chartXAxis {
            AxisMarks(values: gwAxis) { value in
                AxisValueLabel { Text("GW\(value.as(Int.self) ?? 0)") }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { Text(Format.price(value.as(Double.self) ?? 0)) }
            }
        }
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Team value by gameweek")
        .accessibilityValue(valued.map { "GW\($0.gw) \(Format.price($0.value ?? 0))" }.joined(separator: "; "))
    }
}

/// A chart in a card, with a line saying how to read it.
private struct ChartCard<Content: View>: View {
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
            Text(caption)
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolkitCard()
    }
}

/// One gameweek: points against the average, the chip, both ranks with the overall rank's move,
/// and transfers or hits.
private struct WeekRow: View {
    let week: SeasonHistory.Week
    let previous: SeasonHistory.Week?

    var body: some View {
        HStack(alignment: .top, spacing: ToolkitSpace.md) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("GW\(week.gw)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                    if let chip = week.chip {
                        Tag(text: TeamText.chipName(chip), foreground: ToolkitColor.accent, fill: ToolkitColor.goldTag)
                    }
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ToolkitSpace.sm)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(week.points) pts")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
                if let rank = week.overallRank {
                    HStack(spacing: 4) {
                        Text(Format.rank(rank))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(ToolkitColor.secondaryText)
                        RankMoveArrow(current: rank, previous: previous?.overallRank)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var details: String {
        var parts: [String] = []
        if let average = week.average { parts.append("Average \(average)") }
        if let gwRank = week.gwRank { parts.append("GW rank \(Format.rank(gwRank))") }
        if week.chip != "wildcard" && week.chip != "freehit" && week.transfers > 0 {
            parts.append("\(week.transfers) transfer\(week.transfers == 1 ? "" : "s")"
                         + (week.hitPoints > 0 ? " (−\(week.hitPoints))" : ""))
        }
        if week.benchPoints > 0 { parts.append("\(week.benchPoints) on the bench") }
        return parts.joined(separator: " · ")
    }

    private var spoken: String {
        var parts = ["Gameweek \(week.gw)", "\(week.points) points"]
        if let chip = week.chip { parts.append(TeamText.chipName(chip)) }
        parts.append(details)
        if let rank = week.overallRank {
            parts.append("overall rank \(rank.formatted())")
            if let move = RankMoveArrow.spoken(current: rank, previous: previous?.overallRank) { parts.append(move) }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum SeasonText {
    /// A chip over its bar: "WC", "FH", "BB", "TC".
    static func chipShort(_ code: String) -> String {
        switch code {
        case "wildcard": "WC"
        case "freehit": "FH"
        case "bboost": "BB"
        case "3xc": "TC"
        default: code.uppercased()
        }
    }

    /// A rank on a chart's axis, where there's no room for it in full: "1.2m", "350k", "8,431".
    static func axisRank(_ value: Int) -> String {
        if value >= 1_000_000 { return (Double(value) / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "m" }
        if value >= 10_000 { return (Double(value) / 1_000).formatted(.number.precision(.fractionLength(0))) + "k" }
        return value.formatted()
    }
}
