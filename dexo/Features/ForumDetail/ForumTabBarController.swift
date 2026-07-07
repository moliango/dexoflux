import UIKit

final class ForumTabBarController: UITabBarController {
    private let api: DiscourseAPI
    private weak var authGate: AuthGating?
    private(set) var navigationControllers: [UINavigationController] = []
    var onNavigationControllersChanged: (() -> Void)?

    private var isTabBarHiddenByScroll = false
    private var originalAdditionalSafeAreaInsets: [ObjectIdentifier: UIEdgeInsets] = [:]
    private var settingsObservationToken: NSObjectProtocol?
    private var tabIdentifiers: [String] = []
    private var visibleDynamicTabItems: [AppSettings.ForumDynamicTabItem] = []

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.api = api
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        rebuildTabs(preservingIdentifier: nil)
        startObservingSettings()
        configureTabBarSurface()
    }

    deinit {
        if let settingsObservationToken {
            NotificationCenter.default.removeObserver(settingsObservationToken)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if isTabBarHiddenByScroll || shouldHideTabBarForCurrentContent {
            applyHiddenTabBarLayout()
        } else {
            applyVisibleTabBarLayout()
        }
    }

    func setTabBarHiddenByScroll(_ hidden: Bool, animated: Bool) {
        guard isTabBarHiddenByScroll != hidden else { return }
        isTabBarHiddenByScroll = hidden

        let updates = {
            if hidden {
                self.applyHiddenTabBarLayout()
            } else {
                self.applyVisibleTabBarLayout()
            }
            self.view.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.isTabBarHiddenByScroll == hidden else { return }
            self.tabBar.isUserInteractionEnabled = !hidden
            if hidden {
                self.applyHiddenTabBarLayout()
            }
            if !hidden {
                self.configureTabBarSurface()
                self.applyVisibleTabBarLayout()
            }
        }

        if !hidden {
            tabBar.isHidden = false
            tabBar.alpha = 1
            configureTabBarSurface()
        }
        tabBar.isUserInteractionEnabled = !hidden
        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: updates,
                completion: completion
            )
        } else {
            updates()
            completion(true)
        }
    }

    func configureTabBarSurface() {
        let themeStyle = AppSettings.shared.themeStyle
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = themeStyle == .systemDefault ? .systemBackground : themeStyle.contentBackgroundColor
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.35)
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.backgroundColor = appearance.backgroundColor
        tabBar.barTintColor = appearance.backgroundColor
        tabBar.tintColor = themeStyle.accentColor
        tabBar.isOpaque = true
        tabBar.isTranslucent = false
        tabBar.alpha = isTabBarHiddenByScroll ? 0 : 1
    }

    var visibleTabBarHeight: CGFloat {
        guard !isTabBarHiddenByScroll else { return 0 }
        return tabBarTotalHeight
    }

    var tabBarTotalHeight: CGFloat {
        return max(tabBar.bounds.height, tabBar.frame.height, 49 + view.safeAreaInsets.bottom)
    }

    private var shouldHideTabBarForCurrentContent: Bool {
        guard let navigationController = selectedViewController as? UINavigationController,
              let visibleViewController = navigationController.visibleViewController,
              visibleViewController !== navigationController.viewControllers.first
        else {
            return false
        }
        return visibleViewController.hidesBottomBarWhenPushed
    }

    private func applyHiddenTabBarLayout() {
        tabBar.isHidden = false
        tabBar.alpha = 0
        tabBar.transform = .identity
        tabBar.frame = tabBarFrame(hidden: true)
        tabBar.isUserInteractionEnabled = false
        applyBottomSafeAreaCompensation(hidden: true)
        expandSelectedContentIntoTabBarArea()
    }

    private func applyVisibleTabBarLayout() {
        tabBar.isHidden = false
        tabBar.alpha = 1
        tabBar.transform = .identity
        tabBar.frame = tabBarFrame(hidden: false)
        tabBar.isUserInteractionEnabled = true
        view.bringSubviewToFront(tabBar)
        applyBottomSafeAreaCompensation(hidden: false)
    }

    private func tabBarFrame(hidden: Bool) -> CGRect {
        let height = tabBarTotalHeight
        let y = hidden ? view.bounds.maxY : view.bounds.maxY - height
        return CGRect(x: 0, y: y, width: view.bounds.width, height: height)
    }

    private func expandSelectedContentIntoTabBarArea() {
        guard let selectedView = selectedViewController?.view else { return }
        if let contentContainer = selectedView.superview {
            contentContainer.clipsToBounds = false
            contentContainer.frame = view.bounds
            view.bringSubviewToFront(contentContainer)
            selectedView.frame = contentContainer.bounds
        } else {
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
            wrapperView.clipsToBounds = false
            wrapperView.frame = bounds
            contentView.frame = wrapperView.bounds
        } else {
            contentView.frame = bounds
        }
        contentView.clipsToBounds = false
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
    }

    private func applyBottomSafeAreaCompensation(hidden: Bool) {
        for navigationController in navigationControllers {
            applyBottomSafeAreaCompensation(hidden: hidden, to: navigationController)
            navigationController.viewControllers.forEach {
                applyBottomSafeAreaCompensation(hidden: hidden, to: $0)
            }
        }
    }

    private func applyBottomSafeAreaCompensation(hidden: Bool, to viewController: UIViewController) {
        let key = ObjectIdentifier(viewController)
        if hidden {
            if originalAdditionalSafeAreaInsets[key] == nil {
                originalAdditionalSafeAreaInsets[key] = viewController.additionalSafeAreaInsets
            }
            var compensatedInsets = originalAdditionalSafeAreaInsets[key] ?? .zero
            compensatedInsets.bottom -= tabBarTotalHeight
            viewController.additionalSafeAreaInsets = compensatedInsets
        } else if let originalInsets = originalAdditionalSafeAreaInsets.removeValue(forKey: key) {
            viewController.additionalSafeAreaInsets = originalInsets
        }
    }
}

private extension ForumTabBarController {
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

    func handleSettingsChanged() {
        configureTabBarSurface()
        let newVisibleItems = AppSettings.shared.forumVisibleDynamicTabItems
        guard newVisibleItems != visibleDynamicTabItems else { return }
        rebuildTabs(preservingIdentifier: selectedTabIdentifier())
    }

    func rebuildTabs(preservingIdentifier preferredIdentifier: String?) {
        applyBottomSafeAreaCompensation(hidden: false)

        let specs = buildTabSpecs()
        var controllers: [UINavigationController] = []
        var identifiers: [String] = []

        for (index, spec) in specs.enumerated() {
            let rootViewController = spec.makeViewController()
            rootViewController.title = spec.title

            let navigationController = UINavigationController(rootViewController: rootViewController)
            navigationController.delegate = self
            navigationController.tabBarItem = UITabBarItem(
                title: spec.title,
                image: UIImage(systemName: spec.symbolName),
                tag: index
            )
            navigationController.tabBarItem.accessibilityIdentifier = "forum.tab.\(spec.identifier)"
            controllers.append(navigationController)
            identifiers.append(spec.identifier)
        }

        navigationControllers = controllers
        tabIdentifiers = identifiers
        visibleDynamicTabItems = AppSettings.shared.forumVisibleDynamicTabItems

        if #available(iOS 18.0, *) {
            self.tabs = zip(specs, controllers).map { spec, navigationController in
                UITab(
                    title: spec.title,
                    image: UIImage(systemName: spec.symbolName),
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
        onNavigationControllersChanged?()
    }

    func selectedTabIdentifier() -> String? {
        guard selectedIndex >= 0, selectedIndex < tabIdentifiers.count else { return nil }
        return tabIdentifiers[selectedIndex]
    }

    func buildTabSpecs() -> [TabSpec] {
        var specs: [TabSpec] = [
            TabSpec(
                identifier: "home",
                title: String(localized: "tab.home"),
                symbolName: "house"
            ) { [api, authGate] in
                HomeViewController(api: api, authGate: authGate)
            },
        ]

        specs.append(contentsOf: AppSettings.shared.forumVisibleDynamicTabItems.map(dynamicTabSpec(for:)))

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

    func dynamicTabSpec(for item: AppSettings.ForumDynamicTabItem) -> TabSpec {
        TabSpec(
            identifier: item.rawValue,
            title: item.title,
            symbolName: item.symbolName
        ) { [api, authGate] in
            switch item {
            case .history:
                return BrowsingHistoryViewController(api: api, authGate: authGate)
            case .search:
                return SearchViewController(api: api)
            case .notifications:
                return NotificationsViewController(api: api, authGate: authGate)
            case .messages:
                let controller = MessagesViewController(api: api, authGate: authGate)
                controller.hidesBottomBarWhenPushed = false
                return controller
            case .bookmarks:
                return BookmarksViewController(api: api, authGate: authGate)
            }
        }
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
        navigationController.interactivePopGestureRecognizer?.isEnabled = navigationController.viewControllers.count > 1
            && !(viewController is TopicDetailViewController)
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
        table.backgroundColor = .systemGroupedBackground
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
        view.backgroundColor = .systemGroupedBackground
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

        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        var seen = Set<Int>()
        let uniqueIds = viewModel.topics.compactMap { topic -> Int? in
            guard seen.insert(topic.id).inserted else { return nil }
            return topic.id
        }
        snapshot.appendItems(uniqueIds, toSection: 0)
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

private final class TopicDetailNavigationAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let operation: UINavigationController.Operation
    private let detailOffset: CGFloat = 34
    private let listParallaxOffset: CGFloat = 12

    init(operation: UINavigationController.Operation) {
        self.operation = operation
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.24
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        switch operation {
        case .push:
            animatePush(fromView: fromView, toView: toView, context: transitionContext)
        case .pop:
            animatePop(fromView: fromView, toView: toView, context: transitionContext)
        default:
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }

    private func animatePush(
        fromView: UIView,
        toView: UIView,
        context: UIViewControllerContextTransitioning
    ) {
        let container = context.containerView
        guard let toViewController = context.viewController(forKey: .to) else {
            context.completeTransition(false)
            return
        }
        toView.frame = context.finalFrame(for: toViewController)
        toView.alpha = 0.96
        toView.transform = CGAffineTransform(translationX: detailOffset, y: 0)
        container.addSubview(toView)

        UIView.animate(
            withDuration: transitionDuration(using: context),
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            fromView.alpha = 0.98
            fromView.transform = CGAffineTransform(translationX: -self.listParallaxOffset, y: 0)
            toView.alpha = 1
            toView.transform = .identity
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            fromView.alpha = 1
            fromView.transform = .identity
            if !completed {
                toView.removeFromSuperview()
            }
            context.completeTransition(completed)
        }
    }

    private func animatePop(
        fromView: UIView,
        toView: UIView,
        context: UIViewControllerContextTransitioning
    ) {
        let container = context.containerView
        guard let toViewController = context.viewController(forKey: .to) else {
            context.completeTransition(false)
            return
        }
        toView.frame = context.finalFrame(for: toViewController)
        toView.alpha = 0.98
        toView.transform = CGAffineTransform(translationX: -listParallaxOffset, y: 0)
        container.insertSubview(toView, belowSubview: fromView)

        UIView.animate(
            withDuration: transitionDuration(using: context),
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            fromView.alpha = 0.96
            fromView.transform = CGAffineTransform(translationX: self.detailOffset, y: 0)
            toView.alpha = 1
            toView.transform = .identity
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            fromView.alpha = 1
            fromView.transform = .identity
            toView.alpha = 1
            toView.transform = .identity
            context.completeTransition(completed)
        }
    }
}
