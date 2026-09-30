import SwiftUI

/// The Elite 100 home (batch 3): You vs Elite and Elite vs overall first, then a card for every
/// Elite page with this week's key figure from the overview. Replaces the hub's list of Elite rows.
struct EliteHomeView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int?
    @State private var overview: Resource<ElitePage<EliteOverview>>?
    @State private var you: Resource<ElitePage<TeamElite>>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                Text(intro)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let entryId {
                    card("You vs Elite", systemImage: "person.2", figure: youFigure,
                         detail: "Your squad against the top 100: the template, the players you share and the ones you don't.") {
                        YouVsEliteView(entryId: entryId)
                    }
                }
                card("Elite vs overall", systemImage: "arrow.left.and.right", figure: gapsFigure,
                     detail: "The biggest gaps between the top 100 and every manager, both ways.") {
                    EliteGapsView()
                }
                SectionLabel(text: "Every Elite page")
                    .padding(.top, ToolkitSpace.sm)
                card("Elite overview", systemImage: "crown", figure: stat("Median GW points"),
                     detail: "What the top 100 managers own, buy, sell and captain, week by week.") { EliteOverviewView() }
                card("Elite ownership", systemImage: "chart.bar.xaxis", figure: stat("Most owned"),
                     detail: "Every player the cohort owns, starts and captains, against the wider game.") { EliteOwnershipView() }
                card("Elite transfers", systemImage: "arrow.left.arrow.right.circle", figure: stat("Most bought"),
                     detail: "Their buys and sells, net flow, and the swaps they made most.") { EliteTransfersView() }
                card("Elite captaincy", systemImage: "c.circle", figure: stat("Most captained"),
                     detail: "How concentrated the armband is, conviction, and the vice-captains.") { EliteCaptaincyView() }
                card("Elite template", systemImage: "person.3.sequence", figure: overviewBody?.templateSummary,
                     detail: "The fifteen they converge on, the XI they start, and who came and went.") { EliteTemplateView() }
                card("Elite template race", systemImage: "flag.checkered", figure: nil,
                     detail: "The template players and the challengers closing in, over the season.") { EliteRaceView() }
                card("Elite movers", systemImage: "arrow.up.arrow.down", figure: nil,
                     detail: "The sharpest ownership swings, first-time picks, and template entries and exits.") { EliteMoversView() }
                card("Elite comparison", systemImage: "chart.xyaxis.line", figure: nil,
                     detail: "Up to eight players' elite ownership, side by side across the season.") { EliteCompareView(entryId: entryId) }
                card("Elite chips", systemImage: "square.stack.3d.up", figure: stat("Wildcards this GW"),
                     detail: "When the cohort plays each chip, and how many they have left.") { EliteChipsView() }
                card("Elite squad structure", systemImage: "square.grid.3x3", figure: stat("Most common formation"),
                     detail: "Formations, spend by position, and team value over the season.") { EliteStructureView() }
                card("Elite trends", systemImage: "chart.line.uptrend.xyaxis", figure: nil,
                     detail: "The cohort's season week by week, and who they're piling into or dropping.") { EliteTrendsView() }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable {
            async let o: Void = overview?.load(bypassCache: true) ?? ()
            async let y: Void = you?.load(bypassCache: true) ?? ()
            _ = await (o, y)
        }
        .toolkitScreen()
        .navigationTitle("Elite 100")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if overview == nil {
                let overview = Resource(appModel.eliteRepository.overview(gw: nil))
                self.overview = overview
                if let entryId {
                    let you = Resource(appModel.eliteRepository.you(entryId: entryId))
                    self.you = you
                    async let y: Void = you.load()
                    await overview.load()
                    await y
                } else {
                    await overview.load()
                }
            }
        }
    }

    private var overviewPage: ElitePage<EliteOverview>? { overview?.loaded?.value }
    private var overviewBody: EliteOverview? { overviewPage?.body }

    private var intro: String {
        guard let page = overviewPage, page.gw > 0 else {
            return "What the top 100 managers do: a fixed, anonymous cohort of the best FPL managers."
        }
        return "What the top 100 managers did in GW\(page.gw): a fixed, anonymous cohort of the best FPL managers."
    }

    /// "Most owned: Haaland 97%" from the overview's tiles.
    private func stat(_ label: String) -> String? {
        guard let tile = overviewBody?.snapshot.first(where: { $0.label == label }) else { return nil }
        return [label + ": " + tile.value, tile.sub].compactMap { $0 }.joined(separator: " · ")
    }

    private var youFigure: String? {
        guard let body = you?.loaded?.value.body else { return nil }
        return "You own \(body.template.owned) of the \(body.template.total)-man template · likeness \(body.likeness.you.display) (average Elite squad \(body.likeness.eliteAverage.display))"
    }

    private var gapsFigure: String? {
        guard let page = overviewPage, let body = page.body else { return nil }
        var parts: [String] = []
        if let top = body.favourites.first {
            parts.append("Backed: \(EliteFormat.name(page.player(top.playerId), top.playerId)) \(top.edge)")
        }
        if let avoid = body.avoids.first {
            parts.append("avoided: \(EliteFormat.name(page.player(avoid.playerId), avoid.playerId)) \(avoid.edge)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// One Elite page: title, this week's figure (when there is one) and what's inside. VoiceOver
    /// reads "Title, figure. detail", so the UI tests find it by its title and a comma.
    private func card<Destination: View>(
        _ title: String, systemImage: String, figure: String?, detail: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            ToolkitCard {
                HStack(alignment: .center, spacing: ToolkitSpace.md) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(ToolkitColor.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        if let figure {
                            Text(figure)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ", " + [figure, detail].compactMap { $0 }.joined(separator: ". "))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - You vs Elite

/// Your squad against the Elite 100 (batch 3): how much of the template you own, how Elite-like
/// your squad is next to an average Elite squad and the template itself, each player's Elite and
/// overall ownership, the Elite core you don't own, and your differentials. The server works it
/// out; this lays it out.
struct YouVsEliteView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int
    @State private var resource: Resource<ElitePage<TeamElite>>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                switch resource?.phase {
                case .loading?, nil:
                    SkeletonCards(caption: "Comparing your squad with the top 100…")
                case .failed(let copy)?:
                    ErrorStateView(copy: copy) { Task { await resource?.retry() } }
                case .loaded(let loaded)?:
                    if let body = loaded.value.body {
                        content(body, page: loaded.value)
                    } else {
                        InlineNotice(text: "The top 100's picks for this gameweek aren't published yet.", systemImage: "clock")
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await resource?.load(bypassCache: true) }
        .toolkitScreen()
        .navigationTitle("You vs Elite")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if resource == nil {
                let resource = Resource(appModel.eliteRepository.you(entryId: entryId))
                self.resource = resource
                await resource.load()
            }
        }
    }

    @ViewBuilder private func content(_ body: TeamElite, page: ElitePage<TeamElite>) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                Text("Template overlap: \(body.template.owned) of \(body.template.total)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                Text("You own \(body.template.owned) of the \(body.template.total) players the top 100 converge on, and \(body.template.startingOwned) of the \(body.template.startingTotal) they start.")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    likenessBar("You", body.likeness.you, highlighted: true)
                    likenessBar("Average Elite squad", body.likeness.eliteAverage)
                    likenessBar("The template", body.likeness.template)
                }
                Text("Likeness is the average share of the top 100 owning each of a squad's players.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        section("Your squad vs the Elite", rows: body.squad, page: page,
                empty: "No published squad yet.")
        section("Elite core you don't own", rows: body.missing, page: page,
                empty: "You own every player at least 40% of the top 100 own.")
        section("Your differentials", rows: body.differentials, page: page,
                empty: "Every player of yours is owned by at least 10% of the top 100.")
        Text("GW\(page.gw) picks of the top \(body.cohortSize.map(String.init) ?? "100") managers against your GW\(body.squadGw.map(String.init) ?? "–") squad. The core is players at least 40% of them own; differentials are yours owned by under 10%.")
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func likenessBar(_ label: String, _ value: ShownValue, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(highlighted ? .semibold : .regular))
                    .foregroundStyle(ToolkitColor.primaryText)
                Spacer()
                Text(value.display)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ToolkitColor.raised)
                    Capsule().fill(highlighted ? ToolkitColor.accent : ToolkitColor.link)
                        .frame(width: proxy.size.width * min(1, max(0, value.value / 100)))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): likeness \(value.display)")
    }

    @ViewBuilder private func section(_ title: String, rows: [TeamElite.Row], page: ElitePage<TeamElite>,
                                      empty: String) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionHeader(title: title)
            if rows.isEmpty {
                Text(empty)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().overlay(ToolkitColor.border) }
                        eliteRow(row, player: page.player(row.playerId))
                    }
                }
                .padding(.horizontal, 14)
                .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            }
        }
    }

    private func eliteRow(_ row: TeamElite.Row, player: PlayerSummary?) -> some View {
        let name = EliteFormat.name(player, row.playerId)
        let chips = row.inTemplate ? [RowChip(text: "Template", tone: .accent)] : []
        return MarketPlayerRow(
            playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            extra: "Overall \(row.overall)", chips: chips, trailing: row.elite.display,
            trailingChip: EliteFormat.edgeChip(row.edge),
            spoken: [name, "owned by \(row.elite.display) of the top 100", "\(row.overall) overall",
                     row.inTemplate ? "in the template" : nil].compactMap { $0 }.joined(separator: ", ")
        )
    }
}

// MARK: - Elite vs overall

/// The biggest gaps between the top 100 and every manager (batch 3), both ways, from the Elite
/// ownership table sorted by its edge column.
struct EliteGapsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var backed: Resource<ElitePage<EliteOwnership>>?
    @State private var avoided: Resource<ElitePage<EliteOwnership>>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                Text("Ownership among the top 100 against every FPL manager. The chip is the gap in percentage points.")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                list("The Elite back more than the game", resource: backed)
                list("The game backs more than the Elite", resource: avoided)
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable {
            async let b: Void = backed?.load(bypassCache: true) ?? ()
            async let a: Void = avoided?.load(bypassCache: true) ?? ()
            _ = await (b, a)
        }
        .toolkitScreen()
        .navigationTitle("Elite vs overall")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if backed == nil {
                let repo = appModel.eliteRepository
                let backed = Resource(repo.ownership(gw: nil, position: nil, club: nil, maxPrice: nil, view: .all,
                                                     sort: "elite_edge", ascending: false, search: ""))
                let avoided = Resource(repo.ownership(gw: nil, position: nil, club: nil, maxPrice: nil, view: .all,
                                                      sort: "elite_edge", ascending: true, search: ""))
                self.backed = backed
                self.avoided = avoided
                async let b: Void = backed.load()
                async let a: Void = avoided.load()
                _ = await (b, a)
            }
        }
    }

    @ViewBuilder private func list(_ title: String, resource: Resource<ElitePage<EliteOwnership>>?) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionHeader(title: title)
            switch resource?.phase {
            case .loading?, nil:
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            case .failed(let copy)?:
                Text("\(copy.title). \(copy.message)")
                    .foregroundStyle(ToolkitColor.secondaryText)
            case .loaded(let loaded)?:
                if let body = loaded.value.body, !body.rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(body.rows.prefix(15).enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().overlay(ToolkitColor.border) }
                            let player = loaded.value.player(row.playerId)
                            MarketPlayerRow(
                                playerId: row.playerId, player: player,
                                details: [EliteFormat.price(player)].compactMap { $0 },
                                extra: "Overall \(row.overall)", trailing: row.owned.display,
                                trailingChip: EliteFormat.edgeChip(row.edge),
                                spoken: "\(EliteFormat.name(player, row.playerId)), owned by \(row.owned.display) of the top 100 and \(row.overall) overall, \(row.edge)")
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
                } else {
                    Text("The top 100's picks for this gameweek aren't published yet.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
    }
}
