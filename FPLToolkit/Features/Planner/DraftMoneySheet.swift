import SwiftUI

/// The bank and free transfers (Dan, 29 Sep: "easily adjust the bank balance by tapping"). FPL
/// doesn't publish what players would sell for, so the planner's bank can be a little out: set it
/// to the bank FPL shows. The plan's starting budget moves by the same amount, so every week's
/// bank follows; the server re-works the bank and ledger.
struct DraftMoneySheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: PlannerDraft
    let model: DraftModel

    @State private var bank: String
    @State private var freeTransfers: Int

    init(draft: PlannerDraft, model: DraftModel) {
        self.draft = draft
        self.model = model
        _bank = State(initialValue: Self.text(draft.money.bank))
        _freeTransfers = State(initialValue: draft.freeTransfers.starting)
    }

    private static func text(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).grouping(.never))
    }

    /// £m in steps of 0.1 (a draft's bank can go below zero).
    private var parsedBank: Double? {
        let text = bank.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")
        guard let value = Double(text) else { return nil }
        return (value * 10).rounded() / 10
    }

    /// The starting budget that gives this bank; nil outside the £0–200m the server accepts.
    private var startBudget: Double? {
        guard let parsedBank else { return nil }
        let value = ((draft.money.startBudget + parsedBank - draft.money.bank) * 10).rounded() / 10
        return (0...200).contains(value) ? value : nil
    }

    private var patch: PlannerDraftPatch? {
        guard let startBudget else { return nil }
        var patch = PlannerDraftPatch()
        if abs(startBudget - draft.money.startBudget) > 0.001 { patch.startBudget = startBudget }
        if freeTransfers != draft.freeTransfers.starting { patch.startingFt = freeTransfers }
        return patch
    }

    private func step(_ delta: Double) {
        bank = Self.text((((parsedBank ?? draft.money.bank) + delta) * 10).rounded() / 10)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper {
                        HStack(spacing: ToolkitSpace.xs) {
                            Text("£").foregroundStyle(ToolkitColor.secondaryText)
                            TextField("0.0", text: $bank)
                                .keyboardType(.numbersAndPunctuation)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .accessibilityLabel("Bank in millions of pounds")
                            Text("m").foregroundStyle(ToolkitColor.secondaryText)
                        }
                    } onIncrement: {
                        step(0.1)
                    } onDecrement: {
                        step(-0.1)
                    }
                    .accessibilityValue(parsedBank.map(Format.price) ?? "")
                } header: {
                    SectionLabel(text: "In the bank in GW\(draft.gw)")
                } footer: {
                    Text(bankFooter)
                        .font(.footnote)
                        .foregroundStyle(startBudget == nil ? ToolkitColor.error : ToolkitColor.secondaryText)
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
            .navigationTitle("Bank")
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

    private var bankFooter: String {
        if parsedBank == nil { return "Enter an amount, e.g. 2.3." }
        if startBudget == nil { return "That's more than the planner allows for this squad." }
        return "Tap − or + for £0.1m steps, or type it. FPL doesn't publish what your players would sell for, so set this to the bank FPL shows; every later week moves with it."
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
