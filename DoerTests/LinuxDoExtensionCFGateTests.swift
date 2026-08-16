import XCTest
@testable import Doer

final class LinuxDoExtensionCFGateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LinuxDoExtensionCFGate.resetForTesting()
    }

    override func tearDown() {
        LinuxDoExtensionCFGate.resetForTesting()
        super.tearDown()
    }

    func testCDKUserInfoWaitsTenMinutes() throws {
        let url = try XCTUnwrap(URL(string: "https://cdk.linux.do/api/v1/oauth/user-info"))
        let now = Date()
        LinuxDoExtensionCFGate.markUserInfoAttempt(for: url, now: now)

        XCTAssertTrue(LinuxDoExtensionCFGate.shouldSkipUserInfoRefresh(for: url, now: now.addingTimeInterval(9 * 60)))
        XCTAssertFalse(LinuxDoExtensionCFGate.shouldSkipUserInfoRefresh(for: url, now: now.addingTimeInterval(10 * 60)))
    }

    func testLDCUserInfoKeepsShorterInterval() throws {
        let url = try XCTUnwrap(URL(string: "https://credit.linux.do/api/v1/oauth/user-info"))
        let now = Date()
        LinuxDoExtensionCFGate.markUserInfoAttempt(for: url, now: now)

        XCTAssertTrue(LinuxDoExtensionCFGate.shouldSkipUserInfoRefresh(for: url, now: now.addingTimeInterval(30)))
        XCTAssertFalse(LinuxDoExtensionCFGate.shouldSkipUserInfoRefresh(for: url, now: now.addingTimeInterval(45)))
    }

    func testCDKChallengeCooldownLastsTenMinutes() throws {
        let url = try XCTUnwrap(URL(string: "https://cdk.linux.do/api/v1/oauth/user-info"))
        let now = Date()
        LinuxDoExtensionCFGate.markChallenged(for: url, now: now)

        XCTAssertTrue(LinuxDoExtensionCFGate.isInChallengeCooldown(for: url, now: now.addingTimeInterval(9 * 60)))
        XCTAssertFalse(LinuxDoExtensionCFGate.isInChallengeCooldown(for: url, now: now.addingTimeInterval(10 * 60)))
    }
}
