import SwiftUI

/// My Team → Team news (batch 3): the published squad's notes as the Planner's team news cards,
/// most urgent first. They're Today's checks, so this is the same list Today works from.
struct TeamNewsSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let entryId: Int
    /// Called with the player tapped; the sheet closes first.
    let onSelectPlayer: (Int) -> Void

    @State private var resource: Resource<Today>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    switch resource?.phase {
                    case .loading?, nil:
                        SkeletonCards(caption: "Checking your squad's news…")
                    case .failed(let copy)?:
                        ErrorStateView(copy: copy) { Task { await resource?.retry() } }
                    case .loaded(let loaded)?:
                        content(loaded.value)
                    }
                }
                .padding(.horizontal, ToolkitSpace.page)
                .padding(.bottom, ToolkitSpace.section)
            }
            .refreshable { await resource?.load(bypassCache: true) }
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .navigationTitle("Team news")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if resource == nil {
                    let resource = Resource(appModel.teamRepository.today(entryId: entryId))
                    self.resource = resource
                    await resource.load()
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ today: Today) -> some View {
        Text(headline(today))
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(today.insights) { insight in
            Button {
                dismiss()
                onSelectPlayer(insight.playerId)
            } label: {
                InsightCard(insight: insight, player: today.player(insight.playerId), showsChevron: true,
                            transfers: insight.category == .price ? today.transfers(insight.playerId) : nil)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the player")
        }
    }

    private func headline(_ today: Today) -> String {
        let total = today.insights.count
        let gw = today.snapshot.map { "GW\($0.gw) squad" } ?? "Your squad"
        if total == 0 { return "\(gw): no news. Nothing needs your attention." }
        let urgent = today.attentionCount
        let attention = urgent == 0 ? "nothing needs your attention" : "\(urgent) need\(urgent == 1 ? "s" : "") your attention"
        return "\(gw): \(total) note\(total == 1 ? "" : "s"), \(attention). Most urgent first."
    }
}
