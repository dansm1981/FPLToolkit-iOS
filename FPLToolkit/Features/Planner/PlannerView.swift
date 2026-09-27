import SwiftUI

/// The Planner tab: this device's drafts, and starting a new one (Phase 2).
struct PlannerView: View {
    @Environment(AppModel.self) private var appModel
    /// nil while exploring without a team: import needs a Team ID.
    let entryId: Int?
    // Created up front: a task on an empty view never runs.
    @State private var list: Resource<PlannerDraftList>
    @State private var creating: String?
    @State private var createError: ErrorCopy?
    @State private var opened: PlannerDraftRoute?
    @State private var pendingDelete: PlannerDraftSummary?
    /// Drafts being deleted: hidden straight away, shown again if the delete fails.
    @State private var deleting: Set<String> = []
    @State private var showingNewDraft = false

    init(entryId: Int?, repository: PlannerRepository) {
        self.entryId = entryId
        _list = State(initialValue: Resource(repository.list))
    }

    var body: some View {
        Group {
            switch list.phase {
            case .loading:
                ScrollView {
                    SkeletonCards(caption: "Loading your drafts…")
                        .padding(.horizontal, ToolkitSpace.page)
                }
            case .failed(let copy):
                ErrorStateView(copy: copy) { Task { await list.retry() } }
            case .loaded(let loaded):
                content(loaded, list: list)
            }
        }
        .task {
            if list.isInitial { await list.load() }
        }
        .navigationDestination(for: PlannerDraftRoute.self) { route in
            DraftView(id: route.id, repository: appModel.plannerRepository)
        }
        .navigationDestination(item: $opened) { route in
            DraftView(id: route.id, repository: appModel.plannerRepository)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewDraft = true } label: {
                    Label("New draft", systemImage: "plus")
                }
                .disabled(creating != nil)
            }
        }
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
        .settingsButton(entryId: entryId)
    }

    private func content(_ loaded: Loaded<PlannerDraftList>, list: Resource<PlannerDraftList>) -> some View {
        List {
            // Only when there's something to say (an empty row would be an unlabelled element).
            if loaded.isFromCache || list.refreshError != nil || creating != nil || createError != nil {
                Section {
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        SavedDataBanner(resource: list)
                        if let creating {
                            HStack(spacing: ToolkitSpace.sm) {
                                ProgressView()
                                Text(creating).foregroundStyle(ToolkitColor.secondaryText)
                            }
                        }
                        if let createError {
                            ErrorBanner(copy: createError)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }

            let drafts = loaded.value.drafts.filter { !deleting.contains($0.id) }
            if drafts.isEmpty {
                Section {
                    EmptyPlanner(entryId: entryId, busy: creating != nil) { request, label in
                        Task { await create(request, label: label) }
                    } more: {
                        showingNewDraft = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            } else {
                Section {
                    ForEach(drafts) { draft in
                        NavigationLink(value: PlannerDraftRoute(id: draft.id)) {
                            DraftRow(draft: draft)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { pendingDelete = draft }
                                .tint(ToolkitColor.destructiveAction)
                        }
                    }
                } header: {
                    SectionLabel(text: "Your drafts")
                } footer: {
                    Text("Drafts are kept on this device's account with FPLToolkit. Swipe left to delete one.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .listRowBackground(ToolkitColor.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await list.load(bypassCache: true) }
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

struct PlannerDraftRoute: Hashable, Identifiable {
    let id: String
}

private struct DraftRow: View {
    let draft: PlannerDraftSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.name)
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
            Text(details)
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .padding(.vertical, ToolkitSpace.xs)
        .frame(minHeight: 44, alignment: .leading)
    }

    private var details: String {
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
