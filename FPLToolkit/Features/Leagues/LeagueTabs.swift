import SwiftUI

// The website's remaining Leagues tabs (P2-10b): Rivals, Players, Captains, Chips, Transfers,
// History and Report. Each lays out the server's answer; the numbers are the website's.

/// A titled card of rows.
private struct LeagueCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: title)
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A two-line row: a name, then the details; the value on the right. With a player it takes the
/// app's standard look (Dan, 29 Sep): photo, club badge, the gold shirt when he's in your team,
/// and short facts as chips.
private struct LeagueRow: View {
    @Environment(AppModel.self) private var appModel
    let title: String
    var player: PlayerSummary?
    var detail: String?
    var chips: [RowChip] = []
    var value: String?

    var body: some View {
        HStack(alignment: player == nil ? .firstTextBaseline : .center, spacing: ToolkitSpace.sm) {
            if let player {
                PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo, size: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(ToolkitColor.primaryText)
                    if let player, appModel.squadIds.contains(player.id) {
                        Image(systemName: "tshirt.fill")
                            .font(.caption2)
                            .foregroundStyle(ToolkitColor.accent)
                            .accessibilityLabel("in your team")
                    }
                }
                if let player {
                    ClubLabel(clubId: player.clubId,
                              text: [appModel.club(player.clubId)?.shortName, player.position.rawValue, Format.price(player.price)]
                                .compactMap { $0 }.joined(separator: " · "),
                              logoSize: 11)
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
                }
                if !chips.isEmpty {
                    FlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(chips, id: \.self) { RowChipView(chip: $0) }
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ToolkitSpace.sm)
            if let value {
                Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(ToolkitColor.primaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private func pct(_ value: Double) -> String { "\(Int(value.rounded()))%" }

// MARK: - Rivals

struct LeagueRivalsSection: View {
    let data: LeagueRivals
    let onManager: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            LeagueCard(title: "Your current rivals") {
                if data.rivals.isEmpty {
                    Text("Connect your FPL team to identify your rivals.").font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
                }
                ForEach(data.rivals) { rival in
                    Button { onManager(rival.entryId) } label: {
                        LeagueRow(
                            title: rival.displayName,
                            detail: ([rival.teamName].compactMap { $0 } + rival.reasons + ["\(rival.shared)/15 shared"]).joined(separator: " · "),
                            value: rival.pointsDiff == 0 ? "Level" : rival.pointsDiff > 0 ? "\(rival.pointsDiff) ahead" : "\(-rival.pointsDiff) behind"
                        )
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Compares their team with yours")
                }
            }
            similarity("Managers most similar to you", data.mostSimilar)
            similarity("Managers most different from you", data.mostDifferent)
        }
    }

    @ViewBuilder
    private func similarity(_ title: String, _ rows: [LeagueSimilar]) -> some View {
        if !rows.isEmpty {
            LeagueCard(title: title) {
                ForEach(rows, id: \.manager.entryId) { row in
                    Button { onManager(row.manager.entryId) } label: {
                        LeagueRow(title: row.manager.displayName, value: "\(row.similarity)%").frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Players

struct LeaguePlayersSection: View {
    @Environment(AppModel.self) private var appModel
    let data: LeaguePlayers

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            intel("Your biggest threats", data.threats)
            intel("Your biggest opportunities", data.opportunities)
            LeagueCard(title: "\(data.league.name) template XI") {
                Text("Formation \(data.template.formation) · you own \(data.template.owned)/11" + (data.template.similarityPct.map { " · template similarity \($0)%" } ?? ""))
                    .font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
                ForEach([Position.gk, .def, .mid, .fwd], id: \.self) { position in
                    let names = data.template.xi.filter { data.player($0)?.position == position }.map(data.name)
                    if !names.isEmpty {
                        LeagueRow(title: position.plural, detail: names.joined(separator: ", "))
                    }
                }
                if !data.template.bench.isEmpty {
                    Text("Template bench: " + data.template.bench.map(data.name).joined(separator: ", "))
                        .font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
                }
            }
            consensus("This league loves", data.loves)
            consensus("This league is avoiding", data.avoids)
            LeagueCard(title: data.league.syncedGw.map { "Captaincy — GW\($0)" } ?? "Captaincy") {
                if data.captaincy.isEmpty { Text("No captain data yet.").foregroundStyle(ToolkitColor.secondaryText) }
                ForEach(data.captaincy) { c in
                    LeagueRow(title: data.name(c.playerId), player: data.player(c.playerId), value: "\(pct(c.pct)) (\(c.count))")
                }
            }
            LeagueCard(title: data.league.syncedGw.map { "League ownership — GW\($0)" } ?? "League ownership") {
                ForEach(data.ownership) { o in
                    LeagueRow(title: data.name(o.playerId), player: data.player(o.playerId),
                              chips: [RowChip(text: "Starts \(o.started)"), RowChip(text: "EO \(pct(o.eo))"),
                                      .change("All \(pct(o.globalPct))", o.ownedPct - o.globalPct)],
                              value: pct(o.ownedPct))
                }
            }
        }
    }

    private func intel(_ title: String, _ rows: [LeagueIntel]) -> some View {
        LeagueCard(title: title) {
            if rows.isEmpty { Text("Nothing to show yet.").foregroundStyle(ToolkitColor.secondaryText) }
            ForEach(rows) { r in
                LeagueRow(title: data.name(r.playerId), player: data.player(r.playerId),
                          chips: [RowChip(text: r.band), RowChip(text: "EO \(pct(r.eo))"),
                                  RowChip(text: "League \(pct(r.leagueOwnPct))"), RowChip(text: "All \(pct(r.globalPct))"),
                                  .change("\(r.gapPp >= 0 ? "+" : "")\(Int(r.gapPp.rounded()))pp", r.gapPp)],
                          value: "\(r.score)")
            }
        }
    }

    @ViewBuilder
    private func consensus(_ title: String, _ rows: [LeaguePlayers.Consensus]) -> some View {
        if !rows.isEmpty {
            LeagueCard(title: title) {
                ForEach(rows) { c in
                    LeagueRow(title: data.name(c.playerId), player: data.player(c.playerId),
                              chips: [RowChip(text: "League \(pct(c.leaguePct))"), RowChip(text: "All \(pct(c.globalPct))")],
                              value: "\(c.gapPp >= 0 ? "+" : "")\(Int(c.gapPp.rounded()))pp")
                }
            }
        }
    }
}

// MARK: - Captains

struct LeagueCaptainsSection: View {
    let data: LeagueCaptains
    let onManager: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            LeagueCard(title: "League captaincy trend") {
                if data.trend.isEmpty { Text("No captain data for these gameweeks yet.").foregroundStyle(ToolkitColor.secondaryText) }
                ForEach(data.trend.reversed(), id: \.gw) { row in
                    LeagueRow(title: "GW\(row.gw) · \(row.total) managers",
                              detail: row.top.map { "\(data.name($0.playerId)) \(pct($0.pct))" }.joined(separator: " · "))
                }
            }
            LeagueCard(title: data.gws.first.map { "Captain history — GW\($0)–\(data.gws.last ?? $0)" } ?? "Captain history") {
                ForEach(data.rows, id: \.manager.entryId) { row in
                    Button { onManager(row.manager.entryId) } label: {
                        LeagueRow(title: row.manager.displayName,
                                  detail: zip(data.gws, row.captains).map { "GW\($0) \(data.name($1))" }.joined(separator: " · "))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Chips

struct LeagueChipsSection: View {
    let data: LeagueChips
    let onManager: (Int) -> Void
    private let order = ["wildcard", "freehit", "bboost", "3xc"]
    private let short = ["wildcard": "WC", "freehit": "FH", "bboost": "BB", "3xc": "TC"]

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            LeagueCard(title: "League chip usage") {
                ForEach(data.usage, id: \.chip) { u in
                    LeagueRow(title: u.label, detail: "\(u.left) still available", value: "\(u.used) played")
                }
            }
            LeagueCard(title: "Chips remaining by manager") {
                ForEach(data.rows, id: \.manager.entryId) { row in
                    Button { onManager(row.manager.entryId) } label: {
                        LeagueRow(title: row.manager.displayName,
                                  detail: "Left: " + order.map { "\(short[$0] ?? $0) \(row.remaining[$0] ?? 2)" }.joined(separator: " · ")
                                      + " · Played: " + (row.used.isEmpty ? "none" : row.used.map { "\($0.label)\($0.gw)" }.joined(separator: " ")))
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Transfers

struct LeagueTransfersSection: View {
    let data: LeagueTransfers
    @Binding var recent: Bool
    let onManager: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            Picker("Window", selection: $recent) {
                Text(data.league.syncedGw.map { "GW\($0)" } ?? "This gameweek").tag(false)
                Text("Last 6 GWs").tag(true)
            }
            .pickerStyle(.segmented)
            Text("\(data.total) transfers made by this league.").font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
            moves("Most bought", data.bought, sign: "+", other: "Sold for")
            moves("Most sold", data.sold, sign: "−", other: "Bought instead")
            LeagueCard(title: "Transfer activity by gameweek") {
                if data.trend.isEmpty { Text("No transfer history yet.").foregroundStyle(ToolkitColor.secondaryText) }
                ForEach(data.trend, id: \.gw) { t in
                    LeagueRow(title: "GW\(t.gw)", detail: "\(t.managersActive) managers" + (t.hits > 0 ? " · −\(t.hits)" : ""), value: "\(t.transfers) moves")
                }
            }
            LeagueCard(title: data.league.syncedGw.map { "Manager transfer feed — GW\($0)" } ?? "Manager transfer feed") {
                ForEach(data.feed, id: \.manager.entryId) { f in
                    Button { onManager(f.manager.entryId) } label: {
                        LeagueRow(title: f.manager.displayName, detail: feedText(f)).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func feedText(_ f: LeagueTransfers.Feed) -> String {
        var parts = f.transfers.isEmpty ? ["No transfer"] : f.transfers.map { "\(data.name($0.out)) → \(data.name($0.in))" }
        if f.cost > 0 { parts.append("−\(f.cost)") } else if !f.transfers.isEmpty { parts.append("Free") }
        if let chip = f.chip { parts.append(chip.label) }
        return parts.joined(separator: " · ")
    }

    private func moves(_ title: String, _ rows: [LeagueTransfers.Intel], sign: String, other: String) -> some View {
        LeagueCard(title: title) {
            if rows.isEmpty { Text("No transfers in this window.").foregroundStyle(ToolkitColor.secondaryText) }
            ForEach(rows) { r in
                LeagueRow(title: data.name(r.playerId),
                          detail: "\(other): " + r.counterparts.map { "\(data.name($0.playerId))\($0.count > 1 ? " ×\($0.count)" : "")" }.joined(separator: ", ")
                              + (r.managers.isEmpty ? "" : " · by " + r.managers.map(\.name).joined(separator: ", ")),
                          value: "\(sign)\(r.count) (\(pct(r.pct)))")
            }
        }
    }
}

// MARK: - History

struct LeagueHistorySection: View {
    let data: LeagueHistory
    let onManager: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            LeagueCard(title: "League position over the season") {
                if data.positions.allSatisfy({ $0.points.isEmpty }) {
                    Text("No gameweek history synced yet.").foregroundStyle(ToolkitColor.secondaryText)
                }
                ForEach(data.positions, id: \.manager.entryId) { p in
                    Button { onManager(p.manager.entryId) } label: {
                        LeagueRow(title: p.manager.displayName,
                                  detail: p.points.map { "GW\($0.gw) \($0.rank)" }.joined(separator: " · "),
                                  value: p.points.last.map { $0.gapToLeader == 0 ? "leader" : "−\($0.gapToLeader)" })
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            LeagueCard(title: "Season performance") {
                if data.performance.isEmpty { Text("No history yet.").foregroundStyle(ToolkitColor.secondaryText) }
                ForEach(data.performance, id: \.entryId) { r in
                    LeagueRow(title: r.manager?.displayName ?? "Manager \(r.entryId)",
                              detail: [
                                  "Best " + (r.best.map { "\($0.points) (GW\($0.gw))" } ?? "–"),
                                  "Worst " + (r.worst.map { "\($0.points) (GW\($0.gw))" } ?? "–"),
                                  "\(r.transfers) transfers",
                                  "hits " + (r.hitPoints > 0 ? "−\(r.hitPoints)" : "0"),
                                  "bench \(r.benchPoints)",
                                  "wasted \(r.wastage)",
                              ].joined(separator: " · "),
                              value: "avg " + r.avgPoints.formatted(.number.precision(.fractionLength(1))))
                }
            }
        }
    }
}

// MARK: - Report

struct LeagueReportSection: View {
    let data: LeagueReport
    @Binding var gw: Int?

    var body: some View {
        let r = data.report
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            HStack {
                Picker("Gameweek", selection: Binding(get: { gw ?? data.gw }, set: { gw = $0 })) {
                    ForEach(data.gws, id: \.self) { Text("GW\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                Spacer()
                ShareLink(item: data.text) {
                    Label("Share report", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .frame(minHeight: 44)
                }
            }
            LeagueCard(title: "\(data.league.name) — GW\(data.gw)") {
                if let w = r.winner { LeagueRow(title: "GW winner", detail: w.manager.name, value: "\(w.points) pts") }
                LeagueRow(title: "League average", detail: "\(r.managers) managers", value: r.average.formatted(.number.precision(.fractionLength(1))))
                if let l = r.leader { LeagueRow(title: "Overall leader", detail: l.manager.name, value: "\(l.total) pts") }
                if let c = r.climber { LeagueRow(title: "Biggest climber", detail: c.manager.name, value: "+\(c.places) places") }
                if let f = r.faller { LeagueRow(title: "Biggest faller", detail: f.manager.name, value: "\(f.places) places") }
                if let c = r.bestCaptain { LeagueRow(title: "Best captain", detail: "\(data.name(c.playerId)) · \(c.manager.name)", value: "\(c.points) pts") }
                if let c = r.worstCaptain { LeagueRow(title: "Worst captain", detail: "\(data.name(c.playerId)) · \(c.manager.name)", value: "\(c.points) pts") }
                if let b = r.worstBench { LeagueRow(title: "Worst bench call", detail: b.manager.name, value: "\(b.points) pts") }
                if let h = r.biggestHit { LeagueRow(title: "Biggest hit", detail: "\(h.manager.name) · \(h.transfers) transfers", value: "−\(h.points)") }
                if let d = r.bestDifferential {
                    LeagueRow(title: "Best differential", detail: "\(data.name(d.playerId)) · owned by \(d.owners) (\(pct(d.ownedPct)))", value: "\(d.points) pts")
                }
                if !r.chips.isEmpty {
                    LeagueRow(title: "Chips played", detail: r.chips.map { "\($0.manager.name) \($0.label)" }.joined(separator: " · "))
                }
                if let y = r.you {
                    LeagueRow(title: "You", detail: y.rank.map { "Rank \($0) · \(y.gapToLeader) pts behind the leader" }, value: "\(y.points) pts")
                }
            }
        }
    }
}
