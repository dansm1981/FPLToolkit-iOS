import SwiftUI

struct OnboardingFlow: View {
    var body: some View {
        NavigationStack {
            WelcomeView()
        }
    }
}

/// S01. The brand promise, the first action and the unofficial disclosure.
struct WelcomeView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
                BrandLockup(markSize: 40)
                    .padding(.top, ToolkitSpace.xl)

                Pill(text: "Your FPL team companion")

                VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
                    Text("Your team.")
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text("Watching itself.")
                        .foregroundStyle(ToolkitColor.link)
                }
                .font(.largeTitle.weight(.bold))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Text("The changes that matter to your squad. The noise left behind.")
                    .font(.title3)
                    .foregroundStyle(ToolkitColor.secondaryText)

                ToolkitCard {
                    VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                        feature("exclamationmark.triangle", "Injury and availability news for your players")
                        feature("arrow.up.right", "Price-change projections, with how close each player is")
                        feature("clock", "Your next deadline, always in view")
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: ToolkitSpace.md) {
                NavigationLink {
                    ConnectTeamView()
                } label: {
                    Text("Add my FPL team")
                }
                .buttonStyle(ToolkitPrimaryButtonStyle())

                Text(appModel.disclosure)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.top, ToolkitSpace.md)
            .padding(.bottom, ToolkitSpace.sm)
            .background(ToolkitColor.canvas)
        }
        .toolkitScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.body)
                .foregroundStyle(ToolkitColor.primaryText)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(ToolkitColor.link)
                .frame(width: 24)
        }
    }
}

#Preview {
    OnboardingFlow()
        .environment(AppModel())
}
