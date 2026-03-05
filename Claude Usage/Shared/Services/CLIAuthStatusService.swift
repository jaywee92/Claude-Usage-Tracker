//
//  CLIAuthStatusService.swift
//  Claude Usage
//

import Foundation
import Security

struct CLIAuthStatus {
    let email: String
    let orgId: String
    let subscriptionType: String
}

struct CLICredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

actor CLIAuthStatusService {
    static let shared = CLIAuthStatusService()

    private init() {}

    /// Reads the Claude CLI's OAuth credentials from the system keychain.
    /// The CLI stores them under the service name "Claude Code-credentials".
    func readCLICredentials() -> CLICredentials? {
        guard let jsonString = readKeychainPassword(service: "Claude Code-credentials"),
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthDict = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauthDict["accessToken"] as? String else {
            return nil
        }
        let refreshToken = oauthDict["refreshToken"] as? String
        var expiresAt: Date? = nil
        if let expiresMs = oauthDict["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresMs / 1000.0)
        }
        return CLICredentials(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    private func readKeychainPassword(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Runs `claude auth status --json` and returns parsed result, or nil if not logged in / binary not found.
    func fetchStatus() async -> CLIAuthStatus? {
        guard let claudePath = findClaudeBinary() else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["auth", "status", "--json"]
        process.environment = ProcessInfo.processInfo.environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Run with a 5-second timeout
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            let timer = DispatchWorkItem {
                if process.isRunning { process.terminate() }
                continuation.resume(returning: nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timer)

            process.terminationHandler = { _ in
                timer.cancel()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }

        guard let data = result,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = json["loggedIn"] as? Bool, loggedIn,
              let email = json["email"] as? String,
              let orgId = json["orgId"] as? String else {
            return nil
        }

        return CLIAuthStatus(
            email: email,
            orgId: orgId,
            subscriptionType: json["subscriptionType"] as? String ?? "unknown"
        )
    }

    private func findClaudeBinary() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.nvm/versions/node/current/bin/claude",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
