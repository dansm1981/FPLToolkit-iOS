import SwiftUI

/// How a plan's squad is shown (concept 01): the pitch, a list, or each player's next fixtures.
enum PlanLayout: String, CaseIterable, Identifiable {
    case pitch = "Pitch", list = "List", fixtures = "Fixtures"
    var id: String { rawValue }
}

/// One plan, as the Planner tab's workspace (Dan's concept, 5 Oct 2026: "One workspace, different
/// plans. The squad is the starting point."): the plan's name to switch plans, the gameweek with
/// its deadline, free transfers and bank, the squad as a pitch, list or fixtures, the chip, and the
/// week's transfers. Everything shown is the server's answer (contract §13).
struct DraftView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: DraftModel
    /// Opens the plan switcher.
    let onSwitch: () -> Void
    /// The plan was deleted: the Planner picks another.
    let onDeleted: () -> Void

    init(id: String, repository: PlannerRepository, onSwitch: @escaping () -> Void, onDeleted: @escaping () -> Void) {
        _model = State(initialValue: DraftModel(id: id, repository: repository))
        self.onSwitch = onSwitch
        self.onDeleted = onDeleted
    }

    var body: some View {
        Group {
            switch model.resource.phase {
            case .loading:
                ScrollView {
                    SkeletonCards(caption: "Loading your plan…")
                        .padding(.horizontal, ToolkitSpace.page)
                }
            case .failed(let copy):
                ErrorStateView(copy: copy) { Task { await model.resource.retry() } }
            case .loaded(let loaded):
                DraftContent(draft: loaded.value, model: model, onSwitch: onSwitch, onDeleted: onDeleted)
            }
        }
        .task {
            LastDraft.remember(id: model.id, name: model.draft?.name)
            await model.load()
        }
        .onChange(of: model.draft?.name) { _, name in LastDraft.remember(id: model.id, name: name) }
    }
}

private struct DraftContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let draft: PlannerDraft
    let model: DraftModel
    let onSwitch: () -> Void
    let onDeleted: () -> Void
    /// The player whose menu is open.
    @State private var menuFor: PlannerDraft.Pick?
    @State private var pickerSlot: PickerSlot?
    @State private var renaming = false
    @State private var newName = ""
    @State private var editingMoney = false
    @State private var confirmingReset = false
    @State private var confirmingDelete = false
    /// A line to confirm something done off-screen, e.g. a copy saved.
    @State private var notice: String?
    @State private var showingNews = false
    /// The player tapped in Team news, opened once the sheet has closed.
    @State private var newsPlayer: Int?
    @State private var showingPlanSource = false
    @State private var showingFdrInfo = false
    @State private var showingRotation = false
    @State private var showingTimeline = false
    @State private var showingShortlist = false
    @AppStorage("planner.layout") private var layout: PlanLayout = .pitch
    @AppStorage(FixtureView.modelKey) private var fixtureModel = FixtureView.Model.xfdr
    @AppStorage(FixtureView.lensKey) private var fixtureLens = FixtureView.Lens.position

    private var actions: TileActions {
        TileActions(
            highlighted: model.swapFrom,
            tap: { pick in tapped(pick) },
            add: draft.isEditable ? { position, onBench in
                pickerSlot = PickerSlot(position: position, replacing: nil, onBench: onBench)
            } : nil
        )
    }

    private var chipLabels: [String: String] {
        Dictionary(uniqueKeysWithValues: draft.chips.map { ($0.key, $0.label) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                PlanHeader(draft: draft, model: model, onSwitch: onSwitch, onSource: { showingPlanSource = true }) {
                    draftMenu
                }
                PlanWeekCard(draft: draft, model: model, onMoney: { editingMoney = true })
                SavedDataBanner(resource: model.resource)
                if let error = model.stepError {
                    ErrorBanner(copy: error)
                }
                if let error = model.actionError {
                    ErrorBanner(copy: error)
                }
                if let error = appModel.starError {
                    ErrorBanner(copy: ErrorCopy(title: "Couldn't change your shortlist",
                                                message: error.title, canRetry: error.canRetry))
                }
                if let notice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.positive)
                }
                if let from = model.swapFrom {
                    SwapBanner(name: draft.player(from)?.webName ?? "this player") { model.swapFrom = nil }
                }
                if !draft.check.ok {
                    IssuesCard(issues: draft.check.issues)
                }
                Picker("Show the squad as", selection: $layout) {
                    ForEach(PlanLayout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch layout {
                case .pitch:
                    if typeSize.isAccessibilitySize {
                        SquadList(draft: draft, actions: actions)
                    } else {
                        PitchCard(draft: draft, actions: actions)
                        BenchCard(draft: draft, actions: actions)
                    }
                case .list:
                    SquadList(draft: draft, actions: actions)
                case .fixtures:
                    SquadFixturesView(members: (draft.starting + draft.bench).compactMap { pick in
                        draft.player(pick.playerId).map { SquadFixturesView.Member(player: $0, onBench: draft.bench.contains(pick)) }
                    }, model: $fixtureModel, lens: $fixtureLens,
                    onInfo: { showingFdrInfo = true },
                    onPlayer: { id in appModel.router.openPlayer(id) })
                }
                if !draft.isEditable {
                    Label("GW\(draft.gw) has passed. Plan from GW\(draft.firstEditableGw).", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                PlanChipRow(draft: draft, model: model)
                PlanTransfersRow(draft: draft) { showingTimeline = true }
                Footnotes(draft: draft, fixtures: FixtureView(model: fixtureModel, lens: fixtureLens))
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await model.resource.load(bypassCache: true) }
        .navigationDestination(isPresented: $showingRotation) {
            SquadRotationView { try await model.evolution() }
        }
        .navigationDestination(isPresented: $showingTimeline) {
            DraftPlanView(model: model, chipLabels: chipLabels)
        }
        .navigationDestination(isPresented: $showingShortlist) {
            ShortlistView(draftModel: model)
        }
        .alert("Rename plan", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, name != draft.name {
                    Task { await model.update(PlannerDraftPatch(name: name)) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $editingMoney) {
            DraftMoneySheet(draft: draft, model: model)
        }
        .sheet(isPresented: $showingPlanSource) {
            InfoSheet(title: "A plan, not an FPL submission",
                      message: "Changes here affect this plan only; your FPL team is unchanged. Make the real changes in FPL when you're ready. The squad you started from and the gameweek you're planning are kept separate.")
        }
        .sheet(isPresented: $showingFdrInfo) {
            InfoSheet(title: "Fixture difficulty", message: TeamText.fdrMessage)
        }
        .sheet(isPresented: $showingNews, onDismiss: {
            if let id = newsPlayer {
                newsPlayer = nil
                appModel.router.openPlayer(id)
            }
        }) {
            DraftNewsSheet(gw: draft.gw, model: model) { newsPlayer = $0 }
        }
        // A new fixture model or lens: the server re-rates this gameweek.
        .task { await appModel.shortlist.loadIfNeeded() }
        .onChange(of: fixtureModel) { Task { await model.reload() } }
        .onChange(of: fixtureLens) { Task { await model.reload() } }
        .confirmationDialog("Reset to your FPL squad?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset plan", role: .destructive) { Task { await model.apply(.reset) } }
        } message: {
            Text("The plan goes back to the squad imported from FPL, and every planned week is cleared.")
        }
        .confirmationDialog("Delete \u{201C}\(draft.name)\u{201D}?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete plan", role: .destructive) {
                Task { if await model.delete() { onDeleted() } }
            }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog(
            menuFor.flatMap { draft.player($0.playerId)?.webName } ?? "Player",
            isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }),
            titleVisibility: .visible,
            presenting: menuFor
        ) { pick in
            menu(for: pick)
        }
        .sheet(item: $pickerSlot) { slot in
            PlannerPickerView(draft: draft, slot: slot, model: model)
        }
    }

    /// ⋯: the plan's tools (concept 01 keeps them off the screen) and the website's draft toolbar.
    @ViewBuilder
    private var draftMenu: some View {
        Section {
            Button { showingNews = true } label: { Label("Team news", systemImage: "newspaper") }
            Button { showingRotation = true } label: { Label("Squad rotation", systemImage: "square.grid.3x3") }
            Button { showingTimeline = true } label: { Label("Transfer timeline", systemImage: "calendar") }
            Button { showingShortlist = true } label: { Label("Shortlist", systemImage: "star") }
            Menu {
                Picker("Fixture model", selection: $fixtureModel) {
                    ForEach(FixtureView.Model.allCases) { Text($0.label).tag($0) }
                }
                if fixtureModel == .xfdr {
                    Picker("View", selection: $fixtureLens) {
                        ForEach(FixtureView.Lens.allCases) { Text($0.label).tag($0) }
                    }
                }
            } label: {
                Label("Fixture difficulty: \(FixtureView(model: fixtureModel, lens: fixtureLens).summary)", systemImage: "slider.horizontal.3")
            }
        }
        if model.canRedo {
            Button { Task { await model.redo() } } label: {
                Label(model.redoSummary.map { "Redo \($0)" } ?? "Redo", systemImage: "arrow.uturn.forward")
            }
        }
        Section {
            if let url = URL(string: draft.shareUrl) {
                ShareLink(item: url, subject: Text(draft.name), message: Text("My FPL plan")) {
                    Label("Share link", systemImage: "link")
                }
            }
            ShareLink(item: DraftShareText.make(draft), subject: Text(draft.name)) {
                Label("Share as text", systemImage: "text.alignleft")
            }
        }
        Section {
            Button {
                newName = draft.name
                renaming = true
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button { editingMoney = true } label: {
                Label("Bank and free transfers…", systemImage: "sterlingsign.circle")
            }
            Button {
                Task {
                    notice = nil
                    if let copy = await model.duplicate() {
                        notice = "Saved a copy: \u{201C}\(copy.name)\u{201D}. Switch to it from the plan's name."
                    }
                }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            if draft.entryId != nil {
                Button { confirmingReset = true } label: {
                    Label("Reset to FPL squad…", systemImage: "arrow.counterclockwise")
                }
            }
        }
        Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete plan…", systemImage: "trash")
        }
    }

    private func tapped(_ pick: PlannerDraft.Pick) {
        guard draft.isEditable else {
            appModel.router.openPlayer(pick.playerId)
            return
        }
        if let from = model.swapFrom {
            model.swapFrom = nil
            if from != pick.playerId {
                Task { await model.apply(.swap(from, with: pick.playerId, gw: draft.gw)) }
            }
            return
        }
        model.clearActionError()
        menuFor = pick
    }

    /// The website's player menu: captain, vice, replace, swap, watch, remove, and the player page.
    @ViewBuilder
    private func menu(for pick: PlannerDraft.Pick) -> some View {
        let onBench = draft.bench.contains(pick)
        let position = draft.player(pick.playerId)?.position ?? .unknown
        if !onBench && !pick.isCaptain {
            Button("Make captain") { Task { await model.apply(.captain(pick.playerId, gw: draft.gw)) } }
        }
        if !onBench && !pick.isVice {
            Button("Make vice-captain") { Task { await model.apply(.vice(pick.playerId, gw: draft.gw)) } }
        }
        Button("Replace…") {
            pickerSlot = PickerSlot(position: position, replacing: pick, onBench: onBench)
        }
        Button("Swap with…") { model.swapFrom = pick.playerId }
        // One list since batch 3: shortlisted players are watched for alerts.
        let starred = appModel.isStarred(pick.playerId)
        Button(starred ? "Remove from shortlist" : "Add to shortlist") {
            Task { await appModel.toggleStar(pick.playerId) }
        }
        Button("View player") { appModel.router.openPlayer(pick.playerId) }
        Button("Remove from squad", role: .destructive) {
            Task { await model.apply(.remove(pick.playerId, gw: draft.gw)) }
        }
    }
}

// MARK: - Workspace header, week, chip and transfers (concept 01)

/// "My plan ▾" with undo and ⋯, and "Draft · based on GW5 ⓘ".
private struct PlanHeader<MenuContent: View>: View {
    let draft: PlannerDraft
    let model: DraftModel
    let onSwitch: () -> Void
    let onSource: () -> Void
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: ToolkitSpace.sm) {
                Button(action: onSwitch) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(draft.name)
                            .font(.title.weight(.bold))
                            .foregroundStyle(ToolkitColor.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ToolkitColor.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plan: \(draft.name)")
                .accessibilityHint("Switch plan, start a new one, or open your FPL team")
                Spacer(minLength: ToolkitSpace.sm)
                if model.isApplying {
                    ProgressView().accessibilityLabel("Saving")
                }
                Button { Task { await model.undo() } } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.canUndo ? ToolkitColor.primaryText : ToolkitColor.secondaryText)
                .disabled(!model.canUndo || model.isApplying)
                .accessibilityLabel("Undo")
                .accessibilityValue(model.undoSummary ?? "")
                Menu { menu() } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Plan options")
            }
            Button(action: onSource) {
                HStack(spacing: 4) {
                    Text(origin)
                    Image(systemName: "info.circle").imageScale(.small).accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Explains that a plan doesn't change your FPL team")
        }
    }

    /// "Draft · based on GW5", "Draft · from scratch".
    private var origin: String {
        draft.entryId != nil ? "Draft · based on GW\(max(1, draft.firstEditableGw - 1))" : "Draft · from scratch"
    }
}

/// The gameweek card: ◀ GW6 ▶ with the deadline, then free transfers and the bank.
private struct PlanWeekCard: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let draft: PlannerDraft
    let model: DraftModel
    let onMoney: () -> Void

    var body: some View {
        let range = model.gwRange
        let rows = typeSize.stacksRows
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: ToolkitSpace.sm))
        VStack(alignment: .leading, spacing: 4) {
            rows {
                HStack(spacing: 0) {
                    step("chevron.left", label: "Previous gameweek", target: draft.gw - 1,
                         enabled: range.map { draft.gw > $0.lowerBound } ?? false)
                    Text("GW\(draft.gw)")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                        .accessibilityLabel("Gameweek \(draft.gw)")
                    step("chevron.right", label: "Next gameweek", target: draft.gw + 1,
                         enabled: range.map { draft.gw < $0.upperBound } ?? false)
                    if model.isStepping { ProgressView().controlSize(.small).padding(.leading, 4) }
                }
                if !typeSize.stacksRows { Spacer(minLength: ToolkitSpace.sm) }
                Text(when)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            rows {
                Text(freeTransfers)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                if !typeSize.stacksRows { Spacer(minLength: ToolkitSpace.sm) }
                Button(action: onMoney) {
                    Text("\(Format.price(draft.money.bank)) bank")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(draft.money.bank < 0 ? ToolkitColor.error : ToolkitColor.primaryText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Format.price(draft.money.bank)) in the bank")
                .accessibilityHint("Opens the budget")
            }
            if draft.check.players < 15 {
                Text("\(draft.check.players) of 15 players")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.warning)
            }
        }
        .padding(.horizontal, ToolkitSpace.md)
        .padding(.vertical, ToolkitSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    /// The next deadline for the first plannable week; later weeks say what they hold.
    private var when: String {
        if draft.gw < draft.firstEditableGw { return "Starting squad" }
        if draft.gw == draft.firstEditableGw, let next = appModel.bootstrap?.value.gameweek.next, next.id == draft.gw {
            return Format.deadline(next.deadline)
        }
        if draft.gw == draft.firstEditableGw { return "Next deadline" }
        return draft.ledger.contains { $0.gw == draft.gw && $0.transfers > 0 } ? "Planned week" : "Carried over"
    }

    /// "1 FT · estimated", "2 FT", "Free transfers unknown".
    private var freeTransfers: String {
        guard let ft = draft.freeTransfersThisWeek else { return "Free transfers unknown" }
        return "\(ft) FT\(draft.freeTransfers.estimated ? " · estimated" : "")"
    }

    private func step(_ symbol: String, label: String, target: Int, enabled: Bool) -> some View {
        Button {
            Task { await model.show(gw: target) }
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? ToolkitColor.accent : ToolkitColor.secondaryText)
        .disabled(!enabled || model.isStepping)
        .accessibilityLabel(label)
    }
}

/// "Chip: None ▾" (play or cancel this week's chip) and whether the plan is saved.
private struct PlanChipRow: View {
    let draft: PlannerDraft
    let model: DraftModel

    var body: some View {
        let active = draft.chips.first { $0.state == .active }
        HStack(alignment: .center, spacing: ToolkitSpace.sm) {
            Menu {
                ForEach(draft.chips) { chip in
                    if let verb = verb(chip) {
                        Button("\(verb) \(chip.label)") {
                            Task { await model.apply(.chip(chip.key, gw: draft.gw)) }
                        }
                    } else {
                        Button("\(chip.label): \(status(chip))") {}
                            .disabled(true)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Chip: \(active?.label ?? "None")")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.accent)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(model.isApplying)
            .accessibilityLabel("Chip: \(active?.label ?? "none")")
            .accessibilityHint("Plays or cancels a chip in GW\(draft.gw)")
            Spacer(minLength: ToolkitSpace.sm)
            Text(model.isApplying ? "Saving…" : model.actionError != nil ? "Not saved" : "Saved")
                .font(.subheadline)
                .foregroundStyle(model.actionError != nil ? ToolkitColor.error : ToolkitColor.secondaryText)
        }
    }

    /// "Play" or "Cancel" when the chip can change this week; nil when it can't.
    private func verb(_ chip: PlannerDraft.Chip) -> String? {
        guard draft.isEditable else { return nil }
        switch chip.state {
        case .available: return "Play"
        case .active: return "Cancel"
        default: return nil
        }
    }

    private func status(_ chip: PlannerDraft.Chip) -> String {
        switch chip.state {
        case .active: "Playing in GW\(draft.gw)"
        case .available: chip.window.map { "Available (GW\($0.start)–\($0.end))" } ?? "Available"
        default: chip.note ?? "Not available"
        }
    }
}

/// The week's transfers in one row ("Calafiori → Saliba · 1 transfer ›"), opening the timeline.
private struct PlanTransfersRow: View {
    let draft: PlannerDraft
    let open: () -> Void

    var body: some View {
        let pairs = Array(zip(draft.transfers.out, draft.transfers.in))
        let row = draft.ledger.first { $0.gw == draft.gw }
        Button(action: open) {
            HStack(spacing: ToolkitSpace.md) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(ToolkitColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pairs.isEmpty ? "No transfers in GW\(draft.gw)" : pairs.map { "\(name($0.0)) → \(name($0.1))" }.joined(separator: ", "))
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail(count: pairs.count, row: row))
                        .font(.subheadline)
                        .foregroundStyle(row.map { $0.hits > 0 } == true ? ToolkitColor.warning : ToolkitColor.secondaryText)
                }
                Spacer(minLength: ToolkitSpace.sm)
                Image(systemName: "chevron.right")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(ToolkitSpace.md)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the transfer timeline")
    }

    private func detail(count: Int, row: PlannerDraft.LedgerRow?) -> String {
        guard count > 0 else { return "Transfer timeline" }
        let transfers = "\(count) transfer\(count == 1 ? "" : "s")"
        if let row, row.hits > 0 { return "\(transfers) · −\(row.hitPoints) pts" }
        return transfers
    }

    private func name(_ id: Int) -> String { draft.player(id)?.webName ?? "Player \(id)" }
}

/// What tapping the pitch does: a player opens his menu (or completes a swap), an empty place
/// opens the picker. `add` is nil when the gameweek can't be edited.
struct TileActions {
    var highlighted: Int?
    var tap: (PlannerDraft.Pick) -> Void
    var add: ((Position, Bool) -> Void)?
}

private struct SwapBanner: View {
    let name: String
    let cancel: () -> Void

    var body: some View {
        ToolkitCard {
            HStack(spacing: ToolkitSpace.md) {
                Label("Tap the player to swap with \(name)", systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ToolkitSpace.sm)
                // The frame goes on the label: outside it, the tappable area stays the text's height.
                Button(action: cancel) {
                    Text("Cancel")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
    }
}

// MARK: - Gameweek

// MARK: - Money and rules

private struct IssuesCard: View {
    let issues: [String]

    var body: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                Label("Squad rules", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.warning)
                ForEach(issues, id: \.self) { issue in
                    Text(issue)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.primaryText)
                }
            }
        }
    }
}

// MARK: - Pitch

/// The draft's XI on the shared pitch (design pack p.15): the same tiles as Team, with empty
/// places to fill while the squad is being built.
private struct PitchCard: View {
    @Environment(AppModel.self) private var appModel
    let draft: PlannerDraft
    let actions: TileActions

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            HStack {
                Text("This week's fixtures · xFDR")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                Spacer()
                Text(draft.formation)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityLabel("Formation \(draft.formation)")
            }
            VStack(spacing: 10) {
                ForEach(draft.rows(), id: \.position) { row in
                    TileRowLayout {
                        ForEach(row.picks) { pick in
                            Button { actions.tap(pick) } label: {
                                PitchTile(model: DraftTile.model(pick, draft: draft, appModel: appModel),
                                          highlighted: actions.highlighted == pick.playerId)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(draft.isEditable ? "Shows what you can do with this player" : "Opens the player")
                            .accessibilityAddTraits(actions.highlighted == pick.playerId ? [.isButton, .isSelected] : .isButton)
                        }
                        ForEach(0..<row.empty, id: \.self) { _ in
                            EmptyPitchTile(position: row.position, onTap: actions.add.map { add in { add(row.position, false) } })
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(PitchBackground())
            .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.pitchLine))
        }
    }
}

private struct BenchCard: View {
    @Environment(AppModel.self) private var appModel
    let draft: PlannerDraft
    let actions: TileActions

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Bench")
                Spacer()
                Text("GK · 1 · 2 · 3")
                    .accessibilityLabel("Goalkeeper, then substitutes 1, 2 and 3")
            }
            .font(.caption2.weight(.semibold))
            .tracking(1)
            .foregroundStyle(ToolkitColor.secondaryText)
            TileRowLayout {
                ForEach(draft.bench) { pick in
                    Button { actions.tap(pick) } label: {
                        PitchTile(model: DraftTile.model(pick, draft: draft, appModel: appModel), height: 83, onBench: true,
                                  highlighted: actions.highlighted == pick.playerId)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(draft.isEditable ? "Shows what you can do with this player" : "Opens the player")
                    .accessibilityAddTraits(actions.highlighted == pick.playerId ? [.isButton, .isSelected] : .isButton)
                }
                ForEach(PlannerDraft.pitchOrder, id: \.self) { position in
                    ForEach(0..<draft.emptyBench(position), id: \.self) { _ in
                        EmptyPitchTile(position: position, height: 83, onBench: true,
                                       onTap: actions.add.map { add in { add(position, true) } })
                    }
                }
            }
        }
        .padding(9)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A draft pick as a pitch tile: this gameweek's opponent and xFDR, captaincy and availability.
enum DraftTile {
    @MainActor
    static func model(_ pick: PlannerDraft.Pick, draft: PlannerDraft, appModel: AppModel) -> PitchTileModel {
        let player = draft.player(pick.playerId)
        let fixtures = draft.fixtures(for: pick.playerId)
        let real = fixtures.filter { !$0.blank }
        let metric: PitchTileModel.Metric
        if fixtures.isEmpty {
            metric = .text("–")
        } else if real.isEmpty {
            metric = .text("No fixture")
        } else {
            let first = real[0]
            let label = (appModel.club(first.opponentClubId)?.shortName ?? "TBC") + (first.home.map { $0 ? " H" : " A" } ?? "")
            metric = .fixture(label: real.count > 1 ? label + " +\(real.count - 1)" : label,
                              value: real.count > 1 ? nil : first.xfdr?.display,
                              tone: DifficultyTone(band: draft.strip(for: pick.playerId).first?.band ?? first.xfdr?.band))
        }
        var spoken = [player?.webName ?? "Player \(pick.playerId)"]
        if pick.isCaptain { spoken.append("captain") }
        if pick.isVice { spoken.append("vice-captain") }
        if let club = player.flatMap({ appModel.club($0.clubId)?.name }) { spoken.append(club) }
        if let player { spoken.append(Format.price(player.price)) }
        if let a = player?.availability, a.level == .doubt || a.level == .out {
            spoken.append(a.chanceNext.map { "\($0) percent chance of playing" } ?? (a.level == .out ? "out" : "doubtful"))
        }
        if !fixtures.isEmpty && real.isEmpty { spoken.append("no fixture this gameweek") }
        for f in real {
            let name = appModel.club(f.opponentClubId)?.name ?? "opponent to be confirmed"
            let venue = f.home.map { $0 ? "at home" : "away" } ?? ""
            spoken.append("\(name) \(venue)" + (f.xfdr.map { ", \($0.modelLabel) \($0.display)" } ?? ""))
        }
        let strip = draft.strip(for: pick.playerId)
        if let upcoming = FixtureStrip.spoken(strip) { spoken.append(upcoming) }
        let status: PitchTileModel.Status = switch player?.availability.level {
        case .out: .out
        case .doubt: .doubtful
        default: .available
        }
        return PitchTileModel(playerId: pick.playerId, name: player?.webName ?? "Player", colors: appModel.club(player?.clubId)?.colors,
                              isGoalkeeper: player?.position == .gk, photo: player?.photo,
                              role: pick.isCaptain ? "C" : pick.isVice ? "V" : nil, status: status, metric: metric,
                              run: strip.map { week in
                                  .init(gw: week.gw, bands: week.fixtures.filter { !$0.blank }.map { $0.xfdr?.band ?? week.band })
                              },
                              accessibilityLabel: spoken.joined(separator: ", "))
    }
}

/// A player on the pitch: photo, name, captaincy, availability, this gameweek's opponent and xFDR.
struct PlannerTile: View {
    @Environment(AppModel.self) private var appModel
    // The circle and badge grow with the text size, so their text is never cut off.
    @ScaledMetric(relativeTo: .caption) private var circle: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var badge: CGFloat = 20
    let pick: PlannerDraft.Pick
    let draft: PlannerDraft
    /// The player chosen with "Swap with…".
    var highlighted = false
    /// A full-width row (circle beside the text) for the list shown at accessibility sizes.
    var asRow = false
    var onTap: () -> Void

    var body: some View {
        let player = draft.player(pick.playerId)
        Button(action: onTap) {
            if asRow {
                HStack(spacing: ToolkitSpace.md) {
                    marker(player)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player?.webName ?? "Player \(pick.playerId)")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(fixtureText)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                        FixtureStrip(weeks: strip, roomy: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            } else {
                VStack(spacing: 3) {
                    marker(player)
                    // Never shrunk or cut: larger text sizes wrap instead.
                    Text(player?.webName ?? "Player \(pick.playerId)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(fixtureText)
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    FixtureStrip(weeks: strip)
                }
                .frame(maxWidth: max(76, circle + 24))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(player))
        .accessibilityHint(draft.isEditable ? "Shows what you can do with this player" : "Opens the player")
        // Combining the tile into one element drops the button role; put it back.
        .accessibilityAddTraits(highlighted ? [.isButton, .isSelected] : .isButton)
    }

    /// The player's photo in a circle, or the club's short name when there isn't one; ringed
    /// when doubtful or out, with the C / V badge.
    private func marker(_ player: PlayerSummary?) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let photo = player?.photo {
                    PlayerPhoto(path: photo, size: circle, scalesWithText: false)
                } else {
                    Text(club(player?.clubId) ?? "–")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .frame(width: circle, height: circle)
                        .background(ToolkitColor.raised, in: Circle())
                }
            }
                .overlay(Circle().strokeBorder(availabilityColor(player), lineWidth: 2))
                .overlay(Circle().strokeBorder(highlighted ? ToolkitColor.accent : .clear, lineWidth: 3).padding(-4))
            if pick.isCaptain || pick.isVice {
                Text(pick.isCaptain ? "C" : "V")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(ToolkitColor.onAccent)
                    .frame(width: badge, height: badge)
                    .background(ToolkitColor.accent, in: Circle())
                    .offset(x: 6, y: -4)
            }
        }
    }

    private func club(_ id: Int?) -> String? { id.flatMap { appModel.club($0)?.shortName } }

    private func availabilityColor(_ player: PlayerSummary?) -> Color {
        switch player?.availability.level {
        case .out: ToolkitColor.error
        case .doubt: ToolkitColor.warning
        default: .clear
        }
    }

    private var fixtures: [FixtureDifficulty] { draft.fixtures(for: pick.playerId) }
    private var strip: [PlannerDraft.StripWeek] { draft.strip(for: pick.playerId) }

    private var fixtureText: String {
        guard let first = fixtures.first else { return "" }
        if first.blank { return "No game" }
        let opponents = fixtures.map { f -> String in
            let name = appModel.club(f.opponentClubId)?.shortName ?? "TBC"
            return f.home.map { "\(name) (\($0 ? "H" : "A"))" } ?? name
        }
        return opponents.joined(separator: " + ")
    }

    private func accessibilityText(_ player: PlayerSummary?) -> String {
        var parts = [player?.webName ?? "Player \(pick.playerId)"]
        if pick.isCaptain { parts.append("captain") }
        if pick.isVice { parts.append("vice-captain") }
        if let club = player.flatMap({ appModel.club($0.clubId)?.name }) { parts.append(club) }
        if let player { parts.append(Format.price(player.price)) }
        if let availability = player?.availability, availability.level == .doubt || availability.level == .out {
            parts.append(availability.chanceNext.map { "\($0) percent chance of playing" } ?? (availability.level == .out ? "out" : "doubtful"))
        }
        if let first = fixtures.first {
            if first.blank {
                parts.append("no fixture this gameweek")
            } else {
                for f in fixtures {
                    let name = appModel.club(f.opponentClubId)?.name ?? "opponent to be confirmed"
                    let venue = f.home.map { $0 ? "at home" : "away" } ?? ""
                    let difficulty = f.xfdr.map { ", difficulty \($0.display) out of 5" } ?? ""
                    parts.append("\(name) \(venue)\(difficulty)")
                }
            }
        }
        if let upcoming = FixtureStrip.spoken(strip) { parts.append(upcoming) }
        return parts.joined(separator: ", ")
    }
}

private struct EmptyTile: View {
    @ScaledMetric(relativeTo: .caption) private var circle: CGFloat = 44
    let position: Position
    /// Opens the picker; nil when the gameweek can't be edited.
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(onTap == nil ? ToolkitColor.secondaryText : ToolkitColor.link)
                    .frame(width: circle, height: circle)
                    .overlay(Circle().strokeBorder(onTap == nil ? ToolkitColor.border : ToolkitColor.link,
                                                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                Text(position.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .frame(maxWidth: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel("Add a \(position.spokenName)")
    }
}

/// At accessibility text sizes the pitch becomes a list, so nothing is squeezed.
private struct SquadList: View {
    let draft: PlannerDraft
    let actions: TileActions

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            SectionLabel(text: "Starting XI · \(draft.formation)")
            ForEach(draft.rows(), id: \.position) { row in
                ForEach(row.picks) { pick in
                    PlannerTile(pick: pick, draft: draft, highlighted: actions.highlighted == pick.playerId, asRow: true) {
                        actions.tap(pick)
                    }
                }
                if row.empty > 0, let add = actions.add {
                    Button("Add a \(row.position.spokenName)") { add(row.position, false) }
                        .buttonStyle(ToolkitSecondaryButtonStyle())
                }
            }
            SectionLabel(text: "Bench")
            ForEach(draft.bench) { pick in
                PlannerTile(pick: pick, draft: draft, highlighted: actions.highlighted == pick.playerId, asRow: true) {
                    actions.tap(pick)
                }
            }
            ForEach(PlannerDraft.pitchOrder, id: \.self) { position in
                if draft.emptyBench(position) > 0, let add = actions.add {
                    Button("Add a \(position.spokenName) to the bench") { add(position, true) }
                        .buttonStyle(ToolkitSecondaryButtonStyle())
                }
            }
        }
    }
}

// MARK: - Chips and notes

private struct Footnotes: View {
    let draft: PlannerDraft
    let fixtures: FixtureView

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            if draft.freeTransfers.estimated {
                Text("*Free transfers are estimated from your FPL history.")
            }
            if draft.estimatedPurchasePrices {
                Text("Some purchase prices are estimates, so selling prices may be slightly out.")
            }
            if draft.fixtureStrip != nil {
                Text("The strip under each player is the next six gameweeks' difficulty (\(fixtures.summary)), from 1 (easiest) to 5 (hardest). An outlined week has two games.")
            }
            Text("Plans use today's prices and your squad's fixtures. Each player's projected points are on the Projections tab.")
        }
        .font(.footnote)
        .foregroundStyle(ToolkitColor.secondaryText)
    }
}

extension Position {
    var spokenName: String {
        switch self {
        case .gk: "goalkeeper"
        case .def: "defender"
        case .mid: "midfielder"
        case .fwd: "forward"
        case .unknown: "player"
        }
    }
}

