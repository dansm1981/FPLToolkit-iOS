import SwiftUI

/// Your minutes forecasts on the projections list: player id → chance of 60+ minutes, whole
/// percent. Kept while the screen is open, as the website keeps them on its page (Dan, 4 Oct).
@MainActor
@Observable
final class ProjectionTweaks {
    private(set) var minutes: [Int: Int] = [:]
    var allNailed = false

    /// Nil goes back to the model. Changing one player turns "All nailed" off, as on the site.
    func set(_ playerId: Int, to pct: Int?) {
        allNailed = false
        minutes[playerId] = pct
    }

    func reset() { minutes = [:] }
}

/// Which player's minutes forecast the sheet is changing.
struct ProjectionMinutesTarget: Identifiable {
    let playerId: Int
    let name: String
    let gameweek: Int
    let modelPct: Int?
    var id: Int { playerId }
}

/// Projections (happy-backend-pal#74; redesigned 5 Oct 2026 from Dan's concept "Results first,
/// depth on demand"): a readable ranking list, with the run's details behind ⓘ, three controls,
/// removable filter chips, and each player's projected points, range and 10+ chance. A player opens
/// the forecast, where your playing-time forecast is set.
struct ProjectionsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var tweaks = ProjectionTweaks()
    @State private var position: Position?
    @State private var horizon = 1
    @State private var search = ""
    @State private var startersOnly = true
    @State private var sort: ProjectionSort = .mean
    @State private var ascending = false
    @State private var table = ResearchTable<Projections>()
    @State private var showingInfo = false
    @State private var showingFilters = false

    private struct Key: Hashable {
        let horizon: Int, position: Position?, search: String, startersOnly: Bool, allNailed: Bool
        let minutes: [Int: Int], sort: ProjectionSort, ascending: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let run = latest?.run {
                    statusLine(run)
                }
                controls
                ResearchTableView(table: table, caption: "Loading projections…", retry: reload) { data in
                    if data.run == nil {
                        RivalNote(text: "No projection run yet. Once the projection sync has run, the latest one shows here.")
                    } else {
                        list(data)
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Projections")
        .navigationBarTitleDisplayMode(.large)
        .environment(tweaks)
        .sheet(isPresented: $showingInfo) {
            if let latest, let run = latest.run {
                ProjectionRunInfoSheet(run: run, knew: latest.knew)
            }
        }
        .sheet(isPresented: $showingFilters) {
            ProjectionFiltersSheet(sort: $sort, ascending: $ascending, startersOnly: $startersOnly,
                                   tweaks: tweaks, horizon: horizon)
        }
        .onChange(of: horizon) {
            // Blank and FPL ep are one-gameweek columns, as on the website.
            if horizon > 1 && sort.gameweekOnly { sort = .mean }
        }
        .task(id: key) {
            // A short pause while typing a search.
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private var key: Key {
        Key(horizon: horizon, position: position, search: search, startersOnly: startersOnly, allNailed: tweaks.allNailed,
            minutes: tweaks.minutes, sort: sort, ascending: ascending)
    }

    /// The table on screen, or the last one while new options load.
    private var latest: Projections? {
        table.current?.loaded?.value ?? table.previous?.value
    }

    // MARK: Header and controls

    /// "Odds in · updated 12:13 ⓘ": the run in one line; the rest is behind ⓘ.
    private func statusLine(_ run: ProjectionRun) -> some View {
        Button { showingInfo = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ProjectionText.status(run))
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.link)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ProjectionText.status(run))
        .accessibilityHint("Shows what this run is based on and how to read the numbers")
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: ToolkitSpace.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ToolkitColor.secondaryText)
                .accessibilityHidden(true)
            TextField("Search players", text: $search)
                .textFieldStyle(.plain)
                .submitLabel(.search)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 12))
        if let data = latest, data.run != nil {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                Menu {
                    Picker("Gameweeks", selection: $horizon) {
                        ForEach(data.horizons) { Text($0.label).tag($0.value) }
                    }
                } label: {
                    FilterChipLabel(text: horizonLabel(data), active: false, menu: true)
                }
                .accessibilityLabel("Gameweeks: \(horizonLabel(data))")
                Menu {
                    Picker("Players", selection: $position) {
                        Text("All players").tag(Position?.none)
                        ForEach([Position.gk, .def, .mid, .fwd], id: \.self) { Text(Self.plural($0)).tag(Position?.some($0)) }
                    }
                } label: {
                    FilterChipLabel(text: position.map(Self.plural) ?? "All players", active: false, menu: true)
                }
                .accessibilityLabel("Players: \(position.map(Self.plural) ?? "all")")
                Button { showingFilters = true } label: {
                    Label("Filters", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Sort, likely starters, all nailed and your minutes")
            }
            activeChips
        }
    }

    /// The filters in force, each removable.
    @ViewBuilder private var activeChips: some View {
        let sorted = sort != .mean || ascending
        let tweakCount = tweaks.allNailed ? 0 : tweaks.minutes.count
        if startersOnly || tweaks.allNailed || sorted || tweakCount > 0 {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                if startersOnly { removable("Likely starters") { startersOnly = false } }
                if tweaks.allNailed { removable("All nailed") { tweaks.allNailed = false } }
                if sorted {
                    removable("By \(sortLabel(sort).lowercased())\(ascending ? ", lowest first" : "")") {
                        sort = .mean
                        ascending = false
                    }
                }
                if tweakCount > 0 {
                    removable("Your minutes · \(tweakCount)") { tweaks.reset() }
                }
            }
        }
    }

    private func removable(_ text: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                Text(text)
                Image(systemName: "xmark").font(.caption.weight(.bold)).accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ToolkitColor.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(ToolkitColor.goldTag, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove filter: \(text)")
    }

    private func horizonLabel(_ data: Projections) -> String {
        if horizon == 1 { return data.horizons.first?.label ?? "GW\(data.run?.fromGw ?? 0)" }
        guard let run = data.run else { return "Next \(horizon)" }
        return "GW\(run.fromGw)–\(run.fromGw + horizon - 1)"
    }

    private func sortLabel(_ s: ProjectionSort) -> String {
        s == .haul ? (horizon > 1 ? "≥1 haul" : "10+ pts") : s == .mean ? "Projected pts" : s.label
    }

    nonisolated static func plural(_ p: Position) -> String {
        switch p {
        case .gk: "Goalkeepers"
        case .def: "Defenders"
        case .mid: "Midfielders"
        case .fwd: "Forwards"
        case .unknown: "Other players"
        }
    }

    // MARK: List

    @ViewBuilder
    private func list(_ data: Projections) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PLAYER / RANGE")
            Spacer(minLength: ToolkitSpace.sm)
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(ProjectionSort.allCases.filter { horizon == 1 || !$0.gameweekOnly }) {
                        Text(sortLabel($0)).tag($0)
                    }
                }
                Picker("Order", selection: $ascending) {
                    Text("Highest first").tag(false)
                    Text("Lowest first").tag(true)
                }
            } label: {
                Text("\(sortLabel(sort).uppercased()) \(ascending ? "↑" : "↓")")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Sorted by \(sortLabel(sort)), \(ascending ? "lowest" : "highest") first")
        }
        .font(.caption.weight(.semibold))
        .tracking(0.6)
        .foregroundStyle(ToolkitColor.secondaryText)
        if data.rows.isEmpty {
            RivalNote(text: "No players match.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(data.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    playerRow(row, data: data)
                }
            }
        }
        Text("\(data.total) player\(data.total == 1 ? "" : "s")\(data.total > data.rows.count ? ", showing the top \(data.rows.count)" : ""). Open a player for the forecast and to adjust his playing time.")
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func playerRow(_ r: Projections.Row, data: Projections) -> some View {
        if let summary = data.player(r.playerId) {
            NavigationLink {
                ProjectionPlayerView(playerId: r.playerId, knownName: summary.webName, modelSixtyPct: r.modelSixtyPct)
                    .environment(tweaks)
            } label: {
                ProjectionRow(row: r, player: summary, horizon: data.horizon, extra: extra(r, horizon: data.horizon))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(r, name: summary.webName, horizon: data.horizon))
            // One element for the row, still a button (ignoring the children drops the trait).
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the forecast")
        }
    }

    /// The bottom-right figure: the 10+ chance, or what the list is sorted by when that's not
    /// already on the row.
    private func extra(_ r: Projections.Row, horizon: Int) -> String {
        switch sort {
        case .mean, .haul, .price: "\(horizon > 1 ? "≥1 haul" : "10+ pts") \(ProjectionText.pct(r.haulPct))"
        case .median: "Median \(r.median)"
        case .mode: "Mode \(r.mode)"
        case .p90: "P90 \(r.p90)"
        case .blank: "Blank \(ProjectionText.pct(r.blankPct))"
        case .sixty: "60+ \(ProjectionText.pct(r.sixtyPct))"
        case .fplEp: "FPL ep \(r.fplEp.map(ProjectionText.one) ?? "—")"
        }
    }

    private func spoken(_ r: Projections.Row, name: String, horizon: Int) -> String {
        var parts = [
            name,
            "Projected \(ProjectionText.one(r.mean)) points, 80% range \(r.p10) to \(r.p90)",
            horizon > 1 ? "Chance of at least one 10 point gameweek \(ProjectionText.pct(r.haulPct))" : "Chance of 10 or more \(ProjectionText.pct(r.haulPct))",
        ]
        if r.adjusted { parts.append("\(ProjectionText.pct(r.sixtyPct)) chance of 60 minutes, your forecast") }
        if ![.mean, .haul, .price].contains(sort) { parts.append(extra(r, horizon: horizon)) }
        parts.append("Price \(Format.price(r.price))")
        return parts.joined(separator: ". ")
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.researchRepository.projections(
            horizon: horizon, position: position, search: search, startersOnly: startersOnly,
            allNailed: tweaks.allNailed, minutes: tweaks.minutes, sort: sort, ascending: ascending))
    }
}

/// One ranked player (concept 03): name and price, the range bar with its ends, projected points
/// large, and one more figure.
struct ProjectionRow: View {
    @Environment(AppModel.self) private var appModel
    let row: Projections.Row
    let player: PlayerSummary
    let horizon: Int
    let extra: String

    var body: some View {
        HStack(alignment: .top, spacing: ToolkitSpace.md) {
            PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo, size: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(player.webName)
                                .font(.headline)
                                .foregroundStyle(ToolkitColor.primaryText)
                            AvailabilityBadge(availability: player.availability)
                        }
                        Text(Format.unbroken(meta))
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ToolkitSpace.sm)
                    Text(ProjectionText.one(row.mean))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                ProjectionRangeBar(p10: row.p10, p90: row.p90, mean: row.mean, horizon: horizon)
                HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm) {
                    Text(rangeLine)
                        .foregroundStyle(row.adjusted ? ToolkitColor.accent : ToolkitColor.secondaryText)
                    Spacer(minLength: ToolkitSpace.sm)
                    Text(extra)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .font(.footnote.monospacedDigit())
            }
        }
        .padding(.vertical, ToolkitSpace.md)
        .contentShape(Rectangle())
    }

    /// "MUN · MID · £11.9m".
    private var meta: String {
        [appModel.club(player.clubId)?.shortName, player.position.rawValue, Format.price(player.price)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// "1–12 pts", and your minutes when you've set them.
    private var rangeLine: String {
        let range = "\(row.p10)–\(row.p90) pts"
        return row.adjusted ? "\(range) · your 60+ \(ProjectionText.pct(row.sixtyPct))" : range
    }
}

// MARK: - Run

/// The website's four tiles: stage, gameweeks, match context and the run.
struct ProjectionRunCard: View {
    let run: ProjectionRun

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            HStack(spacing: ToolkitSpace.sm) {
                Pill(text: "Beta", foreground: ToolkitColor.warning, fill: ToolkitColor.warningFill)
                ProjectionStagePill(stage: run.stage, tone: .card)
            }
            Text("Every player's points for the coming gameweeks as a distribution rather than one number: the median, the most likely score, the P10 to P90 range and the chance of a haul.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            FigureGrid(items: [
                .init(label: "Stage", value: run.stage.label,
                      spoken: [run.stage.label, ProjectionText.deadline(run)].compactMap { $0 }.joined(separator: ", ")),
                .init(label: "Gameweeks", value: "GW\(run.fromGw)–\(run.toGw)",
                      spoken: "Gameweeks \(run.fromGw) to \(run.toGw)"),
                .init(label: "Match context", value: run.context.market > 0 ? "Market FDR" : "Fitted model"),
                .init(label: "Run", value: run.finishedAt.map(Format.deadline) ?? "—"),
            ])
            Text(Format.unbroken(footnote))
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: String {
        [
            ProjectionText.deadline(run),
            "\(run.sims.formatted()) simulations per player",
            run.context.market > 0 ? "\(run.context.market) team-fixtures from odds" : "This season's team xG",
            "Model \(run.modelVersion)",
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The stage as the website colours it: press conferences and the deadline good, odds amber.
/// The run card and the breakdown use the site's two slightly different schemes.
struct ProjectionStagePill: View {
    enum Tone { case card, breakdown }
    let stage: ProjectionRun.Stage
    let tone: Tone

    var body: some View {
        let good = tone == .card ? ["deadline", "pressconf"].contains(stage.key) : !["early", "odds"].contains(stage.key)
        if stage.key == "odds" {
            Pill(text: stage.label, foreground: ToolkitColor.warning, fill: ToolkitColor.warningFill)
        } else if good {
            Pill(text: stage.label, foreground: ToolkitColor.positive, fill: ToolkitColor.positiveFill)
        } else {
            Pill(text: stage.label, foreground: ToolkitColor.secondaryText, fill: ToolkitColor.raised)
        }
    }
}

/// ⓘ on the list: the run card, what the run knew and how to read the numbers, in one sheet.
struct ProjectionRunInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let run: ProjectionRun
    let knew: Projections.Knew?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    ProjectionRunCard(run: run)
                    SectionHeader(title: "What this run knew")
                    ProjectionKnewContent(run: run, knew: knew)
                    SectionHeader(title: "Reading the numbers")
                    ProjectionReadingContent()
                }
                .padding(.horizontal, ToolkitSpace.page)
                .padding(.bottom, ToolkitSpace.section)
            }
            .toolkitScreen()
            .navigationTitle("About these projections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Each input's status, when it was observed, and the run's notes.
struct ProjectionKnewContent: View {
    let run: ProjectionRun
    let knew: Projections.Knew?

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            if let note = run.stage.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let knew, !knew.inputs.isEmpty {
                CardGroup {
                    ForEach(Array(knew.inputs.enumerated()), id: \.element.id) { index, input in
                        if index > 0 { RowDivider() }
                        inputRow(input)
                    }
                }
            }
            if let knew, !knew.notes.isEmpty {
                BulletList(items: knew.notes)
            }
        }
    }

    private func inputRow(_ input: Projections.Knew.Input) -> some View {
        NameFigureRow {
            Text(input.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
        } details: {
            let facts = [input.observedAt.map { "Observed \(Format.deadline($0))" }, input.detail].compactMap { $0 }
            if !facts.isEmpty {
                Text(Format.unbroken(facts.joined(separator: " · ")))
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        } figure: {
            statusTag(input.status)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusTag(_ status: Projections.Knew.Input.Status) -> some View {
        switch status {
        case .available: Tag(text: "Available", foreground: ToolkitColor.positive, fill: ToolkitColor.positiveFill)
        case .stale: Tag(text: "Stale", foreground: ToolkitColor.warning, fill: ToolkitColor.warningFill)
        case .missing: Tag(text: "Missing")
        case .unknown: Tag(text: "Unknown")
        }
    }
}

/// The website's "Reading the numbers".
struct ProjectionReadingContent: View {
    var body: some View {
        BulletList(items: [
            "Projected points is the mean: the long-run average and the number most tools show. A keeper's mean of 3.2 is a score he rarely gets.",
            "Median splits outcomes in half; mode is the single most likely score.",
            "The range is P10 to P90: it holds about 80% of outcomes. On the bar, the tick is the mean and the gold part is 10 points or more.",
            "10+ pts is the chance of 10 points or more in the gameweek; over a longer horizon it becomes the chance of at least one 10+ gameweek. Blank is 2 or fewer.",
            "A wide range means an explosive player, not a poorly informed model. Each forecast shows the playing-time assumptions separately.",
            "The stage says what the run knew: an early look has form and fixtures only, odds arrive 48 hours before the deadline, press conferences the day before.",
            "Every run is scored once its gameweek finishes; the website's accuracy page shows how accurate the projections have been.",
        ])
    }
}

/// Plain bullet points, each its own VoiceOver element.
struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm) {
                    Text("•").accessibilityHidden(true)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The range as a bar (concept 03): P10 to P90 in blue on a track of 20 points a gameweek, the part
/// at 10 points or more in gold (one gameweek only), and the mean as a tick. One Canvas, so a list
/// of 200 stays cheap to lay out. Decorative: the row reads the figures.
struct ProjectionRangeBar: View {
    let p10: Int
    let p90: Int
    let mean: Double
    var horizon = 1

    var body: some View {
        let blue = ToolkitColor.information
        let gold = ToolkitColor.accent
        let track = ToolkitColor.raised
        let tickColor = ToolkitColor.primaryText
        Canvas { context, size in
            let total = Double(max(1, 20 * horizon))
            func x(_ v: Double) -> CGFloat { size.width * CGFloat(min(1, max(0, v / total))) }
            let mid = size.height / 2
            let bar = CGFloat(6)
            context.fill(Path(roundedRect: CGRect(x: 0, y: mid - bar / 2, width: size.width, height: bar), cornerRadius: bar / 2),
                         with: .color(track))
            let lo = x(Double(max(0, p10))), hi = max(x(Double(p90)), lo + 3)
            context.fill(Path(roundedRect: CGRect(x: lo, y: mid - bar / 2, width: hi - lo, height: bar), cornerRadius: bar / 2),
                         with: .color(blue))
            // Only when the range goes past 10 (a range ending at 10 would show a sliver).
            if horizon == 1 && p90 > 10 {
                let from = max(lo, x(10))
                context.fill(Path(roundedRect: CGRect(x: from, y: mid - bar / 2, width: max(3, hi - from), height: bar),
                                  cornerRadius: bar / 2), with: .color(gold))
            }
            let t = x(mean)
            context.fill(Path(CGRect(x: max(0, t - 1), y: 0, width: 2, height: size.height)), with: .color(tickColor))
        }
        .frame(height: 12)
        .frame(maxWidth: 280)
        .accessibilityHidden(true)
    }
}

/// The list's Filters (concept 03): sort and order, likely starters, all nailed, and your minutes.
struct ProjectionFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sort: ProjectionSort
    @Binding var ascending: Bool
    @Binding var startersOnly: Bool
    let tweaks: ProjectionTweaks
    let horizon: Int

    var body: some View {
        NavigationStack {
            List {
                Section("Sort by") {
                    Picker("Sort by", selection: $sort) {
                        ForEach(ProjectionSort.allCases.filter { horizon == 1 || !$0.gameweekOnly }) { s in
                            Text(s == .mean ? "Projected points" : s == .haul ? (horizon > 1 ? "≥1 haul" : "10+ points") : s.label).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Picker("Order", selection: $ascending) {
                        Text("Highest first").tag(false)
                        Text("Lowest first").tag(true)
                    }
                }
                Section {
                    Toggle("Likely starters only", isOn: $startersOnly)
                    Toggle("All players nailed", isOn: Binding(get: { tweaks.allNailed }, set: { tweaks.allNailed = $0 }))
                } footer: {
                    Text("Likely starters have a 60% or better chance of playing an hour. All nailed treats every player as certain to play 60 minutes or more.")
                }
                if !tweaks.minutes.isEmpty {
                    Section {
                        Button("Reset \(tweaks.minutes.count) minutes forecast\(tweaks.minutes.count == 1 ? "" : "s")", role: .destructive) {
                            tweaks.reset()
                        }
                    } footer: {
                        Text("Your playing-time forecasts are set from each player's forecast and last while this screen is open.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .toolkitScreen()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Minutes forecast

/// The website's 60+ slider: your chance of the player playing an hour, in 5% steps.
struct ProjectionMinutesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: ProjectionMinutesTarget
    let tweaks: ProjectionTweaks
    @State private var value: Double
    /// Reset was chosen: nothing more to save on the way out.
    @State private var didReset = false

    init(target: ProjectionMinutesTarget, tweaks: ProjectionTweaks) {
        self.target = target
        self.tweaks = tweaks
        let yours = tweaks.allNailed ? 100 : tweaks.minutes[target.playerId]
        _value = State(initialValue: Double(yours ?? target.modelPct ?? 0))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                    Text("Chance of 60+ minutes in GW\(target.gameweek)")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("The model says \(ProjectionText.pct(target.modelPct)). Your forecast: \(Int(value))%.")
                        .font(.body)
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Slider(value: $value, in: 0...100, step: 5) {
                        Text("Your forecast")
                    } onEditingChanged: { dragging in
                        if !dragging { commit() }
                    }
                    .tint(ToolkitColor.accent)
                    .accessibilityValue("\(Int(value)) percent")
                    // Always one above the other: switching layout with the text size was read by
                    // the audit as text that doesn't scale (4 Oct).
                    VStack(spacing: ToolkitSpace.md) {
                        Button("Set 100%") {
                            value = 100
                            commit()
                        }
                        .buttonStyle(ToolkitPrimaryButtonStyle())
                        Button("Reset") {
                            didReset = true
                            tweaks.set(target.playerId, to: nil)
                            dismiss()
                        }
                        .buttonStyle(ToolkitSecondaryButtonStyle())
                    }
                    Text("Mean, range, haul and blank rescale with the chance he plays: an estimate on top of the model, kept while the projections screen is open.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ToolkitSpace.page)
            }
            .toolkitScreen()
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Full height: the half-height sheet scales its content, which the accessibility audit
        // reads as clipped text (4 Oct).
        .presentationDetents([.large])
        // VoiceOver's swipes change the value without a drag ending.
        .onDisappear(perform: commitIfChanged)
    }

    private var current: Int? { tweaks.allNailed ? 100 : tweaks.minutes[target.playerId] }

    private func commit() {
        tweaks.set(target.playerId, to: Int(value))
    }

    private func commitIfChanged() {
        guard !didReset else { return }
        if Int(value) != (current ?? target.modelPct ?? -1) { commit() }
    }
}
