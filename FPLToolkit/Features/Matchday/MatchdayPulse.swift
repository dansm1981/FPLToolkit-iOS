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
    /// Opens a moment: what it did to your score and your rivals (phase 2).
    var onMoment: (String) -> Void = { _ in }

    var body: some View {
        if let pulse = live.pulse {
            // Matchday v3 (Dan, 7 Oct): your rival race first, then what just happened and what it
            // did to you, then what could happen next.
            if let race = pulse.race {
                MatchdayRaceHeader(race: race, chance: pulse.winProbability,
                                   onOpen: { onRival(race.entryId) }, onSwing: onMoment)
            }
            if let final = pulse.recap?.final {
                FinalRecapCard(recap: final, live: live, onMoment: onMoment)
            } else if let spell = pulse.recap?.spell {
                SpellRecapCard(recap: spell, live: live, onMoment: onMoment)
            }
            justHappened(pulse)
            whatMattersNow(pulse)
            if pulse.race == nil, let end = pulse.ifNothingChanges {
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
            if pulse.race == nil { rivalCard }
            LiveLeaguesSection(leagues: live.leagues ?? [])
        } else {
            Text("Pulse needs the latest server update. Your team, the feed and matches still work as before.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: What matters now

    @ViewBuilder private func whatMattersNow(_ pulse: LiveTeam.Pulse) -> some View {
        SectionHeader(title: "What could happen next")
        if pulse.whatMattersNow.isEmpty && rivalSituations.isEmpty {
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
                // Against your rival: what would help you and what would hurt you.
                ForEach(Array(rivalSituations.enumerated()), id: \.offset) { index, situation in
                    if index > 0 || !pulse.whatMattersNow.isEmpty { Divider().overlay(ToolkitColor.border) }
                    Label {
                        Text(situation.text)
                            .foregroundStyle(ToolkitColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: situation.effect >= 0 ? "arrow.up.right" : "exclamationmark.triangle.fill")
                            .foregroundStyle(situation.effect >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 15)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }

    /// The featured rival's situations in play (what would swing the race), when the race is shown.
    private var rivalSituations: [LiveTeam.Rivals.Situation] {
        guard live.pulse?.race != nil else { return [] }
        return live.rivals?.featured?.now ?? []
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
                    Button { onMoment(moment.id) } label: {
                        PulseMomentRow(moment: moment, photo: moment.playerId.flatMap { live.player($0)?.photo },
                                       rival: rivalEffect(moment.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows what it did to your score and your rivals")
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
                if let chance = live.pulse?.winProbability, chance.entryId == featured.entryId {
                    WinProbabilityBar(chance: chance)
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
                // The points line is in the consequence line when there is one.
                if let detail = moment.detail, moment.impact?.points == nil {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                if let impact = moment.impact {
                    ConsequenceLine(impact: impact)
                } else if let change = moment.rankChangeText {
                    Text("Est. rank \(change)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityLabel("Estimated \(RankText.spokenChange(change))")
                }
                if let rival, moment.impact?.rival == nil {
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
                    if let chance = live.pulse?.winProbability, chance.entryId == featured.entryId {
                        card { WinProbabilityBar(chance: chance, showsBasis: true) }
                    }
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

/// One moment translated into FPL consequences (Matchday v2 phase 2, Dan's "Event → consequence"):
/// what happened, your points (captain included), why, and what it did against each saved rival.
struct MatchdayMomentView: View {
    @Environment(AppModel.self) private var appModel
    let live: LiveTeam?
    let itemId: String
    let onPlayer: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let live, let item = live.feed?.first(where: { $0.id == itemId }) {
                    header(item, live: live)
                    if let points = item.points, item.playerId != nil {
                        impact(points: points, item: item, live: live)
                        why(points: points, item: item, live: live)
                    }
                    rivals(item, live: live)
                    if let id = item.playerId {
                        Button { onPlayer(id) } label: {
                            HStack {
                                Text("\(live.player(id)?.webName ?? "Player")'s points breakdown")
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
                } else {
                    Text("This moment isn't in the feed any more.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Moment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func multiplier(_ item: LiveTeam.FeedItem, _ live: LiveTeam) -> Int {
        guard let id = item.playerId else { return 1 }
        return max(1, live.squad.first { $0.playerId == id }?.multiplier ?? 1)
    }

    @ViewBuilder private func header(_ item: LiveTeam.FeedItem, live: LiveTeam) -> some View {
        HStack(alignment: .center, spacing: 14) {
            PlayerPhoto(path: item.playerId.flatMap { live.player($0)?.photo }, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(matchLine(item, live: live))
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = item.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .accessibilityElement(children: .combine)
    }

    /// "66' · ARS 2–0 CHE"
    private func matchLine(_ item: LiveTeam.FeedItem, live: LiveTeam) -> String {
        var parts: [String] = []
        if let minute = item.minute { parts.append("\(minute)'") }
        if let f = live.fixtures.first(where: { $0.id == item.fixtureId }) {
            let home = appModel.club(f.homeClubId)?.shortName ?? "Home"
            let away = appModel.club(f.awayClubId)?.shortName ?? "Away"
            if let h = f.homeScore, let a = f.awayScore {
                parts.append("\(home) \(h)–\(a) \(away)")
            } else {
                parts.append("\(home) v \(away)")
            }
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func impact(points: Int, item: LiveTeam.FeedItem, live: LiveTeam) -> some View {
        let m = multiplier(item, live)
        let total = points * m
        VStack(alignment: .leading, spacing: 8) {
            Text("\(total < 0 ? "−" : "+")\(abs(total)) \(abs(total) == 1 ? "point" : "points")\(m == 2 ? " as captain" : m >= 3 ? " as triple captain" : "")")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(total >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
            Text("Your live score is now \(live.total.estimated).")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.primaryText)
            if let impact = item.impact {
                ConsequenceLine(impact: impact)
            } else if let change = item.rankChangeText {
                Text("Estimated overall rank \(change).")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
                    .accessibilityLabel("Estimated overall \(RankText.spokenChange(change)).")
            }
            if let featured = live.rivals?.featured,
               let gap = live.rivals?.rows.first(where: { $0.entryId == featured.entryId })?.gapText {
                Text("Season: \(gap).")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((total >= 0 ? ToolkitColor.positiveFill : ToolkitColor.warningFill),
                    in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func why(points: Int, item: LiveTeam.FeedItem, live: LiveTeam) -> some View {
        let m = multiplier(item, live)
        SectionHeader(title: "Why")
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.text)
                Spacer()
                Text("\(points < 0 ? "−" : "+")\(abs(points))").monospacedDigit()
            }
            if m > 1 {
                HStack {
                    Text(m >= 3 ? "Triple captain" : "Captain")
                    Spacer()
                    Text("×\(m)").monospacedDigit()
                }
                Divider().overlay(ToolkitColor.border)
                HStack {
                    Text("For you").fontWeight(.semibold)
                    Spacer()
                    Text("\(points * m < 0 ? "−" : "+")\(abs(points * m))").fontWeight(.semibold).monospacedDigit()
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(ToolkitColor.primaryText)
        .padding(15)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    @ViewBuilder private func rivals(_ item: LiveTeam.FeedItem, live: LiveTeam) -> some View {
        if let effects = item.rivals, !effects.isEmpty {
            SectionHeader(title: "Against your rivals")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(effects, id: \.entryId) { effect in
                    Label {
                        Text(effect.text).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: effect.effect >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(effect.effect >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.primaryText)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }
}

// MARK: - Recaps (phase 2)

/// Between spells: what the one that just finished did, and who's next.
struct SpellRecapCard: View {
    let recap: LiveTeam.Pulse.Recap.Spell
    let live: LiveTeam
    let onMoment: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recap.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
            Text("\(recap.points < 0 ? "−" : "+")\(abs(recap.points)) pts")
                .font(.title.weight(.bold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
            if let change = recap.rankChangeText {
                Text("Est. rank \(change)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
                    .accessibilityLabel("Estimated \(RankText.spokenChange(change))")
            }
            if let rival = recap.rival, rival.swing != 0 {
                Text(rival.swing > 0 ? "You gained \(rival.swing) on \(rival.name)" : "\(rival.name) gained \(-rival.swing) on you")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(rival.swing > 0 ? ToolkitColor.positive : ToolkitColor.warning)
            }
            if let best = recap.best {
                Button { onMoment(best.id) } label: {
                    Label("Best moment: \(best.text) · \(best.detail)", systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
            }
            if let next = recap.next {
                let names = next.playerIds.compactMap { live.player($0)?.webName }
                Text("Next up \(next.kickoff.formatted(date: .omitted, time: .shortened))\(names.isEmpty ? "" : ": \(names.joined(separator: ", "))")")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.informationFill, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }
}

/// The gameweek's story once your matches are done, with a share card.
struct FinalRecapCard: View {
    let recap: LiveTeam.Pulse.Recap.Final
    let live: LiveTeam
    let onMoment: (String) -> Void
    @State private var shareImage: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recap.confirmed ? "Gameweek \(recap.gameweek) complete" : "Gameweek \(recap.gameweek) · awaiting bonus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(recap.points)")
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                Text("pts").font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
            }
            .foregroundStyle(ToolkitColor.primaryText)
            .accessibilityElement(children: .combine)
            if let rival = recap.rival {
                Text(FinalRecapCard.rivalLine(rival))
                    .font(.headline)
                    .foregroundStyle(rival.margin >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let decided = recap.decided {
                Button { onMoment(decided.id) } label: {
                    row("The moment that decided it", "\(decided.text) · \(decided.detail)")
                }
                .buttonStyle(.plain)
            }
            if let rank = recap.rank {
                row("Overall rank (estimate)", [rank.text, rank.movementText].compactMap { $0 }.joined(separator: " "))
            }
            if let gain = recap.biggestGain, let name = live.player(gain.playerId)?.webName {
                row("Biggest gain", "\(name) · \(gain.points) pts")
            }
            if let bench = recap.benchPain {
                row("Bench pain", "\(bench.points) pts on your bench\(bench.playerId.flatMap { live.player($0)?.webName }.map { ", most from \($0)" } ?? "")")
            }
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview("My GW\(recap.gameweek)", image: shareImage)) {
                    Label("Share your gameweek", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ToolkitPrimaryButtonStyle())
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .task(id: recap) { shareImage = render() }
    }

    nonisolated static func rivalLine(_ rival: LiveTeam.Pulse.Recap.Final.Rival) -> String {
        let score = "You \(rival.you) – \(rival.them) \(rival.name)"
        switch rival.margin {
        case 0: return "\(score) · level"
        case 1...: return "\(score) · you win by \(rival.margin)"
        default: return "\(score) · \(rival.name) wins by \(-rival.margin)"
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
            Text(value).font(.subheadline).foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @MainActor private func render() -> Image? {
        let renderer = ImageRenderer(content: ShareCard(recap: recap, decided: recap.decided))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// The image people share: score, the result against their rival, the deciding moment. Fixed
/// size and colours (it's a picture, not part of the app's screens).
struct ShareCard: View {
    let recap: LiveTeam.Pulse.Recap.Final
    let decided: LiveTeam.Pulse.Recap.Moment?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("FPLToolkit").font(.system(size: 18, weight: .bold))
                Spacer()
                Text("GW\(recap.gameweek)").font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
            Text("\(recap.points) pts")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let rival = recap.rival {
                Text(FinalRecapCard.rivalLine(rival))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.48, green: 0.83, blue: 0.65))
            }
            if let rank = recap.rank {
                Text("Est. rank \([rank.text, rank.movementText].compactMap { $0 }.joined(separator: " "))")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            if let decided {
                Text("\(decided.text) · \(decided.detail)")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Text("Every kick. What it means for you.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(24)
        .frame(width: 360, height: 450, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 0.06, green: 0.12, blue: 0.10), Color(red: 0.04, green: 0.07, blue: 0.12)],
                                   startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Team pitch (phase 2)

/// Your XI on a pitch, by position, with each player's live context; the bench below.
struct MatchdayPitch: View {
    let live: LiveTeam
    let onPlayer: (Int) -> Void

    var body: some View {
        let xi = live.squad.filter { $0.position <= 11 }
        let bench = live.squad.filter { $0.position > 11 }.sorted { $0.position < $1.position }
        VStack(spacing: 12) {
            ForEach([Position.gk, .def, .mid, .fwd], id: \.self) { position in
                let line = xi.filter { live.player($0.playerId)?.position == position }
                if !line.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(line) { p in tile(p) }
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.10, green: 0.30, blue: 0.18), Color(red: 0.07, green: 0.22, blue: 0.13)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        SectionHeader(title: live.chip == "bboost" ? "Bench (Bench Boost)" : "Bench")
        HStack(alignment: .top, spacing: 6) {
            ForEach(bench) { p in tile(p) }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func tile(_ p: LiveTeam.Player) -> some View {
        // One element per player, as on the Planner's pitch (not a button with readable children).
        VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    PlayerPhoto(path: live.player(p.playerId)?.photo, size: 40)
                    if let role = MatchdayText.role(p, live: live) {
                        Text(role)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(3)
                            .background(Color(red: 0.95, green: 0.78, blue: 0.36), in: Circle())
                            .offset(x: 6, y: -4)
                    }
                }
                Text(live.player(p.playerId)?.webName ?? "Player")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(p.points * max(p.multiplier, 1))\(p.provisionalBonus > 0 ? " +\(p.provisionalBonus)" : "")")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(MatchdayPitch.context(p, live: live))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .opacity(p.counted || p.position > 11 ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture { onPlayer(p.playerId) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MatchdayRowText.spoken(p, live: live).isEmpty ? (live.player(p.playerId)?.webName ?? "Player")
                            : "\(live.player(p.playerId)?.webName ?? "Player"), \(MatchdayRowText.spoken(p, live: live))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPlayer(p.playerId) }
    }

    /// "58′ · CS alive", "9/10 DEFCON", "Sun 14:00": the most useful thing about a player now.
    static func context(_ p: LiveTeam.Player, live: LiveTeam) -> String {
        let fixture = p.fixtureIds.compactMap { live.fixture($0) }.first
        switch p.state {
        case .inPlay:
            var parts = [fixture?.minute.map { "\($0)′" } ?? "Playing"]
            if let d = p.next.defcon, !d.reached { parts.append("\(d.count)/\(d.threshold) DC") }
            else if p.next.cleanSheet?.alive == true { parts.append("CS alive") }
            return parts.joined(separator: " · ")
        case .notStarted:
            return fixture?.kickoff?.formatted(.dateTime.weekday(.abbreviated).hour().minute()) ?? "To play"
        case .done: return p.minutes > 0 ? "\(p.minutes)′" : "Didn't play"
        case .blank: return "No fixture"
        case .unknown: return ""
        }
    }
}
