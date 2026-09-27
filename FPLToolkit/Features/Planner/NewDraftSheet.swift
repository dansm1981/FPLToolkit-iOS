import SwiftUI

/// The website's "New draft" dialog: import an FPL team (yours, or any other Team ID), start
/// from scratch, or copy one of your drafts. The server builds the draft; this collects the choice.
struct NewDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// The connected team's ID, filled in for import; nil while exploring without a team.
    let entryId: Int?
    let drafts: [PlannerDraftSummary]
    let start: (PlannerNewDraft, String) -> Void

    enum Choice: Hashable {
        case importTeam, blank, copy
    }

    @State private var choice: Choice
    @State private var teamId: String
    @State private var copyFrom: String?
    @State private var name = ""

    init(entryId: Int?, drafts: [PlannerDraftSummary], start: @escaping (PlannerNewDraft, String) -> Void) {
        self.entryId = entryId
        self.drafts = drafts
        self.start = start
        _choice = State(initialValue: entryId == nil ? .blank : .importTeam)
        _teamId = State(initialValue: entryId.map(String.init) ?? "")
        _copyFrom = State(initialValue: drafts.first?.id)
    }

    /// The Team ID typed, when it looks like one (the server checks it properly).
    private var typedTeamId: Int? {
        Int(teamId.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
    }

    private var trimmedName: String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : n
    }

    private var request: (PlannerNewDraft, String)? {
        switch choice {
        case .importTeam:
            guard let id = typedTeamId else { return nil }
            var r = PlannerNewDraft.import(id)
            r.name = trimmedName
            return (r, id == entryId ? "Importing your team from FPL…" : "Importing team \(id) from FPL…")
        case .blank:
            var r = PlannerNewDraft.blank
            r.name = trimmedName
            return (r, "Starting a blank draft…")
        case .copy:
            guard let copyFrom else { return nil }
            var r = PlannerNewDraft.copy(copyFrom)
            r.name = trimmedName
            return (r, "Copying the draft…")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ChoiceRow(title: "An FPL team", symbol: "square.and.arrow.down", selected: choice == .importTeam) {
                        choice = .importTeam
                    }
                    ChoiceRow(title: "Start from scratch", symbol: "square.dashed", selected: choice == .blank) {
                        choice = .blank
                    }
                    if !drafts.isEmpty {
                        ChoiceRow(title: "A copy of a draft", symbol: "doc.on.doc", selected: choice == .copy) {
                            choice = .copy
                        }
                    }
                } header: {
                    SectionLabel(text: "Start from")
                }
                .listRowBackground(ToolkitColor.surface)

                switch choice {
                case .importTeam:
                    Section {
                        TextField("FPL Team ID", text: $teamId)
                            .keyboardType(.numberPad)
                            .accessibilityLabel("FPL Team ID")
                    } header: {
                        SectionLabel(text: "Team ID")
                    } footer: {
                        Text(importFooter)
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .listRowBackground(ToolkitColor.surface)
                case .blank:
                    Section {
                        Text("An empty squad with a £100.0m budget. Tap \u{201C}+\u{201D} on the pitch to add players.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .listRowBackground(ToolkitColor.surface)
                case .copy:
                    Section {
                        ForEach(drafts) { draft in
                            ChoiceRow(title: draft.name, symbol: nil, selected: copyFrom == draft.id) {
                                copyFrom = draft.id
                            }
                        }
                    } header: {
                        SectionLabel(text: "Draft to copy")
                    } footer: {
                        Text("Every planned week comes too. The original stays as it is.")
                            .font(.footnote)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .listRowBackground(ToolkitColor.surface)
                }

                Section {
                    TextField(namePlaceholder, text: $name)
                        .accessibilityLabel("Draft name, optional")
                } header: {
                    SectionLabel(text: "Name (optional)")
                }
                .listRowBackground(ToolkitColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .navigationTitle("New draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard let request else { return }
                        dismiss()
                        start(request.0, request.1)
                    }
                    .disabled(request == nil)
                }
            }
        }
    }

    private var importFooter: String {
        let others = entryId == nil
            ? "Find a Team ID in the FPL site's address bar: /entry/1234567/."
            : "Your Team ID is filled in. Enter another to plan with a friend's or a rival's team."
        return "\(others) Purchase prices, bank, free transfers and chips played are read from that team's public FPL history."
    }

    private var namePlaceholder: String {
        switch choice {
        case .importTeam: "The FPL team's name"
        case .blank: "New draft"
        case .copy: "\(drafts.first { $0.id == copyFrom }?.name ?? "Draft") (copy)"
        }
    }
}

/// One choice in a list: the whole row is the button, ticked when chosen. Wraps at large text sizes.
private struct ChoiceRow: View {
    let title: String
    let symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ToolkitSpace.md) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(ToolkitColor.link)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
