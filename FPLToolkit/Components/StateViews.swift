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

/// Placeholder cards for when nothing is known yet (S27). No placeholder numbers or fake alerts.
struct SkeletonCards: View {
    var caption: String
    var count = 3

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
            ForEach(0..<count, id: \.self) { index in
                VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                    bar(width: 0.45, height: 18)
                    bar(width: 0.8, height: 12)
                    if index > 0 { bar(width: 0.6, height: 12) }
                }
                .padding(ToolkitSpace.page)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: height / 2)
                .fill(ToolkitColor.raised)
                .frame(width: proxy.size.width * width, height: height)
        }
        .frame(height: height)
    }
}

/// Shown above saved data: "Updating…" while a refresh runs, or why it failed and how old
/// the saved copy is (S23). Hidden when the screen shows a response fetched just now.
struct SavedDataBanner<T: Decodable & Sendable>: View {
    let resource: Resource<T>

    var body: some View {
        if let loaded = resource.loaded, loaded.isFromCache || resource.refreshError != nil {
            let shownAt = loaded.savedAt ?? loaded.meta.generatedAt
            if let error = resource.refreshError {
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    Label(error.title, systemImage: "wifi.exclamationmark")
                        .font(.headline)
                    Text("Showing saved data from \(Format.ago(shownAt)).")
                        .font(.subheadline)
                    // The frame goes on the label: outside it, the tappable area stays the text's height.
                    Button {
                        Task { await resource.load(bypassCache: true) }
                    } label: {
                        Text("Try again")
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(resource.isRefreshing)
                }
                .foregroundStyle(ToolkitColor.warning)
                .padding(ToolkitSpace.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToolkitColor.warningFill, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            } else if resource.isRefreshing {
                HStack(spacing: ToolkitSpace.sm) {
                    ProgressView()
                    Text("Updating… showing saved data from \(Format.ago(shownAt)).")
                }
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
