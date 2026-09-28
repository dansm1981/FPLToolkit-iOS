import Foundation

/// A decoded response plus where it came from. `savedAt` is set only when it was
/// served from the offline cache, so screens can say "Saved at …" and never pass it off as fresh.
struct Loaded<T: Sendable>: Sendable {
    let value: T
    let meta: Meta
    let savedAt: Date?

    var isFromCache: Bool { savedAt != nil }
}

/// Something a screen can load: network first, with the last saved copy available.
protocol LoadableEndpoint<Value>: Sendable {
    associatedtype Value: Decodable & Sendable
    func fetch(bypassCache: Bool) async throws -> Loaded<Value>
    func cached() -> Loaded<Value>?
}

/// Network first; every good response is saved. `cached` returns the last saved copy, if any.
struct CachedEndpoint<T: Decodable & Sendable>: LoadableEndpoint {
    let client: APIClient
    let cache: ResponseCache
    let path: String
    /// Saved separately for each set of options.
    var query: [URLQueryItem] = []

    private var cacheKey: String {
        query.isEmpty ? path : path + "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }

    func fetch(bypassCache: Bool = false) async throws -> Loaded<T> {
        let fetched = try await client.get(path, query: query, as: T.self, bypassCache: bypassCache)
        cache.write(fetched.raw, for: cacheKey)
        return Loaded(value: fetched.envelope.data, meta: fetched.envelope.meta, savedAt: nil)
    }

    func cached() -> Loaded<T>? {
        guard let (data, savedAt) = cache.read(cacheKey) else { return nil }
        guard let envelope = try? APIClient.decode(Envelope<T>.self, from: data) else {
            // Saved by an older build with a different shape: drop it.
            cache.remove(cacheKey)
            return nil
        }
        return Loaded(value: envelope.data, meta: envelope.meta, savedAt: savedAt)
    }
}

struct BootstrapRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    var bootstrap: CachedEndpoint<Bootstrap> { .init(client: client, cache: cache, path: "bootstrap") }
}

struct TeamRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    func team(entryId: Int) -> CachedEndpoint<Team> {
        .init(client: client, cache: cache, path: "team/\(entryId)")
    }

    func today(entryId: Int) -> CachedEndpoint<Today> {
        .init(client: client, cache: cache, path: "team/\(entryId)/today")
    }
}

struct PlayerRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    func player(id: Int) -> CachedEndpoint<PlayerSheet> {
        .init(client: client, cache: cache, path: "players/\(id)")
    }

    /// One of the website's player page tabs, loaded when its section is opened.
    func tab<T: Decodable & Sendable>(_ id: Int, _ tab: PlayerTab, as type: T.Type) -> CachedEndpoint<T> {
        .init(client: client, cache: cache, path: "players/\(id)/\(tab.rawValue)")
    }

    /// Players whose names match, best first. Not saved offline: results are only useful live.
    func search(_ text: String) async throws -> PlayerSearchResult {
        try await client.get("players/search", query: [URLQueryItem(name: "q", value: text)], as: PlayerSearchResult.self).envelope.data
    }

    /// Whether the server has player search yet (it arrives with a backend release). Before
    /// then the address is caught by `players/{id}` ("invalid_player_id"), or doesn't exist (404).
    /// Any other failure (offline, FPL down) counts as available, so search isn't hidden by accident.
    func searchIsAvailable() async -> Bool {
        do {
            _ = try await search("aa")
            return true
        } catch APIError.server(.invalidPlayerId, _, _), APIError.unexpected(status: 404?) {
            return false
        } catch {
            return true
        }
    }
}

/// The Research tab (contract §15): public data, saved offline like Team and Today.
struct ResearchRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    func ticker(horizon: Int, fuzzy: Bool, sort: ResearchTicker.SortKey, hardestFirst: Bool,
                clubs: [Int]?, view: FixtureView) -> CachedEndpoint<ResearchTicker> {
        var query = view.queryItems + [
            URLQueryItem(name: "horizon", value: String(horizon)),
            URLQueryItem(name: "sort", value: sort.queryValue),
            URLQueryItem(name: "dir", value: hardestFirst ? "desc" : "asc"),
        ]
        if fuzzy { query.append(URLQueryItem(name: "fuzzy", value: "1")) }
        if let clubs, !clubs.isEmpty {
            query.append(URLQueryItem(name: "clubs", value: clubs.sorted().map(String.init).joined(separator: ",")))
        }
        return .init(client: client, cache: cache, path: "research/fixtures", query: query)
    }

    func rotation(playerIds: [Int], horizon: Int, start: Int?, starters: Int, view: FixtureView) -> CachedEndpoint<ResearchRotation> {
        var query = view.queryItems + [
            URLQueryItem(name: "players", value: playerIds.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "horizon", value: String(horizon)),
            URLQueryItem(name: "starters", value: String(starters)),
        ]
        if let start { query.append(URLQueryItem(name: "start", value: String(start))) }
        return .init(client: client, cache: cache, path: "research/rotation", query: query)
    }

    /// The DEFCON hub: the leaderboard's filters, then the reliability map's. Defaults are left out.
    func defcon(position: Position?, minStarts: Int, maxPrice: Double, sort: String,
                mapPosition: Position?, mapMinStarts: Int) -> CachedEndpoint<Defcon> {
        var query: [URLQueryItem] = []
        if let position { query.append(URLQueryItem(name: "position", value: position.rawValue)) }
        if minStarts != 1 { query.append(URLQueryItem(name: "minStarts", value: String(minStarts))) }
        if maxPrice != 0 { query.append(URLQueryItem(name: "maxPrice", value: String(maxPrice))) }
        if sort != "hits" { query.append(URLQueryItem(name: "sort", value: sort)) }
        if let mapPosition { query.append(URLQueryItem(name: "mapPosition", value: mapPosition.rawValue)) }
        if mapMinStarts != 1 { query.append(URLQueryItem(name: "mapMinStarts", value: String(mapMinStarts))) }
        return .init(client: client, cache: cache, path: "defcon", query: query)
    }

    var hauls: CachedEndpoint<Hauls> { .init(client: client, cache: cache, path: "deep-dives/hauls") }
    var consistency: CachedEndpoint<Consistency> { .init(client: client, cache: cache, path: "deep-dives/consistency") }
    var homeAway: CachedEndpoint<HomeAway> { .init(client: client, cache: cache, path: "deep-dives/home-away") }
    var records: CachedEndpoint<SeasonRecords> { .init(client: client, cache: cache, path: "deep-dives/records") }

    func congestion(days: Int, shortestRestFirst: Bool) -> CachedEndpoint<ResearchCongestion> {
        .init(client: client, cache: cache, path: "research/congestion", query: [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "sort", value: shortestRestFirst ? "rest" : "matches"),
        ])
    }
}

/// The Research tab's Market screens (contract §16): public data, saved offline.
struct MarketRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    func changes(day: String?) -> CachedEndpoint<MarketChanges> {
        .init(client: client, cache: cache, path: "market/changes",
              query: day.map { [URLQueryItem(name: "day", value: $0)] } ?? [])
    }

    func predictions(club: Int?, position: Position?, maxPrice: Int?) -> CachedEndpoint<MarketPredictions> {
        var query: [URLQueryItem] = []
        if let club { query.append(URLQueryItem(name: "club", value: String(club))) }
        if let position { query.append(URLQueryItem(name: "position", value: position.rawValue)) }
        if let maxPrice { query.append(URLQueryItem(name: "maxPrice", value: String(maxPrice))) }
        return .init(client: client, cache: cache, path: "market/predictions", query: query)
    }

    /// `ids`: only these players (My squad or Shortlist); nil for everyone.
    func trends(position: Position?, club: Int?, band: Int, ids: [Int]?, sort: String, ascending: Bool) -> CachedEndpoint<MarketTrends> {
        var query = [
            URLQueryItem(name: "band", value: String(band)),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "dir", value: ascending ? "asc" : "desc"),
        ]
        if let position { query.append(URLQueryItem(name: "position", value: position.rawValue)) }
        if let club { query.append(URLQueryItem(name: "club", value: String(club))) }
        if let ids { query.append(URLQueryItem(name: "ids", value: ids.sorted().map(String.init).joined(separator: ","))) }
        return .init(client: client, cache: cache, path: "market/trends", query: query)
    }

    var transfers: CachedEndpoint<MarketTransfers> {
        .init(client: client, cache: cache, path: "market/transfers")
    }
}

/// The Research tab's Players screens (contract §17): public data, saved offline.
struct PlayersResearchRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    func insights(position: Position?, club: Int?, search: String, sort: String, ascending: Bool?,
                  per90: Bool, fdrHorizon: Int) -> CachedEndpoint<PlayerInsights> {
        var query = [URLQueryItem(name: "sort", value: sort), URLQueryItem(name: "fdr", value: String(fdrHorizon))]
        if let ascending { query.append(URLQueryItem(name: "dir", value: ascending ? "asc" : "desc")) }
        if per90 { query.append(URLQueryItem(name: "per90", value: "1")) }
        if let position { query.append(URLQueryItem(name: "position", value: position.rawValue)) }
        if let club { query.append(URLQueryItem(name: "club", value: String(club))) }
        let text = search.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { query.append(URLQueryItem(name: "q", value: text)) }
        return .init(client: client, cache: cache, path: "players/insights", query: query)
    }

    func opportunity(metric: String, position: Position?, maxOwn: Int, minMins: Int) -> CachedEndpoint<OpportunityMap> {
        var query = [
            URLQueryItem(name: "metric", value: metric),
            URLQueryItem(name: "maxOwn", value: String(maxOwn)),
            URLQueryItem(name: "minMins", value: String(minMins)),
        ]
        if let position { query.append(URLQueryItem(name: "position", value: position.rawValue)) }
        return .init(client: client, cache: cache, path: "players/opportunity", query: query)
    }

    var template: CachedEndpoint<TemplateTeam> { .init(client: client, cache: cache, path: "players/template") }
    var injuries: CachedEndpoint<InjuryList> { .init(client: client, cache: cache, path: "players/injuries") }
}

/// The Research tab's Elite group (contract §19). `gw` nil means the newest published gameweek.
struct EliteRepository: Sendable {
    let client: APIClient
    let cache: ResponseCache

    enum OwnershipView: String, CaseIterable, Identifiable, Sendable {
        case all, core, differentials
        var id: String { rawValue }
    }

    private func page<Body>(_ name: String, gw: Int?, _ extra: [URLQueryItem] = []) -> CachedEndpoint<ElitePage<Body>> {
        let query = (gw.map { [URLQueryItem(name: "gw", value: String($0))] } ?? []) + extra
        return .init(client: client, cache: cache, path: "elite/\(name)", query: query)
    }

    func overview(gw: Int?) -> CachedEndpoint<ElitePage<EliteOverview>> { page("overview", gw: gw) }
    func transfers(gw: Int?) -> CachedEndpoint<ElitePage<EliteTransfers>> { page("transfers", gw: gw) }
    func captaincy(gw: Int?) -> CachedEndpoint<ElitePage<EliteCaptaincy>> { page("captaincy", gw: gw) }
    func template(gw: Int?) -> CachedEndpoint<ElitePage<EliteTemplate>> { page("template", gw: gw) }
    func movers(gw: Int?) -> CachedEndpoint<ElitePage<EliteMovers>> { page("movers", gw: gw) }
    func trends(gw: Int?) -> CachedEndpoint<ElitePage<EliteTrends>> { page("trends", gw: gw) }
    func chips(gw: Int?) -> CachedEndpoint<ElitePage<EliteChips>> { page("chips", gw: gw) }
    func structure(gw: Int?) -> CachedEndpoint<ElitePage<EliteStructure>> { page("structure", gw: gw) }

    /// The template race for one position, or all.
    func race(gw: Int?, position: Position?) -> CachedEndpoint<ElitePage<EliteRace>> {
        page("race", gw: gw, position.map { [URLQueryItem(name: "position", value: $0.rawValue)] } ?? [])
    }

    /// Up to eight players' elite ownership over the season, in the order chosen.
    func compare(gw: Int?, ids: [Int]) -> CachedEndpoint<ElitePage<EliteCompare>> {
        page("compare", gw: gw, ids.isEmpty ? [] : [URLQueryItem(name: "ids", value: ids.map(String.init).joined(separator: ","))])
    }

    /// The website's ownership table controls: highest first unless `ascending`, as a new column sorts.
    func ownership(gw: Int?, position: Position?, club: Int?, maxPrice: Double?, view: OwnershipView,
                   sort: String, ascending: Bool, search: String) -> CachedEndpoint<ElitePage<EliteOwnership>> {
        var query: [URLQueryItem] = []
        if let position { query.append(URLQueryItem(name: "position", value: position.rawValue)) }
        if let club { query.append(URLQueryItem(name: "club", value: String(club))) }
        if let maxPrice { query.append(URLQueryItem(name: "maxPrice", value: String(maxPrice))) }
        if view != .all { query.append(URLQueryItem(name: "view", value: view.rawValue)) }
        if sort != "owned_pct" { query.append(URLQueryItem(name: "sort", value: sort)) }
        if ascending { query.append(URLQueryItem(name: "dir", value: "asc")) }
        let text = search.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { query.append(URLQueryItem(name: "q", value: text)) }
        return page("ownership", gw: gw, query)
    }
}

