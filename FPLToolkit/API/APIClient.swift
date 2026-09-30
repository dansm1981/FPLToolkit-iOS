import Foundation

/// The only thing in the app that talks to the network. Everything goes to /api/mobile/v1/*.
struct APIClient: Sendable {
    static let production = APIClient(baseURL: URL(string: "https://www.fpltoolkit.co.uk/api/mobile/v1/")!, recent: .shared)

    /// Production, except in debug builds launched with `-apiBaseURL <url>` (e.g. an unreachable
    /// host to check the offline states).
    static var configured: APIClient {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "apiBaseURL"), let url = URL(string: override) {
            return APIClient(baseURL: url, recent: .shared)
        }
        #endif
        return .production
    }

    let baseURL: URL
    var session: URLSession = .shared
    /// Recent GET answers in memory (the app's clients; tests leave it out).
    var recent: RecentResponses?

    /// Fetches `path` and decodes the v1 envelope. Returns the raw bytes too, for the offline cache.
    func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: T.Type,
        bypassCache: Bool = false
    ) async throws -> Fetched<T> {
        try await send("GET", path, query: query, as: type, bypassCache: bypassCache)
    }

    /// Any v1 request. `authorization` is the device header for /devices/me routes;
    /// `body` is sent as JSON.
    func send<T: Decodable & Sendable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        authorization: String? = nil,
        as type: T.Type,
        bypassCache: Bool = false
    ) async throws -> Fetched<T> {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        let recentKey = url.absoluteString
        if method == "GET", !bypassCache, let data = recent?.fresh(recentKey),
           let envelope = try? Self.decode(Envelope<T>.self, from: data) {
            return Fetched(envelope: envelope, raw: data)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        if bypassCache || authorization != nil { request.cachePolicy = .reloadIgnoringLocalCacheData }
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError(urlError: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.unexpected(status: nil)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let body = try? Self.decode(ErrorEnvelope.self, from: data) {
                throw APIError.server(code: body.error.code, message: body.error.message, retryable: body.error.retryable)
            }
            throw APIError.unexpected(status: status)
        }

        let envelope: Envelope<T>
        do {
            envelope = try Self.decode(Envelope<T>.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
        if method == "GET" {
            let cacheControl = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control")
            recent?.keep(data, for: recentKey, cacheControl: authorization == nil ? cacheControl : nil)
        } else {
            recent?.removeAll()
        }
        return Fetched(envelope: envelope, raw: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(string)")
        }
        return try decoder.decode(type, from: data)
    }

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "FPLToolkit-iOS/\(version)"
    }()
}

struct Fetched<T: Decodable & Sendable>: Sendable {
    let envelope: Envelope<T>
    let raw: Data
}

enum APIError: Error, Sendable, Equatable {
    /// The API answered with its v1 error shape (§2.2).
    case server(code: APIErrorCode, message: String, retryable: Bool)
    case offline
    case timedOut
    case unexpected(status: Int?)
    case decoding(String)

    init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            self = .offline
        case .timedOut:
            self = .timedOut
        default:
            self = .unexpected(status: nil)
        }
    }

    var code: APIErrorCode? {
        if case .server(let code, _, _) = self { return code }
        return nil
    }
}
