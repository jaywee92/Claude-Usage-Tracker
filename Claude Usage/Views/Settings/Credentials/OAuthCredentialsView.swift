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
                connectedView(creds: creds)
            } else {
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
            guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow })
                               ?? NSApplication.shared.windows.first else {
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
