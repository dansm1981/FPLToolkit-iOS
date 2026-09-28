import SwiftUI

@main
struct FPLToolkitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .tint(ToolkitColor.link)
                .task {
                    await appModel.refreshBootstrap()
                    await appModel.push.refresh()
                    await appModel.syncDevice()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await appModel.refreshBootstrap()
                            await appModel.push.refresh()
                            await appModel.syncDevice()
                        }
                    }
                }
                .onOpenURL { url in
                    if let link = DeepLink(url: url) { appModel.router.open(link) }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.updateRequired {
                UpdateRequiredView()
            } else if appModel.entryId != nil || appModel.exploring {
                MainView(entryId: appModel.entryId)
            } else {
                OnboardingFlow()
            }
        }
        .animation(.default, value: appModel.entryId)
        .animation(.default, value: appModel.exploring)
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    /// nil while exploring without a team.
    let entryId: Int?

    var body: some View {
        @Bindable var router = appModel.router
        TabView(selection: $router.selectedTab) {
            NavigationStack {
                if let entryId {
                    TodayView(entryId: entryId)
                } else {
                    ExploreTodayView()
                }
            }
            .tabItem { Label("Today", systemImage: "rectangle.stack") }
            .tag(AppTab.today)

            NavigationStack {
                if let entryId {
                    TeamView(entryId: entryId)
                } else {
                    NoTeamView(title: "My team", message: "Add your FPL team to see your published squad here, with each player's next fixture, price and availability.")
                }
            }
            .tabItem { Label("Team", systemImage: "tshirt") }
            .tag(AppTab.team)

            NavigationStack {
                PlannerView(entryId: entryId, repository: appModel.plannerRepository)
            }
            .tabItem { Label("Planner", systemImage: "calendar") }
            .tag(AppTab.planner)

            NavigationStack {
                ResearchView(entryId: entryId)
            }
            .tabItem { Label("Research", systemImage: "chart.bar.xaxis") }
            .tag(AppTab.research)

            NavigationStack {
                WatchView(entryId: entryId)
            }
            .tabItem { Label("Watch", systemImage: "bell") }
            .tag(AppTab.watch)
        }
        .sheet(item: $router.presentedPlayer) { ref in
            PlayerSheetView(playerId: ref.id, fromAlert: ref.fromAlert)
        }
        .fullScreenCover(isPresented: $router.showingMatchday) {
            NavigationStack {
                if let entryId {
                    MatchdayView(entryId: entryId)
                } else {
                    NoTeamView(title: "Matchday", message: "Add your FPL team to follow it live on match days.")
                }
            }
        }
        // A new team gets fresh screens and models.
        .id(entryId)
    }
}

/// Shown when this version is older than the server supports.
struct UpdateRequiredView: View {
    var body: some View {
        VStack(spacing: ToolkitSpace.xl) {
            Spacer()
            Image("BrandMark")
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("Please update FPLToolkit")
                .font(.title.weight(.bold))
                .foregroundStyle(ToolkitColor.primaryText)
                .multilineTextAlignment(.center)
            Text("This version can no longer read the latest data. Update from the App Store to carry on.")
                .foregroundStyle(ToolkitColor.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(ToolkitSpace.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ToolkitColor.canvas.ignoresSafeArea())
    }
}
