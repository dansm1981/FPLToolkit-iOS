import SwiftUI

/// The website's Team news drawer for a draft: Today's notes for the squad planned in the gameweek
/// shown, most urgent first. Tapping a note opens the player.
struct DraftNewsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let gw: Int
    let model: DraftModel
    /// Called with the player tapped; the sheet closes first.
    let onSelectPlayer: (Int) -> Void

    @State private var news: PlannerNews?
    @State private var loadError: ErrorCopy?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    if let loadError {
                        ErrorStateView(copy: loadError) { Task { await load() } }
                    } else if let news {
                        content(news)
                    } else {
                        SkeletonCards(caption: "Checking the squad's news…")
                    }
                }
                .padding(.horizontal, ToolkitSpace.page)
                .padding(.bottom, ToolkitSpace.section)
            }
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .navigationTitle("Team news")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func content(_ news: PlannerNews) -> some View {
        let urgent = news.insights.filter(\.needsAttention).count
        Text(headline(urgent: urgent, total: news.insights.count, gw: news.gw))
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(news.insights) { insight in
            Button {
                dismiss()
                onSelectPlayer(insight.playerId)
            } label: {
                InsightCard(insight: insight, player: news.player(insight.playerId), showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the player")
        }
    }

    private func headline(urgent: Int, total: Int, gw: Int) -> String {
        if total == 0 { return "No news for this squad in GW\(gw). Nothing needs your attention." }
        let attention = urgent == 0 ? "nothing needs your attention" : "\(urgent) need\(urgent == 1 ? "s" : "") your attention"
        return "GW\(gw) squad: \(total) note\(total == 1 ? "" : "s"), \(attention). Most urgent first."
    }

    private func load() async {
        loadError = nil
        do {
            news = try await model.news()
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }
}
