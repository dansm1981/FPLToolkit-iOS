import SwiftUI

/// The website's "My leagues", on the Team tab: the Elite 100 and your saved mini-leagues with
/// your rank and gap to first, "Add a league", and managers in more than one of them.
struct LeaguesCard: View {
    @Environment(AppModel.self) private var appModel
    @State private var adding = false
    @State private var pendingRemove: LeagueList.League?

    private var store: LeaguesStore { appModel.leagues }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            HStack {
                SectionLabel(text: "Leagues")
                Spacer()
                Button { adding = true } label: {
                    Label("Add a league", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .frame(minHeight: 44)
                }
                .disabled(store.adding != nil)
            }
            if let error = store.updateError {
                ErrorBanner(copy: error)
            }
            if let list = store.list {
                ToolkitCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(list.leagues.enumerated()), id: \.element.id) { index, league in
                            NavigationLink {
                                LeagueView(league: league)
                            } label: {
                                leagueRow(league)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if !league.isElite {
                                    Button("Remove league", role: .destructive) { pendingRemove = league }
                                }
                            }
                            if index < list.leagues.count - 1 {
                                Divider().overlay(ToolkitColor.border)
                            }
                        }
                        if let adding = store.adding {
                            Divider().overlay(ToolkitColor.border)
                            HStack(spacing: ToolkitSpace.sm) {
                                ProgressView()
                                Text("Reading league \(adding) from FPL. This can take up to a minute…")
                                    .font(.subheadline)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, ToolkitSpace.sm)
                        }
                    }
                }
                if !list.sharedRivals.isEmpty {
                    sharedRivals(list.sharedRivals)
                }
                Text("Touch and hold a league to remove it. Leagues refresh automatically after each deadline.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = store.loadError {
                ErrorBanner(copy: error)
                Button("Try again") { Task { await store.load() } }
                    .buttonStyle(ToolkitSecondaryButtonStyle())
            } else {
                SkeletonCards(caption: "Loading your leagues…", count: 1)
            }
        }
        .task { await store.loadIfNeeded() }
        .sheet(isPresented: $adding) {
            AddLeagueSheet()
        }
        .confirmationDialog(
            pendingRemove.map { "Remove \u{201C}\($0.name)\u{201D}?" } ?? "",
            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemove
        ) { league in
            Button("Remove league", role: .destructive) { Task { await store.remove(league.id) } }
        } message: { _ in
            Text("You can add it again with its ID.")
        }
    }

    private func leagueRow(_ league: LeagueList.League) -> some View {
        HStack(spacing: ToolkitSpace.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(league.name)
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                FactLine(details(league))
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ToolkitSpace.sm)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func details(_ league: LeagueList.League) -> String {
        if league.isElite { return "\(league.managers ?? 100) managers · Anonymous elite cohort · always available" }
        if !league.synced { return "Couldn't be read from FPL yet" }
        var parts = ["\(league.managers ?? league.tracked) managers"]
        if let rank = league.myRank { parts.append("Rank \(rank)") }
        if let gap = league.gapToFirst { parts.append(gap == 0 ? "top" : "\(gap) pts back") }
        return parts.joined(separator: " · ")
    }

    private func sharedRivals(_ rivals: [LeagueList.SharedRival]) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Managers in more than one of your leagues")
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    ForEach(rivals) { rival in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rival.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                            Text(rival.leagues.map { "\($0.name) #\($0.rank.map(String.init) ?? "–")" }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.top, ToolkitSpace.sm)
    }
}

/// Add a mini-league by its ID (the website's "Mini-league ID").
private struct AddLeagueSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var leagueId: Int? { Int(text.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mini-league ID", text: $text)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Mini-league ID")
                } header: {
                    SectionLabel(text: "Mini-league ID")
                } footer: {
                    Text("Find it in the FPL site's address bar: /leagues/1234/standings/c. Classic leagues only; private leagues can't be read. Up to 150 managers are tracked.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .listRowBackground(ToolkitColor.surface)
                if let error = appModel.leagues.updateError {
                    Section { ErrorBanner(copy: error) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                if appModel.leagues.adding != nil {
                    Section {
                        HStack(spacing: ToolkitSpace.sm) {
                            ProgressView()
                            Text("Reading the league from FPL. This can take up to a minute…")
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                    }
                    .listRowBackground(ToolkitColor.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .navigationTitle("Add a league")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let leagueId else { return }
                        Task { if await appModel.leagues.add(leagueId) { dismiss() } }
                    }
                    .disabled(leagueId == nil || appModel.leagues.adding != nil)
                }
            }
            .onAppear { appModel.leagues.clearError() }
        }
    }
}
