import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen design Dan approved (tasks/phase-3.md §4.1): the score and how many players are
/// live; the single most relevant thing; what's in the score and how fresh it is. Stable, not a
/// ticker. Tapping it opens Matchday.
struct MatchdayLiveActivity: Widget {
    private static let green = Color(red: 0.48, green: 0.83, blue: 0.65)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchdayActivityAttributes.self) { context in
            lockScreen(context.state)
                .padding(16)
                .activityBackgroundTint(Color(red: 0.09, green: 0.11, blue: 0.10))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "fpltoolkit://matchday"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(context.state.points)")
                            .font(.title.weight(.bold).monospacedDigit())
                        Text(context.state.provisionalBonus > 0 ? "est. pts" : "pts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    liveCount(context.state)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.headline)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Text("\(context.state.points)")
                    .font(.headline.monospacedDigit())
            } compactTrailing: {
                Circle()
                    .fill(context.state.playing > 0 ? Self.green : Color.gray)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(context.state.playing > 0 ? "Players live" : "No players live")
            } minimal: {
                Text("\(context.state.points)")
                    .font(.headline.monospacedDigit())
            }
            .widgetURL(URL(string: "fpltoolkit://matchday"))
        }
    }

    private func lockScreen(_ state: MatchdayActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(state.points)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(state.provisionalBonus > 0 ? "est. pts" : "pts")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                liveCount(state)
            }
            Text(state.headline)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(footer(state))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    @ViewBuilder
    private func liveCount(_ state: MatchdayActivityAttributes.ContentState) -> some View {
        if state.playing > 0 {
            Label("\(state.playing) live", systemImage: "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Self.green)
                .labelStyle(DotLabelStyle())
        } else {
            Text(statusText(state.status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private func footer(_ state: MatchdayActivityAttributes.ContentState) -> String {
        let updated = "Updated \(state.updatedAt.formatted(date: .omitted, time: .shortened))"
        return state.provisionalBonus > 0 ? "Includes \(state.provisionalBonus) projected bonus · \(updated)" : updated
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "live": "Live"
        case "between": "Between matches"
        case "awaitingBonus": "Awaiting bonus"
        case "finished": "Complete"
        default: "Not started"
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7))
            configuration.title
        }
    }
}
