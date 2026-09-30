import SwiftUI

/// Squad Rotation (the website's Squad Evolution; renamed in batch 3): a squad over the next six
/// gameweeks, each player's FPL difficulty per week, and a suggested XI per week (the easiest legal
/// XI), ringed. The server builds it with the website's code; this lays it out. At accessibility
/// sizes it reads week by week. A draft's squad in the Planner; the published squad on My Team.
struct SquadRotationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let load: @MainActor () async throws -> PlannerEvolution

    @State private var evolution: PlannerEvolution?
    @State private var loadError: ErrorCopy?
    @State private var highlight = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                Text("Grouped by position, highest value first. Each week's suggested XI is the legal one with the easiest fixtures, using FPL's difficulty, as on the website.")
                    .font(.footnote)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Highlight suggested XI", isOn: $highlight)
                    .font(.subheadline)
                    .tint(ToolkitColor.accent)
                if let loadError {
                    ErrorStateView(copy: loadError) { Task { await reload() } }
                } else if let evolution, evolution.groups.allSatisfy({ $0.playerIds.isEmpty }) {
                    Text("No published squad yet. It appears after your first deadline.")
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let evolution {
                    if typeSize.isAccessibilitySize {
                        weekList(evolution)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            grid(evolution)
                            ScrollView(.horizontal) { grid(evolution) }
                        }
                    }
                    legend
                } else {
                    SkeletonCards(caption: "Building the grid…")
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .toolkitScreen()
        .navigationTitle("Squad rotation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    // MARK: Grid

    private func grid(_ evo: PlannerEvolution) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
            HStack(spacing: 4) {
                Text("Player")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(width: nameWidth, alignment: .leading)
                ForEach(evo.weeks) { week in
                    VStack(spacing: 0) {
                        Text("GW\(week.gw)").font(.caption.weight(.bold))
                        Text(week.formation).font(.caption2).foregroundStyle(ToolkitColor.secondaryText)
                    }
                    .foregroundStyle(ToolkitColor.primaryText)
                    .frame(width: cellWidth)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(evo.weeks.map { "GW\($0.gw) suggested \(formationSpoken($0.formation))" }.joined(separator: ", "))
            ForEach(evo.groups) { group in
                SectionLabel(text: group.position.plural)
                    .padding(.top, ToolkitSpace.sm)
                ForEach(group.playerIds, id: \.self) { id in
                    HStack(spacing: 4) {
                        nameCell(id, evo: evo)
                        ForEach(evo.cells(for: id), id: \.gw) { cell in
                            cellView(cell)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rowLabel(id, evo: evo))
                }
            }
        }
    }

    @ScaledMetric(relativeTo: .caption) private var nameWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .caption) private var cellWidth: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var cellHeight: CGFloat = 30

    private func nameCell(_ id: Int, evo: PlannerEvolution) -> some View {
        let player = evo.player(id)
        return VStack(alignment: .leading, spacing: 0) {
            Text(player?.webName ?? "Player \(id)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
            Text([club(player?.clubId), player.map { Format.price($0.price) }].compactMap { $0 }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: nameWidth, alignment: .leading)
    }

    @ViewBuilder
    private func cellView(_ cell: PlannerEvolution.Cell) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        if !cell.inSquad {
            shape.strokeBorder(ToolkitColor.border, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: cellWidth, height: cellHeight)
        } else {
            VStack(spacing: 0) {
                Text(cell.blank ? "–" : club(cell.opponentClubId) ?? "?")
                    .font(.caption2.weight(.bold))
                if cell.games > 1 {
                    Text("×\(cell.games)").font(.caption2.weight(.bold))
                }
            }
            .foregroundStyle(cell.band.map(DifficultyColor.text) ?? ToolkitColor.secondaryText)
            .frame(width: cellWidth, height: cellHeight)
            .background(cell.band.map(DifficultyColor.fill) ?? ToolkitColor.raised, in: shape)
            .overlay(shape.strokeBorder(ToolkitColor.accent, lineWidth: highlight && cell.suggested ? 2 : 0))
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.xs) {
            Text("Colour is FPL's difficulty (green easiest, red hardest); the opponent is the harder one in a double (×2). A dashed box means not in the squad that week.")
            if highlight { Text("Ringed: in that week's suggested XI.") }
        }
        .font(.footnote)
        .foregroundStyle(ToolkitColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Week by week (accessibility sizes)

    private func weekList(_ evo: PlannerEvolution) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            ForEach(Array(evo.weeks.enumerated()), id: \.element.gw) { index, week in
                VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
                    SectionLabel(text: "GW\(week.gw) · suggested \(week.formation)")
                    ForEach(evo.groups) { group in
                        ForEach(group.playerIds.filter { evo.cells(for: $0)[safe: index]?.inSquad == true }, id: \.self) { id in
                            if let cell = evo.cells(for: id)[safe: index] {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(evo.player(id)?.webName ?? "Player \(id)")
                                        .font(.headline)
                                        .foregroundStyle(ToolkitColor.primaryText)
                                    Text(cellText(cell))
                                        .font(.subheadline)
                                        .foregroundStyle(ToolkitColor.secondaryText)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Words

    private func club(_ id: Int?) -> String? { id.flatMap { appModel.club($0)?.shortName } }

    private func cellText(_ cell: PlannerEvolution.Cell) -> String {
        if cell.blank { return "No game" + (highlight && cell.suggested ? " · suggested XI" : "") }
        let opponent = cell.opponentClubId.flatMap { appModel.club($0)?.name } ?? "opponent to be confirmed"
        var parts = ["\(opponent) \(cell.home == true ? "at home" : "away")"]
        if cell.games > 1 { parts.append("\(cell.games) games") }
        if let fdr = cell.fdr { parts.append("difficulty \(fdr.formatted(.number.precision(.fractionLength(0...1)))) out of 5") }
        if highlight && cell.suggested { parts.append("suggested XI") }
        return parts.joined(separator: " · ")
    }

    private func rowLabel(_ id: Int, evo: PlannerEvolution) -> String {
        let player = evo.player(id)
        var parts = [player?.webName ?? "Player \(id)"]
        if let club = player.flatMap({ appModel.club($0.clubId)?.name }) { parts.append(club) }
        if let player { parts.append(Format.price(player.price)) }
        for cell in evo.cells(for: id) {
            parts.append("GW\(cell.gw) " + (cell.inSquad ? cellText(cell) : "not in the squad"))
        }
        return parts.joined(separator: ", ")
    }

    private func formationSpoken(_ formation: String) -> String {
        formation == "—" ? "no legal XI" : formation
    }

    private func reload() async {
        loadError = nil
        do {
            evolution = try await load()
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }
}

extension Position {
    /// "Goalkeepers", "Defenders"…: the grid's section headings.
    var plural: String {
        switch self {
        case .gk: "Goalkeepers"
        case .def: "Defenders"
        case .mid: "Midfielders"
        case .fwd: "Forwards"
        case .unknown: "Players"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
