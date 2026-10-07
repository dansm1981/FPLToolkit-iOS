import SwiftUI

/// The Deadline reveal (tasks/deadline-reveal.md; Dan, 7 Oct 2026): the first place to go snooping
/// after the deadline. You, then each rival, each saved league and the Elite 100: transfers, hits,
/// chips and captains for the gameweek just locked. Opened from Matchday, Today and the push.
struct DeadlineRevealView: View {
    @Environment(AppModel.self) private var appModel
    @State private var reveal: Reveal?
    @State private var failed: ErrorCopy?
    @State private var pushedRival: Int?
    @State private var pushedLeague: LeagueList.League?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let reveal {
                    content(reveal)
                } else if let failed {
                    ErrorStateView(copy: failed) { Task { await load() } }
                } else {
                    SkeletonCards(caption: "Finding out who did what…")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await load() }
        .task { if reveal == nil { await load() } }
        .toolkitScreen()
        .navigationTitle(reveal.map { "GW\($0.gameweek) deadline reveal" } ?? "Deadline reveal")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushedRival) { RivalView(entryId: $0) }
        .navigationDestination(item: $pushedLeague) { LeagueView(league: $0) }
    }

    private func load() async {
        do {
            reveal = try await appModel.deviceSession.send("GET", "reveal", as: Reveal.self).envelope.data
            failed = nil
        } catch let error as APIError {
            if reveal == nil { failed = ErrorCopy(error) }
        } catch {}
    }

    @ViewBuilder private func content(_ r: Reveal) -> some View {
        if let text = r.readyText {
            Label(text, systemImage: "clock.arrow.circlepath")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToolkitColor.informationFill, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
        if let you = r.you {
            SectionHeader(title: "You")
            RevealManagerCard(name: "Your moves", summary: you.summary, transfers: you.transfers, cost: you.cost,
                              chip: you.chip, captainId: you.captainId, viceId: you.viceId, reveal: r)
        }
        if !r.rivals.isEmpty {
            SectionHeader(title: r.rivals.count == 1 ? "Your rival" : "Your rivals")
            ForEach(r.rivals) { rival in
                Button { pushedRival = rival.entryId } label: {
                    RevealManagerCard(name: rival.name, summary: rival.summary, transfers: rival.transfers,
                                      cost: rival.cost, chip: rival.chip, captainId: rival.captainId,
                                      viceId: rival.viceId, reveal: r, featured: rival.featured,
                                      difference: RevealText.difference(rival, r), opens: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows their team against yours")
            }
        }
        if !r.leagues.isEmpty {
            SectionHeader(title: r.leagues.count == 1 ? "Your league" : "Your leagues")
            ForEach(r.leagues) { league in
                RevealLeagueCard(league: league, reveal: r) {
                    pushedLeague = appModel.leagues.list?.leagues.first { $0.id == league.id }
                }
            }
        }
        if let elite = r.elite {
            SectionHeader(title: "Elite 100")
            RevealEliteCard(elite: elite, reveal: r)
        }
        if r.rivals.isEmpty && r.leagues.isEmpty {
            Text("Save a mini-league or add a rival to see who did what after each deadline.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum RevealText {
    /// "Wissa → Isak"
    static func move(_ m: Reveal.Move, _ r: Reveal) -> String { "\(r.name(m.out)) → \(r.name(m.in))" }

    /// "4 players different from you: Isak, Haaland, Gabriel, Mbeumo"
    static func difference(_ rival: Reveal.Rival, _ r: Reveal) -> String? {
        guard !rival.differenceText.isEmpty else { return nil }
        guard !rival.theirs.isEmpty else { return rival.differenceText }
        return "\(rival.differenceText): \(rival.theirs.map { r.name($0) }.joined(separator: ", "))"
    }

    /// "Isak (8), Saka (5)"
    static func counts(_ list: [Reveal.Count], _ r: Reveal) -> String {
        list.map { "\(r.name($0.playerId)) (\($0.count))" }.joined(separator: ", ")
    }
}

/// One manager's gameweek: who they bought and sold, the hit, the chip and the armband.
struct RevealManagerCard: View {
    let name: String
    let summary: String
    let transfers: [Reveal.Move]
    let cost: Int
    let chip: Reveal.Chip?
    let captainId: Int?
    let viceId: Int?
    let reveal: Reveal
    var featured = false
    var difference: String?
    var opens = false

    var body: some View {
        HStack(alignment: .top, spacing: ToolkitSpace.md) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if featured {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(ToolkitColor.accent)
                            .accessibilityLabel("Featured")
                    }
                }
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    if cost > 0 { Tag(text: "−\(cost) hit", foreground: ToolkitColor.warning, fill: ToolkitColor.warningFill) }
                    if let chip { Tag(text: chip.label, foreground: ToolkitColor.onAccent, fill: ToolkitColor.accent) }
                    if let captainId {
                        Tag(text: "\(reveal.name(captainId)) (\(chip?.chip == "3xc" ? "TC" : "C"))")
                    }
                }
                if transfers.isEmpty {
                    Text(chip?.chip == "freehit" ? "Free Hit team" : "No transfers")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(transfers.enumerated()), id: \.offset) { _, move in
                            Label {
                                Text(RevealText.move(move, reveal))
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundStyle(ToolkitColor.link)
                            }
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        }
                    }
                }
                if let viceId {
                    Text("Vice-captain: \(reveal.name(viceId))")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                if let difference {
                    Text(difference)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if opens {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .accessibilityElement(children: .combine)
    }
}

/// One saved league: who moved, the hits and chips, what they bought, sold and captained, and the
/// leader with the three around you.
struct RevealLeagueCard: View {
    let league: Reveal.League
    let reveal: Reveal
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(league.name)
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(league.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(league.synced ? ToolkitColor.primaryText : ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if league.synced {
                VStack(alignment: .leading, spacing: 4) {
                    if !league.chips.isEmpty {
                        line("Chips", league.chips.map { "\($0.count) \($0.label)" }.joined(separator: ", "))
                    }
                    if !league.mostBought.isEmpty { line("Most bought", RevealText.counts(league.mostBought, reveal)) }
                    if !league.mostSold.isEmpty { line("Most sold", RevealText.counts(league.mostSold, reveal)) }
                    if let captain = league.captainText { line("Captains", captain) }
                }
                Divider().overlay(ToolkitColor.border)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(league.rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.rank.map { "\($0). " } ?? "")\(row.isMe ? "You" : row.name)")
                                .font(.subheadline.weight(row.isMe ? .bold : .semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                            Text(row.summary)
                                .font(.footnote)
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if !row.transfers.isEmpty {
                                Text(row.transfers.map { RevealText.move($0, reveal) }.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(row.isMe ? ToolkitColor.raised.opacity(0.6) : .clear)
                        .accessibilityElement(children: .combine)
                    }
                }
                Button(action: onSeeAll) {
                    HStack {
                        Text("See everyone's transfers")
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
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func line(_ title: String, _ value: String) -> some View {
        Text("\(Text("\(title): ").fontWeight(.semibold))\(value)")
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The Elite 100's gameweek: top buys and sells, captains and chips (totals only).
struct RevealEliteCard: View {
    let elite: Reveal.Elite
    let reveal: Reveal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !elite.bought.isEmpty { line("Top buys", elite.bought) }
            if !elite.sold.isEmpty { line("Top sells", elite.sold) }
            if !elite.captains.isEmpty { line("Captains", elite.captains) }
            let played = elite.chips.filter { $0.value != "0%" && $0.value != "0" }
            if !played.isEmpty {
                Text("Chips: \(played.map { "\($0.label) \($0.value)" }.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The top 100 managers' moves, as totals.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func line(_ title: String, _ rows: [EliteShareRow]) -> some View {
        Text("\(Text("\(title): ").fontWeight(.semibold))\(rows.map { "\(reveal.name($0.playerId)) \($0.display)" }.joined(separator: ", "))")
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The way in from Matchday and Today: "GW6 deadline reveal · see who did what".
struct DeadlineRevealLink: View {
    let gameweek: Int
    /// Before kick-off it's the main thing to see: a bigger card.
    var prominent = false
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: ToolkitSpace.md) {
                Image(systemName: "eye.fill")
                    .font(prominent ? .title3 : .body)
                    .foregroundStyle(prominent ? ToolkitColor.onAccent : ToolkitColor.accent)
                    .frame(width: 44, height: 44)
                    .background(prominent ? ToolkitColor.accent : ToolkitColor.raised, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GW\(gameweek) deadline reveal")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("Your rivals' and leagues' transfers, chips and captains")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay {
                if prominent {
                    RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.accent.opacity(0.6))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
