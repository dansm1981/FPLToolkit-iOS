import SwiftUI

/// Matchday v2's Pulse (tasks/matchday-v2.md, phase 0; Dan's concept "What matters now"): the
/// default tab when Settings → Developer → "Try Matchday v2" is on. What matters now, who's live,
/// what just happened (with your rival's side of it) and your featured rival. The words and
/// figures are the server's (`pulse` on /live/team); this lays them out.
struct MatchdayPulse: View {
    let live: LiveTeam
    let onPlayer: (Int) -> Void
    let onRival: (Int) -> Void
    let onAllMoments: () -> Void

    var body: some View {
        if let pulse = live.pulse {
            whatMattersNow(pulse)
            liveNow
            justHappened(pulse)
            rivalCard
        } else {
            Text("Pulse needs the latest server update. Your team, the feed and matches still work as before.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: What matters now

    @ViewBuilder private func whatMattersNow(_ pulse: LiveTeam.Pulse) -> some View {
        SectionHeader(title: "What matters now")
        if pulse.whatMattersNow.isEmpty {
            Text(quietText)
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(pulse.whatMattersNow.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    Button { onPlayer(item.playerId) } label: {
                        PulseItemRow(item: item, photo: live.player(item.playerId)?.photo)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 15)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }

    /// Nothing within reach: say where the gameweek is instead.
    private var quietText: String {
        switch live.status {
        case .upcoming, .between: live.headline?.text ?? "Nothing within reach until the next kick-off."
        case .awaitingBonus, .finished: "All your matches have finished."
        default: "Nothing close to a threshold right now. \(live.headline?.text ?? "")"
        }
    }

    // MARK: Live now

    @ViewBuilder private var liveNow: some View {
        let playing = live.squad.filter { $0.counted && $0.state == .inPlay }
        if !playing.isEmpty {
            SectionHeader(title: "Live now (\(playing.count))")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(playing) { p in
                        Button { onPlayer(p.playerId) } label: {
                            LiveNowChip(player: p, summary: live.player(p.playerId),
                                        captain: live.captainId == p.playerId)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Just happened

    @ViewBuilder private func justHappened(_ pulse: LiveTeam.Pulse) -> some View {
        if !pulse.justHappened.isEmpty {
            SectionHeader(title: "Just happened")
            VStack(spacing: 0) {
                ForEach(Array(pulse.justHappened.enumerated()), id: \.element.id) { index, moment in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    PulseMomentRow(moment: moment, photo: moment.playerId.flatMap { live.player($0)?.photo },
                                   rival: rivalEffect(moment.id))
                }
                Divider().overlay(ToolkitColor.border)
                Button(action: onAllMoments) {
                    HStack {
                        Text("All moments")
                        Spacer()
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 15)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }

    /// What a moment did to your featured rival, from the feed ("You move 4 ahead of Andy").
    private func rivalEffect(_ itemId: String) -> String? {
        guard let featured = live.rivals?.featured,
              let item = live.feed?.first(where: { $0.id == itemId }) else { return nil }
        return item.rivals?.first { $0.entryId == featured.entryId }?.text
    }

    // MARK: Your rival

    @ViewBuilder private var rivalCard: some View {
        if let rivals = live.rivals, let featured = rivals.featured {
            let row = rivals.rows.first { $0.entryId == featured.entryId }
            SectionHeader(title: "Your rival")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(featured.name)
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Spacer()
                    if let you = row?.you, let them = row?.them {
                        Text("\(you) – \(them)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                            .accessibilityLabel("You \(you), \(featured.name) \(them)")
                    }
                }
                if let gap = row?.gapText {
                    Text(gap)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle((row?.gap ?? 0) >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
                }
                if let changed = featured.changed {
                    Text(changed)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(featured.now.prefix(2)) { situation in
                    Label {
                        Text(situation.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: situation.effect >= 0 ? "arrow.up.right" : "exclamationmark.triangle.fill")
                            .foregroundStyle(situation.effect >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
                    }
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.primaryText)
                }
                Button { onRival(featured.entryId) } label: {
                    HStack {
                        Text("Open head-to-head")
                        Spacer()
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(15)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }
}

/// One thing that matters: who, what, how close, and what's at stake for you.
struct PulseItemRow: View {
    let item: LiveTeam.Pulse.Item
    let photo: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PlayerPhoto(path: photo, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(item.tone == .danger ? ToolkitColor.warning : ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = item.progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(item.tone == .danger ? ToolkitColor.warning : ToolkitColor.positive)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 8)
            Text("\(item.tone == .danger ? "−" : "+")\(item.stake)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(item.tone == .danger ? ToolkitColor.warning : ToolkitColor.positive)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the points breakdown")
    }
}

/// A player on the pitch now: photo, name and points so far.
struct LiveNowChip: View {
    let player: LiveTeam.Player
    let summary: PlayerSummary?
    let captain: Bool

    var body: some View {
        VStack(spacing: 4) {
            PlayerPhoto(path: summary?.photo, size: 44)
            Text(summary?.webName ?? "Player")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
                .lineLimit(1)
            Text("\(player.points * max(player.multiplier, 1))\(captain ? " (C)" : "")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(ToolkitColor.secondaryText)
            Text("\(player.minutes)'")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .frame(minWidth: 72)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the points breakdown")
    }
}

/// A moment that just happened, with your points and your rival's side of it.
struct PulseMomentRow: View {
    let moment: LiveTeam.Pulse.Moment
    let photo: String?
    let rival: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlayerPhoto(path: photo, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(moment.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = moment.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                if let rival {
                    Text(rival)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.link)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(moment.at.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
