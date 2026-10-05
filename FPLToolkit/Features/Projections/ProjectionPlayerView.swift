import Charts
import SwiftUI

/// A player's forecast (happy-backend-pal#74; redesigned 5 Oct 2026 from Dan's concept "a focused
/// forecast, detailed assumptions stay accessible"): projected points, the range and the 10+
/// chance first, then the possible outcomes, playing time (with your forecast), the next gameweeks,
/// and the website's breakdown in sections that open on demand.
struct ProjectionPlayerView: View {
    @Environment(AppModel.self) private var appModel
    /// Present when opened from the projections list, where playing-time forecasts apply.
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
    @State private var showingReading = false
    @State private var showingOutcomesInfo = false

    var body: some View {
        Group {
            switch resource?.phase {
            case .loading?, nil:
                ScrollView {
                    SkeletonCards(caption: "Loading the forecast…")
                        .padding(.horizontal, ToolkitSpace.page)
                }
            case .failed(let copy)?:
                ErrorStateView(copy: copy) {
                    Task { await resource?.retry() }
                }
            case .loaded(let loaded)?:
                if let resource {
                    ScrollView {
                        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
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
        .navigationTitle("Player forecast")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingReading = true } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Reading the numbers")
            }
        }
        .sheet(item: $editing) { target in
            if let tweaks { ProjectionMinutesSheet(target: target, tweaks: tweaks) }
        }
        .sheet(isPresented: $showingReading) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        if let run = resource?.loaded?.value.run {
                            Text(ProjectionText.status(run))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                        }
                        ProjectionReadingContent()
                    }
                    .padding(ToolkitSpace.page)
                }
                .toolkitScreen()
                .navigationTitle("Reading the numbers")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingReading = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingOutcomesInfo) {
            InfoSheet(title: "Possible outcomes",
                      message: "Each bar is the chance of that many points in the gameweek, from about 2,000 simulated games. The dashed line is the projected points (the mean). The last bar adds up every outcome of 15 points or more.")
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
            gameweekMenu(data.gameweeks, selected: gw)
            ProjectionSummaryCard(gw: gw)
            outcomes(gw)
            playingTime(gw, data: data)
            nextGameweeks(data.gameweeks, after: gw)
            VStack(spacing: 0) {
                ProjectionDisclosure(title: "Points by source") {
                    ProjectionSources(components: gw.components)
                }
                ProjectionDisclosure(title: "Playing-time assumptions") {
                    explained(gw.minutes)
                }
                ProjectionDisclosure(title: "Match context and rates") {
                    matchContext(gw)
                    if let rates = gw.rates {
                        Text("Rates per 90")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ToolkitColor.primaryText)
                            .padding(.top, ToolkitSpace.sm)
                        explained(rates)
                    }
                }
                ProjectionDisclosure(title: "More figures") {
                    ProjectionFigures(gw: gw)
                }
                if !data.horizons.isEmpty {
                    ProjectionDisclosure(title: "Over the horizon") {
                        horizons(data.horizons)
                    }
                }
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
        }
    }

    // MARK: Header

    private func header(_ data: ProjectionPlayer) -> some View {
        let p = data.player
        return HStack(alignment: .center, spacing: ToolkitSpace.md) {
            PlayerPhoto(path: p.photo, clubLogo: appModel.club(p.clubId)?.logo, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.webName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                Text(Format.unbroken([appModel.club(p.clubId)?.shortName, p.position.rawValue, Format.price(p.price)]
                    .compactMap { $0 }.joined(separator: " · ")))
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                // Only when there's something to say.
                if data.availabilityText != "No availability flag" {
                    Label(data.availabilityText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func gameweekMenu(_ gws: [ProjectionPlayer.Gameweek], selected: ProjectionPlayer.Gameweek) -> some View {
        Menu {
            Picker("Gameweek", selection: Binding(get: { selected.gameweek }, set: { gameweek = $0 })) {
                ForEach(gws) { g in Text(Self.gwLabel(g)).tag(g.gameweek) }
            }
        } label: {
            FilterChipLabel(text: Self.gwLabel(selected), active: false, menu: true)
        }
        .accessibilityLabel("Gameweek: \(Self.gwLabel(selected))")
    }

    /// "GW6", "GW7 · blank", "GW8 · 2 fixtures".
    nonisolated static func gwLabel(_ g: ProjectionPlayer.Gameweek) -> String {
        g.fixtureCount == 0 ? "GW\(g.gameweek) · blank" : g.fixtureCount > 1 ? "GW\(g.gameweek) · \(g.fixtureCount) fixtures" : "GW\(g.gameweek)"
    }

    // MARK: Sections

    @ViewBuilder
    private func outcomes(_ gw: ProjectionPlayer.Gameweek) -> some View {
        Button { showingOutcomesInfo = true } label: {
            HStack(spacing: 6) {
                Text("Possible outcomes")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                Image(systemName: "info.circle")
                    .foregroundStyle(ToolkitColor.link)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("What the chart shows")
        ProjectionDistributionChart(gw: gw)
    }

    @ViewBuilder
    private func playingTime(_ gw: ProjectionPlayer.Gameweek, data: ProjectionPlayer) -> some View {
        let model = gw.minutes.figures.first { $0.label == "60+ min" }?.value ?? "—"
        let canAdjust = tweaks != nil && data.run.map { gw.gameweek == $0.fromGw } == true
        let yours = canAdjust ? (tweaks?.allNailed == true ? 100 : tweaks?.minutes[playerId]) : nil
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            NameFigureRow {
                Text("60+ minutes")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
            } details: {
                if yours != nil {
                    Text("Your forecast. The model says \(model).")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            } figure: {
                Text(yours.map { "\($0)%" } ?? model)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(yours != nil ? ToolkitColor.accent : ToolkitColor.primaryText)
            }
            .accessibilityElement(children: .combine)
            if canAdjust, let run = data.run {
                Button {
                    editing = ProjectionMinutesTarget(playerId: playerId, name: data.player.webName,
                                                      gameweek: run.fromGw, modelPct: modelSixtyPct)
                } label: {
                    HStack(spacing: ToolkitSpace.md) {
                        Image(systemName: "slider.horizontal.3").accessibilityHidden(true)
                        Text("Adjust playing time")
                            .font(.body.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .foregroundStyle(ToolkitColor.accent)
                    .padding(.horizontal, ToolkitSpace.lg)
                    .frame(minHeight: 52)
                    .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Set your own chance of him playing 60 minutes; the list's figures rescale")
            }
        }
    }

    /// The next three gameweeks' projected points; a tap switches to one (concept 04).
    @ViewBuilder
    private func nextGameweeks(_ gws: [ProjectionPlayer.Gameweek], after gw: ProjectionPlayer.Gameweek) -> some View {
        let next = Array(gws.filter { $0.gameweek > gw.gameweek }.prefix(3))
        if !next.isEmpty {
            Text("Next gameweeks")
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 10, lineSpacing: 10) {
                ForEach(next) { g in
                    Button { gameweek = g.gameweek } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Self.gwLabel(g))
                                .font(.subheadline)
                                .foregroundStyle(ToolkitColor.secondaryText)
                            Text(ProjectionText.one(g.mean))
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundStyle(ToolkitColor.primaryText)
                        }
                        .padding(.horizontal, ToolkitSpace.lg)
                        .padding(.vertical, ToolkitSpace.md)
                        .frame(minWidth: 96, minHeight: 64, alignment: .leading)
                        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Gameweek \(g.gameweek): \(ProjectionText.one(g.mean)) projected points")
                    .accessibilityHint("Shows that gameweek's forecast")
                }
            }
        }
    }

    @ViewBuilder
    private func explained(_ e: ProjectionPlayer.Gameweek.Explained) -> some View {
        FigureGrid(items: e.figures.map { FigureGrid.Item(label: $0.label, value: $0.value) })
        if !e.basis.isEmpty { BulletList(items: e.basis) }
    }

    @ViewBuilder
    private func matchContext(_ gw: ProjectionPlayer.Gameweek) -> some View {
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
                        Text("projected").font(.caption).foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Gameweeks \(h.label.replacingOccurrences(of: "GW", with: "")), \(h.horizon) gameweeks. Projected \(ProjectionText.one(h.mean)), median \(h.median), most likely \(h.mode), 80% range \(h.p10) to \(h.p90). Chance of at least one haul \(ProjectionText.pct(h.anyHaulPct)), of blanking every week \(ProjectionText.pct(h.allBlankPct)).")
            }
        }
    }
}

// MARK: - Summary

/// The headline (concept 04): projected points large, with the range and the 10+ chance beside it.
struct ProjectionSummaryCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let gw: ProjectionPlayer.Gameweek

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ToolkitSpace.md))
            : AnyLayout(HStackLayout(alignment: .center, spacing: ToolkitSpace.lg))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("Projected points")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                Text(ProjectionText.one(gw.mean))
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Grid(alignment: .leading, horizontalSpacing: ToolkitSpace.lg, verticalSpacing: 6) {
                GridRow {
                    Text("Range").foregroundStyle(ToolkitColor.secondaryText)
                    Text("\(gw.p10)–\(gw.p90)").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
                        .gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text("10+ points").foregroundStyle(ToolkitColor.secondaryText)
                    Text(ProjectionText.pct(gw.haulPct)).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
                }
            }
            .font(.subheadline)
        }
        .padding(ToolkitSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolkitCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Projected \(ProjectionText.one(gw.mean)) points. 80% range \(gw.p10) to \(gw.p90). Chance of 10 or more \(ProjectionText.pct(gw.haulPct)).")
    }
}

/// A section of the breakdown that opens on demand (concept 04: "detailed assumptions stay
/// accessible").
struct ProjectionDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: ToolkitSpace.sm) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ToolkitSpace.sm)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the details" : "Shows the details")
            if expanded {
                content()
            }
            Divider().overlay(ToolkitColor.border)
        }
    }
}

// MARK: - Figures

/// The rest of the website's tiles for a gameweek ("More figures").
struct ProjectionFigures: View {
    let gw: ProjectionPlayer.Gameweek

    var body: some View {
        FigureGrid(items: [
            .init(label: "Mean (projected)", value: ProjectionText.one(gw.mean)),
            .init(label: "Median", value: "\(gw.median)"),
            .init(label: "Mode (most likely)", value: "\(gw.mode)"),
            .init(label: "P10 (bad week)", value: "\(gw.p10)"),
            .init(label: "P90 (good week)", value: "\(gw.p90)"),
            .init(label: "Haul 10+", value: ProjectionText.pct(gw.haulPct)),
            .init(label: "Blank ≤2", value: ProjectionText.pct(gw.blankPct), spoken: "\(ProjectionText.pct(gw.blankPct)), 2 points or fewer"),
        ])
    }
}

/// The chance of each points total as bars, everything from 15 up in one bar, and the projected
/// points as a dashed line (concept 04). VoiceOver reads it as one summary.
struct ProjectionDistributionChart: View {
    let gw: ProjectionPlayer.Gameweek

    private struct Bar: Identifiable {
        let points: Int
        let chance: Double
        var id: Int { points }
    }

    var body: some View {
        let bars = ProjectionText.bucketed(gw.chart).map { Bar(points: $0.points, chance: $0.chance) }
        let first = bars.first?.points ?? 0
        let last = max(bars.last?.points ?? 15, first + 1)
        let maxP = max(0.05, bars.map(\.chance).max() ?? 0)
        let meanX = min(Double(last), max(Double(first), gw.mean))
        let ticks = Array(stride(from: 0, through: last, by: 5)).filter { $0 >= first }
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                // Rectangles, not BarMarks: on a numeric axis a BarMark's width came out as nothing.
                ForEach(bars) { bar in
                    RectangleMark(xStart: .value("From", Double(bar.points) - 0.38), xEnd: .value("To", Double(bar.points) + 0.38),
                                  yStart: .value("Base", 0), yEnd: .value("Chance", bar.chance))
                        .foregroundStyle(ToolkitColor.accent.opacity(bar.points >= 15 ? 0.7 : 1))
                }
                RuleMark(x: .value("Projected", meanX))
                    .foregroundStyle(ToolkitColor.information)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(ProjectionText.one(gw.mean))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ToolkitColor.information)
                    }
            }
            .chartXScale(domain: Double(first) - 0.5 ... Double(last) + 0.5, range: .plotDimension(padding: 10))
            .chartYScale(domain: 0 ... maxP)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: ticks.map(Double.init)) { value in
                    let v = Int(value.as(Double.self) ?? 0)
                    // Anchored at the top so the last label isn't dropped to "…".
                    AxisValueLabel(anchor: .top) { Text(v >= 15 ? "15+" : "\(v)") }
                }
            }
            .frame(height: 160)
            // The marks stay out of the accessibility tree; the card reads as one summary.
            .accessibilityHidden(true)
        }
        .padding(ToolkitSpace.lg)
        .toolkitCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Possible outcomes")
        .accessibilityValue("Most likely \(gw.mode) points. Projected \(ProjectionText.one(gw.mean)). 80% of outcomes between \(gw.p10) and \(gw.p90). \(ProjectionText.pct(gw.haulPct)) chance of 10 or more.")
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
