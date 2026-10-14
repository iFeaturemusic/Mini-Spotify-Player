import Foundation

struct SpotifyError: LocalizedError {
    let status: Int
    let message: String
    let reason: String?

    var errorDescription: String? { message }

    var isNoActiveDevice: Bool {
        reason == "NO_ACTIVE_DEVICE" || (status == 404 && message.localizedCaseInsensitiveContains("device"))
    }

    var userMessage: String {
        switch reason {
        case "PREMIUM_REQUIRED": return L("Für die Steuerung braucht Spotify ein Premium-Konto.")
        case "NO_ACTIVE_DEVICE": return L("Kein aktives Gerät gefunden.")
        default: break
        }
        if status == 403 && message.localizedCaseInsensitiveContains("not be registered") {
            return L("Spotify verweigert den Zugriff: Dein Konto ist in der Developer-App nicht freigeschaltet. Im Dashboard unter „User Management“ deine Spotify-E-Mail eintragen.")
        }
        if status == 403 && message.localizedCaseInsensitiveContains("scope") {
            return L("Spotify verweigert den Zugriff (403): fehlende Berechtigung. Bitte abmelden und neu anmelden.")
        }
        if status == 403 && message.lowercased() == "forbidden" {
            return L("Spotify verweigert den Zugriff (403). Seit 2026 funktionieren eigene Developer-Apps nur, wenn das Konto des App-Besitzers Spotify Premium hat.")
        }
        if status == 403 {
            return L("Spotify verweigert den Zugriff (403): %@", message)
        }
        if status == 429 {
            return L("Zu viele Anfragen – Spotify bremst kurz. Gleich nochmal versuchen.")
        }
        return message
    }
}

enum APILog {
    static let url: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MiniPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("api.log")
    }()

    static func write(_ line: String) {
        let entry = "\(Date().formatted(.iso8601)) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            if (try? handle.seekToEnd()) ?? 0 > 512 * 1024 { try? handle.truncate(atOffset: 0) }
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}

@MainActor
final class SpotifyAPI {
    static let base = "https://api.spotify.com/v1"

    let auth: SpotifyAuth
    let decoder = JSONDecoder.spotify

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    init(auth: SpotifyAuth) {
        self.auth = auth
    }

    @discardableResult
    func send(_ method: String, _ path: String, query: [String: String] = [:], json: [String: Any]? = nil) async throws -> Data {
        var components = URLComponents(string: path.hasPrefix("http") ? path : Self.base + path)!
        if !query.isEmpty {
            let extra = query.sorted { $0.key < $1.key }
                .map { "\($0.key)=\(urlEncode($0.value))" }
                .joined(separator: "&")
            if let existing = components.percentEncodedQuery, !existing.isEmpty {
                components.percentEncodedQuery = existing + "&" + extra
            } else {
                components.percentEncodedQuery = extra
            }
        }
        return try await perform(method, url: components.url!, json: json, retry: true)
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await send("GET", path, query: query)
        return try decoder.decode(T.self, from: data)
    }

    private func perform(_ method: String, url: URL, json: [String: Any]?, retry: Bool) async throws -> Data {
        let token = try await auth.accessToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != "GET" {
            request.httpBody = Data()
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        if (200..<300).contains(status) { return data }

        if status == 401 && retry {
            auth.expireAccessToken()
            return try await perform(method, url: url, json: json, retry: false)
        }
        if status == 429 && retry {
            let wait = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
            try await Task.sleep(for: .seconds(min(max(wait, 1), 10)))
            return try await perform(method, url: url, json: json, retry: false)
        }

        let body = try? decoder.decode(SpotifyErrorBody.self, from: data)
        let error = SpotifyError(
            status: status,
            message: body?.error?.message ?? HTTPURLResponse.localizedString(forStatusCode: status),
            reason: body?.error?.reason
        )
        APILog.write("\(method) \(url.path) → \(status) \(error.reason ?? "-") \(error.message)")
        throw error
    }
}

// MARK: - Library

extension SpotifyAPI {
/// Uses `/me/library` (2026) and falls back to the older `/me/tracks` endpoints.
    func setSaved(_ track: Track, saved: Bool) async throws {
        let method = saved ? "PUT" : "DELETE"
        do {
            try await send(method, "/me/library", query: ["uris": track.uri])
        } catch let error as SpotifyError where [400, 403, 404, 405].contains(error.status) {
            guard let id = track.id, track.uri.hasPrefix("spotify:track:") else { throw error }
            try await send(method, "/me/tracks", query: ["ids": id])
        }
    }

    func isSaved(_ track: Track) async -> Bool? {
        if let result = try? await get("/me/library/contains", query: ["uris": track.uri], as: [Bool].self) {
            return result.first
        }
        if let id = track.id, track.uri.hasPrefix("spotify:track:"),
           let result = try? await get("/me/tracks/contains", query: ["ids": id], as: [Bool].self) {
            return result.first
        }
        return nil
    }
}
