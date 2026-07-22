import UIKit

final class ForumTabBarController: UITabBarController {
    private let api: DiscourseAPI
    private let notificationCoordinator: ForumNotificationCoordinator
    private weak var authGate: AuthGating?
    private(set) var navigationControllers: [UINavigationController] = []
    var onNavigationControllersChanged: (() -> Void)?

    private var isTabBarHiddenByScroll = false
    private var isAnimatingScrollTabBar = false
    private var scrollTabBarAnimationID = 0
    private var settingsObservationToken: NSObjectProtocol?
    private var authObservationToken: NSObjectProtocol?
    private var pluginObservationToken: NSObjectProtocol?
    private var notificationObservationToken: NSObjectProtocol?
    private var meAvatarLoadTask: Task<Void, Never>?
    private var renderedMeAvatarKey: String?
    private var pendingMeAvatarKey: String?
    private var tabIdentifiers: [String] = []
    private var visibleTabItemIDs: [String] = []
    private var renderedLanguage = AppSettings.shared.appLanguage
    private var scrollExpandedLayoutSnapshots: [ObjectIdentifier: ScrollExpandedLayoutSnapshot] = [:]

    private var pluginScope: PluginScope {
        PluginScope(
            baseURL: api.baseURL,
            username: authGate?.currentUsername() ?? AuthManager.shared.username(for: api.baseURL)
        )
    }

    init(
        api: DiscourseAPI,
        authGate: AuthGating? = nil,
        notificationCoordinator: ForumNotificationCoordinator
    ) {
        self.api = api
        self.authGate = authGate
        self.notificationCoordinator = notificationCoordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppSettings.shared.themeStyle.topicListBackgroundColor

        rebuildTabs(preservingIdentifier: nil)
        startObservingSettings()
        startObservingAuth()
        startObservingPlugins()
        startObservingNotifications()
        configureTabBarSurface()
        refreshMeTabAvatarIcon()
        applyNotificationBadge()
    }

    deinit {
        if let settingsObservationToken {
            NotificationCenter.default.removeObserver(settingsObservationToken)
        }
        if let authObservationToken {
            NotificationCenter.default.removeObserver(authObservationToken)
        }
        if let pluginObservationToken {
            NotificationCenter.default.removeObserver(pluginObservationToken)
        }
        if let notificationObservationToken {
            NotificationCenter.default.removeObserver(notificationObservationToken)
        }
        meAvatarLoadTask?.cancel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isAnimatingScrollTabBar else { return }
        applyCurrentTabBarLayout()
    }

    func setTabBarHiddenByScroll(_ hidden: Bool, animated: Bool) {
        guard isTabBarHiddenByScroll != hidden else { return }
        isTabBarHiddenByScroll = hidden

        guard animated else {
            scrollTabBarAnimationID += 1
            isAnimatingScrollTabBar = false
            applyCurrentTabBarLayout()
            return
        }

        guard !shouldHideTabBarForCurrentContent else {
            scrollTabBarAnimationID += 1
            isAnimatingScrollTabBar = false
            applyCurrentTabBarLayout()
            return
        }

        let hiddenTransform = CGAffineTransform(translationX: 0, y: tabBarTotalHeight + 8)
        isAnimatingScrollTabBar = true
        scrollTabBarAnimationID += 1
        let animationID = scrollTabBarAnimationID

        let completion: (UIViewAnimatingPosition) -> Void = { [weak self] _ in
            guard let self, self.scrollTabBarAnimationID == animationID else { return }
            self.isAnimatingScrollTabBar = false
            guard self.isTabBarHiddenByScroll == hidden else { return }
            self.tabBar.isUserInteractionEnabled = !hidden
            if hidden {
                self.applyCurrentTabBarLayout()
            } else {
                self.configureTabBarSurface()
                self.applyCurrentTabBarLayout()
            }
        }

        if hidden {
            tabBar.isHidden = false
            tabBar.alpha = 1
            tabBar.transform = .identity
            tabBar.frame = tabBarFrame(hidden: false)
            tabBar.isUserInteractionEnabled = false
            view.bringSubviewToFront(tabBar)

            DexoMotion.animate(
                duration: DexoMotion.standard,
                animations: {
                    self.tabBar.transform = hiddenTransform
                    self.expandSelectedContentIntoTabBarArea()
                    self.view.layoutIfNeeded()
                },
                completion: completion
            )
        } else {
            tabBar.isHidden = false
            tabBar.alpha = 1
            tabBar.frame = tabBarFrame(hidden: false)
            tabBar.transform = hiddenTransform
            configureTabBarSurface()
            view.bringSubviewToFront(tabBar)

            DexoMotion.animate(
                duration: DexoMotion.standard,
                animations: {
                    self.restoreScrollExpandedContentLayout()
                    self.tabBar.transform = .identity
                    self.view.layoutIfNeeded()
                },
                completion: completion
            )
        }
    }

    func configureTabBarSurface() {
        let settings = AppSettings.shared
        let themeStyle = settings.themeStyle
        view.backgroundColor = themeStyle.topicListBackgroundColor
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = themeStyle == .systemDefault ? .systemBackground : themeStyle.contentBackgroundColor
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.35)
        let normalTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.tabBarItemFont(selected: false),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let selectedTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: settings.tabBarItemFont(selected: true),
            .foregroundColor: themeStyle.accentColor,
        ]
        [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ].forEach { itemAppearance in
            itemAppearance.normal.titleTextAttributes = normalTitleAttributes
            itemAppearance.selected.titleTextAttributes = selectedTitleAttributes
            itemAppearance.normal.iconColor = UIColor.secondaryLabel.withAlphaComponent(0.78)
            itemAppearance.selected.iconColor = themeStyle.accentColor
        }
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.backgroundColor = appearance.backgroundColor
        tabBar.barTintColor = appearance.backgroundColor
        tabBar.tintColor = themeStyle.accentColor
        tabBar.unselectedItemTintColor = UIColor.secondaryLabel.withAlphaComponent(0.78)
        tabBar.isOpaque = true
        tabBar.isTranslucent = false
        tabBar.alpha = 1
    }

    var visibleTabBarHeight: CGFloat {
        guard !isTabBarHiddenByScroll, !shouldHideTabBarForCurrentContent, !tabBar.isHidden else { return 0 }
        return tabBarTotalHeight
    }

    func syncTabBarVisibilityForCurrentContent() {
        scrollTabBarAnimationID += 1
        isAnimatingScrollTabBar = false
        applyCurrentTabBarLayout()
    }

    var tabBarTotalHeight: CGFloat {
        return max(tabBar.bounds.height, tabBar.frame.height, 49 + view.safeAreaInsets.bottom)
    }

    private var shouldHideTabBarForCurrentContent: Bool {
        guard let navigationController = selectedViewController as? UINavigationController,
              let visibleViewController = navigationController.visibleViewController
        else {
            return false
        }
        if let browser = visibleViewController as? InAppBrowserViewController,
           browser.hidesHostTabBarAtRoot {
            return true
        }
        guard visibleViewController !== navigationController.viewControllers.first else { return false }
        return visibleViewController.hidesBottomBarWhenPushed
    }

    private var shouldExpandContentForHiddenRootTabBar: Bool {
        guard let navigationController = selectedViewController as? UINavigationController,
              let browser = navigationController.visibleViewController as? InAppBrowserViewController
        else { return false }
        return browser.hidesHostTabBarAtRoot
    }

    private func applyCurrentTabBarLayout() {
        if shouldHideTabBarForCurrentContent {
            applyHiddenTabBarLayout(expandsSelectedContent: shouldExpandContentForHiddenRootTabBar)
        } else if isTabBarHiddenByScroll {
            applyHiddenTabBarLayout(expandsSelectedContent: true)
        } else {
            applyVisibleTabBarLayout()
        }
    }

    private func applyHiddenTabBarLayout(expandsSelectedContent: Bool) {
        tabBar.isHidden = true
        tabBar.alpha = 1
        tabBar.transform = .identity
        tabBar.frame = tabBarFrame(hidden: true)
        tabBar.isUserInteractionEnabled = false
        if expandsSelectedContent {
            expandSelectedContentIntoTabBarArea()
        } else {
            restoreScrollExpandedContentLayout()
        }
    }

    private func applyVisibleTabBarLayout() {
        restoreScrollExpandedContentLayout()
        tabBar.isHidden = false
        tabBar.alpha = 1
        tabBar.transform = .identity
        tabBar.frame = tabBarFrame(hidden: false)
        tabBar.isUserInteractionEnabled = true
        view.bringSubviewToFront(tabBar)
    }

    private func tabBarFrame(hidden: Bool) -> CGRect {
        let height = tabBarTotalHeight
        let y = hidden ? view.bounds.maxY : view.bounds.maxY - height
        return CGRect(x: 0, y: y, width: view.bounds.width, height: height)
    }

    private func expandSelectedContentIntoTabBarArea() {
        guard let selectedView = selectedViewController?.view else { return }
        if let contentContainer = selectedView.superview {
            storeScrollExpandedLayoutSnapshot(for: contentContainer)
            storeScrollExpandedLayoutSnapshot(for: selectedView)
            contentContainer.clipsToBounds = false
            contentContainer.frame = view.bounds
            view.bringSubviewToFront(contentContainer)
            selectedView.frame = contentContainer.bounds
        } else {
            storeScrollExpandedLayoutSnapshot(for: selectedView)
            selectedView.frame = view.bounds
        }
        selectedView.clipsToBounds = false
        selectedView.setNeedsLayout()
        selectedView.layoutIfNeeded()

        if let navigationController = selectedViewController as? UINavigationController,
           let visibleView = navigationController.visibleViewController?.view {
            expandNavigationContentView(visibleView, in: navigationController.view.bounds)
        }
    }

    private func expandNavigationContentView(_ contentView: UIView, in bounds: CGRect) {
        if let wrapperView = contentView.superview {
            storeScrollExpandedLayoutSnapshot(for: wrapperView)
            storeScrollExpandedLayoutSnapshot(for: contentView)
            wrapperView.clipsToBounds = false
            wrapperView.frame = bounds
            contentView.frame = wrapperView.bounds
        } else {
            storeScrollExpandedLayoutSnapshot(for: contentView)
            contentView.frame = bounds
        }
        contentView.clipsToBounds = false
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
    }

    private func storeScrollExpandedLayoutSnapshot(for view: UIView) {
        let identifier = ObjectIdentifier(view)
        guard scrollExpandedLayoutSnapshots[identifier] == nil else { return }
        scrollExpandedLayoutSnapshots[identifier] = ScrollExpandedLayoutSnapshot(
            view: view,
            frame: view.frame,
            clipsToBounds: view.clipsToBounds
        )
    }

    private func restoreScrollExpandedContentLayout() {
        guard !scrollExpandedLayoutSnapshots.isEmpty else { return }
        let snapshots = scrollExpandedLayoutSnapshots.values
        scrollExpandedLayoutSnapshots.removeAll()
        for snapshot in snapshots {
            guard let view = snapshot.view else { continue }
            view.frame = snapshot.frame
            view.clipsToBounds = snapshot.clipsToBounds
            view.setNeedsLayout()
        }
        selectedViewController?.view.setNeedsLayout()
        selectedViewController?.view.layoutIfNeeded()
    }

}

private extension ForumTabBarController {
    struct ScrollExpandedLayoutSnapshot {
        weak var view: UIView?
        let frame: CGRect
        let clipsToBounds: Bool
    }

    struct TabSpec {
        let identifier: String
        let title: String
        let symbolName: String
        let makeViewController: () -> UIViewController
    }

    func startObservingSettings() {
        settingsObservationToken = NotificationCenter.default.addObserver(
            forName: DexoObservableObject.didChangeNotification,
            object: AppSettings.shared,
            queue: .main
        ) { [weak self] _ in
            self?.handleSettingsChanged()
        }
    }

    func startObservingAuth() {
        authObservationToken = NotificationCenter.default.addObserver(
            forName: DexoObservableObject.didChangeNotification,
            object: AuthManager.shared,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.refreshMeTabAvatarIcon(forceRefresh: true)
            self.rebuildTabs(preservingIdentifier: self.selectedTabIdentifier())
        }
    }

    func startObservingPlugins() {
        pluginObservationToken = NotificationCenter.default.addObserver(
            forName: PluginStateStore.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let changedScope = notification.userInfo?[PluginStateStore.scopeUserInfoKey] as? String,
               changedScope != self.pluginScope.storageKey {
                return
            }
            self.rebuildTabs(preservingIdentifier: self.selectedTabIdentifier())
        }
    }

    func startObservingNotifications() {
        notificationObservationToken = NotificationCenter.default.addObserver(
            forName: DexoObservableObject.didChangeNotification,
            object: notificationCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.applyNotificationBadge()
        }
    }

    func handleSettingsChanged() {
        resetScrollHiddenTabBarForSettingsChange()
        configureTabBarSurface()
        applyCurrentTabBarLayout()
        let currentLanguage = AppSettings.shared.appLanguage
        let languageChanged = currentLanguage != renderedLanguage
        renderedLanguage = currentLanguage

        let newVisibleItems = AppSettings.shared.forumVisibleConfiguredTabItemIDs
        if newVisibleItems != visibleTabItemIDs {
            rebuildTabs(preservingIdentifier: selectedTabIdentifier())
            return
        }
        if languageChanged {
            refreshLocalizedTabTitles()
        }
    }

    func resetScrollHiddenTabBarForSettingsChange() {
        scrollTabBarAnimationID += 1
        isAnimatingScrollTabBar = false
        isTabBarHiddenByScroll = false
    }

    func rebuildTabs(preservingIdentifier preferredIdentifier: String?) {
        let specs = buildTabSpecs()
        let previousIdentifiers = tabIdentifiers
        let existingControllers = Dictionary(uniqueKeysWithValues: zip(tabIdentifiers, navigationControllers))
        var controllers: [UINavigationController] = []
        var identifiers: [String] = []

        for (index, spec) in specs.enumerated() {
            let navigationController: UINavigationController
            if let existingController = existingControllers[spec.identifier] {
                navigationController = existingController
                navigationController.viewControllers.first?.title = spec.title
            } else {
                let rootViewController = spec.makeViewController()
                rootViewController.title = spec.title
                navigationController = UINavigationController(rootViewController: rootViewController)
            }
            navigationController.delegate = self
            navigationController.tabBarItem.title = spec.title
            if spec.identifier != "me" || renderedMeAvatarKey == nil {
                navigationController.tabBarItem.image = DexoTabBarIconStyle.image(
                    identifier: spec.identifier,
                    fallbackSymbolName: spec.symbolName,
                    selected: false
                )
                navigationController.tabBarItem.selectedImage = DexoTabBarIconStyle.image(
                    identifier: spec.identifier,
                    fallbackSymbolName: spec.symbolName,
                    selected: true
                )
            }
            navigationController.tabBarItem.tag = index
            navigationController.tabBarItem.imageInsets = UIEdgeInsets(top: -1, left: 0, bottom: 1, right: 0)
            navigationController.tabBarItem.accessibilityIdentifier = "forum.tab.\(spec.identifier)"
            controllers.append(navigationController)
            identifiers.append(spec.identifier)
        }

        navigationControllers = controllers
        tabIdentifiers = identifiers
        visibleTabItemIDs = AppSettings.shared.forumVisibleConfiguredTabItemIDs

        if #available(iOS 18.0, *) {
            let existingTabs = Dictionary(uniqueKeysWithValues: zip(previousIdentifiers, tabs))
            self.tabs = zip(specs, controllers).map { spec, navigationController in
                let tabImage: UIImage? = {
                    if spec.identifier == "me", renderedMeAvatarKey != nil {
                        return navigationController.tabBarItem.image
                    }
                    return DexoTabBarIconStyle.image(
                        identifier: spec.identifier,
                        fallbackSymbolName: spec.symbolName,
                        selected: false
                    )
                }()

                if let existingTab = existingTabs[spec.identifier] {
                    existingTab.title = spec.title
                    existingTab.image = tabImage
                    return existingTab
                }

                return UITab(
                    title: spec.title,
                    image: tabImage,
                    identifier: spec.identifier
                ) { _ in
                    navigationController
                }
            }
        } else {
            viewControllers = controllers
        }

        let selectedIdentifier = preferredIdentifier ?? "home"
        if let selectedIndex = identifiers.firstIndex(of: selectedIdentifier) {
            self.selectedIndex = selectedIndex
        } else {
            self.selectedIndex = 0
        }

        configureTabBarSurface()
        refreshMeTabAvatarIcon()
        applyNotificationBadge()
        onNavigationControllersChanged?()
    }

    func selectedTabIdentifier() -> String? {
        guard selectedIndex >= 0, selectedIndex < tabIdentifiers.count else { return nil }
        return tabIdentifiers[selectedIndex]
    }

    func refreshMeTabAvatarIcon(forceRefresh: Bool = false) {
        guard let meIndex = tabIdentifiers.firstIndex(of: "me"),
              meIndex < navigationControllers.count
        else { return }

        let authManager = AuthManager.shared
        guard authManager.isAuthenticated(for: api.baseURL) else {
            meAvatarLoadTask?.cancel()
            meAvatarLoadTask = nil
            pendingMeAvatarKey = nil
            renderedMeAvatarKey = nil
            applyDefaultMeTabIcon(at: meIndex)
            return
        }

        let username = authManager.username(for: api.baseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarKey = meAvatarKey(username: username)

        if !forceRefresh, renderedMeAvatarKey == avatarKey {
            return
        }

        if let username, !username.isEmpty,
           let cachedEntry = MeProfileCacheStore.cachedProfile(baseURL: api.baseURL, username: username) {
            let avatarTemplate = cachedEntry.userProfile.avatarTemplate ?? cachedEntry.currentUser.avatarTemplate
            applyMeTabAvatar(template: avatarTemplate, at: meIndex, avatarKey: avatarKey)
            return
        }

        guard pendingMeAvatarKey != avatarKey else { return }
        pendingMeAvatarKey = avatarKey
        meAvatarLoadTask?.cancel()
        meAvatarLoadTask = Task { [weak self, api] in
            do {
                let currentUser = try await api.fetchCurrentUser()
                await MainActor.run {
                    guard let self else { return }
                    self.pendingMeAvatarKey = nil
                    self.meAvatarLoadTask = nil
                    guard AuthManager.shared.isAuthenticated(for: self.api.baseURL) else {
                        self.renderedMeAvatarKey = nil
                        self.applyDefaultMeTabIcon(at: meIndex)
                        return
                    }
                    self.applyMeTabAvatar(
                        template: currentUser.avatarTemplate,
                        at: meIndex,
                        avatarKey: self.meAvatarKey(username: currentUser.username)
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.pendingMeAvatarKey = nil
                    self.meAvatarLoadTask = nil
                    if !AuthManager.shared.isAuthenticated(for: self.api.baseURL) {
                        self.renderedMeAvatarKey = nil
                        self.applyDefaultMeTabIcon(at: meIndex)
                    }
                }
            }
        }
    }

    func applyMeTabAvatar(template: String?, at index: Int, avatarKey: String) {
        guard let url = AvatarImageLoader.url(from: template, baseURL: api.baseURL, size: 96) else {
            renderedMeAvatarKey = nil
            applyDefaultMeTabIcon(at: index)
            return
        }

        let requestedKey = avatarKey
        ForumImageLoader.loadImage(with: url) { [weak self] image in
            guard let self, let image else { return }
            guard AuthManager.shared.isAuthenticated(for: self.api.baseURL) else { return }
            let currentUsername = AuthManager.shared.username(for: self.api.baseURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let currentUsername, !currentUsername.isEmpty,
               self.meAvatarKey(username: currentUsername) != requestedKey {
                return
            }
            let normalImage = DexoTabBarIconStyle.avatarImage(
                image,
                selected: false,
                accentColor: AppSettings.shared.themeStyle.accentColor
            )
            let selectedImage = DexoTabBarIconStyle.avatarImage(
                image,
                selected: true,
                accentColor: AppSettings.shared.themeStyle.accentColor
            )
            self.applyMeTabImages(normalImage: normalImage, selectedImage: selectedImage, at: index)
            self.renderedMeAvatarKey = requestedKey
        }
    }

    func applyDefaultMeTabIcon(at index: Int) {
        let normalImage = DexoTabBarIconStyle.image(identifier: "me", fallbackSymbolName: "person", selected: false)
        let selectedImage = DexoTabBarIconStyle.image(identifier: "me", fallbackSymbolName: "person", selected: true)
        applyMeTabImages(normalImage: normalImage, selectedImage: selectedImage, at: index)
    }

    func applyMeTabImages(normalImage: UIImage?, selectedImage: UIImage?, at index: Int) {
        guard index >= 0, index < navigationControllers.count else { return }
        guard let tabBarItem = navigationControllers[index].tabBarItem else { return }
        tabBarItem.image = normalImage
        tabBarItem.selectedImage = selectedImage
        tabBarItem.imageInsets = UIEdgeInsets(top: -1, left: 0, bottom: 1, right: 0)
        if #available(iOS 18.0, *), index < tabs.count {
            tabs[index].image = normalImage
        }
        tabBar.setNeedsLayout()
    }

    func meAvatarKey(username: String?) -> String {
        let baseURL = api.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let userPart = username?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(baseURL)|\(userPart?.isEmpty == false ? userPart! : "_authenticated")"
    }

    func refreshLocalizedTabTitles() {
        let specs = buildTabSpecs()
        for (index, navigationController) in navigationControllers.enumerated() where index < specs.count {
            let spec = specs[index]
            navigationController.tabBarItem.title = spec.title
            navigationController.viewControllers.first?.title = spec.title
        }
        refreshMeTabAvatarIcon()
        if #available(iOS 18.0, *) {
            for (index, tab) in tabs.enumerated() where index < specs.count {
                tab.title = specs[index].title
            }
        }
        onNavigationControllersChanged?()
    }

    func buildTabSpecs() -> [TabSpec] {
        var specs: [TabSpec] = [
            TabSpec(
                identifier: "home",
                title: String(localized: "tab.home"),
                symbolName: "house"
            ) { [api, authGate, notificationCoordinator] in
                HomeViewController(
                    api: api,
                    authGate: authGate,
                    notificationCoordinator: notificationCoordinator
                )
            },
        ]

        let pluginTabs = Dictionary(uniqueKeysWithValues: DexoPluginRuntime.shared.registry
            .contributions(of: .forumTab, for: pluginScope)
            .map { registration in
                (AppSettings.pluginForumTabItemID(
                    pluginID: registration.plugin.id,
                    contributionID: registration.contribution.id
                ), registration)
            })
        let configuredSpecs = AppSettings.shared.forumVisibleConfiguredTabItemIDs.compactMap { itemID -> TabSpec? in
            if let systemItem = AppSettings.ForumDynamicTabItem.storedValue(itemID) {
                return dynamicTabSpec(for: systemItem)
            }
            guard let registration = pluginTabs[itemID] else { return nil }
            return pluginTabSpec(for: registration)
        }
        specs.append(contentsOf: configuredSpecs)

        specs.append(
            TabSpec(
                identifier: "me",
                title: String(localized: "tab.me"),
                symbolName: "person"
            ) { [api, authGate] in
                MeViewController(api: api, authGate: authGate)
            }
        )

        return specs
    }

    func pluginTabSpec(for registration: PluginContributionRegistration) -> TabSpec? {
        let identifier = "plugin.\(registration.plugin.id).\(registration.contribution.id)"
        let title = registration.contribution.titleFallback ?? registration.plugin.displayName

        switch registration.plugin.id {
        case BuiltInPluginID.newAPICheckIn:
            return TabSpec(
                identifier: identifier,
                title: title,
                symbolName: registration.contribution.systemImageName
            ) {
                NewAPICheckInViewController()
            }
        case BuiltInPluginID.ldcStore:
            return TabSpec(
                identifier: identifier,
                title: title,
                symbolName: registration.contribution.systemImageName
            ) { [api, authGate] in
                InAppBrowserViewController(
                    api: api,
                    username: authGate?.currentUsername() ?? AuthManager.shared.username(for: api.baseURL),
                    initialURL: URL(string: "https://ldcstore.com/"),
                    hidesHostTabBarAtRoot: true,
                    hidesBrowserControlBar: true
                )
            }
        default:
            return nil
        }
    }

    func dynamicTabSpec(for item: AppSettings.ForumDynamicTabItem) -> TabSpec {
        TabSpec(
            identifier: item.rawValue,
            title: item.title,
            symbolName: item.symbolName
        ) { [api, authGate, notificationCoordinator] in
            switch item {
            case .history:
                return BrowsingHistoryViewController(api: api, authGate: authGate)
            case .search:
                return SearchViewController(api: api)
            case .notifications:
                return NotificationsViewController(
                    api: api,
                    authGate: authGate,
                    notificationCoordinator: notificationCoordinator
                )
            case .messages:
                let controller = MessagesViewController(api: api, authGate: authGate)
                controller.hidesBottomBarWhenPushed = false
                return controller
            case .bookmarks:
                return BookmarksViewController(api: api, authGate: authGate)
            }
        }
    }

    func applyNotificationBadge() {
        for identifier in ["home", "notifications"] {
            guard let index = tabIdentifiers.firstIndex(of: identifier),
                  index < navigationControllers.count
            else { continue }
            navigationControllers[index].tabBarItem.badgeValue = nil
            if #available(iOS 18.0, *), index < tabs.count {
                tabs[index].badgeValue = nil
            }
        }

        let targetIdentifier = tabIdentifiers.contains("notifications") ? "notifications" : "home"
        guard let index = tabIdentifiers.firstIndex(of: targetIdentifier),
              index < navigationControllers.count
        else { return }
        let unreadCount = notificationCoordinator.unreadCount
        let badgeValue = unreadCount > 0 ? (unreadCount > 99 ? "99+" : String(unreadCount)) : nil
        navigationControllers[index].tabBarItem.badgeValue = badgeValue
        navigationControllers[index].tabBarItem.badgeColor = .systemRed
        if #available(iOS 18.0, *), index < tabs.count {
            tabs[index].badgeValue = badgeValue
        }
    }
}

enum DexoTabBarIconStyle {
    private static let normalConfiguration = UIImage.SymbolConfiguration(
        pointSize: 18,
        weight: .bold,
        scale: .large
    )
    private static let selectedConfiguration = UIImage.SymbolConfiguration(
        pointSize: 19,
        weight: .heavy,
        scale: .large
    )

    static func image(identifier: String, fallbackSymbolName: String, selected: Bool) -> UIImage? {
        let symbolName = filledSymbolName(for: identifier, fallback: fallbackSymbolName)
        return image(named: symbolName, fallbackSymbolName: fallbackSymbolName, selected: selected)
    }

    static func image(named symbolName: String, selected: Bool) -> UIImage? {
        image(named: symbolName, fallbackSymbolName: symbolName, selected: selected)
    }

    static func avatarImage(_ source: UIImage, selected: Bool, accentColor: UIColor) -> UIImage {
        let canvasSize = CGSize(width: 26, height: 26)
        let ringWidth: CGFloat = selected ? 2.0 : 1.0
        let avatarRect = CGRect(x: 2.5, y: 2.5, width: 21, height: 21)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)

        return renderer.image { context in
            let cgContext = context.cgContext
            let avatarPath = UIBezierPath(ovalIn: avatarRect)
            UIColor.secondarySystemFill.setFill()
            avatarPath.fill()

            cgContext.saveGState()
            avatarPath.addClip()
            drawAspectFill(source, in: avatarRect)
            cgContext.restoreGState()

            let strokeColor = selected
                ? accentColor
                : UIColor.separator.withAlphaComponent(0.55)
            strokeColor.setStroke()
            avatarPath.lineWidth = ringWidth
            avatarPath.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }

    private static func image(named symbolName: String, fallbackSymbolName: String, selected: Bool) -> UIImage? {
        let configuration = selected ? selectedConfiguration : normalConfiguration
        return UIImage(systemName: symbolName, withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: fallbackSymbolName, withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate)
            ?? UIImage(named: fallbackSymbolName)?.withRenderingMode(.alwaysOriginal)
    }

    private static func filledSymbolName(for identifier: String, fallback: String) -> String {
        switch identifier {
        case "home":
            return "house.fill"
        case "history":
            return "clock.fill"
        case "search":
            return "magnifyingglass.circle.fill"
        case "notifications":
            return "bell.fill"
        case "messages":
            return "envelope.fill"
        case "bookmarks":
            return "bookmark.fill"
        case "me":
            return "person.crop.circle.fill"
        default:
            return fallback
        }
    }

    private static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }
}

extension ForumTabBarController: UINavigationControllerDelegate {
    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        switch operation {
        case .push where toVC is TopicDetailViewController:
            return TopicDetailNavigationAnimator(operation: .push)
        default:
            return nil
        }
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        TopicDetailTransitionGeometry.normalize(viewController.view)
        navigationController.interactivePopGestureRecognizer?.isEnabled = navigationController.viewControllers.count > 1
            && !(viewController is TopicDetailViewController)
        if navigationController.viewControllers.count > 1 {
            isTabBarHiddenByScroll = false
        }
        isAnimatingScrollTabBar = false
        applyCurrentTabBarLayout()
    }
}

private final class BrowsingHistoryViewModel: DexoObservableObject {
    var topics: [DiscourseTopicList.Topic] = []
    var isLoading = false
    var isLoadingMore = false
    var canLoadMore = false
    var errorMessage: String?
    var requiresLogin = false

    private let api: DiscourseAPI
    private var currentPage = 0
    private var usersById: [Int: DiscourseTopicList.User] = [:]
    private var categoryIndex = DiscourseCategoryIndex()

    init(api: DiscourseAPI) {
        self.api = api
    }

    private var canBrowseTopics: Bool {
        AuthManager.shared.isAuthenticated(for: api.baseURL)
    }

    func avatarTemplate(for topic: DiscourseTopicList.Topic) -> String? {
        guard let firstPoster = topic.posters?.first else { return nil }
        return usersById[firstPoster.userId]?.avatarTemplate
    }

    func category(for topic: DiscourseTopicList.Topic) -> DiscourseCategory? {
        guard let categoryId = topic.categoryId else { return nil }
        return categoryIndex[categoryId]
    }

    func categoryDisplayName(for category: DiscourseCategory?) -> String? {
        guard let category else { return nil }
        let resolved = categoryIndex[category.id] ?? category
        return resolved.displayName(parent: parentCategory(for: resolved))
    }

    func loadTopics() async {
        isLoading = true
        errorMessage = nil
        requiresLogin = false
        currentPage = 0
        notifyChanged()
        defer {
            isLoading = false
            notifyChanged()
        }
        guard await validateTopicAccess() else { return }

        do {
            let result = try await api.fetchReadTopics(page: 0)
            topics = result.topicList.topics
            canLoadMore = result.topicList.moreTopicsUrl != nil
            indexUsers(result.users)
            indexCategories(result.categories)
        } catch {
            handle(error)
        }
    }

    func loadMoreTopics() async {
        guard canLoadMore, !isLoadingMore else { return }
        guard await validateTopicAccess() else { return }

        isLoadingMore = true
        notifyChanged()
        defer {
            isLoadingMore = false
            notifyChanged()
        }

        let nextPage = currentPage + 1
        do {
            let result = try await api.fetchReadTopics(page: nextPage)
            currentPage = nextPage
            let existingIds = Set(topics.map(\.id))
            let newTopics = result.topicList.topics.filter { !existingIds.contains($0.id) }
            topics.append(contentsOf: newTopics)
            canLoadMore = result.topicList.moreTopicsUrl != nil
            indexUsers(result.users)
            indexCategories(result.categories)
        } catch {
            handle(error, clearOnAuthFailure: true)
        }
    }

    private func validateTopicAccess() async -> Bool {
        guard canBrowseTopics else {
            clearProtectedContent(invalidateSession: true)
            return false
        }
        do {
            _ = try await api.fetchCurrentUser()
            return true
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                clearProtectedContent(invalidateSession: true)
            } else if topics.isEmpty {
                errorMessage = error.localizedDescription
                notifyChanged()
            }
            return false
        }
    }

    private func handle(_ error: Error, clearOnAuthFailure: Bool = false) {
        if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
            clearProtectedContent(invalidateSession: true)
            return
        }
        if clearOnAuthFailure, topics.isEmpty {
            errorMessage = error.localizedDescription
        } else if !clearOnAuthFailure {
            errorMessage = error.localizedDescription
        }
    }

    private func clearProtectedContent(invalidateSession: Bool = false) {
        topics = []
        isLoading = false
        isLoadingMore = false
        canLoadMore = false
        errorMessage = String(localized: "login.required.message")
        requiresLogin = true
        currentPage = 0
        usersById.removeAll()
        categoryIndex = DiscourseCategoryIndex()
        if invalidateSession {
            AuthManager.shared.invalidateWebSession(for: api.baseURL)
        }
        notifyChanged()
    }

    private func indexUsers(_ users: [DiscourseTopicList.User]?) {
        guard let users else { return }
        for user in users {
            usersById[user.id] = user
        }
    }

    private func indexCategories(_ categories: [DiscourseCategory]?) {
        categoryIndex.merge(categories, source: .topicList)
    }

    private func parentCategory(for category: DiscourseCategory) -> DiscourseCategory? {
        guard let parentId = category.parentCategoryId else { return nil }
        return categoryIndex[parentId]
    }
}

final class BrowsingHistoryViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: BrowsingHistoryViewModel
    private weak var authGate: AuthGating?

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(TopicCell.self, forCellReuseIdentifier: TopicCell.reuseIdentifier)
        table.delegate = self
        table.separatorStyle = .none
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = TopicCell.estimatedHeight
        table.showsVerticalScrollIndicator = false
        return table
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = {
        UITableViewDiffableDataSource<Int, Int>(tableView: tableView) { [weak self] tableView, indexPath, topicId in
            guard let self,
                  let cell = tableView.dequeueReusableCell(withIdentifier: TopicCell.reuseIdentifier, for: indexPath) as? TopicCell,
                  let topic = self.viewModel.topics.first(where: { $0.id == topicId })
            else {
                return UITableViewCell()
            }

            let avatarURL = AvatarImageLoader.url(
                from: self.viewModel.avatarTemplate(for: topic),
                baseURL: self.api.baseURL,
                size: 96
            )
            let category = self.viewModel.category(for: topic)
            let categoryColor = category.flatMap { Self.color(fromHex: $0.color) }
            cell.configure(
                with: topic,
                avatarURL: avatarURL,
                categoryName: self.viewModel.categoryDisplayName(for: category),
                categoryColor: categoryColor,
                tags: topic.tags ?? []
            )
            return cell
        }
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let stateIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .tertiaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let loginButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "me.login")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let retryButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = String(localized: "action.retry")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var stateStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [stateIconView, stateLabel, loginButton, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()

    private let footerSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        return spinner
    }()

    private let emptyFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        return control
    }()

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.api = api
        self.viewModel = BrowsingHistoryViewModel(api: api)
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "tab.history")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyThemeStyle()
        tableView.tableFooterView = emptyFooterView
        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(stateStackView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            stateStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateStackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateStackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            stateIconView.widthAnchor.constraint(equalToConstant: 58),
            stateIconView.heightAnchor.constraint(equalToConstant: 58),
        ])

        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        Task {
            await viewModel.loadTopics()
        }
    }

    override func updateUI() {
        refreshControl.endRefreshing()
        applyThemeStyle()

        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        var seen = Set<Int>()
        let uniqueIds = viewModel.topics.compactMap { topic -> Int? in
            guard seen.insert(topic.id).inserted else { return nil }
            return topic.id
        }
        snapshot.appendItems(uniqueIds, toSection: 0)
        let currentIds = Set(dataSource.snapshot().itemIdentifiers)
        let reconfigurableIds = uniqueIds.filter { currentIds.contains($0) }
        if !reconfigurableIds.isEmpty {
            snapshot.reconfigureItems(reconfigurableIds)
        }
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)

        let hasTopics = !viewModel.topics.isEmpty
        if viewModel.isLoading && !hasTopics {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        tableView.isHidden = !hasTopics
        stateStackView.isHidden = hasTopics || viewModel.isLoading

        if viewModel.requiresLogin {
            configureState(
                iconName: "lock.circle",
                text: viewModel.errorMessage ?? String(localized: "login.required.message"),
                showLogin: authGate != nil,
                showRetry: authGate == nil
            )
        } else if let errorMessage = viewModel.errorMessage, !hasTopics {
            configureState(
                iconName: "exclamationmark.triangle",
                text: errorMessage,
                showLogin: false,
                showRetry: true
            )
        } else if !hasTopics, !viewModel.isLoading {
            configureState(
                iconName: "clock.arrow.circlepath",
                text: "还没有浏览历史",
                showLogin: false,
                showRetry: false
            )
        }

        if viewModel.isLoadingMore {
            tableView.tableFooterView = footerSpinner
            footerSpinner.startAnimating()
        } else {
            footerSpinner.stopAnimating()
            tableView.tableFooterView = emptyFooterView
        }
    }

    private func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        let pageBackground = themeStyle.topicListBackgroundColor
        view.backgroundColor = pageBackground
        tableView.backgroundColor = pageBackground
        view.tintColor = themeStyle.accentColor
        refreshControl.tintColor = themeStyle.accentColor
        activityIndicator.color = themeStyle.accentColor
        footerSpinner.color = themeStyle.accentColor
        stateIconView.tintColor = themeStyle.accentColor.withAlphaComponent(0.78)
        loginButton.tintColor = themeStyle.accentColor
        retryButton.tintColor = themeStyle.accentColor
    }

    private func configureState(iconName: String, text: String, showLogin: Bool, showRetry: Bool) {
        stateIconView.image = UIImage(
            systemName: iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 50, weight: .regular)
        )
        stateLabel.text = text
        loginButton.isHidden = !showLogin
        retryButton.isHidden = !showRetry
    }

    @objc private func pullToRefresh() {
        Task {
            await viewModel.loadTopics()
        }
    }

    @objc private func retryTapped() {
        Task {
            await viewModel.loadTopics()
        }
    }

    @objc private func loginTapped() {
        authGate?.requireAuth(then: { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.loadTopics()
            }
        })
    }

    private static func color(fromHex hex: String) -> UIColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension BrowsingHistoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicId = dataSource.itemIdentifier(for: indexPath) else { return }
        let detailVC = TopicDetailViewController(api: api, topicId: topicId)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let totalRows = tableView.numberOfRows(inSection: 0)
        if indexPath.row >= totalRows - 5 {
            Task {
                await viewModel.loadMoreTopics()
            }
        }
    }
}

enum TopicDetailTransitionGeometry {
    static let pushInitialTransform = CGAffineTransform.identity

    static func normalize(_ view: UIView) {
        view.layer.removeAllAnimations()
        view.alpha = 1
        view.transform = .identity
    }
}

private final class TopicDetailNavigationAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let operation: UINavigationController.Operation
    private let detailOffset: CGFloat = 34
    private let listParallaxOffset: CGFloat = 12
    private var runningAnimator: UIViewPropertyAnimator?

    init(operation: UINavigationController.Operation) {
        self.operation = operation
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        DexoMotion.emphasized
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let animator = interruptibleAnimator(using: transitionContext)
        animator.startAnimation()
    }

    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let runningAnimator {
            return runningAnimator
        }

        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return DexoMotion.propertyAnimator(duration: 0)
        }

        let animator: UIViewPropertyAnimator
        switch operation {
        case .push:
            animator = makePushAnimator(fromView: fromView, toView: toView, context: transitionContext)
        case .pop:
            animator = makePopAnimator(fromView: fromView, toView: toView, context: transitionContext)
        default:
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            animator = DexoMotion.propertyAnimator(duration: 0)
        }

        runningAnimator = animator
        return animator
    }

    func animationEnded(_ transitionCompleted: Bool) {
        runningAnimator = nil
    }

    private func makePushAnimator(
        fromView: UIView,
        toView: UIView,
        context: UIViewControllerContextTransitioning
    ) -> UIViewPropertyAnimator {
        let container = context.containerView
        guard let toViewController = context.viewController(forKey: .to) else {
            context.completeTransition(false)
            return DexoMotion.propertyAnimator(duration: 0)
        }
        TopicDetailTransitionGeometry.normalize(fromView)
        TopicDetailTransitionGeometry.normalize(toView)
        container.backgroundColor = AppSettings.shared.themeStyle.topicListBackgroundColor
        toView.frame = context.finalFrame(for: toViewController)
        toView.alpha = 0.97
        toView.transform = TopicDetailTransitionGeometry.pushInitialTransform
        container.addSubview(toView)

        let animator = DexoMotion.propertyAnimator(
            duration: transitionDuration(using: context),
            timingParameters: DexoMotion.softSpring
        )
        animator.addAnimations {
            fromView.alpha = 0.98
            fromView.transform = CGAffineTransform(translationX: -self.listParallaxOffset, y: 0)
                .scaledBy(x: 0.992, y: 0.992)
            toView.alpha = 1
            toView.transform = .identity
        }
        animator.addCompletion { [weak self] position in
            let completed = position == .end && !context.transitionWasCancelled
            TopicDetailTransitionGeometry.normalize(fromView)
            TopicDetailTransitionGeometry.normalize(toView)
            if !completed {
                toView.removeFromSuperview()
            }
            context.completeTransition(completed)
            self?.runningAnimator = nil
        }
        return animator
    }

    private func makePopAnimator(
        fromView: UIView,
        toView: UIView,
        context: UIViewControllerContextTransitioning
    ) -> UIViewPropertyAnimator {
        let container = context.containerView
        guard let toViewController = context.viewController(forKey: .to) else {
            context.completeTransition(false)
            return DexoMotion.propertyAnimator(duration: 0)
        }
        TopicDetailTransitionGeometry.normalize(fromView)
        TopicDetailTransitionGeometry.normalize(toView)
        toView.frame = context.finalFrame(for: toViewController)
        toView.alpha = 0.98
        toView.transform = CGAffineTransform(translationX: -listParallaxOffset, y: 0)
        container.insertSubview(toView, belowSubview: fromView)

        let animator = DexoMotion.propertyAnimator(
            duration: transitionDuration(using: context),
            timingParameters: DexoMotion.softSpring
        )
        animator.addAnimations {
            fromView.alpha = 0.96
            fromView.transform = CGAffineTransform(translationX: self.detailOffset, y: 0)
                .scaledBy(x: 0.992, y: 0.992)
            toView.alpha = 1
            toView.transform = .identity
        }
        animator.addCompletion { [weak self] position in
            let completed = position == .end && !context.transitionWasCancelled
            TopicDetailTransitionGeometry.normalize(fromView)
            TopicDetailTransitionGeometry.normalize(toView)
            context.completeTransition(completed)
            self?.runningAnimator = nil
        }
        return animator
    }
}
