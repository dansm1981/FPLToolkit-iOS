import Charts
import SwiftUI

/// The rivalry look (Dan's design, 2 Oct): you in blue, the rival in red, gold for whoever leads.
/// Drawn in code (no artwork yet), so it works at every text size.
enum RivalColor {
    static let you = ToolkitColor.information
    static let them = ToolkitColor.error
    static let leader = ToolkitColor.accent
    static func fill(_ c: Color) -> Color { c.opacity(0.22) }
}

// MARK: - Overview hero

/// "YOU 45 VS ANDY 27" with the leader's crown and "19 PTS AHEAD": this gameweek's scores and the
/// season gap, the server's figures.
struct RivalVersusHero: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let rival: RivalSummary
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 54

    var body: some View {
        let gap = rival.gap
        VStack(spacing: 10) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                side("YOU", rival.you, colour: RivalColor.you, shirt: "RivalShirtYou", leads: (gap ?? 0) > 0)
                Text("VS")
                    .font(.title2.weight(.black).italic())
                    .foregroundStyle(RivalColor.leader)
                    .accessibilityHidden(true)
                side(rival.name.uppercased(), rival.them, colour: RivalColor.them, shirt: "RivalShirtThem", leads: (gap ?? 0) < 0)
            }
            if let gap {
                // The crown and gold only when you lead.
                HStack(spacing: 6) {
                    if gap > 0 {
                        Image(systemName: "crown.fill").foregroundStyle(RivalColor.leader).accessibilityHidden(true)
                    }
                    Text(headline(gap))
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(gap > 0 ? RivalColor.leader : ToolkitColor.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        // Dan's artwork (2 Oct): floodlit stadium behind, darkened so the figures read.
        .background {
            ZStack {
                Image("RivalStadium")
                    .resizable()
                    .scaledToFill()
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [RivalColor.you.opacity(0.25), .clear, RivalColor.them.opacity(0.25)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .accessibilityHidden(true)
        }
        // The stadium fills the card and no further.
        .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(RivalColor.leader.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The name and score printed on the shirt back; the shirt grows with the text.
    private func side(_ title: String, _ points: Int?, colour: Color, shirt: String, leads: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                if leads { Image(systemName: "crown.fill").font(.caption).foregroundStyle(RivalColor.leader) }
                Text(title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Text(points.map(String.init) ?? "–")
                .font(.system(size: scoreSize, weight: .black).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
        }
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .padding(.horizontal, 18)
        .background {
            Image(shirt)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private func headline(_ gap: Int) -> String {
        if gap == 0 { return "LEVEL ON POINTS" }
        return "\(abs(gap)) PT\(abs(gap) == 1 ? "" : "S") \(gap > 0 ? "AHEAD" : "BEHIND")"
    }

    private var spoken: String {
        var parts = ["This gameweek: you \(rival.you.map(String.init) ?? "not synced"), \(rival.name) \(rival.them.map(String.init) ?? "not synced")"]
        if let gap = rival.gapText { parts.append("Season: \(gap)") }
        return parts.joined(separator: ". ")
    }
}

/// The gameweek in words: how it started, the scores, who gained.
struct RivalStatusCard: View {
    let data: RivalComparison

    var body: some View {
        let r = data.rival
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.title2)
                .foregroundStyle(RivalColor.leader)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    if let start = data.startText {
                        Text(start).font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
                    }
                    Spacer(minLength: 6)
                    Tag(text: RivalViewText.state(data.status), foreground: RivalColor.leader, fill: RivalColor.fill(RivalColor.leader))
                }
                if let week = RivalText.thisWeek(r) {
                    Text(week).font(.subheadline).foregroundStyle(ToolkitColor.primaryText)
                }
                if let swing = r.swingText {
                    Text(swing).font(.title3.weight(.bold)).foregroundStyle(ToolkitColor.primaryText)
                }
                if let bonus = RivalText.bonus(r) {
                    Text(bonus).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(RivalColor.leader.opacity(0.4)))
        .accessibilityElement(children: .combine)
    }
}

/// "Rivalry momentum": the season gap after each gameweek, the latest marked.
struct RivalMomentumChart: View {
    let trend: [RivalComparison.Stats.GapPoint]
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RIVALRY MOMENTUM")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                Spacer()
                if let last = trend.last {
                    Text(last.gap > 0 ? "+\(last.gap)" : last.gap < 0 ? "−\(-last.gap)" : "0")
                        .font(.caption.weight(.heavy).monospacedDigit())
                        .foregroundStyle(ToolkitColor.onAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(last.gap >= 0 ? RivalColor.you : RivalColor.them, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Chart {
                RuleMark(y: .value("Level", 0))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ForEach(trend, id: \.gw) { p in
                    AreaMark(x: .value("Gameweek", p.gw), yStart: .value("Level", 0), yEnd: .value("Gap", p.gap))
                        .foregroundStyle(LinearGradient(colors: [RivalColor.you.opacity(0.35), RivalColor.them.opacity(0.35)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Gameweek", p.gw), y: .value("Gap", p.gap))
                        .foregroundStyle(RivalColor.you)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Gameweek", p.gw), y: .value("Gap", p.gap))
                        .foregroundStyle(p.gap >= 0 ? RivalColor.you : RivalColor.them)
                }
            }
            .chartXScale(range: .plotDimension(padding: 14))
            .chartXAxis {
                AxisMarks(values: trend.map(\.gw)) { value in
                    AxisValueLabel(anchor: .top) { Text("GW\(value.as(Int.self) ?? 0)") }
                }
            }
            .frame(height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rivalry momentum, the gap after each gameweek")
            .accessibilityValue(trend.map { "GW\($0.gw) \(RivalStatsText.gap($0.gap, name: name))" }.joined(separator: "; "))
            Text("Above the line you're ahead of \(name); below it, \(name) is.")
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }
}

/// "KEY INSIGHT": the server's main reason behind the gameweek.
struct RivalInsightCard: View {
    let text: String
    var title = "KEY INSIGHT"
    var systemImage = "lightbulb"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(RivalColor.leader)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RivalColor.leader)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(RivalColor.leader.opacity(0.45)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Teams tiles

/// "3 Shared · 7 You only · 5 Andy only" across the two starting XIs.
struct RivalTeamTiles: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let summary: (shared: Int, yours: Int, theirs: Int)
    let name: String

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            tile("\(summary.shared)", "Shared", colour: ToolkitColor.positive)
            tile("\(summary.yours)", "You only", colour: RivalColor.you)
            tile("\(summary.theirs)", "\(name) only", colour: RivalColor.them)
        }
    }

    private func tile(_ value: String, _ label: String, colour: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(RivalColor.fill(colour), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colour.opacity(0.6)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stats

/// Season points for each of you, the leader crowned.
struct RivalTotalsTiles: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let you: Int
    let them: Int
    let name: String
    let label: String

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            tile("You", you, colour: RivalColor.you, leads: you > them)
            tile(name, them, colour: RivalColor.them, leads: them > you)
        }
    }

    private func tile(_ title: String, _ value: Int, colour: Color, leads: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.headline).foregroundStyle(ToolkitColor.primaryText)
                Spacer()
                if leads {
                    Image(systemName: "crown.fill").foregroundStyle(RivalColor.leader).accessibilityLabel("Leading")
                }
            }
            Text("\(value)").font(.largeTitle.weight(.heavy).monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
            Text(label).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RivalColor.fill(colour), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(colour.opacity(leads ? 0.9 : 0.4), lineWidth: leads ? 1.5 : 1))
        .accessibilityElement(children: .combine)
    }
}

/// A tug of war: your figure, the label, theirs, and a bar split between you.
struct RivalTugRow: View {
    let title: String
    let you: Int
    let them: Int
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(you)").font(.headline.monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                Text("\(them)").font(.headline.monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
            }
            GeometryReader { geo in
                let total = max(abs(you) + abs(them), 1)
                let share = you == them ? 0.5 : CGFloat(abs(you)) / CGFloat(total)
                HStack(spacing: 3) {
                    Capsule().fill(RivalColor.you).frame(width: max(4, (geo.size.width - 3) * share))
                    Capsule().fill(RivalColor.them.opacity(0.75))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): you \(you), \(name) \(them)")
    }
}

/// Each side's points per gameweek, the latest labelled.
struct RivalWeeklyChart: View {
    let weekly: [RivalComparison.Stats.Week]
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("GAMEWEEK POINTS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                Spacer()
                legend("You", RivalColor.you)
                legend(name, RivalColor.them)
            }
            Chart {
                ForEach(weekly, id: \.gw) { w in
                    LineMark(x: .value("Gameweek", w.gw), y: .value("Points", w.you), series: .value("Side", "You"))
                        .foregroundStyle(RivalColor.you)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("Gameweek", w.gw), y: .value("Points", w.you))
                        .foregroundStyle(RivalColor.you)
                    LineMark(x: .value("Gameweek", w.gw), y: .value("Points", w.them), series: .value("Side", name))
                        .foregroundStyle(RivalColor.them)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 3]))
                    PointMark(x: .value("Gameweek", w.gw), y: .value("Points", w.them))
                        .foregroundStyle(RivalColor.them)
                }
            }
            .chartXScale(range: .plotDimension(padding: 14))
            .chartXAxis {
                AxisMarks(values: weekly.map(\.gw)) { value in
                    AxisValueLabel(anchor: .top) { Text("GW\(value.as(Int.self) ?? 0)") }
                }
            }
            .frame(height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Points each gameweek")
            .accessibilityValue(weekly.map { "GW\($0.gw): you \($0.you), \(name) \($0.them)" }.joined(separator: "; "))
        }
        .padding(15)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func legend(_ text: String, _ colour: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(colour).frame(width: 14, height: 4)
            Text(text).font(.caption).foregroundStyle(ToolkitColor.secondaryText)
        }
        .accessibilityHidden(true)
    }
}
