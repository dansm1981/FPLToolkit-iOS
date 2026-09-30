import SwiftUI

/// One draft for one gameweek: the pitch and bench, money, the rule check, chips and the
/// week's transfers. Everything shown is the server's answer (contract §13).
struct DraftView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: DraftModel

    init(id: String, repository: PlannerRepository) {
        _model = State(initialValue: DraftModel(id: id, repository: repository))
    }

    var body: some View {
        Group {
            switch model.resource.phase {
            case .loading:
                ScrollView {
                    SkeletonCards(caption: "Loading the draft…")
                        .padding(.horizontal, ToolkitSpace.page)
                }
            case .failed(let copy):
                ErrorStateView(copy: copy) { Task { await model.resource.retry() } }
            case .loaded(let loaded):
                DraftContent(draft: loaded.value, model: model)
            }
        }
        .task {
            LastDraft.remember(id: model.id, name: model.draft?.name)
            await model.load()
        }
        .onChange(of: model.draft?.name) { _, name in LastDraft.remember(id: model.id, name: name) }
        .toolkitScreen()
        .navigationTitle(model.draft?.name ?? "Draft")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DraftContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let draft: PlannerDraft
    let model: DraftModel
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                GameweekStepper(draft: draft, model: model)
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
                DraftStatusLine(draft: draft, onMoney: { editingMoney = true }, onSource: { showingPlanSource = true })
                if !draft.check.ok {
                    IssuesCard(issues: draft.check.issues)
                }
                if !draft.transfers.in.isEmpty || !draft.transfers.out.isEmpty {
                    WeekTransfers(draft: draft)
                }
                DraftTools(model: $fixtureModel, lens: $fixtureLens, draftModel: model,
                           chipLabels: Dictionary(uniqueKeysWithValues: draft.chips.map { ($0.key, $0.label) })) {
                    showingNews = true
                }
                if draft.isEditable && (model.canUndo || model.canRedo) {
                    UndoBar(model: model)
                }
                if typeSize.isAccessibilitySize {
                    SquadList(draft: draft, actions: actions)
                } else {
                    PitchCard(draft: draft, actions: actions)
                    BenchCard(draft: draft, actions: actions)
                }
                if !draft.isEditable {
                    Label("GW\(draft.gw) has passed. Plan from GW\(draft.firstEditableGw).", systemImage: "lock")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                ChipsSection(draft: draft, model: model)
                Footnotes(draft: draft, fixtures: FixtureView(model: fixtureModel, lens: fixtureLens))
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await model.resource.load(bypassCache: true) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.isApplying {
                    ProgressView().accessibilityLabel("Saving")
                }
                Menu { draftMenu } label: {
                    Label("Draft options", systemImage: "ellipsis")
                }
            }
        }
        .alert("Rename draft", isPresented: $renaming) {
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
                      message: "Changes here affect this draft only; your FPL team is unchanged. Make the real changes in FPL when you're ready. The squad you imported and the gameweek you're planning are kept separate.")
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
            Button("Reset draft", role: .destructive) { Task { await model.apply(.reset) } }
        } message: {
            Text("The draft goes back to the squad imported from FPL, and every planned week is cleared.")
        }
        .confirmationDialog("Delete \u{201C}\(draft.name)\u{201D}?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete draft", role: .destructive) {
                Task { if await model.delete() { dismiss() } }
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

    /// The website's draft toolbar as a menu: share, rename, budget, duplicate, reset, delete.
    @ViewBuilder
    private var draftMenu: some View {
        if let url = URL(string: draft.shareUrl) {
            ShareLink(item: url, subject: Text(draft.name), message: Text("My FPL plan")) {
                Label("Share link", systemImage: "link")
            }
        }
        ShareLink(item: DraftShareText.make(draft), subject: Text(draft.name)) {
            Label("Share as text", systemImage: "text.alignleft")
        }
        Divider()
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
                    notice = "Saved a copy: \u{201C}\(copy.name)\u{201D}. It's in your drafts."
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
        Divider()
        Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete draft…", systemImage: "trash")
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

private struct GameweekStepper: View {
    let draft: PlannerDraft
    let model: DraftModel

    var body: some View {
        let range = model.gwRange
        HStack(spacing: ToolkitSpace.md) {
            stepButton("chevron.left", label: "Previous gameweek", target: draft.gw - 1,
                       enabled: range.map { draft.gw > $0.lowerBound } ?? false)
            VStack(spacing: 2) {
                HStack(spacing: ToolkitSpace.sm) {
                    Text("GW\(draft.gw)")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                    if model.isStepping { ProgressView().controlSize(.small) }
                }
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            stepButton("chevron.right", label: "Next gameweek", target: draft.gw + 1,
                       enabled: range.map { draft.gw < $0.upperBound } ?? false)
        }
        .padding(.top, ToolkitSpace.sm)
    }

    private var caption: String {
        if draft.gw < draft.firstEditableGw { return "Starting squad, before the next deadline" }
        if draft.gw == draft.firstEditableGw { return "Next deadline" }
        return draft.ledger.contains { $0.gw == draft.gw && $0.transfers > 0 } ? "Planned week" : "Carried over"
    }

    private func stepButton(_ symbol: String, label: String, target: Int, enabled: Bool) -> some View {
        Button {
            Task { await model.show(gw: target) }
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(ToolkitColor.surface, in: Circle())
        }
        .foregroundStyle(enabled ? ToolkitColor.link : ToolkitColor.secondaryText)
        .disabled(!enabled || model.isStepping)
        .accessibilityLabel(label)
    }
}

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

private struct WeekTransfers: View {
    let draft: PlannerDraft

    var body: some View {
        let row = draft.ledger.first { $0.gw == draft.gw }
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Transfers this week")
                ForEach(Array(zip(draft.transfers.out, draft.transfers.in)), id: \.0) { out, inn in
                    HStack(spacing: ToolkitSpace.sm) {
                        Text(name(out)).foregroundStyle(ToolkitColor.secondaryText)
                        Image(systemName: "arrow.right").foregroundStyle(ToolkitColor.secondaryText).accessibilityHidden(true)
                        Text(name(inn)).foregroundStyle(ToolkitColor.primaryText).fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name(out)) out, \(name(inn)) in")
                }
                if let row {
                    Text(row.hits > 0 ? "\(row.transfers) transfers · \(row.hitPoints) points" : "\(row.transfers) of \(row.freeTransfers) free transfers")
                        .font(.footnote)
                        .foregroundStyle(row.hits > 0 ? ToolkitColor.warning : ToolkitColor.secondaryText)
                }
            }
        }
    }

    private func name(_ id: Int) -> String { draft.player(id)?.webName ?? "Player \(id)" }
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

/// Undo and redo beside the pitch (as on the website), each naming the change it takes back or
/// makes again: "Undo Salah → Palmer". VoiceOver hears "Undo" with the change as its value.
private struct UndoBar: View {
    let model: DraftModel

    var body: some View {
        HStack(spacing: 10) {
            Button { Task { await model.undo() } } label: {
                Label(model.undoSummary.map { "Undo \($0)" } ?? "Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(UndoButtonStyle())
            .disabled(!model.canUndo || model.isApplying)
            .accessibilityLabel("Undo")
            .accessibilityValue(model.undoSummary ?? "")
            Button { Task { await model.redo() } } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .buttonStyle(UndoButtonStyle())
            .disabled(!model.canRedo || model.isApplying)
            .accessibilityLabel("Redo")
            .accessibilityValue(model.redoSummary ?? "")
        }
    }
}

private struct UndoButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? ToolkitColor.primaryText : ToolkitColor.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .toolkitCard(radius: 12)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// "Plan only ⓘ · GW6 onwards" and "1 FT · £2.2m bank", with squad status when it isn't full.
private struct DraftStatusLine: View {
    let draft: PlannerDraft
    let onMoney: () -> Void
    let onSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ContextLine(lead: "Plan only", parts: ["GW\(draft.firstEditableGw) onwards"],
                            leadHint: "Explains that a plan doesn't change your FPL team", onInfo: onSource)
                Spacer(minLength: ToolkitSpace.sm)
                Button(action: onMoney) {
                    Text(summary)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(draft.money.bank < 0 ? ToolkitColor.error : ToolkitColor.link)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(spokenFreeTransfers), \(Format.price(draft.money.bank)) in the bank")
                .accessibilityHint("Opens the budget")
            }
            if draft.check.players < 15 {
                Text("\(draft.check.players) of 15 players")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
    }

    private var summary: String {
        let ft = draft.freeTransfersThisWeek.map { "\($0)\(draft.freeTransfers.estimated ? "*" : "") FT · " } ?? ""
        return ft + "\(Format.price(draft.money.bank)) bank"
    }

    private var spokenFreeTransfers: String {
        guard let ft = draft.freeTransfersThisWeek else { return "Free transfers unknown" }
        return "\(ft) free transfer\(ft == 1 ? "" : "s")\(draft.freeTransfers.estimated ? ", estimated" : "")"
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

private struct ChipsSection: View {
    let draft: PlannerDraft
    let model: DraftModel

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Chips")
            ForEach(draft.chips) { chip in
                if let verb = verb(chip) {
                    Button {
                        Task { await model.apply(.chip(chip.key, gw: draft.gw)) }
                    } label: {
                        row(chip, verb: verb)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isApplying)
                    .accessibilityHint(chip.state == .active
                                       ? "Cancels \(chip.label) in GW\(draft.gw)"
                                       : "Plays \(chip.label) in GW\(draft.gw)")
                } else {
                    row(chip, verb: nil)
                }
            }
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

    private func row(_ chip: PlannerDraft.Chip, verb: String?) -> some View {
        HStack(spacing: ToolkitSpace.md) {
            Image(systemName: symbol(chip.state))
                .foregroundStyle(tint(chip.state))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(chip.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                Text(status(chip))
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ToolkitSpace.sm)
            if let verb {
                Text(verb)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func status(_ chip: PlannerDraft.Chip) -> String {
        switch chip.state {
        case .active: "Playing in GW\(draft.gw)"
        case .available: chip.window.map { "Available (GW\($0.start)–\($0.end))" } ?? "Available"
        default: chip.note ?? ""
        }
    }

    private func symbol(_ state: PlannerDraft.Chip.State) -> String {
        switch state {
        case .active: "checkmark.circle.fill"
        case .available: "circle"
        case .played: "checkmark.circle"
        case .blocked, .outside, .unknown: "minus.circle"
        }
    }

    private func tint(_ state: PlannerDraft.Chip.State) -> Color {
        switch state {
        case .active: ToolkitColor.accent
        case .available: ToolkitColor.link
        default: ToolkitColor.secondaryText
        }
    }
}

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
            Text("Plans use today's prices and your squad's fixtures. There are no points forecasts.")
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

/// The website's fixture switches (model and lens), Team news, Squad rotation and the transfer
/// timeline, above the pitch.
private struct DraftTools: View {
    @Binding var model: FixtureView.Model
    @Binding var lens: FixtureView.Lens
    let draftModel: DraftModel
    let chipLabels: [String: String]
    let onNews: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ToolkitSpace.md) {
                    fixtureMenu
                    Spacer(minLength: 0)
                    newsButton
                }
                VStack(alignment: .leading, spacing: 0) {
                    fixtureMenu
                    newsButton
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ToolkitSpace.md) {
                    rotationLink
                    Spacer(minLength: 0)
                    timelineLink
                }
                VStack(alignment: .leading, spacing: 0) {
                    rotationLink
                    timelineLink
                }
            }
            shortlistLink
        }
    }

    private var shortlistLink: some View {
        NavigationLink {
            ShortlistView(draftModel: draftModel)
        } label: {
            Label("Shortlist", systemImage: "star")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
    }

    private var rotationLink: some View {
        NavigationLink {
            SquadRotationView { try await draftModel.evolution() }
        } label: {
            Label("Squad rotation", systemImage: "square.grid.3x3")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
    }

    private var timelineLink: some View {
        NavigationLink {
            DraftPlanView(model: draftModel, chipLabels: chipLabels)
        } label: {
            Label("Transfer timeline", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
    }

    private var fixtureMenu: some View {
        Menu {
            Picker("Fixture model", selection: $model) {
                ForEach(FixtureView.Model.allCases) { Text($0.label).tag($0) }
            }
            if model == .xfdr {
                Picker("View", selection: $lens) {
                    ForEach(FixtureView.Lens.allCases) { Text($0.label).tag($0) }
                }
            }
        } label: {
            Label(FixtureView(model: model, lens: lens).summary, systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Fixture difficulty: \(FixtureView(model: model, lens: lens).summary)")
        .accessibilityHint("Chooses FPL's difficulty or xFDR, and the xFDR view")
    }

    private var newsButton: some View {
        Button(action: onNews) {
            Label("Team news", systemImage: "newspaper")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
    }
}
