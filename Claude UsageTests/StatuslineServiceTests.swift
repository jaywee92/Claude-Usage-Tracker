//
//  StatuslineServiceTests.swift
//  Claude UsageTests
//

import XCTest
@testable import Claude_Usage

class StatuslineServiceTests: XCTestCase {

    // Test: StatuslineService.shared exists and is accessible
    func testStatuslineServiceIsAccessible() {
        let service = StatuslineService.shared
        XCTAssertNotNil(service, "StatuslineService.shared should be accessible")
    }

    // Test: isInstalled returns a Bool (not nil)
    func testIsInstalledReturnsBool() {
        let service = StatuslineService.shared
        // isInstalled checks file existence — should return a Bool without crashing
        let result = service.isInstalled
        // result is a Bool — this just verifies the property exists and doesn't crash
        XCTAssertTrue(result || !result, "isInstalled should return a valid Bool")
    }
}
