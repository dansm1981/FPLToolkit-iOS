import SwiftUI

@main
struct FPLToolkitApp: App {
    @State private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .tint(ToolkitColor.link)
                .task {
                    await appModel.refreshBootstrap()
                    await appModel.syncDevice()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await appModel.refreshBootstrap()
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
            if let entryId = appModel.entryId {
                MainView(entryId: entryId)
            } else {
                OnboardingFlow()
            }
        }
        .animation(.default, value: appModel.entryId)
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int

    var body: some View {
        @Bindable var router = appModel.router
        TabView(selection: $router.selectedTab) {
            NavigationStack {
                TodayView(entryId: entryId)
            }
            .tabItem { Label("Today", systemImage: "rectangle.stack") }
            .tag(AppTab.today)

            NavigationStack {
                TeamView(entryId: entryId)
            }
            .tabItem { Label("Team", systemImage: "tshirt") }
            .tag(AppTab.team)

            NavigationStack {
                WatchView(entryId: entryId)
            }
            .tabItem { Label("Watch", systemImage: "bell") }
            .tag(AppTab.watch)
        }
        .sheet(item: $router.presentedPlayer) { ref in
            PlayerSheetView(playerId: ref.id)
        }
        // A new team gets fresh screens and models.
        .id(entryId)
    }
}
