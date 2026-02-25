//
//  OAuthService.swift
//  Claude Usage
//

import Foundation
import CryptoKit

@MainActor
final class OAuthService {

    // MARK: - Constants

    private enum OAuth {
        static let clientId     = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        // The Claude.ai OAuth server only accepts this HTTPS redirect URI (same as Claude Code CLI)
        static let redirectURI  = "https://platform.claude.com/oauth/code/callback"
        static let authURL      = "https://claude.ai/oauth/authorize"
        static let tokenURL     = "https://platform.claude.com/v1/oauth/token"
        static let scopes       = "user:inference user:profile"
    }

    // MARK: - Public API

    /// Step 1: Build the authorization URL and generate PKCE verifier.
    /// Open this URL in the browser. The server shows a code the user must copy.
    /// - Returns: (authorizationURL, pkceVerifier) — store the verifier for step 2.
    func buildAuthorizationURL() throws -> (url: URL, verifier: String) {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = UUID().uuidString

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
        return (authURL, verifier)
    }

    /// Step 2: Exchange the authorization code (copied by user) for tokens.
    /// - Parameters:
    ///   - code: The code displayed on the claude.ai page after login.
    ///   - verifier: The PKCE verifier returned by buildAuthorizationURL().
    func exchangeCode(_ code: String, verifier: String) async throws -> OAuthCredentials {
        let body: [String: String] = [
            "grant_type":    "authorization_code",
            "code":          code.trimmingCharacters(in: .whitespacesAndNewlines),
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

    private func postTokenRequest(body: [String: String]) async throws -> TokenResponse {
        guard let url = URL(string: OAuth.tokenURL) else {
            throw OAuthError.invalidURL
        }

        // OAuth 2.0 token endpoints require application/x-www-form-urlencoded (not JSON)
        var components = URLComponents()
        components.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let formBody = components.query?.data(using: .utf8) else {
            throw OAuthError.tokenExchangeFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody

        LoggingService.shared.log("OAuth POST \(url.absoluteString)")
        LoggingService.shared.log("OAuth body: \(String(data: formBody, encoding: .utf8) ?? "(nil)")")

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
