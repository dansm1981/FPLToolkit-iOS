import SwiftUI

/// My Team → List (Dan, 29 Sep: "the single view to see my team info"): each player with his
/// odds (clean sheet, goal, goal or assist), whether his price is heading up or down, his chance
/// of playing and news, and the next six gameweeks' difficulty, all in one row. Every figure is
/// the server's; missing ones are left out, never shown as 0%.
struct TeamListRow: View {
    @Environment(AppModel.self) private var appModel
    let player: PlayerSummary
    /// "C" or "V".
    let role: String?
    let odds: Odds?
    /// FPL's progress towards his next price change, when he's among the nearest.
    let price: MarketPredictions.Row?
    let run: [ResearchTicker.Cell]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(player.webName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                    if let role {
                        Text(role)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(ToolkitColor.onAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(ToolkitColor.accent, in: Capsule())
                            .accessibilityHidden(true)
                    }
                }
                ClubLabel(clubId: player.clubId,
                          text: [appModel.club(player.clubId)?.shortName, player.position.rawValue, Format.price(player.price)]
                            .compactMap { $0 }.joined(separator: " · "),
                          logoSize: 12)
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
                let chips = self.chips
                if !chips.isEmpty {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(chips, id: \.self) { RowChipView(chip: $0) }
                    }
                }
                if player.availability.level != .ok, let news = player.availability.news, !news.isEmpty {
                    Text(news)
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !run.isEmpty {
                    RunStrip(cells: run)
                        .padding(.top, 2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Facts

    private var chips: [RowChip] {
        var chips: [RowChip] = []
        switch player.availability.level {
        case .out:
            chips.append(RowChip(text: player.availability.chanceNext.map { "\($0)% to play" } ?? "Out", tone: .down))
        case .doubt:
            chips.append(RowChip(text: player.availability.chanceNext.map { "\($0)% to play" } ?? "Doubtful", tone: .warn))
        default:
            break
        }
        if let risk = player.suspensionRisk {
            chips.append(RowChip(text: risk.chip, tone: .warn))
        }
        chips.append(contentsOf: oddsChips)
        if let price {
            let text = price.progress >= 0 ? "Rise \(price.progressDisplay)" : "Fall \(price.progressDisplay)"
            chips.append(RowChip(text: text.replacingOccurrences(of: "-", with: ""), tone: price.progress >= 0 ? .up : .down))
        }
        return chips
    }

    /// Clean sheet for keepers and defenders, scoring for everyone the market prices.
    private var oddsChips: [RowChip] {
        guard let odds, odds.available else { return [] }
        var chips: [RowChip] = []
        if player.position == .gk || player.position == .def,
           let cs = OddsChance.of(player, in: odds) {
            chips.append(RowChip(text: "CS \(OddsChance.percent(cs.value))"))
        }
        if player.position != .gk, let p = odds.player(player.id) {
            if let scorer = p.scorer { chips.append(RowChip(text: "Goal \(OddsChance.percent(scorer))")) }
            if let either = p.scoreOrAssist, player.position != .def {
                chips.append(RowChip(text: "G/A \(OddsChance.percent(either))"))
            }
        }
        return chips
    }

    private var spoken: String {
        var parts = [player.webName]
        if role == "C" { parts.append("captain") }
        if role == "V" { parts.append("vice-captain") }
        parts.append(contentsOf: [appModel.club(player.clubId)?.name, player.position.displayName, Format.price(player.price)].compactMap { $0 })
        if let risk = player.suspensionRisk { parts.append(risk.spoken) }
        parts.append(contentsOf: chips.filter { !$0.text.contains("ban at") }.map { chip in
            chip.text.replacingOccurrences(of: "CS ", with: "clean sheet ")
                .replacingOccurrences(of: "G/A ", with: "goal or assist ")
        })
        if player.availability.level != .ok, let news = player.availability.news { parts.append(news) }
        if let run = FixtureRunColumn.spoken(run) { parts.append(run) }
        return parts.joined(separator: ", ")
    }
}

/// The next gameweeks' difficulty as a row of small numbered cells; decorative (the row reads it).
private struct RunStrip: View {
    let cells: [ResearchTicker.Cell]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(cells, id: \.gw) { cell in
                let first = cell.fixtures.first
                let band = first?.band
                Text(cell.blank || first == nil ? "–" : (first?.value == nil ? "?" : first!.display) + (cell.fixtures.count > 1 ? "+" : ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(band.map(DifficultyColor.text) ?? ToolkitColor.secondaryText)
                    .padding(.horizontal, 3)
                    .frame(minWidth: 30, minHeight: 20)
                    .background(band.map(DifficultyColor.fill) ?? ToolkitColor.raised, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .accessibilityHidden(true)
    }
}
