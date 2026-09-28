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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
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
            shortlisted: appModel.shortlist.list == nil ? (candidate.shortlisted ?? false) : appModel.shortlist.contains(candidate.id)
        ) {
            Task { await pick(candidate) }
        } toggleShortlist: {
            Task { await appModel.shortlist.toggle(candidate.id) }
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

    private var filterMenu: some View {
        Menu {
            if mode == .explore {
                Picker("Price", selection: $cheapestFirst) {
                    Text("Dearest first").tag(false)
                    Text("Cheapest first").tag(true)
                }
                Toggle("Affordable only", isOn: $affordableOnly)
            } else {
                Picker("Sort by", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.label).tag($0) }
                }
            }
            Picker("Club", selection: $club) {
                Text("All clubs").tag(Int?.none)
                ForEach(clubs, id: \.id) { club in
                    Text(club.shortName).tag(Int?.some(club.id))
                }
            }
            if mode == .all {
                Picker("Max price", selection: $maxPrice) {
                    Text("Any price").tag(Double?.none)
                    ForEach(Array(stride(from: 4.5, through: 15.0, by: 0.5)), id: \.self) { price in
                        Text("Up to \(Format.price(price))").tag(Double?.some(price))
                    }
                }
                Toggle("Available only", isOn: $availableOnly)
            }
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
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
        picking = candidate.id
        defer { picking = nil }
        let action = PlannerAction.pick(candidate.id, replacing: slot.replacing?.playerId, gw: draft.gw)
        if await model.apply(action) { dismiss() }
    }
}

private struct CandidateRow: View {
    @Environment(AppModel.self) private var appModel
    let candidate: PlannerPicker.Candidate
    let replacing: Bool
    let busy: Bool
    let pickable: Bool
    let shortlisted: Bool
    let pick: () -> Void
    let toggleShortlist: () -> Void

    var body: some View {
        let player = candidate.player
        HStack(alignment: .top, spacing: ToolkitSpace.sm) {
            Button(action: pick) {
                HStack(alignment: .top, spacing: ToolkitSpace.md) {
                    PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo)
                        .opacity(candidate.reason == nil ? 1 : 0.6)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: ToolkitSpace.sm) {
                            Text(player.webName)
                                .font(.headline)
                                .foregroundStyle(candidate.reason == nil ? ToolkitColor.primaryText : ToolkitColor.secondaryText)
                            AvailabilityBadge(availability: player.availability)
                        }
                        ClubLabel(clubId: player.clubId, text: details)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                        if let strip = candidate.fixtureStrip, !strip.isEmpty {
                            FixtureStrip(weeks: strip, roomy: true)
                                .padding(.top, 2)
                        }
                        if let reason = candidate.reason {
                            Text(reason)
                                .font(.footnote)
                                .foregroundStyle(ToolkitColor.secondaryText)
                        } else if candidate.inSquad {
                            Text("In your squad: swaps places")
                                .font(.footnote)
                                .foregroundStyle(ToolkitColor.link)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: ToolkitSpace.sm)
                    VStack(alignment: .trailing, spacing: 3) {
                        if busy {
                            ProgressView()
                        } else {
                            Text("\(candidate.totalPoints) pts")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(ToolkitColor.primaryText)
                            if let form = candidate.form {
                                Text("Form \(form.formatted(.number.precision(.fractionLength(1))))")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                        }
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!pickable)
            .accessibilityElement(children: .combine)
            .accessibilityHint(candidate.reason == nil ? (candidate.inSquad ? "Swaps places with this player" : (replacing ? "Transfers this player in" : "Adds this player")) : "")

            Button(action: toggleShortlist) {
                Image(systemName: shortlisted ? "star.fill" : "star")
                    .foregroundStyle(shortlisted ? ToolkitColor.accent : ToolkitColor.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(shortlisted ? "Remove \(player.webName) from the shortlist" : "Add \(player.webName) to the shortlist")
        }
    }

    private var details: String {
        let player = candidate.player
        var parts: [String] = []
        if let club = appModel.club(player.clubId) { parts.append(club.shortName) }
        parts.append(player.position.rawValue)
        parts.append(Format.price(player.price))
        if let f = player.nextFixture {
            if f.blank {
                parts.append("no game")
            } else {
                let opponent = appModel.club(f.opponentClubId)?.shortName ?? "TBC"
                let venue = f.home.map { $0 ? "H" : "A" } ?? ""
                var text = "\(opponent) (\(venue))"
                if let x = f.xfdr { text += " \(x.display)" }
                parts.append(text)
            }
        }
        return parts.joined(separator: " · ")
    }
}
