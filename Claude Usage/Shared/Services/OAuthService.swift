//
//  OAuthService.swift
//  Claude Usage
//

import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class OAuthService: NSObject {

    // MARK: - Constants

    private enum OAuth {
        static let clientId     = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        static let redirectURI  = "claudeusage://oauth/callback"
        static let authURL      = "https://claude.ai/oauth/authorize"
        static let tokenURL     = "https://claude.ai/v1/oauth/token"
        static let scopes       = "user:inference user:profile"
    }

    // MARK: - Public API

    /// Starts the OAuth login flow. Presents a browser sheet and returns OAuthCredentials on success.
    /// Call from the settings UI when the user taps "Mit Claude.ai verbinden".
    func startLogin(presentationAnchor: ASPresentationAnchor) async throws -> OAuthCredentials {
        // 1. Generate PKCE
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = UUID().uuidString

        // 2. Build auth URL
        var components = URLComponents(string: OAuth.authURL)!
        components.queryItems = [
            .init(name: "client_id",             value: OAuth.clientId),
            .init(name: "redirect_uri",           value: OAuth.redirectURI),
            .init(name: "response_type",          value: "code"),
            .init(name: "scope",                  value: OAuth.scopes),
            .init(name: "code_challenge",         value: challenge),
            .init(name: "code_challenge_method",  value: "S256"),
            .init(name: "state",                  value: state),
        ]
        guard let authURL = components.url else {
            throw OAuthError.invalidURL
        }

        // 3. Show browser sheet and wait for callback
        let callbackURL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "claudeusage"
            ) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: OAuthError.noCallbackURL)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
            // Keep session alive during await — store reference
            self.activeSession = session
        }

        activeSession = nil

        // 4. Validate state and extract code
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state,
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.invalidCallback
        }

        // 5. Exchange code for tokens
        return try await exchangeCode(code, verifier: verifier)
    }

    /// Refreshes the access token using the stored refresh token.
    /// Updates and returns new credentials; refreshToken stays the same unless server rotates it.
    func refreshToken(_ credentials: OAuthCredentials) async throws -> OAuthCredentials {
        let body: [String: String] = [
            "grant_type":    "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id":     OAuth.clientId,
        ]

        let response = try await postTokenRequest(body: body)

        return OAuthCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? credentials.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            email: credentials.email
        )
    }

    // MARK: - Private Helpers

    private var activeSession: ASWebAuthenticationSession?

    private func exchangeCode(_ code: String, verifier: String) async throws -> OAuthCredentials {
        let body: [String: String] = [
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  OAuth.redirectURI,
            "client_id":     OAuth.clientId,
            "code_verifier": verifier,
        ]

        let response = try await postTokenRequest(body: body)

        return OAuthCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            email: nil
        )
    }

    private func postTokenRequest(body: [String: String]) async throws -> TokenResponse {
        guard let url = URL(string: OAuth.tokenURL) else {
            throw OAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "(empty)"
            LoggingService.shared.log("OAuth token request failed: \(responseBody)")
            throw OAuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64URLEncodedString()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthService: ASWebAuthenticationPresentationContextProviding {
    // ASWebAuthenticationSession always calls presentationAnchor on the main thread,
    // so @MainActor is safe here even though the protocol requires nonisolated.
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first(where: { $0.isKeyWindow })
            ?? NSApplication.shared.windows.first
            ?? NSWindow()
    }
}

// MARK: - Supporting Types

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum OAuthError: LocalizedError {
    case invalidURL
    case noCallbackURL
    case invalidCallback
    case tokenExchangeFailed
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Ungültige OAuth URL."
        case .noCallbackURL:       return "Kein Callback von Claude.ai erhalten."
        case .invalidCallback:     return "OAuth Callback ungültig (State-Mismatch)."
        case .tokenExchangeFailed: return "Token-Austausch fehlgeschlagen. Bitte erneut versuchen."
        case .refreshFailed:       return "Token-Refresh fehlgeschlagen. Bitte erneut verbinden."
        }
    }
}

// MARK: - Data+Base64URL

private extension Data {
    /// URL-safe base64 without padding (RFC 4648 §5)
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
