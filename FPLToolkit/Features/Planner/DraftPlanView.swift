import SwiftUI

/// The website's Transfer & chip timeline: every gameweek with planned transfers or a chip, then
/// the free-transfer ledger week by week. All from the shared planner rules on the server.
struct DraftPlanView: View {
    let model: DraftModel
    /// Chip names by key, for the ledger's chip column.
    let chipLabels: [String: String]

    @State private var plan: PlannerPlan?
    @State private var loadError: ErrorCopy?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                if let loadError {
                    ErrorStateView(copy: loadError) { Task { await load() } }
                } else if let plan {
                    content(plan)
                } else {
                    SkeletonCards(caption: "Loading the plan…")
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Transfer timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ plan: PlannerPlan) -> some View {
        if plan.events.isEmpty {
            ToolkitCard {
                Text("No changes yet. Play a chip or make a transfer to see it here.")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            SectionLabel(text: "Timeline")
            ForEach(plan.events) { event in
                ToolkitCard {
                    VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                        Text("GW\(event.gw)")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        ForEach(event.chips, id: \.key) { chip in
                            Label(chip.label, systemImage: "bolt.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ToolkitColor.accent)
                        }
                        ForEach(Array(pairs(event).enumerated()), id: \.offset) { _, pair in
                            transferRow(out: pair.out.map(plan.name), in: pair.in.map(plan.name))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }

        if !plan.ledger.isEmpty {
            SectionLabel(text: "Free transfers")
                .padding(.top, ToolkitSpace.sm)
            ToolkitCard {
                VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                    ForEach(plan.ledger) { row in
                        ledgerRow(row)
                        if row.id != plan.ledger.last?.id { Divider() }
                    }
                }
            }
            if plan.totals.hits > 0 {
                Text("Total: \(plan.totals.hits) hit\(plan.totals.hits == 1 ? "" : "s"), \(plan.totals.hitPoints) points.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.warning)
            }
            Text("Up to five free transfers can be banked. Wildcard and Free Hit weeks make every transfer free and still bank one for the next week.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Outs and ins side by side, in the order the server lists them.
    private func pairs(_ event: PlannerPlan.Event) -> [(out: Int?, in: Int?)] {
        (0..<max(event.out.count, event.in.count)).map { i in
            (event.out.indices.contains(i) ? event.out[i] : nil, event.in.indices.contains(i) ? event.in[i] : nil)
        }
    }

    private func transferRow(out: String?, in inn: String?) -> some View {
        HStack(spacing: ToolkitSpace.sm) {
            Text(out ?? "–").foregroundStyle(ToolkitColor.secondaryText)
            Image(systemName: "arrow.right")
                .foregroundStyle(ToolkitColor.secondaryText)
                .accessibilityHidden(true)
            Text(inn ?? "–").fontWeight(.semibold).foregroundStyle(ToolkitColor.primaryText)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([out.map { "\($0) out" }, inn.map { "\($0) in" }].compactMap { $0 }.joined(separator: ", "))
    }

    private func ledgerRow(_ row: PlannerDraft.LedgerRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("GW\(row.gw)").font(.subheadline.weight(.semibold))
                if let chip = row.chip {
                    Text(chipLabels[chip] ?? chip)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.accent)
                }
                Spacer(minLength: 0)
                if row.hits > 0 {
                    Text("\(row.hitPoints) pts")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(ToolkitColor.warning)
                }
            }
            .foregroundStyle(ToolkitColor.primaryText)
            Text("\(row.freeTransfers) free · \(row.transfers) used · \(row.bankedAfter) for next week")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        loadError = nil
        do {
            plan = try await model.plan()
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }
}
