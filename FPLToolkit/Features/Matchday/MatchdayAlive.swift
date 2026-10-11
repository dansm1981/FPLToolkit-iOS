import SwiftUI

// MARK: - Matchday feels alive (tasks/matchday-alive.md)

/// The rotating live ticker under the score: breaking moments first, then your players, your
/// matches, around the game, your rival, threats and chances, and what's next. Moves on every
/// 10 seconds; swipe to move it yourself, pause with the button. A new breaking moment jumps to the
/// front. With Reduce Motion or VoiceOver on, it only moves when you swipe.
struct LiveTicker: View {
    let items: [LiveTeam.Pulse.TickerItem]
    let onOpen: (LiveTeam.Pulse.TickerItem) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var index = 0
    @State private var paused = false
    static let seconds: UInt64 = 10

    private var current: LiveTeam.Pulse.TickerItem? { items.isEmpty ? nil : items[index % items.count] }
    private var autoAdvance: Bool { !paused && !reduceMotion && !voiceOver && items.count > 1 }

    var body: some View {
        if let item = current {
            HStack(alignment: .top, spacing: ToolkitSpace.md) {
                Image(systemName: LiveTickerText.symbol(item.kind))
                    .font(.headline)
                    .foregroundStyle(LiveTickerText.colour(item.kind))
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LiveTickerText.label(item.kind))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LiveTickerText.colour(item.kind))
                    Text(item.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let impact = item.impact { ConsequenceLine(impact: impact) }
                    Text("\(index % items.count + 1) of \(items.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .id(item.id)
                .transition(.opacity)
                Spacer(minLength: 0)
                if items.count > 1 && !reduceMotion && !voiceOver {
                    Button { paused.toggle() } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ToolkitColor.link)
                    .accessibilityLabel(paused ? "Resume the live ticker" : "Pause the live ticker")
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .contentShape(Rectangle())
            .onTapGesture { onOpen(item) }
            .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                step(value.translation.width < 0 ? 1 : -1)
            })
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: "Open") { onOpen(item) }
            .accessibilityAdjustableAction { direction in
                step(direction == .increment ? 1 : -1)
            }
            .accessibilityHint("Swipe up or down for the next line")
            .task(id: autoAdvance) {
                guard autoAdvance else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: Self.seconds * 1_000_000_000)
                    if Task.isCancelled { break }
                    step(1)
                }
            }
            .onChange(of: items.first?.id) { _, first in
                // A new breaking moment goes straight to the front.
                if items.first?.kind == "breaking", first != nil { withAnimation { index = 0 } }
            }
        }
    }

    private func step(_ by: Int) {
        guard !items.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            index = (index + by + items.count) % items.count
        }
    }
}

enum LiveTickerText {
    static func label(_ kind: String) -> String {
        switch kind {
        case "breaking": "JUST NOW"
        case "player": "YOUR PLAYER"
        case "fixture": "LIVE MATCH"
        case "rival": "YOUR RIVAL"
        case "opportunity": "CHANCE"
        case "threat": "THREAT"
        case "around": "AROUND THE GAME"
        case "coming": "COMING UP"
        default: "LIVE"
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "breaking": "bolt.fill"
        case "player": "person.fill"
        case "fixture": "sportscourt"
        case "rival": "person.2.fill"
        case "opportunity": "arrow.up.right"
        case "threat": "exclamationmark.triangle.fill"
        case "around": "globe"
        case "coming": "clock"
        default: "dot.radiowaves.left.and.right"
        }
    }

    static func colour(_ kind: String) -> Color {
        switch kind {
        case "breaking", "opportunity": ToolkitColor.positive
        case "threat": ToolkitColor.warning
        case "rival", "around": ToolkitColor.accent
        default: ToolkitColor.link
        }
    }
}

/// "Around the game": the latest big moments across the league, with ownership and what they did
/// to your rank.
struct AroundTheGameSection: View {
    let live: LiveTeam
    let onMoment: (String) -> Void
    let onAll: () -> Void

    var body: some View {
        let items = Array((live.feed ?? []).filter { $0.group == .around && $0.state != .withdrawn }.prefix(5))
        if !items.isEmpty {
            SectionHeader(title: "Around the game", actionTitle: "All", action: onAll)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    Button { onMoment(item.id) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            PlayerPhoto(path: item.playerId.flatMap { live.player($0)?.photo }, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.text)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ToolkitColor.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let owned = item.watching {
                                    Text(owned).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let impact = item.impact { ConsequenceLine(impact: impact) }
                            }
                            Spacer(minLength: 0)
                            Text(MatchdayText.feedTime(item))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 15)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }
}

/// Goals that would move your rank most, either way: "A Haaland goal would cost you ~24k places".
struct RankSwingRows: View {
    let swings: [LiveTeam.Pulse.Swing]

    var body: some View {
        ForEach(swings) { swing in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(swing.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(swing.detail)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: swing.kind == "threat" ? "exclamationmark.triangle.fill" : "arrow.up.right")
                    .foregroundStyle(swing.kind == "threat" ? ToolkitColor.warning : ToolkitColor.positive)
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }
}
