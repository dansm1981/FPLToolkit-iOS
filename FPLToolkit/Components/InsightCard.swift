import SwiftUI

/// One API insight. Title, wording, tone and value all come from the API (§4.1);
/// this view only lays them out, with an icon as well as colour.
struct InsightCard: View {
    let insight: TeamInsight
    let player: PlayerSummary?

    var body: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                Label {
                    Text(insight.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                } icon: {
                    Image(systemName: insight.symbol)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(insight.tone.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(insight.tone.fill, in: RoundedRectangle(cornerRadius: ToolkitRadius.pill))

                if let player {
                    Text(player.webName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .padding(.top, ToolkitSpace.xs)
                }

                Text(insight.summary)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let value = insight.supportingValue {
                    HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm) {
                        Text(Format.supporting(value))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text(value.label)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }

                if let timestamp = insight.sourceTimestamp {
                    Text("Updated \(Format.ago(timestamp))")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension TeamInsight {
    var symbol: String {
        switch category {
        case .availability: "exclamationmark.triangle"
        case .price: (supportingValue?.value ?? 0) < 0 ? "arrow.down.right" : "arrow.up.right"
        case .minutes: "clock"
        case .elite: "star"
        case .market: "arrow.left.arrow.right"
        case .setpiece: "flag"
        case .other: "info.circle"
        }
    }
}

#if DEBUG
#Preview {
    let today = PreviewFixtures.load("today-3612045-attention", as: Today.self).value
    ScrollView {
        VStack(spacing: ToolkitSpace.lg) {
            ForEach(today.insights.prefix(6)) { insight in
                InsightCard(insight: insight, player: today.player(insight.playerId))
            }
        }
        .padding(ToolkitSpace.page)
    }
    .toolkitScreen()
}
#endif
