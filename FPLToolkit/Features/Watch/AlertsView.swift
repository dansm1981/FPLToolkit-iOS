import SwiftUI

/// What the manager wants to be told about (Dan, 29 Sep), with his defaults. Kept on this phone
/// for now: nothing is sent until notifications are live, when the server takes them over.
struct AlertChoices: Codable, Equatable {
    var priceDrop = true
    var priceRise = false
    var priceConfirmed = true
    var availability = true
    var marketData = true
    var teamNews = true
    var liveMatchday = true
    var captainNotStarting = false
    var lineupClash = false
    var wrapUp = false
    /// Nil until chosen: on when the manager follows a mini-league.
    var leagueSummary: Bool?
    var eliteSummary = false

    static let storageKey = "alerts.choices"
}

/// Watch → Alerts: every alert in one place, grouped by when it would come.
struct AlertsView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(AlertChoices.storageKey) private var stored = Data()

    private var choices: AlertChoices {
        (try? JSONDecoder().decode(AlertChoices.self, from: stored)) ?? AlertChoices()
    }

    private var followsLeague: Bool {
        appModel.leagues.list?.leagues.contains { !$0.isElite } ?? false
    }

    var body: some View {
        List {
            Section {
                InlineNotice(text: "Alerts aren't sent yet. Choose what you want now and they'll start when notifications go live.",
                             systemImage: "bell.badge")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                toggle("Price drop", "A player you own is about to fall in price", \.priceDrop)
                toggle("Price rise", "A player you own is about to rise in price", \.priceRise)
                toggle("Price change confirmed", "The actual overnight change, not the forecast", \.priceConfirmed)
                toggle("Injuries and availability", "FPL changes a player's status or news", \.availability)
            } header: {
                Text("Your players")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                toggle("Market data ready", "About 48 hours before the deadline: odds and price watch", \.marketData)
                toggle("Team news", "3 hours before the deadline: your squad's latest news", \.teamNews)
            } header: {
                Text("Before the deadline")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                toggle("Live match day", "When your players are playing, straight to Matchday", \.liveMatchday)
                toggle("Captain not starting", "When line-ups come out, about 30 minutes before kick-off", \.captainNotStarting)
                toggle("Line-up clash", "One of your starters is out while a bench player starts", \.lineupClash)
                toggle("Gameweek wrap-up", "Once bonus is added: your final points and rank change", \.wrapUp)
            } header: {
                Text("Match days")
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                Toggle(isOn: Binding(
                    get: { choices.leagueSummary ?? followsLeague },
                    set: { on in update { $0.leagueSummary = on } }
                )) {
                    label("Mini-league round-up", "After each deadline: changes, captains, transfers and differentials in your leagues")
                }
                .tint(ToolkitColor.accent)
                toggle("Elite round-up", "The same for the top 100 managers", \.eliteSummary)
            } header: {
                Text("Leagues")
            } footer: {
                Text(appModel.anyPushFeature
                     ? "Quiet hours and your phone's permission are in Settings › Notifications."
                     : "Quiet hours and your phone's permission will be in Settings › Notifications once alerts go live.")
            }
            .listRowBackground(ToolkitColor.surface)
        }
        .listStyle(.insetGrouped)
        .toolkitScreen()
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ title: String, _ detail: String, _ key: WritableKeyPath<AlertChoices, Bool>) -> some View {
        Toggle(isOn: Binding(get: { choices[keyPath: key] }, set: { on in update { $0[keyPath: key] = on } })) {
            label(title, detail)
        }
        .tint(ToolkitColor.accent)
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(ToolkitColor.primaryText)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func update(_ change: (inout AlertChoices) -> Void) {
        var next = choices
        change(&next)
        if let data = try? JSONEncoder().encode(next) { stored = data }
    }
}
