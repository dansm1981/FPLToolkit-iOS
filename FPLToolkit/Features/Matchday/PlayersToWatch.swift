import SwiftUI

// MARK: - Settings

/// Matchday's players to watch (Dan, 2 Oct 2026; happy-backend-pal#66): beside your own team, the
/// players who move your rank. The settings are saved on the server with the device's other prefs
/// (Settings → Notifications → Live matchday); this keeps a copy on the phone so each live request
/// can say what to watch without asking for them first.
enum MatchdayWatch {
    static let storageKey = "matchday.watch"

    /// What this phone last saved, else the server's defaults (highly owned only). UI tests pass
    /// `-matchdayWatch owned,elite,rivals -matchdayWatchLeague <id>` instead.
    nonisolated static var current: DevicePrefs.MatchdayPrefs {
        let defaults = UserDefaults.standard
        if let groups = defaults.string(forKey: "matchdayWatch") {
            let names = Set(groups.split(separator: ",").map(String.init))
            let league = defaults.integer(forKey: "matchdayWatchLeague")
            var prefs = DevicePrefs.MatchdayPrefs.standard
            prefs.highlyOwned = names.contains("owned")
            prefs.eliteDifferentials = names.contains("elite")
            prefs.rivals = names.contains("rivals")
            prefs.rivalsLeague = league > 0 ? league : nil
            return prefs
        }
        guard let data = defaults.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(DevicePrefs.MatchdayPrefs.self, from: data)
        else { return .standard }
        return prefs
    }

    /// Keeps the phone's copy in step with what the server saved; nil (an older server) leaves it.
    static func remember(_ prefs: DevicePrefs.MatchdayPrefs?) {
        guard let prefs, let data = try? JSONEncoder().encode(prefs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// A league taken off the device stops being the rivals' league (the server does the same).
    static func leagueRemoved(_ leagueId: Int) {
        var prefs = current
        guard prefs.rivalsLeague == leagueId else { return }
        prefs.rivalsLeague = nil
        remember(prefs)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

extension DevicePrefs.MatchdayPrefs {
    /// `watch=owned,elite,rivals&league=&above=&below=&leader=&feed=` (contract §34); nothing when
    /// nothing is watched. Rivals need a league.
    nonisolated var queryItems: [URLQueryItem] {
        var groups: [String] = []
        if highlyOwned { groups.append("owned") }
        if eliteDifferentials { groups.append("elite") }
        let league = rivals ? rivalsLeague : nil
        if league != nil { groups.append("rivals") }
        guard !groups.isEmpty else { return [] }
        var items = [URLQueryItem(name: "watch", value: groups.joined(separator: ","))]
        if let league {
            items.append(URLQueryItem(name: "league", value: String(league)))
            items.append(URLQueryItem(name: "above", value: String(rivalsAbove)))
            items.append(URLQueryItem(name: "below", value: String(rivalsBelow)))
            if !rivalsLeader { items.append(URLQueryItem(name: "leader", value: "0")) }
        }
        if !inFeed { items.append(URLQueryItem(name: "feed", value: "0")) }
        return items
    }

    /// Whether Matchday shows anything beside your team.
    var watchesAnyone: Bool { !queryItems.isEmpty }
}

// MARK: - Matchday → Your team

/// "Players to watch" under the bench: a card per group the server sent, in its order.
struct MatchdayWatchingSection: View {
    let live: LiveTeam
    let onPlayer: (Int, String) -> Void
    let onSettings: () -> Void

    var body: some View {
        SectionHeader(title: "Players to watch", actionTitle: "Choose", action: onSettings)
        if let groups = live.watching?.groups, !groups.isEmpty {
            ForEach(groups) { group in
                switch group.kind {
                case .rivals: MatchdayRivalsCard(group: group, live: live, onPlayer: onPlayer)
                default: MatchdayWatchGroupCard(group: group, live: live, onPlayer: onPlayer)
                }
            }
        } else {
            CardGroup {
                LinkRow(title: "Choose who to watch",
                        detail: "Highly owned players, the Elite 100's differentials or your mini-league rivals, live beside your team",
                        systemImage: "eye",
                        action: onSettings)
            }
        }
    }
}

/// The title and line of explanation that open each card.
private struct WatchCardHeader: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

/// Highly owned players or the Elite's differentials.
struct MatchdayWatchGroupCard: View {
    let group: LiveTeam.Watching.Group
    let live: LiveTeam
    let onPlayer: (Int, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WatchCardHeader(title: group.title, detail: group.detail)
            if group.players.isEmpty {
                Divider().overlay(ToolkitColor.border)
                Text("None of them play this gameweek.")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            }
            ForEach(group.players) { player in
                Divider().overlay(ToolkitColor.border)
                WatchedPlayerRow(player: player, live: live, onPlayer: onPlayer)
            }
        }
        .padding(.horizontal, 14)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }
}

/// One watched player: why they're watched and how their match is going; opens their page.
struct WatchedPlayerRow: View {
    let player: LiveTeam.Watching.WatchedPlayer
    let live: LiveTeam
    let onPlayer: (Int, String) -> Void

    var body: some View {
        if let summary = live.player(player.playerId) {
            Button { onPlayer(player.playerId, player.reason) } label: {
                // Wraps between its facts ("Elite 54% · everyone 29% · Yet to play"), never inside one.
                PlayerListRow(player: summary,
                              detail: Format.unbroken("\(player.reason) · \(WatchText.state(player))"),
                              value: "\(player.points)",
                              valueDetail: player.provisionalBonus > 0 ? "+\(player.provisionalBonus) est." : nil,
                              spokenDetail: WatchText.spoken(player),
                              wrapsDetail: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the player")
        }
    }
}

/// Mini-league rivals: their live score beside yours; tap one for their captain and the players
/// they have that you don't.
struct MatchdayRivalsCard: View {
    let group: LiveTeam.Watching.Group
    let live: LiveTeam
    let onPlayer: (Int, String) -> Void
    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WatchCardHeader(title: group.title, detail: group.detail)
            if group.rivals.isEmpty, group.detail?.hasPrefix("Live") == true {
                Divider().overlay(ToolkitColor.border)
                Text("No managers to show with these settings.")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            }
            ForEach(group.rivals) { rival in
                Divider().overlay(ToolkitColor.border)
                rivalRow(rival)
                if expanded.contains(rival.entryId) {
                    ForEach(rival.players) { player in
                        Divider().overlay(ToolkitColor.border).padding(.leading, 14)
                        WatchedPlayerRow(player: player, live: live, onPlayer: onPlayer)
                            .padding(.leading, 14)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    @ViewBuilder private func rivalRow(_ rival: LiveTeam.Watching.Rival) -> some View {
        let open = expanded.contains(rival.entryId)
        let row = NameFigureRow {
            Text(rival.manager ?? rival.team ?? "Manager")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
        } details: {
            VStack(alignment: .leading, spacing: 2) {
                FactLine(rival.label)
                if let line = WatchText.rivalDetail(rival, live: live) { FactLine(line) }
            }
            .font(.caption)
            .foregroundStyle(ToolkitColor.secondaryText)
        } figure: {
            HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(rival.live.map(String.init) ?? "–")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("you \(live.total.confirmed)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                if !rival.players.isEmpty {
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WatchText.spoken(rival, live: live))

        if rival.players.isEmpty {
            row
        } else {
            Button {
                withAnimation(.snappy) {
                    if open { expanded.remove(rival.entryId) } else { expanded.insert(rival.entryId) }
                }
            } label: { row }
                .buttonStyle(.plain)
                .accessibilityHint(open ? "Hides their players" : "Shows their captain and the players they have that you don't")
                .accessibilityAddTraits(open ? .isSelected : [])
        }
    }
}

enum WatchText {
    /// "Playing · 60 min", "Finished · 90 min", "Yet to play".
    nonisolated static func state(_ player: LiveTeam.Watching.WatchedPlayer) -> String {
        switch player.state {
        case .blank: "No match"
        case .notStarted: "Yet to play"
        case .inPlay: "Playing · \(player.minutes) min"
        case .done: player.minutes > 0 ? "Finished · \(player.minutes) min" : "Didn't play"
        case .unknown: ""
        }
    }

    nonisolated static func spoken(_ player: LiveTeam.Watching.WatchedPlayer) -> String {
        var parts = [player.reason, state(player), "\(player.points) FPL-recorded point\(player.points == 1 ? "" : "s")"]
        if player.provisionalBonus > 0 { parts.append("plus \(player.provisionalBonus) estimated bonus, not included") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Their team name when the manager leads, their captain, and their estimated bonus.
    nonisolated static func rivalDetail(_ rival: LiveTeam.Watching.Rival, live: LiveTeam) -> String? {
        var parts: [String] = []
        if rival.manager != nil, let team = rival.team { parts.append(team) }
        if let name = live.player(rival.captainId)?.webName { parts.append("Captain \(name)") }
        if rival.live == nil { parts.append("Team not synced yet") }
        if rival.provisionalBonus > 0 { parts.append("+\(rival.provisionalBonus) est. bonus") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    nonisolated static func spoken(_ rival: LiveTeam.Watching.Rival, live: LiveTeam) -> String {
        var parts = [rival.manager ?? rival.team ?? "Manager", rival.label]
        if let live = rival.live {
            parts.append("\(live) points this gameweek")
        }
        parts.append("you have \(live.total.confirmed)")
        if let detail = rivalDetail(rival, live: live) { parts.append(detail) }
        return parts.joined(separator: ", ")
    }
}
