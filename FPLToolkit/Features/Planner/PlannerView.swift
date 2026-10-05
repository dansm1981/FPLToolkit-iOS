import SwiftUI

/// The Planner tab (Dan's concept, 5 Oct 2026: "One workspace, different plans. The squad is the
/// starting point. The plan selector replaces the landing directory."). It opens on your plan; the
/// plan's name switches plans, starts a new one, or opens your FPL team, read-only, with its news,
/// fixtures and odds as the Team tab had them.
struct PlannerView: View {
    @Environment(AppModel.self) private var appModel
    /// nil while exploring without a team: import needs a Team ID, and there's no squad to show.
    let entryId: Int?
    // Created up front: a task on an empty view never runs.
    @State private var list: Resource<PlannerDraftList>
    /// The plan on screen: the last one opened (kept by DraftView), else the latest.
    @AppStorage(LastDraft.idKey) private var lastDraftId = ""
    @State private var showingSwitch = false
    @State private var showingNewDraft = false
    @State private var showingTeam = false
    @State private var addingTeam = false
    @State private var creating: String?
    @State private var createError: ErrorCopy?

    init(entryId: Int?, repository: PlannerRepository) {
        self.entryId = entryId
        _list = State(initialValue: Resource(repository.list))
    }

    var body: some View {
        Group {
            switch list.phase {
            case .loading:
                ScrollView {
                    SkeletonCards(caption: "Loading your plans…")
                        .padding(.horizontal, ToolkitSpace.page)
                }
            case .failed(let copy):
                ErrorStateView(copy: copy) { Task { await list.retry() } }
            case .loaded(let loaded):
                workspace(loaded.value.drafts)
            }
        }
        .task {
            if list.isInitial { await list.load() }
        }
        // Back on the tab: names and planned transfers may have changed.
        .onAppear {
            if !list.isInitial { Task { await list.load(bypassCache: true) } }
            openPending()
        }
        .onChange(of: appModel.router.pendingDraftId) { openPending() }
        .onChange(of: appModel.router.pendingPlannerSection) { openPending() }
        .navigationDestination(isPresented: $showingTeam) {
            if let entryId { FPLTeamView(entryId: entryId) }
        }
        .sheet(isPresented: $showingSwitch) {
            SwitchPlanSheet(
                drafts: list.loaded?.value.drafts ?? [],
                selectedId: currentId(list.loaded?.value.drafts ?? []),
                teamGameweek: appModel.bootstrap?.value.gameweek.current,
                hasTeam: entryId != nil,
                onSelect: { id in
                    lastDraftId = id
                    showingSwitch = false
                },
                onNew: {
                    showingSwitch = false
                    showingNewDraft = true
                },
                onTeam: {
                    showingSwitch = false
                    showingTeam = true
                },
                onAddTeam: {
                    showingSwitch = false
                    addingTeam = true
                },
                onRename: { draft, name in await rename(draft, to: name) },
                onDuplicate: { draft in await create(.copy(draft.id), label: "Copying \u{201C}\(draft.name)\u{201D}…") },
                onDelete: { draft in await delete(draft) })
        }
        .sheet(isPresented: $showingNewDraft) {
            NewDraftSheet(entryId: entryId, drafts: list.loaded?.value.drafts ?? []) { request, label in
                Task { await create(request, label: label) }
            }
        }
        .sheet(isPresented: $addingTeam) { AddTeamSheet() }
        .toolkitScreen()
        .navigationTitle("Planner")
        .navigationBarTitleDisplayMode(.large)
        .settingsButton(entryId: entryId)
    }

    @ViewBuilder
    private func workspace(_ drafts: [PlannerDraftSummary]) -> some View {
        if let id = currentId(drafts) {
            DraftView(id: id, repository: appModel.plannerRepository,
                      onSwitch: { showingSwitch = true },
                      onDeleted: { Task { await afterDelete() } })
                .id(id)
        } else {
            start
        }
    }

    /// No plans yet: the ways to start one, and your FPL team.
    private var start: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let creating {
                    HStack(spacing: ToolkitSpace.sm) {
                        ProgressView()
                        Text(creating).foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                if let createError { ErrorBanner(copy: createError) }
                EmptyPlanner(entryId: entryId, busy: creating != nil) { request, label in
                    Task { await create(request, label: label) }
                } more: {
                    showingNewDraft = true
                }
                if entryId != nil {
                    SectionLabel(text: "FPL reference")
                    FPLTeamRow(gameweek: appModel.bootstrap?.value.gameweek.current) { showingTeam = true }
                } else {
                    AddTeamCard(message: "Add your FPL team to plan from it, and to see your published squad with each player's next fixture, price and availability.") {
                        addingTeam = true
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
    }

    private func currentId(_ drafts: [PlannerDraftSummary]) -> String? {
        if drafts.contains(where: { $0.id == lastDraftId }) { return lastDraftId }
        return drafts.max { ($0.updatedAt ?? "") < ($1.updatedAt ?? "") }?.id
    }

    /// Today's "Continue your plan" names a plan; links to your team open it.
    private func openPending() {
        if let id = appModel.router.pendingDraftId {
            appModel.router.pendingDraftId = nil
            lastDraftId = id
        }
        if let section = appModel.router.pendingPlannerSection {
            appModel.router.pendingPlannerSection = nil
            if section == .team, entryId != nil { showingTeam = true }
        }
    }

    private func create(_ request: PlannerNewDraft, label: String) async {
        creating = label
        createError = nil
        defer { creating = nil }
        do {
            let draft = try await appModel.plannerRepository.create(request)
            await list.load(bypassCache: true)
            lastDraftId = draft.id
        } catch let error as APIError {
            createError = ErrorCopy(error)
        } catch {}
    }

    private func rename(_ draft: PlannerDraftSummary, to name: String) async {
        _ = try? await appModel.plannerRepository.update(draft.id, PlannerDraftPatch(name: name))
        await list.load(bypassCache: true)
    }

    private func delete(_ draft: PlannerDraftSummary) async {
        do {
            try await appModel.plannerRepository.delete(draft.id)
            LastDraft.forget(id: draft.id)
            await list.load(bypassCache: true)
        } catch let error as APIError {
            createError = ErrorCopy(error)
        } catch {}
    }

    private func afterDelete() async {
        await list.load(bypassCache: true)
    }
}

/// The read-only FPL team, as a row (concept 02's "FPL REFERENCE").
struct FPLTeamRow: View {
    let gameweek: Int?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: ToolkitSpace.md) {
                Image(systemName: "lock")
                    .font(.title3)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gameweek.map { "FPL team · GW\($0)" } ?? "FPL team")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("Read-only · last synced squad, news and fixtures")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: ToolkitSpace.sm)
                Image(systemName: "chevron.right")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(ToolkitSpace.lg)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(ToolkitColor.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your published FPL squad")
    }
}

/// Concept 02: your plans (the current one ticked, each with ⋯), your FPL team for reference,
/// and a new plan.
struct SwitchPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let drafts: [PlannerDraftSummary]
    let selectedId: String?
    let teamGameweek: Int?
    let hasTeam: Bool
    let onSelect: (String) -> Void
    let onNew: () -> Void
    let onTeam: () -> Void
    /// Exploring without a team: add one.
    let onAddTeam: () -> Void
    let onRename: (PlannerDraftSummary, String) async -> Void
    let onDuplicate: (PlannerDraftSummary) async -> Void
    let onDelete: (PlannerDraftSummary) async -> Void
    @State private var renaming: PlannerDraftSummary?
    @State private var newName = ""
    @State private var deleting: PlannerDraftSummary?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    SectionLabel(text: "Your plans")
                    ForEach(drafts) { draft in
                        planRow(draft)
                    }
                    SectionLabel(text: "FPL reference")
                        .padding(.top, ToolkitSpace.md)
                    if hasTeam {
                        FPLTeamRow(gameweek: teamGameweek, open: onTeam)
                    } else {
                        AddTeamCard(message: "Add your FPL team to plan from it, and to see your published squad with its news and fixtures.",
                                    add: onAddTeam)
                    }
                }
                .padding(.horizontal, ToolkitSpace.page)
                .padding(.bottom, ToolkitSpace.section)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onNew) {
                    Label("New plan", systemImage: "plus")
                }
                .buttonStyle(ToolkitPrimaryButtonStyle())
                .padding(.horizontal, ToolkitSpace.page)
                .padding(.vertical, ToolkitSpace.sm)
                .background(ToolkitColor.canvas)
            }
            .toolkitScreen()
            .navigationTitle("Switch plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename plan", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if let draft = renaming, !name.isEmpty, name != draft.name {
                        Task { await onRename(draft, name) }
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog(deleting.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { draft in
                Button("Delete plan", role: .destructive) { Task { await onDelete(draft) } }
            } message: { _ in
                Text("This can't be undone.")
            }
        }
        .presentationDetents([.large])
    }

    private func planRow(_ draft: PlannerDraftSummary) -> some View {
        let selected = draft.id == selectedId
        return HStack(alignment: .center, spacing: ToolkitSpace.sm) {
            Button { onSelect(draft.id) } label: {
                HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.md) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "doc.text")
                        .font(.title3)
                        .foregroundStyle(selected ? ToolkitColor.accent : ToolkitColor.secondaryText)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.name)
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(SwitchPlanSheet.detail(draft))
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(draft.name), \(SwitchPlanSheet.detail(draft))")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(selected ? "The plan on screen" : "Switches to this plan")
            Menu {
                Button {
                    newName = draft.name
                    renaming = draft
                } label: { Label("Rename…", systemImage: "pencil") }
                Button { Task { await onDuplicate(draft) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { deleting = draft } label: { Label("Delete…", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(draft.name)")
        }
        .padding(.horizontal, ToolkitSpace.md)
        .padding(.vertical, ToolkitSpace.sm)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card)
            .strokeBorder(selected ? ToolkitColor.accent : Color.clear, lineWidth: 1.5))
    }

    /// "GW6–9 · 1 planned transfer", "Nothing planned yet".
    nonisolated static func detail(_ draft: PlannerDraftSummary) -> String {
        guard let first = draft.plannedGws.min(), let last = draft.plannedGws.max() else {
            return draft.source == .import ? "From your FPL team · nothing planned yet" : "\(draft.playerCount) of 15 players · nothing planned yet"
        }
        let weeks = first == last ? "GW\(first)" : "GW\(first)–\(last)"
        if let n = draft.transferCount {
            return "\(weeks) · \(n) planned transfer\(n == 1 ? "" : "s")"
        }
        return "\(weeks) · \(draft.plannedGws.count) week\(draft.plannedGws.count == 1 ? "" : "s") planned"
    }
}

/// Your FPL team, read-only (from the plan switcher and Today's "View fixtures"): the squad you
/// last published, with team news, squad rotation, the pitch, list and fixtures, and odds, as the
/// Team tab had it. Your leagues are a tap away.
struct FPLTeamView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let entryId: Int
    @State private var team: Resource<Team>?
    @State private var odds: Resource<Odds>?
    @State private var showingLeagues = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                Text("Read-only: the squad you last published to FPL, with team news, fixtures and prices. Changes go in a plan.")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // "Plan changes" goes back to your plan.
                TeamSection(entryId: entryId, resource: team, odds: odds) { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable {
            async let o: Void = odds?.load(bypassCache: true) ?? ()
            await team?.load(bypassCache: true)
            await o
            noteSquad()
        }
        .toolkitScreen()
        .navigationTitle("FPL team")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingLeagues = true } label: {
                    Label("Your leagues", systemImage: "trophy")
                }
                .tint(ToolkitColor.accent)
            }
        }
        .navigationDestination(isPresented: $showingLeagues) { LeaguesListView() }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshIfStale() } }
        }
    }

    private func load() async {
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
            await refreshIfStale()
        }
    }

    /// Back here from another tab or the app: reload the squad after a minute (odds after 5).
    private func refreshIfStale() async {
        async let oddsLoad: Void = odds?.refreshIfStale(maxAge: 300) ?? ()
        await team?.refreshIfStale()
        await oddsLoad
        noteSquad()
    }

    private func noteSquad() {
        if let picks = team?.loaded?.value.snapshot?.picks {
            appModel.squadIds = Set(picks.map(\.playerId))
        }
    }
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
