import Foundation
import Observation

/// The device's planner drafts (contract §13). Every rule runs on the server; this sends
/// requests and keeps the last copy of each list and gameweek for offline reading.
struct PlannerRepository: Sendable {
    let session: DeviceSession
    let cache: ResponseCache
    private static let base = "planner/drafts"

    var list: PlannerListEndpoint { PlannerListEndpoint(session: session, cache: cache) }

    func draft(_ id: String, gw: Int?) -> PlannerDraftEndpoint {
        PlannerDraftEndpoint(session: session, cache: cache, id: id, gw: gw)
    }

    func create(_ request: PlannerNewDraft) async throws -> PlannerDraft {
        let fetched = try await session.send("POST", Self.base, query: Self.view, body: request, as: PlannerDraft.self)
        return saved(fetched).value
    }

    /// One edit; the answer is the draft for that gameweek, or `invalid_action` with the reason.
    func apply(_ action: PlannerAction, to id: String) async throws -> Loaded<PlannerDraft> {
        let fetched = try await session.send("POST", "\(Self.base)/\(id)/actions", query: Self.view, body: action, as: PlannerDraft.self)
        return saved(fetched)
    }

    /// The draft as it would be after one edit, checked by the server but not saved
    /// (`?preview=1`, happy-backend-pal#43): the review step before "Save move to plan".
    func preview(_ action: PlannerAction, to id: String) async throws -> PlannerDraft {
        let query = Self.view + [URLQueryItem(name: "preview", value: "1")]
        return try await session.send("POST", "\(Self.base)/\(id)/actions", query: query, body: action, as: PlannerDraft.self).envelope.data
    }

    func update(_ id: String, _ patch: PlannerDraftPatch) async throws -> Loaded<PlannerDraft> {
        let fetched = try await session.send("PATCH", "\(Self.base)/\(id)", query: Self.view, body: patch, as: PlannerDraft.self)
        return saved(fetched)
    }

    func delete(_ id: String) async throws {
        _ = try await session.send("DELETE", "\(Self.base)/\(id)", as: DeleteResult.self)
        LastDraft.forget(id: id)
    }

    func picker(_ id: String, query: [URLQueryItem]) async throws -> PlannerPicker {
        try await session.send("GET", "\(Self.base)/\(id)/picker", query: query + Self.view, as: PlannerPicker.self).envelope.data
    }

    /// Today's notes for the squad planned in a gameweek (the website's Team news drawer).
    func news(_ id: String, gw: Int) async throws -> PlannerNews {
        let query = [URLQueryItem(name: "gw", value: String(gw))] + Self.view
        return try await session.send("GET", "\(Self.base)/\(id)/news", query: query, as: PlannerNews.self).envelope.data
    }

    /// Squad Rotation (the website's Squad Evolution grid) from a gameweek.
    func evolution(_ id: String, gw: Int) async throws -> PlannerEvolution {
        let query = [URLQueryItem(name: "gw", value: String(gw))] + Self.view
        return try await session.send("GET", "\(Self.base)/\(id)/evolution", query: query, as: PlannerEvolution.self).envelope.data
    }

    /// The website's Transfer & chip timeline.
    func plan(_ id: String) async throws -> PlannerPlan {
        try await session.send("GET", "\(Self.base)/\(id)/plan", query: Self.view, as: PlannerPlan.self).envelope.data
    }

    /// This device's shortlist.
    func shortlist() async throws -> PlannerShortlist {
        try await session.send("GET", "planner/shortlist", query: Self.view, as: PlannerShortlist.self).envelope.data
    }

    /// Adds a player to the shortlist, or sets his vibe flag; answers with the whole list.
    func saveShortlisted(_ playerId: Int, vibe: Bool? = nil) async throws -> PlannerShortlist {
        try await session.send("PUT", "planner/shortlist/\(playerId)", query: Self.view,
                               body: PlannerShortlistSave(vibe: vibe), as: PlannerShortlist.self).envelope.data
    }

    func removeShortlisted(_ playerId: Int) async throws -> PlannerShortlist {
        try await session.send("DELETE", "planner/shortlist/\(playerId)", query: Self.view, as: PlannerShortlist.self).envelope.data
    }

    /// The fixture model and lens chosen on this device, sent with every request.
    fileprivate static var view: [URLQueryItem] { FixtureView.current.queryItems }

    /// Keeps the answer as that gameweek's saved copy.
    private func saved(_ fetched: Fetched<PlannerDraft>) -> Loaded<PlannerDraft> {
        let draft = fetched.envelope.data
        cache.write(fetched.raw, for: PlannerDraftEndpoint.cacheKey(draft.id, gw: draft.gw))
        return Loaded(value: draft, meta: fetched.envelope.meta, savedAt: nil)
    }
}

struct PlannerListEndpoint: LoadableEndpoint {
    let session: DeviceSession
    let cache: ResponseCache
    private let key = "planner/drafts"

    func fetch(bypassCache: Bool = false) async throws -> Loaded<PlannerDraftList> {
        let fetched = try await session.send("GET", key, as: PlannerDraftList.self)
        cache.write(fetched.raw, for: key)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    func cached() -> Loaded<PlannerDraftList>? {
        CachedEndpoint<PlannerDraftList>(client: .production, cache: cache, path: key).cached()
    }
}

struct PlannerDraftEndpoint: LoadableEndpoint {
    let session: DeviceSession
    let cache: ResponseCache
    let id: String
    /// nil: the next deadline's gameweek.
    let gw: Int?

    static func cacheKey(_ id: String, gw: Int?) -> String {
        "planner/drafts/\(id)/gw-\(gw.map(String.init) ?? "next")"
    }

    func fetch(bypassCache: Bool = false) async throws -> Loaded<PlannerDraft> {
        let query = (gw.map { [URLQueryItem(name: "gw", value: String($0))] } ?? []) + FixtureView.current.queryItems
        let fetched = try await session.send("GET", "planner/drafts/\(id)", query: query, as: PlannerDraft.self)
        cache.write(fetched.raw, for: Self.cacheKey(id, gw: gw))
        if gw == nil { cache.write(fetched.raw, for: Self.cacheKey(id, gw: fetched.envelope.data.gw)) }
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    func cached() -> Loaded<PlannerDraft>? {
        CachedEndpoint<PlannerDraft>(client: .production, cache: cache, path: Self.cacheKey(id, gw: gw)).cached()
    }
}

/// One draft on screen: the gameweek shown, stepping between gameweeks, and edits. The draft
/// shown is always the server's answer; nothing is changed locally.
@MainActor
@Observable
final class DraftModel {
    let id: String
    private let repository: PlannerRepository
    private(set) var resource: Resource<PlannerDraft>

    init(id: String, repository: PlannerRepository) {
        self.id = id
        self.repository = repository
        self.resource = Resource(repository.draft(id, gw: nil))
    }

    var draft: PlannerDraft? { resource.loaded?.value }

    /// An edit is on its way to the server.
    private(set) var isApplying = false
    /// Why the last edit wasn't made (the server's reason, in words).
    private(set) var actionError: ErrorCopy?
    /// The player chosen with "Swap with…": the next player tapped swaps with him.
    var swapFrom: Int?

    /// Squad edits to undo and redo, per gameweek (in memory while the draft is open).
    private(set) var history = SquadHistory()
    var canUndo: Bool { draft.map { $0.isEditable && history.canUndo(gw: $0.gw) } ?? false }
    var canRedo: Bool { draft.map { $0.isEditable && history.canRedo(gw: $0.gw) } ?? false }
    /// Names of the players seen in this draft, so an undo can name one who has since left it.
    private var names: [Int: String] = [:]

    /// The edit an undo would take back, e.g. "Salah → Palmer".
    var undoSummary: String? {
        guard let d = draft, let old = history.previous(gw: d.gw) else { return nil }
        return summary(from: old, to: d.restorePicks)
    }

    /// The edit a redo would make again.
    var redoSummary: String? {
        guard let d = draft, let new = history.next(gw: d.gw) else { return nil }
        return summary(from: d.restorePicks, to: new)
    }

    private func summary(from old: SquadHistory.Squad, to new: SquadHistory.Squad) -> String {
        let before = Set(old.map(\.playerId)), after = Set(new.map(\.playerId))
        let out = old.map(\.playerId).filter { !after.contains($0) }
        let added = new.map(\.playerId).filter { !before.contains($0) }
        func name(_ id: Int) -> String { names[id] ?? "a player" }
        switch (out.count, added.count) {
        case (0, 0):
            return old.first(where: \.isCaptain)?.playerId != new.first(where: \.isCaptain)?.playerId
                ? "captain change" : "line-up change"
        case (1, 1): return "\(name(out[0])) → \(name(added[0]))"
        case (0, 1): return "adding \(name(added[0]))"
        case (1, 0): return "removing \(name(out[0]))"
        default: return "\(max(out.count, added.count)) changes"
        }
    }

    private func rememberNames() {
        for (key, player) in draft?.players ?? [:] {
            if let id = Int(key) { names[id] = player.webName }
        }
    }

    /// Sends one edit; true when it was made (the draft on screen is then the server's answer).
    /// Squad edits can be undone; a reset clears the history, since every week changes.
    @discardableResult
    func apply(_ action: PlannerAction) async -> Bool {
        rememberNames()
        let before = draft.flatMap { $0.gw == action.gw ? $0.restorePicks : nil }
        guard await send(action) else { return false }
        if action.isSquadEdit, let before, let gw = action.gw {
            history.record(before, gw: gw)
        } else if action.type == "reset" {
            history.clear()
        }
        return true
    }

    /// The draft as it would be after this edit, without saving it (the server checks it).
    func preview(_ action: PlannerAction) async throws -> PlannerDraft {
        try await repository.preview(action, to: id)
    }

    /// Back to the squad before the last edit in the gameweek shown.
    func undo() async {
        guard let d = draft, let squad = history.previous(gw: d.gw) else { return }
        rememberNames()
        if await send(.restore(squad, gw: d.gw)) { history.didUndo(gw: d.gw, from: d.restorePicks) }
    }

    /// Forward again to the squad the last undo left.
    func redo() async {
        guard let d = draft, let squad = history.next(gw: d.gw) else { return }
        rememberNames()
        if await send(.restore(squad, gw: d.gw)) { history.didRedo(gw: d.gw, from: d.restorePicks) }
    }

    private func send(_ action: PlannerAction) async -> Bool {
        await run { resource.replace(with: try await repository.apply(action, to: id)) }
    }

    /// Renames the draft or changes its starting budget or free transfers. The gameweek shown
    /// stays on screen (the server answers with the next deadline's).
    @discardableResult
    func update(_ patch: PlannerDraftPatch) async -> Bool {
        let shown = draft?.gw
        let done = await run { resource.replace(with: try await repository.update(id, patch)) }
        if done, let shown, draft?.gw != shown { await show(gw: shown) }
        return done
    }

    /// A copy of this draft, every planned week included; nil if it couldn't be made.
    func duplicate() async -> PlannerDraft? {
        var copy: PlannerDraft?
        _ = await run { copy = try await repository.create(.copy(id)) }
        return copy
    }

    /// Deletes the draft; true when it's gone.
    func delete() async -> Bool {
        await run { try await repository.delete(id) }
    }

    /// Runs one request, keeping `isApplying` and `actionError` up to date.
    private func run(_ work: () async throws -> Void) async -> Bool {
        isApplying = true
        actionError = nil
        defer { isApplying = false }
        do {
            try await work()
            return true
        } catch let error as APIError {
            actionError = ErrorCopy(error)
            return false
        } catch {
            return false
        }
    }

    func clearActionError() { actionError = nil }

    /// Players for a slot, with why each can't be chosen (the server decides).
    func candidates(_ query: [URLQueryItem]) async throws -> PlannerPicker {
        try await repository.picker(id, query: query)
    }

    func load() async {
        if resource.isInitial { await resource.load() }
    }

    /// The same gameweek again, e.g. after the fixture model or lens changes.
    func reload() async {
        await resource.load(bypassCache: true)
    }

    /// Squad Rotation from the gameweek shown.
    func evolution() async throws -> PlannerEvolution {
        try await repository.evolution(id, gw: draft?.gw ?? 1)
    }

    /// The Transfer & chip timeline.
    func plan() async throws -> PlannerPlan {
        try await repository.plan(id)
    }

    /// Team news for the squad in the gameweek shown.
    func news() async throws -> PlannerNews {
        try await repository.news(id, gw: draft?.gw ?? resource.loaded?.value.gw ?? 1)
    }

    /// True while another gameweek loads; the current one stays on screen meanwhile.
    private(set) var isStepping = false
    /// Why the last gameweek change didn't load.
    private(set) var stepError: ErrorCopy?

    /// The gameweeks the stepper can show: the starting squad's to 38.
    var gwRange: ClosedRange<Int>? {
        guard let d = draft else { return nil }
        return (d.baseGw ?? d.firstEditableGw)...d.lastGw
    }

    /// Shows another gameweek (a saved copy first when there is one).
    func show(gw: Int) async {
        guard let current = draft, gw != current.gw, gwRange?.contains(gw) == true else { return }
        isStepping = true
        stepError = nil
        defer { isStepping = false }
        let next = Resource(repository.draft(id, gw: gw))
        await next.load()
        if next.loaded != nil {
            resource = next
        } else if case .failed(let copy) = next.phase {
            stepError = copy
        }
    }
}

/// The draft last opened in the Planner: where "+" on a research list adds a player, as the
/// website's "+" adds to its current draft.
enum LastDraft {
    static let idKey = "planner.lastDraftId"
    static let nameKey = "planner.lastDraftName"

    static func remember(id: String, name: String?) {
        UserDefaults.standard.set(id, forKey: idKey)
        if let name { UserDefaults.standard.set(name, forKey: nameKey) }
    }

    /// Called when a draft is deleted, so "+" doesn't point at it.
    static func forget(id: String) {
        guard UserDefaults.standard.string(forKey: idKey) == id else { return }
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }
}

