import SwiftUI

/// Settings: the connected team, "Change team", and the unofficial disclosure.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let entryId: Int
    @State private var confirmingChange = false

    var body: some View {
        NavigationStack {
            List {
                Section("Your team") {
                    LabeledContent("Team ID", value: String(entryId))
                    Button("Change team", role: .destructive) {
                        confirmingChange = true
                    }
                }

                Section {
                    Text(appModel.disclosure)
                        .font(.callout)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    if let url = URL(string: appModel.bootstrap?.value.config.webBaseUrl ?? "https://www.fpltoolkit.co.uk") {
                        Link("Open fpltoolkit.co.uk", destination: url)
                    }
                } header: {
                    Text("About")
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Change team?", isPresented: $confirmingChange, titleVisibility: .visible) {
                Button("Change team", role: .destructive) {
                    dismiss()
                    appModel.disconnect()
                }
            } message: {
                Text("You'll go back to the start and can enter a different Team ID.")
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
