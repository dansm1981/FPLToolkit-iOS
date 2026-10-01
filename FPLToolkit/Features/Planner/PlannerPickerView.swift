import SwiftUI

/// Where the picker was opened from: an empty place in a position, or a player to replace.
struct PickerSlot: Identifiable, Hashable {
    let id = UUID()
    let position: Position
    /// The squad player being replaced (or swapped); nil for an empty place.
    let replacing: PlannerDraft.Pick?
    let onBench: Bool
}

/// The website's player picker: search, club, sort, max price and available-only, every player
/// marked with why he can't be chosen. Squad players that can swap in come first when replacing.
/// The server decides who can be picked and why; this lays out its answer.
struct PlannerPickerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let draft: PlannerDraft
    let slot: PickerSlot
    let model: DraftModel

    enum Sort: String, CaseIterable, Identifiable {
        case points, form, ppg, value, price, xgi, selected, fdr
        var id: String { rawValue }
        var label: String {
            switch self {
            case .points: "Total points"
            case .form: "Form"
            case .ppg: "Points per game"
            case .value: "Points per £m"
            case .price: "Price"
            case .xgi: "Expected goal involvements"
            case .selected: "Selected by"
            case .fdr: "Easiest next 6 fixtures"
            }
        }
    }

    @State private var query = ""
    @State private var sort: Sort = .points
    @State private var club: Int?
    @State private var maxPrice: Double?
    @State private var availableOnly = false
    @State private var result: PlannerPicker?
    @State private var loadError: ErrorCopy?
    @State private var picking: Int?
    /// A replacement chosen: reviewed before it's saved to the plan (design pack p.16).
    @State private var reviewing: PlannerPicker.Candidate?

    /// When replacing: every player, or the website's Explore (shortlist first, then the rest by price).
    enum Mode: Hashable { case all, explore }
    @State private var mode: Mode = .all
    @State private var affordableOnly = false
    @State private var cheapestFirst = false
    @State private var explore: (shortlist: PlannerPicker, more: PlannerPicker)?

    private var replacedName: String? {
        slot.replacing.flatMap { draft.player($0.playerId)?.webName }
    }

    private var title: String {
        if let replacedName { return "Replace \(replacedName)" }
        return "Pick a \(slot.position.rawValue)\(slot.onBench ? " (bench)" : "")"
    }

    private var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "gw", value: String(draft.gw)),
            URLQueryItem(name: "position", value: slot.position.rawValue),
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "dir", value: "desc"),
            URLQueryItem(name: "limit", value: "60"),
            URLQueryItem(name: "strip", value: "4"),
        ]
        if let replacing = slot.replacing { items.append(URLQueryItem(name: "replace", value: String(replacing.playerId))) }
        if let club { items.append(URLQueryItem(name: "club", value: String(club))) }
        if let maxPrice { items.append(URLQueryItem(name: "maxPrice", value: String(maxPrice))) }
        if availableOnly { items.append(URLQueryItem(name: "available", value: "1")) }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        return items
    }

    /// Explore's two lists: shortlisted players, then everyone else, by price, with four weeks of fixtures.
    private func exploreItems(shortlisted: Bool) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "gw", value: String(draft.gw)),
            URLQueryItem(name: "position", value: slot.position.rawValue),
            URLQueryItem(name: "sort", value: "price"),
            URLQueryItem(name: "dir", value: cheapestFirst ? "asc" : "desc"),
            URLQueryItem(name: "limit", value: shortlisted ? "40" : "60"),
            URLQueryItem(name: "shortlist", value: shortlisted ? "only" : "exclude"),
            URLQueryItem(name: "strip", value: "4"),
        ]
        if let replacing = slot.replacing { items.append(URLQueryItem(name: "replace", value: String(replacing.playerId))) }
        if let club { items.append(URLQueryItem(name: "club", value: String(club))) }
        if affordableOnly && !shortlisted { items.append(URLQueryItem(name: "affordable", value: "1")) }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        return items
    }

    private var taskKey: [URLQueryItem] {
        mode == .explore ? exploreItems(shortlisted: true) + exploreItems(shortlisted: false) : queryItems
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if slot.replacing != nil {
                        Picker("View", selection: $mode) {
                            Text("All players").tag(Mode.all)
                            Text("Explore").tag(Mode.explore)
                        }
                        .pickerStyle(.segmented)
                    }
                    summary
                    filterBar
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    if let error = model.actionError {
                        ErrorBanner(copy: error)
                            .listRowBackground(Color.clear)
                    }
                }
                .listRowBackground(Color.clear)

                if let loadError {
                    Section {
                        Text("\(loadError.title). \(loadError.message)")
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .listRowBackground(ToolkitColor.surface)
                } else if mode == .explore {
                    if let explore {
                        exploreSection("Your shortlist", explore.shortlist,
                                       empty: "No shortlisted \(slot.position.spokenName)s. Tap a star to add one.")
                        exploreSection(affordableOnly ? "More players you can afford" : "More players", explore.more,
                                       empty: "No players match these filters.")
                    } else {
                        loadingSection
                    }
                } else if let result {
                    Section {
                        if result.candidates.isEmpty {
                            Text("No players match these filters.")
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                        ForEach(result.candidates) { candidate in
                            candidateRow(candidate)
                        }
                    } header: {
                        SectionLabel(text: result.total > result.candidates.count
                                     ? "Top \(result.candidates.count) of \(result.total) · \(sort.label)"
                                     : "\(result.total) players · \(sort.label)")
                    }
                    .listRowBackground(ToolkitColor.surface)
                } else {
                    loadingSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search name")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $reviewing) { candidate in
                if let replacing = slot.replacing {
                    ReviewMoveView(draft: draft, outgoing: replacing, incoming: candidate, model: model) { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: taskKey) {
                // A short pause while typing; a newer query cancels this one.
                try? await Task.sleep(for: .milliseconds(result == nil && explore == nil ? 0 : 300))
                if Task.isCancelled { return }
                await load()
            }
            .onAppear { model.clearActionError() }
            .task { await appModel.shortlist.loadIfNeeded() }
        }
    }

    private var loadingSection: some View {
        Section {
            HStack(spacing: ToolkitSpace.sm) {
                ProgressView()
                Text("Finding players…").foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .listRowBackground(ToolkitColor.surface)
    }

    private func exploreSection(_ title: String, _ list: PlannerPicker, empty: String) -> some View {
        Section {
            if list.candidates.isEmpty {
                Text(empty).foregroundStyle(ToolkitColor.secondaryText)
            }
            ForEach(list.candidates) { candidate in
                candidateRow(candidate)
            }
        } header: {
            SectionLabel(text: "\(title) · \(cheapestFirst ? "cheapest" : "dearest") first")
        }
        .listRowBackground(ToolkitColor.surface)
    }

    private func candidateRow(_ candidate: PlannerPicker.Candidate) -> some View {
        CandidateRow(
            candidate: candidate,
            replacing: slot.replacing != nil,
            busy: picking == candidate.id,
            pickable: candidate.reason == nil && picking == nil,
            shortlisted: appModel.shortlist.list == nil ? (candidate.shortlisted ?? false) : appModel.isStarred(candidate.id)
        ) {
            Task { await pick(candidate) }
        } toggleShortlist: {
            Task { await appModel.toggleStar(candidate.id) }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("GW\(draft.gw)")
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                Spacer()
                if let result {
                    Text("Bank \(Format.price(result.bank))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(result.bank < 0 ? ToolkitColor.error : ToolkitColor.primaryText)
                }
            }
            if let replacedName, let sells = result?.outgoingSellingPrice {
                Text("Selling \(replacedName) returns \(Format.price(sells)).")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The filters in plain view (Dan, 29 Sep): sort, club, price and availability as chips, each
    /// showing its current choice, wrapping onto a second line rather than scrolling out of sight.
    private var filterBar: some View {
        FlowLayout(spacing: 8) {
                if mode == .explore {
                    Menu {
                        Picker("Price order", selection: $cheapestFirst) {
                            Text("Dearest first").tag(false)
                            Text("Cheapest first").tag(true)
                        }
                    } label: {
                        FilterChipLabel(text: cheapestFirst ? "Cheapest first" : "Dearest first", active: false, menu: true)
                    }
                    Button { affordableOnly.toggle() } label: {
                        FilterChipLabel(text: "Affordable", active: affordableOnly, menu: false)
                    }
                    .accessibilityAddTraits(affordableOnly ? .isSelected : [])
                } else {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        FilterChipLabel(text: sort.label, active: false, menu: true)
                    }
                    .accessibilityLabel("Sort by \(sort.label)")
                }
                Menu {
                    Picker("Club", selection: $club) {
                        Text("All clubs").tag(Int?.none)
                        ForEach(clubs, id: \.id) { club in
                            Text(club.name).tag(Int?.some(club.id))
                        }
                    }
                } label: {
                    FilterChipLabel(text: club.flatMap { appModel.club($0)?.shortName } ?? "All clubs", active: club != nil, menu: true)
                }
                .accessibilityLabel("Club: \(club.flatMap { appModel.club($0)?.name } ?? "all clubs")")
                if mode == .all {
                    Menu {
                        Picker("Max price", selection: $maxPrice) {
                            Text("Any price").tag(Double?.none)
                            ForEach(Array(stride(from: 4.5, through: 15.0, by: 0.5)), id: \.self) { price in
                                Text("Up to \(Format.price(price))").tag(Double?.some(price))
                            }
                        }
                    } label: {
                        FilterChipLabel(text: maxPrice.map { "Up to \(Format.price($0))" } ?? "Any price", active: maxPrice != nil, menu: true)
                    }
                    .accessibilityLabel("Price: \(maxPrice.map { "up to \(Format.price($0))" } ?? "any")")
                    Button { availableOnly.toggle() } label: {
                        FilterChipLabel(text: "Available", active: availableOnly, menu: false)
                    }
                    .accessibilityAddTraits(availableOnly ? .isSelected : [])
                }
        }
        .padding(.vertical, 2)
    }

    private var clubs: [Bootstrap.Club] {
        (appModel.bootstrap?.value.clubs ?? []).sorted { $0.shortName < $1.shortName }
    }

    private func load() async {
        do {
            if mode == .explore {
                async let shortlisted = model.candidates(exploreItems(shortlisted: true))
                async let more = model.candidates(exploreItems(shortlisted: false))
                explore = try await (shortlisted, more)
            } else {
                result = try await model.candidates(queryItems)
            }
            loadError = nil
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }

    private func pick(_ candidate: PlannerPicker.Candidate) async {
        // Replacing a player is a decision: review the cost and fixtures first. Filling an empty
        // place is building the squad, so it's made straight away. Only a server that previews
        // without saving can offer the review (an older one would save the move).
        if slot.replacing != nil, appModel.supports("plannerPreview") {
            reviewing = candidate
            return
        }
        picking = candidate.id
        defer { picking = nil }
        let action = PlannerAction.pick(candidate.id, replacing: slot.replacing?.playerId, gw: draft.gw)
        if await model.apply(action) { dismiss() }
    }
}

private struct CandidateRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let candidate: PlannerPicker.Candidate
    let replacing: Bool
    let busy: Bool
    let pickable: Bool
    let shortlisted: Bool
    let pick: () -> Void
    let toggleShortlist: () -> Void

    /// A quick list to scroll, as on the website (Dan, 29 Sep): photo, name, club, price and the
    /// next four fixtures' ratings in one line; the reason a player can't be picked under it.
    var body: some View {
        let player = candidate.player
        HStack(spacing: 6) {
            Button(action: pick) {
                HStack(spacing: 10) {
                    PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo, size: 30)
                        .opacity(candidate.reason == nil ? 1 : 0.6)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(player.webName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(candidate.reason == nil ? ToolkitColor.primaryText : ToolkitColor.secondaryText)
                            AvailabilityBadge(availability: player.availability)
                        }
                        ClubLabel(clubId: player.clubId, text: details, logoSize: 12)
                            .font(.caption)
                            .foregroundStyle(ToolkitColor.secondaryText)
                        if typeSize >= .xxLarge, let strip = candidate.fixtureStrip, !strip.isEmpty {
                            FixtureStrip(weeks: strip, roomy: true)
                                .padding(.top, 2)
                        }
                        if let reason = candidate.reason {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(ToolkitColor.secondaryText)
                        } else if candidate.inSquad {
                            Text("In your squad: swaps places")
                                .font(.caption)
                                .foregroundStyle(ToolkitColor.link)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    // At the large sizes the details use the row's width, not just the fixture
                    // boxes' (club and price wrapped beside an empty gap, 1 Oct).
                    .frame(maxWidth: typeSize >= .xxLarge ? .infinity : nil, alignment: .leading)
                    Spacer(minLength: 4)
                    if typeSize < .xxLarge, let strip = candidate.fixtureStrip, !strip.isEmpty {
                        FixtureStrip(weeks: strip, roomy: true)
                    }
                    Group {
                        if busy {
                            ProgressView()
                        } else {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(candidate.totalPoints)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(ToolkitColor.primaryText)
                                Text("pts")
                                    .font(.caption2)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                        }
                    }
                    .frame(minWidth: 28, alignment: .trailing)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!pickable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityHint(candidate.reason == nil ? (candidate.inSquad ? "Swaps places with this player" : (replacing ? "Transfers this player in" : "Adds this player")) : "")
            .accessibilityAddTraits(.isButton)

            Button(action: toggleShortlist) {
                Image(systemName: shortlisted ? "star.fill" : "star")
                    .foregroundStyle(shortlisted ? ToolkitColor.accent : ToolkitColor.secondaryText)
                    .frame(minWidth: 36, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(shortlisted ? "Remove \(player.webName) from the shortlist" : "Add \(player.webName) to the shortlist")
        }
    }

    private var spoken: String {
        let player = candidate.player
        var parts = [player.webName, appModel.club(player.clubId)?.name ?? "", Format.price(player.price),
                     "\(candidate.totalPoints) points"]
        if player.availability.level == .doubt || player.availability.level == .out {
            parts.append(player.availability.chanceNext.map { "\($0) percent chance of playing" } ?? "availability concern")
        }
        if let strip = candidate.fixtureStrip, let run = FixtureStrip.spoken(strip) { parts.append(run) }
        if let reason = candidate.reason { parts.append(reason) } else if candidate.inSquad { parts.append("in your squad") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var details: String {
        let player = candidate.player
        return [appModel.club(player.clubId)?.shortName, Format.price(player.price)].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A filter as a chip: its current choice, gold when it narrows the list, a chevron when it opens
/// a menu.
struct FilterChipLabel: View {
    let text: String
    let active: Bool
    let menu: Bool

    var body: some View {
        HStack(spacing: 4) {
            if !menu && active {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).accessibilityHidden(true)
            }
            Text(text)
            if menu {
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(active ? ToolkitColor.onAccent : ToolkitColor.primaryText)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(active ? ToolkitColor.accent : ToolkitColor.raised, in: Capsule())
        .contentShape(Capsule())
        .frame(minHeight: 44)
    }
}
