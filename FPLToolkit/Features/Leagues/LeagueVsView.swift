import SwiftUI

/// The website's manager comparison ("vs me"): their season, what needs to happen for you to
/// catch or stay ahead of them, chips, their squad, and how your squads differ.
struct LeagueVsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let leagueId: Int
    let entryId: Int
    let baseline: LeagueBaseline
    /// From a saved mini-league (not the Elite 100): offers "Add as a rival".
    var canAddRival = false

    @State private var vs: LeagueVs?
    @State private var loadError: ErrorCopy?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                if let loadError {
                    ErrorStateView(copy: loadError) { Task { await load() } }
                } else if let vs {
                    content(vs)
                } else {
                    SkeletonCards(caption: "Comparing squads…", count: 3)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .background(ToolkitColor.canvas.ignoresSafeArea())
        .navigationTitle(vs?.them.teamName ?? "Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { await load() }
        .task { if canAddRival { await appModel.rivals.loadIfNeeded() } }
    }

    @ViewBuilder
    private func content(_ vs: LeagueVs) -> some View {
        let them = vs.them
        Text([them.managerName, them.rank.map { "\($0) in league" }, vs.league.syncedGw.map { "GW\($0)" }]
            .compactMap { $0 }.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)

        if canAddRival, let me = appModel.entryId, me != entryId {
            rivalAction(name: them.managerName ?? them.teamName ?? "them")
        }

        // One a row from xxLarge ("£100.9" / "m" and "TRANS-" / "FERS" in a third of the width).
        let row = typeSize.stacksRows
            ? AnyLayout(VStackLayout(spacing: ToolkitSpace.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: ToolkitSpace.sm))
        VStack(spacing: ToolkitSpace.sm) {
            row {
                stat("GW pts", them.gwPoints.map(String.init) ?? "—")
                stat("Total", them.total.map(String.init) ?? "—")
                stat("Overall rank", them.overallRank.map { $0.formatted() } ?? "—")
            }
            row {
                stat("Value", them.value.map(Format.price) ?? "—")
                stat("Transfers", "\(them.transfers)")
                stat("Hits", them.hits > 0 ? "−\(them.hits)" : "0")
            }
        }

        if let h = vs.headToHead {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "What needs to happen")
                ToolkitCard {
                    VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                        Text(gapSentence(h) + " " + captainSentence(h, vs))
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(h.pointsGap >= 0
                             ? "To stay ahead, your \(h.yourDifferences.count) unique players need to outscore their \(h.theirDifferences.count)."
                             : "To close \(-h.pointsGap) pts, your \(h.yourDifferences.count) unique players must outscore their \(h.theirDifferences.count) — \(h.shared.count) players cancel out.")
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: ToolkitSpace.md) {
                    names("Your differences", h.yourDifferences, vs, colour: ToolkitColor.positive)
                    names("Their differences", h.theirDifferences, vs, colour: ToolkitColor.error)
                }
            }
        }

        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Chips")
            Text((them.chipsPlayed.map { "\(chipName($0.chip)) · GW\($0.gw)" }
                  + them.chipsLeft.map { "\($0.label) ×\($0.count) left" }).joined(separator: "\n"))
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Squad · \(them.formation)")
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
                    ForEach(them.starting) { pickRow($0, vs) }
                    Divider().overlay(ToolkitColor.border).padding(.vertical, ToolkitSpace.xs)
                    Text("BENCH").font(.caption.weight(.semibold)).foregroundStyle(ToolkitColor.secondaryText)
                    ForEach(them.bench) { pickRow($0, vs) }
                }
            }
        }

        if !them.recentTransfers.isEmpty {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                SectionLabel(text: "Recent transfers")
                ToolkitCard {
                    VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
                        ForEach(Array(them.recentTransfers.prefix(10).enumerated()), id: \.offset) { _, t in
                            Text("GW\(t.gw): \(vs.name(t.out)) → \(vs.name(t.in))")
                                .font(.subheadline)
                                .foregroundStyle(ToolkitColor.primaryText)
                        }
                    }
                }
            }
        }
    }

    /// Add them as a rival, or open the rivalry once they are one (brief §3).
    @ViewBuilder
    private func rivalAction(name: String) -> some View {
        let store = appModel.rivals
        if let error = store.updateError { ErrorBanner(copy: error) }
        if store.contains(entryId) {
            NavigationLink {
                RivalView(entryId: entryId)
            } label: {
                LinkRowLabel(title: "Your rival", detail: "See how you compare all season", systemImage: "person.2")
                    .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            }
            .buttonStyle(.plain)
        } else if store.list != nil {
            Button {
                Task { await store.save(entryId) }
            } label: {
                if store.changing == entryId { ProgressView() } else { Text("Add \(name) as a rival") }
            }
            .buttonStyle(ToolkitSecondaryButtonStyle())
            .disabled(store.changing != nil)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(ToolkitColor.secondaryText)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ToolkitSpace.sm)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.button))
        .accessibilityElement(children: .combine)
    }

    private func pickRow(_ pick: LeagueVs.Pick, _ vs: LeagueVs) -> some View {
        let player = vs.player(pick.playerId)
        let club = player.flatMap { appModel.club($0.clubId)?.shortName } ?? ""
        let badge = pick.isCaptain ? " (C)" : pick.isVice ? " (V)" : ""
        return Text("\(player?.webName ?? "Player \(pick.playerId)")\(badge)  \(club) \(player?.position.rawValue ?? "")")
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.primaryText)
    }

    private func names(_ title: String, _ ids: [Int], _ vs: LeagueVs, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(colour)
            ForEach(ids, id: \.self) { Text(vs.name($0)).font(.subheadline).foregroundStyle(ToolkitColor.primaryText) }
            if ids.isEmpty { Text("None").font(.subheadline).foregroundStyle(ToolkitColor.secondaryText) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func gapSentence(_ h: LeagueVs.HeadToHead) -> String {
        h.pointsGap == 0 ? "You are level on total points."
            : h.pointsGap > 0 ? "You are \(h.pointsGap) pts ahead overall."
            : "You are \(-h.pointsGap) pts behind overall."
    }

    private func captainSentence(_ h: LeagueVs.HeadToHead, _ vs: LeagueVs) -> String {
        h.sameCaptain ? "Same captain, so the armband is neutral this week."
            : "Captains differ: you \(vs.name(h.myCaptainId)) vs \(vs.name(h.theirCaptainId))."
    }

    private func chipName(_ chip: String) -> String {
        ["wildcard": "Wildcard", "freehit": "Free Hit", "bboost": "Bench Boost", "3xc": "Triple Captain", "manager": "Assistant Manager"][chip] ?? chip
    }

    private func load() async {
        loadError = nil
        do {
            vs = try await appModel.leagues.repository.vs(leagueId, entryId: entryId, baseline: baseline)
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }
}
