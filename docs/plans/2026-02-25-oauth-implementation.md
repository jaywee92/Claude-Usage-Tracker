# OAuth ASWebAuthenticationSession Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add OAuth login via `ASWebAuthenticationSession` to each profile so users don't need to manually copy session keys — the app fetches and auto-refreshes tokens silently.

**Architecture:** New `OAuthCredentials` model stored in `Profile`; new `OAuthService` handles PKCE flow and token refresh. `ClaudeAPIService.getAuthentication()` gains a priority-2 slot for OAuth credentials with auto-refresh before expiry. UI adds a "Mit Claude.ai verbinden" button in the existing credentials section (new `OAuthCredentialsView`).

**Tech Stack:** Swift / SwiftUI, `AuthenticationServices.ASWebAuthenticationSession`, `CryptoKit` (SHA256 for PKCE), `Foundation.URLSession` (token exchange/refresh), `UserDefaults` via existing `ProfileStore`.

---

## Context: How the Codebase Works

### Credential Storage
All profiles are stored as `[Profile]` serialized to UserDefaults (`"profiles_v3"` key via `ProfileStore.shared`). Credentials live directly on the `Profile` struct as optional strings — no Keychain for app storage.

### Current Auth Priority in `ClaudeAPIService.getAuthentication()`
1. `claudeSessionKey` (manual session cookie)
2. `cliCredentialsJSON` (CLI OAuth stored in profile — checked for expiry)
3. System Keychain CLI OAuth (fallback)

### How to Update a Profile
```swift
var profiles = ProfileStore.shared.loadProfiles()
profiles[index].someField = newValue
ProfileStore.shared.saveProfiles(profiles)
// Also update in-memory via ProfileManager:
ProfileManager.shared.updateProfile(profiles[index])
```

### Key File Locations
- `Claude Usage/Shared/Models/Profile.swift` — Profile struct
- `Claude Usage/Shared/Services/ClaudeAPIService.swift` — auth logic
- `Claude Usage/Shared/Services/ClaudeCodeSyncService.swift` — token extraction helpers
- `Claude Usage/Views/Settings/Credentials/PersonalUsageView.swift` — session key UI
- `Claude Usage/Views/Settings/Credentials/CLIAccountView.swift` — CLI sync UI
- `Claude Usage/Views/SettingsView.swift` — settings navigation

---

## Task 1: Create `OAuthCredentials` Model

**Files:**
- Create: `Claude Usage/Shared/Models/OAuthCredentials.swift`

**Step 1: Create the file**

```swift
//
//  OAuthCredentials.swift
//  Claude Usage
//

import Foundation

struct OAuthCredentials: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String?

    var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Returns true if the token expires within the next 5 minutes.
    var expiresInFiveMinutes: Bool {
        Date() >= expiresAt.addingTimeInterval(-300)
    }
}
```

**Step 2: Verify it compiles (no tests yet)**

Open Xcode → Product → Build (⌘B). Expected: Build Succeeded.

**Step 3: Commit**

```bash
git add "Claude Usage/Shared/Models/OAuthCredentials.swift"
git commit -m "feat: add OAuthCredentials model"
```

---

## Task 2: Add `oauthCredentials` Field to `Profile`

**Files:**
- Modify: `Claude Usage/Shared/Models/Profile.swift`

**Step 1: Find the credentials block in Profile.swift**

Look for the section with `var claudeSessionKey: String?` — add `oauthCredentials` right after `apiOrganizationId`:

```swift
// MARK: - Credentials
var claudeSessionKey: String?
var organizationId: String?
var apiSessionKey: String?
var apiOrganizationId: String?
var cliCredentialsJSON: String?
var oauthCredentials: OAuthCredentials?   // ← ADD THIS LINE
```

**Step 2: Add computed property `hasOAuthCredentials`**

Find the block with `var hasClaudeAI: Bool` and add:

```swift
var hasOAuthCredentials: Bool { oauthCredentials != nil }
```

**Step 3: Update `hasUsageCredentials` to include OAuth**

Find `var hasUsageCredentials: Bool` and add `|| hasOAuthCredentials`:

```swift
var hasUsageCredentials: Bool {
    hasClaudeAI || hasAPIConsole || hasValidCLIOAuth || hasValidSystemCLIOAuth || hasOAuthCredentials
}
```

**Step 4: Build to verify**

⌘B. Expected: Build Succeeded. `OAuthCredentials` is Codable so `Profile` remains Codable automatically.

**Step 5: Commit**

```bash
git add "Claude Usage/Shared/Models/Profile.swift"
git commit -m "feat: add oauthCredentials field to Profile model"
```

---

## Task 3: Create `OAuthService`

**Files:**
- Create: `Claude Usage/Shared/Services/OAuthService.swift`

This service handles PKCE generation, `ASWebAuthenticationSession` login, token exchange, and token refresh.

**Step 1: Create the file**

```swift
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
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state,
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.invalidCallback
        }

        // 5. Exchange code for tokens
        return try await exchangeCode(code, verifier: verifier)
    }

    /// Refreshes the access token using the stored refresh token.
    /// Updates and returns new credentials; refreshToken stays the same unless server rotates it.
    func refreshToken(_ credentials: OAuthCredentials) async throws -> OAuthCredentials {
        var body: [String: String] = [
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
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            LoggingService.shared.log("OAuth token request failed: \(body)")
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
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return key window for sheet presentation
        return NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first!
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
    /// URL-safe base64 without padding
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

**Step 2: Build to verify**

⌘B. Expected: Build Succeeded. You may need to add `import AuthenticationServices` and `import CryptoKit` at the top if Xcode doesn't find them automatically — they're already in the file above.

**Step 3: Commit**

```bash
git add "Claude Usage/Shared/Services/OAuthService.swift"
git commit -m "feat: add OAuthService with PKCE flow and token refresh"
```

---

## Task 4: Register URL Scheme `claudeusage` in Info.plist

**Files:**
- Modify: `Claude Usage/Resources/Info.plist`

**Step 1: Open Info.plist in Xcode**

In Xcode, click the project in the navigator → select the "Claude Usage" target → open the "Info" tab. Or open `Claude Usage/Resources/Info.plist` directly.

**Step 2: Add URL Types**

In Info.plist (source code view), add this block inside the root `<dict>`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>claudeusage</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.claudeusage.oauth</string>
    </dict>
</array>
```

**Step 3: Build to verify**

⌘B. Expected: Build Succeeded. The URL scheme is now registered so `ASWebAuthenticationSession` can receive the callback.

**Step 4: Commit**

```bash
git add "Claude Usage/Resources/Info.plist"
git commit -m "feat: register claudeusage:// URL scheme for OAuth callback"
```

---

## Task 5: Add Auto-Refresh to `ClaudeAPIService`

**Files:**
- Modify: `Claude Usage/Shared/Services/ClaudeAPIService.swift`

The goal: insert OAuth credentials as priority 2 in `getAuthentication()`, with silent refresh when token expires in <5 minutes. Also store updated credentials back to the profile after refresh.

**Step 1: Locate `getAuthentication()` in ClaudeAPIService.swift**

Find the method `private func getAuthentication() throws -> AuthenticationType`. It currently has 3 fallback paths:
1. `claudeSessionKey`
2. `cliCredentialsJSON`
3. System Keychain

**Step 2: Insert OAuth block as priority 2 (between claudeSessionKey and cliCredentialsJSON)**

Add this block after the `claudeSessionKey` block and before the `cliCredentialsJSON` block:

```swift
// Priority 2: OAuth credentials (with auto-refresh)
if var oauthCreds = activeProfile.oauthCredentials {
    if oauthCreds.expiresInFiveMinutes {
        // Refresh silently
        do {
            let refreshed = try await OAuthService().refreshToken(oauthCreds)
            oauthCreds = refreshed
            // Persist updated credentials
            var profiles = ProfileStore.shared.loadProfiles()
            if let index = profiles.firstIndex(where: { $0.id == activeProfile.id }) {
                profiles[index].oauthCredentials = refreshed
                ProfileStore.shared.saveProfiles(profiles)
                await MainActor.run {
                    ProfileManager.shared.updateProfile(profiles[index])
                }
            }
        } catch {
            LoggingService.shared.log("OAuth auto-refresh failed: \(error.localizedDescription)")
            // Fall through to next auth method
        }
    }
    if !oauthCreds.isExpired {
        return .cliOAuth(oauthCreds.accessToken)
    }
}
```

**Note:** `getAuthentication()` may currently be `throws` (sync). If it needs `await`, change the signature to `async throws`. Check if there are callers that need updating — search for all calls to `getAuthentication()` in the file and ensure they use `try await` or `try`.

**Step 3: If `getAuthentication` was sync, make it async**

If the method signature was `private func getAuthentication() throws`, change it to:
```swift
private func getAuthentication() async throws -> AuthenticationType
```

Then find all call sites in the same file and add `await`:
```swift
let auth = try await getAuthentication()
```

**Step 4: Build to verify**

⌘B. Expected: Build Succeeded. Fix any `async`/`await` propagation errors.

**Step 5: Commit**

```bash
git add "Claude Usage/Shared/Services/ClaudeAPIService.swift"
git commit -m "feat: add OAuth auto-refresh in ClaudeAPIService authentication priority"
```

---

## Task 6: Create `OAuthCredentialsView` (Settings UI)

**Files:**
- Create: `Claude Usage/Views/Settings/Credentials/OAuthCredentialsView.swift`

This is a new SwiftUI view shown in the credentials section of settings. It shows:
- If not connected: "Kein manueller Session-Key nötig" + "Mit Claude.ai verbinden" button
- If connected: email (if available), "Verbindung trennen" button

**Step 1: Create the file**

```swift
//
//  OAuthCredentialsView.swift
//  Claude Usage
//

import SwiftUI
import AuthenticationServices

struct OAuthCredentialsView: View {
    let profileId: UUID

    @StateObject private var profileManager = ProfileManager.shared
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private var profile: Profile? {
        profileManager.profiles.first { $0.id == profileId }
            ?? profileManager.activeProfile
    }

    private var oauthCreds: OAuthCredentials? {
        profile?.oauthCredentials
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundColor(.accentColor)
                Text("Claude.ai OAuth")
                    .font(.headline)
            }

            if let creds = oauthCreds {
                // Connected state
                connectedView(creds: creds)
            } else {
                // Not connected state
                notConnectedView
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Connected View

    private func connectedView(creds: OAuthCredentials) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                if let email = creds.email {
                    Text("Verbunden als \(email)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Verbunden")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Button("Verbindung trennen") {
                disconnect()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    // MARK: - Not Connected View

    private var notConnectedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kein manueller Session-Key nötig")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                Task { await connect() }
            } label: {
                if isConnecting {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Verbinde...")
                    }
                } else {
                    Label("Mit Claude.ai verbinden", systemImage: "arrow.right.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)
        }
    }

    // MARK: - Actions

    @MainActor
    private func connect() async {
        isConnecting = true
        errorMessage = nil

        do {
            guard let window = NSApplication.shared.windows.first else {
                errorMessage = "Kein aktives Fenster gefunden."
                isConnecting = false
                return
            }

            let credentials = try await OAuthService().startLogin(presentationAnchor: window)
            saveCredentials(credentials)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            // User cancelled — no error shown
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }

    private func disconnect() {
        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }

        profiles[index].oauthCredentials = nil
        ProfileStore.shared.saveProfiles(profiles)
        ProfileManager.shared.updateProfile(profiles[index])
    }

    private func saveCredentials(_ creds: OAuthCredentials) {
        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }

        profiles[index].oauthCredentials = creds
        ProfileStore.shared.saveProfiles(profiles)
        ProfileManager.shared.updateProfile(profiles[index])
    }
}
```

**Step 2: Build to verify**

⌘B. Expected: Build Succeeded. Fix any import or type errors.

**Step 3: Commit**

```bash
git add "Claude Usage/Views/Settings/Credentials/OAuthCredentialsView.swift"
git commit -m "feat: add OAuthCredentialsView for connecting/disconnecting OAuth"
```

---

## Task 7: Integrate `OAuthCredentialsView` into Settings Navigation

**Files:**
- Modify: `Claude Usage/Views/SettingsView.swift` (or wherever the credentials section is rendered)

The goal: show `OAuthCredentialsView` in the credentials area — alongside the existing Claude.ai session key and CLI account views.

**Step 1: Find where credential views are shown**

In `SettingsView.swift`, find the `case .claudeAI` or `case .cliAccount` section — this is where `PersonalUsageView` and `CLIAccountView` are instantiated.

**Step 2: Add OAuth section**

Option A — if settings has a sidebar with navigation items, add a new `case .oauthLogin` to the settings enum and add a menu item. Then render `OAuthCredentialsView(profileId:)` in the detail pane.

Option B — if the Claude.ai credentials view (`PersonalUsageView`) is a full-page form, add `OAuthCredentialsView` as a section at the top or bottom of that view, above or below the session key form.

**Which to choose:** Look at how `PersonalUsageView` and `CLIAccountView` are structured. If they're separate sidebar items, add `oauthLogin` as a new sidebar case. If `PersonalUsageView` is a standalone page, add `OAuthCredentialsView` as a section inside it.

**Recommended approach (cleaner, matches design doc):**

Add to the credentials sidebar / navigation as a new top-level item alongside "Claude.ai Session Key":

```swift
// In SettingsSection enum (or equivalent):
case oauthLogin

// In the settings navigation list:
NavigationLink(value: SettingsSection.oauthLogin) {
    Label("Claude.ai OAuth", systemImage: "lock.shield")
}

// In the detail view switch:
case .oauthLogin:
    if let profileId = profileManager.activeProfile?.id {
        OAuthCredentialsView(profileId: profileId)
    }
```

**Step 3: Build to verify**

⌘B. Expected: Build Succeeded.

**Step 4: Commit**

```bash
git add "Claude Usage/Views/SettingsView.swift"
git commit -m "feat: add OAuth section to settings navigation"
```

---

## Task 8: Add `ProfileCredentials` support for OAuth (if needed)

**Files:**
- Modify: `Claude Usage/Shared/Storage/ProfileStore.swift` (if `ProfileCredentials` struct is used for loading/saving)

**Step 1: Check if `ProfileCredentials` struct exists**

Search for `struct ProfileCredentials`. If found, add `oauthCredentials` field:

```swift
struct ProfileCredentials {
    var claudeSessionKey: String?
    var organizationId: String?
    var apiSessionKey: String?
    var apiOrganizationId: String?
    var cliCredentialsJSON: String?
    var oauthCredentials: OAuthCredentials?   // ← ADD
}
```

**Step 2: Update `saveProfileCredentials` and `loadProfileCredentials`**

In `ProfileStore.saveProfileCredentials`:
```swift
profiles[index].oauthCredentials = credentials.oauthCredentials
```

In `ProfileStore.loadProfileCredentials` return initializer:
```swift
return ProfileCredentials(
    ...,
    oauthCredentials: profile.oauthCredentials
)
```

**Step 3: Build to verify**

⌘B. Expected: Build Succeeded.

**Step 4: Commit (if changes were needed)**

```bash
git add "Claude Usage/Shared/Storage/ProfileStore.swift"
git commit -m "feat: propagate oauthCredentials through ProfileCredentials"
```

---

## Task 9: End-to-End Manual Test

No unit tests are needed for the OAuth flow (it requires a real network/browser). Do a manual smoke test:

**Step 1: Build and run in Xcode**

⌘R. App launches in menu bar.

**Step 2: Open Settings → OAuth section**

Click the menu bar icon → Open Settings → Navigate to the OAuth section. Expected: "Kein manueller Session-Key nötig" + "Mit Claude.ai verbinden" button.

**Step 3: Tap "Mit Claude.ai verbinden"**

Expected: `ASWebAuthenticationSession` browser sheet opens pointing to `https://claude.ai/oauth/authorize`.

**Step 4: Log in**

Log into Claude.ai in the browser sheet. Expected: Sheet closes, status shows "Verbunden".

**Step 5: Verify usage data loads**

Wait for next refresh cycle (or trigger manual refresh). Expected: Usage data appears in menu bar from OAuth token.

**Step 6: Verify auto-refresh works (optional)**

Temporarily set `expiresAt` to `Date()` in a debug build to force refresh. Check logs for "OAuth auto-refresh" messages.

**Step 7: Verify disconnect**

Tap "Verbindung trennen". Expected: Status returns to "Kein manueller Session-Key nötig".

---

## Task 10: Final Commit and Summary

```bash
git log --oneline -10
```

Expected commits (in order):
1. `feat: add OAuthCredentials model`
2. `feat: add oauthCredentials field to Profile model`
3. `feat: add OAuthService with PKCE flow and token refresh`
4. `feat: register claudeusage:// URL scheme for OAuth callback`
5. `feat: add OAuth auto-refresh in ClaudeAPIService authentication priority`
6. `feat: add OAuthCredentialsView for connecting/disconnecting OAuth`
7. `feat: add OAuth section to settings navigation`
8. `feat: propagate oauthCredentials through ProfileCredentials` (if applicable)

---

## Known Edge Cases

- **Token refresh fails while app is in use:** Log the error, fall through to next auth method (session key or CLI). Do not crash.
- **User cancels browser sheet:** `ASWebAuthenticationSessionError.canceledLogin` — swallow silently, no error shown.
- **Refresh token expired:** Server returns error. User must reconnect manually. Show a notification or update the OAuth status to "disconnected".
- **Multiple profiles with OAuth:** Each profile stores its own `OAuthCredentials` independently. No sharing.
- **State mismatch in callback:** Throw `OAuthError.invalidCallback`. This is a security check against CSRF — do not skip it.
