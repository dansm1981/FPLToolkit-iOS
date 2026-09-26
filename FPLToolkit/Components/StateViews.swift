import SwiftUI

struct LoadingStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: ToolkitSpace.lg) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A full-screen failure with nothing saved to show instead.
struct ErrorStateView: View {
    let copy: ErrorCopy
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: ToolkitSpace.lg) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(ToolkitColor.error)
                    .accessibilityHidden(true)
                Text(copy.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .multilineTextAlignment(.center)
                Text(copy.message)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .multilineTextAlignment(.center)
                Button("Try again", action: retry)
                    .buttonStyle(ToolkitPrimaryButtonStyle())
                    .padding(.top, ToolkitSpace.md)
            }
            .padding(ToolkitSpace.page)
            .padding(.top, ToolkitSpace.section)
        }
    }
}
