import SwiftUI

/// Ownership up front on the player page (Dan, 29 Sep): everyone, the Elite top 100 and how far
/// they differ, then each of your mini-leagues one tap away (loaded when opened).
struct PlayerOwnershipSection: View {
    @Environment(AppModel.self) private var appModel
    let sheet: PlayerSheet
    let onEliteInfo: () -> Void

    @State private var showingLeagues = false
    @State private var leagues: PlayerLeagues?
    @State private var leaguesError: ErrorCopy?

    private var hasMiniLeagues: Bool {
        appModel.leagues.list?.leagues.contains { !$0.isElite } ?? false
    }

    var body: some View {
        let items = figures
        if !items.isEmpty || hasMiniLeagues {
            SectionHeader(title: "Ownership", actionTitle: sheet.elite == nil ? nil : "About",
                          action: sheet.elite == nil ? nil : onEliteInfo)
            if !items.isEmpty {
                FigureGrid(items: items)
            }
            if let note = eliteNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hasMiniLeagues {
                CardGroup {
                    Button {
                        withAnimation(.snappy) { showingLeagues.toggle() }
                    } label: {
                        HStack(spacing: ToolkitSpace.md) {
                            IconBadge(systemImage: "trophy")
                            Text("In your mini-leagues")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                            Spacer()
                            Image(systemName: showingLeagues ? "chevron.up" : "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(showingLeagues ? "Hides his ownership in your leagues" : "Shows his ownership in your leagues")
                    if showingLeagues {
                        leagueRows
                    }
                }
                .task(id: showingLeagues) {
                    guard showingLeagues, leagues == nil else { return }
                    await loadLeagues()
                }
            }
        }
    }

    // MARK: Everyone and the top 100

    private var figures: [FigureGrid.Item] {
        var items: [FigureGrid.Item] = []
        if let overall = sheet.market.selectedByPct {
            items.append(.init(label: "All managers", value: PlayerDetailContent.percent(overall)))
        }
        if let elite = sheet.elite {
            items.append(.init(label: "Top \(elite.cohortSize) owned", value: PlayerDetailContent.percent(elite.ownedPct)))
            items.append(.init(label: "Top \(elite.cohortSize) captained", value: PlayerDetailContent.percent(elite.captainPct)))
        }
        if let change = sheet.market.ownershipChange7d {
            items.append(.init(label: "Last 7 days", value: Format.signedPercent(change),
                               spoken: "\(Format.signedPercent(change)) ownership in the last 7 days"))
        }
        return items
    }

    /// Where the top 100 differ from everyone, and what they did this gameweek.
    private var eliteNote: String? {
        guard let elite = sheet.elite else { return nil }
        var parts: [String] = []
        if let overall = sheet.market.selectedByPct {
            let gap = elite.ownedPct - overall
            if abs(gap) >= 1 {
                let points = abs(gap).formatted(.number.precision(.fractionLength(0)))
                parts.append("The top \(elite.cohortSize) own him \(points) points \(gap > 0 ? "more" : "less") than all managers.")
            } else {
                parts.append("The top \(elite.cohortSize) own him about as much as all managers.")
            }
        }
        if elite.boughtPct >= 0.5 || elite.soldPct >= 0.5 {
            parts.append("In GW\(elite.gw), \(PlayerDetailContent.percent(elite.boughtPct)) bought him and \(PlayerDetailContent.percent(elite.soldPct)) sold him.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Your mini-leagues

    @ViewBuilder private var leagueRows: some View {
        if let leagues {
            if leagues.leagues.isEmpty {
                RowDivider()
                Text("Your leagues haven't been read from FPL yet.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            ForEach(leagues.leagues) { row in
                RowDivider()
                HStack(alignment: .top, spacing: ToolkitSpace.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.league.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ToolkitColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Starts \(PlayerDetailContent.percent(row.startedPct)) · captain \(PlayerDetailContent.percent(row.captainedPct)) · \(row.counted) managers")
                            .font(.caption)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: ToolkitSpace.sm)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(PlayerDetailContent.percent(row.ownedPct))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(ToolkitColor.primaryText)
                        Text("EO \(PlayerDetailContent.percent(row.eo))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.league.name): owned by \(PlayerDetailContent.percent(row.ownedPct)), started by \(PlayerDetailContent.percent(row.startedPct)), captained by \(PlayerDetailContent.percent(row.captainedPct)), effective ownership \(PlayerDetailContent.percent(row.eo)), \(row.counted) managers")
            }
        } else if let leaguesError {
            RowDivider()
            VStack(alignment: .leading, spacing: 4) {
                Text("\(leaguesError.title). \(leaguesError.message)")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                Button("Try again") { Task { await loadLeagues() } }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        } else {
            RowDivider()
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 52)
        }
    }

    private func loadLeagues() async {
        leaguesError = nil
        do {
            leagues = try await appModel.leagues.repository.playerOwnership(sheet.player.summary.id)
        } catch let error as APIError {
            leaguesError = ErrorCopy(error)
        } catch {}
    }
}
