# Design: OAuth Login mit ASWebAuthenticationSession

**Datum:** 2026-02-25
**Ansatz:** Option A – `ASWebAuthenticationSession` (Apple-nativer OAuth-Flow)

## Ziel

Session-Keys müssen nicht mehr manuell aus dem Browser kopiert werden. Pro Profil kann der User sich einmalig mit Claude.ai verbinden. Die App holt sich dann automatisch neue Access-Tokens via Refresh-Token – ohne weiteren User-Eingriff.

## Bekannte OAuth-Endpunkte (aus Claude Code CLI extrahiert)

| Parameter | Wert |
|-----------|------|
| Authorization URL | `https://claude.ai/oauth/authorize` |
| Token URL | `https://claude.ai/v1/oauth/token` |
| Client ID | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |
| Redirect URI | `claudeusage://oauth/callback` |
| Scopes | `user:inference user:profile` |
| PKCE | `S256` |

## Abschnitt 1: Datenmodel & Speicherung

### Neues Model `OAuthCredentials`

```swift
struct OAuthCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String?  // für Anzeige im UI

    var isExpired: Bool { Date() >= expiresAt }
    var expiresInFiveMinutes: Bool { Date() >= expiresAt.addingTimeInterval(-300) }
}
```

### `Profile.swift` Erweiterung

```swift
var oauthCredentials: OAuthCredentials?
```

### Authentifizierungs-Priorität in `ClaudeAPIService`

```
1. claudeSessionKey      (bestehend – falls manuell gesetzt)
2. oauthCredentials      (NEU – mit Auto-Refresh)
3. CLI OAuth (Keychain)  (bestehender Fallback)
```

## Abschnitt 2: OAuth Flow & Token-Refresh

### Login-Flow (einmalig pro Profil)

1. User klickt **"Mit Claude.ai verbinden"** in den Profil-Einstellungen
2. `OAuthService.startLogin()` generiert PKCE `code_verifier` + `code_challenge` (SHA256)
3. `ASWebAuthenticationSession` öffnet sich mit Authorization URL:
   ```
   https://claude.ai/oauth/authorize
     ?client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e
     &redirect_uri=claudeusage://oauth/callback
     &response_type=code
     &scope=user:inference%20user:profile
     &code_challenge=<SHA256(verifier)>
     &code_challenge_method=S256
     &state=<random>
   ```
4. User loggt sich im Browser-Sheet ein
5. Redirect zu `claudeusage://oauth/callback?code=...&state=...`
6. `OAuthService` tauscht Code gegen Tokens (POST `/v1/oauth/token`):
   ```json
   { "grant_type": "authorization_code", "code": "...",
     "redirect_uri": "claudeusage://oauth/callback",
     "client_id": "9d1c250a...", "code_verifier": "..." }
   ```
7. Response: `{ "access_token": "...", "refresh_token": "...", "expires_in": 3600 }`
8. `OAuthCredentials` wird im Profil gespeichert

### Auto-Refresh (unsichtbar)

Vor jedem API-Call in `ClaudeAPIService.getAuthentication()`:
- Falls `oauthCredentials.expiresInFiveMinutes == true` → Token-Refresh
- POST `/v1/oauth/token` mit `grant_type=refresh_token`
- Neue `accessToken` + `expiresAt` speichern
- `refreshToken` bleibt unverändert (bis Server ihn rotiert)

## Abschnitt 3: Neue Dateien & UI-Änderungen

### Neue Dateien

| Datei | Zweck |
|-------|-------|
| `OAuthService.swift` | PKCE, `ASWebAuthenticationSession`, Token-Exchange, Token-Refresh |
| `OAuthCredentials.swift` | Model (accessToken, refreshToken, expiresAt, email) |

### Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `Profile.swift` | Neues Feld `oauthCredentials: OAuthCredentials?` |
| `ClaudeAPIService.swift` | Priorität 2 + Auto-Refresh vor API-Calls |
| `PersonalUsageView.swift` | Neuer "Mit Claude.ai verbinden" Button + Status-Anzeige |
| `Info.plist` | URL Scheme `claudeusage` registrieren |

### UI-Mockup (Credentials-Bereich)

```
Verbunden:
┌─────────────────────────────────────┐
│ Claude.ai OAuth                     │
│ ● Verbunden als jochenwahl@...      │
│ [Verbindung trennen]                │
└─────────────────────────────────────┘

Nicht verbunden:
┌─────────────────────────────────────┐
│ Claude.ai OAuth                     │
│ Kein manueller Session-Key nötig    │
│ [Mit Claude.ai verbinden]           │
└─────────────────────────────────────┘
```

## Nicht im Scope

- Kein Token-Sharing zwischen Profilen
- Kein automatischer Re-Login wenn Refresh-Token abläuft (User muss dann erneut verbinden)
- Session-Key bleibt weiterhin als Alternative erhalten
