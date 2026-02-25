//
//  ClaudeCodeSyncServiceTests.swift
//  Claude UsageTests
//

import XCTest
@testable import Claude_Usage

class ClaudeCodeSyncServiceTests: XCTestCase {

    // Test: extractServiceName finds service name WITH hash suffix
    func testExtractServiceNameWithHashSuffix() {
        let service = ClaudeCodeSyncService.shared

        let mockOutput = """
        keychain: "/Users/test/Library/Keychains/login.keychain-db"
        class: "genp"
        attributes:
            "svce"<blob>="Claude Code-credentials-0f61c92a"
            "acct"<blob>="testuser"
        """

        let serviceName = service.extractServiceName(from: mockOutput)
        XCTAssertEqual(serviceName, "Claude Code-credentials-0f61c92a",
                       "Should find service name WITH hash suffix")
    }

    // Test: extractServiceName finds service name WITHOUT hash suffix (backwards compat)
    func testExtractServiceNameWithoutHashSuffix() {
        let service = ClaudeCodeSyncService.shared

        let mockOutput = """
        keychain: "/Users/test/Library/Keychains/login.keychain-db"
        class: "genp"
        attributes:
            "svce"<blob>="Claude Code-credentials"
            "acct"<blob>="testuser"
        """

        let serviceName = service.extractServiceName(from: mockOutput)
        XCTAssertEqual(serviceName, "Claude Code-credentials",
                       "Should find service name WITHOUT hash suffix (backwards compat)")
    }

    // Test: extractServiceName returns nil when no matching entry found
    func testExtractServiceNameReturnsNilWhenNotFound() {
        let service = ClaudeCodeSyncService.shared

        let mockOutput = """
        keychain: "/Users/test/Library/Keychains/login.keychain-db"
        class: "genp"
        attributes:
            "svce"<blob>="SomeOtherApp-credentials"
            "acct"<blob>="testuser"
        """

        let serviceName = service.extractServiceName(from: mockOutput)
        XCTAssertNil(serviceName, "Should return nil when no Claude Code credentials found")
    }

    // MARK: - isTokenExpired / extractTokenExpiry Tests

    private func makeCredentialsJSON(expiresAt: Double) -> String {
        """
        {"claudeAiOauth":{"accessToken":"tok","refreshToken":"ref","expiresAt":\(expiresAt),"tokenType":"Bearer","subscriptionType":"claude_pro","scopes":[]}}
        """
    }

    // Test: millisecond timestamp (Claude CLI format) that is expired
    func testIsTokenExpired_MillisecondsExpired() {
        let service = ClaudeCodeSyncService.shared
        // 1 day ago in milliseconds
        let expiredMs = (Date().timeIntervalSince1970 - 86400) * 1000
        let json = makeCredentialsJSON(expiresAt: expiredMs)
        XCTAssertTrue(service.isTokenExpired(json),
                      "Token with ms expiry in the past should be expired")
    }

    // Test: millisecond timestamp that is NOT yet expired
    func testIsTokenExpired_MillisecondsValid() {
        let service = ClaudeCodeSyncService.shared
        // 1 hour from now in milliseconds
        let futureMs = (Date().timeIntervalSince1970 + 3600) * 1000
        let json = makeCredentialsJSON(expiresAt: futureMs)
        XCTAssertFalse(service.isTokenExpired(json),
                       "Token with ms expiry in the future should NOT be expired")
    }

    // Test: second timestamp (legacy format) that is expired
    func testIsTokenExpired_SecondsExpired() {
        let service = ClaudeCodeSyncService.shared
        // 1 day ago in seconds
        let expiredSec = Date().timeIntervalSince1970 - 86400
        let json = makeCredentialsJSON(expiresAt: expiredSec)
        XCTAssertTrue(service.isTokenExpired(json),
                      "Token with second expiry in the past should be expired")
    }

    // Test: missing expiresAt field → assume valid (returns false)
    func testIsTokenExpired_MissingExpiry() {
        let service = ClaudeCodeSyncService.shared
        let json = """
        {"claudeAiOauth":{"accessToken":"tok","tokenType":"Bearer"}}
        """
        XCTAssertFalse(service.isTokenExpired(json),
                       "Token with no expiry field should be assumed valid")
    }

    // Test: extractServiceName handles multi-line output with multiple entries
    func testExtractServiceNameFromMultipleEntries() {
        let service = ClaudeCodeSyncService.shared

        let mockOutput = """
        keychain: "/Users/test/Library/Keychains/login.keychain-db"
        class: "genp"
        attributes:
            "svce"<blob>="SomeOtherApp"
            "acct"<blob>="testuser"
        keychain: "/Users/test/Library/Keychains/login.keychain-db"
        class: "genp"
        attributes:
            "svce"<blob>="Claude Code-credentials-abc12345"
            "acct"<blob>="testuser2"
        """

        let serviceName = service.extractServiceName(from: mockOutput)
        XCTAssertEqual(serviceName, "Claude Code-credentials-abc12345",
                       "Should find Claude Code entry among multiple keychain entries")
    }
}
