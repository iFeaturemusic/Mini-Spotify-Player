import AppKit
import CryptoKit
import Observation

struct AuthError: LocalizedError {
    let message: String
    var code: String?

    init(_ message: String, code: String? = nil) {
        self.message = message
        self.code = code
    }

    var errorDescription: String? { message }
}

@MainActor @Observable
/// Authorization Code flow with PKCE (no client secret). The refresh token lives in the Keychain.
final class SpotifyAuth {
    static let port: UInt16 = 8898
    static let redirectURI = "http://127.0.0.1:8898/callback"
    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-library-read",
        "user-library-modify",
        "playlist-read-private",
        "playlist-read-collaborative",
    ]

    private(set) var clientID: String
    private(set) var isLoggedIn: Bool
    private(set) var isAuthorizing = false
    var errorMessage: String?

    @ObservationIgnored var onLogin: (() -> Void)?
    @ObservationIgnored var onLogout: (() -> Void)?

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var tokenExpiry = Date.distantPast
    @ObservationIgnored private var refreshToken: String?
    @ObservationIgnored private var refreshTask: Task<String, Error>?
    @ObservationIgnored private var server: LoopbackServer?

    init() {
        clientID = UserDefaults.standard.string(forKey: "clientID") ?? ""
        isLoggedIn = UserDefaults.standard.bool(forKey: "loggedIn")
    }

    func setClientID(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != clientID else { return }
        if isLoggedIn { logout() }
        clientID = trimmed
        UserDefaults.standard.set(trimmed, forKey: "clientID")
    }

    // MARK: - Login

    func login() {
        guard !clientID.isEmpty, !isAuthorizing else { return }
        errorMessage = nil
        isAuthorizing = true

        Task {
            defer {
                isAuthorizing = false
                server = nil
            }
            do {
                let verifier = Self.randomString(64)
                let state = Self.randomString(24)
                let authorizeURL = makeAuthorizeURL(challenge: Self.challenge(for: verifier), state: state)

                let server = LoopbackServer()
                self.server = server
                let callback = try await server.waitForCallback(port: Self.port) {
                    NSWorkspace.shared.open(authorizeURL)
                }

                let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let param: (String) -> String? = { name in items.first { $0.name == name }?.value }

                if let error = param("error") {
                    throw AuthError(error == "access_denied" ? "Anmeldung wurde abgelehnt." : "Spotify-Fehler: \(error)")
                }
                guard param("state") == state, let code = param("code") else {
                    throw AuthError("Ungültige Antwort von Spotify.")
                }

                try await requestToken([
                    "grant_type": "authorization_code",
                    "code": code,
                    "redirect_uri": Self.redirectURI,
                    "client_id": clientID,
                    "code_verifier": verifier,
                ])
                isLoggedIn = true
                UserDefaults.standard.set(true, forKey: "loggedIn")
                onLogin?()
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelLogin() {
        server?.cancel()
    }

    func logout() {
        token = nil
        tokenExpiry = .distantPast
        refreshToken = nil
        Keychain.delete("refreshToken")
        UserDefaults.standard.set(false, forKey: "loggedIn")
        isLoggedIn = false
        onLogout?()
    }

    // MARK: - Tokens

    func accessToken() async throws -> String {
        if let token, tokenExpiry.timeIntervalSinceNow > 60 { return token }
        if let refreshTask { return try await refreshTask.value }

        let task = Task<String, Error> {
// Re-read every time: Spotify may rotate the token, and another process may have refreshed it.
            refreshToken = Keychain.get("refreshToken") ?? refreshToken
            guard isLoggedIn, let refresh = refreshToken else {
                throw AuthError("Nicht angemeldet.")
            }
            do {
                try await requestToken([
                    "grant_type": "refresh_token",
                    "refresh_token": refresh,
                    "client_id": clientID,
                ])
            } catch let error as AuthError where error.code == "invalid_grant" || error.code == "invalid_client" {
                logout()
                throw AuthError("Sitzung abgelaufen – bitte neu anmelden.")
            }
            guard let token else { throw AuthError("Kein Token erhalten.") }
            return token
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func expireAccessToken() {
        tokenExpiry = .distantPast
    }

    private func requestToken(_ params: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(params.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let code = object?["error"] as? String
            let description = object?["error_description"] as? String
            throw AuthError(description ?? code ?? "Token-Fehler (\(status))", code: code)
        }

        let decoded = try JSONDecoder.spotify.decode(TokenResponse.self, from: data)
        token = decoded.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        if let newRefresh = decoded.refreshToken, newRefresh != refreshToken {
            refreshToken = newRefresh
            Keychain.set(newRefresh, for: "refreshToken")
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?
    }

    // MARK: - PKCE

    private func makeAuthorizeURL(challenge: String, state: String) -> URL {
        let params = [
            "response_type": "code",
            "client_id": clientID,
            "scope": Self.scopes.joined(separator: " "),
            "redirect_uri": Self.redirectURI,
            "code_challenge_method": "S256",
            "code_challenge": challenge,
            "state": state,
        ]
        let query = params.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
        return URL(string: "https://accounts.spotify.com/authorize?\(query)")!
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars.randomElement(using: &generator)! })
    }

    private static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
