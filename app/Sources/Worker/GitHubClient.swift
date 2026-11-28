import CryptoKit
import Foundation

enum GitHubError: Error, LocalizedError, RetryAfterError {
    case rateLimited(until: Date)
    case status(Int)
    case invalidResponse

    var retryAfter: Date? {
        if case .rateLimited(let until) = self { return until }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .rateLimited(let until):
            "GitHub's rate limit was reached. Try again after \(until.formatted(date: .omitted, time: .shortened))."
        case .status(let code):
            "GitHub returned an error (\(code))."
        case .invalidResponse:
            "GitHub returned an unexpected response."
        }
    }
}

actor GitHubClient {
    static let shared = GitHubClient()

    private struct CachedResponse: Codable {
        var etag: String
        var body: Data
    }

    private static let base = URL(string: "https://api.github.com")!
    private static let secondaryLimitWait: TimeInterval = 60

    private let token: String?
    private let session: URLSession
    private let cacheDirectory: URL?
    private var blockedUntil: Date?

    init(token: String? = nil) {
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        let namespace = token.map { "user-" + Self.digest($0).prefix(16) } ?? "public"
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Argon", isDirectory: true)
            .appendingPathComponent("GitHub", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let data = try await data(path, query: query)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitHubError.invalidResponse
        }
    }

    func data(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        if let blockedUntil, blockedUntil > Date() { throw GitHubError.rateLimited(until: blockedUntil) }
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw GitHubError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Argon", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let cached = cachedResponse(for: url)
        if let cached { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        noteRateLimit(http)

        switch http.statusCode {
        case 304:
            guard let cached else { throw GitHubError.invalidResponse }
            return cached.body
        case 200..<300:
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                store(CachedResponse(etag: etag, body: body), for: url)
            }
            return body
        case 403, 429:
            if let until = rateLimitReset(http) {
                blockedUntil = until
                throw GitHubError.rateLimited(until: until)
            }
            throw GitHubError.status(http.statusCode)
        default:
            throw GitHubError.status(http.statusCode)
        }
    }

    private func noteRateLimit(_ response: HTTPURLResponse) {
        guard response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
              let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init) else { return }
        blockedUntil = Date(timeIntervalSince1970: reset)
    }

    private func rateLimitReset(_ response: HTTPURLResponse) -> Date? {
        if let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
            return Date().addingTimeInterval(seconds)
        }
        if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
           let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: reset)
        }
        return response.statusCode == 429 ? Date().addingTimeInterval(Self.secondaryLimitWait) : nil
    }

    private func cacheFile(for url: URL) -> URL? {
        cacheDirectory?.appendingPathComponent(Self.digest(url.absoluteString) + ".plist")
    }

    private func cachedResponse(for url: URL) -> CachedResponse? {
        guard let file = cacheFile(for: url), let data = try? Data(contentsOf: file) else { return nil }
        return try? PropertyListDecoder().decode(CachedResponse.self, from: data)
    }

    private func store(_ response: CachedResponse, for url: URL) {
        guard let file = cacheFile(for: url), let directory = cacheDirectory else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(response) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private static func digest(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
