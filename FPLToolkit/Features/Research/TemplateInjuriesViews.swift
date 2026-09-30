import SwiftUI

/// The website's template team (/template): the most-owned legal XI, and everyone owned by 20% or
/// more.
struct TemplateTeamView: View {
    @Environment(AppModel.self) private var appModel
    @State private var table = ResearchTable<TemplateTeam>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                ResearchTableView(table: table, caption: "Building the template…", retry: reload) { team in
                    content(team)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Template team")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func reload() { Task { await load() } }
    private func load() async { await table.load(appModel.playersResearchRepository.template) }

    private func content(_ team: TemplateTeam) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketFigures(items: [
                ResearchFigure(label: "Formation", value: team.formation, hint: "Most-owned legal XI"),
                ResearchFigure(label: "Squad cost", value: team.cost.display, hint: "Starting XI only"),
                ResearchFigure(label: "Season points", value: "\(team.points)", hint: "Combined XI total"),
                ResearchFigure(label: "Average ownership", value: team.averageOwnership.display),
            ])
            MarketList(title: "The template XI", rows: team.xi, initial: 11) { row($0, team) }
            MarketList(title: "Essential players (20%+ owned) · \(team.essential.count)", rows: team.essential,
                       empty: "No one is owned by 20% or more.") { row($0, team) }
            Text("The XI the FPL crowd actually owns, within a legal formation, ranked by ownership in each position. Anyone you don't own from the essential list is a rank risk each gameweek.")
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ p: TemplateTeam.Player, _ team: TemplateTeam) -> some View {
        let player = team.player(p.playerId)
        let price = "£\(p.price.formatted(.number.precision(.fractionLength(1))))m"
        let form = p.form.formatted(.number.precision(.fractionLength(1)))
        // Short facts as chips (Dan, 29 Sep: "too many words"): price stays with the club.
        return MarketPlayerRow(
            playerId: p.playerId, player: player, details: [price],
            chips: [RowChip(text: "\(p.points) pts"), RowChip(text: "Form \(form)")],
            trailing: MarketFormat.percent(p.own),
            spoken: [player?.webName ?? "Player", "\(MarketFormat.percent(p.own)) owned", price,
                     "\(p.points) points", "form \(form)"].joined(separator: ", ")
        )
    }
}

/// The website's injury list (/injuries): every flagged player in FPL's status groups, most owned
/// first, with the chance of playing and the latest news.
struct InjuriesView: View {
    @Environment(AppModel.self) private var appModel
    @State private var table = ResearchTable<InjuryList>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                ResearchTableView(table: table, caption: "Loading the injury list…", retry: reload) { list in
                    content(list)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Injuries")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func reload() { Task { await load() } }
    private func load() async { await table.load(appModel.playersResearchRepository.injuries) }

    private func content(_ list: InjuryList) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xl) {
            MarketFigures(items: [
                ResearchFigure(label: "Flagged players", value: "\(list.counts.flagged)"),
                ResearchFigure(label: "Owned by 5%+", value: "\(list.counts.owned)", hint: "Widely held concerns"),
                ResearchFigure(label: "Doubtful", value: "\(list.counts.doubtful)"),
                ResearchFigure(label: "Ruled out", value: "\(list.counts.ruledOut)"),
            ])
            if list.groups.isEmpty {
                Text("Every player is listed as available.")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            ForEach(list.groups) { group in
                VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
                    MarketList(title: "\(group.label) (\(group.rows.count))", rows: group.rows, initial: 15,
                               playerOf: { list.player($0.playerId) }) { row($0, group, list) }
                    Text(group.blurb)
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
    }

    private func row(_ r: InjuryList.Row, _ group: InjuryList.Group, _ list: InjuryList) -> some View {
        let player = list.player(r.playerId)
        let name: String = player?.webName ?? "Player"
        let chance: String = r.chance.map { "\($0)%" } ?? "—"
        let price: String = r.price.formatted(.number.precision(.fractionLength(1)))
        let details: [String] = ["£\(price)m"]
        let news: String = r.news ?? "No update"
        var spoken: [String] = [name, group.label]
        spoken.append(r.chance.map { "\($0)% chance of playing" } ?? "no chance given")
        spoken.append(contentsOf: details)
        spoken.append(news)
        spoken.append("\(MarketFormat.percent(r.own)) owned")
        return MarketPlayerRow(
            playerId: r.playerId, player: player, details: details, extra: news,
            chips: [RowChip(text: "\(MarketFormat.percent(r.own)) owned")],
            trailing: chance, trailingColor: chanceColor(r.chance, doubtful: group.key == "d"),
            spoken: spoken.joined(separator: ", ")
        )
    }

    /// The website's chance colours: 75% or more is good; below that, amber when doubtful, red otherwise.
    private func chanceColor(_ chance: Int?, doubtful: Bool) -> Color {
        guard let chance else { return ToolkitColor.secondaryText }
        if chance >= 75 { return ToolkitColor.positive }
        return doubtful ? ToolkitColor.warning : ToolkitColor.error
    }
}
