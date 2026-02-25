//
//  ProfileManagerTests.swift
//  Claude UsageTests
//

import XCTest
@testable import Claude_Usage

class ProfileManagerTests: XCTestCase {

    // Test: isDataStale returns true for data from yesterday
    func testIsDataStaleReturnsTrueForYesterdayData() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let staleUsage = ClaudeUsage(
            sessionTokensUsed: 0,
            sessionLimit: 0,
            sessionPercentage: 50,
            sessionResetTime: Date(),
            weeklyTokensUsed: 0,
            weeklyLimit: 1_000_000,
            weeklyPercentage: 0,
            weeklyResetTime: Date(),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: yesterday,  // From yesterday!
            userTimezone: .current
        )

        XCTAssertTrue(ClaudeUsage.isStale(staleUsage),
                      "Data from yesterday should be considered stale")
    }

    // Test: isDataStale returns false for data from today
    func testIsDataStaleReturnsFalseForTodayData() {
        let freshUsage = ClaudeUsage(
            sessionTokensUsed: 0,
            sessionLimit: 0,
            sessionPercentage: 50,
            sessionResetTime: Date(),
            weeklyTokensUsed: 0,
            weeklyLimit: 1_000_000,
            weeklyPercentage: 0,
            weeklyResetTime: Date(),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),  // Now (today)
            userTimezone: .current
        )

        XCTAssertFalse(ClaudeUsage.isStale(freshUsage),
                       "Data from today should NOT be considered stale")
    }

    // Test: nil usage is considered stale (no data = needs refresh)
    func testNilUsageIsConsideredStale() {
        XCTAssertTrue(ClaudeUsage.isStale(nil),
                      "nil usage (no data) should be considered stale")
    }

    // Test: Data from 2 minutes ago today is NOT stale
    func testRecentDataIsNotStale() {
        let twoMinutesAgo = Date().addingTimeInterval(-120)

        let recentUsage = ClaudeUsage(
            sessionTokensUsed: 0,
            sessionLimit: 0,
            sessionPercentage: 30,
            sessionResetTime: Date(),
            weeklyTokensUsed: 0,
            weeklyLimit: 1_000_000,
            weeklyPercentage: 0,
            weeklyResetTime: Date(),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: twoMinutesAgo,
            userTimezone: .current
        )

        XCTAssertFalse(ClaudeUsage.isStale(recentUsage),
                       "Data from 2 minutes ago (today) should NOT be stale")
    }
}
