import Foundation

/// Undo and redo for squad edits, kept as the website keeps them (`src/lib/fpl/history.ts`):
/// one stack per gameweek, 50 deep, squads only (a chip is undone by tapping it again), in memory
/// for as long as the draft is open. Going back sends the old squad with the "restore" action, so
/// the server re-checks it like any other edit.
struct SquadHistory: Sendable {
    typealias Squad = [PlannerAction.RestorePick]
    static let limit = 50

    private var past: [Int: [Squad]] = [:]
    private var future: [Int: [Squad]] = [:]

    func canUndo(gw: Int) -> Bool { !(past[gw] ?? []).isEmpty }
    func canRedo(gw: Int) -> Bool { !(future[gw] ?? []).isEmpty }

    /// The squad to go back to, if any (applied first; `didUndo` once the server agrees).
    func previous(gw: Int) -> Squad? { past[gw]?.last }
    /// The squad to go forward to, if any (applied first; `didRedo` once the server agrees).
    func next(gw: Int) -> Squad? { future[gw]?.last }

    /// Before a new edit: the squad as it was. A new edit clears redo, as on the website.
    mutating func record(_ squad: Squad, gw: Int) {
        var stack = past[gw] ?? []
        stack.append(squad)
        past[gw] = Array(stack.suffix(Self.limit))
        future[gw] = []
    }

    mutating func didUndo(gw: Int, from current: Squad) {
        guard past[gw]?.popLast() != nil else { return }
        future[gw] = Array(((future[gw] ?? []) + [current]).suffix(Self.limit))
    }

    mutating func didRedo(gw: Int, from current: Squad) {
        guard future[gw]?.popLast() != nil else { return }
        past[gw] = Array(((past[gw] ?? []) + [current]).suffix(Self.limit))
    }

    /// After a reset every week changes, so no saved squad still applies.
    mutating func clear() {
        past = [:]
        future = [:]
    }
}
