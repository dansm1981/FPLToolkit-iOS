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

/// Projections (Dan, 4 Oct 2026; happy-backend-pal#74): the website's /projections. Every
/// player's points for the coming gameweeks as a distribution, with the site's filters, your own
/// minutes forecasts, and a breakdown per player. Built to stand alone, so it can become a tab.
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
    @State private var editing: ProjectionMinutesTarget?

    private struct Key: Hashable {
        let horizon: Int, position: Position?, search: String, startersOnly: Bool, allNailed: Bool
        let minutes: [Int: Int], sort: ProjectionSort, ascending: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let latest {
                    if let run = latest.run {
                        ProjectionRunCard(run: run)
                        CardGroup {
                            NavigationLink {
                                ProjectionKnewView(run: run, knew: latest.knew)
                            } label: {
                                LinkRowLabel(title: "What this run knew", detail: run.stage.note ?? "The inputs behind these numbers",
                                             systemImage: "checklist")
                            }
                            .buttonStyle(.plain)
                            RowDivider()
                            NavigationLink {
                                ProjectionReadingView()
                            } label: {
                                LinkRowLabel(title: "Reading the numbers", detail: "Mean, median, mode, the range, hauls and blanks",
                                             systemImage: "book")
                            }
                            .buttonStyle(.plain)
                        }
                        filters(latest)
                    }
                }
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
        .navigationBarTitleDisplayMode(.inline)
        .environment(tweaks)
        .sheet(item: $editing) { target in
            ProjectionMinutesSheet(target: target, tweaks: tweaks)
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

    // MARK: Filters

    @ViewBuilder
    private func filters(_ data: Projections) -> some View {
        PositionPicker(position: $position)
        TextField("Search players", text: $search)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 10))
            .submitLabel(.search)
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Menu {
                Picker("Gameweeks", selection: $horizon) {
                    ForEach(data.horizons) { Text($0.label).tag($0.value) }
                }
            } label: {
                FilterChipLabel(text: horizonLabel(data), active: horizon > 1, menu: true)
            }
            .accessibilityLabel("Gameweeks: \(horizonLabel(data))")
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
                FilterChipLabel(text: "Sort: \(sortLabel(sort))\(ascending ? " ↑" : "")", active: false, menu: true)
            }
            .accessibilityLabel("Sort by \(sortLabel(sort)), \(ascending ? "lowest" : "highest") first")
            toggleChip("Likely starters", active: startersOnly,
                       spoken: "Likely starters only, 60% or more to play an hour") { startersOnly.toggle() }
            toggleChip("All nailed", active: tweaks.allNailed,
                       spoken: "All players nailed, 100% to play 60 minutes or more") { tweaks.allNailed.toggle() }
            if !tweaks.allNailed && !tweaks.minutes.isEmpty {
                Button { tweaks.reset() } label: {
                    Text("Reset \(tweaks.minutes.count) minutes tweak\(tweaks.minutes.count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func horizonLabel(_ data: Projections) -> String {
        data.horizons.first { $0.value == horizon }?.label ?? "GW\(data.run?.fromGw ?? 0)"
    }

    private func sortLabel(_ s: ProjectionSort) -> String {
        s == .haul && horizon > 1 ? "≥1 haul" : s.label
    }

    private func toggleChip(_ text: String, active: Bool, spoken: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            FilterChipLabel(text: text, active: active, menu: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(active ? [.isSelected, .isToggle] : .isToggle)
    }

    // MARK: List

    @ViewBuilder
    private func list(_ data: Projections) -> some View {
        Text("\(data.total) player\(data.total == 1 ? "" : "s")\(data.total > data.rows.count ? ", showing the top \(data.rows.count)" : "")")
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
        if data.rows.isEmpty {
            RivalNote(text: "No players match.")
        } else {
            CardGroup {
                ForEach(Array(data.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider() }
                    playerRow(row, data: data)
                }
            }
        }
        Text("Open a player for how the number is built. Press and hold a player to set your own minutes forecast: mean, range, haul and blank rescale with the chance he plays (an estimate on top of the model, kept while this screen is open). Over a longer horizon, haul becomes the chance of at least one 10+ gameweek.")
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func playerRow(_ r: Projections.Row, data: Projections) -> some View {
        if let summary = data.player(r.playerId) {
            let target = ProjectionMinutesTarget(playerId: r.playerId, name: summary.webName,
                                                 gameweek: data.run?.fromGw ?? 0, modelPct: r.modelSixtyPct)
            NavigationLink {
                ProjectionPlayerView(playerId: r.playerId, knownName: summary.webName, modelSixtyPct: r.modelSixtyPct)
                    .environment(tweaks)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    PlayerListRow(player: summary,
                                  detail: Format.unbroken(detail(r, horizon: data.horizon)),
                                  value: value(r),
                                  valueDetail: valueLabel(data.horizon),
                                  spokenDetail: spoken(r, horizon: data.horizon),
                                  wrapsDetail: true)
                    ProjectionRangeBar(p10: r.p10, p90: r.p90, mean: r.mean, span: 20 * data.horizon)
                        .padding(.leading, 44)
                        .padding(.top, -4)
                        .padding(.bottom, ToolkitSpace.md)
                }
                .padding(.horizontal, 15)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens how this projection is built")
            .contextMenu {
                Button { editing = target } label: { Label("Your minutes forecast…", systemImage: "slider.horizontal.3") }
                if r.adjusted && !tweaks.allNailed {
                    Button { tweaks.set(r.playerId, to: nil) } label: { Label("Back to the model's", systemImage: "arrow.uturn.backward") }
                }
            }
            .accessibilityAction(named: "Your minutes forecast") { editing = target }
        }
    }

    /// Everything but the figure on the right: "£9.5m · Mean 6.8 · Med 6 · Mode 2 · Range 1–15 · …".
    private func detail(_ r: Projections.Row, horizon: Int) -> String {
        var parts: [String] = []
        if sort != .price { parts.append(Format.price(r.price)) }
        if sort != .mean { parts.append("Mean \(ProjectionText.one(r.mean))") }
        if sort != .median { parts.append("Med \(r.median)") }
        if sort != .mode { parts.append("Mode \(r.mode)") }
        parts.append("Range \(r.p10)–\(r.p90)")
        if sort != .haul { parts.append("\(horizon > 1 ? "≥1 haul" : "Haul") \(ProjectionText.pct(r.haulPct))") }
        if horizon == 1 && sort != .blank { parts.append("Blank \(ProjectionText.pct(r.blankPct))") }
        if sort != .sixty { parts.append("60+ \(ProjectionText.pct(r.sixtyPct))\(r.adjusted ? " yours" : "")") }
        if horizon == 1 && sort != .fplEp { parts.append("FPL ep \(r.fplEp.map(ProjectionText.one) ?? "—")") }
        return parts.joined(separator: " · ")
    }

    private func value(_ r: Projections.Row) -> String {
        switch sort {
        case .mean: ProjectionText.one(r.mean)
        case .median: "\(r.median)"
        case .mode: "\(r.mode)"
        case .p90: "\(r.p90)"
        case .haul: ProjectionText.pct(r.haulPct)
        case .blank: ProjectionText.pct(r.blankPct)
        case .sixty: ProjectionText.pct(r.sixtyPct)
        case .price: Format.price(r.price)
        case .fplEp: r.fplEp.map(ProjectionText.one) ?? "—"
        }
    }

    private func valueLabel(_ horizon: Int) -> String {
        switch sort {
        case .mean: "mean"
        case .median: "median"
        case .mode: "mode"
        case .p90: "P90"
        case .haul: horizon > 1 ? "≥1 haul" : "haul"
        case .blank: "blank"
        case .sixty: "60+ min"
        case .price: "price"
        case .fplEp: "FPL ep"
        }
    }

    private func spoken(_ r: Projections.Row, horizon: Int) -> String {
        var parts = [
            "\(sortLabel(sort)) \(value(r))",
            "Mean \(ProjectionText.one(r.mean)) points, median \(r.median), most likely \(r.mode), 80% range \(r.p10) to \(r.p90)",
            horizon > 1 ? "Chance of at least one 10 point gameweek \(ProjectionText.pct(r.haulPct))" : "Haul chance \(ProjectionText.pct(r.haulPct))",
        ]
        if horizon == 1 { parts.append("Blank chance \(ProjectionText.pct(r.blankPct))") }
        parts.append("\(ProjectionText.pct(r.sixtyPct)) chance of 60 minutes\(r.adjusted ? ", your forecast" : "")")
        if horizon == 1, let ep = r.fplEp { parts.append("FPL's expected points \(ProjectionText.one(ep))") }
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

/// "What this run knew": each input's status, when it was observed, and the run's notes.
struct ProjectionKnewView: View {
    let run: ProjectionRun
    let knew: Projections.Knew?

    var body: some View {
        ScrollView {
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
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("What this run knew")
        .navigationBarTitleDisplayMode(.inline)
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
struct ProjectionReadingView: View {
    var body: some View {
        ScrollView {
            BulletList(items: [
                "Mean is the long-run average and the number most tools show. A keeper's mean of 3.2 is a score he rarely gets.",
                "Median splits outcomes in half; mode is the single most likely score.",
                "P10 to P90 is the range that holds about 80% of outcomes; the tick is the mean.",
                "Haul is the chance of 10 points or more in the gameweek; over a longer horizon it becomes the chance of at least one 10+ gameweek. Blank is 2 or fewer.",
                "A wide range means an explosive player, not a poorly informed model. What the run knew is listed with the run, and each player's breakdown shows the minutes certainty separately.",
                "The stage says what the run knew: an early look has form and fixtures only, odds arrive 48 hours before the deadline, press conferences the day before.",
                "Every run is scored once its gameweek finishes; the website's accuracy page shows how accurate the projections have been.",
            ])
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Reading the numbers")
        .navigationBarTitleDisplayMode(.inline)
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

/// The website's P10–P90 bar: the band on a track of 20 points a gameweek, with the mean as a tick.
/// A fixed width, measured once (no GeometryReader in each of up to 200 rows: the accessibility
/// audit re-lays the list out at every text size it tries). Decorative: the row reads the figures.
struct ProjectionRangeBar: View {
    let p10: Int
    let p90: Int
    let mean: Double
    let span: Int
    private let width: CGFloat = 160

    var body: some View {
        let total = Double(max(1, span))
        let start = min(1, Double(max(0, p10)) / total)
        let band = min(1 - start, max(0.02, Double(p90 - max(0, p10)) / total))
        let tick = min(1, max(0, mean) / total)
        ZStack(alignment: .leading) {
            Capsule().fill(ToolkitColor.raised).frame(width: width, height: 6)
            Capsule().fill(ToolkitColor.accent.opacity(0.55))
                .frame(width: width * band, height: 6)
                .offset(x: width * start)
            Rectangle().fill(ToolkitColor.primaryText)
                .frame(width: 2, height: 11)
                .offset(x: max(0, width * tick - 1))
        }
        .frame(width: width, height: 11, alignment: .leading)
        .accessibilityHidden(true)
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
