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

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                } else if let result {
                    Section {
                        if result.candidates.isEmpty {
                            Text("No players match these filters.")
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                        ForEach(result.candidates) { candidate in
                            CandidateRow(candidate: candidate, replacing: slot.replacing != nil, busy: picking == candidate.id) {
                                Task { await pick(candidate) }
                            }
                            .disabled(candidate.reason != nil || picking != nil)
                        }
                    } header: {
                        SectionLabel(text: result.total > result.candidates.count
                                     ? "Top \(result.candidates.count) of \(result.total) · \(sort.label)"
                                     : "\(result.total) players · \(sort.label)")
                    }
                    .listRowBackground(ToolkitColor.surface)
                } else {
                    Section {
                        HStack(spacing: ToolkitSpace.sm) {
                            ProgressView()
                            Text("Finding players…").foregroundStyle(ToolkitColor.secondaryText)
                        }
                    }
                    .listRowBackground(ToolkitColor.surface)
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
            .task(id: queryItems) {
                // A short pause while typing; a newer query cancels this one.
                try? await Task.sleep(for: .milliseconds(result == nil ? 0 : 300))
                if Task.isCancelled { return }
                await load()
            }
            .onAppear { model.clearActionError() }
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
            Picker("Sort by", selection: $sort) {
                ForEach(Sort.allCases) { Text($0.label).tag($0) }
            }
            Picker("Club", selection: $club) {
                Text("All clubs").tag(Int?.none)
                ForEach(clubs, id: \.id) { club in
                    Text(club.shortName).tag(Int?.some(club.id))
                }
            }
            Picker("Max price", selection: $maxPrice) {
                Text("Any price").tag(Double?.none)
                ForEach(Array(stride(from: 4.5, through: 15.0, by: 0.5)), id: \.self) { price in
                    Text("Up to \(Format.price(price))").tag(Double?.some(price))
                }
            }
            Toggle("Available only", isOn: $availableOnly)
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var clubs: [Bootstrap.Club] {
        (appModel.bootstrap?.value.clubs ?? []).sorted { $0.shortName < $1.shortName }
    }

    private func load() async {
        do {
            result = try await model.candidates(queryItems)
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
    let pick: () -> Void

    var body: some View {
        let player = candidate.player
        Button(action: pick) {
            HStack(alignment: .top, spacing: ToolkitSpace.md) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: ToolkitSpace.sm) {
                        Text(player.webName)
                            .font(.headline)
                            .foregroundStyle(candidate.reason == nil ? ToolkitColor.primaryText : ToolkitColor.secondaryText)
                        AvailabilityBadge(availability: player.availability)
                    }
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
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
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(candidate.reason == nil ? (candidate.inSquad ? "Swaps places with this player" : (replacing ? "Transfers this player in" : "Adds this player")) : "")
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
