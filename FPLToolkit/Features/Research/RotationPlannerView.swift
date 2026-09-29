import SwiftUI

/// The website's rotation planner (/dovetail): pick 2 to 6 players and see, week by week, who to
/// start, with the rotation's total difficulty against the best single player. The server runs the
/// website's own planner; this screen lays it out.
struct RotationPlannerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let entryId: Int?

    @AppStorage(FixtureView.modelKey) private var model = FixtureView.Model.xfdr
    @AppStorage(FixtureView.lensKey) private var lens = FixtureView.Lens.position
    @AppStorage("research.rotation.picks") private var picksRaw = ""
    @AppStorage("research.rotation.horizon") private var horizon = 6
    @State private var start: Int?
    @State private var starters = 1
    @State private var adding = false
    @State private var table = ResearchTable<ResearchRotation>()

    static let horizons = [3, 5, 6, 8, 10, 12]
    static let maxPlayers = 6

    /// A chosen player, saved with the name so the list reads before anything loads.
    struct Pick: Codable, Hashable, Identifiable {
        let id: Int
        let name: String
    }

    private var picks: [Pick] {
        (try? JSONDecoder().decode([Pick].self, from: Data(picksRaw.utf8))) ?? []
    }

    private func setPicks(_ picks: [Pick]) {
        picksRaw = (try? String(decoding: JSONEncoder().encode(picks), as: UTF8.self)) ?? ""
        starters = min(starters, maxStarters(for: picks.count))
    }

    private func maxStarters(for count: Int) -> Int { max(1, min(4, count - 1)) }

    private struct Options: Hashable {
        let ids: [Int]
        let horizon: Int
        let start: Int?
        let starters: Int
        let view: FixtureView
    }

    private var options: Options {
        Options(ids: picks.map(\.id), horizon: horizon, start: start, starters: starters,
                view: FixtureView(model: model, lens: lens))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                playersSection
                if picks.count >= 2 {
                    controls
                    ResearchTableView(table: table, caption: "Working out the rotation…", retry: reload) { rotation in
                        result(rotation)
                    }
                } else {
                    Text("Pick at least two players, ideally at a similar price, whose clubs rarely have a hard week at the same time. Two is the classic pair; more widens the choice each week but ties up budget.")
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.bottom, ToolkitSpace.section)
        }
        .refreshable { await table.refresh() }
        .toolkitScreen()
        .navigationTitle("Rotation planner")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: options) {
            guard options.ids.count >= 2 else { return }
            await load(options)
        }
        .sheet(isPresented: $adding) {
            AddPlayerSheet(entryId: entryId, chosen: Set(picks.map(\.id))) { player in
                var list = picks
                guard list.count < Self.maxPlayers, !list.contains(where: { $0.id == player.id }) else { return }
                list.append(Pick(id: player.id, name: player.webName))
                setPicks(list)
            }
        }
    }

    private func reload() { Task { await load(options) } }

    private func load(_ options: Options) async {
        await table.load(appModel.researchRepository.rotation(
            playerIds: options.ids, horizon: options.horizon, start: options.start,
            starters: options.starters, view: options.view))
    }

    // MARK: Players and controls

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.sm) {
            SectionLabel(text: "Players (\(picks.count) of \(Self.maxPlayers))")
            ForEach(picks) { pick in
                let player = (table.current?.loaded ?? table.previous)?.value.player(pick.id)
                HStack(spacing: ToolkitSpace.md) {
                    PlayerPhoto(path: player?.photo, clubLogo: appModel.club(player?.clubId)?.logo, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pick.name)
                            .font(.headline)
                            .foregroundStyle(ToolkitColor.primaryText)
                        ClubLabel(clubId: player?.clubId, text: pickDetails(pick.id), logoSize: 13)
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Button {
                        setPicks(picks.filter { $0.id != pick.id })
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(pick.name)")
                }
                .frame(minHeight: 44)
            }
            if picks.count < Self.maxPlayers {
                Button {
                    adding = true
                } label: {
                    Label("Add player", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.link)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func pickDetails(_ id: Int) -> String {
        guard let player = (table.current?.loaded ?? table.previous)?.value.player(id) else { return "" }
        return [appModel.club(player.clubId)?.shortName, Format.price(player.price)].compactMap { $0 }.joined(separator: " · ")
    }

    private var controls: some View {
        let loaded = (table.current?.loaded ?? table.previous)?.value
        let fromGw = start ?? loaded?.fromGw ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            (typeSize >= .xLarge
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(spacing: ToolkitSpace.lg))) {
                weeksMenu
                ResearchFixtureMenu(model: $model, lens: $lens)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Stepper(value: Binding(get: { fromGw }, set: { start = $0 }), in: 1...38) {
                Text("From GW\(fromGw)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
            }
            .frame(minHeight: 44)
            if picks.count >= 3 {
                Stepper(value: $starters, in: 1...maxStarters(for: picks.count)) {
                    Text(starters == 1 ? "Start 1 a week" : "Start \(starters) a week")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ToolkitColor.primaryText)
                }
                .frame(minHeight: 44)
            }
        }
    }

    private var weeksMenu: some View {
        Menu {
            Picker("Gameweeks", selection: $horizon) {
                ForEach(Self.horizons, id: \.self) { Text("\($0) gameweeks").tag($0) }
            }
        } label: {
            Label("\(horizon) gameweeks", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
                .frame(minHeight: 44)
        }
        .accessibilityLabel("Gameweeks: \(horizon)")
    }

    // MARK: Result

    private func result(_ rotation: ResearchRotation) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            figures(rotation)
            if typeSize.isAccessibilitySize {
                weekList(rotation)
            } else {
                grid(rotation)
            }
            Text(legend(rotation))
                .font(.footnote)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func figures(_ rotation: ResearchRotation) -> some View {
        let solo = rotation.starters > 1 ? "Best \(rotation.starters) solo FDR" : "Best solo FDR"
        let items = [
            ResearchFigure(label: "Rotation FDR", value: rotation.display.rotationTotal),
            ResearchFigure(label: solo, value: rotation.display.bestSolo),
            ResearchFigure(label: "Rotation gain", value: rotation.display.gain,
                           hint: rotation.starters > 1 ? "vs the best \(rotation.starters) every week" : "vs the best single player"),
            ResearchFigure(label: "Combined cost", value: rotation.display.combinedCost),
        ]
        // Two by two, or one column at accessibility sizes.
        let pair = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: ToolkitSpace.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: ToolkitSpace.sm))
        return VStack(spacing: ToolkitSpace.sm) {
            pair { items[0]; items[1] }
            pair { items[2]; items[3] }
        }
    }

    @ScaledMetric(relativeTo: .caption) private var nameWidth: CGFloat = 96
    @ScaledMetric(relativeTo: .caption) private var cellWidth: CGFloat = 54
    @ScaledMetric(relativeTo: .caption) private var cellHeight: CGFloat = 38
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 22

    private func grid(_ rotation: ResearchRotation) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Player")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .frame(width: nameWidth, height: headerHeight, alignment: .leading)
                    .accessibilityHidden(true)
                ForEach(rotation.playerIds, id: \.self) { id in
                    nameCell(id, rotation)
                        .frame(width: nameWidth, height: cellHeight, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spoken(id, rotation))
                }
            }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(rotation.weeks, id: \.gw) { week in
                            Text("GW\(week.gw)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ToolkitColor.primaryText)
                                .frame(width: cellWidth, height: headerHeight)
                        }
                    }
                    ForEach(rotation.playerIds, id: \.self) { id in
                        HStack(spacing: 4) {
                            ForEach(rotation.weeks, id: \.gw) { week in
                                if let cell = week.cells.first(where: { $0.playerId == id }) {
                                    cellView(cell, topPick: week.starterIds.first == id)
                                        .frame(width: cellWidth, height: cellHeight)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
                .padding(.trailing, 6)
            }
            .accessibilityHidden(true)
        }
    }

    private func nameCell(_ id: Int, _ rotation: ResearchRotation) -> some View {
        let player = rotation.player(id)
        let starts = rotation.startCounts[String(id)] ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(player?.webName ?? "Player \(id)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ToolkitColor.primaryText)
            Text("\(rotation.starters > 1 ? "Chosen" : "Starts") \(starts)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func cellView(_ cell: ResearchRotation.Cell, topPick: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        if cell.blank {
            Text("BGW")
                .font(.caption2.weight(.bold))
                .foregroundStyle(ToolkitColor.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ToolkitColor.raised, in: shape)
        } else {
            VStack(spacing: 0) {
                Text(cell.fixtures.map(opponent).joined(separator: "/"))
                    .font(.caption2.weight(.bold))
                Text(cell.fixtures.map { value($0.value) }.joined(separator: "/"))
                    .font(.caption2.weight(.semibold).monospacedDigit())
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(cell.band.map(DifficultyColor.text) ?? ToolkitColor.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cell.band.map(DifficultyColor.fill) ?? ToolkitColor.raised, in: shape)
            .opacity(cell.starter ? 1 : 0.5)
            .overlay(shape.strokeBorder(ToolkitColor.accent, lineWidth: cell.starter ? (topPick ? 3 : 2) : 0))
            .overlay(alignment: .topTrailing) {
                if topPick {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(ToolkitColor.onAccent)
                        .frame(width: 14, height: 14)
                        .background(ToolkitColor.accent, in: Circle())
                        .offset(x: 5, y: -5)
                }
            }
        }
    }

    /// The website's rotation labels: upper case at home, lower case away.
    private func opponent(_ fixture: ResearchRotation.Fixture) -> String {
        let name = fixture.opponentClubId.flatMap { appModel.club($0)?.shortName } ?? "tbc"
        return fixture.home ? name.uppercased() : name.lowercased()
    }

    /// As the website writes difficulty: xFDR to one decimal place, FPL's own whole.
    private func value(_ value: Double?) -> String {
        guard let value else { return "–" }
        return model == .xfdr ? value.formatted(.number.precision(.fractionLength(1))) : String(Int(value.rounded()))
    }

    // MARK: Week by week (accessibility sizes)

    private func weekList(_ rotation: ResearchRotation) -> some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
            ForEach(rotation.weeks, id: \.gw) { week in
                VStack(alignment: .leading, spacing: 2) {
                    Text("GW\(week.gw)")
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(week.cells.map { weekLine($0, week: week) }.joined(separator: "\n"))
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func weekLine(_ cell: ResearchRotation.Cell, week: ResearchRotation.Week) -> String {
        let name = (table.current?.loaded ?? table.previous)?.value.player(cell.playerId)?.webName ?? "Player"
        var text = "\(name): \(fixtureWords(cell))"
        if week.starterIds.first == cell.playerId {
            text += " · top pick"
        } else if cell.starter {
            text += " · start"
        }
        return text
    }

    // MARK: Words

    private func fixtureWords(_ cell: ResearchRotation.Cell) -> String {
        guard !cell.blank else { return "no game" }
        return cell.fixtures.map { fixture -> String in
            let name = fixture.opponentClubId.flatMap { appModel.club($0)?.name } ?? "opponent to be confirmed"
            return "\(name) \(fixture.home ? "at home" : "away") \(value(fixture.value))"
        }.joined(separator: " and ")
    }

    private func spoken(_ id: Int, _ rotation: ResearchRotation) -> String {
        let player = rotation.player(id)
        var parts = [player?.webName ?? "Player \(id)"]
        parts.append("\(rotation.starters > 1 ? "chosen" : "starts") \(rotation.startCounts[String(id)] ?? 0) of \(rotation.weeks.count) weeks")
        for week in rotation.weeks {
            guard let cell = week.cells.first(where: { $0.playerId == id }) else { continue }
            var text = "GW\(week.gw) \(fixtureWords(cell))"
            if week.starterIds.first == id { text += ", top pick" } else if cell.starter { text += ", start" }
            parts.append(text)
        }
        return parts.joined(separator: ", ")
    }

    private func legend(_ rotation: ResearchRotation) -> String {
        var text = rotation.starters > 1
            ? "Gold outlines are the best \(rotation.starters) starts each gameweek; the tick marks the top pick."
            : "The gold outline and tick mark who to start each gameweek."
        text += " Upper case is at home, lower case away; colour is the fixture's difficulty. A double counts a little easier, and a blank (BGW) counts as harder than any fixture."
        if rotation.blankWeeks > 0 {
            text += " None of these players has a game in \(rotation.blankWeeks) of these weeks."
        }
        return text
    }
}

/// Adds a player to a research screen (the rotation, the Elite comparison): your squad first, then
/// any player by name.
struct AddPlayerSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let entryId: Int?
    let chosen: Set<Int>
    /// VoiceOver hints: "Adds to the rotation", "Already in the rotation".
    var addHint = "Adds to the rotation"
    var chosenHint = "Already in the rotation"
    let onPick: (PlayerSummary) -> Void

    @State private var query = ""
    @State private var search: PlayerSearchModel?
    @State private var squad: [PlayerSummary] = []

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if squad.isEmpty {
                        Text("Search for any player by name.")
                            .font(.subheadline)
                            .foregroundStyle(ToolkitColor.secondaryText)
                            .listRowBackground(ToolkitColor.surface)
                    }
                    ForEach([Position.gk, .def, .mid, .fwd], id: \.self) { position in
                        let players = squad.filter { $0.position == position }
                        if !players.isEmpty {
                            Section(position.plural + " in your squad") {
                                ForEach(players) { row($0) }
                            }
                            .listRowBackground(ToolkitColor.surface)
                        }
                    }
                } else if let search {
                    results(search)
                }
            }
            .listStyle(.insetGrouped)
            .toolkitScreen()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all players")
            .navigationTitle("Add player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if search == nil { search = PlayerSearchModel(repository: appModel.playerRepository) }
                squad = loadSquad()
            }
            .task(id: query) { await search?.run(query) }
        }
    }

    @ViewBuilder
    private func results(_ search: PlayerSearchModel) -> some View {
        switch search.phase {
        case .idle, .tooShort:
            note("Type at least 2 letters of a player's name.")
        case .searching:
            HStack(spacing: ToolkitSpace.sm) {
                ProgressView()
                Text("Searching…").foregroundStyle(ToolkitColor.secondaryText)
            }
            .listRowBackground(ToolkitColor.surface)
        case .failed(let copy):
            note("\(copy.title). \(copy.message)")
        case .results(let query, let players):
            if players.isEmpty {
                note("No players match \u{201C}\(query)\u{201D}.")
            } else {
                Section {
                    ForEach(players) { row($0) }
                }
                .listRowBackground(ToolkitColor.surface)
            }
        }
    }

    private func row(_ player: PlayerSummary) -> some View {
        let isChosen = chosen.contains(player.id)
        return Button {
            onPick(player)
            dismiss()
        } label: {
            HStack(spacing: ToolkitSpace.md) {
                PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.webName)
                        .font(.headline)
                        .foregroundStyle(ToolkitColor.primaryText)
                    ClubLabel(
                        clubId: player.clubId,
                        text: [appModel.club(player.clubId)?.shortName, player.position.rawValue, Format.price(player.price)]
                            .compactMap { $0 }.joined(separator: " · ")
                    )
                        .font(.subheadline)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: isChosen ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(ToolkitColor.link)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isChosen)
        .accessibilityHint(isChosen ? chosenHint : addHint)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(ToolkitColor.secondaryText)
            .listRowBackground(ToolkitColor.surface)
    }

    /// Your last published squad, from the saved Team tab.
    private func loadSquad() -> [PlayerSummary] {
        guard let entryId, let team = appModel.teamRepository.team(entryId: entryId).cached()?.value,
              let picks = team.snapshot?.picks else { return [] }
        return picks.compactMap { team.players[String($0.playerId)] }
            .sorted { $0.price == $1.price ? $0.webName < $1.webName : $0.price > $1.price }
    }
}
