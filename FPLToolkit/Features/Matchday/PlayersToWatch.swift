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
    /// `watch=owned,elite&feed=` (contract §34); nothing when nothing is watched. Rivals are your
    /// saved ones now (happy-backend-pal#68), sent separately: the league-position group (above,
    /// below, the leader) isn't asked for any more.
    nonisolated var queryItems: [URLQueryItem] {
        var groups: [String] = []
        if highlyOwned { groups.append("owned") }
        if eliteDifferentials { groups.append("elite") }
        guard !groups.isEmpty else { return [] }
        var items = [URLQueryItem(name: "watch", value: groups.joined(separator: ","))]
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
            // Rivals are their own section now (MatchdayRivalsSection).
            ForEach(groups.filter { $0.kind != .rivals }) { group in
                MatchdayWatchGroupCard(group: group, live: live, onPlayer: onPlayer)
            }
        } else {
            CardGroup {
                LinkRow(title: "Choose who to watch",
                        detail: "Highly owned players or the Elite 100's differentials, live beside your team",
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
}
