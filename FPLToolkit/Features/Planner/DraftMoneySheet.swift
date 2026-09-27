import SwiftUI

/// The website's bank control and free-transfer setting: the budget the plan starts from, and the
/// free transfers for the first week you can plan. The server re-works the bank and ledger.
struct DraftMoneySheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: PlannerDraft
    let model: DraftModel

    @State private var budget: String
    @State private var freeTransfers: Int

    init(draft: PlannerDraft, model: DraftModel) {
        self.draft = draft
        self.model = model
        _budget = State(initialValue: draft.money.startBudget.formatted(.number.precision(.fractionLength(1))))
        _freeTransfers = State(initialValue: draft.freeTransfers.starting)
    }

    /// £m, 0–200 in steps of 0.1 (the server checks too).
    private var parsedBudget: Double? {
        let text = budget.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), (0...200).contains(value) else { return nil }
        return (value * 10).rounded() / 10
    }

    private var patch: PlannerDraftPatch? {
        guard let parsedBudget else { return nil }
        var patch = PlannerDraftPatch()
        if abs(parsedBudget - draft.money.startBudget) > 0.001 { patch.startBudget = parsedBudget }
        if freeTransfers != draft.freeTransfers.starting { patch.startingFt = freeTransfers }
        return patch
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: ToolkitSpace.xs) {
                        Text("£").foregroundStyle(ToolkitColor.secondaryText)
                        TextField("100.0", text: $budget)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Starting budget in millions of pounds")
                        Text("m").foregroundStyle(ToolkitColor.secondaryText)
                    }
                } header: {
                    SectionLabel(text: "Starting budget")
                } footer: {
                    Text(budgetFooter)
                        .font(.footnote)
                        .foregroundStyle(parsedBudget == nil ? ToolkitColor.error : ToolkitColor.secondaryText)
                }
                .listRowBackground(ToolkitColor.surface)

                Section {
                    Stepper(value: $freeTransfers, in: 0...5) {
                        Text("\(freeTransfers) free transfer\(freeTransfers == 1 ? "" : "s")")
                            .foregroundStyle(ToolkitColor.primaryText)
                    }
                } header: {
                    SectionLabel(text: "Free transfers in GW\(draft.firstEditableGw)")
                } footer: {
                    Text(transfersFooter)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .listRowBackground(ToolkitColor.surface)

                if let error = model.actionError {
                    Section {
                        ErrorBanner(copy: error)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .scrollContentBackground(.hidden)
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isApplying {
                        ProgressView().accessibilityLabel("Saving")
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(patch == nil)
                    }
                }
            }
            .onAppear { model.clearActionError() }
        }
    }

    private var budgetFooter: String {
        if parsedBudget == nil { return "Enter an amount from £0.0m to £200.0m." }
        let why = draft.entryId == nil
            ? "A new FPL squad starts with £100.0m."
            : "For an imported team it's worked out from your FPL history. Change it if your bank looks wrong."
        return "What the squad had to spend when the plan starts. \(why) Your bank follows from it."
    }

    private var transfersFooter: String {
        let estimated = draft.freeTransfers.estimated ? " The current figure is estimated from your FPL history." : ""
        return "Later weeks follow FPL's rules: one more a week, up to five. Wildcard and Free Hit weeks don't use any.\(estimated)"
    }

    private func save() async {
        guard let patch else { return }
        if patch.startBudget == nil && patch.startingFt == nil {
            dismiss()
            return
        }
        if await model.update(patch) { dismiss() }
    }
}
