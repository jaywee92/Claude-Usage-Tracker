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
