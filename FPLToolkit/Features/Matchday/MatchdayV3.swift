import SwiftUI

// MARK: - Matchday v3 (tasks/matchday-v3.md, Dan 7 Oct): what did it do to me, the rival race,
// and following your FPL day live.

/// What a moment did to you: "+10 pts (C) · +6 vs Andy · Rank ↑18k", each part green when it helps
/// and amber when it hurts. The words are the server's (`impact`).
struct ConsequenceLine: View {
    let impact: LiveTeam.Impact

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(impact.parts, id: \.self) { part in
                Text(part.text)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(part.value >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(part.value >= 0 ? ToolkitColor.positiveFill : ToolkitColor.warningFill,
                                in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ImpactText.spoken(impact))
    }
}

enum ImpactText {
    /// "plus 10 points as captain, plus 6 against Andy, estimated rank up 18 thousand".
    nonisolated static func spoken(_ impact: LiveTeam.Impact) -> String {
        var parts: [String] = []
        if let p = impact.points {
            let role = p.text.contains("(TC)") ? " as triple captain" : p.text.contains("(C)") ? " as captain" : ""
            parts.append("\(p.value < 0 ? "minus" : "plus") \(abs(p.value)) \(abs(p.value) == 1 ? "point" : "points")\(role)")
        }
        if let r = impact.rival {
            let name = r.text.components(separatedBy: " vs ").last ?? "your rival"
            parts.append("\(r.value < 0 ? "minus" : "plus") \(abs(r.value)) against \(name)")
        }
        if let k = impact.rank {
            parts.append("estimated \(RankText.spokenChange(k.text.replacingOccurrences(of: "Rank ", with: "")))")
        }
        return parts.joined(separator: ", ")
    }
}

/// The rival race at the top of Pulse (Dan's "YOU 54 — 51 ANDY +3"): the score, the biggest swing,
/// what they still have to come, your differentials and the projected finish.
struct MatchdayRaceHeader: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let race: LiveTeam.Pulse.Race
    let chance: LiveTeam.Pulse.WinProbability?
    let onOpen: () -> Void
    let onSwing: (String) -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            score
            if let swing = race.biggestSwing {
                Button { onSwing(swing.itemId) } label: {
                    line("Biggest swing: \(swing.text)", systemImage: "arrow.left.arrow.right",
                         colour: swing.effect >= 0 ? ToolkitColor.positive : ToolkitColor.warning)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows that moment")
            }
            ForEach(race.threats, id: \.self) { threat in
                line(threat, systemImage: "exclamationmark.triangle.fill", colour: ToolkitColor.warning)
            }
            if let differentials = race.differentials {
                line(differentials, systemImage: "star.fill", colour: ToolkitColor.accent)
            }
            if let projected = race.projected {
                line(projected.text, systemImage: "chart.line.uptrend.xyaxis", colour: ToolkitColor.secondaryText)
            }
            if let chance, chance.entryId == race.entryId {
                WinProbabilityBar(chance: chance)
            }
            Button(action: onOpen) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    /// YOU 54 — 51 ANDY, the margin between; stacked at the accessibility sizes.
    private var score: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 10))
        return layout {
            side("YOU", race.you, alignment: .leading)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            Text(race.marginText)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(race.margin > 0 ? ToolkitColor.positive : race.margin < 0 ? ToolkitColor.warning : ToolkitColor.secondaryText)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            side(race.name.uppercased(), race.them, alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RaceText.spokenScore(race))
    }

    private func side(_ label: String, _ points: Int, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(points)")
                .font(.system(size: scoreSize, weight: .bold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
        }
    }

    private func line(_ text: String, systemImage: String, colour: Color) -> some View {
        Label {
            Text(text)
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(colour)
        }
        .font(.subheadline)
    }
}

enum RaceText {
    /// "You 54, Andy 51: you're 3 ahead this gameweek".
    nonisolated static func spokenScore(_ race: LiveTeam.Pulse.Race) -> String {
        let m = race.margin
        let state = m == 0 ? "level" : m > 0 ? "you're \(m) ahead this gameweek" : "\(race.name) is \(-m) ahead this gameweek"
        return "You \(race.you), \(race.name) \(race.them): \(state)"
    }
}

// MARK: - Follow your FPL day live (activation)

enum MatchdayActivation {
    static let window: TimeInterval = 48 * 3600

    /// Whether to offer it: the server has matchday alerts, something is still off, the deadline is
    /// within 48 hours, and it hasn't been put off for this gameweek (or twice already).
    nonisolated static func shouldOffer(
        offered: Bool, alertsOn: Bool, followingOn: Bool, canFollow: Bool, permissionGranted: Bool,
        deadline: Date?, gameweek: Int?, now: Date, dismissedGameweek: Int, dismissCount: Int
    ) -> Bool {
        guard offered, let deadline, let gameweek else { return false }
        let allOn = alertsOn && permissionGranted && (followingOn || !canFollow)
        if allOn || dismissCount >= 2 || dismissedGameweek == gameweek { return false }
        let left = deadline.timeIntervalSince(now)
        return left > 0 && left <= window
    }

    /// On Matchday: any time your gameweek isn't over, unless put off for it (or twice already).
    nonisolated static func shouldOfferOnMatchday(
        offered: Bool, alertsOn: Bool, followingOn: Bool, canFollow: Bool, permissionGranted: Bool,
        gameweek: Int, finished: Bool, dismissedGameweek: Int, dismissCount: Int
    ) -> Bool {
        guard offered, !finished, dismissCount < 2, dismissedGameweek != gameweek else { return false }
        return !(alertsOn && permissionGranted && (followingOn || !canFollow))
    }
}

/// The offer itself: one tap turns on matchday alerts (Normal) and Follow my matchdays, then asks
/// for notifications. Used as a Today card and as a sheet on the first Matchday visit.
struct MatchdayActivationPanel: View {
    @Environment(AppModel.self) private var appModel
    let prefs: DevicePrefs?
    let onNotNow: () -> Void
    /// After it's switched on (with the prefs the server saved).
    let onDone: (DevicePrefs?) -> Void
    @State private var working = false
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: ToolkitSpace.md) {
                Image(systemName: "bolt.fill")
                    .font(.title3)
                    .foregroundStyle(ToolkitColor.onAccent)
                    .frame(width: 44, height: 44)
                    .background(ToolkitColor.accent, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Follow your FPL day live")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Get the moments that affect your team, rank and rivals, even when the app is closed.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if denied {
                Text("Notifications are off for FPLToolkit. Turn them on in Settings to get matchday alerts.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") { appModel.push.openSystemSettings() }
                    .buttonStyle(ToolkitSecondaryButtonStyle())
            } else {
                Button { Task { await activate() } } label: {
                    Text(working ? "Turning it on…" : "Follow my matchday")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ToolkitPrimaryButtonStyle())
                .disabled(working)
                Text("The big moments are pushed; everything else is in Matchday and on your Lock Screen. Change it any time in Settings.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onNotNow) {
                Text(denied ? "Close" : "Not now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.accent.opacity(0.6)))
    }

    private func activate() async {
        working = true
        defer { working = false }
        var current = prefs
        if current == nil { current = try? await appModel.deviceSession.device().prefs }
        guard var notifications = current?.notifications else { return }
        var alerts = (notifications.matchday ?? .standard).applying(.normal)
        alerts.enabled = true
        notifications.matchday = alerts
        let saved = try? await appModel.deviceSession.updatePrefs(
            .init(notifications: notifications,
                  followMatchdays: MatchdayActivity.canFollowMatchdays ? true : nil))
        if appModel.push.permission != .authorized {
            let granted = await appModel.push.requestPermission()
            if !granted {
                denied = true
                return
            }
        }
        onDone(saved?.prefs)
    }
}

/// Matchday's card for your own team, while the gameweek is on (tasks/matchday-v3.md item 1).
struct MatchdayActivationMatchdayCard: View {
    @Environment(AppModel.self) private var appModel
    let gameweek: Int
    let finished: Bool
    @State private var prefs: DevicePrefs?
    @AppStorage("activation.dismissedGW") private var dismissedGameweek = 0
    @AppStorage("activation.dismissCount") private var dismissCount = 0

    var body: some View {
        // Always a view, so the prefs load runs (an empty Group never runs its task).
        VStack(spacing: 0) {
            if let prefs, MatchdayActivation.shouldOfferOnMatchday(
                offered: appModel.pushFeatures?.matchdayAlerts == true,
                alertsOn: prefs.notifications.matchday?.enabled == true,
                followingOn: prefs.followMatchdays == true,
                canFollow: MatchdayActivity.canFollowMatchdays,
                permissionGranted: appModel.push.permission == .authorized,
                gameweek: gameweek, finished: finished,
                dismissedGameweek: dismissedGameweek, dismissCount: dismissCount) {
                MatchdayActivationPanel(prefs: prefs, onNotNow: {
                    dismissedGameweek = gameweek
                    dismissCount += 1
                }, onDone: { saved in self.prefs = saved ?? self.prefs })
            }
        }
        .task(id: gameweek) {
            guard appModel.pushFeatures?.matchdayAlerts == true, !finished else { return }
            prefs = try? await appModel.deviceSession.device().prefs
        }
    }
}

/// Today's card, in the 48 hours before a deadline (tasks/matchday-v3.md item 1).
struct MatchdayActivationCard: View {
    @Environment(AppModel.self) private var appModel
    let next: NextDeadline
    let prefs: DevicePrefs?
    let onChanged: (DevicePrefs?) -> Void
    @AppStorage("activation.dismissedGW") private var dismissedGameweek = 0
    @AppStorage("activation.dismissCount") private var dismissCount = 0

    var body: some View {
        if let prefs, MatchdayActivation.shouldOffer(
            offered: appModel.pushFeatures?.matchdayAlerts == true,
            alertsOn: prefs.notifications.matchday?.enabled == true,
            followingOn: prefs.followMatchdays == true,
            canFollow: MatchdayActivity.canFollowMatchdays,
            permissionGranted: appModel.push.permission == .authorized,
            deadline: next.deadline, gameweek: next.id, now: .now,
            dismissedGameweek: dismissedGameweek, dismissCount: dismissCount) {
            MatchdayActivationPanel(prefs: prefs, onNotNow: {
                dismissedGameweek = next.id
                dismissCount += 1
            }, onDone: onChanged)
        }
    }
}
