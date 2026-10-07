import SwiftUI

/// Matchday v2's Pulse (tasks/matchday-v2.md, phase 0; Dan's concept "What matters now"): the
/// default tab when Settings → Developer → "Try Matchday v2" is on. What matters now, who's live,
/// what just happened (with your rival's side of it) and your featured rival. The words and
/// figures are the server's (`pulse` on /live/team); this lays them out.
struct MatchdayPulse: View {
    let live: LiveTeam
    let onPlayer: (Int) -> Void
    /// Opens the live head-to-head with the featured rival.
    let onRival: (Int) -> Void
    let onAllMoments: () -> Void
    let onNextPoints: () -> Void

    var body: some View {
        if let pulse = live.pulse {
            whatMattersNow(pulse)
            if let end = pulse.ifNothingChanges {
                IfNothingChangesCard(end: end)
            }
            if pulse.nextPoints.count > pulse.whatMattersNow.count {
                Button(action: onNextPoints) {
                    HStack {
                        Text("All points within reach (\(pulse.nextPoints.count))")
                        Spacer()
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 48)
                    .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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
            // Wraps rather than scrolling sideways, so large text keeps every chip in view.
            FlowLayout(spacing: 10, lineSpacing: 10) {
                ForEach(playing) { p in
                    Button { onPlayer(p.playerId) } label: {
                        LiveNowChip(player: p, summary: live.player(p.playerId),
                                    captain: live.captainId == p.playerId)
                    }
                    .buttonStyle(.plain)
                }
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
                    // The name wraps; the score never clips.
                    Text(featured.name)
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let you = row?.you, let them = row?.them {
                        Text("\(you) – \(them)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                            .fixedSize()
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
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(points)\(captain ? " (C)" : "") · \(player.minutes)'")
                .font(.caption.monospacedDigit())
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 76)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary?.webName ?? "Player")\(captain ? ", captain" : ""): \(points) points, \(player.minutes) minutes")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the points breakdown")
    }

    private var points: Int { player.points * max(player.multiplier, 1) }
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

/// "If nothing changes…" (phase 1): where the gameweek ends if the matches in play end as they
/// stand and players still to play score as projected.
struct IfNothingChangesCard: View {
    let end: LiveTeam.Pulse.EndState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("If nothing changes…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(end.points)")
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
                Text("estimated points")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
            if let rival = end.rival {
                Text(Self.rivalText(rival))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(rival.margin >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(end.basis)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.informationFill, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    nonisolated static func rivalText(_ rival: LiveTeam.Pulse.EndState.Rival) -> String {
        switch rival.margin {
        case 0: "You'd draw the gameweek with \(rival.name)"
        case 1...: "You'd beat \(rival.name) by \(rival.margin) this gameweek"
        default: "\(rival.name) would beat you by \(-rival.margin) this gameweek"
        }
    }
}

/// Every point within reach (phase 1, Dan's "Next points"): closest first, then where the
/// gameweek ends if nothing changes.
struct MatchdayNextPoints: View {
    let live: LiveTeam?
    let onPlayer: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let live, let pulse = live.pulse {
                    if pulse.nextPoints.isEmpty {
                        Text("Nothing within reach right now.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(pulse.nextPoints.enumerated()), id: \.element.id) { index, item in
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
                    if let end = pulse.ifNothingChanges {
                        IfNothingChangesCard(end: end)
                    }
                    Text("DEFCON, saves, bonus, 60 minutes and clean sheets for the players who count, closest first. Points include your captain.")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Next points")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The live head-to-head with your featured rival (phase 1, Dan's "Live Rivals"): this gameweek's
/// scores, the season gap, what changed, what matters now and who's still to play on each side.
struct MatchdayHeadToHead: View {
    let live: LiveTeam?
    let onFullPage: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let live, let rivals = live.rivals, let featured = rivals.featured {
                    let row = rivals.rows.first { $0.entryId == featured.entryId }
                    scores(live: live, name: featured.name, row: row)
                    if let changed = featured.changed {
                        SectionHeader(title: "What changed")
                        card { Text(changed).fixedSize(horizontal: false, vertical: true) }
                    }
                    if !featured.now.isEmpty {
                        SectionHeader(title: "What matters now")
                        card {
                            ForEach(featured.now) { situation in
                                Label {
                                    Text(situation.text).fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: situation.effect >= 0 ? "arrow.up.right" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(situation.effect >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
                                }
                            }
                        }
                    }
                    let toCome = Self.stillToCome(featured.next)
                    if !toCome.isEmpty {
                        SectionHeader(title: "Still to come")
                        card {
                            ForEach(toCome, id: \.playerId) { entry in
                                HStack {
                                    Text(live.player(entry.playerId)?.webName ?? "Player")
                                        .foregroundStyle(ToolkitColor.primaryText)
                                    Spacer()
                                    Text(entry.side(featured.name))
                                        .foregroundStyle(entry.yours && !entry.theirs ? ToolkitColor.positive
                                                         : entry.theirs && !entry.yours ? ToolkitColor.warning
                                                         : ToolkitColor.secondaryText)
                                }
                                .font(.subheadline)
                            }
                        }
                        Text("Players whose matches aren't over yet. Both: you have them too, so they can't change the gap.")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let end = live.pulse?.ifNothingChanges, end.rival != nil {
                        IfNothingChangesCard(end: end)
                    }
                    Button { onFullPage(featured.entryId) } label: {
                        HStack {
                            Text("\(featured.name)'s full page")
                            Spacer()
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .padding(.horizontal, 15)
                        .frame(minHeight: 48)
                        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Feature a rival from their page (Watch → Rivals) to follow them here, live.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle(live?.rivals?.featured.map { "You v \($0.name)" } ?? "Head-to-head")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func scores(live: LiveTeam, name: String, row: RivalSummary?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(row?.you ?? live.total.estimated)")
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                    Text("You").font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row?.them.map(String.init) ?? "–")
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                    Text(name).font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
                }
            }
            .foregroundStyle(ToolkitColor.primaryText)
            .accessibilityElement(children: .combine)
            if let swing = row?.swingText {
                Text(swing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
            }
            if let gap = row?.gapText {
                Text("Season: \(gap)")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.primaryText)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    struct ToCome: Equatable {
        let playerId: Int
        let yours: Bool
        let theirs: Bool
        func side(_ name: String) -> String {
            yours && theirs ? "Both" : yours ? "You only" : "\(name) only"
        }
    }

    /// Each player still to play once, in kick-off order: yours, theirs or both.
    nonisolated static func stillToCome(_ next: [LiveTeam.Rivals.ComingUp]) -> [ToCome] {
        var seen = Set<Int>()
        var out: [ToCome] = []
        for fixture in next.sorted(by: { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) }) {
            for id in fixture.yours + fixture.theirs where !seen.contains(id) {
                seen.insert(id)
                out.append(ToCome(playerId: id, yours: fixture.yours.contains(id), theirs: fixture.theirs.contains(id)))
            }
        }
        return out
    }
}
