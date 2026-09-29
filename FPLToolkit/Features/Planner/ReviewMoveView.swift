import SwiftUI

/// "Review move" (S37/S39; design pack p.16): a transfer is a decision, not a tap. The server
/// previews the move (happy-backend-pal#43) and every figure here is its answer: the bank after,
/// this gameweek's transfers, free transfers and hit. Saving only changes the plan; the FPL team
/// is untouched.
struct ReviewMoveView: View {
    @Environment(AppModel.self) private var appModel
    let draft: PlannerDraft
    let outgoing: PlannerDraft.Pick
    let incoming: PlannerPicker.Candidate
    let model: DraftModel
    let onSaved: () -> Void

    @State private var preview: PlannerDraft?
    @State private var previewError: ErrorCopy?
    @State private var saving = false

    private var action: PlannerAction {
        .pick(incoming.id, replacing: outgoing.playerId, gw: draft.gw)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                Text("GW\(draft.gw) plan · \(draft.name)")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                movePlayers
                if let previewError {
                    InlineNotice(text: "\(previewError.title). \(previewError.message)")
                } else if let preview {
                    figures(preview)
                    if !preview.check.ok, !preview.check.issues.isEmpty {
                        InlineNotice(text: preview.check.issues.joined(separator: " "))
                    }
                    SectionHeader(title: "Next three fixtures")
                    fixtures(preview)
                } else {
                    SkeletonCards(caption: "Checking the move…", count: 1)
                }
                if let error = model.actionError, !saving {
                    ErrorBanner(copy: error)
                }
                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "Saving…" : "Save move to plan")
                }
                .buttonStyle(ToolkitPrimaryButtonStyle())
                .disabled(preview == nil || previewError != nil || saving)
                .padding(.top, ToolkitSpace.sm)
                Text("Planning only. Your official FPL team is unchanged.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Review move")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard preview == nil else { return }
            do {
                preview = try await model.preview(action)
            } catch let error as APIError {
                previewError = ErrorCopy(error)
            } catch {}
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        if await model.apply(action) { onSaved() }
    }

    // MARK: Out and in

    private var movePlayers: some View {
        let outPlayer = draft.player(outgoing.playerId)
        return VStack(alignment: .leading, spacing: 10) {
            eyebrow("Out", colour: ToolkitColor.secondaryText)
            if let outPlayer {
                playerLine(outPlayer, price: outgoing.sellingPrice ?? outPlayer.price,
                           priceNote: outgoing.sellingPrice != nil ? "selling price" : nil)
            }
            Divider().overlay(ToolkitColor.border)
            eyebrow("In", colour: ToolkitColor.accent)
            playerLine(incoming.player, price: incoming.player.price, priceNote: nil)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func eyebrow(_ text: String, colour: Color) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(colour)
            .accessibilityAddTraits(.isHeader)
    }

    private func playerLine(_ player: PlayerSummary, price: Double, priceNote: String?) -> some View {
        HStack(spacing: ToolkitSpace.md) {
            PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.webName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                ClubLabel(clubId: player.clubId,
                          text: [appModel.club(player.clubId)?.name, player.position.rawValue].compactMap { $0 }.joined(separator: " · "),
                          logoSize: 13)
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.price(price))
                    .font(.body.weight(.bold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
                if let priceNote {
                    Text(priceNote)
                        .font(.caption2)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Figures (the server's)

    private func figures(_ preview: PlannerDraft) -> some View {
        let bankBefore = draft.money.bank
        let bankAfter = preview.money.bank
        let spent = bankBefore - bankAfter
        let row = preview.ledger.first { $0.gw == draft.gw }
        let hitBefore = draft.ledger.first { $0.gw == draft.gw }?.hitPoints ?? 0
        var lines: [(String, String)] = [
            (spent >= 0 ? "Cost" : "Money back", Format.price(abs(spent))),
            ("Bank after move", Format.price(bankAfter)),
        ]
        if let row {
            lines.append(("Transfers this gameweek", "\(row.transfers) of \(row.freeTransfers) free"))
            lines.append(("Points hit", row.hitPoints > 0 ? "−\(row.hitPoints)" : "0"))
        }
        if row.map({ $0.hitPoints > hitBefore }) == true {
            lines.append(("This move adds", "−\((row?.hitPoints ?? 0) - hitBefore) points"))
        }
        return VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if index > 0 { Divider().overlay(ToolkitColor.border) }
                HStack {
                    Text(line.0).foregroundStyle(ToolkitColor.secondaryText)
                    Spacer()
                    Text(line.1)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(line.1.hasPrefix("−") ? ToolkitColor.error : ToolkitColor.primaryText)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
            if draft.estimatedPurchasePrices || preview.freeTransfers.estimated {
                Text("Some purchase prices or free transfers are estimates. Check them in the draft's budget.")
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .padding(.vertical, ToolkitSpace.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 15)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    // MARK: Fixtures

    private func fixtures(_ preview: PlannerDraft) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            if let outPlayer = draft.player(outgoing.playerId) {
                strip(outPlayer.webName, weeks: draft.strip(for: outgoing.playerId))
            }
            strip(incoming.player.webName, weeks: preview.strip(for: incoming.id).isEmpty
                  ? (incoming.fixtureStrip ?? []) : preview.strip(for: incoming.id))
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func strip(_ name: String, weeks: [PlannerDraft.StripWeek]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
            HStack(spacing: 6) {
                ForEach(weeks.prefix(3), id: \.gw) { week in
                    let real = week.fixtures.filter { !$0.blank }
                    let tone = DifficultyTone(band: week.band)
                    Text(real.isEmpty ? "GW\(week.gw) · No fixture" : real.map { chipText($0) }.joined(separator: " + "))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(tone.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tone.fill, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel(spoken(week))
                }
            }
            if weeks.isEmpty {
                Text("Fixtures unavailable")
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
        }
    }

    private func chipText(_ f: FixtureDifficulty) -> String {
        let name = appModel.club(f.opponentClubId)?.shortName ?? "TBC"
        let venue = f.home.map { $0 ? " H" : " A" } ?? ""
        return name + venue + (f.xfdr.map { " · \($0.display)" } ?? "")
    }

    private func spoken(_ week: PlannerDraft.StripWeek) -> String {
        let real = week.fixtures.filter { !$0.blank }
        if real.isEmpty { return "Gameweek \(week.gw), no fixture" }
        return "Gameweek \(week.gw), " + real.map { f in
            let name = appModel.club(f.opponentClubId)?.name ?? "opponent to be confirmed"
            let venue = f.home.map { $0 ? "at home" : "away" } ?? ""
            return "\(name) \(venue)" + (f.xfdr.map { ", \($0.modelLabel) \($0.display)" } ?? "")
        }.joined(separator: " and ")
    }
}
