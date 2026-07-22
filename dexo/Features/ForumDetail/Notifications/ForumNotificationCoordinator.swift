import Foundation
import UIKit
import UserNotifications

enum ForumNotificationRefreshPolicy {
    static func shouldFetchList(
        forceList: Bool,
        notificationsAreEmpty: Bool,
        previousUnreadCount: Int,
        officialUnreadCount: Int?,
        previousChannelPosition: Int?,
        currentChannelPosition: Int?,
        listRefreshExpired: Bool
    ) -> Bool {
        let channelPositionChanged = previousChannelPosition != nil
            && currentChannelPosition != nil
            && previousChannelPosition != currentChannelPosition
        return forceList
            || notificationsAreEmpty
            || officialUnreadCount != previousUnreadCount
            || channelPositionChanged
            || listRefreshExpired
    }
}

enum ForumNotificationAuthorizationPolicy {
    case requestIfNeeded
    case existingOnly

    func allowsAuthorizationRequest(isApplicationActive: Bool) -> Bool {
        switch self {
        case .requestIfNeeded:
            return isApplicationActive
        case .existingOnly:
            return false
        }
    }
}

struct ForumNotificationBadgeState: Equatable {
    private(set) var unreadCountsByScope: [String: Int]

    init(unreadCountsByScope: [String: Int] = [:]) {
        self.unreadCountsByScope = unreadCountsByScope.filter { $0.value > 0 }
    }

    var totalUnreadCount: Int {
        unreadCountsByScope.values.reduce(0, +)
    }

    mutating func update(_ unreadCount: Int, scope: String) {
        if unreadCount > 0 {
            unreadCountsByScope[scope] = unreadCount
        } else {
            unreadCountsByScope.removeValue(forKey: scope)
        }
    }

    mutating func replace(_ unreadCount: Int, baseURL: String, username: String) {
        let prefix = "\(Self.normalizedBaseURL(baseURL))|"
        unreadCountsByScope = unreadCountsByScope.filter { !$0.key.hasPrefix(prefix) }
        update(unreadCount, scope: Self.scope(baseURL: baseURL, username: username))
    }

    mutating func retainBaseURLs(_ baseURLs: Set<String>) {
        let normalizedBaseURLs = Set(baseURLs.map(Self.normalizedBaseURL))
        unreadCountsByScope = unreadCountsByScope.filter { scope, _ in
            normalizedBaseURLs.contains(Self.baseURL(fromScope: scope))
        }
    }

    mutating func remove(baseURL: String) {
        let prefix = "\(Self.normalizedBaseURL(baseURL))|"
        unreadCountsByScope = unreadCountsByScope.filter { !$0.key.hasPrefix(prefix) }
    }

    static func scope(baseURL: String, username: String) -> String {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedBaseURL(baseURL))|\(normalizedUsername)"
    }

    private static func baseURL(fromScope scope: String) -> String {
        guard let separator = scope.lastIndex(of: "|") else { return scope }
        return String(scope[..<separator])
    }

    private nonisolated static func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}

@MainActor
final class ForumNotificationDeliveryStore {
    static let shared = ForumNotificationDeliveryStore()

    private let defaults: UserDefaults
    private var reservedNotificationIdsByKey: [String: Set<Int>] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func establishBaselineIfNeeded(
        _ notifications: [DiscourseNotification],
        baseURL: String,
        username: String
    ) {
        let key = cursorKey(baseURL: baseURL, username: username)
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(notifications.map(\.id).max() ?? 0, forKey: key)
    }

    func reservePendingNotifications(
        _ notifications: [DiscourseNotification],
        baseURL: String,
        username: String,
        limit: Int
    ) -> [DiscourseNotification] {
        let key = cursorKey(baseURL: baseURL, username: username)
        guard let storedId = (defaults.object(forKey: key) as? NSNumber)?.intValue else {
            establishBaselineIfNeeded(notifications, baseURL: baseURL, username: username)
            return []
        }
        guard reservedNotificationIdsByKey[key]?.isEmpty != false else { return [] }
        let reservedIds = reservedNotificationIdsByKey[key] ?? []
        let candidates = notifications
            .filter { !$0.read && $0.id > storedId && !reservedIds.contains($0.id) }
            .sorted { $0.id < $1.id }
            .suffix(max(limit, 0))
        let reserved = Array(candidates)
        reservedNotificationIdsByKey[key, default: []].formUnion(reserved.map(\.id))
        return reserved
    }

    func completeDeliveryAttempt(
        requested: [DiscourseNotification],
        delivered: [DiscourseNotification],
        baseURL: String,
        username: String
    ) {
        let key = cursorKey(baseURL: baseURL, username: username)
        reservedNotificationIdsByKey[key]?.subtract(requested.map(\.id))
        if reservedNotificationIdsByKey[key]?.isEmpty == true {
            reservedNotificationIdsByKey.removeValue(forKey: key)
        }
        guard let newestDeliveredId = delivered.map(\.id).max() else { return }
        let storedId = (defaults.object(forKey: key) as? NSNumber)?.intValue ?? 0
        defaults.set(max(storedId, newestDeliveredId), forKey: key)
    }

    func cursorKey(baseURL: String, username: String) -> String {
        let normalizedBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "dexoflux.notification.lastSeen.\(normalizedBaseURL).\(normalizedUsername)"
    }
}

@MainActor
protocol ForumLocalNotificationPresenting: AnyObject {
    func updateApplicationBadge(_ unreadCount: Int, scope: String)
    func replaceApplicationBadge(_ unreadCount: Int, baseURL: String, username: String)
    func retainApplicationBadgeBaseURLs(_ baseURLs: Set<String>)
    func removeApplicationBadge(baseURL: String)
    func deliver(
        notifications: [DiscourseNotification],
        baseURL: String,
        authorizationPolicy: ForumNotificationAuthorizationPolicy
    ) async -> [DiscourseNotification]
}

@MainActor
final class ForumLocalNotificationPresenter: ForumLocalNotificationPresenting {
    static let shared = ForumLocalNotificationPresenter()

    private static let badgeStateKey = "dexoflux.notification.badgeCountsByScope"
    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private var badgeState: ForumNotificationBadgeState

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.badgeStateKey) ?? [:]
        let counts = stored.reduce(into: [String: Int]()) { result, entry in
            if let value = entry.value as? NSNumber, value.intValue > 0 {
                result[entry.key] = value.intValue
            }
        }
        self.badgeState = ForumNotificationBadgeState(unreadCountsByScope: counts)
    }

    func updateApplicationBadge(_ unreadCount: Int, scope: String) {
        badgeState.update(unreadCount, scope: scope)
        persistAndApplyBadgeState()
    }

    func replaceApplicationBadge(_ unreadCount: Int, baseURL: String, username: String) {
        badgeState.replace(unreadCount, baseURL: baseURL, username: username)
        persistAndApplyBadgeState()
    }

    func retainApplicationBadgeBaseURLs(_ baseURLs: Set<String>) {
        badgeState.retainBaseURLs(baseURLs)
        persistAndApplyBadgeState()
    }

    func removeApplicationBadge(baseURL: String) {
        badgeState.remove(baseURL: baseURL)
        persistAndApplyBadgeState()
    }

    private func persistAndApplyBadgeState() {
        defaults.set(badgeState.unreadCountsByScope, forKey: Self.badgeStateKey)
        let badgeCount = badgeState.totalUnreadCount
        if #available(iOS 16.0, *) {
            center.setBadgeCount(badgeCount) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = badgeCount
        }
    }

    func deliver(
        notifications: [DiscourseNotification],
        baseURL: String,
        authorizationPolicy: ForumNotificationAuthorizationPolicy
    ) async -> [DiscourseNotification] {
        guard !notifications.isEmpty else { return [] }
        guard await ensureAuthorization(policy: authorizationPolicy) else { return [] }

        var delivered: [DiscourseNotification] = []
        for notification in notifications {
            guard !Task.isCancelled else { break }
            let content = UNMutableNotificationContent()
            content.title = notification.displayTitle
            content.body = notification.displayDescription
            content.sound = .default
            content.badge = NSNumber(value: badgeState.totalUnreadCount)
            var userInfo: [String: Any] = [ForumNotificationRoute.UserInfoKey.baseURL: baseURL]
            userInfo[ForumNotificationRoute.UserInfoKey.notificationId] = notification.id
            if let topicId = notification.topicId {
                userInfo[ForumNotificationRoute.UserInfoKey.topicId] = topicId
            }
            if let postNumber = notification.postNumber {
                userInfo[ForumNotificationRoute.UserInfoKey.postNumber] = postNumber
            }
            content.userInfo = userInfo
            let request = UNNotificationRequest(
                identifier: "dexoflux.\(normalizedBaseURL(baseURL)).\(notification.id)",
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
                delivered.append(notification)
            } catch {
                DohDebugLog.record(
                    "local notification enqueue failed id=\(notification.id) error=\(error.localizedDescription)",
                    subsystem: "BackgroundRefresh"
                )
                break
            }
        }
        return delivered
    }

    private func ensureAuthorization(policy: ForumNotificationAuthorizationPolicy) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            guard policy.allowsAuthorizationRequest(
                isApplicationActive: UIApplication.shared.applicationState == .active
            ) else {
                return false
            }
            return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
            .replacingOccurrences(of: "://", with: ".")
            .replacingOccurrences(of: "/", with: ".")
    }
}

struct ForumNotificationRoute: Equatable {
    enum UserInfoKey {
        static let baseURL = "dexoflux.notification.baseURL"
        static let notificationId = "dexoflux.notification.notificationId"
        static let topicId = "dexoflux.notification.topicId"
        static let postNumber = "dexoflux.notification.postNumber"
    }

    let baseURL: String
    let notificationId: Int?
    let topicId: Int?
    let postNumber: Int?
}

@MainActor
final class ForumNotificationRouteStore: DexoObservableObject {
    static let shared = ForumNotificationRouteStore()

    private(set) var pendingRoute: ForumNotificationRoute?

    private override init() {
        super.init()
    }

    func enqueue(_ route: ForumNotificationRoute) {
        pendingRoute = route
        notifyChanged()
    }

    func consume(baseURL: String) -> ForumNotificationRoute? {
        guard let pendingRoute,
              normalizedBaseURL(pendingRoute.baseURL) == normalizedBaseURL(baseURL)
        else { return nil }
        self.pendingRoute = nil
        return pendingRoute
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}

@MainActor
enum ForumNotificationRoutePresenter {
    static func presentPendingRouteIfNeeded() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0.delegate as? SceneDelegate)?.window })
            .first
        else { return }
        presentPendingRouteIfNeeded(in: window)
    }

    static func presentPendingRouteIfNeeded(in window: UIWindow) {
        guard let route = ForumNotificationRouteStore.shared.pendingRoute else { return }
        let targetBaseURL = ForumInstance.normalizedBaseURL(route.baseURL)

        if let currentContainer = ForumOverlayManager.shared.currentContainer,
           ForumInstance.normalizedBaseURL(currentContainer.forum.baseURL) == targetBaseURL {
            return
        }
        if let rootContainer = window.rootViewController as? ForumContainerViewController,
           ForumInstance.normalizedBaseURL(rootContainer.forum.baseURL) == targetBaseURL {
            return
        }

        let forums = (try? DatabaseManager.shared.fetchAllForums()) ?? []
        guard let forum = matchingForum(baseURL: route.baseURL, forums: forums) else { return }
        ForumOverlayManager.shared.present(forum: forum, in: window)
    }

    static func matchingForum(baseURL: String, forums: [ForumInstance]) -> ForumInstance? {
        let normalizedBaseURL = ForumInstance.normalizedBaseURL(baseURL)
        return forums.first {
            ForumInstance.normalizedBaseURL($0.baseURL) == normalizedBaseURL
        }
    }
}

@MainActor
final class ForumNotificationCoordinator: DexoObservableObject {
    private static let foregroundRefreshInterval: TimeInterval = 60

    private let api: DiscourseAPI
    private let deliveryStore: ForumNotificationDeliveryStore
    private let presenter: ForumLocalNotificationPresenting
    private var refreshTimer: Timer?
    private var foregroundObservationToken: NSObjectProtocol?
    private var backgroundObservationToken: NSObjectProtocol?
    private var authObservationToken: NSObjectProtocol?
    private var isRefreshing = false
    private var pendingForceListRefresh = false
    private var lastListRefreshAt: Date?
    private var nextAutomaticRefreshAt: Date?
    private var lastNotificationChannelPosition: Int?
    private var activeBadgeScope: String?

    private(set) var notifications: [DiscourseNotification] = []
    private(set) var unreadCount = 0
    private(set) var unreadHighPriorityCount = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var requiresLogin = false

    init(
        api: DiscourseAPI
    ) {
        self.api = api
        self.deliveryStore = .shared
        self.presenter = ForumLocalNotificationPresenter.shared
        super.init()
    }

    init(
        api: DiscourseAPI,
        defaults: UserDefaults,
        presenter: ForumLocalNotificationPresenting
    ) {
        self.api = api
        self.deliveryStore = ForumNotificationDeliveryStore(defaults: defaults)
        self.presenter = presenter
        super.init()
    }

    @MainActor deinit {
        refreshTimer?.invalidate()
        if let foregroundObservationToken {
            NotificationCenter.default.removeObserver(foregroundObservationToken)
        }
        if let backgroundObservationToken {
            NotificationCenter.default.removeObserver(backgroundObservationToken)
        }
        if let authObservationToken {
            NotificationCenter.default.removeObserver(authObservationToken)
        }
    }

    func startMonitoring() {
        guard foregroundObservationToken == nil else { return }
        foregroundObservationToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.startRefreshTimer()
                await self.refresh(deliverAlerts: true)
            }
        }
        backgroundObservationToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopRefreshTimer()
            }
        }
        authObservationToken = NotificationCenter.default.addObserver(
            forName: DexoObservableObject.didChangeNotification,
            object: AuthManager.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if AuthManager.shared.isAuthenticated(for: self.api.baseURL) {
                    await self.refresh(forceList: true, deliverAlerts: false)
                } else {
                    self.resetForLogout()
                }
            }
        }
        startRefreshTimer()
        Task { await refresh(forceList: true, deliverAlerts: false) }
    }

    func refresh(forceList: Bool = false, deliverAlerts: Bool = true) async {
        if isRefreshing {
            pendingForceListRefresh = pendingForceListRefresh || forceList
            return
        }
        if !forceList, let nextAutomaticRefreshAt, nextAutomaticRefreshAt > Date() {
            return
        }
        guard AuthManager.shared.isAuthenticated(for: api.baseURL) else {
            resetForLogout()
            return
        }

        isRefreshing = true
        isLoading = forceList && notifications.isEmpty
        errorMessage = nil
        requiresLogin = false
        notifyChanged()
        defer {
            isRefreshing = false
            isLoading = false
            notifyChanged()
            if pendingForceListRefresh {
                pendingForceListRefresh = false
                Task { await refresh(forceList: true, deliverAlerts: false) }
            }
        }

        do {
            let currentUser = try await api.fetchCurrentUser()
            nextAutomaticRefreshAt = nil
            let previousUnreadCount = unreadCount
            let officialUnreadCount = currentUser.hasOfficialUnreadNotificationCount
                ? currentUser.effectiveUnreadNotificationCount
                : nil
            if let officialUnreadCount {
                unreadCount = officialUnreadCount
                unreadHighPriorityCount = max(currentUser.unreadHighPriorityNotifications ?? 0, 0)
                updateApplicationBadge(unreadCount, username: currentUser.username)
                notifyChanged()
            }
            let listRefreshExpired = lastListRefreshAt.map {
                Date().timeIntervalSince($0) >= 5 * 60
            } ?? true
            let shouldFetchList = ForumNotificationRefreshPolicy.shouldFetchList(
                forceList: forceList,
                notificationsAreEmpty: notifications.isEmpty,
                previousUnreadCount: previousUnreadCount,
                officialUnreadCount: officialUnreadCount,
                previousChannelPosition: lastNotificationChannelPosition,
                currentChannelPosition: currentUser.notificationChannelPosition,
                listRefreshExpired: listRefreshExpired
            )
            lastNotificationChannelPosition = currentUser.notificationChannelPosition

            var shouldEvaluateLocalAlerts = deliverAlerts
            if shouldFetchList {
                do {
                    let list = try await api.fetchNotifications()
                    lastListRefreshAt = Date()
                    notifications = list.notifications
                    unreadCount = officialUnreadCount ?? list.notifications.filter { !$0.read }.count
                    unreadHighPriorityCount = max(currentUser.unreadHighPriorityNotifications ?? 0, 0)
                    updateApplicationBadge(unreadCount, username: currentUser.username)
                    shouldEvaluateLocalAlerts = true
                } catch {
                    if let apiError = error as? DiscourseAPIError,
                       apiError.isNotLoggedIn || apiError.isForbidden {
                        requiresLogin = true
                    }
                    errorMessage = error.localizedDescription
                    nextAutomaticRefreshAt = Date().addingTimeInterval(5 * 60)
                }
            }
            if shouldEvaluateLocalAlerts {
                deliveryStore.establishBaselineIfNeeded(
                    notifications,
                    baseURL: api.baseURL,
                    username: currentUser.username
                )
                if deliverAlerts {
                    let candidates = deliveryStore.reservePendingNotifications(
                        notifications,
                        baseURL: api.baseURL,
                        username: currentUser.username,
                        limit: 3
                    )
                    guard !candidates.isEmpty else { return }
                    let delivered = await presenter.deliver(
                        notifications: candidates,
                        baseURL: api.baseURL,
                        authorizationPolicy: .requestIfNeeded
                    )
                    deliveryStore.completeDeliveryAttempt(
                        requested: candidates,
                        delivered: delivered,
                        baseURL: api.baseURL,
                        username: currentUser.username
                    )
                }
            }
        } catch {
            if let apiError = error as? DiscourseAPIError,
               apiError.isNotLoggedIn || apiError.isForbidden {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
            nextAutomaticRefreshAt = Date().addingTimeInterval(5 * 60)
        }
    }

    func markNotificationRead(id: Int) async {
        var optimisticIndex: Int?
        var previousNotification: DiscourseNotification?
        let previousUnreadCount = unreadCount
        if let index = notifications.firstIndex(where: { $0.id == id }), !notifications[index].read {
            optimisticIndex = index
            previousNotification = notifications[index]
            notifications[index] = notifications[index].markingRead()
            unreadCount = max(unreadCount - 1, 0)
            updateApplicationBadge(unreadCount)
            notifyChanged()
        }
        do {
            try await api.markNotificationRead(id: id)
            await refresh(deliverAlerts: false)
        } catch {
            if optimisticIndex != nil,
               let previousNotification,
               let currentIndex = notifications.firstIndex(where: { $0.id == id }),
               notifications[currentIndex].read {
                notifications[currentIndex] = previousNotification
                let localUnreadCount = notifications.filter { !$0.read }.count
                unreadCount = max(previousUnreadCount, localUnreadCount)
                updateApplicationBadge(unreadCount)
            }
            errorMessage = error.localizedDescription
            notifyChanged()
        }
    }

    func markAllRead() async {
        guard notifications.contains(where: { !$0.read }) || unreadCount > 0 else { return }
        let previousUnreadNotificationIds = Set(
            notifications.lazy.filter { !$0.read }.map(\.id)
        )
        let previousUnreadCount = unreadCount
        let previousHighPriorityCount = unreadHighPriorityCount
        notifications = notifications.map { $0.markingRead() }
        unreadCount = 0
        unreadHighPriorityCount = 0
        updateApplicationBadge(0)
        notifyChanged()
        do {
            try await api.markAllNotificationsRead()
            await refresh(deliverAlerts: false)
        } catch {
            notifications = notifications.map { notification in
                guard previousUnreadNotificationIds.contains(notification.id), notification.read else {
                    return notification
                }
                return notification.markingRead(false)
            }
            let localUnreadCount = notifications.filter { !$0.read }.count
            unreadCount = max(previousUnreadCount, localUnreadCount)
            unreadHighPriorityCount = previousHighPriorityCount
            updateApplicationBadge(unreadCount)
            errorMessage = error.localizedDescription
            notifyChanged()
        }
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.foregroundRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh(deliverAlerts: true) }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func resetForLogout() {
        notifications = []
        unreadCount = 0
        unreadHighPriorityCount = 0
        errorMessage = nil
        requiresLogin = true
        nextAutomaticRefreshAt = nil
        if let activeBadgeScope {
            presenter.updateApplicationBadge(0, scope: activeBadgeScope)
            self.activeBadgeScope = nil
        }
        notifyChanged()
    }

    private func updateApplicationBadge(_ unreadCount: Int, username: String? = nil) {
        if let username {
            let newScope = badgeScope(username: username)
            if let activeBadgeScope, activeBadgeScope != newScope {
                presenter.updateApplicationBadge(0, scope: activeBadgeScope)
            }
            activeBadgeScope = newScope
        }
        guard let activeBadgeScope else { return }
        presenter.updateApplicationBadge(unreadCount, scope: activeBadgeScope)
    }

    private func badgeScope(username: String) -> String {
        ForumNotificationBadgeState.scope(baseURL: api.baseURL, username: username)
    }
}
