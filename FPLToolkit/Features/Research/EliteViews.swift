import SwiftUI

/// The website's Elite Managers page (/elite): headline signals, the cohort's snapshot, and who
/// they buy, sell, own and captain.
struct EliteOverviewView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var table = ResearchTable<ElitePage<EliteOverview>>()

    static let explainer = "Elite Managers tracks a fixed anonymous cohort of 100 historically high-performing FPL managers. Their individual teams and identities are never displayed. Instead their collective decisions are aggregated to reveal ownership, transfers, captaincy, chip usage, squad structure and trends."

    var body: some View {
        EliteScreen(title: "Elite overview", caption: "Loading the elite cohort…", table: table, gw: $gw,
                    retry: reload) {
            EliteNote(text: Self.explainer)
        } content: { page, o in
            content(page, o)
        }
        .task(id: gw) { await table.load(appModel.eliteRepository.overview(gw: gw)) }
    }

    private func reload() { Task { await table.load(appModel.eliteRepository.overview(gw: gw)) } }

    private func content(_ page: ElitePage<EliteOverview>, _ o: EliteOverview) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            if !o.signals.isEmpty { signals(o.signals) }
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Elite snapshot · GW\(page.gw)")
                EliteStats(stats: o.snapshot)
            }
            template(page, o)
            transfers(page, o)
            owned(page, o)
            captaincy(page, o)
            positions(page, o)
            structure(o)
            MarketList(title: "Elite rising", rows: o.rising, empty: "Not enough history yet.") {
                EliteChangeRowView(row: $0, player: page.player($0.playerId), measure: "elite ownership over three gameweeks")
            }
            MarketList(title: "Elite cooling", rows: o.cooling, empty: "Not enough history yet.") {
                EliteChangeRowView(row: $0, player: page.player($0.playerId), measure: "elite ownership over three gameweeks")
            }
            EliteNote(text: "Rising and cooling compare elite ownership with three gameweeks earlier.")
        }
    }

    private func signals(_ signals: [EliteOverview.Signal]) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Elite signals")
            ForEach(signals) { signal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.title)
                        .font(.headline)
                    Text(signal.body)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(tint(signal.tone))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ToolkitSpace.md)
                .background(fill(signal.tone), in: RoundedRectangle(cornerRadius: ToolkitRadius.pill))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func tint(_ tone: EliteOverview.Signal.Tone) -> Color {
        switch tone {
        case .green: ToolkitColor.positive
        case .red: ToolkitColor.error
        case .amber, .unknown: ToolkitColor.warning
        }
    }

    private func fill(_ tone: EliteOverview.Signal.Tone) -> Color {
        switch tone {
        case .green: ToolkitColor.positiveFill
        case .red: ToolkitColor.errorFill
        case .amber, .unknown: ToolkitColor.warningFill
        }
    }

    private func template(_ page: ElitePage<EliteOverview>, _ o: EliteOverview) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Elite template")
            if let summary = o.templateSummary { EliteNote(text: summary) }
            NavigationLink {
                EliteTemplateView(initialGw: page.gw)
            } label: {
                Label("See the template squad", systemImage: "person.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
        }
    }

    private func transfers(_ page: ElitePage<EliteOverview>, _ o: EliteOverview) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketList(title: "Most bought", rows: o.bought, empty: "No elite transfers recorded for this gameweek.") {
                EliteShareRowView(row: $0, player: page.player($0.playerId), measure: "bought")
            }
            MarketList(title: "Most sold", rows: o.sold, empty: "No elite transfers recorded for this gameweek.") {
                EliteShareRowView(row: $0, player: page.player($0.playerId), measure: "sold")
            }
            MarketList(title: "Net elite transfers", rows: o.net, empty: "No net movement yet.") {
                EliteChangeRowView(row: $0, player: page.player($0.playerId), measure: "net")
            }
        }
    }

    private func owned(_ page: ElitePage<EliteOverview>, _ o: EliteOverview) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketList(title: "Most owned by elite managers", rows: o.mostOwned, playerOf: { page.player($0.playerId) }) {
                EliteShareRowView(row: $0, player: page.player($0.playerId), measure: "of elite managers", edgeVsAll: true)
            }
            MarketList(title: "Elite favourites", rows: o.favourites) { edgeRow($0, page) }
            EliteNote(text: "Favourites: much higher elite ownership than the wider game. Avoids: popular picks the cohort is largely ignoring.")
            MarketList(title: "Elite avoids", rows: o.avoids) { edgeRow($0, page) }
        }
    }

    private func edgeRow(_ row: EliteOverview.Edge, _ page: ElitePage<EliteOverview>) -> some View {
        EliteFigureRowView(
            playerId: row.playerId, figure: row.edge, player: page.player(row.playerId),
            chips: [RowChip(text: "Elite v all \(row.detail)")],
            figureColor: row.edge.hasPrefix("−") || row.edge.hasPrefix("-") ? ToolkitColor.error : ToolkitColor.positive,
            spokenFigure: "elite edge \(row.edge), elite versus overall \(row.detail)"
        )
    }

    private func captaincy(_ page: ElitePage<EliteOverview>, _ o: EliteOverview) -> some View {
        MarketList(title: "Captaincy", rows: o.captains) {
            EliteShareRowView(row: $0, player: page.player($0.playerId), measure: "captained")
        }
    }

    private func positions(_ page: ElitePage<EliteOverview>, _ o: EliteOverview) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            SectionLabel(text: "Position intelligence")
            ForEach(o.positions) { position in
                VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
                    MarketList(title: position.title, rows: position.top) { row in
                        EliteFigureRowView(playerId: row.playerId, figure: row.display, player: page.player(row.playerId),
                                           spokenFigure: "\(row.display) of elite managers")
                    }
                    EliteNote(text: "Average spend \(position.averageSpend) · median \(position.medianSpend)")
                }
            }
        }
    }

    private func structure(_ o: EliteOverview) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Squad structure")
                EliteStats(stats: o.structure)
            }
            MarketList(title: "Formations", rows: o.formations) { formation in
                HStack {
                    Text(formation.formation)
                        .font(.headline.monospacedDigit())
                    Spacer()
                    Text(formation.display)
                        .font(.headline.monospacedDigit())
                }
                .foregroundStyle(ToolkitColor.primaryText)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(formation.formation), \(formation.display) of elite managers")
            }
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Chips")
                EliteStats(stats: o.chips)
            }
        }
    }
}

/// The website's elite ownership table (/elite/ownership): every player the cohort owns, with
/// the website's filters and sorts.
struct EliteOwnershipView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var position: Position?
    @State private var club: Int?
    @State private var maxPrice: Double?
    @State private var view = EliteRepository.OwnershipView.all
    @State private var sort = "owned_pct"
    @State private var ascending = false
    @State private var search = ""
    @State private var table = ResearchTable<ElitePage<EliteOwnership>>()

    static let columns: [(key: String, label: String)] = [
        ("owned_pct", "Elite owned"), ("start_pct", "Starting"), ("bench_pct", "Benched"),
        ("captain_pct", "Captained"), ("overall_owned_pct", "Overall owned"), ("elite_edge", "Elite edge"),
        ("owned_delta", "Change since last gameweek"), ("price", "Price"),
    ]

    private struct Options: Hashable {
        let gw: Int?
        let position: Position?
        let club: Int?
        let maxPrice: Double?
        let view: EliteRepository.OwnershipView
        let sort: String
        let ascending: Bool
        let search: String
    }

    private var options: Options {
        Options(gw: gw, position: position, club: club, maxPrice: maxPrice, view: view, sort: sort,
                ascending: ascending, search: search)
    }

    var body: some View {
        EliteScreen(title: "Elite ownership", caption: "Loading elite ownership…", table: table, gw: $gw,
                    retry: reload) {
            controls
        } content: { page, o in
            list(page, o)
        }
        .searchable(text: $search, prompt: "Search players")
        .task(id: options) {
            // A short pause while typing a search.
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await table.load(appModel.eliteRepository.ownership(
            gw: gw, position: position, club: club, maxPrice: maxPrice, view: view, sort: sort,
            ascending: ascending, search: search))
    }

    private var priceCap: Double { (table.current?.loaded ?? table.previous)?.value.body?.priceCap ?? 15 }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Show", selection: $view) {
                Text("All").tag(EliteRepository.OwnershipView.all)
                Text("Highly owned").tag(EliteRepository.OwnershipView.core)
                Text("Differentials").tag(EliteRepository.OwnershipView.differentials)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, ToolkitSpace.sm)
            PositionPicker(position: $position)
                .padding(.bottom, ToolkitSpace.xs)
            ClubMenu(club: $club)
            Menu {
                Picker("Maximum price", selection: $maxPrice) {
                    Text("Any price").tag(Double?.none)
                    ForEach(prices, id: \.self) { Text("Up to \(money($0))").tag(Double?.some($0)) }
                }
            } label: {
                Label(maxPrice.map { "Up to \(money($0))" } ?? "Any price", systemImage: "sterlingsign.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Price: \(maxPrice.map { "up to \(money($0))" } ?? "any")")
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(Self.columns, id: \.key) { Text($0.label).tag($0.key) }
                }
                Picker("Order", selection: $ascending) {
                    Text("Highest first").tag(false)
                    Text("Lowest first").tag(true)
                }
            } label: {
                Label(sortSummary, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Sort: \(sortSummary)")
        }
    }

    /// The website's slider steps below its top.
    private var prices: [Double] { Array(stride(from: 3.5, to: priceCap, by: 0.5)) }

    private func money(_ value: Double) -> String { "£\(value.formatted(.number.precision(.fractionLength(1))))m" }

    private var sortSummary: String {
        let label = Self.columns.first { $0.key == sort }?.label ?? sort
        return "\(label), \(ascending ? "lowest first" : "highest first")"
    }

    private func list(_ page: ElitePage<EliteOwnership>, _ o: EliteOwnership) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            MarketList(title: "\(o.count) players", rows: o.rows, empty: "No players match these filters.", initial: 50) {
                row($0, page)
            }
            EliteNote(text: "Elite owned is the share of the 100 managers who own him; overall is the whole game. Elite edge is the gap between the two. Highly owned: 40%+ of the cohort. Differentials: 10%+ of the cohort but under 10% overall.")
        }
    }

    private func row(_ row: EliteOwnership.Row, _ page: ElitePage<EliteOwnership>) -> some View {
        let player = page.player(row.playerId)
        let spoken = [EliteFormat.name(player, row.playerId), "\(row.owned.display) of elite managers",
                      "starting \(row.start)", "benched \(row.bench)", "captained \(row.captain)",
                      "\(row.overall) overall", "elite edge \(row.edge)", "\(row.change.spoken) since last gameweek",
                      EliteFormat.price(player)].compactMap { $0 }.joined(separator: ", ")
        // Elite against everyone first (Dan, 29 Sep): the gap sits under the Elite figure.
        var chips = [RowChip(text: "All \(row.overall)"), RowChip(text: "Start \(row.start)")]
        if row.captain != "0%" { chips.append(RowChip(text: "Cap \(row.captain)")) }
        if row.change.value != 0 { chips.append(.change("\(row.change.shown) this GW", row.change.value)) }
        return MarketPlayerRow(
            playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            chips: chips, trailing: row.owned.display,
            trailingChip: EliteFormat.edgeChip(row.edge), spoken: spoken
        )
    }
}

/// The website's Elite Transfers page (/elite/transfers): buys, sells, net flow and the swaps
/// made most often.
struct EliteTransfersView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var table = ResearchTable<ElitePage<EliteTransfers>>()

    var body: some View {
        EliteScreen(title: "Elite transfers", caption: "Loading elite transfers…", table: table, gw: $gw,
                    retry: reload) { page, t in
            content(page, t)
        }
        .task(id: gw) { await table.load(appModel.eliteRepository.transfers(gw: gw)) }
    }

    private func reload() { Task { await table.load(appModel.eliteRepository.transfers(gw: gw)) } }

    private func content(_ page: ElitePage<EliteTransfers>, _ t: EliteTransfers) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Transfer activity · GW\(page.gw)")
                EliteStats(stats: t.stats)
            }
            MarketList(title: "Most bought", rows: t.bought, empty: "No elite buys recorded.") {
                EliteShareRowView(row: $0, player: page.player($0.playerId), measure: "bought")
            }
            MarketList(title: "Most sold", rows: t.sold, empty: "No elite sales recorded.") {
                EliteShareRowView(row: $0, player: page.player($0.playerId), measure: "sold")
            }
            MarketList(title: "Net elite transfers", rows: t.net, empty: "No net movement yet.") {
                EliteChangeRowView(row: $0, player: page.player($0.playerId), measure: "net")
            }
            MarketList(title: "Most common moves", rows: t.moves, empty: "No repeated swaps recorded for this gameweek.") {
                moveRow($0, page)
            }
            EliteNote(text: "Bought and sold are shares of the cohort; net is buyers minus sellers, in percentage points. Moves are the exact out-for-in swaps repeated across the cohort.")
        }
    }

    private func moveRow(_ move: EliteTransfers.Move, _ page: ElitePage<EliteTransfers>) -> some View {
        let out = EliteFormat.name(page.player(move.outId), move.outId)
        let incoming = EliteFormat.name(page.player(move.inId), move.inId)
        return HStack(alignment: .center, spacing: ToolkitSpace.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Out: \(out)")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                Text("In: \(incoming)")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ToolkitSpace.sm)
            Text(move.display)
                .font(.headline.monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, ToolkitSpace.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(out) out, \(incoming) in, \(move.display) of elite managers")
    }
}

/// The website's Elite Captaincy page (/elite/captaincy): how concentrated the armband is, and
/// the vice-captains.
struct EliteCaptaincyView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var table = ResearchTable<ElitePage<EliteCaptaincy>>()

    var body: some View {
        EliteScreen(title: "Elite captaincy", caption: "Loading elite captaincy…", table: table, gw: $gw,
                    retry: reload) { page, c in
            content(page, c)
        }
        .task(id: gw) { await table.load(appModel.eliteRepository.captaincy(gw: gw)) }
    }

    private func reload() { Task { await table.load(appModel.eliteRepository.captaincy(gw: gw)) } }

    private func content(_ page: ElitePage<EliteCaptaincy>, _ c: EliteCaptaincy) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Captaincy consensus · GW\(page.gw)")
                EliteStats(stats: c.stats)
            }
            MarketList(title: "Captain share", rows: c.captains, empty: "No captaincy data for this gameweek.") {
                EliteShareRowView(row: $0, player: page.player($0.playerId), measure: "captained")
            }
            MarketList(title: "Captain conviction", rows: c.conviction) { row in
                EliteFigureRowView(playerId: row.playerId, figure: row.display, player: page.player(row.playerId),
                                   spokenFigure: "conviction \(row.display)")
            }
            EliteNote(text: "Conviction is how often the managers who own a player hand him the armband: a measure of trust, not just ownership.")
            MarketList(title: "Vice-captain picks", rows: c.vices, empty: "No vice-captain data for this gameweek.") { row in
                EliteFigureRowView(playerId: row.playerId, figure: row.display, player: page.player(row.playerId),
                                   spokenFigure: "\(row.display) vice-captain")
            }
        }
    }
}

/// The website's Elite Template page (/elite/template): the fifteen the cohort converges on, the
/// XI they most often start, and who came and went since the last gameweek.
struct EliteTemplateView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gw: Int?
    @State private var table = ResearchTable<ElitePage<EliteTemplate>>()

    init(initialGw: Int? = nil) {
        _gw = State(initialValue: initialGw)
    }

    var body: some View {
        EliteScreen(title: "Elite template", caption: "Loading the elite template…", table: table, gw: $gw,
                    retry: reload) { page, t in
            content(page, t)
        }
        .task(id: gw) { await table.load(appModel.eliteRepository.template(gw: gw)) }
    }

    private func reload() { Task { await table.load(appModel.eliteRepository.template(gw: gw)) } }

    private func content(_ page: ElitePage<EliteTemplate>, _ t: EliteTemplate) -> some View {
        let starters = t.pitch.rows.flatMap { $0 }
        return VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Template squad · GW\(page.gw)")
                if let consensus = t.consensus { EliteNote(text: consensus) }
                EliteStats(stats: t.stats)
            }
            MarketList(title: "Starting XI", rows: starters, initial: 11) {
                EliteTemplatePickRow(pick: $0, player: page.player($0.playerId))
            }
            MarketList(title: "Bench", rows: t.pitch.bench) {
                EliteTemplatePickRow(pick: $0, player: page.player($0.playerId))
            }
            if let changes = t.changes {
                MarketList(title: "In since GW\(changes.from)", rows: changes.movedIn, empty: "No new template picks.") {
                    movedRow($0, page, from: changes.from, joined: true)
                }
                MarketList(title: "Out since GW\(changes.from)", rows: changes.movedOut, empty: "No players dropped out.") {
                    movedRow($0, page, from: changes.from, joined: false)
                }
            }
            EliteNote(text: "The fifteen most-backed players that still fit FPL's squad and club rules, with the XI the cohort most often starts. The price is the template's; strength is the fifteen's average elite ownership.")
        }
    }

    private func movedRow(_ row: EliteTemplate.Moved, _ page: ElitePage<EliteTemplate>, from: Int, joined: Bool) -> some View {
        EliteFigureRowView(
            playerId: row.playerId, figure: row.owned, player: page.player(row.playerId),
            extra: "\(row.change) since GW\(from)",
            spokenFigure: "\(joined ? "joined" : "left") the template, \(row.owned) of elite managers"
        )
    }
}
