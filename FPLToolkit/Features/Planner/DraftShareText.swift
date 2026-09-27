import Foundation

/// The plan as plain text for the share sheet (messages, notes, group chats): the gameweek's XI by
/// position, the bench, this week's transfers and chip, money, and the link to the website's copy.
/// Every figure is the server's; this only writes it out.
enum DraftShareText {
    static func make(_ draft: PlannerDraft) -> String {
        var lines = ["\(draft.name): GW\(draft.gw) plan"]
        lines.append("")
        for row in draft.rows() where !row.picks.isEmpty {
            let names = row.picks.map { name($0, in: draft) }.joined(separator: ", ")
            lines.append("\(row.position.rawValue): \(names)")
        }
        if !draft.bench.isEmpty {
            lines.append("Bench: " + draft.bench.map { name($0, in: draft) }.joined(separator: ", "))
        }
        let pairs = zip(draft.transfers.out, draft.transfers.in).map { out, inn in
            "\(player(out, in: draft)) → \(player(inn, in: draft))"
        }
        if !pairs.isEmpty {
            lines.append("")
            lines.append("Transfers: " + pairs.joined(separator: ", "))
        }
        if let chip = draft.chips.first(where: { $0.state == .active }) {
            lines.append("Chip: \(chip.label)")
        }
        lines.append("")
        var money = "Bank \(Format.price(draft.money.bank)) · Squad value \(Format.price(draft.money.squadValue))"
        if let free = draft.freeTransfersThisWeek {
            money += " · \(free) free transfer\(free == 1 ? "" : "s")"
        }
        if let row = draft.ledger.first(where: { $0.gw == draft.gw }), row.hits > 0 {
            money += " · \(row.hitPoints) points in hits"
        }
        lines.append(money)
        if !draft.check.ok {
            lines.append("Squad rules: " + draft.check.issues.joined(separator: "; "))
        }
        lines.append("")
        lines.append("Planned with FPLToolkit: \(draft.shareUrl)")
        return lines.joined(separator: "\n")
    }

    private static func name(_ pick: PlannerDraft.Pick, in draft: PlannerDraft) -> String {
        let base = player(pick.playerId, in: draft)
        if pick.isCaptain { return "\(base) (C)" }
        if pick.isVice { return "\(base) (VC)" }
        return base
    }

    private static func player(_ id: Int, in draft: PlannerDraft) -> String {
        draft.player(id)?.webName ?? "Player \(id)"
    }
}
