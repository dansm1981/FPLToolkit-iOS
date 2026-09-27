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
                .task { await appModel.refreshBootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await appModel.refreshBootstrap() }
                    }
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
    let entryId: Int

    var body: some View {
        TabView {
            NavigationStack {
                TodayView(entryId: entryId)
            }
            .tabItem { Label("Today", systemImage: "rectangle.stack") }

            NavigationStack {
                TeamView(entryId: entryId)
            }
            .tabItem { Label("Team", systemImage: "tshirt") }
        }
        // A new team gets fresh screens and models.
        .id(entryId)
    }
}
