import Charts
import SwiftUI

/// Identifies which player sheet to open.
struct PlayerRef: Identifiable, Hashable {
    let id: Int
    /// Opened from a notification: the sheet says the facts may have moved on since.
    var fromAlert = false
}

/// S08 (availability), S09 (price) and S29 (research): the compact player sheet (§3.4).
struct PlayerSheetView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let playerId: Int
    /// The name we already know, shown while loading.
    var knownName: String?
    var fromAlert = false
    @State private var resource: Resource<PlayerSheet>?

    var body: some View {
        NavigationStack {
            Group {
                switch resource?.phase {
                case .loading?, nil:
                    ScrollView {
                        SkeletonCards(caption: "Loading player…")
                            .padding(.horizontal, ToolkitSpace.page)
                    }
                case .failed(let copy)?:
                    ErrorStateView(copy: copy) {
                        Task { await resource?.retry() }
                    }
                case .loaded(let loaded)?:
                    if let resource {
                        ScrollView {
                            VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
                                SavedDataBanner(resource: resource)
                                if fromAlert {
                                    Label("You opened an alert. This is the latest information, which may have changed since it was sent.", systemImage: "bell.badge")
                                        .font(.footnote)
                                        .foregroundStyle(ToolkitColor.information)
                                        .padding(ToolkitSpace.md)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(ToolkitColor.informationFill, in: RoundedRectangle(cornerRadius: ToolkitRadius.pill))
                                }
                                PlayerSheetContent(loaded: loaded)
                            }
                            .padding(.horizontal, ToolkitSpace.page)
                            .padding(.bottom, ToolkitSpace.section)
                        }
                        .refreshable { await resource.load(bypassCache: true) }
                    }
                }
            }
            .toolkitScreen()
            .navigationTitle(resource?.loaded?.value.player.summary.webName ?? knownName ?? "Player")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if resource == nil {
                let resource = Resource(appModel.playerRepository.player(id: playerId))
                self.resource = resource
                await resource.load()
            }
        }
    }
}

struct PlayerSheetContent: View {
    @Environment(AppModel.self) private var appModel
    let loaded: Loaded<PlayerSheet>

    private var sheet: PlayerSheet { loaded.value }
    private var player: PlayerSummary { sheet.player.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            header

            if let store = appModel.watch {
                WatchToggle(store: store, playerId: player.id, playerName: player.webName)
            }

            if showsAvailability {
                AvailabilitySection(availability: player.availability,
                                    newsAddedAt: sheet.player.newsAddedAt,
                                    source: freshness(.availability))
            }

            WorkloadSection(playerId: player.id)

            if !otherInsights.isEmpty {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    SectionLabel(text: "What's worth knowing")
                    ForEach(otherInsights) { insight in
                        InsightCard(insight: insight, player: nil)
                    }
                }
            }

            FixturesSection(fixtures: sheet.fixtures)

            if let prediction = sheet.pricePrediction {
                PriceSection(prediction: prediction, source: freshness(.pricePredictions))
            }

            MarketSection(market: sheet.market)

            if let elite = sheet.elite {
                EliteSection(elite: elite, source: freshness(.elite))
            }

            if let defcon = sheet.defcon {
                DefconSection(defcon: defcon)
            }

            StatsSection(player: sheet.player)

            PlayerMoreSection(playerId: player.id, name: player.webName)

            if let url = URL(string: sheet.links.web) {
                Link(destination: url) {
                    Label("More on fpltoolkit.co.uk", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(ToolkitSecondaryButtonStyle())
            }

            if let freshness = loaded.meta.freshness, !freshness.isEmpty {
                WhatWeCheckedSection(sources: freshness, savedAt: loaded.savedAt)
            }
        }
    }

    private var header: some View {
        HStack(spacing: ToolkitSpace.md) {
            PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo, size: 56, scalesWithText: false)
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                let fullName = [sheet.player.firstName, sheet.player.secondName].compactMap { $0 }.joined(separator: " ")
                if !fullName.isEmpty && fullName != player.webName {
                    Text(fullName)
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                }
                ClubLabel(
                    clubId: player.clubId,
                    text: [appModel.club(player.clubId)?.name, player.position.displayName, Format.price(player.price)]
                        .compactMap { $0 }.joined(separator: " · "),
                    logoSize: 16
                )
                .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
    }

    private var showsAvailability: Bool {
        player.availability.level != .ok || player.availability.news != nil
    }

    /// The availability note says the same as the availability card, so it isn't repeated.
    private var otherInsights: [TeamInsight] {
        showsAvailability ? sheet.insights.filter { $0.category != .availability } : sheet.insights
    }

    private func freshness(_ kind: FreshnessSource.Kind) -> FreshnessSource? {
        loaded.meta.freshness?.first { $0.source == kind }
    }
}

// MARK: - Sections

/// Watch / stop watching this player (a manual watch, kept even if he leaves your squad).
private struct WatchToggle: View {
    let store: WatchStore
    let playerId: Int
    let playerName: String

    var body: some View {
        let watch = store.watch
        let isManual = watch?.isManual(playerId) ?? false
        let inSquad = watch.map { $0.autoTrackSquad && ($0.squad?.playerIds.contains(playerId) ?? false) } ?? false
        Button {
            Task { await store.setWatched(!isManual, playerId: playerId) }
        } label: {
            HStack(spacing: ToolkitSpace.md) {
                Image(systemName: isManual ? "pin.fill" : (inSquad ? "bell.fill" : "bell"))
                    .font(.title3)
                    .foregroundStyle(isManual ? ToolkitColor.onAccent : ToolkitColor.link)
                    .frame(width: 44, height: 44)
                    .background(isManual ? ToolkitColor.accent : ToolkitColor.raised, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(isManual: isManual, inSquad: inSquad))
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(caption(isManual: isManual, inSquad: inSquad))
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if store.isUpdating { ProgressView() }
            }
            .padding(ToolkitSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.border))
        }
        .buttonStyle(.plain)
        .disabled(watch == nil || store.isUpdating)
        .accessibilityLabel(title(isManual: isManual, inSquad: inSquad))
        .accessibilityHint(caption(isManual: isManual, inSquad: inSquad))
        .task { await store.loadIfNeeded() }
        if let error = store.updateError {
            Text("Couldn't change this: \(error.title.prefix(1).lowercased() + error.title.dropFirst()).")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.error)
        }
    }

    private func title(isManual: Bool, inSquad: Bool) -> String {
        switch (isManual, inSquad) {
        case (true, true): "Kept if you sell him"
        case (true, false): "Watching"
        case (false, true): "Watching: in your squad"
        case (false, false): "Watch \(playerName)"
        }
    }

    private func caption(isManual: Bool, inSquad: Bool) -> String {
        switch (isManual, inSquad) {
        case (true, true): "Stays on your watch list after he leaves your squad. Tap to unpin."
        case (true, false): "On your watch list. Tap to stop watching."
        case (false, true): "Tap to keep watching him even after you sell him."
        case (false, false): "Add him to your watch list."
        }
    }
}

private struct AvailabilitySection: View {
    let availability: PlayerSummary.Availability
    let newsAddedAt: Date?
    let source: FreshnessSource?

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    HStack {
                        Text("Availability")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        Spacer()
                        levelPill
                    }
                    if let chance = availability.chanceNext {
                        HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.md) {
                            Text("\(chance)%")
                                .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(levelColor)
                            Text("chance of playing")
                                .font(.headline)
                                .foregroundStyle(ToolkitColor.primaryText)
                        }
                    }
                    if let news = availability.news {
                        Text(news)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(sourceLine)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
            if availability.chanceNext != nil {
                Text("This is FPL's published chance of playing, not a probability of starting.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
    }

    private var sourceLine: String {
        var parts = ["Source: FPL"]
        if let newsAddedAt { parts.append("news added \(Format.ago(newsAddedAt))") }
        if let asOf = source?.asOf { parts.append("checked \(Format.ago(asOf))") }
        return parts.joined(separator: " · ")
    }

    private var levelColor: Color {
        availability.level == .out ? ToolkitColor.error : ToolkitColor.warning
    }

    @ViewBuilder private var levelPill: some View {
        switch availability.level {
        case .out: Pill(text: "Out", foreground: ToolkitColor.error, fill: ToolkitColor.errorFill)
        case .doubt: Pill(text: "Flagged", foreground: ToolkitColor.warning, fill: ToolkitColor.warningFill)
        case .ok, .unknown: EmptyView()
        }
    }
}

private struct FixturesSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let fixtures: [FixtureDifficulty]

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            SectionLabel(text: title)
            if typeSize.isAccessibilitySize || fixtures.count > 5 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ToolkitSpace.sm) {
                        ForEach(Array(fixtures.enumerated()), id: \.offset) { _, fixture in
                            chip(fixture).frame(minWidth: 72)
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(fixtures.enumerated()), id: \.offset) { _, fixture in
                        chip(fixture).frame(maxWidth: .infinity)
                    }
                }
            }
            Text("Lower is easier. From 1 to 5, Market FDR model\(fixtures.contains { $0.xfdr?.source == .fpl } ? "; \u{201C}FPL\u{201D} marks FPL's own rating where the model has none" : "").")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
    }

    private var title: String {
        switch fixtures.lazy.compactMap(\.xfdr).first?.lens {
        case .attack: "Next fixtures · attack xFDR"
        case .cleanSheet: "Next fixtures · clean-sheet xFDR"
        default: "Next fixtures · xFDR"
        }
    }

    private func chip(_ fixture: FixtureDifficulty) -> some View {
        VStack(spacing: 4) {
            Text("GW\(fixture.gw)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
            ClubLabel(clubId: fixture.opponentClubId, text: opponent(fixture))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
            if let xfdr = fixture.xfdr {
                Text(xfdr.value.formatted(.number.precision(.fractionLength(1))))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
                if xfdr.source == .fpl {
                    Text("FPL")
                        .font(.caption2)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            } else {
                Text("–")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.vertical, ToolkitSpace.md)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ToolkitColor.border))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(fixture))
    }

    private func opponent(_ fixture: FixtureDifficulty) -> String {
        if fixture.blank { return "No game" }
        let name = appModel.club(fixture.opponentClubId)?.shortName ?? "TBC"
        guard let home = fixture.home else { return name }
        return "\(name) \(home ? "H" : "A")"
    }

    private func accessibilityText(_ fixture: FixtureDifficulty) -> String {
        if fixture.blank { return "Gameweek \(fixture.gw): no fixture" }
        let name = appModel.club(fixture.opponentClubId)?.name ?? "opponent to be confirmed"
        let venue = fixture.home.map { $0 ? "at home" : "away" } ?? ""
        let difficulty = fixture.xfdr.map { ", difficulty \($0.value.formatted(.number.precision(.fractionLength(1)))) out of 5" } ?? ""
        return "Gameweek \(fixture.gw): \(name) \(venue)\(difficulty)"
    }
}

private struct PriceSection: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let prediction: PlayerSheet.PricePrediction
    let source: FreshnessSource?

    private var headline: Double { prediction.tonightPct ?? prediction.progressPct }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    Text(prediction.tonightPct != nil ? "Tonight's price projection" : "Price-change progress")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.signed(headline))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(ToolkitColor.link)
                        Text("of the \(headline < 0 ? "fall" : "rise") threshold")
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Self.spoken(headline)) of the \(headline < 0 ? "fall" : "rise") threshold")
                    ThresholdBar(value: headline)
                    VStack(alignment: .leading, spacing: 4) {
                        if prediction.tonightPct != nil {
                            detail("Now", Self.signed(prediction.progressPct))
                        }
                        ForEach(prediction.projections.filter { $0.offset > 0 }, id: \.offset) { projection in
                            detail(projection.offset == 1 ? "Tomorrow night" : "In \(projection.offset) nights",
                                   Self.signed(projection.projectedPct))
                        }
                        if let rate = prediction.hourlyRate {
                            detail("Net transfers per hour", rate.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always())))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(projectionSummary)
                    if prediction.calibrating {
                        Label("The model is still calibrating for this player.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.warning)
                    }
                    if let locked = prediction.lockedUntil {
                        Label("Price locked until \(Format.deadline(locked)).", systemImage: "lock")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    Text(sourceLine)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
            Text("A projection, not a guarantee. It shows how far the player is towards a price change, not the probability of one.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
    }

    private var sourceLine: String {
        guard let source else { return "Projection" }
        if let asOf = source.asOf { return "Projection refreshed \(Format.ago(asOf))" }
        return "Projection · refresh time unknown"
    }

    private func detail(_ label: String, _ value: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout())
        return layout {
            Text(label).foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer() }
            Text(value).monospacedDigit().foregroundStyle(ToolkitColor.primaryText)
        }
        .font(.subheadline)
    }

    /// The projection rows read as one item: "Now: up 1 percent. Tomorrow night: up 1.3 percent. …"
    private var projectionSummary: String {
        var parts: [String] = []
        if prediction.tonightPct != nil { parts.append("Now: \(Self.spoken(prediction.progressPct))") }
        for p in prediction.projections where p.offset > 0 {
            parts.append("\(p.offset == 1 ? "Tomorrow night" : "In \(p.offset) nights"): \(Self.spoken(p.projectedPct))")
        }
        if let rate = prediction.hourlyRate {
            parts.append("Net transfers per hour: \(rate.formatted(.number.precision(.fractionLength(0))))")
        }
        return parts.joined(separator: ". ")
    }

    static func spoken(_ value: Double) -> String { Format.spokenPercent(value) }
    static func signed(_ value: Double) -> String { Format.signedPercent(value) }
}

/// Progress towards ±100 with a marker at the threshold. Presentation only: no rule is applied.
private struct ThresholdBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            let scale: Double = 120
            let fraction = min(abs(value), scale) / scale
            let thresholdX = proxy.size.width * (100 / scale)
            ZStack(alignment: .leading) {
                Capsule().fill(ToolkitColor.raised)
                Capsule().fill(ToolkitColor.accent)
                    .frame(width: max(proxy.size.width * fraction, 8))
                Rectangle()
                    .fill(ToolkitColor.primaryText)
                    .frame(width: 2, height: 22)
                    .offset(x: thresholdX - 1)
            }
        }
        .frame(height: 12)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

private struct MarketSection: View {
    let market: PlayerSheet.Market

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            SectionLabel(text: "Market")
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    HStack(alignment: .firstTextBaseline) {
                        if let selected = market.selectedByPct {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(selected.formatted(.number.precision(.fractionLength(1))))%")
                                    .font(.title2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(ToolkitColor.primaryText)
                                Text("selected by")
                                    .font(.footnote)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                        }
                        Spacer()
                        if let change = market.ownershipChange7d {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(change.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))) pts")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(ToolkitColor.primaryText)
                                Text("last 7 days")
                                    .font(.footnote)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                        }
                    }
                    let points = market.ownershipTrend7d.compactMap { point in
                        point.selectedByPct.map { (date: point.date, pct: $0) }
                    }
                    if points.count >= 2 {
                        Chart(points, id: \.date) { point in
                            LineMark(x: .value("Day", point.date), y: .value("Selected by %", point.pct))
                                .foregroundStyle(ToolkitColor.accent)
                                .interpolationMethod(.monotone)
                        }
                        .chartXAxis(.hidden)
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxis {
                            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                                AxisGridLine().foregroundStyle(ToolkitColor.border)
                                AxisValueLabel().foregroundStyle(ToolkitColor.secondaryText)
                            }
                        }
                        .frame(height: 90)
                        .accessibilityLabel("Ownership over the last \(points.count) days")
                    }
                    Divider().overlay(ToolkitColor.border)
                    HStack {
                        Label("\(market.transfersInEvent.formatted()) in", systemImage: "arrow.down.left")
                        Spacer()
                        Label("\(market.transfersOutEvent.formatted()) out", systemImage: "arrow.up.right")
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(ToolkitColor.secondaryText)
                    Text("Transfers this gameweek, across all managers.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
    }
}

private struct EliteSection: View {
    let elite: PlayerSheet.Elite
    let source: FreshnessSource?

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            SectionLabel(text: "Top \(elite.cohortSize) managers")
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    Grid(alignment: .leading, horizontalSpacing: ToolkitSpace.lg, verticalSpacing: ToolkitSpace.md) {
                        GridRow {
                            stat(elite.ownedPct, "own him")
                            stat(elite.captainPct, "captained him")
                        }
                        GridRow {
                            stat(elite.boughtPct, "bought him")
                            stat(elite.soldPct, "sold him")
                        }
                    }
                    Text(source?.label ?? "Top \(elite.cohortSize) cohort, published GW\(elite.gw)")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    Text("Moves made for GW\(elite.gw). Nobody can see their private choices for the next deadline.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
    }

    private func stat(_ value: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value.formatted(.number.precision(.fractionLength(0...1))))%")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
            Text(label)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct DefconSection: View {
    let defcon: PlayerSheet.Defcon

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            SectionLabel(text: "Defensive contributions")
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.md) {
                        Text((defcon.hitRateStarts * 100).formatted(.number.precision(.fractionLength(0))) + "%")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(ToolkitColor.link)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("hit rate in starts")
                                .font(.headline)
                                .foregroundStyle(ToolkitColor.primaryText)
                            Text("\(defcon.hits) \(defcon.hits == 1 ? "hit" : "hits") in \(defcon.starts) \(defcon.starts == 1 ? "start" : "starts")")
                                .font(.subheadline)
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                    }
                    Divider().overlay(ToolkitColor.border)
                    HStack {
                        Text("Per 90: \(defcon.dcPer90.formatted(.number.precision(.fractionLength(1))))")
                        Spacer()
                        Text("Threshold: \(defcon.threshold) a match")
                    }
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
    }
}

private struct StatsSection: View {
    let player: PlayerSheet.Player

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            SectionLabel(text: "Season so far")
            ToolkitCard {
                Grid(alignment: .leading, horizontalSpacing: ToolkitSpace.lg, verticalSpacing: ToolkitSpace.md) {
                    GridRow {
                        stat(String(player.totalPoints), "points")
                        stat(player.minutes.formatted(), "minutes")
                    }
                    GridRow {
                        stat(player.form.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–", "form")
                        stat(player.pointsPerGame.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–", "points per game")
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
            Text(label)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension Position {
    var displayName: String {
        switch self {
        case .gk: "Goalkeeper"
        case .def: "Defender"
        case .mid: "Midfielder"
        case .fwd: "Forward"
        case .unknown: "Player"
        }
    }
}

#if DEBUG
#Preview("Palmer") {
    NavigationStack {
        ScrollView {
            PlayerSheetContent(loaded: PreviewFixtures.load("player-palmer", as: PlayerSheet.self))
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Palmer")
    }
    .environment(AppModel())
}

#Preview("Haaland") {
    NavigationStack {
        ScrollView {
            PlayerSheetContent(loaded: PreviewFixtures.load("player-haaland", as: PlayerSheet.self))
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Haaland")
    }
    .environment(AppModel())
}
#endif
