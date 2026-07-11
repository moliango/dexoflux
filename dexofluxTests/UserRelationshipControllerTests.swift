import XCTest
@testable import dexoflux

@MainActor
final class UserRelationshipControllerTests: XCTestCase {
    func testFollowSuccessUpdatesStateAndCallsService() async throws {
        let service = FakeUserRelationshipService()
        let controller = UserRelationshipController(username: "sam", service: service)
        controller.apply(profile: try profile(isFollowed: false))

        await controller.perform(.toggleFollow)

        XCTAssertTrue(controller.state.isFollowed)
        XCTAssertFalse(controller.state.isMutating)
        XCTAssertEqual(service.operations, [.follow("sam")])
    }

    func testFollowFailureRollsBackStateAndExposesError() async throws {
        let service = FakeUserRelationshipService()
        service.error = TestError.failed
        let controller = UserRelationshipController(username: "sam", service: service)
        controller.apply(profile: try profile(isFollowed: false))

        await controller.perform(.toggleFollow)

        XCTAssertFalse(controller.state.isFollowed)
        XCTAssertFalse(controller.state.isMutating)
        XCTAssertNotNil(controller.state.errorMessage)
    }

    func testMuteIgnoreAndRestoreUseNotificationLevels() async throws {
        let service = FakeUserRelationshipService()
        let controller = UserRelationshipController(username: "sam", service: service)
        controller.apply(profile: try profile(isFollowed: false))
        let expiry = Date(timeIntervalSince1970: 1234)

        await controller.perform(.mute)
        XCTAssertTrue(controller.state.isMuted)
        XCTAssertFalse(controller.state.isIgnored)

        await controller.perform(.ignore(until: expiry))
        XCTAssertFalse(controller.state.isMuted)
        XCTAssertTrue(controller.state.isIgnored)

        await controller.perform(.restore)
        XCTAssertFalse(controller.state.isMuted)
        XCTAssertFalse(controller.state.isIgnored)
        XCTAssertEqual(
            service.operations,
            [.level("sam", "mute", nil), .level("sam", "ignore", expiry), .level("sam", "normal", nil)]
        )
    }

    func testDeniedFollowCapabilityDoesNotCallService() async throws {
        let service = FakeUserRelationshipService()
        let controller = UserRelationshipController(username: "sam", service: service)
        controller.apply(profile: try profile(isFollowed: false, canFollow: false))

        await controller.perform(.toggleFollow)

        XCTAssertFalse(controller.state.isFollowed)
        XCTAssertTrue(service.operations.isEmpty)
    }

    private func profile(isFollowed: Bool, canFollow: Bool = true) throws -> DiscourseUserProfile {
        let data = Data(#"{"user":{"id":1,"username":"sam","trust_level":2,"is_followed":\#(isFollowed),"can_follow":\#(canFollow),"can_mute_user":true,"can_ignore_user":true}}"#.utf8)
        return try JSONDecoder().decode(DiscourseUserProfileResponse.self, from: data).user
    }
}

@MainActor
private final class FakeUserRelationshipService: UserRelationshipServicing {
    enum Operation: Equatable {
        case follow(String)
        case unfollow(String)
        case level(String, String, Date?)
    }

    var operations: [Operation] = []
    var error: Error?

    func followUser(username: String) async throws {
        operations.append(.follow(username))
        if let error { throw error }
    }

    func unfollowUser(username: String) async throws {
        operations.append(.unfollow(username))
        if let error { throw error }
    }

    func updateUserNotificationLevel(username: String, level: String, expiringAt: Date?) async throws {
        operations.append(.level(username, level, expiringAt))
        if let error { throw error }
    }
}

private enum TestError: Error {
    case failed
}
