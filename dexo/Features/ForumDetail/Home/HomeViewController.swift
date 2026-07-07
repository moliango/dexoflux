import Network
import UIKit

private enum HomeFABMode {
    case create
    case refresh
}

final class HomeViewController: ObservableViewController {
    private static let reloadTimeoutNanoseconds: UInt64 = 25_000_000_000
    private static let searchRowExpandedHeight: CGFloat = 40
    private static let categoryRowHeight: CGFloat = 36
    private static let filterRowHeight: CGFloat = 36
    private static let incomingTopicsBannerHeight: CGFloat = 64
    private static let cloudflareShieldSuppressionDuration: TimeInterval = 6
    private static let cloudflareForegroundAutoPresentationCooldown: TimeInterval = 10
    private static let headerVerticalSpacing: CGFloat = 8 + 6
    private static let headerBottomPadding: CGFloat = 8
    private static let baseTableTopSpacing: CGFloat = 8
    private static let xiaohongshuTableTopSpacing: CGFloat = 18

    private let api: DiscourseAPI
    private let viewModel: HomeViewModel
    private weak var authGate: AuthGating?
    private var categoryTabButtons: [Int?: UIButton] = [:]
    private var categoryTabOrder: [Int?] = []
    private var headerHeightConstraint: NSLayoutConstraint?
    private var searchRowHeightConstraint: NSLayoutConstraint?
    private var floatingActionButtonBottomConstraint: NSLayoutConstraint?
    private var isSearchRowCollapsed = false
    private var fabMode: HomeFABMode = .create
    private var isHomeTabBarHidden = false
    private var lastHomeScrollY: CGFloat?
    private var incomingTopicsPollTimer: Timer?
    private var cloudflareCompletionObservationToken: NSObjectProtocol?
    private var cloudflareChallengeObservationToken: NSObjectProtocol?
    private var cloudflareNeedsUserObservationToken: NSObjectProtocol?
    private var authObservationToken: NSObjectProtocol?
    private var settingsObservationToken: NSObjectProtocol?
    private var foregroundObservationToken: NSObjectProtocol?
    private var topicReloadTask: Task<Void, Never>?
    private var reloadTimeoutTask: Task<Void, Never>?
    private var incomingTopicsRetryTask: Task<Void, Never>?
    private var reloadSequence = 0
    private var lastAuthenticatedState: Bool?
    private var shouldShowCloudflareShieldButton = false
    private var isIncomingTopicsBannerVisible = false
    private var incomingTopicsUsesTopSpace = false
    private var cloudflareShieldSuppressedUntil: Date?
    private var cloudflareChallengeReloadSequence: Int?
    private var isPresentingCloudflareForegroundVerification = false
    private var pendingCloudflareForegroundVerification = false
    private var lastAutomaticCloudflareForegroundPresentationAt: Date?
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "dexo.home.network-monitor")
    private var lastNetworkStatus: NWPath.Status?

    private var expandedHeaderHeight: CGFloat {
        view.safeAreaInsets.top
            + 2
            + Self.searchRowExpandedHeight
            + Self.headerVerticalSpacing
            + Self.categoryRowHeight
            + Self.filterRowHeight
            + Self.headerBottomPadding
    }

    private var collapsedHeaderHeight: CGFloat {
        view.safeAreaInsets.top
            + 2
            + Self.headerVerticalSpacing
            + Self.categoryRowHeight
            + Self.filterRowHeight
            + Self.headerBottomPadding
    }

    private let headerContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGroupedBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let searchRowStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let searchButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "home.search.placeholder")
        config.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        config.imagePlacement = .leading
        config.imagePadding = 8
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 14, weight: .regular)
            return a
        }
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.backgroundColor = .secondarySystemGroupedBackground
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let notificationButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "bell", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        config.baseForegroundColor = .secondaryLabel
        let button = UIButton(configuration: config)
        button.accessibilityLabel = String(localized: "notifications.title")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let categoryManagerButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "line.3.horizontal", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        config.baseForegroundColor = .secondaryLabel
        let button = UIButton(configuration: config)
        button.accessibilityLabel = String(localized: "home.category_manager.title")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let categoryScrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let categoryStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let filterStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let filterButton: UIButton = {
        let button = UIButton(configuration: .plain())
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let categoryButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "home.filter.categories")
        config.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        config.imagePlacement = .trailing
        config.imagePadding = 3
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 8)
        config.background.backgroundColor = .secondarySystemGroupedBackground
        config.background.cornerRadius = 8
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            return a
        }
        let button = UIButton(configuration: config)
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(TopicCell.self, forCellReuseIdentifier: TopicCell.reuseIdentifier)
        tv.register(XiaohongshuTopicGridCell.self, forCellReuseIdentifier: XiaohongshuTopicGridCell.reuseIdentifier)
        tv.delegate = self
        tv.separatorStyle = .none
        tv.backgroundColor = .systemGroupedBackground
        tv.showsVerticalScrollIndicator = false
        tv.showsHorizontalScrollIndicator = false
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = TopicCell.estimatedHeight
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = .init(tableView: tableView) { [weak self] tableView, indexPath, topicId in
        guard let self else {
            return UITableViewCell()
        }
        if let rowIndex = Self.xiaohongshuRowIndex(from: topicId) {
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: XiaohongshuTopicGridCell.reuseIdentifier,
                for: indexPath
            ) as? XiaohongshuTopicGridCell else {
                return UITableViewCell()
            }
            let pair = self.xiaohongshuTopicPair(at: rowIndex)
            cell.configure(
                left: pair.left.map { self.xiaohongshuCardModel(for: $0) },
                right: pair.right.map { self.xiaohongshuCardModel(for: $0) }
            )
            cell.onTopicSelected = { [weak self] topicId in
                self?.openTopic(topicId)
            }
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(withIdentifier: TopicCell.reuseIdentifier, for: indexPath) as? TopicCell,
              let topic = self.viewModel.topics.first(where: { $0.id == topicId }) else {
            return UITableViewCell()
        }
        let baseURL = self.api.baseURL
        let avatarURL = AvatarImageLoader.url(
            from: self.viewModel.avatarTemplate(for: topic),
            baseURL: baseURL,
            size: 96
        )
        let category = self.viewModel.category(for: topic)
        let categoryColor: UIColor? = category.flatMap { Self.color(fromHex: $0.color) }
        cell.configure(
            with: topic,
            avatarURL: avatarURL,
            categoryName: self.viewModel.categoryDisplayName(for: category),
            categoryColor: categoryColor,
            tags: topic.tags ?? []
        )
        return cell
    }

    private var usesXiaohongshuCardLayout: Bool {
        AppSettings.shared.themeStyle == .xiaohongshu
    }

    private static func xiaohongshuRowIdentifier(for rowIndex: Int) -> Int {
        -(rowIndex + 1)
    }

    private static func xiaohongshuRowIndex(from identifier: Int) -> Int? {
        guard identifier < 0 else { return nil }
        return abs(identifier) - 1
    }

    private func xiaohongshuTopicPair(at rowIndex: Int) -> (left: DiscourseTopicList.Topic?, right: DiscourseTopicList.Topic?) {
        let leftIndex = rowIndex * 2
        guard viewModel.topics.indices.contains(leftIndex) else {
            return (nil, nil)
        }
        let rightIndex = leftIndex + 1
        let rightTopic = viewModel.topics.indices.contains(rightIndex) ? viewModel.topics[rightIndex] : nil
        return (viewModel.topics[leftIndex], rightTopic)
    }

    private func xiaohongshuCardModel(for topic: DiscourseTopicList.Topic) -> XiaohongshuTopicCardModel {
        let avatarURL = AvatarImageLoader.url(
            from: viewModel.avatarTemplate(for: topic),
            baseURL: api.baseURL,
            size: 96
        )
        let category = viewModel.category(for: topic)
        let categoryColor: UIColor? = category.flatMap { Self.color(fromHex: $0.color) }
        return XiaohongshuTopicCardModel(
            id: topic.id,
            title: topic.fancyTitle,
            excerpt: topic.excerpt,
            avatarURL: avatarURL,
            username: viewModel.username(for: topic),
            categoryName: viewModel.categoryDisplayName(for: category),
            categoryColor: categoryColor,
            tags: topic.tags ?? [],
            replyCount: max(topic.postsCount - 1, 0),
            views: topic.views,
            timeText: TopicCell.formatDate(topic.lastPostedAt ?? topic.createdAt)
        )
    }

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private let footerSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        return spinner
    }()

    private let emptyFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private let loginButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "home.login_prompt")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    private let floatingActionButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = AppSettings.shared.themeStyle.accentColor
        button.layer.cornerRadius = 28
        button.layer.cornerCurve = .continuous
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.22
        button.layer.shadowRadius = 10
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.accessibilityLabel = String(localized: "new_topic.title")
        return button
    }()

    private let cloudflareShieldButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        button.setImage(UIImage(systemName: "shield.lefthalf.filled", withConfiguration: config), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.18
        button.layer.shadowRadius = 9
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.accessibilityLabel = String(localized: "settings.network.cloudflare_verify")
        button.isHidden = true
        return button
    }()

    private let incomingTopicsHeaderView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        view.isHidden = true
        view.accessibilityElementsHidden = true
        return view
    }()

    private let incomingTopicsButton: IncomingTopicsBannerView = {
        let button = IncomingTopicsBannerView()
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        return rc
    }()

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.api = api
        self.viewModel = HomeViewModel(api: api)
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCategorySelectionIndicators()
        updateHeaderHeight(animated: false)

        hideHomeScrollIndicators()
        updateIncomingTopicsHeader()
        updateTableInsets()
        floatingActionButtonBottomConstraint?.constant = -currentBottomChromeHeight - 20
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        tableView.tableFooterView = emptyFooterView
        tableView.refreshControl = refreshControl
        tableView.contentInsetAdjustmentBehavior = .never
        hideHomeScrollIndicators()

        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        incomingTopicsHeaderView.addSubview(incomingTopicsButton)
        view.addSubview(tableView)
        view.addSubview(headerContainer)
        view.addSubview(incomingTopicsHeaderView)

        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)
        view.addSubview(loginButton)
        view.addSubview(floatingActionButton)
        view.addSubview(cloudflareShieldButton)

        setupHeader()
        applyThemeStyle()
        updateFloatingActionButton(animated: false)

        let fabBottomConstraint = floatingActionButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -currentBottomChromeHeight - 20)
        floatingActionButtonBottomConstraint = fabBottomConstraint
        let shieldCenterYConstraint = cloudflareShieldButton.centerYAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.centerYAnchor,
            constant: 72
        )
        shieldCenterYConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            headerContainer.topAnchor.constraint(equalTo: view.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            incomingTopicsHeaderView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 6),
            incomingTopicsHeaderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            incomingTopicsHeaderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            incomingTopicsHeaderView.heightAnchor.constraint(equalToConstant: Self.incomingTopicsBannerHeight),

            incomingTopicsButton.topAnchor.constraint(equalTo: incomingTopicsHeaderView.topAnchor, constant: 6),
            incomingTopicsButton.leadingAnchor.constraint(equalTo: incomingTopicsHeaderView.leadingAnchor, constant: 18),
            incomingTopicsButton.trailingAnchor.constraint(equalTo: incomingTopicsHeaderView.trailingAnchor, constant: -18),
            incomingTopicsButton.heightAnchor.constraint(equalToConstant: 52),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loginButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),

            floatingActionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            fabBottomConstraint,
            floatingActionButton.widthAnchor.constraint(equalToConstant: 56),
            floatingActionButton.heightAnchor.constraint(equalToConstant: 56),

            cloudflareShieldButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            shieldCenterYConstraint,
            cloudflareShieldButton.bottomAnchor.constraint(lessThanOrEqualTo: floatingActionButton.topAnchor, constant: -28),
            cloudflareShieldButton.widthAnchor.constraint(equalToConstant: 50),
            cloudflareShieldButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        headerHeightConstraint = headerContainer.heightAnchor.constraint(equalToConstant: expandedHeaderHeight)
        headerHeightConstraint?.isActive = true

        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        notificationButton.addTarget(self, action: #selector(notificationsTapped), for: .touchUpInside)
        categoryManagerButton.addTarget(self, action: #selector(categoryManagerTapped), for: .touchUpInside)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        floatingActionButton.addTarget(self, action: #selector(fabTapped), for: .touchUpInside)
        cloudflareShieldButton.addTarget(self, action: #selector(cloudflareShieldTapped), for: .touchUpInside)
        incomingTopicsButton.addTarget(self, action: #selector(incomingTopicsTapped), for: .touchUpInside)
        lastAuthenticatedState = AuthManager.shared.isAuthenticated(for: api.baseURL)
        startObservingCloudflareVerification()
        startObservingAuthChanges()
        startObservingSettingsChanges()
        startObservingForeground()
        startMonitoringNetwork()

        reloadTopics()
        Task {
            await api.loadOrFetchEmojiMap()
        }
    }

    @MainActor deinit {
        if let cloudflareCompletionObservationToken {
            NotificationCenter.default.removeObserver(cloudflareCompletionObservationToken)
        }
        if let cloudflareChallengeObservationToken {
            NotificationCenter.default.removeObserver(cloudflareChallengeObservationToken)
        }
        if let cloudflareNeedsUserObservationToken {
            NotificationCenter.default.removeObserver(cloudflareNeedsUserObservationToken)
        }
        if let authObservationToken {
            NotificationCenter.default.removeObserver(authObservationToken)
        }
        if let settingsObservationToken {
            NotificationCenter.default.removeObserver(settingsObservationToken)
        }
        if let foregroundObservationToken {
            NotificationCenter.default.removeObserver(foregroundObservationToken)
        }
        topicReloadTask?.cancel()
        reloadTimeoutTask?.cancel()
        incomingTopicsRetryTask?.cancel()
        pathMonitor.cancel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        lastHomeScrollY = tableView.contentOffset.y + tableView.contentInset.top
        updateTabBarVisibilityForCurrentScroll(animated: false)
        reconcileCloudflareShieldButtonVisibility(animated: false)
        startIncomingTopicsPolling()
        reloadAfterBecomingVisibleIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPendingCloudflareVerificationIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        setHomeTabBarHidden(false, animated: animated)
        stopIncomingTopicsPolling()
    }

    private func startObservingCloudflareVerification() {
        cloudflareCompletionObservationToken = NotificationCenter.default.addObserver(
            forName: DiscourseAPI.cloudflareVerificationCompletedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareVerificationCompleted(notification)
        }
        cloudflareChallengeObservationToken = NotificationCenter.default.addObserver(
            forName: DiscourseAPI.cloudflareChallengeDetectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareChallengeDetected(notification)
        }
        cloudflareNeedsUserObservationToken = NotificationCenter.default.addObserver(
            forName: CloudflareBackgroundVerificationService.needsUserInteractionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareNeedsUserInteraction(notification)
        }
    }

    private func startObservingAuthChanges() {
        authObservationToken = NotificationCenter.default.addObserver(
            forName: DexoObservableObject.didChangeNotification,
            object: AuthManager.shared,
            queue: .main
        ) { [weak self] _ in
            self?.handleAuthChanged()
        }
    }

    private func startObservingSettingsChanges() {
        settingsObservationToken = NotificationCenter.default.addObserver(
            forName: DexoObservableObject.didChangeNotification,
            object: AppSettings.shared,
            queue: .main
        ) { [weak self] _ in
            self?.handleSettingsChanged()
        }
    }

    private func startObservingForeground() {
        foregroundObservationToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadAfterBecomingVisibleIfNeeded()
        }
    }

    private func startMonitoringNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handleNetworkStatus(path.status)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func handleCloudflareVerificationCompleted(_ notification: Notification) {
        guard let baseURL = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURL) == normalizedBaseURL(api.baseURL) else { return }
        let shouldReloadTopics = shouldReloadTopicsAfterCloudflareVerification()
        logCloudflareState("verification completed base=\(baseURL) reloadTopics=\(shouldReloadTopics)")
        isPresentingCloudflareForegroundVerification = false
        pendingCloudflareForegroundVerification = false
        if shouldReloadTopics {
            cloudflareShieldSuppressedUntil = nil
        } else {
            suppressCloudflareShieldTemporarily()
        }
        cloudflareChallengeReloadSequence = nil
        setCloudflareShieldButtonVisible(false, animated: true)
        reloadTopicsAfterCloudflareVerificationIfNeeded(shouldReloadTopics)
        retryIncomingTopicsAfterCloudflareIfNeeded()
    }

    private func handleCloudflareChallengeDetected(_ notification: Notification) {
        guard let baseURL = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURL) == normalizedBaseURL(api.baseURL) else { return }
        guard !isCloudflareShieldSuppressed() else {
            logCloudflareState("challenge ignored while shield is suppressed base=\(baseURL)")
            cloudflareChallengeReloadSequence = nil
            setCloudflareShieldButtonVisible(false, animated: true)
            return
        }
        if isPresentingCloudflareForegroundVerification {
            logCloudflareState("challenge ignored because foreground verification is already presented base=\(baseURL)")
            return
        }
        cloudflareChallengeReloadSequence = nil
        setCloudflareShieldButtonVisible(false, animated: true)
        let responseURL = notification.userInfo?[DiscourseAPI.cloudflareResponseURLUserInfoKey] as? URL
        logCloudflareState(
            "challenge detected base=\(baseURL) response=\(responseURL?.absoluteString ?? "none")"
        )
        if shouldAutomaticallyPresentCloudflareVerification() {
            requestAutomaticCloudflareForegroundVerification(reason: "challenge_detected")
            return
        }
        CloudflareBackgroundVerificationService.shared.ensureInBackground(
            baseURL: baseURL,
            reason: "home_challenge",
            responseURL: responseURL
        )
    }

    private func handleCloudflareNeedsUserInteraction(_ notification: Notification) {
        guard let baseURL = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURL) == normalizedBaseURL(api.baseURL) else { return }
        guard !isCloudflareShieldSuppressed() else {
            logCloudflareState("needs-user ignored while shield is suppressed base=\(baseURL)")
            cloudflareChallengeReloadSequence = nil
            setCloudflareShieldButtonVisible(false, animated: true)
            return
        }
        if isPresentingCloudflareForegroundVerification {
            logCloudflareState("needs-user ignored because foreground verification is already presented base=\(baseURL)")
            return
        }
        let responseURL = notification.userInfo?[DiscourseAPI.cloudflareResponseURLUserInfoKey] as? URL
        logCloudflareState(
            "background verification needs user; showing shield base=\(baseURL) response=\(responseURL?.absoluteString ?? "none")"
        )
        if shouldAutomaticallyPresentCloudflareVerification() {
            requestAutomaticCloudflareForegroundVerification(reason: "needs_user_interaction")
            return
        }
        cloudflareChallengeReloadSequence = reloadSequence
        setCloudflareShieldButtonVisible(true, animated: true)
    }

    private func suppressCloudflareShieldTemporarily() {
        cloudflareShieldSuppressedUntil = Date().addingTimeInterval(Self.cloudflareShieldSuppressionDuration)
    }

    private func isCloudflareShieldSuppressed(now: Date = Date()) -> Bool {
        guard let suppressedUntil = cloudflareShieldSuppressedUntil else { return false }
        if now < suppressedUntil {
            return true
        }
        cloudflareShieldSuppressedUntil = nil
        return false
    }

    private func setCloudflareShieldButtonVisible(_ visible: Bool, animated: Bool) {
        guard shouldShowCloudflareShieldButton != visible else {
            updateCloudflareShieldButtonVisibility(animated: animated)
            return
        }
        logCloudflareState("shield visibility changed visible=\(visible) animated=\(animated)")
        shouldShowCloudflareShieldButton = visible
        updateCloudflareShieldButtonVisibility(animated: animated)
    }

    private func updateCloudflareShieldButtonVisibility(animated: Bool) {
        let isVisible = shouldShowCloudflareShieldButton
        let updates = {
            self.cloudflareShieldButton.alpha = isVisible ? 1 : 0
        }
        let completion: (Bool) -> Void = { _ in
            self.cloudflareShieldButton.isHidden = !self.shouldShowCloudflareShieldButton
        }

        if isVisible {
            cloudflareShieldButton.isHidden = false
        }

        guard animated else {
            updates()
            completion(true)
            return
        }

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
            animations: updates,
            completion: completion
        )
    }

    private func reconcileCloudflareShieldButtonVisibility(animated: Bool) {
        if viewModel.requiresLogin {
            if shouldShowCloudflareShieldButton {
                logCloudflareState("shield hidden because login is required")
            }
            cloudflareChallengeReloadSequence = nil
            setCloudflareShieldButtonVisible(false, animated: animated)
            return
        }

        if isCloudflareShieldSuppressed() {
            if shouldShowCloudflareShieldButton {
                logCloudflareState("shield hidden because success suppression window is active")
            }
            cloudflareChallengeReloadSequence = nil
            setCloudflareShieldButtonVisible(false, animated: animated)
            return
        }

        guard !viewModel.isLoading else {
            updateCloudflareShieldButtonVisibility(animated: animated)
            return
        }

        let hasCurrentChallenge = shouldShowCloudflareShieldButton
            && cloudflareChallengeReloadSequence == reloadSequence
        if hasCurrentChallenge {
            updateCloudflareShieldButtonVisibility(animated: animated)
        } else {
            if shouldShowCloudflareShieldButton {
                logCloudflareState(
                    "shield hidden because challenge sequence is stale current=\(reloadSequence) challenge=\(cloudflareChallengeReloadSequence.map(String.init) ?? "none")"
                )
            }
            cloudflareChallengeReloadSequence = nil
            setCloudflareShieldButtonVisible(false, animated: animated)
        }
    }

    private func logCloudflareState(_ message: String) {
        DohDebugLog.record("home \(message) sequence=\(reloadSequence)", subsystem: "CF")
    }

    private func handleAuthChanged() {
        let isAuthenticated = AuthManager.shared.isAuthenticated(for: api.baseURL)
        guard let previous = lastAuthenticatedState else {
            lastAuthenticatedState = isAuthenticated
            return
        }
        guard previous != isAuthenticated else { return }
        lastAuthenticatedState = isAuthenticated
        reloadTopics(resetCategoryMetadata: true)
    }

    private func handleNetworkStatus(_ status: NWPath.Status) {
        let previous = lastNetworkStatus
        lastNetworkStatus = status
        guard let previous, previous != .satisfied, status == .satisfied else { return }
        recoverTransportAndReload()
    }

    private func reloadAfterBecomingVisibleIfNeeded() {
        guard isViewLoaded, view.window != nil, !viewModel.isLoading else { return }
        guard viewModel.topics.isEmpty || viewModel.errorMessage != nil else { return }
        recoverTransportAndReload()
    }

    private func recoverTransportAndReload(resetCategoryMetadata: Bool = false) {
        api.resetSession()
        LightweightDohProxyService.shared.clearCache()
        reloadTopics(resetCategoryMetadata: resetCategoryMetadata)
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private func setupHeader() {
        searchRowStackView.addArrangedSubview(searchButton)
        searchRowStackView.addArrangedSubview(notificationButton)

        categoryScrollView.addSubview(categoryStackView)
        headerContainer.addSubview(searchRowStackView)
        headerContainer.addSubview(categoryScrollView)
        headerContainer.addSubview(categoryManagerButton)
        headerContainer.addSubview(filterStackView)

        NSLayoutConstraint.activate([
            searchRowStackView.topAnchor.constraint(equalTo: headerContainer.safeAreaLayoutGuide.topAnchor, constant: 2),
            searchRowStackView.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            searchRowStackView.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),

            searchButton.heightAnchor.constraint(equalToConstant: 40),
            notificationButton.widthAnchor.constraint(equalToConstant: 40),
            notificationButton.heightAnchor.constraint(equalToConstant: 40),

            categoryScrollView.topAnchor.constraint(equalTo: searchRowStackView.bottomAnchor, constant: 8),
            categoryScrollView.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            categoryScrollView.trailingAnchor.constraint(equalTo: categoryManagerButton.leadingAnchor, constant: -4),
            categoryScrollView.heightAnchor.constraint(equalToConstant: 36),

            categoryManagerButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -10),
            categoryManagerButton.centerYAnchor.constraint(equalTo: categoryScrollView.centerYAnchor),
            categoryManagerButton.widthAnchor.constraint(equalToConstant: 36),
            categoryManagerButton.heightAnchor.constraint(equalToConstant: 36),

            categoryStackView.topAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.topAnchor),
            categoryStackView.leadingAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            categoryStackView.trailingAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            categoryStackView.bottomAnchor.constraint(equalTo: categoryScrollView.contentLayoutGuide.bottomAnchor),
            categoryStackView.heightAnchor.constraint(equalTo: categoryScrollView.frameLayoutGuide.heightAnchor),

            filterStackView.topAnchor.constraint(equalTo: categoryScrollView.bottomAnchor, constant: 6),
            filterStackView.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 12),
            filterStackView.trailingAnchor.constraint(lessThanOrEqualTo: headerContainer.trailingAnchor, constant: -12),
            filterStackView.heightAnchor.constraint(equalToConstant: 36),
        ])
        searchRowHeightConstraint = searchRowStackView.heightAnchor.constraint(equalToConstant: Self.searchRowExpandedHeight)
        searchRowHeightConstraint?.isActive = true

        setupFilterBar()
        rebuildCategoryTabs()
        hideHomeScrollIndicators()
    }

    private func hideHomeScrollIndicators() {
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        categoryScrollView.showsVerticalScrollIndicator = false
        categoryScrollView.showsHorizontalScrollIndicator = false
    }

    private func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        let pageBackground: UIColor = themeStyle == .systemDefault ? .systemGroupedBackground : themeStyle.mutedContentBackgroundColor
        view.backgroundColor = pageBackground
        tableView.backgroundColor = pageBackground
        tableView.estimatedRowHeight = usesXiaohongshuCardLayout
            ? XiaohongshuTopicGridCell.estimatedHeight
            : TopicCell.estimatedHeight
        headerContainer.backgroundColor = pageBackground
        searchButton.backgroundColor = themeStyle.topicChipBackgroundColor
        floatingActionButton.backgroundColor = themeStyle.accentColor
        floatingActionButton.layer.shadowColor = themeStyle.accentColor.cgColor
        incomingTopicsButton.applyThemeStyle()
    }

    private func setupFilterBar() {
        filterStackView.arrangedSubviews.forEach { view in
            filterStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        filterStackView.addArrangedSubview(filterButton)
        filterStackView.addArrangedSubview(categoryButton)
        filterButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        categoryButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        updateFilterButton()
    }

    private func applyDropdownStyle(to button: UIButton, title: String, selected: Bool = false) {
        let themeStyle = AppSettings.shared.themeStyle
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        config.imagePlacement = .trailing
        config.imagePadding = 3
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 8)
        config.background.backgroundColor = selected ? themeStyle.accentColor.withAlphaComponent(0.14) : themeStyle.topicChipBackgroundColor
        config.background.cornerRadius = 8
        config.baseForegroundColor = selected ? themeStyle.accentColor : .label
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            return a
        }
        button.configuration = config
    }

    private func makeCategoryTabButton(title: String, categoryId: Int?) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 2, bottom: 6, trailing: 2)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return a
        }
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in
            self?.selectCategory(categoryId)
        }, for: .touchUpInside)
        return button
    }

    override func updateUI() {
        applyThemeStyle()
        // Login-required state
        if viewModel.requiresLogin {
            errorLabel.text = viewModel.errorMessage
            errorLabel.isHidden = false
            loginButton.isHidden = false
            tableView.isHidden = true
            headerContainer.isHidden = true
            floatingActionButton.isHidden = true
            setIncomingTopicsBannerVisible(false, animated: false)
            reconcileCloudflareShieldButtonVisibility(animated: false)
            activityIndicator.stopAnimating()
            return
        }

        loginButton.isHidden = true
        tableView.isHidden = false
        headerContainer.isHidden = false
        floatingActionButton.isHidden = false
        reconcileCloudflareShieldButtonVisibility(animated: false)

        categoryButton.menu = UIMenu(title: "", children: buildCategoryMenuElements())
        updateCategoryButton()
        rebuildCategoryTabs()
        updateFilterButton()
        updateIncomingTopicsHeader()
        // Show non-login errors (e.g. rate limit) when topic list is empty
        if let error = viewModel.errorMessage, viewModel.topics.isEmpty {
            errorLabel.text = error
            errorLabel.isHidden = false
        } else {
            errorLabel.isHidden = true
        }
        if viewModel.isBlockedByCloudflare, viewModel.topics.isEmpty {
            requestAutomaticCloudflareForegroundVerification(reason: "home_error_state")
        }

        applyTopicSnapshot()

        if viewModel.isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        if viewModel.isLoadingMore {
            tableView.tableFooterView = footerSpinner
            footerSpinner.startAnimating()
        } else {
            footerSpinner.stopAnimating()
            tableView.tableFooterView = emptyFooterView
        }
    }

    private func applyTopicSnapshot(animatingDifferences: Bool? = nil) {
        let itemIdentifiers = topicSnapshotItemIdentifiers()
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(itemIdentifiers, toSection: 0)

        prefetchAvatarImages(for: viewModel.topics)
        let currentSnapshot = dataSource.snapshot()
        let currentIds = currentSnapshot.itemIdentifiers
        let needsInitialSnapshot = currentSnapshot.sectionIdentifiers.isEmpty
        let visibleExistingIds = Set(
            tableView.indexPathsForVisibleRows?.compactMap { dataSource.itemIdentifier(for: $0) } ?? []
        )
        let idsNeedingReconfigure = itemIdentifiers.filter { visibleExistingIds.contains($0) }
        let shouldAnimateSnapshot = animatingDifferences ?? (
            view.window != nil
                && !tableView.isDragging
                && !tableView.isDecelerating
        )

        if !needsInitialSnapshot, currentIds == itemIdentifiers {
            if !idsNeedingReconfigure.isEmpty {
                var updatedSnapshot = currentSnapshot
                updatedSnapshot.reconfigureItems(idsNeedingReconfigure)
                dataSource.apply(updatedSnapshot, animatingDifferences: false)
            }
        } else {
            if !idsNeedingReconfigure.isEmpty {
                snapshot.reconfigureItems(idsNeedingReconfigure)
            }
            dataSource.apply(snapshot, animatingDifferences: shouldAnimateSnapshot)
        }
    }

    private func topicSnapshotItemIdentifiers() -> [Int] {
        if usesXiaohongshuCardLayout {
            let rowCount = Int(ceil(Double(viewModel.topics.count) / 2.0))
            return (0..<rowCount).map(Self.xiaohongshuRowIdentifier(for:))
        }

        var seen = Set<Int>()
        return viewModel.topics.compactMap { topic -> Int? in
            guard seen.insert(topic.id).inserted else { return nil }
            return topic.id
        }
    }

    private func reloadTopics(resetCategoryMetadata: Bool = false, detectIncoming: Bool = true) {
        topicReloadTask?.cancel()
        reloadTimeoutTask?.cancel()
        incomingTopicsRetryTask?.cancel()
        incomingTopicsRetryTask = nil
        reloadSequence += 1
        let sequence = reloadSequence

        if resetCategoryMetadata {
            viewModel.resetCategoryMetadata(clearSelection: true)
        }

        reloadTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.reloadTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.handleReloadTimeout(sequence: sequence)
            }
        }

        topicReloadTask = Task { [weak self] in
            guard let self else { return }
            await self.viewModel.loadTopics()
            guard !Task.isCancelled else { return }
            if detectIncoming {
                await self.viewModel.detectIncomingTopics()
            }
            await MainActor.run {
                self.finishReload(sequence: sequence)
            }
        }
    }

    private func handleReloadTimeout(sequence: Int) {
        guard sequence == reloadSequence else { return }
        topicReloadTask?.cancel()
        topicReloadTask = nil
        reloadTimeoutTask = nil
        viewModel.finishLoadingAfterTimeout(message: String(localized: "error.network_timeout"))
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        reconcileCloudflareShieldButtonVisibility(animated: false)
    }

    private func finishReload(sequence: Int) {
        guard sequence == reloadSequence else { return }
        reloadTimeoutTask?.cancel()
        reloadTimeoutTask = nil
        topicReloadTask = nil
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        reconcileCloudflareShieldButtonVisibility(animated: true)
    }

    private func selectListMode(_ mode: HomeListMode) {
        guard viewModel.listMode != mode else { return }
        viewModel.listMode = mode
        updateFilterButton()
        reloadTopics()
    }

    @objc private func searchTapped() {
        let searchVC = SearchViewController(api: api)
        navigationController?.pushViewController(searchVC, animated: true)
    }

    @objc private func notificationsTapped() {
        let notificationsVC = NotificationsViewController(api: api, authGate: authGate)
        notificationsVC.onTopicSelected = { [weak self] topicId in
            guard let self else { return }
            let detailVC = TopicDetailViewController(api: self.api, topicId: topicId)
            self.navigationController?.pushViewController(detailVC, animated: true)
        }
        let nav = UINavigationController(rootViewController: notificationsVC)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(nav, animated: true)
    }

    @objc private func categoryManagerTapped() {
        let manager = CategoryTabManagerViewController(
            categories: viewModel.allSelectableCategories(),
            pinnedCategoryIds: AppSettings.shared.homePinnedCategoryIds,
            displayNameProvider: { [weak self] category in
                self?.viewModel.categoryDisplayName(for: category) ?? category.name
            },
            parentNameProvider: { [weak self] category in
                guard let parentId = category.parentCategoryId,
                      let parent = self?.viewModel.category(id: parentId)
                else { return nil }
                return self?.viewModel.categoryDisplayName(for: parent) ?? parent.name
            },
            colorProvider: { [weak self] category in
                self?.viewModel.category(id: category.id).flatMap { Self.color(fromHex: $0.color) }
                    ?? Self.color(fromHex: category.color)
            }
        )
        manager.onPinnedCategoryIdsChanged = { [weak self] ids in
            AppSettings.shared.homePinnedCategoryIds = ids
            self?.rebuildCategoryTabs()
        }
        let nav = UINavigationController(rootViewController: manager)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(nav, animated: true)
    }

    @objc private func pullToRefresh() {
        revealHeaderForTopRefresh(animated: true)
        reloadTopics()
    }

    @objc private func incomingTopicsTapped() {
        setHomeTabBarHidden(false, animated: true)
        incomingTopicsRetryTask?.cancel()
        incomingTopicsRetryTask = nil
        Task {
            await viewModel.loadIncomingTopics()
            let topOffset = CGPoint(x: 0, y: -tableView.contentInset.top)
            tableView.setContentOffset(topOffset, animated: true)
        }
    }

    private func retryIncomingTopicsAfterCloudflareIfNeeded() {
        guard viewModel.shouldRetryIncomingTopicsAfterCloudflare,
              !viewModel.incomingTopicIds.isEmpty
        else { return }
        logCloudflareState("scheduling incoming topics retry after verification ids=\(viewModel.incomingTopicIds)")
        incomingTopicsRetryTask?.cancel()
        incomingTopicsRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.viewModel.loadIncomingTopics()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.incomingTopicsRetryTask = nil
                self.updateIncomingTopicsHeader()
                self.logCloudflareState("incoming topics retry completed remainingIds=\(self.viewModel.incomingTopicIds)")
                if self.viewModel.incomingTopicIds.isEmpty {
                    let topOffset = CGPoint(x: 0, y: -self.tableView.contentInset.top)
                    self.tableView.setContentOffset(topOffset, animated: true)
                }
            }
        }
    }

    private func shouldReloadTopicsAfterCloudflareVerification() -> Bool {
        viewModel.topics.isEmpty || viewModel.isBlockedByCloudflare || viewModel.errorMessage != nil
    }

    private func reloadTopicsAfterCloudflareVerificationIfNeeded(_ shouldReload: Bool) {
        guard shouldReload else { return }
        logCloudflareState("scheduling topics reload after verification")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.isViewLoaded, self.view.window != nil else { return }
                self.logCloudflareState("reloading topics after verification")
                self.recoverTransportAndReload()
            }
        }
    }

    @objc private func pollIncomingTopics() {
        Task {
            await viewModel.detectIncomingTopics()
        }
    }

    @objc private func fabTapped() {
        switch fabMode {
        case .create:
            openNewTopicComposer()
        case .refresh:
            refreshFromFloatingActionButton()
        }
    }

    @objc private func cloudflareShieldTapped() {
        logCloudflareState("shield tapped; presenting foreground verification")
        presentCloudflareVerification(autoTriggered: false)
    }

    private func shouldAutomaticallyPresentCloudflareVerification(now: Date = Date()) -> Bool {
        guard viewModel.topics.isEmpty,
              !viewModel.requiresLogin,
              !isCloudflareShieldSuppressed(now: now)
        else { return false }
        if let lastAutomaticCloudflareForegroundPresentationAt,
           now.timeIntervalSince(lastAutomaticCloudflareForegroundPresentationAt) < Self.cloudflareForegroundAutoPresentationCooldown {
            return false
        }
        return true
    }

    private func presentPendingCloudflareVerificationIfNeeded() {
        guard pendingCloudflareForegroundVerification else { return }
        guard shouldAutomaticallyPresentCloudflareVerification() else {
            pendingCloudflareForegroundVerification = false
            return
        }
        presentCloudflareVerification(autoTriggered: true)
    }

    @discardableResult
    private func requestAutomaticCloudflareForegroundVerification(reason: String) -> Bool {
        guard shouldAutomaticallyPresentCloudflareVerification() else { return false }
        cloudflareChallengeReloadSequence = reloadSequence
        if pendingCloudflareForegroundVerification {
            schedulePendingCloudflareVerificationRetry()
            return true
        }
        pendingCloudflareForegroundVerification = true
        logCloudflareState("foreground verification requested reason=\(reason)")
        schedulePendingCloudflareVerificationRetry()
        return true
    }

    private func schedulePendingCloudflareVerificationRetry() {
        DispatchQueue.main.async { [weak self] in
            self?.presentPendingCloudflareVerificationIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.presentPendingCloudflareVerificationIfNeeded()
        }
    }

    @discardableResult
    private func presentCloudflareVerification(autoTriggered: Bool) -> Bool {
        guard !isPresentingCloudflareForegroundVerification else {
            logCloudflareState("foreground verification skipped because verification is already presented")
            return false
        }
        guard let presenter = topMostCloudflareVerificationPresenter(),
              !presenter.isBeingDismissed,
              presenter.view.window != nil
        else {
            logCloudflareState("foreground verification deferred because presenter is unavailable")
            if autoTriggered {
                pendingCloudflareForegroundVerification = true
            }
            return false
        }
        guard let baseURL = URL(string: api.baseURL) else {
            logCloudflareState("foreground verification skipped because base URL is invalid")
            return false
        }
        guard view.window != nil else {
            logCloudflareState("foreground verification deferred because Home is not in a window")
            if autoTriggered {
                pendingCloudflareForegroundVerification = true
            }
            return false
        }
        pendingCloudflareForegroundVerification = false
        isPresentingCloudflareForegroundVerification = true
        setCloudflareShieldButtonVisible(false, animated: true)
        let vc = CloudflareVerificationViewController(
            baseURL: baseURL,
            autoDismissOnSuccess: true,
            onFinish: { [weak self] in
                self?.isPresentingCloudflareForegroundVerification = false
                self?.pendingCloudflareForegroundVerification = false
            }
        )
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = self
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        presenter.present(nav, animated: true) { [weak self] in
            if autoTriggered {
                self?.lastAutomaticCloudflareForegroundPresentationAt = Date()
            }
        }
        return true
    }

    private func topMostCloudflareVerificationPresenter() -> UIViewController? {
        guard view.window != nil else { return nil }

        var presenter: UIViewController = self
        while let parent = presenter.parent {
            presenter = parent
        }

        while let presented = presenter.presentedViewController {
            if isCloudflareVerificationPresentation(presented) {
                return nil
            }
            if presented.isBeingDismissed {
                break
            }
            presenter = presented
        }

        return presenter
    }

    private func isCloudflareVerificationPresentation(_ controller: UIViewController) -> Bool {
        if controller is CloudflareVerificationViewController {
            return true
        }
        if let nav = controller as? UINavigationController,
           nav.viewControllers.first is CloudflareVerificationViewController {
            return true
        }
        return false
    }

    private func openNewTopicComposer() {
        let presentComposer = { [weak self] in
            guard let self else { return }
            let composer = NewTopicComposerViewController(
                api: self.api,
                categories: self.viewModel.categories,
                initialCategoryId: self.viewModel.selectedCategoryId
            )
            composer.onTopicCreated = { [weak self] topicId in
                guard let self else { return }
                self.reloadTopics()
                let detailVC = TopicDetailViewController(api: self.api, topicId: topicId)
                self.navigationController?.pushViewController(detailVC, animated: true)
            }
            let nav = UINavigationController(rootViewController: composer)
            self.present(nav, animated: true)
        }
        if let authGate {
            authGate.requireAuth(then: presentComposer)
        } else {
            presentComposer()
        }
    }

    private func refreshFromFloatingActionButton() {
        setFABMode(.create, animated: true)
        setHomeTabBarHidden(false, animated: true)
        revealHeaderForTopRefresh(animated: true)
        reloadTopics()
    }

    @objc private func loginTapped() {
        authGate?.requireAuth { [weak self] in
            guard let self else { return }
            self.reloadTopics(resetCategoryMetadata: true)
        }
    }

    private func updateCategoryButton() {
        let selected = viewModel.selectedCategory()
        let title = viewModel.categoryDisplayName(for: selected) ?? String(localized: "home.filter.categories")
        applyDropdownStyle(to: categoryButton, title: title, selected: selected != nil)
        categoryButton.sizeToFit()
    }

    private func updateFilterButton() {
        filterButton.menu = UIMenu(title: "", children: buildFilterMenuElements())
        applyDropdownStyle(to: filterButton, title: title(for: viewModel.listMode), selected: true)
    }

    private func prefetchAvatarImages(for topics: [DiscourseTopicList.Topic]) {
        let urls = topics
            .prefix(60)
            .compactMap { topic in
                AvatarImageLoader.url(
                    from: viewModel.avatarTemplate(for: topic),
                    baseURL: api.baseURL,
                    size: 96
                )
            }
        AvatarImageLoader.prefetch(urls: urls)
    }

    private func updateIncomingTopicsHeader() {
        let count = viewModel.incomingTopicIds.count
        guard viewModel.listMode == .latest, count > 0 else {
            setIncomingTopicsBannerVisible(false, animated: view.window != nil)
            updateIncomingTopicsPlacement(animated: false)
            return
        }

        incomingTopicsButton.configure(
            title: String.localizedStringWithFormat(String(localized: "home.incoming_topics %lld"), Int64(count)),
            isLoading: viewModel.isLoadingIncomingTopics
        )
        incomingTopicsButton.isEnabled = !viewModel.isLoadingIncomingTopics
        setIncomingTopicsBannerVisible(true, animated: view.window != nil)
        updateIncomingTopicsPlacement(animated: view.window != nil)
    }

    private func setIncomingTopicsBannerVisible(_ visible: Bool, animated: Bool) {
        if !visible {
            setIncomingTopicsUsesTopSpace(false)
        }
        guard isIncomingTopicsBannerVisible != visible else {
            if visible {
                incomingTopicsHeaderView.isHidden = false
                incomingTopicsHeaderView.accessibilityElementsHidden = false
                incomingTopicsHeaderView.alpha = 1
                incomingTopicsHeaderView.transform = .identity
            }
            return
        }

        isIncomingTopicsBannerVisible = visible
        incomingTopicsHeaderView.accessibilityElementsHidden = !visible

        let hiddenTransform = CGAffineTransform(translationX: 0, y: -6)
        let updates = {
            self.incomingTopicsHeaderView.alpha = visible ? 1 : 0
            self.incomingTopicsHeaderView.transform = visible ? .identity : hiddenTransform
        }
        let completion: (Bool) -> Void = { _ in
            self.incomingTopicsHeaderView.isHidden = !self.isIncomingTopicsBannerVisible
            if !self.isIncomingTopicsBannerVisible {
                self.incomingTopicsHeaderView.transform = hiddenTransform
            }
        }

        if visible {
            incomingTopicsHeaderView.isHidden = false
            incomingTopicsHeaderView.transform = hiddenTransform
        }

        guard animated else {
            updates()
            completion(true)
            return
        }

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
            animations: updates,
            completion: completion
        )
    }

    private func updateIncomingTopicsPlacement(animated: Bool) {
        let shouldUseTopSpace = isIncomingTopicsBannerVisible
        setIncomingTopicsUsesTopSpace(shouldUseTopSpace)
        incomingTopicsButton.setFloating(false)

        guard animated else { return }
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
        }
    }

    private func setIncomingTopicsUsesTopSpace(_ usesTopSpace: Bool) {
        guard incomingTopicsUsesTopSpace != usesTopSpace else { return }
        incomingTopicsUsesTopSpace = usesTopSpace
        updateTableInsets()
    }

    private func updateTableInsets() {
        let incomingTopicsTopSpace = isIncomingTopicsBannerVisible && incomingTopicsUsesTopSpace
            ? Self.incomingTopicsBannerHeight
            : 0
        let topInset = headerContainer.frame.maxY + tableTopSpacing + incomingTopicsTopSpace
        let bottomInset = currentBottomChromeHeight

        var insets = tableView.contentInset
        let oldTopInset = insets.top
        let oldBottomInset = insets.bottom
        guard abs(oldTopInset - topInset) > 0.5 || abs(oldBottomInset - bottomInset) > 0.5 else { return }

        insets.top = topInset
        insets.bottom = bottomInset
        tableView.contentInset = insets
        tableView.verticalScrollIndicatorInsets = insets

        // Keep the visible content stable when the collapsible header changes height.
        if oldTopInset > 0, abs(oldTopInset - topInset) > 0.5 {
            tableView.contentOffset.y += oldTopInset - topInset
        }
        if bottomInset < oldBottomInset {
            let minimumOffsetY = -insets.top
            let maximumOffsetY = max(
                minimumOffsetY,
                tableView.contentSize.height + insets.bottom - tableView.bounds.height
            )
            if tableView.contentOffset.y > maximumOffsetY {
                tableView.contentOffset.y = maximumOffsetY
            }
        }
    }

    private var currentBottomChromeHeight: CGFloat {
        if let forumTabBarController = tabBarController as? ForumTabBarController {
            return forumTabBarController.visibleTabBarHeight
        }
        guard let tabBar = tabBarController?.tabBar, !tabBar.isHidden else { return 0 }
        return tabBar.frame.height
    }

    private var tableTopSpacing: CGFloat {
        usesXiaohongshuCardLayout ? Self.xiaohongshuTableTopSpacing : Self.baseTableTopSpacing
    }

    private func revealHeaderForTopRefresh(animated: Bool) {
        setSearchRowCollapsed(false, animated: animated)
        view.layoutIfNeeded()
        updateTableInsets()
        let topOffset = CGPoint(x: 0, y: -tableView.contentInset.top)
        tableView.setContentOffset(topOffset, animated: animated)
        lastHomeScrollY = 0
    }

    private func updateBottomChrome(animated: Bool) {
        let updates = {
            self.floatingActionButtonBottomConstraint?.constant = -self.currentBottomChromeHeight - 20
            self.updateTableInsets()
            self.view.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: updates
            )
        } else {
            updates()
        }
    }

    private func startIncomingTopicsPolling() {
        stopIncomingTopicsPolling()
        pollIncomingTopics()
        let timer = Timer(timeInterval: 30, target: self, selector: #selector(pollIncomingTopics), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        incomingTopicsPollTimer = timer
    }

    private func stopIncomingTopicsPolling() {
        incomingTopicsPollTimer?.invalidate()
        incomingTopicsPollTimer = nil
    }

    private func buildFilterMenuElements() -> [UIMenuElement] {
        HomeListMode.allCases.map { mode in
            UIAction(
                title: title(for: mode),
                image: UIImage(systemName: imageName(for: mode)),
                state: viewModel.listMode == mode ? .on : .off
            ) { [weak self] _ in
                self?.selectListMode(mode)
            }
        }
    }

    private func title(for mode: HomeListMode) -> String {
        switch mode {
        case .latest:
            return String(localized: "home.latest")
        case .newTopics:
            return String(localized: "home.new_topics")
        case .unread:
            return String(localized: "home.updated_topics")
        case .hot:
            return String(localized: "home.hot")
        case .top:
            return String(localized: "home.top")
        }
    }

    private func imageName(for mode: HomeListMode) -> String {
        switch mode {
        case .latest:
            return "clock"
        case .newTopics:
            return "sparkles"
        case .unread:
            return "text.bubble"
        case .hot:
            return "flame"
        case .top:
            return "chart.bar"
        }
    }

    private func rebuildCategoryTabs() {
        let pinnedCategories = viewModel.pinnedCategories(for: AppSettings.shared.homePinnedCategoryIds)
        let nextOrder: [Int?] = [nil] + pinnedCategories.map { Optional($0.id) }
        guard categoryTabOrder != nextOrder else {
            updateCategoryTabs()
            return
        }

        categoryTabOrder = nextOrder
        categoryTabButtons.removeAll()
        categoryStackView.arrangedSubviews.forEach { view in
            categoryStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let allButton = makeCategoryTabButton(title: String(localized: "home.filter.all_categories"), categoryId: nil)
        categoryTabButtons[nil] = allButton
        categoryStackView.addArrangedSubview(allButton)

        for category in pinnedCategories {
            let button = makeCategoryTabButton(title: viewModel.categoryDisplayName(for: category) ?? category.name, categoryId: category.id)
            categoryTabButtons[category.id] = button
            categoryStackView.addArrangedSubview(button)
        }

        updateCategoryTabs()
    }

    private func updateCategoryTabs() {
        let themeStyle = AppSettings.shared.themeStyle
        for (categoryId, button) in categoryTabButtons {
            let selected = categoryId == viewModel.selectedCategoryId
            var config = button.configuration ?? UIButton.Configuration.plain()
            if let categoryId, let category = viewModel.category(id: categoryId) {
                config.title = viewModel.categoryDisplayName(for: category) ?? category.name
            } else {
                config.title = String(localized: "home.filter.all_categories")
            }
            config.baseForegroundColor = selected ? themeStyle.accentColor : .secondaryLabel
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
                var a = attrs
                a.font = UIFont.systemFont(ofSize: 15, weight: selected ? .semibold : .regular)
                return a
            }
            button.configuration = config
            button.layer.sublayers?
                .filter { $0.name == "selectionIndicator" }
                .forEach { $0.removeFromSuperlayer() }
            if selected {
                let indicator = CALayer()
                indicator.name = "selectionIndicator"
                indicator.backgroundColor = themeStyle.accentColor.cgColor
                indicator.cornerRadius = 1
                button.layer.addSublayer(indicator)
                button.setNeedsLayout()
            }
        }
        layoutCategorySelectionIndicators()
    }

    private func layoutCategorySelectionIndicators() {
        for button in categoryTabButtons.values {
            guard let indicator = button.layer.sublayers?.first(where: { $0.name == "selectionIndicator" }) else { continue }
            indicator.frame = CGRect(x: 0, y: button.bounds.height - 3, width: button.bounds.width, height: 2)
        }
    }

    private func buildCategoryMenuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = []

        let allAction = UIAction(
            title: String(localized: "home.filter.all_categories"),
            state: viewModel.selectedCategoryId == nil ? .on : .off
        ) { [weak self] _ in
            self?.selectCategory(nil)
        }
        elements.append(allAction)

        for cat in viewModel.categories {
            let state: UIMenuElement.State = viewModel.selectedCategoryId == cat.id ? .on : .off
            let catColor = Self.color(fromHex: cat.color)
            let catImage = Self.colorDotImage(color: catColor)
            let catTitle = viewModel.categoryDisplayName(for: cat) ?? cat.name
            let catAction = UIAction(title: catTitle, image: catImage, state: state) { [weak self] _ in
                self?.selectCategory(cat.id)
            }
            if let subs = cat.subcategoryList, !subs.isEmpty {
                var groupChildren: [UIMenuElement] = [catAction]
                for sub in subs {
                    let subState: UIMenuElement.State = viewModel.selectedCategoryId == sub.id ? .on : .off
                    let subColor = Self.color(fromHex: sub.color)
                    let subImage = Self.colorDotImage(color: subColor)
                    let subTitle = viewModel.categoryDisplayName(for: sub) ?? sub.name
                    let subAction = UIAction(title: subTitle, image: subImage, state: subState) { [weak self] _ in
                        self?.selectCategory(sub.id)
                    }
                    groupChildren.append(subAction)
                }
                elements.append(UIMenu(title: catTitle, image: catImage, children: groupChildren))
            } else {
                elements.append(catAction)
            }
        }
        return elements
    }

    private func selectCategory(_ categoryId: Int?) {
        viewModel.selectedCategoryId = categoryId
        updateCategoryButton()
        reloadTopics()
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

    private static func colorDotImage(color: UIColor?) -> UIImage? {
        guard let color else { return nil }
        let size = CGSize(width: 12, height: 12)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysOriginal)
    }

    private func setSearchRowCollapsed(_ collapsed: Bool, animated: Bool) {
        guard isSearchRowCollapsed != collapsed else { return }
        isSearchRowCollapsed = collapsed
        updateHeaderHeight(animated: animated)
    }

    private func updateHeaderHeight(animated: Bool) {
        let targetSearchHeight = isSearchRowCollapsed ? 0 : Self.searchRowExpandedHeight
        let targetHeaderHeight = isSearchRowCollapsed ? collapsedHeaderHeight : expandedHeaderHeight
        let needsLayout = searchRowHeightConstraint?.constant != targetSearchHeight
            || headerHeightConstraint?.constant != targetHeaderHeight
            || searchRowStackView.alpha != (isSearchRowCollapsed ? 0 : 1)
        guard needsLayout else { return }
        let updates = {
            self.searchRowHeightConstraint?.constant = targetSearchHeight
            self.searchRowStackView.alpha = self.isSearchRowCollapsed ? 0 : 1
            self.headerHeightConstraint?.constant = targetHeaderHeight
            self.view.layoutIfNeeded()
            self.updateTableInsets()
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: updates)
        } else {
            updates()
        }
    }

    private func setFABMode(_ mode: HomeFABMode, animated: Bool) {
        guard fabMode != mode else { return }
        fabMode = mode
        updateFloatingActionButton(animated: animated)
    }

    private func updateFloatingActionButton(animated: Bool) {
        let symbolName: String
        let accessibilityLabel: String
        switch fabMode {
        case .create:
            symbolName = "plus"
            accessibilityLabel = String(localized: "new_topic.title")
        case .refresh:
            symbolName = "arrow.clockwise"
            accessibilityLabel = String(localized: "action.refresh")
        }
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let image = UIImage(systemName: symbolName, withConfiguration: config)
        let updates = {
            self.floatingActionButton.setImage(image, for: .normal)
            self.floatingActionButton.accessibilityLabel = accessibilityLabel
            self.floatingActionButton.transform = self.fabMode == .refresh
                ? CGAffineTransform(rotationAngle: .pi / 8)
                : .identity
        }
        if animated {
            UIView.transition(
                with: floatingActionButton,
                duration: 0.18,
                options: [.transitionCrossDissolve, .beginFromCurrentState],
                animations: updates
            )
        } else {
            updates()
        }
    }

    private func updateTabBarVisibilityForCurrentScroll(animated: Bool) {
        let y = tableView.contentOffset.y + tableView.contentInset.top
        if !AppSettings.shared.bottomBarAutoHideEnabled || y <= 4 {
            setHomeTabBarHidden(false, animated: animated)
        } else if y > 40 {
            setHomeTabBarHidden(true, animated: animated)
        }
    }

    private func setHomeTabBarHidden(_ hidden: Bool, animated: Bool) {
        guard AppSettings.shared.bottomBarAutoHideEnabled || !hidden else { return }
        guard isHomeTabBarHidden != hidden else { return }
        isHomeTabBarHidden = hidden
        (tabBarController as? ForumTabBarController)?.setTabBarHiddenByScroll(hidden, animated: animated)
        updateBottomChrome(animated: animated)
    }

    private func handleSettingsChanged() {
        applyThemeStyle()
        updateFilterButton()
        updateCategoryButton()
        updateCategoryTabs()
        updateFloatingActionButton(animated: false)
        incomingTopicsButton.applyThemeStyle()
        updateTableInsets()
        applyTopicSnapshot(animatingDifferences: false)
    }

    private func openTopic(_ topicId: Int) {
        let detailVC = TopicDetailViewController(api: api, topicId: topicId)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

private final class IncomingTopicsBannerView: UIControl {
    private let iconContainer: UIView = {
        let view = UIView()
        view.backgroundColor = AppSettings.shared.themeStyle.accentColor.withAlphaComponent(0.14)
        view.layer.cornerRadius = 17
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let view = UIImageView(image: UIImage(systemName: "arrow.up", withConfiguration: config))
        view.tintColor = AppSettings.shared.themeStyle.accentColor
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.86
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "action.refresh")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let chevronView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let view = UIImageView(image: UIImage(systemName: "chevron.up", withConfiguration: config))
        view.tintColor = .tertiaryLabel
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
                self.alpha = self.isHighlighted ? 0.82 : 1
            }
        }
    }

    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.72
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isLoading: Bool) {
        titleLabel.text = title
        applyThemeStyle()
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        chevronView.isHidden = isLoading
        iconView.isHidden = isLoading
        activityIndicator.isHidden = !isLoading
        accessibilityLabel = title
        accessibilityTraits = [.button]
    }

    func setFloating(_ isFloating: Bool) {
        layer.shadowOpacity = isFloating ? 0.08 : 0.02
        layer.shadowRadius = isFloating ? 14 : 8
        layer.shadowOffset = isFloating ? CGSize(width: 0, height: 6) : CGSize(width: 0, height: 2)
    }

    func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        backgroundColor = themeStyle.topicCardBackgroundColor
        layer.borderColor = themeStyle.accentColor.withAlphaComponent(0.12).cgColor
        iconContainer.backgroundColor = themeStyle.accentColor.withAlphaComponent(0.14)
        iconView.tintColor = themeStyle.accentColor
        activityIndicator.color = themeStyle.accentColor
    }

    private func setupUI() {
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 5)

        iconContainer.addSubview(iconView)
        iconContainer.addSubview(activityIndicator)
        addSubview(iconContainer)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(chevronView)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 34),
            iconContainer.heightAnchor.constraint(equalToConstant: 34),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),

            activityIndicator.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -10),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),
        ])
    }
}

private final class CategoryTabManagerViewController: UITableViewController {
    var onPinnedCategoryIdsChanged: (([Int]) -> Void)?

    private enum Section: Int, CaseIterable {
        case pinned
        case available
    }

    private let allCategories: [DiscourseCategory]
    private var pinnedCategoryIds: [Int]
    private let displayNameProvider: (DiscourseCategory) -> String
    private let parentNameProvider: (DiscourseCategory) -> String?
    private let colorProvider: (DiscourseCategory) -> UIColor?

    private var categoriesById: [Int: DiscourseCategory] {
        Dictionary(uniqueKeysWithValues: allCategories.map { ($0.id, $0) })
    }

    private var pinnedCategories: [DiscourseCategory] {
        let lookup = categoriesById
        return pinnedCategoryIds.compactMap { lookup[$0] }
    }

    private var availableCategories: [DiscourseCategory] {
        let pinned = Set(pinnedCategoryIds)
        return allCategories.filter { !pinned.contains($0.id) }
    }

    init(
        categories: [DiscourseCategory],
        pinnedCategoryIds: [Int],
        displayNameProvider: @escaping (DiscourseCategory) -> String,
        parentNameProvider: @escaping (DiscourseCategory) -> String?,
        colorProvider: @escaping (DiscourseCategory) -> UIColor?
    ) {
        self.allCategories = categories
        self.pinnedCategoryIds = Self.validPinnedIds(pinnedCategoryIds, categories: categories)
        self.displayNameProvider = displayNameProvider
        self.parentNameProvider = parentNameProvider
        self.colorProvider = colorProvider
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "home.category_manager.title")
        view.backgroundColor = .systemGroupedBackground
        tableView.register(CategoryManagerCell.self, forCellReuseIdentifier: CategoryManagerCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EmptyCell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "home.category_manager.done"),
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .pinned:
            return max(pinnedCategories.count, 1)
        case .available:
            return max(availableCategories.count, 1)
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .pinned:
            return String(localized: "home.category_manager.my_categories")
        case .available:
            return String(localized: "home.category_manager.all_categories")
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .pinned:
            return String(localized: "home.category_manager.remove_hint")
        case .available:
            return String(localized: "home.category_manager.add_hint")
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .pinned:
            let categories = pinnedCategories
            guard !categories.isEmpty else {
                return emptyCell(text: String(localized: "home.category_manager.empty_pinned"), indexPath: indexPath)
            }
            return categoryCell(category: categories[indexPath.row], mode: .remove, indexPath: indexPath)
        case .available:
            let categories = availableCategories
            guard !categories.isEmpty else {
                return emptyCell(text: String(localized: "home.category_manager.empty_available"), indexPath: indexPath)
            }
            return categoryCell(category: categories[indexPath.row], mode: .add, indexPath: indexPath)
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .pinned:
            let categories = pinnedCategories
            guard categories.indices.contains(indexPath.row) else { return }
            pinnedCategoryIds.removeAll { $0 == categories[indexPath.row].id }
            commitPinnedCategoryChange()
        case .available:
            let categories = availableCategories
            guard categories.indices.contains(indexPath.row) else { return }
            pinnedCategoryIds.append(categories[indexPath.row].id)
            commitPinnedCategoryChange()
        case .none:
            break
        }
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .pinned && pinnedCategories.count > 1
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard Section(rawValue: sourceIndexPath.section) == .pinned,
              Section(rawValue: destinationIndexPath.section) == .pinned,
              pinnedCategoryIds.indices.contains(sourceIndexPath.row)
        else {
            tableView.reloadData()
            return
        }
        let id = pinnedCategoryIds.remove(at: sourceIndexPath.row)
        let destination = min(destinationIndexPath.row, pinnedCategoryIds.count)
        pinnedCategoryIds.insert(id, at: destination)
        commitPinnedCategoryChange(reload: false)
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        if proposedDestinationIndexPath.section == Section.pinned.rawValue {
            return proposedDestinationIndexPath
        }
        return sourceIndexPath
    }

    private func categoryCell(category: DiscourseCategory, mode: CategoryManagerCell.Mode, indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: CategoryManagerCell.reuseIdentifier,
            for: indexPath
        ) as? CategoryManagerCell else {
            return UITableViewCell()
        }
        cell.configure(
            title: displayNameProvider(category),
            subtitle: parentNameProvider(category),
            color: colorProvider(category),
            mode: mode
        )
        return cell
    }

    private func emptyCell(text: String, indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyCell", for: indexPath)
        var config = UIListContentConfiguration.cell()
        config.text = text
        config.textProperties.color = .secondaryLabel
        config.textProperties.font = .systemFont(ofSize: 14, weight: .regular)
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        cell.accessoryType = .none
        return cell
    }

    private func commitPinnedCategoryChange(reload: Bool = true) {
        pinnedCategoryIds = Self.validPinnedIds(pinnedCategoryIds, categories: allCategories)
        onPinnedCategoryIdsChanged?(pinnedCategoryIds)
        if reload {
            tableView.reloadData()
        }
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private static func validPinnedIds(_ ids: [Int], categories: [DiscourseCategory]) -> [Int] {
        let validIds = Set(categories.map(\.id))
        var seen = Set<Int>()
        return ids.filter { validIds.contains($0) && seen.insert($0).inserted }
    }
}

private final class CategoryManagerCell: UITableViewCell {
    enum Mode {
        case add
        case remove
    }

    static let reuseIdentifier = "CategoryManagerCell"

    private let colorDotView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 6
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16, weight: .medium))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .regular))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }()

    private let modeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        contentView.addSubview(colorDotView)
        contentView.addSubview(textStack)
        contentView.addSubview(modeImageView)

        NSLayoutConstraint.activate([
            colorDotView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            colorDotView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            colorDotView.widthAnchor.constraint(equalToConstant: 12),
            colorDotView.heightAnchor.constraint(equalToConstant: 12),

            textStack.leadingAnchor.constraint(equalTo: colorDotView.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(equalTo: modeImageView.leadingAnchor, constant: -12),

            modeImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            modeImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            modeImageView.widthAnchor.constraint(equalToConstant: 22),
            modeImageView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        modeImageView.image = nil
    }

    func configure(title: String, subtitle: String?, color: UIColor?, mode: Mode) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        colorDotView.backgroundColor = TopicTagVisualStyle.categoryColor(for: title, fallback: color ?? .tertiaryLabel)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        switch mode {
        case .add:
            modeImageView.image = UIImage(systemName: "plus.circle.fill", withConfiguration: symbolConfig)
            modeImageView.tintColor = AppSettings.shared.themeStyle.accentColor
            accessibilityHint = String(localized: "home.category_manager.add_hint")
        case .remove:
            modeImageView.image = UIImage(systemName: "minus.circle.fill", withConfiguration: symbolConfig)
            modeImageView.tintColor = .systemRed
            accessibilityHint = String(localized: "home.category_manager.remove_hint")
        }
    }
}

extension HomeViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        isPresentingCloudflareForegroundVerification = false
        pendingCloudflareForegroundVerification = false
        guard viewModel.topics.isEmpty,
              !viewModel.requiresLogin,
              !isCloudflareShieldSuppressed()
        else { return }
        cloudflareChallengeReloadSequence = reloadSequence
        setCloudflareShieldButtonVisible(true, animated: true)
    }
}

extension HomeViewController: UITableViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        hideHomeScrollIndicators()
        updateIncomingTopicsPlacement(animated: false)
        let y = scrollView.contentOffset.y + scrollView.contentInset.top
        let previousY = lastHomeScrollY ?? y
        let deltaY = y - previousY
        lastHomeScrollY = y

        let velocityY = scrollView.panGestureRecognizer.velocity(in: scrollView).y
        if velocityY > 80, y > 24 {
            setFABMode(.refresh, animated: true)
        } else if velocityY < -80 || y <= 2 {
            setFABMode(.create, animated: true)
        }

        if !AppSettings.shared.bottomBarAutoHideEnabled {
            setHomeTabBarHidden(false, animated: true)
        } else if y <= 4 || deltaY < -3 {
            setHomeTabBarHidden(false, animated: true)
        } else if y > 40, deltaY > 3 {
            setHomeTabBarHidden(true, animated: true)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === tableView, !decelerate else { return }
        settleSearchRowCollapse(animated: true)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        settleSearchRowCollapse(animated: true)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        settleSearchRowCollapse(animated: true)
    }

    private func settleSearchRowCollapse(animated: Bool) {
        let y = tableView.contentOffset.y + tableView.contentInset.top
        setSearchRowCollapsed(y > 18, animated: animated)
        lastHomeScrollY = tableView.contentOffset.y + tableView.contentInset.top
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicId = dataSource.itemIdentifier(for: indexPath),
              Self.xiaohongshuRowIndex(from: topicId) == nil
        else { return }
        openTopic(topicId)
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
