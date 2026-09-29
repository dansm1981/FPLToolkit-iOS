import SwiftUI

/// Identifies which player to open.
struct PlayerRef: Identifiable, Hashable {
    let id: Int
    /// Opened from a notification: the page says the facts may have moved on since.
    var fromAlert = false
    /// Why this player matters where it was opened, e.g. "In your GW5 squad".
    var context: String?
}

/// The player detail as a sheet, for places that aren't in a navigation stack (a notification or
/// a deep link). Everywhere else pushes `PlayerDetailView`.
struct PlayerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let playerId: Int
    var knownName: String?
    var fromAlert = false

    var body: some View {
        NavigationStack {
            PlayerDetailView(playerId: playerId, knownName: knownName, fromAlert: fromAlert)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

enum PlayerDetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview", stats = "Stats", fixtures = "Fixtures"
    var id: String { rawValue }
}

/// S10–S18 (design pack pp.13–14): one shared player page. The overview answers the football
/// question (identity, price, headline figures, next fixtures); depth lives one tap away.
struct PlayerDetailView: View {
    @Environment(AppModel.self) private var appModel
    let playerId: Int
    var knownName: String?
    var fromAlert = false
    /// Why this player matters here, e.g. "In your GW5 squad".
    var context: String?
    @State private var resource: Resource<PlayerSheet>?
    @State private var workload: Resource<WorkloadPage>?
    @State private var tab: PlayerDetailTab = .overview

    var body: some View {
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
                        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                            SavedDataBanner(resource: resource)
                            if fromAlert {
                                InlineNotice(text: "You opened an alert. This is the latest information, which may have changed since it was sent.",
                                             systemImage: "bell.badge")
                            }
                            PlayerDetailContent(loaded: loaded, workload: workload?.loaded?.value.workload(playerId),
                                                context: context, tab: $tab)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, ToolkitSpace.section)
                    }
                    .refreshable { await resource.load(bypassCache: true) }
                }
            }
        }
        .toolkitScreen()
        .navigationTitle(resource?.loaded?.value.player.summary.webName ?? knownName ?? "Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let sheet = resource?.loaded?.value {
                ToolbarItem(placement: .topBarTrailing) {
                    PlayerMoreMenu(player: sheet.player.summary, web: URL(string: sheet.links.web))
                }
            }
        }
        .task {
            if resource == nil {
                let resource = Resource(appModel.playerRepository.player(id: playerId))
                self.resource = resource
                if workload == nil {
                    let workload = Resource(appModel.researchRepository.workload(playerIds: [playerId]))
                    self.workload = workload
                    Task { await workload.load() }
                }
                await resource.load()
            }
        }
    }
}

/// "⋯": follow and the website page.
private struct PlayerMoreMenu: View {
    @Environment(AppModel.self) private var appModel
    let player: PlayerSummary
    let web: URL?

    var body: some View {
        Menu {
            if let store = appModel.watch {
                let manual = store.watch?.isManual(player.id) ?? false
                Button {
                    Task { await store.setWatched(!manual, playerId: player.id) }
                } label: {
                    Label(manual ? "Stop watching" : "Watch \(player.webName)", systemImage: manual ? "bell.slash" : "bell")
                }
            }
            if let web {
                Link(destination: web) {
                    Label("Open on fpltoolkit.co.uk", systemImage: "arrow.up.right.square")
                }
            }
        } label: {
            Label("More options", systemImage: "ellipsis")
        }
    }
}

struct PlayerDetailContent: View {
    @Environment(AppModel.self) private var appModel
    let loaded: Loaded<PlayerSheet>
    let workload: Workload?
    var context: String?
    @Binding var tab: PlayerDetailTab
    @State private var info: PlayerInfo?

    private var sheet: PlayerSheet { loaded.value }
    private var player: PlayerSummary { sheet.player.summary }

    enum PlayerInfo: String, Identifiable {
        case price, fdr, elite, workload
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            header
            if player.availability.level == .doubt || player.availability.level == .out {
                availabilityCard
            }
            Picker("Section", selection: $tab) {
                ForEach(PlayerDetailTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch tab {
            case .overview: overview
            case .stats: stats
            case .fixtures: fixtures
            }
        }
        .sheet(item: $info) { which in
            infoSheet(which)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: ToolkitSpace.md) {
            PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo, size: 64, scalesWithText: false)
            VStack(alignment: .leading, spacing: 5) {
                Text(fullName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ClubLabel(clubId: player.clubId,
                          text: [appModel.club(player.clubId)?.name, player.position.displayName].compactMap { $0 }.joined(separator: " · "),
                          logoSize: 15)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                HStack(spacing: ToolkitSpace.sm) {
                    Text(Format.price(player.price))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                    if let context { Tag(text: context) }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var fullName: String {
        let name = [sheet.player.firstName, sheet.player.secondName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? player.webName : name
    }

    private var availabilityCard: some View {
        AttentionCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: ToolkitSpace.md) {
                    Image(systemName: player.availability.level == .out ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ToolkitColor.warning)
                        .frame(width: 35, height: 35)
                        .background(ToolkitColor.raised, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.availability.level == .out ? "\(player.webName) is out" : "\(player.webName) is a doubt")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(availabilityLine)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                if let news = player.availability.news {
                    Text(news)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var availabilityLine: String {
        var parts: [String] = []
        if let chance = player.availability.chanceNext { parts.append("\(chance)% chance of playing") }
        parts.append("FPL flag")
        if let added = sheet.player.newsAddedAt { parts.append("added \(Format.ago(added))") }
        return parts.joined(separator: " · ")
    }

    // MARK: Overview

    @ViewBuilder private var overview: some View {
        StatStrip(items: [
            .init(value: String(sheet.player.totalPoints), label: "Season points"),
            .init(value: sheet.player.pointsPerGame.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–", label: "Pts / game"),
            .init(value: sheet.player.minutes.formatted(), label: "FPL minutes"),
        ])
        .padding(.vertical, 6)

        SectionHeader(title: "Next fixtures", actionTitle: "Full run") { tab = .fixtures }
        if let label = variantLabel {
            Button { info = .fdr } label: {
                HStack(spacing: 4) {
                    Text(label)
                    Image(systemName: "info.circle").imageScale(.small)
                }
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityHint("What fixture difficulty means")
        }
        FixtureRunStrip(cells: Array(fixtureCells.prefix(5)))

        if let prediction = sheet.pricePrediction {
            priceWatch(prediction)
        }

        let links = overviewLinks
        if !links.isEmpty {
            CardGroup {
                ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                    if index > 0 { RowDivider() }
                    LinkRow(title: link.title, detail: link.detail, systemImage: link.systemImage, action: link.action)
                }
            }
        }

        let worth = sheet.insights.filter { [.market, .setpiece, .other].contains($0.category) }
        if !worth.isEmpty {
            SectionHeader(title: "Worth knowing")
            ForEach(worth) { insight in
                InsightCard(insight: insight, player: nil)
            }
        }

        if appModel.watch != nil {
            WatchButton(player: player)
                .padding(.top, 4)
        }
    }

    private var variantLabel: String? {
        sheet.fixtures.lazy.compactMap(\.xfdr).first?.modelLabel
    }

    private var fixtureCells: [FixtureCellModel] {
        let byGw = Dictionary(grouping: sheet.fixtures, by: \.gw)
        let model = variantLabel ?? "xFDR"
        return byGw.keys.sorted().map { gw in
            FixtureCellModel(gw: gw, fixtures: byGw[gw] ?? [], club: appModel.club, model: model, subject: player.webName)
        }
    }

    private func priceWatch(_ prediction: PlayerSheet.PricePrediction) -> some View {
        let value = prediction.tonightPct ?? prediction.progressPct
        let rising = value >= 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Price watch")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                Spacer()
                Button { info = .price } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ToolkitColor.link)
                .accessibilityLabel("What price threshold progress means")
            }
            HStack {
                Text(rising ? "Rise threshold progress" : "Fall threshold progress")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                Spacer()
                Text(abs(value).formatted(.number.precision(.fractionLength(0))) + "%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ToolkitColor.accent)
            }
            .accessibilityElement(children: .combine)
            ProgressLine(fraction: abs(value) / 100, tint: rising ? ToolkitColor.accent : ToolkitColor.error)
            Text(prediction.calibrating ? "Model estimate, not a probability. Still calibrating for this player." : "Model estimate, not a probability")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
            if let locked = prediction.lockedUntil {
                Label("Price locked until \(Format.deadline(locked)).", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .padding(.horizontal, 17)
        .padding(.bottom, 15)
        .padding(.top, 6)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private struct OverviewLink: Identifiable {
        let title: String
        let detail: String?
        let systemImage: String
        let action: () -> Void
        var id: String { title }
    }

    private var overviewLinks: [OverviewLink] {
        var links: [OverviewLink] = []
        if let workload, workload.lastMatch != nil {
            links.append(OverviewLink(title: "\(workload.last14) minutes in 14 days", detail: "All competitions",
                                      systemImage: "clock") { info = .workload })
        }
        if let elite = sheet.elite {
            let title = elite.boughtPct >= 1
                ? "\(Self.percent(elite.boughtPct)) of the top \(elite.cohortSize) bought him"
                : "Owned by \(Self.percent(elite.ownedPct)) of the top \(elite.cohortSize)"
            links.append(OverviewLink(title: title, detail: "GW\(elite.gw) · top \(elite.cohortSize) managers",
                                      systemImage: "trophy") { info = .elite })
        }
        return links
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    // MARK: Stats

    @ViewBuilder private var stats: some View {
        StatStrip(items: [
            .init(value: String(sheet.player.totalPoints), label: "Points"),
            .init(value: sheet.player.form.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–", label: "Form"),
            .init(value: sheet.player.minutes.formatted(), label: "Minutes"),
        ])
        .padding(.vertical, 6)
        SectionHeader(title: "In depth")
        CardGroup {
            ForEach(Array(PlayerTab.allCases.enumerated()), id: \.element) { index, page in
                if index > 0 { RowDivider() }
                NavigationLink {
                    PlayerTabDestination(playerId: player.id, name: player.webName, tab: page)
                } label: {
                    LinkRowLabel(title: page.title, detail: statsDetail(page), systemImage: page.systemImage)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statsDetail(_ page: PlayerTab) -> String {
        switch page {
        case .history: return "Points and match-by-match stats"
        case .form: return "Rolling windows of form"
        case .underlying: return "Totals and per 90"
        case .fixtures: return "Returns by fixture difficulty"
        case .price:
            let owned = sheet.market.selectedByPct.map { "\(Self.percent($0)) owned · " } ?? ""
            return owned + Format.price(player.price)
        case .defensive:
            if let d = sheet.defcon { return "\(d.hits) / \(d.starts) starts hit the threshold" }
            return "Defensive contributions match by match"
        case .compare: return "Percentile ranks and alternatives"
        }
    }

    // MARK: Fixtures

    @ViewBuilder private var fixtures: some View {
        HStack {
            Text("Next \(min(fixtureCells.count, 5)) fixtures")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
            Spacer()
            if let label = variantLabel {
                Button { info = .fdr } label: {
                    HStack(spacing: 4) {
                        Text(label)
                        Image(systemName: "info.circle").imageScale(.small)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
            }
        }
        FixtureRunStrip(cells: Array(fixtureCells.prefix(5)))
        VStack(spacing: 0) {
            ForEach(Array(sheet.fixtures.enumerated()), id: \.offset) { index, fixture in
                if index > 0 { Divider().overlay(ToolkitColor.border) }
                fixtureRow(fixture)
            }
        }
        .padding(.horizontal, 15)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        CardGroup {
            NavigationLink {
                PlayerTabDestination(playerId: player.id, name: player.webName, tab: .fixtures)
            } label: {
                LinkRowLabel(title: "Returns by difficulty", detail: "Past FPL points against easier and harder fixtures",
                             systemImage: "chart.bar")
            }
            .buttonStyle(.plain)
        }
    }

    private func fixtureRow(_ fixture: FixtureDifficulty) -> some View {
        let opponent = appModel.club(fixture.opponentClubId)
        return HStack(spacing: ToolkitSpace.md) {
            Text("GW\(fixture.gw)")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .frame(width: 44, alignment: .leading)
            if fixture.blank {
                Text("No fixture")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                Spacer()
            } else {
                ClubLogo(clubId: fixture.opponentClubId, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(opponent?.name ?? "To be confirmed")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text([fixture.home.map { $0 ? "Home" : "Away" }, fixture.kickoff.map { Format.deadline($0) }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                Spacer()
                if let xfdr = fixture.xfdr {
                    let tone = DifficultyTone(band: xfdr.band)
                    Text(xfdr.display)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(tone.text)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(tone.fill, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("–").foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fixtureSpoken(fixture))
    }

    private func fixtureSpoken(_ fixture: FixtureDifficulty) -> String {
        if fixture.blank { return "Gameweek \(fixture.gw): no fixture" }
        let name = appModel.club(fixture.opponentClubId)?.name ?? "opponent to be confirmed"
        let venue = fixture.home.map { $0 ? "at home" : "away" } ?? ""
        let difficulty = fixture.xfdr.map { ", \($0.modelLabel) \($0.display)" } ?? ", difficulty unavailable"
        return "Gameweek \(fixture.gw): \(name) \(venue)\(difficulty)"
    }

    // MARK: Explanations

    @ViewBuilder private func infoSheet(_ which: PlayerInfo) -> some View {
        switch which {
        case .price:
            InfoSheet(title: "Price threshold progress", message: priceMessage)
        case .fdr:
            InfoSheet(title: "Fixture difficulty", message: TeamText.fdrMessage)
        case .elite:
            InfoSheet(title: "Top \(sheet.elite?.cohortSize ?? 100) managers", message: eliteMessage)
        case .workload:
            NavigationStack {
                ScrollView {
                    WorkloadSection(playerId: player.id)
                        .padding(.horizontal, ToolkitSpace.page)
                }
                .toolkitScreen()
                .navigationTitle("Minutes and rest")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { info = nil } }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var priceMessage: String {
        guard let p = sheet.pricePrediction else { return "" }
        let value = p.tonightPct ?? p.progressPct
        var text = "\(abs(value).formatted(.number.precision(.fractionLength(0...1))))% is progress towards the model's estimated \(value >= 0 ? "rise" : "fall") threshold. It isn't the probability of a price change, and the model can be wrong, including after the threshold is crossed."
        var lines: [String] = []
        if p.tonightPct != nil { lines.append("Now: \(Format.signedPercent(p.progressPct))") }
        for projection in p.projections where projection.offset > 0 {
            lines.append("\(projection.offset == 1 ? "Tomorrow night" : "In \(projection.offset) nights"): \(Format.signedPercent(projection.projectedPct))")
        }
        if let rate = p.hourlyRate {
            lines.append("Net transfers per hour: \(rate.formatted(.number.precision(.fractionLength(0)).sign(strategy: .always())))")
        }
        if !lines.isEmpty { text += "\n\n" + lines.joined(separator: "\n") }
        return text
    }

    private var eliteMessage: String {
        guard let e = sheet.elite else { return "" }
        return """
        Owned by \(Self.percent(e.ownedPct)), captained by \(Self.percent(e.captainPct)), bought by \(Self.percent(e.boughtPct)) and sold by \(Self.percent(e.soldPct)) of the top \(e.cohortSize) managers in GW\(e.gw).

        These are the moves they made for GW\(e.gw). Nobody can see their choices for the next deadline until it passes.
        """
    }
}

/// Watch / stop watching this player (a manual watch, kept even if he leaves your squad).
private struct WatchButton: View {
    @Environment(AppModel.self) private var appModel
    let player: PlayerSummary

    var body: some View {
        if let store = appModel.watch {
            let manual = store.watch?.isManual(player.id) ?? false
            let inSquad = store.watch.map { $0.autoTrackSquad && ($0.squad?.playerIds.contains(player.id) ?? false) } ?? false
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await store.setWatched(!manual, playerId: player.id) }
                } label: {
                    Label(manual ? "Watching" : inSquad ? "Keep watching after a sale" : "Watch",
                          systemImage: manual ? "checkmark" : "bell")
                }
                .buttonStyle(ToolkitSecondaryButtonStyle())
                .disabled(store.watch == nil || store.isUpdating)
                .accessibilityHint(manual ? "Stops watching this player"
                                   : inSquad ? "You're already watching him as part of your squad; this keeps him if you sell him"
                                   : "Adds him to your watch list")
                if let error = store.updateError {
                    Text("Couldn't change this: \(error.title.prefix(1).lowercased() + error.title.dropFirst()).")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.error)
                }
            }
            .task { await store.loadIfNeeded() }
        }
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
            PlayerDetailContent(loaded: PreviewFixtures.load("player-palmer", as: PlayerSheet.self), workload: nil,
                                tab: .constant(.overview))
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("Palmer")
    }
    .environment(AppModel())
}
#endif
