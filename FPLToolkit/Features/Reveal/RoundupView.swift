import SwiftUI

// MARK: - The gameweek round-up (tasks/deadline-reveal.md; happy-backend-pal#96)

struct Roundup: Decodable, Sendable {
    struct Scored: Decodable, Sendable, Hashable {
        let playerId: Int
        let points: Int
    }
    struct Transfers: Decodable, Sendable, Hashable {
        let net: Int
        /// "Isak in for Wissa: +7, after a −4 hit: +3"
        let text: String
    }
    struct Rank: Decodable, Sendable, Hashable {
        let before: Int?
        let after: Int?
        /// "63.1k → 41.2k ↑21.9k"
        let text: String?
    }
    struct Week: Decodable, Sendable, Hashable {
        let points: Int
        let cost: Int
        let chip: Reveal.Chip?
        let captain: Scored?
        let bench: Int
        let transfers: Transfers?
        let best: Scored?
        let worst: Scored?
        let rank: Rank
    }
    struct Area: Decodable, Sendable, Hashable {
        let label: String
        let text: String
        let edge: Int
    }
    struct Rival: Decodable, Sendable, Hashable, Identifiable {
        let entryId: Int
        let name: String
        let featured: Bool
        let you: Int
        let them: Int
        let margin: Int
        /// "RIVALRY WON"
        let result: String
        let areas: [Area]
        let biggestSwing: String?
        let seasonText: String?
        var id: Int { entryId }
    }
    struct League: Decodable, Sendable, Hashable, Identifiable {
        let id: Int
        let name: String
        let text: String
    }
    let gameweek: Int
    let available: Bool
    let average: Int?
    let highest: Int?
    let headline: String?
    let you: Week?
    let rivals: [Rival]
    let leagues: [League]
    let players: [String: PlayerSummary]

    func name(_ id: Int?) -> String { id.flatMap { players[String($0)]?.webName } ?? "Player" }
}

struct RoundupView: View {
    @Environment(AppModel.self) private var appModel
    @State private var roundup: Roundup?
    @State private var failed: ErrorCopy?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let roundup {
                    content(roundup)
                } else if let failed {
                    ErrorStateView(copy: failed) { Task { await load() } }
                } else {
                    SkeletonCards(caption: "Adding up your gameweek…")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await load() }
        .task { if roundup == nil { await load() } }
        .toolkitScreen()
        .navigationTitle(roundup.map { "GW\($0.gameweek) round-up" } ?? "Round-up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        do {
            roundup = try await appModel.deviceSession.send("GET", "roundup", as: Roundup.self).envelope.data
            failed = nil
        } catch let error as APIError {
            if roundup == nil { failed = ErrorCopy(error) }
        } catch {}
    }

    @ViewBuilder private func content(_ r: Roundup) -> some View {
        if let you = r.you {
            SectionHeader(title: "Your gameweek")
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(you.points)").font(.largeTitle.weight(.bold).monospacedDigit())
                    Text("pts").font(.subheadline).foregroundStyle(ToolkitColor.secondaryText)
                }
                .foregroundStyle(ToolkitColor.primaryText)
                .accessibilityElement(children: .combine)
                if let avg = r.average { row("Average · highest", "\(avg) · \(r.highest.map(String.init) ?? "—")") }
                if let rank = you.rank.text { row("Overall rank", rank) }
                if let c = you.captain { row("Captain", "\(r.name(c.playerId)) · \(c.points) pts") }
                if let t = you.transfers { row("Transfers", t.text) }
                if let chip = you.chip { row("Chip", chip.label) }
                row("Bench", "\(you.bench) pts left on the bench")
                if let b = you.best { row("Best", "\(r.name(b.playerId)) · \(b.points) pts") }
                if let w = you.worst { row("Worst", "\(r.name(w.playerId)) · \(w.points) pts") }
                ForEach(r.leagues) { row($0.name, $0.text) }
                ShareImageLink(title: "Share your gameweek", name: "My GW\(r.gameweek)") {
                    RoundupShareCard(gameweek: r.gameweek, lines: RoundupText.youLines(you, r), title: "\(you.points) pts")
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        } else {
            Text("Your round-up is ready once FPL confirms the gameweek.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        if !r.rivals.isEmpty {
            SectionHeader(title: r.rivals.count == 1 ? "Your rivalry" : "Your rivalries")
            ForEach(r.rivals) { rival in
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOU \(rival.you) — \(rival.them) \(rival.name.uppercased())")
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rival.result)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(rival.margin > 0 ? ToolkitColor.positive : rival.margin < 0 ? ToolkitColor.warning : ToolkitColor.secondaryText)
                    ForEach(rival.areas, id: \.label) { row($0.label, $0.text) }
                    if let swing = rival.biggestSwing { row("Biggest swing", swing) }
                    if let season = rival.seasonText {
                        Text(season).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
                    }
                    ShareImageLink(title: "Share this rivalry", name: "GW\(r.gameweek) v \(rival.name)") {
                        RoundupShareCard(gameweek: r.gameweek, lines: RoundupText.rivalLines(rival),
                                         title: "YOU \(rival.you) — \(rival.them) \(rival.name.uppercased())",
                                         result: rival.result, won: rival.margin > 0)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(ToolkitColor.secondaryText)
            Text(value).font(.subheadline).foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

enum RoundupText {
    static func youLines(_ you: Roundup.Week, _ r: Roundup) -> [String] {
        var lines: [String] = []
        if let rank = you.rank.text { lines.append("Rank: \(rank)") }
        if let c = you.captain { lines.append("Captain: \(r.name(c.playerId)) \(c.points) pts") }
        if let t = you.transfers { lines.append("Transfers: \(t.net > 0 ? "+" : "")\(t.net)") }
        if let avg = r.average { lines.append("Average: \(avg)") }
        return lines
    }

    static func rivalLines(_ rival: Roundup.Rival) -> [String] {
        var lines: [String] = []
        if let swing = rival.biggestSwing { lines.append("Biggest swing: \(swing)") }
        lines.append(contentsOf: rival.areas.prefix(2).map { "\($0.label): \($0.text)" })
        if let season = rival.seasonText { lines.append(season) }
        return lines
    }
}

/// A fixed-size picture for sharing (SF Symbols, not emoji: the renderer draws emoji as boxes).
struct RoundupShareCard: View {
    let gameweek: Int
    let lines: [String]
    let title: String
    var result: String?
    var won = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FPLToolkit").font(.system(size: 18, weight: .bold))
                Spacer()
                Text("GW\(gameweek) ROUND-UP").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if let result {
                HStack(spacing: 8) {
                    Text(result)
                    if won { Image(systemName: "trophy.fill") }
                }
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(won ? Color(red: 0.48, green: 0.83, blue: 0.65) : Color(red: 0.98, green: 0.78, blue: 0.45))
            }
            ForEach(lines, id: \.self) { line in
                Text(line).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Text("Every kick. What it means for you.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(24)
        .frame(width: 360, height: 450, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 0.06, green: 0.12, blue: 0.10), Color(red: 0.04, green: 0.07, blue: 0.12)],
                                   startPoint: .top, endPoint: .bottom))
    }
}

/// Renders a share card and offers it through the share sheet.
struct ShareImageLink<Card: View>: View {
    let title: String
    let name: String
    @ViewBuilder let card: () -> Card
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, preview: SharePreview(name, image: image)) {
                    Label(title, systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ToolkitPrimaryButtonStyle())
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .task {
            let renderer = ImageRenderer(content: card())
            renderer.scale = 3
            image = renderer.uiImage.map { Image(uiImage: $0) }
        }
    }
}

/// The way in from Today and Matchday once the gameweek is confirmed.
struct RoundupLink: View {
    let gameweek: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: ToolkitSpace.md) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(ToolkitColor.onAccent)
                    .frame(width: 44, height: 44)
                    .background(ToolkitColor.accent, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GW\(gameweek) round-up").font(.headline).foregroundStyle(ToolkitColor.primaryText)
                    Text("How your week went, and each rivalry, ready to share")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(ToolkitColor.secondaryText).accessibilityHidden(true)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
