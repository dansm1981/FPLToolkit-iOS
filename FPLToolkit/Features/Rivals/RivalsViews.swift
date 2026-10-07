import SwiftUI

// MARK: - Watch → Rivals

/// Watch → Rivals (Dan, 2 Oct 2026; happy-backend-pal#67): the managers you've added from your
/// saved mini-leagues, featured first, each with the season gap and this gameweek. Nothing is
/// suggested: rivals are only ever the ones you add.
struct RivalsContent: View {
    @Environment(AppModel.self) private var appModel
    @State private var adding = false

    private var store: RivalsStore { appModel.rivals }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if appModel.entryId == nil {
                    RivalNote(text: "Add your FPL team to keep rivals: managers from your mini-leagues you want to keep an eye on.")
                } else if let list = store.list {
                    SectionHeader(title: "Your rivals",
                                  actionTitle: list.rivals.count < list.max ? "Add" : nil,
                                  action: list.rivals.count < list.max ? { adding = true } : nil)
                    if let error = store.updateError { ErrorBanner(copy: error) }
                    if list.rivals.isEmpty {
                        empty
                    } else {
                        CardGroup {
                            ForEach(Array(list.rivals.enumerated()), id: \.element.id) { index, rival in
                                if index > 0 { RowDivider() }
                                NavigationLink {
                                    RivalView(entryId: rival.entryId)
                                } label: {
                                    RivalRow(rival: rival, gameweek: list.gameweek)
                                        .padding(.horizontal, 15)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Compares their team with yours")
                            }
                        }
                    }
                    Text(footnote(list))
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let error = store.loadError {
                    ErrorStateView(copy: error) { Task { await store.load() } }
                } else {
                    SkeletonCards(caption: "Loading your rivals…", count: 2)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.top, ToolkitSpace.sm)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await store.load() }
        // Fresh each visit: the gap moves through a gameweek.
        .task { if appModel.entryId != nil { await store.load() } }
        .sheet(isPresented: $adding) { AddRivalView() }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            Text("Add a friend, a family member or the league leader from your mini-leagues. You'll see how you're doing against them all season.")
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a rival") { adding = true }
                .buttonStyle(ToolkitPrimaryButtonStyle())
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func footnote(_ list: RivalsList) -> String {
        var parts = ["Rivals come from your saved mini-leagues, and only you can see them."]
        if !list.rivals.isEmpty { parts.append("Up to \(list.max).") }
        if list.rivals.count > 1 { parts.append("Feature one from their page to see them on Today.") }
        return parts.joined(separator: " ")
    }
}

/// A rival in a list: name (with a star when featured), who they are, where they stand in your
/// leagues and this gameweek, and the gap in words.
struct RivalRow: View {
    let rival: RivalSummary
    let gameweek: Int

    var body: some View {
        NameFigureRow {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(rival.name)
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                if rival.featured {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.accent)
                }
            }
        } details: {
            VStack(alignment: .leading, spacing: 2) {
                if !rival.identity.isEmpty { FactLine(rival.identity) }
                FactLine(RivalText.detail(rival, gameweek: gameweek))
            }
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
        } figure: {
            RivalGapFigure(gap: rival.gap)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RivalText.spoken(rival, gameweek: gameweek))
    }
}

/// The gap as a figure with its direction in words ("30 behind"), never colour alone.
struct RivalGapFigure: View {
    let gap: Int?

    var body: some View {
        let f = RivalText.figure(gap)
        VStack(alignment: .trailing, spacing: 0) {
            Text(f.value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
            Text(f.word)
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
    }
}

struct RivalNote: View {
    let text: String
    var body: some View {
        Text(text)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }
}

enum RivalText {
    /// "30" over "behind", "4" over "ahead", "0" over "level"; "–" until both are synced.
    nonisolated static func figure(_ gap: Int?) -> (value: String, word: String) {
        guard let gap else { return ("–", "not synced") }
        if gap == 0 { return ("0", "level") }
        return ("\(abs(gap))", gap > 0 ? "ahead" : "behind")
    }

    nonisolated static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        if (11...13).contains(tens) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// "LEAGUE OF EXPERTS 1st · GW5: you 45, Andy 56", or what's stopping the figures.
    nonisolated static func detail(_ rival: RivalSummary, gameweek: Int) -> String {
        switch rival.state {
        case .otherSeason: return "Saved last season: open to add them again"
        case .notInLeagues: return "Not in your saved leagues: no new data"
        case .ok, .unknown: break
        }
        var parts: [String] = []
        if let league = rival.leagues.first {
            var text = league.rank.map { "\(league.name) \(ordinal($0))" } ?? league.name
            if rival.leagues.count > 1 { text += " +\(rival.leagues.count - 1) more" }
            parts.append(text)
        }
        if let you = rival.you, let them = rival.them {
            parts.append("GW\(gameweek): you \(you), \(rival.name) \(them)")
        } else if rival.gapBefore != nil {
            parts.append("Their GW\(gameweek) team isn't synced yet")
        }
        return parts.joined(separator: " · ")
    }

    nonisolated static func spoken(_ rival: RivalSummary, gameweek: Int) -> String {
        var parts = [rival.name]
        if rival.featured { parts.append("featured") }
        if !rival.identity.isEmpty { parts.append(rival.identity) }
        if let gap = rival.gapText { parts.append(gap) }
        if let swing = rival.swingText { parts.append(swing) }
        parts.append(detail(rival, gameweek: gameweek))
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// "This gameweek: you 45 · Andy 56".
    nonisolated static func thisWeek(_ rival: RivalSummary) -> String? {
        guard let you = rival.you, let them = rival.them else { return nil }
        return "This gameweek: you \(you) · \(rival.name) \(them)"
    }

    /// The player page: "Andy captains him · Big Paul starts him · Chris has him on the bench (GW5)".
    nonisolated static func holding(_ rivals: [PlayerLeagues.Rival]) -> String {
        let parts = rivals.map { r in
            "\(r.name) \(r.captain ? "captains him" : r.started ? "starts him" : "has him on the bench")"
        }
        let gw = rivals.map(\.gameweek).max().map { " (GW\($0))" } ?? ""
        return parts.joined(separator: " · ") + gw
    }

    /// "Estimated bonus to come: you +2 · Andy +3" (not in the figures).
    nonisolated static func bonus(_ rival: RivalSummary) -> String? {
        guard rival.youBonus > 0 || rival.themBonus > 0 else { return nil }
        return "Estimated bonus to come, not included: you +\(rival.youBonus) · \(rival.name) +\(rival.themBonus)"
    }
}

// MARK: - Add a rival

/// Everyone in your saved mini-leagues you could add, with a search (Dan: rivals only from leagues
/// you've added; no suggestions).
struct AddRivalView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: RivalCandidates?
    @State private var loadError: ErrorCopy?
    @State private var query = ""
    /// Just added and nobody featured yet: offer to feature them.
    @State private var offerFeature: RivalCandidates.Manager?

    private var store: RivalsStore { appModel.rivals }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.updateError {
                    ErrorBanner(copy: error)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                if let candidates {
                    if full {
                        Text("You have \(candidates.max) rivals. Remove one to add another.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .listRowBackground(ToolkitColor.surface)
                    }
                    if candidates.managers.isEmpty {
                        Text("Add a mini-league from Today → Your leagues, then add rivals from it here.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .listRowBackground(ToolkitColor.surface)
                    }
                    Section {
                        ForEach(shown(candidates)) { manager in
                            row(manager)
                        }
                    } footer: {
                        if !candidates.managers.isEmpty {
                            Text("Managers from your saved leagues (the top 150 of each).")
                        }
                    }
                    .listRowBackground(ToolkitColor.surface)
                } else if let loadError {
                    Section {
                        Text("\(loadError.title). \(loadError.message)")
                            .foregroundStyle(ToolkitColor.secondaryText)
                        Button("Try again") { Task { await load() } }
                    }
                    .listRowBackground(ToolkitColor.surface)
                } else {
                    Section { ProgressView() }.listRowBackground(ToolkitColor.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search managers and teams")
            .navigationTitle("Add a rival")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                store.clearError()
                await load()
            }
            .alert(offerFeature.map { "Feature \($0.name)?" } ?? "",
                   isPresented: Binding(get: { offerFeature != nil }, set: { if !$0 { offerFeature = nil } }),
                   presenting: offerFeature) { manager in
                Button("Feature") { Task { await store.save(manager.entryId, RivalPatch(featured: true)) } }
                Button("Not now", role: .cancel) {}
            } message: { _ in
                Text("Your featured rival shows on Today and on Matchday. You can change it any time.")
            }
        }
    }

    private var full: Bool {
        guard let list = store.list else { return false }
        return list.rivals.count >= list.max
    }

    private func shown(_ candidates: RivalCandidates) -> [RivalCandidates.Manager] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return candidates.managers }
        return candidates.managers.filter {
            [$0.manager, $0.team].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
        }
    }

    private func row(_ manager: RivalCandidates.Manager) -> some View {
        let isRival = store.contains(manager.entryId)
        return HStack(spacing: ToolkitSpace.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.manager ?? manager.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                FactLine(([manager.team] + manager.leagues.map { l in
                    l.rank.map { "\(l.name) \(RivalText.ordinal($0))" } ?? l.name
                }).compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if isRival {
                Label("Rival", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.positive)
            } else if store.changing == manager.entryId {
                ProgressView()
            } else {
                // The frame goes on the label: outside it, the tappable area stays the text's size.
                Button { Task { await add(manager) } } label: {
                    Text("Add")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .buttonStyle(.borderless)
                .disabled(full || store.changing != nil)
                .accessibilityLabel("Add \(manager.manager ?? manager.name) as a rival")
            }
        }
        .frame(minHeight: 44)
        // Separators from the row's leading edge, not the "Rival" label's.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private func add(_ manager: RivalCandidates.Manager) async {
        let hadFeatured = store.featured != nil
        if await store.save(manager.entryId), !hadFeatured {
            offerFeature = manager
        }
    }

    private func load() async {
        loadError = nil
        do {
            async let list: Void = store.loadIfNeeded()
            candidates = try await store.repository.candidates()
            await list
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }
}

// MARK: - Today

/// Today's line for the featured rival (brief: one compact summary, not a second league table).
struct FeaturedRivalCard: View {
    let rival: RivalSummary
    let gameweek: Int
    let open: () -> Void

    var body: some View {
        CardGroup {
            Button(action: open) {
                HStack(spacing: ToolkitSpace.md) {
                    IconBadge(systemImage: "person.2")
                    RivalRow(rival: rival, gameweek: gameweek)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Compares their team with yours")
        }
    }
}

/// All your rivals as their own screen (from Today's "All rivals").
struct RivalsScreen: View {
    var body: some View {
        RivalsContent()
            .toolkitScreen()
            .navigationTitle("Rivals")
            .navigationBarTitleDisplayMode(.inline)
    }
}
