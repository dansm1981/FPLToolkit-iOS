import SwiftUI

/// S07. The published squad, read-only: starters by line, then the bench.
struct TeamView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int
    @State private var resource: Resource<Team>?
    /// Chances from bookmaker odds (P3-5), shown on the rows when switched on.
    @State private var odds: Resource<Odds>?
    @AppStorage("odds.overlay") private var showOdds = false
    @State private var checkingOdds = false

    var body: some View {
        Group {
            switch resource?.phase {
            case .loading?, nil:
                ScrollView {
                    SkeletonCards(caption: "Loading your squad…", count: 4)
                        .padding(.horizontal, ToolkitSpace.page)
                }
            case .failed(let copy)?:
                ErrorStateView(copy: copy) {
                    Task { await resource?.retry() }
                }
            case .loaded(let loaded)?:
                if let resource {
                    ScrollView {
                        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                            SavedDataBanner(resource: resource)
                            TeamContent(
                                loaded: loaded,
                                onSelectPlayer: { appModel.router.openPlayer($0) },
                                odds: odds?.loaded?.value,
                                showOdds: $showOdds,
                                onOddsCheck: { checkingOdds = true })
                            LeaguesCard()
                                .padding(.top, ToolkitSpace.sm)
                        }
                        .padding(.horizontal, ToolkitSpace.page)
                        .padding(.bottom, ToolkitSpace.section)
                    }
                    .refreshable { await resource.load(bypassCache: true) }
                }
            }
        }
        .toolkitScreen()
        .navigationTitle("My team")
        .settingsButton(entryId: entryId)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    appModel.router.showingMatchday = true
                } label: {
                    Label("Matchday", systemImage: "sportscourt")
                }
            }
        }
        .sheet(isPresented: $checkingOdds) {
            if let team = resource?.loaded?.value, let odds = odds?.loaded?.value {
                NavigationStack { OddsCheckView(team: team, odds: odds) }
            }
        }
        .task {
            if odds == nil {
                let odds = Resource(appModel.liveRepository.odds())
                self.odds = odds
                Task { await odds.load() }
            }
            if resource == nil {
                let resource = Resource(appModel.teamRepository.team(entryId: entryId))
                self.resource = resource
                await resource.load()
            }
        }
    }
}

struct TeamContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let loaded: Loaded<Team>
    var onSelectPlayer: ((Int) -> Void)?
    var odds: Odds?
    var showOdds: Binding<Bool>?
    var onOddsCheck: (() -> Void)?

    private var team: Team { loaded.value }

    private func chance(for player: PlayerSummary) -> OddsChance? {
        guard showOdds?.wrappedValue == true, let odds, odds.available else { return nil }
        return OddsChance.of(player, in: odds)
    }

    private func oddsControls(_ odds: Odds, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show odds")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("Betting-market estimate for GW\(odds.gameweek)")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
            .tint(ToolkitColor.accent)
            .frame(minHeight: 44)
            if let onOddsCheck {
                Button(action: onOddsCheck) {
                    Label("Odds check: captain, defence, bench", systemImage: "chart.bar.xaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ToolkitSpace.lg)
        .padding(.vertical, ToolkitSpace.sm)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.border))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            if let snapshot = team.snapshot {
                header(snapshot)
                if let freeHit = snapshot.freeHitGw {
                    freeHitBanner(freeHit: freeHit, gw: snapshot.gw)
                }
                if let odds, odds.available, let showOdds {
                    oddsControls(odds, isOn: showOdds)
                }
                ForEach(lines(snapshot)) { line in
                    VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                        SectionLabel(text: line.title)
                        VStack(spacing: 0) {
                            ForEach(Array(line.picks.enumerated()), id: \.element.playerId) { index, pick in
                                if let player = team.player(pick.playerId) {
                                    Button {
                                        onSelectPlayer?(pick.playerId)
                                    } label: {
                                        PlayerRow(pick: pick, player: player, chance: chance(for: player))
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Opens the player")
                                    if index < line.picks.count - 1 {
                                        Divider().overlay(ToolkitColor.border)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, ToolkitSpace.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.border))
                    }
                }
                Text("xFDR is fixture difficulty for the next gameweek, from 1 (easiest) to 5 (hardest): attack for midfielders and forwards, clean sheet for goalkeepers and defenders.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            } else {
                noSnapshot
            }

            let sources = (loaded.meta.freshness ?? []).filter { team.snapshot != nil || $0.source != .picks }
            if !sources.isEmpty {
                WhatWeCheckedSection(sources: sources, savedAt: loaded.savedAt)
                    .padding(.top, ToolkitSpace.sm)
            }
        }
    }

    private func header(_ snapshot: Team.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            Text(team.entry.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
            let layout = typeSize >= .xxxLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: ToolkitSpace.sm))
                : AnyLayout(HStackLayout(spacing: ToolkitSpace.sm))
            layout {
                Pill(text: "Published snapshot")
                if typeSize < .xxxLarge { Spacer() }
                readOnly
            }
            Text("Squad as of the GW\(snapshot.gw) deadline, \(Format.deadline(snapshot.deadline)). Changes you've made since then won't show until the next deadline passes.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            let facts = [
                snapshot.activeChip.map { "GW\(snapshot.gw) chip: \(Self.chipName($0))" },
                snapshot.bank.map { "Bank \(Format.price($0))" },
                snapshot.value.map { "Squad value \(Format.price($0))" },
            ].compactMap { $0 }
            if !facts.isEmpty {
                Text(facts.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
    }

    private var readOnly: some View {
        Text("Read-only")
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
    }

    private func freeHitBanner(freeHit: Int, gw: Int) -> some View {
        Label {
            Text("You played your Free Hit in GW\(freeHit), so this is the GW\(gw) squad it reverts to.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.uturn.backward")
        }
        .font(.subheadline)
        .foregroundStyle(ToolkitColor.information)
        .padding(ToolkitSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.informationFill, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private var noSnapshot: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                Text("No published squad yet")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                Text(noSnapshotMessage)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noSnapshotMessage: String {
        if let next = appModel.bootstrap?.value.gameweek.next {
            return "\(team.entry.name) hasn't been through a deadline yet. Your squad will appear here once the GW\(next.id) deadline passes."
        }
        return "\(team.entry.name) hasn't been through a deadline yet. Your squad will appear here once the next deadline passes."
    }

    private struct Line: Identifiable {
        let title: String
        let picks: [Team.Pick]
        var id: String { title }
    }

    private func lines(_ snapshot: Team.Snapshot) -> [Line] {
        let starters = snapshot.picks.filter { $0.role != .bench }.sorted { $0.slot < $1.slot }
        let bench = snapshot.picks.filter { $0.role == .bench }.sorted { $0.slot < $1.slot }
        func line(_ position: Position) -> [Team.Pick] {
            starters.filter { team.player($0.playerId)?.position == position }
        }
        let known: Set<Position> = [.gk, .def, .mid, .fwd]
        return [
            Line(title: "Goalkeeper", picks: line(.gk)),
            Line(title: "Defenders", picks: line(.def)),
            Line(title: "Midfielders", picks: line(.mid)),
            Line(title: "Forwards", picks: line(.fwd)),
            Line(title: "Starting", picks: starters.filter { !known.contains(team.player($0.playerId)?.position ?? .unknown) }),
            Line(title: "Bench", picks: bench),
        ].filter { !$0.picks.isEmpty }
    }

    static func chipName(_ code: String) -> String {
        switch code {
        case "wildcard": "Wildcard"
        case "freehit": "Free Hit"
        case "bboost": "Bench Boost"
        case "3xc": "Triple Captain"
        default: code
        }
    }
}

/// One squad member: name, captaincy, availability, club and price, and the next fixture with xFDR.
struct PlayerRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let pick: Team.Pick
    let player: PlayerSummary
    /// The betting-market chance for this player's position, when odds are switched on.
    var chance: OddsChance?

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ToolkitSpace.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: ToolkitSpace.md))
        layout {
            HStack(spacing: ToolkitSpace.md) {
                PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: ToolkitSpace.sm) {
                        Text(player.webName)
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        if pick.isCaptain { RoleBadge(letter: "C") }
                        if pick.isViceCaptain { RoleBadge(letter: "V") }
                        AvailabilityBadge(availability: player.availability)
                    }
                    ClubLabel(clubId: player.clubId, text: details)
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    if let chance {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar.xaxis")
                                .accessibilityHidden(true)
                            Text(chance.text)
                            if let move = chance.movement {
                                Text(move)
                                    .foregroundStyle(move.hasPrefix("↑") ? ToolkitColor.positive : ToolkitColor.error)
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(chance.spoken)
                    }
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: ToolkitSpace.sm) }
            if let fixture = player.nextFixture {
                FixtureSummary(fixture: fixture)
            }
        }
        .padding(.vertical, ToolkitSpace.md)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts: [String] = []
        if let club = appModel.club(player.clubId) { parts.append(club.shortName) }
        parts.append(player.position.rawValue)
        parts.append(Format.price(player.price))
        return parts.joined(separator: " · ")
    }
}

struct RoleBadge: View {
    let letter: String
    var body: some View {
        Text(letter)
            .font(.caption.weight(.heavy))
            .foregroundStyle(ToolkitColor.onAccent)
            .frame(width: 22, height: 22)
            .background(ToolkitColor.accent, in: Circle())
            .accessibilityLabel(letter == "C" ? "Captain" : "Vice-captain")
    }
}

/// Nothing for available players; an icon plus the published chance (never colour alone) otherwise.
struct AvailabilityBadge: View {
    let availability: PlayerSummary.Availability

    var body: some View {
        switch availability.level {
        case .ok, .unknown:
            EmptyView()
        case .doubt, .out:
            let isOut = availability.level == .out
            Label(chanceText, systemImage: isOut ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOut ? ToolkitColor.error : ToolkitColor.warning)
                .accessibilityLabel(availability.news ?? (isOut ? "Out" : "Doubtful"))
        }
    }

    private var chanceText: String {
        if let chance = availability.chanceNext { return "\(chance)%" }
        return availability.level == .out ? "Out" : "Doubt"
    }
}

/// "CHE (H)" with the xFDR value, or "No fixture" in a blank gameweek.
struct FixtureSummary: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let fixture: FixtureDifficulty

    var body: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
            Text(opponent)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
            if let xfdr = fixture.xfdr {
                Text("xFDR \(xfdr.value.formatted(.number.precision(.fractionLength(1))))\(xfdr.source == .fpl ? " (FPL)" : "")")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ToolkitColor.raised, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var opponent: String {
        if fixture.blank { return "No fixture" }
        let name = appModel.club(fixture.opponentClubId)?.shortName ?? "TBC"
        guard let home = fixture.home else { return name }
        return "\(name) (\(home ? "H" : "A"))"
    }

    private var accessibilityText: String {
        if fixture.blank { return "No fixture in gameweek \(fixture.gw)" }
        let name = appModel.club(fixture.opponentClubId)?.name ?? "opponent to be confirmed"
        let venue = fixture.home.map { $0 ? "at home" : "away" } ?? ""
        let difficulty = fixture.xfdr.map { ", difficulty \($0.value.formatted(.number.precision(.fractionLength(1)))) out of 5" } ?? ""
        return "Next: \(name) \(venue)\(difficulty)"
    }
}

#if DEBUG
#Preview("Published") {
    NavigationStack {
        ScrollView {
            TeamContent(loaded: PreviewFixtures.load("team-71191", as: Team.self))
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("My team")
    }
    .environment(AppModel())
}

#Preview("Free Hit") {
    NavigationStack {
        ScrollView {
            TeamContent(loaded: PreviewFixtures.load("team-895045-freehit", as: Team.self))
                .padding(.horizontal, ToolkitSpace.page)
        }
        .toolkitScreen()
        .navigationTitle("My team")
    }
    .environment(AppModel())
}
#endif
