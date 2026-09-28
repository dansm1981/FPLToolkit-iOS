import SwiftUI

/// The Research tab: the website's research pages, in its groups: Fixtures (the ticker, the rotation
/// planner and congestion), Players (insights, the template team, injuries), Market (prices,
/// predictions, trends, transfers and ownership) and Elite (what the top 100 managers do). The
/// server builds every table with the website's code.
struct ResearchView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int?

    var body: some View {
        List {
            Section {
                row("Fixture ticker", systemImage: "list.number",
                    detail: "Every club's run of fixtures, easiest first, over the next 1 to 24 gameweeks.") {
                    FixtureTickerView(entryId: entryId)
                }
                row("Rotation planner", systemImage: "arrow.triangle.2.circlepath",
                    detail: "Pair 2 to 6 players whose fixtures alternate, and see who to start each week.") {
                    RotationPlannerView(entryId: entryId)
                }
                row("Congestion", systemImage: "calendar.badge.clock",
                    detail: "Every club's games in all competitions, and the rest between them.") {
                    CongestionView()
                }
            } header: {
                Text("Fixtures")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                row("Player insights", systemImage: "person.text.rectangle",
                    detail: "Every player sorted by any stat, with the differential opportunity map.") {
                    PlayerInsightsView()
                }
                row("Template team", systemImage: "person.3",
                    detail: "The most-owned XI, and everyone owned by 20% or more.") {
                    TemplateTeamView()
                }
                row("Injuries", systemImage: "cross.case",
                    detail: "Every flagged player, most owned first, with the latest news.") {
                    InjuriesView()
                }
            } header: {
                Text("Players")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                row("Price changes", systemImage: "sterlingsign.arrow.circlepath",
                    detail: "Confirmed rises and falls day by day, and the season's biggest movers.") {
                    MarketChangesView()
                }
                row("Predictions", systemImage: "gauge.with.dots.needle.67percent",
                    detail: "FPL's own figures for who is closest to a rise or fall tonight.") {
                    MarketPredictionsView()
                }
                row("Price and transfer trends", systemImage: "chart.line.uptrend.xyaxis",
                    detail: "Today's movers, the strongest flows, and every player sorted your way.") {
                    MarketTrendsView(entryId: entryId)
                }
                row("Transfers and ownership", systemImage: "arrow.left.arrow.right",
                    detail: "This gameweek's most bought and sold, and who owns whom.") {
                    MarketTransfersView()
                }
                Button {
                    appModel.router.selectedTab = .watch
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.md) {
                        Image(systemName: "bell")
                            .foregroundStyle(ToolkitColor.link)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("My price tracker")
                                .font(.headline)
                                .foregroundStyle(ToolkitColor.primaryText)
                            Text("Your watched players' price progress lives on the Watch tab.")
                                .font(.subheadline)
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, ToolkitSpace.xs)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the Watch tab")
            } header: {
                Text("Market")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                row("Elite overview", systemImage: "crown",
                    detail: "What the top 100 managers own, buy, sell and captain, week by week.") {
                    EliteOverviewView()
                }
                row("Elite ownership", systemImage: "chart.bar.xaxis",
                    detail: "Every player the cohort owns, starts and captains, against the wider game.") {
                    EliteOwnershipView()
                }
                row("Elite transfers", systemImage: "arrow.left.arrow.right.circle",
                    detail: "Their buys and sells, net flow, and the swaps they made most.") {
                    EliteTransfersView()
                }
                row("Elite captaincy", systemImage: "c.circle",
                    detail: "How concentrated the armband is, conviction, and the vice-captains.") {
                    EliteCaptaincyView()
                }
                row("Elite template", systemImage: "person.3.sequence",
                    detail: "The fifteen they converge on, the XI they start, and who came and went.") {
                    EliteTemplateView()
                }
            } header: {
                Text("Elite")
            }
            .listRowBackground(ToolkitColor.surface)
        }
        .listStyle(.insetGrouped)
        .toolkitScreen()
        .navigationTitle("Research")
        .settingsButton(entryId: entryId)
    }

    private func row<Destination: View>(
        _ title: String, systemImage: String, detail: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.md) {
                Image(systemName: systemImage)
                    .foregroundStyle(ToolkitColor.link)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, ToolkitSpace.xs)
            .frame(minHeight: 44)
        }
    }
}

/// One research table for the options on screen. A new choice loads a new table; the last one
/// stays up, dimmed, until it arrives. Saved copies show first and are labelled.
@MainActor
@Observable
final class ResearchTable<T: Decodable & Sendable> {
    private(set) var current: Resource<T>?
    private(set) var previous: Loaded<T>?

    func load(_ endpoint: some LoadableEndpoint<T>) async {
        if let loaded = current?.loaded { previous = loaded }
        let resource = Resource(endpoint)
        current = resource
        await resource.load()
        if resource.loaded != nil { previous = nil }
    }

    func refresh() async {
        await current?.load(bypassCache: true)
    }
}

/// Lays out a `ResearchTable`: the table, the last table while new options load, the failure, or
/// placeholders when nothing is known yet.
struct ResearchTableView<T: Decodable & Sendable, Content: View>: View {
    let table: ResearchTable<T>
    let caption: String
    let retry: () -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        if let resource = table.current, let loaded = resource.loaded {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                SavedDataBanner(resource: resource)
                content(loaded.value)
            }
        } else if case .failed(let copy)? = table.current?.phase {
            ResearchErrorView(copy: copy, retry: retry)
        } else if let previous = table.previous {
            content(previous.value)
                .opacity(0.45)
                .overlay(alignment: .top) {
                    ProgressView()
                        .padding(ToolkitSpace.lg)
                        .accessibilityLabel("Updating")
                }
                .allowsHitTesting(false)
        } else {
            SkeletonCards(caption: caption, count: 2)
        }
    }
}

/// A failure inside a scrolling screen (the full-screen one has its own scroll view).
struct ResearchErrorView: View {
    let copy: ErrorCopy
    let retry: () -> Void

    var body: some View {
        VStack(spacing: ToolkitSpace.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(ToolkitColor.error)
                .accessibilityHidden(true)
            Text(copy.title)
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
                .multilineTextAlignment(.center)
            Text(copy.message)
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(ToolkitSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ToolkitSpace.section)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The website's fixture switches for research screens. A club ticker has no position, so there
/// "By position" is left out and reads as Match, as the server does.
struct ResearchFixtureMenu: View {
    @Binding var model: FixtureView.Model
    @Binding var lens: FixtureView.Lens
    /// True on screens that rate clubs, not players.
    var clubs = false

    var body: some View {
        Menu {
            Picker("Fixture model", selection: $model) {
                ForEach(FixtureView.Model.allCases) { Text($0.label).tag($0) }
            }
            if model == .xfdr {
                Picker("View", selection: lensBinding) {
                    ForEach(lenses) { Text($0.label).tag($0) }
                }
            }
        } label: {
            Label(summary, systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Fixture difficulty: \(summary)")
        .accessibilityHint("Chooses FPL's difficulty or xFDR, and the xFDR view")
    }

    private var lenses: [FixtureView.Lens] {
        clubs ? FixtureView.Lens.allCases.filter { $0 != .position } : FixtureView.Lens.allCases
    }

    private var shownLens: FixtureView.Lens { clubs && lens == .position ? .match : lens }

    private var lensBinding: Binding<FixtureView.Lens> {
        Binding(get: { shownLens }, set: { lens = $0 })
    }

    var summary: String { FixtureView(model: model, lens: shownLens).summary }
}

/// A labelled figure, e.g. "ROTATION FDR 16.0".
struct ResearchFigure: View {
    let label: String
    let value: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ToolkitSpace.md)
        .background(ToolkitColor.raised, in: RoundedRectangle(cornerRadius: ToolkitRadius.pill))
        .accessibilityElement(children: .combine)
    }
}
