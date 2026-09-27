import SwiftUI

/// S04 before the system prompt, S28 if notifications are (or get) turned off.
/// "Not now" is always a supported path.
struct NotificationPrimerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var asking = false

    var body: some View {
        NavigationStack {
            Group {
                if appModel.push.permission == .denied {
                    notificationsOff
                } else {
                    primer
                }
            }
            .toolkitScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var primer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
                Text("Let useful alerts come to you.")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .accessibilityAddTraits(.isHeader)

                ToolkitCard {
                    HStack(alignment: .top, spacing: ToolkitSpace.md) {
                        Image("BrandMark")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FPLToolkit").font(.subheadline.weight(.semibold))
                            Text(example.title).font(.headline)
                            Text(example.body).font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
                        }
                        .foregroundStyle(ToolkitColor.primaryText)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Example notification: \(example.title). \(example.body)")

                VStack(spacing: 0) {
                    point("tshirt", "Your players only", "Your squad and the players you watch")
                    Divider().overlay(ToolkitColor.border)
                    point("bell", "You choose the alerts", "No general football news feed")
                    Divider().overlay(ToolkitColor.border)
                    point("moon", "Quiet overnight", "Nothing between 22:30 and 07:30 unless you change it")
                    Divider().overlay(ToolkitColor.border)
                    point("checkmark.shield", "Change this any time", "In Settings → Notifications")
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: ToolkitSpace.md) {
                Button {
                    Task {
                        asking = true
                        let granted = await appModel.push.requestPermission()
                        asking = false
                        if granted { dismiss() }
                    }
                } label: {
                    if asking { ProgressView().tint(ToolkitColor.onAccent) } else { Text("Enable notifications") }
                }
                .buttonStyle(ToolkitPrimaryButtonStyle())
                .disabled(asking)

                Button("Not now") {
                    appModel.push.primerDismissed = true
                    dismiss()
                }
                .buttonStyle(ToolkitSecondaryButtonStyle())
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.vertical, ToolkitSpace.sm)
            .background(ToolkitColor.canvas)
        }
    }

    /// An example built from what's actually switched on, never a real player.
    private var example: (title: String, body: String) {
        let f = appModel.pushFeatures
        if f?.availabilityAlerts == true { return ("A watched player's status changed", "Tap to see the latest FPL news and when it was checked.") }
        if f?.priceAlerts == true { return ("A watched player may rise tonight", "Tap to see how close he is to the threshold.") }
        return ("Deadline in 3 hours", "Check your team before the deadline.")
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: ToolkitSpace.md) {
            Image(systemName: symbol)
                .foregroundStyle(ToolkitColor.information)
                .frame(width: 44, height: 44)
                .background(ToolkitColor.informationFill, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(ToolkitColor.primaryText)
                Text(detail).font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, ToolkitSpace.md)
        .accessibilityElement(children: .combine)
    }

    /// S28: permission denial is not a dead end.
    private var notificationsOff: some View {
        ScrollView {
            VStack(spacing: ToolkitSpace.xl) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(ToolkitColor.information)
                    .frame(width: 96, height: 96)
                    .background(ToolkitColor.informationFill, in: Circle())
                    .accessibilityHidden(true)
                    .padding(.top, ToolkitSpace.xl)
                Text("Notifications are off")
                    .font(.title.weight(.bold))
                    .foregroundStyle(ToolkitColor.primaryText)
                Text("Today, Team and Watch still work, and every alert is still listed in your alert history.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ToolkitColor.secondaryText)
                ToolkitCard {
                    VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                        Text("Turn them on later").font(.headline).foregroundStyle(ToolkitColor.primaryText)
                        Text("Use iPhone Settings whenever you're ready.").foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: ToolkitSpace.md) {
                Button("Open iPhone Settings") { appModel.push.openSystemSettings() }
                    .buttonStyle(ToolkitPrimaryButtonStyle())
                Button("Continue without alerts") {
                    appModel.push.primerDismissed = true
                    dismiss()
                }
                .buttonStyle(ToolkitSecondaryButtonStyle())
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.vertical, ToolkitSpace.sm)
            .background(ToolkitColor.canvas)
        }
    }
}

/// The card on Today that offers alerts, once some are live and the user hasn't answered yet.
/// The prompt itself is presented by the screen, so it survives the card disappearing
/// the moment the user answers (it then shows S28 if they declined).
struct AlertsOfferCard: View {
    @Environment(AppModel.self) private var appModel
    let open: () -> Void

    var body: some View {
        if appModel.anyPushFeature && appModel.push.permission == .notDetermined && !appModel.push.primerDismissed {
            Button(action: open) {
                ToolkitCard {
                    HStack(spacing: ToolkitSpace.md) {
                        Image(systemName: "bell.badge")
                            .font(.title3)
                            .foregroundStyle(ToolkitColor.onAccent)
                            .frame(width: 44, height: 44)
                            .background(ToolkitColor.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get alerts for your players")
                                .font(.headline)
                                .foregroundStyle(ToolkitColor.primaryText)
                            Text("Only for your squad and watch list. You choose which.")
                                .font(.subheadline)
                                .foregroundStyle(ToolkitColor.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
