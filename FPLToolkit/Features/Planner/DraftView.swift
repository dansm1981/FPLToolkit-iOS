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
        .task { await model.load() }
        .toolkitScreen()
        .navigationTitle(model.draft?.name ?? "Draft")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let draft = model.draft, let url = URL(string: draft.shareUrl) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url, subject: Text(draft.name), message: Text("My FPL plan")) {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityLabel("Share this plan")
                    }
                }
            }
        }
    }
}

private struct DraftContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let draft: PlannerDraft
    let model: DraftModel
    /// The player whose menu is open.
    @State private var menuFor: PlannerDraft.Pick?
    @State private var pickerSlot: PickerSlot?

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
                if let from = model.swapFrom {
                    SwapBanner(name: draft.player(from)?.webName ?? "this player") { model.swapFrom = nil }
                }
                MoneySummary(draft: draft)
                if !draft.check.ok {
                    IssuesCard(issues: draft.check.issues)
                }
                if !draft.transfers.in.isEmpty || !draft.transfers.out.isEmpty {
                    WeekTransfers(draft: draft)
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
                ChipsSection(draft: draft)
                Footnotes(draft: draft)
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await model.resource.load(bypassCache: true) }
        .toolbar {
            if model.isApplying {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView().accessibilityLabel("Saving")
                }
            }
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
        if let store = appModel.watch, let watch = store.watch {
            let watched = watch.isManual(pick.playerId)
            Button(watched ? "Stop watching" : "Watch for alerts") {
                Task { await store.setWatched(!watched, playerId: pick.playerId) }
            }
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
                Button("Cancel", action: cancel)
                    .frame(minHeight: 44)
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

private struct MoneySummary: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let draft: PlannerDraft

    var body: some View {
        ToolkitCard {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) { stats }
            } else {
                Grid(alignment: .leading, horizontalSpacing: ToolkitSpace.lg, verticalSpacing: ToolkitSpace.md) {
                    GridRow {
                        bank
                        value
                    }
                    GridRow {
                        transfers
                        rules
                    }
                }
            }
        }
    }

    @ViewBuilder private var stats: some View {
        bank
        value
        transfers
        rules
    }
    private var bank: some View {
        stat("Bank", Format.price(draft.money.bank), tint: draft.money.bank < 0 ? ToolkitColor.error : ToolkitColor.primaryText)
    }
    private var value: some View { stat("Squad value", Format.price(draft.money.squadValue)) }
    private var transfers: some View {
        stat(draft.freeTransfers.estimated ? "Free transfers*" : "Free transfers", freeTransfers)
    }
    private var rules: some View {
        let players = draft.check.players
        return Group {
            if !draft.check.ok {
                stat("Squad rules", "\(draft.check.issues.count) to fix", tint: ToolkitColor.warning)
            } else if players < 15 {
                // Nothing broken yet, but not a full squad: say how far along it is.
                stat("Squad", "\(players) of 15 players")
            } else {
                stat("Squad rules", "OK", tint: ToolkitColor.positive)
            }
        }
    }

    private var freeTransfers: String {
        if let row = draft.ledger.first(where: { $0.gw == draft.gw }) { return "\(row.freeTransfers)" }
        return draft.gw >= draft.firstEditableGw ? "\(draft.freeTransfers.starting)" : "–"
    }

    private func stat(_ label: String, _ value: String, tint: Color = ToolkitColor.primaryText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

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

private struct PitchCard: View {
    let draft: PlannerDraft
    let actions: TileActions

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            HStack {
                SectionLabel(text: "Starting XI")
                Spacer()
                Text(draft.formation)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityLabel("Formation \(draft.formation)")
            }
            VStack(spacing: ToolkitSpace.md) {
                ForEach(draft.rows(), id: \.position) { row in
                    HStack(alignment: .top, spacing: ToolkitSpace.xs) {
                        ForEach(row.picks) { pick in
                            PlannerTile(pick: pick, draft: draft, highlighted: actions.highlighted == pick.playerId) {
                                actions.tap(pick)
                            }
                        }
                        ForEach(0..<row.empty, id: \.self) { _ in
                            EmptyTile(position: row.position, onTap: actions.add.map { add in { add(row.position, false) } })
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, ToolkitSpace.lg)
            .padding(.horizontal, ToolkitSpace.xs)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: ToolkitRadius.card)
                    .strokeBorder(ToolkitColor.border)
            )
        }
    }
}

private struct BenchCard: View {
    let draft: PlannerDraft
    let actions: TileActions

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Bench")
            HStack(alignment: .top, spacing: ToolkitSpace.xs) {
                ForEach(draft.bench) { pick in
                    PlannerTile(pick: pick, draft: draft, highlighted: actions.highlighted == pick.playerId) {
                        actions.tap(pick)
                    }
                }
                ForEach(PlannerDraft.pitchOrder, id: \.self) { position in
                    ForEach(0..<draft.emptyBench(position), id: \.self) { _ in
                        EmptyTile(position: position, onTap: actions.add.map { add in { add(position, true) } })
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ToolkitSpace.md)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }
}

/// A player on the pitch: name, captaincy, availability, this gameweek's opponent and xFDR.
/// No photos or club badges (workspace rule); the club is shown by its short name.
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

    /// The club's short name in a circle (ringed when doubtful or out), with the C / V badge.
    private func marker(_ player: PlayerSummary?) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(club(player?.clubId) ?? "–")
                .font(.caption.weight(.bold))
                .foregroundStyle(ToolkitColor.primaryText)
                .frame(width: circle, height: circle)
                .background(ToolkitColor.raised, in: Circle())
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
                    let difficulty = f.xfdr.map { ", difficulty \($0.value.formatted(.number.precision(.fractionLength(1)))) out of 5" } ?? ""
                    parts.append("\(name) \(venue)\(difficulty)")
                }
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Chips")
            ForEach(draft.chips) { chip in
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
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func status(_ chip: PlannerDraft.Chip) -> String {
        switch chip.state {
        case .active: "Played this week"
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

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            if draft.freeTransfers.estimated {
                Text("*Free transfers are estimated from your FPL history.")
            }
            if draft.estimatedPurchasePrices {
                Text("Some purchase prices are estimates, so selling prices may be slightly out.")
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
