import XCTest
@testable import Doer

final class PollResultsPolicyTests: XCTestCase {
    func testHidesCountsBeforeVotingOnOpenPoll() {
        XCTAssertFalse(
            PollResultsPolicy.shouldShowResults(resultsMode: "on_vote", status: "open", hasVoted: false)
        )
        XCTAssertFalse(
            PollResultsPolicy.shouldShowResults(resultsMode: nil, status: "open", hasVoted: false)
        )
        XCTAssertFalse(
            PollResultsPolicy.shouldShowResults(resultsMode: "always", status: "open", hasVoted: false)
        )
    }

    func testShowsCountsAfterVotingOrClose() {
        XCTAssertTrue(
            PollResultsPolicy.shouldShowResults(resultsMode: "on_vote", status: "open", hasVoted: true)
        )
        XCTAssertTrue(
            PollResultsPolicy.shouldShowResults(resultsMode: nil, status: "closed", hasVoted: false)
        )
    }

    func testOnCloseWaitsUntilClosed() {
        XCTAssertFalse(
            PollResultsPolicy.shouldShowResults(resultsMode: "on_close", status: "open", hasVoted: true)
        )
        XCTAssertTrue(
            PollResultsPolicy.shouldShowResults(resultsMode: "on_close", status: "closed", hasVoted: false)
        )
    }

    func testStaffOnlyNeverRevealsInApp() {
        XCTAssertFalse(
            PollResultsPolicy.shouldShowResults(resultsMode: "staff_only", status: "open", hasVoted: true)
        )
        XCTAssertFalse(
            PollResultsPolicy.shouldShowResults(resultsMode: "staff_only", status: "closed", hasVoted: true)
        )
    }

    func testAlwaysAllowsPeekToggleBeforeVoting() {
        XCTAssertTrue(
            PollResultsPolicy.canToggleResults(resultsMode: "always", status: "open", hasVoted: false)
        )
        XCTAssertFalse(
            PollResultsPolicy.canToggleResults(resultsMode: "on_vote", status: "open", hasVoted: false)
        )
        XCTAssertTrue(
            PollResultsPolicy.canToggleResults(resultsMode: "on_vote", status: "open", hasVoted: true)
        )
        XCTAssertFalse(
            PollResultsPolicy.canToggleResults(resultsMode: "always", status: "closed", hasVoted: false)
        )
    }
}
