import SwiftUI

/// The Planner tab (Dan, 4 Oct 2026): your plans and drafts at the top, then your current team
/// below with its news and info as the Team tab had them. A card at the top says both are here and
/// jumps to each. Drafts are this device's (Phase 2); the team is your published FPL squad.
struct PlannerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    /// nil while exploring without a team: import needs a Team ID, and there's no squad to show.
    let entryId: Int?
    // Created up front: a task on an empty view never runs.
    @State private var list: Resource<PlannerDraftList>
    @State private var team: Resource<Team>?
    @State private var odds: Resource<Odds>?
    @State private var creating: String?
    @State private var createError: ErrorCopy?
    @State private var opened: PlannerDraftRoute?
    @State private var pendingDelete: PlannerDraftSummary?
    /// Drafts being deleted: hidden straight away, shown again if the delete fails.
    @State private var deleting: Set<String> = []
    @State private var showingNewDraft = false
    @State private var showingLeagues = false
    @State private var addingTeam = false

    init(entryId: Int?, repository: PlannerRepository) {
        self.entryId = entryId
        _list = State(initialValue: Resource(repository.list))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    // "Your plans" scrolls to the very top, so the page card naming both parts shows too.
                    PlannerPageMap(drafts: visibleDrafts?.count, team: teamLine) { section in
                        scroll(to: section, proxy)
                    }
                    .id(PlannerSection.plans)
                    plans
                    currentTeam(proxy)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, ToolkitSpace.section)
            }
            .refreshable { await refreshAll() }
            .onAppear {
                // Back from a draft: names, planned weeks, copies and deletions may have changed.
                if !list.isInitial { Task { await list.load(bypassCache: true) } }
                openPending(proxy)
            }
            .onChange(of: appModel.router.pendingDraftId) { openPending(proxy) }
            .onChange(of: appModel.router.pendingPlannerSection) { openPending(proxy) }
        }
        .task {
            if list.isInitial { await list.load() }
        }
        .task { await loadTeam() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshTeamIfStale() } }
        }
        .navigationDestination(for: PlannerDraftRoute.self) { route in
            DraftView(id: route.id, repository: appModel.plannerRepository)
        }
        .navigationDestination(item: $opened) { route in
            DraftView(id: route.id, repository: appModel.plannerRepository)
        }
        .navigationDestination(isPresented: $showingLeagues) { LeaguesListView() }
        .toolbar {
            if entryId != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingLeagues = true } label: {
                        Label("Your leagues", systemImage: "trophy")
                    }
                    .tint(ToolkitColor.accent)
                }
            }
        }
        .sheet(isPresented: $addingTeam) { AddTeamSheet() }
        .sheet(isPresented: $showingNewDraft) {
            NewDraftSheet(entryId: entryId, drafts: list.loaded?.value.drafts ?? []) { request, label in
                Task { await create(request, label: label) }
            }
        }
        .confirmationDialog(
            pendingDelete.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { draft in
            Button("Delete draft", role: .destructive) { Task { await delete(draft) } }
        } message: { _ in
            Text("This can't be undone.")
        }
        .toolkitScreen()
        .navigationTitle("Planner")
        // In the top bar, as on Today (Dan, 30 Sep).
        .navigationBarTitleDisplayMode(.inline)
        .settingsButton(entryId: entryId)
    }

    // MARK: Your plans

    private var visibleDrafts: [PlannerDraftSummary]? {
        list.loaded?.value.drafts.filter { !deleting.contains($0.id) }
    }

    @ViewBuilder private var plans: some View {
        SectionHeader(title: "Your plans")
        Text("Drafts are separate plans: try transfers, chips and captains for the weeks ahead. Your real team below doesn't change.")
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        switch list.phase {
        case .loading:
            SkeletonCards(caption: "Loading your drafts…", count: 1)
        case .failed(let copy):
            ResearchErrorView(copy: copy) { Task { await list.retry() } }
        case .loaded(let loaded):
            if loaded.isFromCache || list.refreshError != nil { SavedDataBanner(resource: list) }
            if let creating {
                HStack(spacing: ToolkitSpace.sm) {
                    ProgressView()
                    Text(creating).foregroundStyle(ToolkitColor.secondaryText)
                }
            }
            if let createError { ErrorBanner(copy: createError) }
            let drafts = visibleDrafts ?? []
            if drafts.isEmpty {
                EmptyPlanner(entryId: entryId, busy: creating != nil) { request, label in
                    Task { await create(request, label: label) }
                } more: {
                    showingNewDraft = true
                }
            } else {
                CardGroup {
                    ForEach(drafts) { draft in
                        NavigationLink(value: PlannerDraftRoute(id: draft.id)) {
                            LinkRowLabel(title: draft.name, detail: DraftRow.details(draft), systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete draft", systemImage: "trash", role: .destructive) { pendingDelete = draft }
                        }
                        .accessibilityAction(named: "Delete draft") { pendingDelete = draft }
                        RowDivider()
                    }
                    Button { showingNewDraft = true } label: {
                        LinkRowLabel(title: "New draft", detail: "Import a team, start from scratch or copy a draft",
                                     systemImage: "plus", showsChevron: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(creating != nil)
                }
                Text("Drafts are kept on this device's account with FPLToolkit. Press and hold a draft to delete it.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Your current team

    @ViewBuilder private func currentTeam(_ proxy: ScrollViewProxy) -> some View {
        SectionHeader(title: "Your current team")
            .id(PlannerSection.team)
            .padding(.top, ToolkitSpace.md)
        if let entryId {
            Text("Your published squad as FPL has it, with team news, fixtures and prices.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TeamSection(entryId: entryId, resource: team, odds: odds) {
                scroll(to: .plans, proxy)
            }
        } else {
            AddTeamCard(message: "Add your FPL team to see your published squad here, with each player's next fixture, price and availability.") {
                addingTeam = true
            }
        }
    }

    /// "GW5 squad · team news" once the team has loaded.
    private var teamLine: String? {
        guard entryId != nil else { return nil }
        if let gw = team?.loaded?.value.snapshot?.gw { return "GW\(gw) squad, team news and fixtures" }
        return "Your squad, team news and fixtures"
    }

    // MARK: Loading

    private func loadTeam() async {
        guard let entryId else { return }
        if odds == nil {
            let odds = Resource(appModel.liveRepository.odds())
            self.odds = odds
            Task { await odds.load() }
        }
        if team == nil {
            let team = Resource(appModel.teamRepository.team(entryId: entryId))
            self.team = team
            await team.load()
            noteSquad()
        } else {
            await refreshTeamIfStale()
        }
    }

    /// Back on the Planner from another tab or the app: reload the squad after a minute (odds after
    /// 5), keeping the current copy on screen meanwhile.
    private func refreshTeamIfStale() async {
        async let oddsLoad: Void = odds?.refreshIfStale(maxAge: 300) ?? ()
        await team?.refreshIfStale()
        await oddsLoad
        noteSquad()
    }

    private func refreshAll() async {
        async let drafts: Void = list.load(bypassCache: true)
        async let squad: Void = team?.load(bypassCache: true) ?? ()
        _ = await (drafts, squad)
        noteSquad()
    }

    private func noteSquad() {
        if let picks = team?.loaded?.value.snapshot?.picks {
            appModel.squadIds = Set(picks.map(\.playerId))
        }
    }

    // MARK: Navigation

    private func scroll(to section: PlannerSection, _ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(section, anchor: .top) }
    }

    /// Today's "Continue your plan" asks for a draft by setting the router's pending ID; links to
    /// your team or your plans ask for a part of this screen.
    private func openPending(_ proxy: ScrollViewProxy) {
        if let id = appModel.router.pendingDraftId {
            appModel.router.pendingDraftId = nil
            opened = PlannerDraftRoute(id: id)
        }
        if let section = appModel.router.pendingPlannerSection {
            appModel.router.pendingPlannerSection = nil
            // After the tab switch has laid the screen out.
            DispatchQueue.main.async { scroll(to: section, proxy) }
        }
    }

    private func create(_ request: PlannerNewDraft, label: String) async {
        creating = label
        createError = nil
        defer { creating = nil }
        do {
            let draft = try await appModel.plannerRepository.create(request)
            await list.load(bypassCache: true)
            opened = PlannerDraftRoute(id: draft.id)
        } catch let error as APIError {
            createError = ErrorCopy(error)
        } catch {}
    }

    private func delete(_ draft: PlannerDraftSummary) async {
        deleting.insert(draft.id)
        defer { deleting.remove(draft.id) }
        do {
            try await appModel.plannerRepository.delete(draft.id)
            await list.load(bypassCache: true)
        } catch let error as APIError {
            createError = ErrorCopy(error)
        } catch {}
    }
}

/// The top of the Planner tab: what's on this page, each part a tap away.
private struct PlannerPageMap: View {
    /// Nil until the drafts have loaded.
    let drafts: Int?
    /// Nil while exploring without a team.
    let team: String?
    let jump: (PlannerSection) -> Void

    var body: some View {
        CardGroup {
            Button { jump(.plans) } label: {
                LinkRowLabel(title: "Your plans", detail: plansLine, systemImage: "calendar.badge.plus", showsChevron: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Scrolls to your plans")
            RowDivider()
            Button { jump(.team) } label: {
                LinkRowLabel(title: "Your current team", detail: team ?? "Add your FPL team to see it here",
                             systemImage: "tshirt", trailing: "Below ↓", showsChevron: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Scrolls down to your current team")
        }
    }

    private var plansLine: String {
        switch drafts {
        case nil: "Drafts for the weeks ahead"
        case 0?: "No drafts yet: start one below"
        case 1?: "1 draft"
        case let n?: "\(n) drafts"
        }
    }
}

struct PlannerDraftRoute: Hashable, Identifiable {
    let id: String
}

/// A draft's line under its name.
enum DraftRow {
    nonisolated static func details(_ draft: PlannerDraftSummary) -> String {
        var parts: [String] = []
        switch draft.source {
        case .import: parts.append("From your FPL team")
        case .copy: parts.append("Copy")
        case .blank, .unknown: parts.append("\(draft.playerCount) of 15 players")
        }
        switch draft.plannedGws.count {
        case 0: parts.append("nothing planned yet")
        case 1: parts.append("GW\(draft.plannedGws[0]) planned")
        default: parts.append("\(draft.plannedGws.count) weeks planned")
        }
        return parts.joined(separator: " · ")
    }
}

/// First visit: what the planner does, and the two ways to start.
private struct EmptyPlanner: View {
    let entryId: Int?
    let busy: Bool
    let start: (PlannerNewDraft, String) -> Void
    /// Opens the full new-draft sheet (another team's ID).
    let more: () -> Void

    var body: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                Label("Plan the weeks ahead", systemImage: "calendar.badge.plus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                Text("Try transfers, chips and captains for future gameweeks. Your bank, free transfers and the squad rules update as you go, using the same rules as fpltoolkit.co.uk.")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let entryId {
                    Button("Import my FPL team") { start(.import(entryId), "Importing your team from FPL…") }
                        .buttonStyle(ToolkitPrimaryButtonStyle())
                        .disabled(busy)
                    Text("Your purchase prices, bank, free transfers and chips played are read from your public FPL history.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Start from scratch") { start(.blank, "Starting a blank draft…") }
                    .buttonStyle(ToolkitSecondaryButtonStyle())
                    .disabled(busy)
                Button("Import another team’s ID…", action: more)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
                    .disabled(busy)
            }
        }
    }
}
