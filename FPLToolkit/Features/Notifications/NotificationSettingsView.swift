import SwiftUI

/// S15. Only the push types the server has switched on are listed; changes are saved straight away.
struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var prefs: DevicePrefs?
    @State private var error: ErrorCopy?
    @State private var saving = false
    @State private var showingPrimer = false

    var body: some View {
        List {
            Section {
                permissionRow
            }
            .listRowBackground(ToolkitColor.surface)

            Section {
                NavigationLink {
                    MatchdayWatchSettingsView()
                } label: {
                    Label("Live matchday", systemImage: "eye")
                }
            } footer: {
                Text("Who Matchday watches beside your team.")
            }
            .listRowBackground(ToolkitColor.surface)

            if let prefs {
                let f = appModel.pushFeatures
                Section {
                    if f?.priceAlerts == true {
                        toggle("Price projections", "When a watched player may rise or fall tonight (15:00\u{2060}–\u{2060}22:30 UK)", \.notifications.price, prefs)
                    }
                    if f?.availabilityAlerts == true {
                        toggle("Availability changes", "When FPL changes a watched player's status", \.notifications.availability, prefs)
                    }
                    if f?.deadlineReminders == true {
                        toggle("Deadline: 24 hours before", "With how many of your players are flagged", \.notifications.deadline24h, prefs)
                        toggle("Deadline: 3 hours before", "With how many of your players are flagged", \.notifications.deadline3h, prefs)
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("Only for players in your squad or watch list. At most 5 a day, plus deadline reminders.")
                }
                .listRowBackground(ToolkitColor.surface)

                if f?.matchdayAlerts == true {
                    let alerts = prefs.notifications.matchday ?? .standard
                    Section {
                        matchdayToggle("Matchday alerts", "What happens to your team, as it happens", \.enabled, prefs)
                        if alerts.enabled {
                            // Presets for most people, every switch underneath (Dan, 7 Oct).
                            Picker("How many", selection: Binding(
                                get: { alerts.preset },
                                set: { preset in
                                    guard let preset else { return }
                                    var next = prefs
                                    next.notifications.matchday = alerts.applying(preset)
                                    save(next)
                                }
                            )) {
                                ForEach(DevicePrefs.MatchdayAlerts.Preset.allCases) { Text($0.rawValue).tag(Optional($0)) }
                            }
                            .pickerStyle(.segmented)
                            .disabled(saving)
                            Text(presetDetail(alerts.preset))
                                .font(.footnote)
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup("Choose each alert") {
                                matchdayToggle("Goals", "Once FPL confirms them, with your points", \.goals, prefs)
                                matchdayToggle("Assists", "Once FPL confirms them, with your points", \.assists, prefs)
                                matchdayToggle("Red cards", "Once FPL confirms them", \.cards, prefs)
                                matchdayToggle("Final score", "When FPL confirms the gameweek", \.final, prefs)
                                matchdayToggle("Line-ups", "Who of your XI starts, about an hour before kick-off", \.lineups, prefs)
                                matchdayToggle("DEFCON", "When one of your players reaches it", \.defcon, prefs)
                                matchdayToggle("Bonus", "When FPL confirms your players' bonus", \.bonus, prefs)
                                matchdayToggle("Rival lead changes", "When your featured rival overtakes you, or you them", \.rivals, prefs)
                                matchdayToggle("Substitutions", "When one of your players comes off", \.subs, prefs)
                                matchdayToggle("Saves", "When your keeper earns a save point", \.saves, prefs)
                                matchdayToggle("Clean sheets lost", "When a goal costs your players a clean sheet", \.cleanSheets, prefs)
                            }
                            .tint(ToolkitColor.link)
                        }
                    } header: {
                        Text("Matchday")
                    } footer: {
                        Text("For your starting XI, and bench players once they're subbed on. Points include your captain. At most 10 a matchday.")
                    }
                    .listRowBackground(ToolkitColor.surface)
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { prefs.quietHours.start != prefs.quietHours.end },
                        set: { on in
                            var next = prefs
                            next.quietHours = on ? .init(start: "22:30", end: "07:30") : .init(start: "00:00", end: "00:00")
                            save(next)
                        }
                    )) {
                        Text("Quiet hours")
                    }
                    .tint(ToolkitColor.accent)
                    if prefs.quietHours.start != prefs.quietHours.end {
                        timePicker("From", \.quietHours.start, prefs)
                        timePicker("Until", \.quietHours.end, prefs)
                    }
                } header: {
                    Text("Quiet hours")
                } footer: {
                    Text("On this phone's clock. Availability changes and deadline reminders wait until quiet hours end; price and matchday alerts found during them are skipped.")
                }
                .listRowBackground(ToolkitColor.surface)
            } else if let error {
                Section {
                    Text("\(error.title). \(error.message)")
                        .foregroundStyle(ToolkitColor.secondaryText)
                    Button("Try again") { Task { await load() } }
                }
                .listRowBackground(ToolkitColor.surface)
            } else {
                Section { ProgressView() }.listRowBackground(ToolkitColor.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(ToolkitColor.canvas.ignoresSafeArea())
        .navigationTitle("Notifications")
        .task { await load() }
        .sheet(isPresented: $showingPrimer) { NotificationPrimerView() }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch appModel.push.permission {
        case .authorized:
            Label("Notifications are on for this iPhone", systemImage: "checkmark.circle.fill")
                .foregroundStyle(ToolkitColor.positive)
        case .denied:
            VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                Label("Notifications are off in iPhone Settings", systemImage: "bell.slash")
                    .foregroundStyle(ToolkitColor.warning)
                Button("Open iPhone Settings") { appModel.push.openSystemSettings() }
            }
        case .notDetermined, .unknown:
            Button {
                showingPrimer = true
            } label: {
                Label("Turn on notifications", systemImage: "bell.badge")
            }
        }
    }

    private func toggle(_ title: String, _ detail: String, _ path: WritableKeyPath<DevicePrefs, Bool>, _ prefs: DevicePrefs) -> some View {
        Toggle(isOn: Binding(
            get: { prefs[keyPath: path] },
            set: { on in
                var next = prefs
                next[keyPath: path] = on
                save(next)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .tint(ToolkitColor.accent)
        .disabled(saving)
    }

    private func presetDetail(_ preset: DevicePrefs.MatchdayAlerts.Preset?) -> String {
        switch preset {
        case .essential: "Goals, assists, red cards and your final score."
        case .normal: "Adds line-ups, DEFCON, bonus and rival lead changes."
        case .everything: "Adds substitutions, saves and clean sheets lost."
        case nil: "Your own choice of alerts."
        }
    }

    private func matchdayToggle(_ title: String, _ detail: String, _ path: WritableKeyPath<DevicePrefs.MatchdayAlerts, Bool>, _ prefs: DevicePrefs) -> some View {
        Toggle(isOn: Binding(
            get: { (prefs.notifications.matchday ?? .standard)[keyPath: path] },
            set: { on in
                var next = prefs
                var alerts = next.notifications.matchday ?? .standard
                alerts[keyPath: path] = on
                next.notifications.matchday = alerts
                save(next)
                if on, path == \.enabled, appModel.push.permission != .authorized { showingPrimer = true }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
            }
        }
        .tint(ToolkitColor.accent)
        .disabled(saving)
    }

    private func timePicker(_ title: String, _ path: WritableKeyPath<DevicePrefs, String>, _ prefs: DevicePrefs) -> some View {
        DatePicker(title, selection: Binding(
            get: { Self.date(from: prefs[keyPath: path]) },
            set: { date in
                var next = prefs
                next[keyPath: path] = Self.hhmm(from: date)
                save(next)
            }
        ), displayedComponents: .hourAndMinute)
        .disabled(saving)
    }

    private func load() async {
        error = nil
        do {
            prefs = try await appModel.deviceSession.device().prefs
            if prefs == nil { error = ErrorCopy(title: "Settings aren't available", message: "Try again in a moment.", canRetry: true) }
        } catch let e as APIError {
            error = ErrorCopy(e)
        } catch {}
    }

    /// Optimistic: shows the change, saves it, and puts it back if saving fails.
    private func save(_ next: DevicePrefs) {
        let previous = prefs
        prefs = next
        saving = true
        Task {
            defer { saving = false }
            do {
                let saved = try await appModel.deviceSession.updatePrefs(.init(notifications: next.notifications, quietHours: next.quietHours))
                prefs = saved.prefs ?? next
            } catch let e as APIError {
                prefs = previous
                error = ErrorCopy(e)
            } catch {}
        }
    }

    private static func date(from hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts.first ?? 0, minute: parts.dropFirst().first ?? 0, second: 0, of: .now) ?? .now
    }

    private static func hhmm(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
