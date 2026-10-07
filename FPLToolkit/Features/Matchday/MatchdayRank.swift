import SwiftUI

// MARK: - Matchday v2 phase 3: rank, win probability, leagues

/// The live rank under the score (Dan's concept; Matchday v3 item 5 gives it a bigger stage):
/// "Estimated live rank · ~42.8k → ~28.2k ↑14.6k", always called an estimate, with how it's worked
/// out a tap away. The figures and words are the server's (`rank` on /live/team).
struct MatchdayRankLine: View {
    let rank: LiveTeam.Rank
    @State private var explaining = false

    var body: some View {
        Button { explaining = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Estimated live rank")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.link)
                        .accessibilityHidden(true)
                }
                // One Text, so it wraps as a sentence at large sizes.
                RankText.journey(rank)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RankText.spoken(rank))
        .accessibilityHint("Explains how it's estimated")
        .alert("Estimated rank", isPresented: $explaining) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rank.basis)
        }
    }
}

enum RankText {
    /// "~42.8k → ~28.2k ↑14.6k", the move coloured.
    static func journey(_ rank: LiveTeam.Rank) -> Text {
        let now = rank.previousText.map { "\($0) → \(rank.text)" } ?? rank.text
        guard let move = rank.movementText else { return Text(now) }
        return Text("\(now) \(Text(move).foregroundStyle(colour(rank.movement)))")
    }

    /// Up the table is good news; down is a warning.
    static func colour(_ movement: Int?) -> Color {
        guard let movement, movement != 0 else { return ToolkitColor.secondaryText }
        return movement > 0 ? ToolkitColor.positive : ToolkitColor.warning
    }

    /// "Estimated overall rank about 327,000, up 18,000 places since last gameweek".
    nonisolated static func spoken(_ rank: LiveTeam.Rank) -> String {
        var line = "Estimated overall rank about \(rounded(rank.estimate).formatted())"
        if let movement = rank.movement {
            line += movement == 0
                ? ", the same as last gameweek"
                : ", \(movement > 0 ? "up" : "down") \(rounded(abs(movement)).formatted()) places since last gameweek"
        }
        return line
    }

    /// "↑18k" → "rank up 18 thousand", for VoiceOver.
    nonisolated static func spokenChange(_ text: String) -> String {
        var words = text
            .replacingOccurrences(of: "↑", with: "up ")
            .replacingOccurrences(of: "↓", with: "down ")
            .replacingOccurrences(of: "→", with: "unchanged")
        if words.hasSuffix("k") { words = String(words.dropLast()) + " thousand" }
        if words.hasSuffix("m") { words = String(words.dropLast()) + " million" }
        return "rank \(words)"
    }

    /// Three significant figures: an estimate shouldn't be read out to the last place.
    nonisolated static func rounded(_ n: Int) -> Int {
        guard n >= 1000 else { return n }
        let step = Int(pow(10, floor(log10(Double(n))) - 2))
        return Int((Double(n) / Double(step)).rounded()) * step
    }
}

/// Your chance of beating your featured rival this gameweek (phase 3): a bar split between you.
struct WinProbabilityBar: View {
    let chance: LiveTeam.Pulse.WinProbability
    /// The head-to-head shows how it's worked out; the Pulse card keeps to the bar.
    var showsBasis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chance of winning the gameweek")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                let share = min(max(chance.you, 0.02), 0.98)
                HStack(spacing: 2) {
                    Capsule().fill(ToolkitColor.positive)
                        .frame(width: max(0, (geo.size.width - 2) * share))
                    Capsule().fill(ToolkitColor.warning)
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            Text("You \(chance.youPercent)% · \(chance.name) \(chance.themPercent)%")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if showsBasis {
                Text(chance.basis)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chance of winning the gameweek: you \(chance.youPercent)%, \(chance.name) \(chance.themPercent)%")
        .accessibilityHint(showsBasis ? chance.basis : "")
    }
}

/// "Your leagues, live" (phase 3): where you'd be in each saved mini-league if it ended now.
struct LiveLeaguesSection: View {
    let leagues: [LiveTeam.League]

    var body: some View {
        if !leagues.isEmpty {
            SectionHeader(title: "Your leagues, live")
            VStack(spacing: 0) {
                ForEach(Array(leagues.enumerated()), id: \.element.id) { index, league in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    LiveLeagueRow(league: league)
                }
            }
            .padding(.horizontal, 15)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            Text("If the gameweek ended now, against each league's managers synced to FPLToolkit.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LiveLeagueRow: View {
    let league: LiveTeam.League

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RankText.colour(league.movement))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(league.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(league.text)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = league.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch league.movement {
        case .some(let m) where m > 0: "arrow.up"
        case .some(let m) where m < 0: "arrow.down"
        default: "equal"
        }
    }
}
