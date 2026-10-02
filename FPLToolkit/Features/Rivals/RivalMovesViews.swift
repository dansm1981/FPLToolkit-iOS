import SwiftUI

// MARK: - Their latest moves (Overview)

/// "Andy's GW5": captain and vice as picked, chip, transfers and hits (Dan, 2 Oct: theirs only).
struct RivalLatestMovesCard: View {
    let data: RivalComparison
    let moves: RivalComparison.Moves

    var body: some View {
        let name = data.rival.name
        SectionHeader(title: "\(name)'s GW\(moves.gameweek)")
        CardGroup {
            fact("Captain", moves.captainId.map { "\(player($0)) ×\(moves.captainMultiplier)" } ?? "–")
            RowDivider()
            fact("Vice-captain", moves.viceCaptainId.map(player) ?? "–")
            RowDivider()
            fact("Chip", moves.chipLabel ?? "None")
            RowDivider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Transfers")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                if moves.transfers.isEmpty {
                    Text("None")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                }
                ForEach(Array(moves.transfers.enumerated()), id: \.offset) { _, t in
                    RivalTransferLine(data: data, transfer: t)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            RowDivider()
            fact("Points spent on hits", moves.hits > 0 ? "−\(moves.hits)" : "None")
        }
    }

    private func player(_ id: Int) -> String { data.player(id)?.webName ?? "Player \(id)" }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// One transfer: who went out and who came in, at the prices then.
struct RivalTransferLine: View {
    let data: RivalComparison
    let transfer: RivalComparison.Transfer

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(side(transfer.out, transfer.outCost))
            } icon: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(ToolkitColor.error)
            }
            Label {
                Text(side(transfer.in, transfer.inCost))
            } icon: {
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(ToolkitColor.positive)
            }
        }
        .font(.subheadline)
        .foregroundStyle(ToolkitColor.primaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func name(_ id: Int) -> String { data.player(id)?.webName ?? "Player \(id)" }

    private func side(_ id: Int, _ cost: Double?) -> String {
        cost.map { "\(name(id)) · \(Format.price($0))" } ?? name(id)
    }

    private var spoken: String {
        let out = transfer.outCost.map { " at \(Format.price($0))" } ?? ""
        let into = transfer.inCost.map { " at \(Format.price($0))" } ?? ""
        return "\(name(transfer.out)) out\(out), \(name(transfer.in)) in\(into)"
    }
}

// MARK: - Transfers tab

/// Every transfer this season, by gameweek, newest first (Dan, 2 Oct).
struct RivalTransfersTab: View {
    let data: RivalComparison

    var body: some View {
        if let history = data.transfers {
            Text(RivalMovesText.summary(history))
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
            if history.weeks.isEmpty {
                RivalNote(text: "\(data.rival.name) hasn't made a transfer this season.")
            }
            ForEach(history.weeks) { week in
                SectionHeader(title: RivalMovesText.weekTitle(week))
                if let note = week.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CardGroup {
                    ForEach(Array(week.moves.enumerated()), id: \.offset) { index, t in
                        if index > 0 { RowDivider() }
                        RivalTransferLine(data: data, transfer: t)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                    }
                }
            }
            Text("Prices are FPL's at the time of each transfer.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
        } else {
            RivalNote(text: "Transfers aren't available yet. Pull to refresh.")
        }
    }
}

enum RivalMovesText {
    /// "11 transfers this season · 4 pts on hits".
    nonisolated static func summary(_ h: RivalComparison.TransferHistory) -> String {
        let transfers = "\(h.total) transfer\(h.total == 1 ? "" : "s") this season"
        return h.hits > 0 ? "\(transfers) · \(h.hits) pts on hits" : "\(transfers) · no hits"
    }

    /// "6.2 FPL xP", "12.4 FPL xP (×2)".
    nonisolated static func expected(_ p: RivalComparison.Outlook.Player) -> String {
        let value = (p.expected * Double(p.multiplier)).formatted(.number.precision(.fractionLength(1)))
        return "\(value) xP"
    }

    /// Where the outlook's figures come from, and which teams it compares.
    nonisolated static func outlookNote(_ o: RivalComparison.Outlook, name: String) -> String {
        var text = "xP is FPL's expected points for GW\(o.gameweek), doubled for a captain. Compares \(name)'s GW\(o.theirGameweek) team with your GW\(o.yourGameweek) team"
        text += o.theirGameweek < o.gameweek ? ": transfers before the deadline may change it." : "."
        return text
    }

    /// "GW4 · Free Hit", "GW5 · −4 hit", "GW6".
    nonisolated static func weekTitle(_ w: RivalComparison.TransferHistory.Week) -> String {
        var parts = ["GW\(w.gw)"]
        if let chip = w.chipLabel { parts.append(chip) }
        if w.hits > 0 { parts.append("−\(w.hits) hit") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Side by side (Teams)

/// Your team and theirs in two columns (Dan, 2 Oct), grouped goalkeepers, defenders, midfielders,
/// forwards, then the bench, with each group's points. Each row is coloured and marked by how it
/// matches (Dan: green/amber/red): ✓ the same player counted the same; ! the same player counted
/// differently, or one side has the other's player elsewhere (on the bench); ✕ different players.
/// Two columns at every text size: from xxLarge the photo and match state go and names wrap.
struct RivalSideBySide: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let data: RivalComparison
    let teams: RivalComparison.Teams

    /// A position group, then the bench.
    enum Band: CaseIterable {
        case gk, def, mid, fwd, bench
        var title: String {
            switch self {
            case .gk: "Goalkeepers"
            case .def: "Defenders"
            case .mid: "Midfielders"
            case .fwd: "Forwards"
            case .bench: "Bench"
            }
        }
    }

    enum Match {
        case same, partly, different
        var symbol: String {
            switch self {
            case .same: "checkmark"
            case .partly: "exclamationmark"
            case .different: "xmark"
            }
        }
        var colour: Color {
            switch self {
            case .same: ToolkitColor.positive
            case .partly: ToolkitColor.warning
            case .different: ToolkitColor.error
            }
        }
        var fill: Color {
            switch self {
            case .same: ToolkitColor.positiveFill
            case .partly: ToolkitColor.warningFill
            case .different: ToolkitColor.errorFill
            }
        }
        var spoken: String {
            switch self {
            case .same: "match"
            case .partly: "partly matches"
            case .different: "no match"
            }
        }
    }

    struct Cell: Hashable {
        let row: RivalComparison.PlayerRow
        let side: RivalComparison.Side
        /// Counted points (the captain's multiplier in); a bench player's own points.
        var value: Int { row.points * max(side.multiplier, 1) }
    }

    struct Line: Identifiable, Hashable {
        let you: Cell?
        let them: Cell?
        var shared: Bool { you != nil && you?.row.playerId == them?.row.playerId }
        var id: String { "\(you?.row.playerId ?? 0)-\(them?.row.playerId ?? 0)" }

        /// ✓ same player counted the same; ! same player counted differently, or a player the other
        /// side also has (elsewhere in their team); ✕ otherwise.
        var match: Match {
            if shared { return you?.side.multiplier == them?.side.multiplier ? .same : .partly }
            if you?.row.them != nil || them?.row.you != nil { return .partly }
            return .different
        }
    }

    var body: some View {
        let name = data.rival.name
        VStack(spacing: 0) {
            header(name)
            legend
            ForEach(Band.allCases, id: \.self) { group in
                let lines = Self.lines(teams.rows, group: group) { data.player($0)?.position }
                if !lines.isEmpty {
                    Divider().overlay(ToolkitColor.border)
                    groupHeader(group, lines: lines, name: name)
                    VStack(spacing: 4) {
                        ForEach(lines) { line in lineView(line, name: name) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    /// The group's players on each side, shared ones first on one row, then pairs biggest first.
    nonisolated static func lines(_ rows: [RivalComparison.PlayerRow], group: Band,
                                  position: (Int) -> Position?) -> [Line] {
        func inGroup(_ row: RivalComparison.PlayerRow, _ side: RivalComparison.Side?) -> Cell? {
            guard let side else { return nil }
            let counted = side.multiplier > 0
            switch group {
            case .bench: return counted ? nil : Cell(row: row, side: side)
            case .gk, .def, .mid, .fwd:
                guard counted else { return nil }
                let wanted: Position = group == .gk ? .gk : group == .def ? .def : group == .mid ? .mid : .fwd
                return position(row.playerId) == wanted ? Cell(row: row, side: side) : nil
            }
        }
        let byValue: (Cell, Cell) -> Bool = { $0.value != $1.value ? $0.value > $1.value : $0.side.position < $1.side.position }
        let yours = rows.compactMap { inGroup($0, $0.you) }
        let theirs = rows.compactMap { inGroup($0, $0.them) }
        let sharedIds = Set(yours.map(\.row.playerId)).intersection(theirs.map(\.row.playerId))
        let shared = yours.filter { sharedIds.contains($0.row.playerId) }.sorted(by: byValue).map { cell in
            Line(you: cell, them: theirs.first { $0.row.playerId == cell.row.playerId })
        }
        let restYours = yours.filter { !sharedIds.contains($0.row.playerId) }.sorted(by: byValue)
        let restTheirs = theirs.filter { !sharedIds.contains($0.row.playerId) }.sorted(by: byValue)
        let pairs = (0..<max(restYours.count, restTheirs.count)).map { i in
            Line(you: i < restYours.count ? restYours[i] : nil, them: i < restTheirs.count ? restTheirs[i] : nil)
        }
        return shared + pairs
    }

    private func header(_ name: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            column("You", data.rival.you)
            Color.clear.frame(width: 18, height: 1)
            column(name, data.rival.them)
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    private func column(_ title: String, _ points: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
            Text(points.map { "\($0) pts" } ?? "–")
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        FlowLayout(spacing: 10, lineSpacing: 4) {
            key(.same, "Same player")
            key(.partly, "Same player, counted differently")
            key(.different, "Different")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private func key(_ match: Match, _ text: String) -> some View {
        HStack(spacing: 4) {
            mark(match)
            Text(text)
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mark(_ match: Match) -> some View {
        Image(systemName: match.symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(match.colour)
            .frame(width: 18)
            .accessibilityHidden(true)
    }

    private func groupHeader(_ group: Band, lines: [Line], name: String) -> some View {
        let you = lines.compactMap(\.you).reduce(0) { $0 + $1.value }
        let them = lines.compactMap(\.them).reduce(0) { $0 + $1.value }
        let shared = lines.filter(\.shared).count
        let shareText = group == .bench ? "" : " · \(shared)/\(lines.count) shared"
        return Text("\(group.title)\(shareText) · you \(you) · \(name) \(them)")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func lineView(_ line: Line, name: String) -> some View {
        let match = line.match
        // Your cell in blue, theirs in red; a shared row all green (Dan's rivalry design).
        return HStack(alignment: .center, spacing: 0) {
            cellView(line.you)
                .background(line.shared || line.you == nil ? .clear : RivalColor.fill(RivalColor.you),
                            in: RoundedRectangle(cornerRadius: 8))
            mark(match)
            cellView(line.them)
                .background(line.shared || line.them == nil ? .clear : RivalColor.fill(RivalColor.them),
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(4)
        .background(line.shared ? match.fill.opacity(0.7) : ToolkitColor.raised.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(match.colour).frame(width: 3).padding(.vertical, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(line, name: name))
    }

    @ViewBuilder
    private func cellView(_ cell: Cell?) -> some View {
        if let cell, let summary = data.player(cell.row.playerId) {
            let large = typeSize.stacksRows
            Button { appModel.router.openPlayer(cell.row.playerId) } label: {
                HStack(spacing: 6) {
                    if !large {
                        PlayerPhoto(path: summary.photo, clubLogo: appModel.club(summary.clubId)?.logo, size: 26)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(summary.webName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                                .lineLimit(large ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            if let badge = badge(cell.side) {
                                Text(badge)
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(ToolkitColor.accent)
                                    .fixedSize()
                            }
                        }
                        if large {
                            Text("\(cell.value) pt\(cell.value == 1 ? "" : "s")")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(ToolkitColor.primaryText)
                        } else {
                            // Brighter than secondary text: it sits on the blue or red tint.
                            Text(RivalSideBySide.state(cell))
                                .font(.caption)
                                .foregroundStyle(ToolkitColor.primaryText.opacity(0.85))
                        }
                    }
                    if !large {
                        Spacer(minLength: 2)
                        Text("\(cell.value)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                            .fixedSize()
                    }
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text("–")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }

    private func badge(_ side: RivalComparison.Side) -> String? {
        if side.multiplier >= 3 { return "TC" }
        if side.multiplier == 2 { return "C" }
        if side.isViceCaptain { return "V" }
        return nil
    }

    /// "Playing", "Finished", "Yet to play", "Sub in".
    nonisolated static func state(_ cell: Cell) -> String {
        var text: String
        switch cell.row.state {
        case .blank: text = "No match"
        case .notStarted: text = "Yet to play"
        case .inPlay: text = "Playing"
        case .done: text = cell.row.minutes > 0 ? "Finished" : "Didn't play"
        case .unknown: text = ""
        }
        if cell.side.autoSub == .in { text += text.isEmpty ? "Sub in" : " · sub in" }
        if cell.side.autoSub == .out { text += text.isEmpty ? "Subbed out" : " · subbed out" }
        return text
    }

    private func spoken(_ line: Line, name: String) -> String {
        func describe(_ cell: Cell?) -> String {
            guard let cell, let summary = data.player(cell.row.playerId) else { return "nobody" }
            var text = summary.webName
            if let badge = badge(cell.side) { text += badge == "C" ? ", captain" : badge == "TC" ? ", triple captain" : ", vice-captain" }
            return "\(text), \(cell.value) point\(cell.value == 1 ? "" : "s")"
        }
        return "\(line.match.spoken). You: \(describe(line.you)). \(name): \(describe(line.them))"
    }
}

// MARK: - How you stack up (Overview)

/// Their starters you don't own (threats) and yours they don't (opportunities) for the next
/// gameweek, by FPL's expected points (Dan, 2 Oct).
struct RivalOutlookCard: View {
    @Environment(AppModel.self) private var appModel
    let data: RivalComparison
    let outlook: RivalComparison.Outlook

    var body: some View {
        let name = data.rival.name
        SectionHeader(title: "How you stack up for GW\(outlook.gameweek)")
        CardGroup {
            group("Threats", detail: "In \(name)'s team, not yours", systemImage: "exclamationmark.triangle",
                  colour: ToolkitColor.error, players: outlook.threats)
            RowDivider()
            group("Opportunities", detail: "In your team, not \(name)'s", systemImage: "arrow.up.right.circle",
                  colour: ToolkitColor.positive, players: outlook.opportunities)
        }
        Text(RivalMovesText.outlookNote(outlook, name: name))
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func group(_ title: String, detail: String, systemImage: String, colour: Color,
                       players: [RivalComparison.Outlook.Player]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(ToolkitColor.primaryText)
                    Text(detail).font(.caption).foregroundStyle(ToolkitColor.secondaryText)
                }
            } icon: {
                Image(systemName: systemImage).foregroundStyle(colour)
            }
            if players.isEmpty {
                Text("None").font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
            }
            ForEach(players) { p in
                Button { appModel.router.openPlayer(p.playerId) } label: {
                    NameFigureRow {
                        Text(data.player(p.playerId)?.webName ?? "Player \(p.playerId)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ToolkitColor.primaryText)
                    } details: {
                        if p.multiplier > 1 {
                            Text(p.multiplier == 3 ? "Triple captain" : "Captain")
                                .font(.caption)
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                    } figure: {
                        Text(RivalMovesText.expected(p))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the player")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }
}

// MARK: - GW Audit

/// Every gameweek they've played, newest first: points, captain and vice, chip, transfers and hits
/// (Dan, 2 Oct: "GW Audit").
struct RivalAuditTab: View {
    let data: RivalComparison

    var body: some View {
        if let history = data.transfers {
            Text(RivalMovesText.summary(history))
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
        }
        ForEach(data.audit?.weeks ?? []) { week in
            SectionHeader(title: "GW\(week.gw) · \(week.points) pts")
            if let note = week.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CardGroup {
                fact("Captain", week.captainId.map { "\(player($0)) ×\(week.captainMultiplier)" } ?? "Not kept for this gameweek")
                RowDivider()
                fact("Vice-captain", week.viceCaptainId.map(player) ?? "–")
                RowDivider()
                fact("Chip", week.chipLabel ?? "None")
                RowDivider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transfers")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    if week.transfers.isEmpty {
                        Text("None").font(.subheadline.weight(.semibold)).foregroundStyle(ToolkitColor.primaryText)
                    }
                    ForEach(Array(week.transfers.enumerated()), id: \.offset) { _, t in
                        RivalTransferLine(data: data, transfer: t)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                RowDivider()
                fact("Points spent on hits", week.hits > 0 ? "−\(week.hits)" : "None")
            }
        }
        Text("Points are after hits. Prices are FPL's at the time of each transfer.")
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func player(_ id: Int) -> String { data.player(id)?.webName ?? "Player \(id)" }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(ToolkitColor.primaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
