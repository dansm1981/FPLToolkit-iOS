import SwiftUI

/// Settings › Data & sources (design pack p.28): the one home for routine freshness, so feeds
/// don't repeat "Up to date". Publication and fetch times are separate: a fresh fetch of the GW5
/// squad is still the GW5 squad. Only an exception gets a label.
struct DataSourcesView: View {
    @Environment(AppModel.self) private var appModel
    let entryId: Int?
    @State private var team: Resource<Team>?
    @State private var today: Resource<Today>?
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let loaded = team?.loaded, let snapshot = loaded.value.snapshot {
                    snapshotCard(snapshot, loaded: loaded)
                }
                if !sources.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                            if index > 0 { Divider().overlay(ToolkitColor.border) }
                            SourceRow(source: source)
                        }
                    }
                    .padding(.horizontal, 15)
                    .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
                } else if today == nil && team == nil {
                    Text("Add your FPL team to see where its data comes from.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                } else {
                    SkeletonCards(caption: "Checking sources…", count: 1)
                }
                Button {
                    Task { await load(force: true) }
                } label: {
                    Label(refreshing ? "Refreshing…" : "Refresh data", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ToolkitSecondaryButtonStyle())
                .disabled(refreshing || entryId == nil)
                Text("Refreshing doesn't show changes you've made to your FPL team since the last deadline.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Data & sources")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(force: false) }
    }

    /// Today's list covers every feed the app's screens lean on; the team's is the fallback.
    private var sources: [FreshnessSource] {
        today?.loaded?.meta.freshness ?? team?.loaded?.meta.freshness ?? []
    }

    private func snapshotCard(_ snapshot: Team.Snapshot, loaded: Loaded<Team>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your team snapshot")
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
            Text("GW\(snapshot.gw) deadline squad")
                .foregroundStyle(ToolkitColor.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Published: \(Format.deadline(snapshot.deadline))")
                Text("Last fetched: \(Format.deadline(loaded.savedAt ?? loaded.meta.generatedAt))")
            }
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
            Divider().overlay(ToolkitColor.border).padding(.vertical, 6)
            Text("New transfers appear after the next deadline. Use Planner to explore changes now.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    private func load(force: Bool) async {
        guard let entryId else { return }
        refreshing = force
        defer { refreshing = false }
        if team == nil { team = Resource(appModel.teamRepository.team(entryId: entryId)) }
        if today == nil { today = Resource(appModel.teamRepository.today(entryId: entryId)) }
        async let t: Void = team?.load(bypassCache: force) ?? ()
        async let d: Void = today?.load(bypassCache: force) ?? ()
        _ = await (t, d)
    }
}

/// One feed: what it is, where it comes from, and when it was received. Quiet when healthy.
private struct SourceRow: View {
    let source: FreshnessSource

    var body: some View {
        HStack(alignment: .top, spacing: ToolkitSpace.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.source.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ToolkitSpace.sm)
            switch source.state {
            case .fresh:
                EmptyView()
            case .stale:
                Tag(text: "Out of date", foreground: ToolkitColor.warning, fill: ToolkitColor.warningFill)
            case .unknown:
                Tag(text: "Unknown")
            }
        }
        .padding(.vertical, ToolkitSpace.md)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let label = source.label { parts.append(label) }
        parts.append(source.asOf.map { "received \(Format.ago($0))" } ?? "no timestamp yet")
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
