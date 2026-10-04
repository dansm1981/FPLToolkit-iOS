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
        // The buttons and the disclosure sit at the foot of the screen while everything fits, and
        // scroll with the page once the text is large: pinned below the scroll view, they were
        // squeezed and their text clipped at the larger sizes (audit, 4 Oct).
        GeometryReader { geo in
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

                    Spacer(minLength: 0)

                    actions
                }
                .padding(.horizontal, ToolkitSpace.page)
                .padding(.bottom, ToolkitSpace.sm)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
        }
        .toolkitScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var actions: some View {
        VStack(spacing: ToolkitSpace.md) {
            NavigationLink {
                ConnectTeamView(repository: appModel.teamRepository)
            } label: {
                Text("Add my FPL team")
            }
            .buttonStyle(ToolkitPrimaryButtonStyle())

            Button("Explore without a team") { appModel.startExploring() }
                .buttonStyle(ToolkitSecondaryButtonStyle())

            Text(appModel.disclosure)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .multilineTextAlignment(.center)
                // Grows onto more lines with the text size, never cut short.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
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
