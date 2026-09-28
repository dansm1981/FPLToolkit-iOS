import SwiftUI

/// An Elite screen: the gameweek picker, any controls, then the page for that gameweek, or the
/// website's "not published yet" note.
struct EliteScreen<Body: Decodable & Sendable, Controls: View, Content: View>: View {
    let title: String
    let caption: String
    let table: ResearchTable<ElitePage<Body>>
    @Binding var gw: Int?
    let retry: () -> Void
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder let content: (ElitePage<Body>, Body) -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                EliteGameweekMenu(gw: $gw, gameweeks: loaded?.gameweeks ?? [], shown: loaded?.gw)
                controls()
                ResearchTableView(table: table, caption: caption, retry: retry) { page in
                    if let body = page.body {
                        content(page, body)
                    } else {
                        EliteUnpublished(gw: page.gw)
                    }
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var loaded: ElitePage<Body>? { (table.current?.loaded ?? table.previous)?.value }
}

extension EliteScreen where Controls == EmptyView {
    init(title: String, caption: String, table: ResearchTable<ElitePage<Body>>, gw: Binding<Int?>,
         retry: @escaping () -> Void, @ViewBuilder content: @escaping (ElitePage<Body>, Body) -> Content) {
        self.init(title: title, caption: caption, table: table, gw: gw, retry: retry,
                  controls: { EmptyView() }, content: content)
    }
}

/// The published gameweeks, newest first. Hidden until the first page arrives.
struct EliteGameweekMenu: View {
    @Binding var gw: Int?
    let gameweeks: [Int]
    let shown: Int?

    var body: some View {
        if let shown, !gameweeks.isEmpty {
            Menu {
                Picker("Gameweek", selection: Binding(get: { gw ?? shown }, set: { gw = $0 })) {
                    ForEach(gameweeks, id: \.self) { Text("Gameweek \($0)").tag($0) }
                }
            } label: {
                Label("Gameweek \(shown)", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Gameweek \(shown)")
            .accessibilityHint("Chooses another gameweek")
        }
    }
}

/// The website's empty state, before the cohort sync has run for a gameweek.
struct EliteUnpublished: View {
    let gw: Int

    var body: some View {
        Text(gw > 0
             ? "No Elite data has been published for GW\(gw) yet. It appears once the cohort sync runs after the deadline."
             : "No Elite data has been published yet. It appears once the cohort sync runs after the deadline.")
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ToolkitSpace.lg)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }
}

/// The website's stat tiles, two by two.
struct EliteStats: View {
    let stats: [EliteStat]

    var body: some View {
        MarketFigures(items: stats.map { ResearchFigure(label: $0.label, value: $0.value, hint: $0.sub) })
    }
}

enum EliteFormat {
    /// "£6.2m" from the player's live price.
    static func price(_ player: PlayerSummary?) -> String? {
        player.map { "£\($0.price.formatted(.number.precision(.fractionLength(1))))m" }
    }

    static func name(_ player: PlayerSummary?, _ id: Int) -> String { player?.webName ?? "Player \(id)" }
}

/// A player with a share of the cohort on the right, e.g. "36%" bought. Opens the player.
struct EliteShareRowView: View {
    let row: EliteShareRow
    let player: PlayerSummary?
    /// What the share is, for VoiceOver: "bought", "captained", "elite owned".
    let measure: String

    var body: some View {
        let changeWords = row.change.map { "ownership \($0.shown)" }
        let extra = [changeWords, row.detail].compactMap { $0 }.joined(separator: " · ")
        let spokenChange = row.change.map { "ownership \($0.spoken) since last gameweek" }
        let spoken = [EliteFormat.name(player, row.playerId), "\(row.display) \(measure)", spokenChange, row.detail,
                      EliteFormat.price(player)].compactMap { $0 }.joined(separator: ", ")
        MarketPlayerRow(
            playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            extra: extra.isEmpty ? nil : extra, trailing: row.display, spoken: spoken
        )
    }
}

/// A player with a change in points on the right, green up and red down.
struct EliteChangeRowView: View {
    let row: EliteChangeRow
    let player: PlayerSummary?
    /// "net", "since three gameweeks ago".
    let measure: String

    var body: some View {
        let spoken = [EliteFormat.name(player, row.playerId), "\(measure) \(row.change.spoken)",
                      EliteFormat.price(player)].compactMap { $0 }.joined(separator: ", ")
        MarketPlayerRow(
            playerId: row.playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            trailing: row.change.shown, trailingColor: MarketFormat.tint(row.change.value), spoken: spoken
        )
    }
}

/// A player and one figure on the right.
struct EliteFigureRowView: View {
    let playerId: Int
    let figure: String
    let player: PlayerSummary?
    var extra: String?
    /// The figure for VoiceOver: "36% vice-captain".
    let spokenFigure: String

    var body: some View {
        let spoken = [EliteFormat.name(player, playerId), spokenFigure, extra, EliteFormat.price(player)]
            .compactMap { $0 }.joined(separator: ", ")
        MarketPlayerRow(
            playerId: playerId, player: player, details: [EliteFormat.price(player)].compactMap { $0 },
            extra: extra, trailing: figure, spoken: spoken
        )
    }
}

/// A template squad player: the template's price, how often he starts, and his captaincy.
struct EliteTemplatePickRow: View {
    let pick: EliteTemplatePick
    let player: PlayerSummary?

    var body: some View {
        let start = "start \(pick.start)"
        let captain = pick.captain.map { "C \($0)" }
        let extra = [start, captain].compactMap { $0 }.joined(separator: " · ")
        let spokenCaptain = pick.captain.map { "captained by \($0)" }
        let spoken = [EliteFormat.name(player, pick.playerId), "\(pick.owned.display) of elite managers",
                      "starts for \(pick.start)", spokenCaptain, pick.price].compactMap { $0 }.joined(separator: ", ")
        MarketPlayerRow(
            playerId: pick.playerId, player: player, details: [pick.price], extra: extra,
            trailing: pick.owned.display, spoken: spoken
        )
    }
}

/// A footnote under an Elite section.
struct EliteNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
