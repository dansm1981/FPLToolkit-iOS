import Charts
import SwiftUI

/// How one player's projection is built (the website's breakdown drawer, happy-backend-pal#74):
/// per gameweek the seven figures, the points distribution, minutes, match context, rates per 90
/// and points by source, then the horizon totals.
struct ProjectionPlayerView: View {
    @Environment(AppModel.self) private var appModel
    /// Present when opened from the projections list, where minutes forecasts apply.
    @Environment(ProjectionTweaks.self) private var tweaks: ProjectionTweaks?
    let playerId: Int
    var knownName: String?
    /// The model's 60+ chance in the run's first gameweek, from the list row.
    var modelSixtyPct: Int?
    /// False when opened from the player page, which would only lead back to itself.
    var showsPlayerLink = true
    @State private var resource: Resource<ProjectionPlayer>?
    @State private var gameweek: Int?
    @State private var editing: ProjectionMinutesTarget?

    var body: some View {
        Group {
            switch resource?.phase {
            case .loading?, nil:
                ScrollView {
                    SkeletonCards(caption: "Loading projection…")
                        .padding(.horizontal, ToolkitSpace.page)
                }
            case .failed(let copy)?:
                ErrorStateView(copy: copy) {
                    Task { await resource?.retry() }
                }
            case .loaded(let loaded)?:
                if let resource {
                    ScrollView {
                        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                            SavedDataBanner(resource: resource)
                            content(loaded.value)
                        }
                        .padding(.horizontal, ToolkitSpace.page)
                        .padding(.bottom, ToolkitSpace.section)
                    }
                    .refreshable { await resource.load(bypassCache: true) }
                }
            }
        }
        .toolkitScreen()
        .navigationTitle(resource?.loaded?.value.player.webName ?? knownName ?? "Projection")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            if let tweaks { ProjectionMinutesSheet(target: target, tweaks: tweaks) }
        }
        .task {
            if resource == nil {
                let resource = Resource(appModel.researchRepository.projectionPlayer(playerId))
                self.resource = resource
                await resource.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ data: ProjectionPlayer) -> some View {
        header(data)
        if data.run == nil {
            RivalNote(text: "No projection run yet. Once the projection sync has run, the latest one shows here.")
        } else if data.gameweeks.isEmpty {
            RivalNote(text: "No gameweeks in this run.")
        } else {
            let gw = data.gameweeks.first { $0.gameweek == gameweek } ?? data.gameweeks[0]
            gameweekChips(data.gameweeks, selected: gw.gameweek)
            ProjectionFigures(gw: gw)
            ProjectionDistributionChart(gw: gw)
            minutes(gw, data: data)
            matchContext(gw)
            if let rates = gw.rates {
                section("3. Rates per 90")
                explained(rates)
            }
            section("4. Expected points by source")
            ProjectionSources(components: gw.components)
            if !data.horizons.isEmpty {
                section("Over the horizon")
                horizons(data.horizons)
            }
        }
        if showsPlayerLink {
            CardGroup {
                NavigationLink {
                    PlayerDetailView(playerId: data.player.id, knownName: data.player.webName)
                } label: {
                    LinkRowLabel(title: "Open \(data.player.webName)'s player page", detail: nil, systemImage: "person")
                }
                .buttonStyle(.plain)
            }
            .padding(.top, ToolkitSpace.sm)
        }
    }

    // MARK: Header

    private func header(_ data: ProjectionPlayer) -> some View {
        let p = data.player
        return HStack(alignment: .top, spacing: ToolkitSpace.md) {
            PlayerPhoto(path: p.photo, clubLogo: appModel.club(p.clubId)?.logo, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(p.webName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                ClubLabel(clubId: p.clubId,
                          text: Format.unbroken([appModel.club(p.clubId)?.shortName, p.position.rawValue, Format.price(p.price)]
                            .compactMap { $0 }.joined(separator: " · ")),
                          logoSize: 15)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                if let run = data.run {
                    ProjectionStagePill(stage: run.stage, tone: .breakdown)
                }
                Text(data.availabilityText)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func gameweekChips(_ gws: [ProjectionPlayer.Gameweek], selected: Int) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(gws) { g in
                let note = g.fixtureCount == 0 ? " blank" : g.fixtureCount > 1 ? " ×\(g.fixtureCount)" : ""
                Button { gameweek = g.gameweek } label: {
                    FilterChipLabel(text: "GW\(g.gameweek)\(note)", active: g.gameweek == selected, menu: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gameweek \(g.gameweek)\(g.fixtureCount == 0 ? ", blank" : g.fixtureCount > 1 ? ", \(g.fixtureCount) fixtures" : "")")
                .accessibilityAddTraits(g.gameweek == selected ? .isSelected : [])
            }
        }
    }

    // MARK: Sections

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(ToolkitColor.primaryText)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, ToolkitSpace.sm)
    }

    @ViewBuilder
    private func explained(_ e: ProjectionPlayer.Gameweek.Explained) -> some View {
        FigureGrid(items: e.figures.map { FigureGrid.Item(label: $0.label, value: $0.value) })
        if !e.basis.isEmpty { BulletList(items: e.basis) }
    }

    @ViewBuilder
    private func minutes(_ gw: ProjectionPlayer.Gameweek, data: ProjectionPlayer) -> some View {
        section("1. Minutes")
        explained(gw.minutes)
        // Your forecast applies to the list's first gameweek, as the website's 60+ slider does.
        if let tweaks, let run = data.run, gw.gameweek == run.fromGw {
            let yours = tweaks.allNailed ? 100 : tweaks.minutes[playerId]
            CardGroup {
                LinkRow(title: "Your minutes forecast",
                        detail: yours.map { "\($0)% to play 60+ (the model says \(ProjectionText.pct(modelSixtyPct))). Applies to the projections list." }
                            ?? "Set your own chance of 60+ minutes for the projections list.",
                        systemImage: "slider.horizontal.3") {
                    editing = ProjectionMinutesTarget(playerId: playerId, name: data.player.webName,
                                                      gameweek: run.fromGw, modelPct: modelSixtyPct)
                }
            }
        }
    }

    @ViewBuilder
    private func matchContext(_ gw: ProjectionPlayer.Gameweek) -> some View {
        section("2. Match context")
        if gw.fixtures.isEmpty {
            RivalNote(text: "Blank gameweek: no fixture, no points.")
        } else {
            CardGroup {
                ForEach(Array(gw.fixtures.enumerated()), id: \.offset) { index, f in
                    if index > 0 { RowDivider() }
                    fixtureRow(f)
                }
            }
        }
    }

    private func fixtureRow(_ f: ProjectionPlayer.Fixture) -> some View {
        let opponent = appModel.club(f.opponentId)
        let source = f.source == .market ? "Market FDR" : "Fitted model"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: ToolkitSpace.sm) {
                Tag(text: f.home ? "H" : "A", foreground: ToolkitColor.primaryText)
                ClubLabel(clubId: f.opponentId, text: opponent?.name ?? "Club \(f.opponentId)", logoSize: 16)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
            }
            Text(Format.unbroken("Team xG \(ProjectionText.two(f.teamXg)) · Opp xG \(ProjectionText.two(f.opponentXg)) · Clean sheet \(f.cleanSheetPct)% · DefCon factor \(ProjectionText.two(f.defconFactor)) · \(source)"))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(f.home ? "Home to" : "Away at") \(opponent?.name ?? "club \(f.opponentId)"). Team xG \(ProjectionText.two(f.teamXg)), opponent xG \(ProjectionText.two(f.opponentXg)), clean sheet chance \(f.cleanSheetPct)%, DefCon factor \(ProjectionText.two(f.defconFactor)). From the \(source).")
    }

    private func horizons(_ rows: [ProjectionPlayer.Horizon]) -> some View {
        CardGroup {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, h in
                if index > 0 { RowDivider() }
                NameFigureRow {
                    Text("\(h.label) (\(h.horizon))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                } details: {
                    Text(Format.unbroken("Median \(h.median) · Mode \(h.mode) · Range \(h.p10)–\(h.p90) · ≥1 haul \(ProjectionText.pct(h.anyHaulPct)) · All blank \(ProjectionText.pct(h.allBlankPct))"))
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                } figure: {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(ProjectionText.one(h.mean)).font(.headline.monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
                        Text("mean").font(.caption).foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Gameweeks \(h.label.replacingOccurrences(of: "GW", with: "")), \(h.horizon) gameweeks. Mean \(ProjectionText.one(h.mean)), median \(h.median), most likely \(h.mode), 80% range \(h.p10) to \(h.p90). Chance of at least one haul \(ProjectionText.pct(h.anyHaulPct)), of blanking every week \(ProjectionText.pct(h.allBlankPct)).")
            }
        }
    }
}

// MARK: - Figures

/// The website's seven tiles for a gameweek.
struct ProjectionFigures: View {
    let gw: ProjectionPlayer.Gameweek

    var body: some View {
        FigureGrid(items: [
            .init(label: "Mean (average)", value: ProjectionText.one(gw.mean)),
            .init(label: "Median", value: "\(gw.median)"),
            .init(label: "Mode (most likely)", value: "\(gw.mode)"),
            .init(label: "P10 (bad week)", value: "\(gw.p10)"),
            .init(label: "P90 (good week)", value: "\(gw.p90)"),
            .init(label: "Haul 10+", value: ProjectionText.pct(gw.haulPct)),
            .init(label: "Blank ≤2", value: ProjectionText.pct(gw.blankPct), spoken: "\(ProjectionText.pct(gw.blankPct)), 2 points or fewer"),
        ])
    }
}

/// The chance of each points total as bars, the P10–P90 band behind them and the mean as a
/// dashed line; the mode at full strength, the rest at 60% (the website's chart). VoiceOver reads
/// it as one summary.
struct ProjectionDistributionChart: View {
    let gw: ProjectionPlayer.Gameweek

    private struct Bar: Identifiable {
        let points: Int
        let chance: Double
        var id: Int { points }
    }

    var body: some View {
        let bars = gw.chart.bars.enumerated().map { Bar(points: gw.chart.first + $0.offset, chance: $0.element) }
        let maxP = max(0.05, bars.map(\.chance).max() ?? 0)
        let last = gw.chart.first + max(0, bars.count - 1)
        let step = bars.count > 40 ? 5 : bars.count > 20 ? 2 : 1
        let meanX = min(Double(last), max(Double(gw.chart.first), gw.mean))
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                RectangleMark(xStart: .value("P10", Double(gw.p10) - 0.5), xEnd: .value("P90", Double(gw.p90) + 0.5),
                              yStart: .value("Base", 0), yEnd: .value("Top", maxP))
                    .foregroundStyle(ToolkitColor.accent.opacity(0.12))
                // Rectangles, not BarMarks: on a numeric axis a BarMark's width came out as nothing.
                ForEach(bars) { bar in
                    RectangleMark(xStart: .value("From", Double(bar.points) - 0.4), xEnd: .value("To", Double(bar.points) + 0.4),
                                  yStart: .value("Base", 0), yEnd: .value("Chance", bar.chance))
                        .foregroundStyle(ToolkitColor.accent.opacity(bar.points == gw.mode ? 1 : 0.6))
                }
                RuleMark(x: .value("Mean", meanX))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("mean \(ProjectionText.one(gw.mean))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ToolkitColor.primaryText)
                    }
            }
            // Padding at the ends so the first and last labels aren't cut off.
            .chartXScale(domain: Double(gw.chart.first) - 0.5 ... Double(last) + 0.5, range: .plotDimension(padding: 10))
            .chartYScale(domain: 0 ... maxP)
            .chartXAxis {
                AxisMarks(values: Array(stride(from: gw.chart.first, through: last, by: step)).map(Double.init)) { value in
                    // Anchored at the top so the last label isn't dropped to "…".
                    AxisValueLabel(anchor: .top) { Text("\(Int(value.as(Double.self) ?? 0))") }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, maxP / 2, maxP]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(Int(((value.as(Double.self) ?? 0) * 100).rounded()))%") }
                }
            }
            .frame(height: 180)
            // The marks stay out of the accessibility tree (each would be an element); the card
            // below reads the chart as one summary.
            .accessibilityHidden(true)
            Text("Shaded: P10 \(gw.p10) to P90 \(gw.p90). Dashed: the mean.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ToolkitSpace.lg)
        .toolkitCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chance of each points total")
        .accessibilityValue("Most likely \(gw.mode) points, at \(Int(((bars.first { $0.points == gw.mode }?.chance ?? 0) * 100).rounded()))%. Median \(gw.median), mean \(ProjectionText.one(gw.mean)). 80% of outcomes between \(gw.p10) and \(gw.p90).")
    }
}

/// Expected points by source: a bar of the gains, then each source's value.
struct ProjectionSources: View {
    let components: [ProjectionPlayer.Component]

    var body: some View {
        let gains = components.filter { $0.value > 0 }
        let total = max(gains.reduce(0) { $0 + $1.value }, 0.01)
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(gains) { c in
                        Rectangle()
                            .fill(Self.color(c.key))
                            .frame(width: max(2, (geo.size.width - CGFloat(gains.count)) * c.value / total))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(Array(components.enumerated()), id: \.element.id) { index, c in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    HStack(spacing: ToolkitSpace.sm) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.color(c.key))
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(c.label)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        Spacer(minLength: ToolkitSpace.sm)
                        Text(ProjectionText.signed(c.value))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(c.value < 0 ? ToolkitColor.error : ToolkitColor.primaryText)
                    }
                    // 44 pt rows: the audit counts a combined element as something to tap.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(c.label): \(c.value < 0 ? "minus" : "plus") \(ProjectionText.two(abs(c.value))) points")
                }
            }
        }
        .padding(ToolkitSpace.lg)
        .toolkitCard()
    }

    /// One colour per source, in the app's palette (the website's own differ by theme).
    static func color(_ key: String) -> Color {
        switch key {
        case "appearance": ToolkitColor.secondaryText
        case "goals": ToolkitColor.accent
        case "assists": ToolkitColor.information
        case "clean_sheet": ToolkitColor.positive
        case "saves": .teal
        case "defcon": .purple
        case "bonus": ToolkitColor.warning
        default: ToolkitColor.error
        }
    }
}
