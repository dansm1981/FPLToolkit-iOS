import SwiftUI

/// S11. An audit trail, not a news feed: every alert considered for this phone, and what happened to it.
struct AlertHistoryView: View {
    @Environment(AppModel.self) private var appModel
    let resource: Resource<AlertHistory>

    var body: some View {
        List {
            switch resource.phase {
            case .loading:
                ProgressView().listRowBackground(ToolkitColor.surface)
            case .failed(let copy):
                Text("\(copy.title). \(copy.message)")
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .listRowBackground(ToolkitColor.surface)
            case .loaded(let loaded):
                if loaded.value.alerts.isEmpty {
                    Text("No alerts yet. When something changes for the players you watch, it'll be listed here.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .listRowBackground(ToolkitColor.surface)
                } else {
                    Section {
                        ForEach(loaded.value.alerts) { alert in
                            AlertRow(alert: alert)
                        }
                    } footer: {
                        Text("Projections and confirmed changes are kept separate. Alerts from the last 30 days.")
                    }
                    .listRowBackground(ToolkitColor.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ToolkitColor.canvas.ignoresSafeArea())
        .navigationTitle("Alert history")
        .refreshable { await resource.load(bypassCache: true) }
        .task { if case .loading = resource.phase { await resource.load() } }
    }
}

struct AlertRow: View {
    @Environment(AppModel.self) private var appModel
    let alert: AlertItem

    var body: some View {
        Button {
            if let url = URL(string: alert.deepLink), let link = DeepLink(url: url) { appModel.router.open(link) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Format.deadline(alert.sentAt ?? alert.detectedAt).uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                    Spacer()
                    Circle().fill(dotColor).frame(width: 8, height: 8).accessibilityHidden(true)
                }
                Text(alert.title)
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                Text(alert.body)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                Text(AlertRow.statusText(alert))
                    .font(.footnote)
                    .foregroundStyle(alert.status == .sent ? ToolkitColor.secondaryText : ToolkitColor.warning)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        switch alert.category {
        case .price: ToolkitColor.information
        case .availability: ToolkitColor.warning
        case .deadline: ToolkitColor.positive
        case .other: ToolkitColor.secondaryText
        }
    }

    nonisolated static func statusText(_ alert: AlertItem) -> String {
        switch alert.status {
        case .sent: return "Sent"
        case .queued: return "Sending…"
        case .deferred: return "Held until quiet hours end"
        case .superseded: return "Not sent: the status changed back before it went out"
        case .failed: return "Couldn't be delivered to this iPhone"
        case .suppressed, .unknown:
            switch alert.reason {
            case "quiet_hours": return "Not sent: found during quiet hours"
            case "outside_window": return "Not sent: found outside the 15:00–22:30 price window"
            case "daily_cap": return "Not sent: daily alert limit reached"
            case "notifications_off": return "Not sent: notifications are off on this iPhone"
            default: return "Not sent"
            }
        }
    }
}
