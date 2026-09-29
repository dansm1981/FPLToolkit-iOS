import Foundation
import Observation

/// Mini-leagues (contract, happy-backend-pal#21): the device's saved leagues and each league's
/// Overview, Standings and manager comparison. Needs a connection; nothing is worked out here.
struct LeaguesRepository: Sendable {
    let session: DeviceSession

    func list() async throws -> LeagueList {
        try await session.send("GET", "leagues", as: LeagueList.self).envelope.data
    }

    /// Saves a league; the server reads it from FPL first if it's stale (can take up to a minute).
    func save(_ leagueId: Int) async throws -> LeagueList {
        try await session.send("PUT", "leagues/\(leagueId)", as: LeagueList.self).envelope.data
    }

    /// One player in each mini-league saved on this device (happy-backend-pal#48).
    func playerOwnership(_ playerId: Int) async throws -> PlayerLeagues {
        try await session.send("GET", "players/\(playerId)/leagues", as: PlayerLeagues.self).envelope.data
    }

    func remove(_ leagueId: Int) async throws -> LeagueList {
        try await session.send("DELETE", "leagues/\(leagueId)", as: LeagueList.self).envelope.data
    }

    func overview(_ leagueId: Int, baseline: LeagueBaseline) async throws -> LeagueOverview {
        try await session.send("GET", "leagues/\(leagueId)/overview", query: baseline.queryItems, as: LeagueOverview.self).envelope.data
    }

    func standings(_ leagueId: Int) async throws -> LeagueStandings {
        try await session.send("GET", "leagues/\(leagueId)/standings", as: LeagueStandings.self).envelope.data
    }

    func rivals(_ leagueId: Int, baseline: LeagueBaseline) async throws -> LeagueRivals {
        try await get("rivals", leagueId, baseline.queryItems)
    }

    func players(_ leagueId: Int, baseline: LeagueBaseline) async throws -> LeaguePlayers {
        try await get("players", leagueId, baseline.queryItems)
    }

    func captains(_ leagueId: Int) async throws -> LeagueCaptains { try await get("captains", leagueId) }

    func chips(_ leagueId: Int) async throws -> LeagueChips { try await get("chips", leagueId) }

    /// `recent`: the last six gameweeks; otherwise the synced one.
    func transfers(_ leagueId: Int, recent: Bool) async throws -> LeagueTransfers {
        try await get("transfers", leagueId, [URLQueryItem(name: "scope", value: recent ? "recent" : "gw")])
    }

    func history(_ leagueId: Int) async throws -> LeagueHistory { try await get("history", leagueId) }

    func report(_ leagueId: Int, gw: Int?) async throws -> LeagueReport {
        try await get("report", leagueId, gw.map { [URLQueryItem(name: "gw", value: String($0))] } ?? [])
    }

    private func get<T: Decodable & Sendable>(_ tab: String, _ leagueId: Int, _ query: [URLQueryItem] = []) async throws -> T {
        try await session.send("GET", "leagues/\(leagueId)/\(tab)", query: query, as: T.self).envelope.data
    }

    func vs(_ leagueId: Int, entryId: Int, baseline: LeagueBaseline) async throws -> LeagueVs {
        try await session.send("GET", "leagues/\(leagueId)/vs/\(entryId)", query: baseline.queryItems, as: LeagueVs.self).envelope.data
    }
}

/// The device's leagues, shared by the Team tab's card and each league screen.
@MainActor
@Observable
final class LeaguesStore {
    let repository: LeaguesRepository
    private(set) var list: LeagueList?
    private(set) var loadError: ErrorCopy?
    private(set) var updateError: ErrorCopy?
    /// A league being added (its sync can take a while).
    private(set) var adding: Int?

    init(repository: LeaguesRepository) {
        self.repository = repository
    }

    func load() async {
        loadError = nil
        do {
            list = try await repository.list()
        } catch let error as APIError {
            loadError = ErrorCopy(error)
        } catch {}
    }

    func loadIfNeeded() async {
        if list == nil { await load() }
    }

    /// True when the league was saved.
    @discardableResult
    func add(_ leagueId: Int) async -> Bool {
        adding = leagueId
        updateError = nil
        defer { adding = nil }
        do {
            list = try await repository.save(leagueId)
            return true
        } catch let error as APIError {
            updateError = ErrorCopy(error)
            return false
        } catch {
            return false
        }
    }

    func remove(_ leagueId: Int) async {
        updateError = nil
        do {
            list = try await repository.remove(leagueId)
        } catch let error as APIError {
            updateError = ErrorCopy(error)
        } catch {}
    }

    func clearError() { updateError = nil }

    func reset() {
        list = nil
        loadError = nil
        updateError = nil
    }
}
