import SwiftUI

/// The website's /team-news (happy-backend-pal#95): what the press conferences said, club by club,
/// beside FPL's own flags, and what each claim did to the projections. Every word is the server's.
struct TeamNewsPage: Decodable, Sendable {
    struct Claim: Decodable, Sendable, Hashable, Identifiable {
        let id: String
        let claim: String
        let label: String
        /// bad, warn, good or default.
        let tone: String
        let quote: String?
        let source_name: String?
        let source_url: String?
        let observed_at: String
        let effect: String
    }
    struct Player: Decodable, Sendable, Hashable, Identifiable {
        let id: Int
        let web_name: String
        let fpl_status: String?
        let fpl_chance: Int?
        let fpl_news: String?
        let fpl_effect: String
        let claims: [Claim]
    }
    struct Club: Decodable, Sendable, Hashable, Identifiable {
        let id: Int
        let name: String
        let short_name: String
        let players: [Player]
    }
    struct Counts: Decodable, Sendable, Hashable {
        let claims: Int
        let players: Int
        let flagged: Int
        let clubs: Int
    }
    let gameweek: Int?
    let deadline: String?
    let read_at: String?
    let clubs: [Club]
    let counts: Counts
}

struct TeamNewsView: View {
    @State private var page: TeamNewsPage?
    @State private var failed: ErrorCopy?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.md) {
                if let page {
                    content(page)
                } else if let failed {
                    ErrorStateView(copy: failed) { Task { await load() } }
                } else {
                    SkeletonCards(caption: "Reading the team news…")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await load() }
        .task { if page == nil { await load() } }
        .toolkitScreen()
        .navigationTitle("Team news")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        do {
            page = try await APIClient.configured.get("team-news", as: TeamNewsPage.self).envelope.data
            failed = nil
        } catch let error as APIError {
            if page == nil { failed = ErrorCopy(error) }
        } catch {}
    }

    @ViewBuilder private func content(_ p: TeamNewsPage) -> some View {
        Text(TeamNewsText.summary(p))
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        if p.counts.claims == 0 {
            Text("Press conferences are read on Thursday and Friday afternoons before each deadline. FPL's own flags are below until then.")
                .font(.subheadline)
                .foregroundStyle(ToolkitColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToolkitColor.informationFill, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
        ForEach(p.clubs) { club in
            SectionHeader(title: club.name)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(club.players.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(ToolkitColor.border) }
                    playerRow(player)
                }
            }
            .padding(.horizontal, 15)
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
        }
    }

    private func playerRow(_ player: TeamNewsPage.Player) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(player.web_name)
                .font(.headline)
                .foregroundStyle(ToolkitColor.primaryText)
            ForEach(player.claims) { claim in
                VStack(alignment: .leading, spacing: 3) {
                    Tag(text: claim.label, foreground: TeamNewsText.colour(claim.tone), fill: TeamNewsText.fill(claim.tone))
                    if let quote = claim.quote {
                        Text("“\(quote)”")
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text([claim.source_name, TeamNewsText.when(claim.observed_at)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.secondaryText)
                    Text(claim.effect)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = claim.source_url.flatMap(URL.init(string:)) {
                        Button("Read the report") { openURL(url) }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ToolkitColor.link)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
            if let news = player.fpl_news, !news.isEmpty {
                Text("FPL: \(news)")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if player.claims.isEmpty {
                Text(player.fpl_effect)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum TeamNewsText {
    /// "9 Oct, 14:32" from the database's timestamp (with or without fractional seconds).
    static func when(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let trimmed = iso.replacingOccurrences(of: #"\.(\d{3})\d+"#, with: ".$1", options: .regularExpression)
        guard let date = f.date(from: trimmed) ?? plain.date(from: iso) else { return iso }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// "GW6 · 14 claims about 11 players · 23 flagged by FPL"
    static func summary(_ p: TeamNewsPage) -> String {
        var parts: [String] = []
        if let gw = p.gameweek { parts.append("GW\(gw)") }
        let c = p.counts
        parts.append("\(c.claims) \(c.claims == 1 ? "claim" : "claims") about \(c.players) \(c.players == 1 ? "player" : "players")")
        parts.append("\(c.flagged) flagged by FPL")
        return parts.joined(separator: " · ")
    }

    static func colour(_ tone: String) -> Color {
        switch tone {
        case "bad": ToolkitColor.error
        case "warn": ToolkitColor.warning
        case "good": ToolkitColor.positive
        default: ToolkitColor.secondaryText
        }
    }

    static func fill(_ tone: String) -> Color {
        switch tone {
        case "bad": ToolkitColor.errorFill
        case "warn": ToolkitColor.warningFill
        case "good": ToolkitColor.positiveFill
        default: ToolkitColor.raised
        }
    }
}
