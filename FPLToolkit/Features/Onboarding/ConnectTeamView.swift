import SwiftUI

@MainActor
@Observable
final class ConnectModel {
    enum Phase: Equatable {
        case idle
        case checking
        case failed(ErrorCopy)
    }

    var input = ""
    private(set) var phase: Phase = .idle
    /// Set when the team loads; drives navigation to "Team found".
    var found: FoundTeam?

    private let repository: TeamRepository

    init(repository: TeamRepository) {
        self.repository = repository
    }

    func submit() async {
        guard let entryId = TeamIDInput.parse(input) else {
            phase = .failed(.invalidInput)
            return
        }
        phase = .checking
        do {
            // The team gives the squad and captain; today gives the attention count.
            // Today failing on its own doesn't block onboarding.
            async let team = repository.team(entryId: entryId).fetch()
            async let today = try? repository.today(entryId: entryId).fetch()
            found = FoundTeam(entryId: entryId, team: try await team.value, today: await today?.value)
            phase = .idle
        } catch let error as APIError {
            phase = .failed(ErrorCopy(error))
        } catch {
            phase = .idle
        }
    }

    func clearError() {
        if case .failed = phase { phase = .idle }
    }
}

struct FoundTeam {
    let entryId: Int
    let team: Team
    let today: Today?
}

/// S02 (connect) and S24 (import error).
struct ConnectTeamView: View {
    @State private var model: ConnectModel
    @FocusState private var fieldFocused: Bool
    @State private var showingHelp = false

    init(repository: TeamRepository) {
        _model = State(initialValue: ConnectModel(repository: repository))
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    Text("Connect your team")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text("No FPL password required.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                }

                Text("Enter your FPL Team ID, or paste your team's link.")
                    .font(.title3)
                    .foregroundStyle(ToolkitColor.primaryText)

                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    SectionLabel(text: "FPL Team ID")
                    HStack(spacing: ToolkitSpace.md) {
                        TextField("e.g. 1234567", text: $model.input)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                            .keyboardType(.asciiCapableNumberPad)
                            .textContentType(.none)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($fieldFocused)
                            .accessibilityLabel("FPL Team ID")
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first { model.input = first }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                        .tint(ToolkitColor.raised)
                    }
                    .padding(.horizontal, ToolkitSpace.page)
                    .frame(minHeight: 64)
                    .background(ToolkitColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.card))
                    .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card)
                        .strokeBorder(fieldBorder(model), lineWidth: 1.5))
                }
                .onChange(of: model.input) { model.clearError() }

                if case .failed(let copy) = model.phase {
                    ErrorBanner(copy: copy)
                }

                ToolkitCard {
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        Text("Where's my Team ID?")
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text("On the FPL website, open the Points page. The address looks like …/entry/1234567/event/5. The number after \u{201C}entry\u{201D} is your Team ID.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if showingHelp {
                            Text("In the FPL app: open Points, then share your team. The shared link contains the same number, and you can paste the whole link here.")
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Button("Using the FPL app?") { withAnimation { showingHelp = true } }
                                .font(.body.weight(.semibold))
                                .foregroundStyle(ToolkitColor.link)
                                .frame(minHeight: 44)
                        }
                    }
                }

                Text("We load the squad you had at the last deadline. Changes you've made since then won't show until the next deadline passes.")
                    .font(.callout)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.top, ToolkitSpace.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: ToolkitSpace.md) {
                Button {
                    fieldFocused = false
                    Task { await model.submit() }
                } label: {
                    if model.phase == .checking {
                        HStack(spacing: ToolkitSpace.sm) {
                            ProgressView().tint(ToolkitColor.onAccent)
                            Text("Finding your team…")
                        }
                    } else {
                        Text(isRetryable(model) ? "Try again" : "Find my team")
                    }
                }
                .buttonStyle(ToolkitPrimaryButtonStyle())
                .disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty || model.phase == .checking)

                Text("Your FPL login stays with FPL.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.top, ToolkitSpace.md)
            .padding(.bottom, ToolkitSpace.sm)
            .background(ToolkitColor.canvas)
        }
        .toolkitScreen()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { model.found != nil },
            set: { if !$0 { model.found = nil } }
        )) {
            if let found = model.found {
                TeamFoundView(found: found)
            }
        }
        .onAppear { fieldFocused = model.found == nil }
    }

    private func fieldBorder(_ model: ConnectModel) -> Color {
        if case .failed = model.phase { return ToolkitColor.error }
        return fieldFocused ? ToolkitColor.accent : ToolkitColor.border
    }

    private func isRetryable(_ model: ConnectModel) -> Bool {
        if case .failed(let copy) = model.phase { return copy.canRetry }
        return false
    }
}

struct ErrorBanner: View {
    let copy: ErrorCopy

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            Label(copy.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(copy.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ToolkitColor.error)
        .padding(ToolkitSpace.page)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.errorFill)
        .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let appModel = AppModel()
    NavigationStack {
        ConnectTeamView(repository: appModel.teamRepository)
    }
    .environment(appModel)
}
