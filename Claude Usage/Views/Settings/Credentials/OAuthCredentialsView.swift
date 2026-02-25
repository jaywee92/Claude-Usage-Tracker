//
//  OAuthCredentialsView.swift
//  Claude Usage
//

import SwiftUI
import AuthenticationServices

struct OAuthCredentialsView: View {
    let profileId: UUID

    @StateObject private var profileManager = ProfileManager.shared

    // Flow state
    private enum FlowStep {
        case idle           // Not connected, show "Connect" button
        case waitingForCode // Browser opened, waiting for user to paste code
        case exchanging     // Exchanging code for token
        case connected      // Successfully connected
    }

    @State private var step: FlowStep = .idle
    @State private var authURL: URL?
    @State private var pkceVerifier: String?
    @State private var codeInput: String = ""
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

            if oauthCreds != nil {
                connectedView
            } else {
                switch step {
                case .idle:
                    notConnectedView
                case .waitingForCode:
                    codeInputView
                case .exchanging:
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Token wird ausgetauscht...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                case .connected:
                    // Will flip to connectedView once profile reloads
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Verbunden")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
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

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Verbunden")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
            Text("Einmalig mit Claude.ai verbinden — kein manueller Session-Key nötig.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                openBrowser()
            } label: {
                Label("Mit Claude.ai verbinden", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Code Input View (step 2)

    private var codeInputView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude.ai wurde im Browser geöffnet. Melde dich an und kopiere den angezeigten Code:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("Code einfügen", text: $codeInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button("Bestätigen") {
                    Task { await submitCode() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 12) {
                Button("Browser erneut öffnen") {
                    openBrowser()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Button("Abbrechen") {
                    step = .idle
                    codeInput = ""
                    errorMessage = nil
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
            }
        }
    }

    // MARK: - Actions

    private func openBrowser() {
        errorMessage = nil
        codeInput = ""

        do {
            let (url, verifier) = try OAuthService().buildAuthorizationURL()
            authURL = url
            pkceVerifier = verifier
            step = .waitingForCode
            NSWorkspace.shared.open(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submitCode() async {
        guard let verifier = pkceVerifier else { return }
        let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        step = .exchanging
        errorMessage = nil

        do {
            let credentials = try await OAuthService().exchangeCode(code, verifier: verifier)
            saveCredentials(credentials)
            step = .connected
            codeInput = ""
        } catch {
            errorMessage = error.localizedDescription
            step = .waitingForCode
        }
    }

    private func disconnect() {
        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].oauthCredentials = nil
        ProfileStore.shared.saveProfiles(profiles)
        ProfileManager.shared.updateProfile(profiles[index])
        step = .idle
    }

    private func saveCredentials(_ creds: OAuthCredentials) {
        var profiles = ProfileStore.shared.loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].oauthCredentials = creds
        ProfileStore.shared.saveProfiles(profiles)
        ProfileManager.shared.updateProfile(profiles[index])
    }
}
