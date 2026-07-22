import XCTest
@testable import dexoflux

@MainActor
final class ForumNotificationStateTests: XCTestCase {
    func testCurrentUserDecodesOfficialUnreadNotificationCounts() throws {
        let data = Data(
            #"{"current_user":{"id":7,"username":"naine","unread_notifications":3,"unread_high_priority_notifications":2,"all_unread_notifications_count":5,"seen_notification_id":40,"notification_channel_position":99}}"#.utf8
        )

        let user = try XCTUnwrap(JSONDecoder().decode(DiscourseCurrentUserResponse.self, from: data).currentUser)

        XCTAssertEqual(user.unreadNotifications, 3)
        XCTAssertEqual(user.unreadHighPriorityNotifications, 2)
        XCTAssertEqual(user.allUnreadNotificationsCount, 5)
        XCTAssertEqual(user.seenNotificationId, 40)
        XCTAssertEqual(user.notificationChannelPosition, 99)
        XCTAssertEqual(user.effectiveUnreadNotificationCount, 5)
    }

    func testMissingOfficialUnreadCountFallsBackToAvailableCounts() throws {
        let data = Data(
            #"{"current_user":{"id":7,"username":"naine","unread_notifications":3,"unread_high_priority_notifications":2}}"#.utf8
        )

        let user = try XCTUnwrap(JSONDecoder().decode(DiscourseCurrentUserResponse.self, from: data).currentUser)

        XCTAssertEqual(user.effectiveUnreadNotificationCount, 5)
    }

    func testChannelPositionChangeForcesListRefreshEvenWhenUnreadCountIsStable() {
        XCTAssertTrue(ForumNotificationRefreshPolicy.shouldFetchList(
            forceList: false,
            notificationsAreEmpty: false,
            previousUnreadCount: 3,
            officialUnreadCount: 3,
            previousChannelPosition: 20,
            currentChannelPosition: 21,
            listRefreshExpired: false
        ))
    }

    func testDeliveryStoreEstablishesBaselineThenCommitsDeliveredNotifications() throws {
        let suiteName = "ForumNotificationStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ForumNotificationDeliveryStore(defaults: defaults)

        let baseline = try decodeNotifications(idsAndReadState: [(42, false)])
        store.establishBaselineIfNeeded(
            baseline,
            baseURL: "https://linux.do/",
            username: "Naine"
        )

        let updated = try decodeNotifications(idsAndReadState: [
            (45, false),
            (44, false),
            (43, false),
            (42, false),
        ])
        let pending = store.reservePendingNotifications(
            updated,
            baseURL: "https://linux.do",
            username: "naine",
            limit: 3
        )
        XCTAssertEqual(pending.map(\.id), [43, 44, 45])
        XCTAssertTrue(store.reservePendingNotifications(
            updated,
            baseURL: "https://linux.do",
            username: "naine",
            limit: 3
        ).isEmpty)

        store.completeDeliveryAttempt(
            requested: pending,
            delivered: pending,
            baseURL: "https://linux.do",
            username: "naine"
        )
        XCTAssertTrue(store.reservePendingNotifications(
            updated,
            baseURL: "https://linux.do",
            username: "naine",
            limit: 3
        ).isEmpty)
    }

    func testFailedDeliveryReleasesReservationForNextAttempt() throws {
        let suiteName = "ForumNotificationStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ForumNotificationDeliveryStore(defaults: defaults)
        let baseline = try decodeNotifications(idsAndReadState: [(42, false)])
        store.establishBaselineIfNeeded(baseline, baseURL: "https://linux.do", username: "naine")
        let updated = try decodeNotifications(idsAndReadState: [(43, false), (42, false)])

        let firstAttempt = store.reservePendingNotifications(
            updated,
            baseURL: "https://linux.do",
            username: "naine",
            limit: 3
        )
        store.completeDeliveryAttempt(
            requested: firstAttempt,
            delivered: [],
            baseURL: "https://linux.do",
            username: "naine"
        )
        let secondAttempt = store.reservePendingNotifications(
            updated,
            baseURL: "https://linux.do",
            username: "naine",
            limit: 3
        )

        XCTAssertEqual(firstAttempt.map(\.id), [43])
        XCTAssertEqual(secondAttempt.map(\.id), [43])
    }

    func testBadgeStateReplacesAccountForSameForumAndRetainsEligibleForums() {
        var state = ForumNotificationBadgeState(unreadCountsByScope: [
            "https://linux.do|old": 2,
            "https://example.com|alice": 4,
        ])

        state.replace(3, baseURL: "https://linux.do/", username: "new")
        XCTAssertEqual(state.totalUnreadCount, 7)
        XCTAssertNil(state.unreadCountsByScope["https://linux.do|old"])
        XCTAssertEqual(state.unreadCountsByScope["https://linux.do|new"], 3)

        state.retainBaseURLs(["https://linux.do"])
        XCTAssertEqual(state.unreadCountsByScope, ["https://linux.do|new": 3])
        XCTAssertEqual(state.totalUnreadCount, 3)

        state.remove(baseURL: "https://linux.do/")
        XCTAssertTrue(state.unreadCountsByScope.isEmpty)
        XCTAssertEqual(state.totalUnreadCount, 0)
    }

    func testBackgroundAuthorizationPolicyNeverRequestsPermission() {
        XCTAssertFalse(
            ForumNotificationAuthorizationPolicy.existingOnly
                .allowsAuthorizationRequest(isApplicationActive: true)
        )
        XCTAssertFalse(
            ForumNotificationAuthorizationPolicy.requestIfNeeded
                .allowsAuthorizationRequest(isApplicationActive: false)
        )
        XCTAssertTrue(
            ForumNotificationAuthorizationPolicy.requestIfNeeded
                .allowsAuthorizationRequest(isApplicationActive: true)
        )
    }

    func testBackgroundRefreshPolicyUsesFifteenMinuteEarliestDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(
            BackgroundNotificationRefreshPolicy.earliestBeginDate(now: now),
            now.addingTimeInterval(15 * 60)
        )
        XCTAssertTrue(BackgroundNotificationRefreshPolicy.completionSuccess(
            workSucceeded: true,
            didExpire: false
        ))
        XCTAssertFalse(BackgroundNotificationRefreshPolicy.completionSuccess(
            workSucceeded: true,
            didExpire: true
        ))
        XCTAssertFalse(BackgroundNotificationRefreshPolicy.completionSuccess(
            workSucceeded: false,
            didExpire: false
        ))
    }

    func testBackgroundSyncResultOnlyFailsTaskForTransientErrorsOrCancellation() {
        let authenticationFailure = BackgroundNotificationSyncFailure(
            baseURL: "https://linux.do",
            kind: .authentication,
            message: "expired"
        )
        let transientFailure = BackgroundNotificationSyncFailure(
            baseURL: "https://linux.do",
            kind: .transient,
            message: "offline"
        )

        XCTAssertTrue(BackgroundNotificationSyncResult(
            eligibleBaseURLs: ["https://linux.do"],
            snapshots: [],
            failures: [authenticationFailure],
            wasCancelled: false
        ).taskSucceeded)
        XCTAssertFalse(BackgroundNotificationSyncResult(
            eligibleBaseURLs: ["https://linux.do"],
            snapshots: [],
            failures: [transientFailure],
            wasCancelled: false
        ).taskSucceeded)
        XCTAssertFalse(BackgroundNotificationSyncResult(
            eligibleBaseURLs: [],
            snapshots: [],
            failures: [],
            wasCancelled: true
        ).taskSucceeded)
    }

    func testOnlyNotificationAuthenticationFailureClearsBadge() {
        let notificationFailure = BackgroundNotificationSyncFailure(
            baseURL: "https://linux.do",
            kind: .authentication,
            scope: .notifications,
            message: "expired"
        )
        let topicFailure = BackgroundNotificationSyncFailure(
            baseURL: "https://linux.do",
            kind: .authentication,
            scope: .topics,
            message: "forbidden"
        )

        XCTAssertTrue(notificationFailure.shouldClearBadge)
        XCTAssertFalse(topicFailure.shouldClearBadge)
    }

    func testBackgroundAPIContextDisablesInteractiveWebRecovery() {
        XCTAssertTrue(DiscourseAPIExecutionContext.foreground.allowsInteractiveWebRecovery)
        XCTAssertFalse(DiscourseAPIExecutionContext.backgroundRefresh.allowsInteractiveWebRecovery)
    }

    func testNotificationRouteMatchesForumUsingNormalizedBaseURL() throws {
        let linuxDo = ForumInstance.new(title: "Linux.do", baseURL: "https://linux.do/")
        let example = ForumInstance.new(title: "Example", baseURL: "https://example.com")

        let matched = try XCTUnwrap(ForumNotificationRoutePresenter.matchingForum(
            baseURL: "HTTPS://LINUX.DO",
            forums: [example, linuxDo]
        ))

        XCTAssertEqual(matched.title, "Linux.do")
    }

    func testNotificationRouteDoesNotOpenUnknownForum() {
        let forums = [ForumInstance.new(title: "Linux.do", baseURL: "https://linux.do")]

        XCTAssertNil(ForumNotificationRoutePresenter.matchingForum(
            baseURL: "https://unknown.example",
            forums: forums
        ))
    }

    private func decodeNotifications(idsAndReadState: [(Int, Bool)]) throws -> [DiscourseNotification] {
        let entries = idsAndReadState.map { id, read in
            """
            {
              "id": \(id),
              "notification_type": 2,
              "read": \(read),
              "high_priority": false,
              "created_at": "2026-07-19T00:00:00.000Z",
              "topic_id": 17,
              "data": {"topic_title": "Topic \(id)", "username": "alice"}
            }
            """
        }.joined(separator: ",")
        let data = Data("{\"notifications\":[\(entries)]}".utf8)
        return try JSONDecoder().decode(DiscourseNotificationList.self, from: data).notifications
    }
}
