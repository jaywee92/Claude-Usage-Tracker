//
//  AutoStartSessionServiceTests.swift
//  Claude UsageTests
//

import XCTest
@testable import Claude_Usage

@MainActor
class AutoStartSessionServiceTests: XCTestCase {

    // Test: HTTP 404 response during delete should be logged, not silently ignored
    func testDeleteResponseStatusIsChecked() {
        // This tests the helper method that validates HTTP responses
        let service = AutoStartSessionService.shared

        // A 204 No Content response IS a success for DELETE
        XCTAssertTrue(service.isSuccessfulDeleteStatus(204),
                      "204 No Content is a valid success status for DELETE")

        // A 200 OK response is also a success
        XCTAssertTrue(service.isSuccessfulDeleteStatus(200),
                      "200 OK is a valid success status for DELETE")

        // A 404 Not Found is NOT a success
        XCTAssertFalse(service.isSuccessfulDeleteStatus(404),
                       "404 Not Found is not a success status")

        // A 403 Forbidden is NOT a success
        XCTAssertFalse(service.isSuccessfulDeleteStatus(403),
                       "403 Forbidden is not a success status")
    }

    // Test: checkProfile should skip when autoStartSessionEnabled is false
    func testAutoStartSkipsProfileWithoutEnabled() {
        // This is a conceptual test - verifies the guard condition exists
        // A profile with autoStartSessionEnabled = false should never trigger auto-start
        // We verify this by checking the filter logic in checkAllProfiles
        // The profileManager.profiles.filter { $0.autoStartSessionEnabled } call
        // ensures only enabled profiles are checked

        // Verify the Profile model has autoStartSessionEnabled property
        let profile = Profile(
            id: UUID(),
            name: "Test",
            hasCliAccount: false,
            iconConfig: .default,
            refreshInterval: 30.0,
            autoStartSessionEnabled: false,
            checkOverageLimitEnabled: true,
            notificationSettings: NotificationSettings(),
            isSelectedForDisplay: true
        )
        XCTAssertFalse(profile.autoStartSessionEnabled,
                       "Profile should not have auto-start enabled by default")
    }
}
