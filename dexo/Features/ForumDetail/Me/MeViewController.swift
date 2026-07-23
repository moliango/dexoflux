import SafariServices
import SDWebImage
import UIKit

final class MeViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: MeViewModel
    private weak var authGate: AuthGating?

    private let statsPreferences = MeStatsPreferences()
    private let profileCard = MeProfileCardView()
    private let statsCard = MeStatsCardView()
    private let balanceCard = MeBalanceCardView()
    private let quickActionsCard = MeQuickActionsCardView()
    private let actionsCard = MeActionCardView()
    private let loadingSkeletonView = MeDashboardSkeletonView()
    private var balanceCache: LinuxDoExtensionCache?
    private var balanceRefreshTask: Task<Void, Never>?

    private var pluginScope: PluginScope {
        PluginScope(
            baseURL: api.baseURL,
            username: viewModel.currentUser?.username ?? authGate?.currentUsername()
        )
    }

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        return rc
    }()

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.api = api
        self.viewModel = MeViewModel(api: api)
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "tab.me")
        applyThemeStyle()

        setupLayout()
        setupActions()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pluginStateDidChange),
            name: PluginStateStore.stateDidChangeNotification,
            object: nil
        )
        loadData()
    }

    @MainActor
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateUI()
    }

    override func updateUI() {
        applyThemeStyle()
        if !viewModel.isLoading, refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        activityIndicator.stopAnimating()

        let isLoggedIn = (authGate?.isAuthenticated() ?? false) && !viewModel.requiresLogin
        let showsInitialSkeleton = viewModel.isLoading
            && isLoggedIn
            && viewModel.currentUser == nil
            && viewModel.userProfile == nil
        loadingSkeletonView.setSkeletonActive(showsInitialSkeleton, animated: view.window != nil)
        scrollView.isHidden = showsInitialSkeleton

        if let error = viewModel.errorMessage {
            loadingSkeletonView.setSkeletonActive(false, animated: view.window != nil)
            scrollView.isHidden = false
            let alert = UIAlertController(title: nil, message: error, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
            present(alert, animated: true)
            viewModel.errorMessage = nil
            return
        }

        if isLoggedIn {
            profileCard.configure(
                user: viewModel.currentUser,
                profile: viewModel.userProfile,
                baseURL: api.baseURL
            )
            statsCard.configure(
                items: makeStatItems(),
                isLoggedIn: true,
                layout: statsPreferences.configuration.layout
            )
        } else {
            profileCard.configure(user: nil, profile: nil, baseURL: api.baseURL)
            statsCard.configure(items: [], isLoggedIn: false, layout: .grid)
        }

        configureActionRows(isLoggedIn: isLoggedIn)
        configureQuickActions(isLoggedIn: isLoggedIn)
        configureBalanceCard(isLoggedIn: isLoggedIn)
    }

    private func setupLayout() {
        scrollView.refreshControl = refreshControl

        view.addSubview(scrollView)
        view.addSubview(loadingSkeletonView)
        view.addSubview(activityIndicator)
        scrollView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(profileCard)
        contentStackView.addArrangedSubview(statsCard)
        contentStackView.addArrangedSubview(balanceCard)
        contentStackView.addArrangedSubview(quickActionsCard)
        contentStackView.addArrangedSubview(actionsCard)
        contentStackView.addArrangedSubview(makeAuthButtonContainer())

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingSkeletonView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            loadingSkeletonView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            loadingSkeletonView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            loadingSkeletonView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -28),

            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupActions() {
        profileCard.onLoginTapped = { [weak self] in
            self?.loginTapped()
        }
        profileCard.onProfileTapped = { [weak self] in
            self?.openCurrentUserProfile()
        }
        statsCard.onCustomizeTapped = { [weak self] in
            self?.showStatsCustomizer()
        }
        balanceCard.onSelect = { [weak self] service in
            self?.handleBalanceServiceTap(service)
        }
    }

    private func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        view.backgroundColor = themeStyle.topicListBackgroundColor
        scrollView.backgroundColor = themeStyle.topicListBackgroundColor
        refreshControl.tintColor = themeStyle.accentColor
        activityIndicator.color = themeStyle.accentColor
        loadingSkeletonView.applyThemeStyle()
    }

    private func makeAuthButtonContainer() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.addTarget(self, action: #selector(authButtonTapped), for: .touchUpInside)
        button.tag = 9001

        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        return container
    }

    private func configureActionRows(isLoggedIn: Bool) {
        let trustLevel = viewModel.userProfile?.trustLevel ?? 0
        // 我的主题 / 书签 / 草稿 / 浏览历史 已迁移到快捷入口四宫格，账号功能列表不再重复展示。
        var rows: [MeActionRow] = [
            MeActionRow(
                title: String(localized: "messages.title"),
                subtitle: String(localized: "me.action.messages.subtitle"),
                symbolName: "envelope.fill",
                tintColor: .systemIndigo,
                isEnabled: isLoggedIn,
                action: { [weak self] in self?.openMessages() }
            ),
            MeActionRow(
                title: String(localized: "me.browser.home", defaultValue: "网页浏览"),
                subtitle: String(localized: "me.action.browser.subtitle", defaultValue: "收藏、历史与内置浏览器"),
                symbolName: "safari.fill",
                tintColor: .systemCyan,
                isEnabled: true,
                action: { [weak self] in self?.openBrowser() }
            ),
            MeActionRow(
                title: String(localized: "ai.service.title", defaultValue: "AI 模型服务"),
                subtitle: String(localized: "me.action.ai.subtitle", defaultValue: "管理 AI 供应商与模型"),
                symbolName: "cpu.fill",
                tintColor: .systemTeal,
                isEnabled: true,
                action: { [weak self] in self?.openAIModelService() }
            ),
            MeActionRow(
                title: String(localized: "me.badges"),
                subtitle: String(localized: "me.action.badges.subtitle"),
                symbolName: "medal.fill",
                tintColor: .systemYellow,
                isEnabled: isLoggedIn,
                action: { [weak self] in self?.openBadges() }
            ),
            MeActionRow(
                title: String(localized: "me.trust_requirements"),
                subtitle: String(localized: "me.action.trust.subtitle"),
                symbolName: "checkmark.shield.fill",
                tintColor: .systemGreen,
                isEnabled: isLoggedIn,
                action: { [weak self] in self?.openTrustRequirements() }
            ),
            MeActionRow(
                title: String(localized: "me.invite_links"),
                subtitle: trustLevel >= 3 ? String(localized: "me.action.invites.subtitle") : String(localized: "me.invite_links.requires_level"),
                symbolName: "link.circle.fill",
                tintColor: .systemCyan,
                isEnabled: isLoggedIn && trustLevel >= 3,
                action: { [weak self] in self?.openInviteLinks() }
            ),
            MeActionRow(
                title: String(localized: "me.settings"),
                subtitle: String(localized: "me.action.settings.subtitle"),
                symbolName: "gearshape.fill",
                tintColor: .systemBlue,
                isEnabled: true,
                action: { [weak self] in self?.openSettings() }
            ),
        ]

        var pluginRows: [MeActionRow] = [
            MeActionRow(
                title: String(localized: "plugins.title", defaultValue: "插件中心"),
                subtitle: String(localized: "plugins.subtitle", defaultValue: "管理内部插件与运行权限"),
                symbolName: "puzzlepiece.extension.fill",
                tintColor: .systemPurple,
                isEnabled: true,
                action: { [weak self] in self?.openPluginCenter() }
            ),
        ]
        let registry = DexoPluginRuntime.shared.registry
        if registry.isPluginEnabled(BuiltInPluginID.ldc, for: pluginScope)
            || registry.isPluginEnabled(BuiltInPluginID.cdk, for: pluginScope) {
            pluginRows.append(MeActionRow(
                title: String(localized: "extensions.title", defaultValue: "元宇宙"),
                subtitle: String(localized: "extensions.subtitle", defaultValue: "连接 LDC 与 CDK 服务"),
                symbolName: "sparkles.rectangle.stack.fill",
                tintColor: .systemIndigo,
                isEnabled: isLoggedIn,
                action: { [weak self] in self?.openMetaverseServices() }
            ))
        }
        if registry.isPluginEnabled(BuiltInPluginID.topicExport, for: pluginScope) {
            pluginRows.append(MeActionRow(
                title: String(localized: "topic.export.history", defaultValue: "导出历史"),
                subtitle: String(localized: "me.action.export_history.subtitle", defaultValue: "查看并再次分享话题导出文件"),
                symbolName: "square.and.arrow.up.on.square.fill",
                tintColor: .systemGreen,
                isEnabled: true,
                action: { [weak self] in self?.openExportHistory() }
            ))
        }
        rows.insert(contentsOf: pluginRows, at: min(6, rows.count))
        actionsCard.configure(title: String(localized: "me.actions.title"), rows: rows)

        if let authButton = (contentStackView.arrangedSubviews.last?.subviews.first as? UIButton) {
            let title = isLoggedIn ? String(localized: "me.logout") : String(localized: "me.login")
            authButton.setTitle(title, for: .normal)
            authButton.setTitleColor(isLoggedIn ? .systemRed : .tintColor, for: .normal)
        }
    }

    private func loadData() {
        guard authGate?.isAuthenticated() == true else {
            MeProfileCacheStore.clear(baseURL: api.baseURL)
            viewModel.clearSessionState(requiresLogin: true)
            return
        }
        Task {
            await viewModel.loadProfile()
        }
    }

    func refreshAfterCloudflareVerification() {
        loadData()
    }

    @objc private func pullToRefresh() {
        Task {
            if authGate?.isAuthenticated() == true {
                await viewModel.reload()
            }
            refreshControl.endRefreshing()
        }
    }

    @objc private func authButtonTapped() {
        if authGate?.isAuthenticated() == true {
            logoutTapped()
        } else {
            loginTapped()
        }
    }

    private func loginTapped() {
        authGate?.requireAuth { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.reload()
            }
        }
    }

    private func logoutTapped() {
        let alert = UIAlertController(
            title: String(localized: "me.logout.confirm.title"),
            message: String(localized: "me.logout.confirm.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "me.logout"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.authGate?.performLogout()
                self.viewModel.clearSessionState(requiresLogin: true)
                self.updateUI()
            }
        })
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func makeStatItems() -> [MeStatItem] {
        statsPreferences.selectedStats.compactMap { type in
            switch type {
            case .topicCount:
                return MeStatItem(type: type, value: viewModel.summary?.topicCount)
            case .postCount:
                return MeStatItem(type: type, value: viewModel.summary?.postCount)
            case .likesReceived:
                return MeStatItem(type: type, value: viewModel.summary?.likesReceived)
            case .likesGiven:
                return MeStatItem(type: type, value: viewModel.summary?.likesGiven)
            case .daysVisited:
                return MeStatItem(type: type, value: viewModel.summary?.daysVisited)
            case .timeRead:
                return MeStatItem(type: type, valueText: formatDuration(seconds: viewModel.userProfile?.timeRead))
            case .profileViews:
                return MeStatItem(type: type, value: viewModel.userProfile?.profileViewCount)
            case .badges:
                return MeStatItem(type: type, value: viewModel.userProfile?.badgeCount)
            }
        }
    }

    private func formatDuration(seconds: Int?) -> String? {
        guard let seconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds))
    }

    private func showStatsCustomizer() {
        let editor = ProfileStatsEditorViewController(configuration: statsPreferences.configuration)
        editor.onChange = { [weak self] configuration in
            guard let self else { return }
            self.statsPreferences.configuration = configuration
            self.statsCard.configure(
                items: self.makeStatItems(),
                isLoggedIn: self.authGate?.isAuthenticated() == true,
                layout: configuration.layout
            )
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func openCurrentUserProfile() {
        guard let username = viewModel.currentUser?.username else { return }
        let vc = UserProfileViewController(api: api, username: username)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openMessages() {
        guard authGate?.isAuthenticated() == true else {
            loginTapped()
            return
        }
        let vc = MessagesViewController(api: api, authGate: authGate)
        navigationController?.pushViewController(vc, animated: true)
    }


    private func configureQuickActions(isLoggedIn: Bool) {
        quickActionsCard.configure(items: [
            MeQuickActionItem(
                title: String(localized: "me.quick.topics", defaultValue: "我的话题"),
                symbolName: "doc.text.fill",
                tintColor: .systemBlue,
                action: { [weak self] in self?.openMyTopics() }
            ),
            MeQuickActionItem(
                title: String(localized: "me.quick.bookmarks", defaultValue: "我的书签"),
                symbolName: "bookmark.fill",
                tintColor: .systemOrange,
                action: { [weak self] in self?.openBookmarks() }
            ),
            MeQuickActionItem(
                title: String(localized: "me.quick.drafts", defaultValue: "我的草稿"),
                symbolName: "envelope.fill",
                tintColor: .systemTeal,
                action: { [weak self] in self?.openDrafts() }
            ),
            MeQuickActionItem(
                title: String(localized: "me.quick.history", defaultValue: "浏览历史"),
                symbolName: "clock.fill",
                tintColor: .systemPurple,
                action: { [weak self] in self?.openDiscourseHistory() }
            ),
        ])
        quickActionsCard.alpha = isLoggedIn ? 1 : 0.55
        quickActionsCard.isUserInteractionEnabled = true
    }

    private func configureBalanceCard(isLoggedIn: Bool) {
        guard isLoggedIn, let username = viewModel.currentUser?.username ?? authGate?.currentUsername() else {
            balanceCard.isHidden = true
            balanceRefreshTask?.cancel()
            return
        }
        let cache = LinuxDoExtensionCache(baseURL: api.baseURL, username: username)
        balanceCache = cache
        let registry = DexoPluginRuntime.shared.registry
        let scope = pluginScope
        var rows: [MeBalanceRowModel] = []

        if registry.isPluginEnabled(BuiltInPluginID.ldc, for: scope) {
            let info = cache.userInfo(.ldc)
            let connected = cache.isEnabled(.ldc)
            let income = Self.dailyIncomeText(
                gamificationScore: viewModel.userProfile?.gamificationScore,
                communityBalance: info?.communityBalance
            )
            rows.append(
                MeBalanceRowModel(
                    service: .ldc,
                    title: String(localized: "me.balance.ldc", defaultValue: "LDC 余额"),
                    valueText: connected ? (info?.balanceText ?? "--") : String(localized: "extensions.connect", defaultValue: "点击连接"),
                    dailyIncomeText: connected ? income : nil,
                    isLoading: false,
                    isConnected: connected
                )
            )
        }
        if registry.isPluginEnabled(BuiltInPluginID.cdk, for: scope) {
            let info = cache.userInfo(.cdk)
            let connected = cache.isEnabled(.cdk)
            rows.append(
                MeBalanceRowModel(
                    service: .cdk,
                    title: String(localized: "me.balance.cdk", defaultValue: "CDK 积分"),
                    valueText: connected ? (info?.balanceText ?? "--") : String(localized: "extensions.connect", defaultValue: "点击连接"),
                    dailyIncomeText: nil,
                    isLoading: false,
                    isConnected: connected
                )
            )
        }
        balanceCard.configure(rows: rows)
        refreshBalancesIfNeeded(username: username)
    }

    private static func dailyIncomeText(gamificationScore: Int?, communityBalance: String?) -> String? {
        guard let score = gamificationScore,
              let community = communityBalance,
              let balance = Double(community)
        else { return nil }
        let income = Int((Double(score) - balance).rounded())
        if income > 0 { return "+\(income)" }
        if income < 0 { return "\(income)" }
        return "+0"
    }

    private func refreshBalancesIfNeeded(username: String) {
        balanceRefreshTask?.cancel()
        let registry = DexoPluginRuntime.shared.registry
        let scope = pluginScope
        let services = [LinuxDoExtensionService.ldc, .cdk].filter {
            registry.isPluginEnabled($0 == .ldc ? BuiltInPluginID.ldc : BuiltInPluginID.cdk, for: scope)
                && (balanceCache?.isEnabled($0) == true)
        }
        guard !services.isEmpty else { return }
        balanceRefreshTask = Task { [weak self] in
            guard let self else { return }
            for service in services {
                do {
                    let info = try await LinuxDoExtensionOAuthCoordinator(
                        service: service,
                        forumBaseURL: self.api.baseURL
                    ).fetchUserInfo()
                    self.balanceCache?.setUserInfo(info, service: service)
                } catch {
                    // 保持缓存展示，静默失败
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.configureBalanceCard(isLoggedIn: true)
            }
        }
    }

    private func handleBalanceServiceTap(_ service: LinuxDoExtensionService) {
        guard let username = viewModel.currentUser?.username ?? authGate?.currentUsername() else {
            loginTapped()
            return
        }
        let cache = balanceCache ?? LinuxDoExtensionCache(baseURL: api.baseURL, username: username)
        balanceCache = cache
        if cache.isEnabled(service) {
            let browser = InAppBrowserViewController(
                api: api,
                username: username,
                initialURL: service.dashboardURL
            )
            navigationController?.pushViewController(browser, animated: true)
            return
        }
        // 未连接：FluxDo 同款原生授权确认，不先打开内置浏览器。
        Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await LinuxDoExtensionOAuthCoordinator(
                    service: service,
                    forumBaseURL: self.api.baseURL
                ).authorize(from: self)
                guard let info else { return }
                cache.setEnabled(true, service: service)
                cache.setUserInfo(info, service: service)
                await MainActor.run {
                    self.configureBalanceCard(isLoggedIn: true)
                }
            } catch LinuxDoExtensionError.cloudflare(let baseURL, _) {
                await MainActor.run {
                    let verifier = CloudflareVerificationViewController(
                        baseURL: service.baseURL,
                        responseURL: nil,
                        verificationURL: service.baseURL,
                        autoDismissOnSuccess: true
                    ) { [weak self] in
                        self?.handleBalanceServiceTap(service)
                    }
                    let nav = UINavigationController(rootViewController: verifier)
                    nav.modalPresentationStyle = .pageSheet
                    self.present(nav, animated: true)
                }
            } catch {
                await MainActor.run {
                    let alert = UIAlertController(
                        title: nil,
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func openMyTopics() {
        guard let username = viewModel.currentUser?.username else {
            loginTapped()
            return
        }
        let vc = PagedTopicListViewController(
            api: api,
            title: String(localized: "me.my_topics", defaultValue: "我的主题"),
            emptyMessage: String(localized: "me.my_topics.empty", defaultValue: "还没有创建过话题"),
            searchQuery: "@\(username) order:latest",
            loader: { [api] page in
                try await api.fetchCreatedTopics(username: username, page: page)
            }
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openDiscourseHistory() {
        guard authGate?.isAuthenticated() == true else {
            loginTapped()
            return
        }
        let vc = PagedTopicListViewController(
            api: api,
            title: String(localized: "me.discourse_history", defaultValue: "浏览历史"),
            emptyMessage: String(localized: "me.discourse_history.empty", defaultValue: "还没有论坛浏览记录"),
            fixedSearchQualifier: "in:seen",
            loader: { [api] page in
                try await api.fetchReadTopics(page: page)
            }
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openDrafts() {
        guard authGate?.isAuthenticated() == true else {
            loginTapped()
            return
        }
        navigationController?.pushViewController(DraftsViewController(api: api), animated: true)
    }

    private func openBookmarks() {
        guard let username = viewModel.currentUser?.username else {
            loginTapped()
            return
        }
        let vc = BookmarksViewController(api: api, username: username, authGate: authGate)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openBrowser() {
        let vc = WebBrowsingHomeViewController(
            api: api,
            username: viewModel.currentUser?.username ?? authGate?.currentUsername()
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openPluginCenter() {
        let vc = PluginCenterViewController(
            baseURL: api.baseURL,
            username: viewModel.currentUser?.username ?? authGate?.currentUsername()
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func pluginStateDidChange() {
        updateUI()
    }

    private func openMetaverseServices() {
        guard let username = viewModel.currentUser?.username ?? authGate?.currentUsername() else {
            loginTapped()
            return
        }
        navigationController?.pushViewController(
            MetaverseServicesViewController(api: api, username: username),
            animated: true
        )
    }

    private func openExportHistory() {
        let vc = ExportHistoryViewController(
            baseURL: api.baseURL,
            username: viewModel.currentUser?.username ?? authGate?.currentUsername()
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openBadges() {
        guard let username = viewModel.currentUser?.username else {
            loginTapped()
            return
        }
        let vc = UserBadgesViewController(api: api, username: username)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openTrustRequirements() {
        let vc = TrustRequirementsViewController(
            api: api,
            username: viewModel.currentUser?.username,
            trustLevel: viewModel.userProfile?.trustLevel ?? 0
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openInviteLinks() {
        guard let username = viewModel.currentUser?.username else {
            loginTapped()
            return
        }
        let vc = InviteLinksViewController(api: api, username: username)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openSettings() {
        let vc = SettingsViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openAIModelService() {
        navigationController?.pushViewController(AIModelServiceViewController(api: api), animated: true)
    }

    private func openUserWebPath(_ path: String) {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let baseURL = api.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        openExternalURL(baseURL + normalizedPath)
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            showInfoAlert(String(localized: "me.web.open_error"))
            return
        }
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }

    private func showInfoAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }
}

private final class UserBadgesViewController: UIViewController {
    private let api: DiscourseAPI
    private let username: String
    private var sections: [(DiscourseBadge.BadgeType, [DiscourseUserBadge])] = []
    private var isLoading = false
    private var errorMessage: String?

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 76
        return table
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        return control
    }()

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.badges")
        view.backgroundColor = .systemGroupedBackground
        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        view.addSubview(stateLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        loadBadges()
    }

    private func loadBadges() {
        isLoading = true
        errorMessage = nil
        updateState()
        Task {
            do {
                let response = try await api.fetchUserBadges(username: username)
                let grouped: [DiscourseBadge.BadgeType: [DiscourseUserBadge]] = Dictionary(grouping: response.userBadges) { badge in
                    badge.badge?.type ?? DiscourseBadge.BadgeType.bronze
                }
                let orderedTypes: [DiscourseBadge.BadgeType] = [.gold, .silver, .bronze]
                sections = orderedTypes.compactMap { type in
                    guard let badges = grouped[type], !badges.isEmpty else { return nil }
                    return (type, badges.sorted { ($0.badge?.name ?? "") < ($1.badge?.name ?? "") })
                }
            } catch {
                errorMessage = error.localizedDescription
                sections = []
            }
            isLoading = false
            refreshControl.endRefreshing()
            tableView.reloadData()
            updateState()
        }
    }

    private func updateState() {
        tableView.isHidden = sections.isEmpty
        stateLabel.isHidden = !sections.isEmpty
        if isLoading {
            stateLabel.text = String(localized: "badges.loading")
        } else if let errorMessage {
            stateLabel.text = errorMessage
        } else {
            stateLabel.text = String(localized: "badges.empty")
        }
    }

    @objc private func refreshPulled() {
        loadBadges()
    }
}

extension UserBadgesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].1.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let section = sections[section]
        return "\(section.0.title) · \(section.1.count)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let badge = sections[indexPath.section].1[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let type = badge.badge?.type ?? .bronze
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: "medal.fill")
        content.imageProperties.tintColor = type.color
        content.text = badge.badge?.name ?? String(localized: "badges.unknown")
        content.secondaryText = badge.topicTitle ?? badge.badge?.description
        content.secondaryTextProperties.color = .secondaryLabel
        content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.contentConfiguration = content
        if badge.count > 1 {
            let label = UILabel()
            label.text = "×\(badge.count)"
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            label.textColor = type.color
            cell.accessoryView = label
        } else if badge.topicId != nil {
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
}

extension UserBadgesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicId = sections[indexPath.section].1[indexPath.row].topicId else { return }
        let detail = TopicDetailViewController(api: api, topicId: topicId)
        navigationController?.pushViewController(detail, animated: true)
    }
}

private struct MeActionRow {
    let title: String
    let subtitle: String
    let symbolName: String
    let tintColor: UIColor
    let isEnabled: Bool
    let action: () -> Void
}

enum MeStatType: String, CaseIterable, Codable {
    case daysVisited
    case topicCount
    case postCount
    case likesReceived
    case likesGiven
    case timeRead
    case profileViews
    case badges

    var title: String {
        switch self {
        case .daysVisited: return String(localized: "me.stats.days")
        case .topicCount: return String(localized: "me.stats.topics")
        case .postCount: return String(localized: "me.stats.posts")
        case .likesReceived: return String(localized: "me.stats.likes")
        case .likesGiven: return String(localized: "me.stats.likes_given")
        case .timeRead: return String(localized: "me.stats.time_read")
        case .profileViews: return String(localized: "me.stats.profile_views")
        case .badges: return String(localized: "me.stats.badges")
        }
    }

    var symbolName: String {
        switch self {
        case .daysVisited: return "calendar"
        case .topicCount: return "text.bubble.fill"
        case .postCount: return "bubble.left.and.bubble.right.fill"
        case .likesReceived: return "heart.fill"
        case .likesGiven: return "hand.thumbsup.fill"
        case .timeRead: return "clock.fill"
        case .profileViews: return "eye.fill"
        case .badges: return "medal.fill"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .daysVisited: return .systemTeal
        case .topicCount: return .systemBlue
        case .postCount: return .systemIndigo
        case .likesReceived: return .systemPink
        case .likesGiven: return .systemPurple
        case .timeRead: return .systemGreen
        case .profileViews: return .systemOrange
        case .badges: return .systemYellow
        }
    }
}

enum MeStatsLayout: String, Codable, CaseIterable {
    case grid
    case horizontal

    var title: String {
        switch self {
        case .grid:
            return String(localized: "me.stats.layout.grid", defaultValue: "网格")
        case .horizontal:
            return String(localized: "me.stats.layout.horizontal", defaultValue: "横向")
        }
    }
}

struct MeStatsConfiguration: Codable, Equatable {
    var orderedMetrics: [MeStatType]
    var layout: MeStatsLayout
}

private struct MeStatItem {
    let type: MeStatType
    let valueText: String

    init(type: MeStatType, value: Int?) {
        self.type = type
        self.valueText = value.map { Self.formatNumber($0) } ?? "-"
    }

    init(type: MeStatType, valueText: String?) {
        self.type = type
        self.valueText = valueText ?? "-"
    }

    private static func formatNumber(_ value: Int) -> String {
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

final class MeStatsPreferences {
    private let legacyKey = "me.stats.selected"
    private let configurationKey = "me.stats.configuration"
    private let defaults: UserDefaults
    private let fallback: [MeStatType] = [.daysVisited, .postCount, .likesReceived, .topicCount]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: MeStatsConfiguration {
        get {
            if let data = defaults.data(forKey: configurationKey),
               let decoded = try? JSONDecoder().decode(MeStatsConfiguration.self, from: data),
               !decoded.orderedMetrics.isEmpty {
                return decoded
            }

            let legacy = defaults.stringArray(forKey: legacyKey)?.compactMap(MeStatType.init(rawValue:)) ?? []
            let migrated = MeStatsConfiguration(
                orderedMetrics: legacy.isEmpty ? fallback : legacy,
                layout: .grid
            )
            if let data = try? JSONEncoder().encode(migrated) {
                defaults.set(data, forKey: configurationKey)
            }
            return migrated
        }
        set {
            guard !newValue.orderedMetrics.isEmpty,
                  let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: configurationKey)
            defaults.set(newValue.orderedMetrics.map(\.rawValue), forKey: legacyKey)
        }
    }

    var selectedStats: [MeStatType] {
        get { configuration.orderedMetrics }
        set {
            var updated = configuration
            updated.orderedMetrics = newValue
            configuration = updated
        }
    }

    func reset() {
        configuration = MeStatsConfiguration(orderedMetrics: fallback, layout: .grid)
    }
}

private final class MeDashboardSkeletonView: DexoSkeletonPlaceholderView {
    private var cardSurfaces: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        skeletonContentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: skeletonContentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: skeletonContentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: skeletonContentView.bottomAnchor),
        ])

        stack.addArrangedSubview(makeProfileCard())
        stack.addArrangedSubview(makeStatsCard())
        stack.addArrangedSubview(makeActionsCard())
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        applySkeletonTheme(
            backgroundColor: .clear,
            blockColor: themeStyle.accentColor.withAlphaComponent(0.12)
        )
        cardSurfaces.forEach {
            $0.backgroundColor = themeStyle.topicCardBackgroundColor
            $0.layer.borderColor = UIColor.separator.withAlphaComponent(0.20).cgColor
        }
    }

    private func makeCardSurface(height: CGFloat) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 0.5
        cardSurfaces.append(card)
        card.heightAnchor.constraint(equalToConstant: height).isActive = true
        return card
    }

    private func makeProfileCard() -> UIView {
        let card = makeCardSurface(height: 108)
        let avatar = makeSkeletonBlock(cornerRadius: 36)
        let name = makeSkeletonBlock(cornerRadius: 6)
        let username = makeSkeletonBlock(cornerRadius: 5)
        let badge = makeSkeletonBlock(cornerRadius: 11)

        [avatar, name, username, badge].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            avatar.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 72),
            avatar.heightAnchor.constraint(equalToConstant: 72),

            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 16),
            name.topAnchor.constraint(equalTo: avatar.topAnchor, constant: 6),
            name.widthAnchor.constraint(equalToConstant: 156),
            name.heightAnchor.constraint(equalToConstant: 20),

            username.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            username.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 10),
            username.widthAnchor.constraint(equalToConstant: 118),
            username.heightAnchor.constraint(equalToConstant: 14),

            badge.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            badge.topAnchor.constraint(equalTo: username.bottomAnchor, constant: 10),
            badge.widthAnchor.constraint(equalToConstant: 82),
            badge.heightAnchor.constraint(equalToConstant: 22),
        ])

        return card
    }

    private func makeStatsCard() -> UIView {
        let card = makeCardSurface(height: 142)
        let title = makeSkeletonBlock(cornerRadius: 6)
        card.addSubview(title)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.widthAnchor.constraint(equalToConstant: 110),
            title.heightAnchor.constraint(equalToConstant: 16),
        ])

        var previous: UIView?
        for index in 0 ..< 4 {
            let column = UIView()
            column.translatesAutoresizingMaskIntoConstraints = false
            let icon = makeSkeletonBlock(cornerRadius: 12)
            let value = makeSkeletonBlock(cornerRadius: 5)
            let label = makeSkeletonBlock(cornerRadius: 4)
            column.addSubview(icon)
            column.addSubview(value)
            column.addSubview(label)
            card.addSubview(column)

            NSLayoutConstraint.activate([
                column.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
                column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
                column.widthAnchor.constraint(equalTo: card.widthAnchor, multiplier: 0.20),

                icon.topAnchor.constraint(equalTo: column.topAnchor),
                icon.centerXAnchor.constraint(equalTo: column.centerXAnchor),
                icon.widthAnchor.constraint(equalToConstant: 34),
                icon.heightAnchor.constraint(equalToConstant: 34),

                value.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 9),
                value.centerXAnchor.constraint(equalTo: column.centerXAnchor),
                value.widthAnchor.constraint(equalToConstant: 44),
                value.heightAnchor.constraint(equalToConstant: 16),

                label.topAnchor.constraint(equalTo: value.bottomAnchor, constant: 8),
                label.centerXAnchor.constraint(equalTo: column.centerXAnchor),
                label.widthAnchor.constraint(equalToConstant: 52),
                label.heightAnchor.constraint(equalToConstant: 10),
            ])

            if let previous {
                column.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 8).isActive = true
            } else {
                column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14).isActive = true
            }
            if index == 3 {
                column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14).isActive = true
            }
            previous = column
        }

        return card
    }

    private func makeActionsCard() -> UIView {
        let card = makeCardSurface(height: 224)
        let title = makeSkeletonBlock(cornerRadius: 6)
        card.addSubview(title)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.widthAnchor.constraint(equalToConstant: 128),
            title.heightAnchor.constraint(equalToConstant: 16),
        ])

        var previousRow: UIView = title
        for _ in 0 ..< 3 {
            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false
            let icon = makeSkeletonBlock(cornerRadius: 11)
            let rowTitle = makeSkeletonBlock(cornerRadius: 5)
            let subtitle = makeSkeletonBlock(cornerRadius: 4)
            row.addSubview(icon)
            row.addSubview(rowTitle)
            row.addSubview(subtitle)
            card.addSubview(row)

            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: previousRow.bottomAnchor, constant: previousRow === title ? 14 : 0),
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                row.heightAnchor.constraint(equalToConstant: 56),

                icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
                icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 38),
                icon.heightAnchor.constraint(equalToConstant: 38),

                rowTitle.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
                rowTitle.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
                rowTitle.widthAnchor.constraint(equalToConstant: 136),
                rowTitle.heightAnchor.constraint(equalToConstant: 14),

                subtitle.leadingAnchor.constraint(equalTo: rowTitle.leadingAnchor),
                subtitle.topAnchor.constraint(equalTo: rowTitle.bottomAnchor, constant: 8),
                subtitle.widthAnchor.constraint(equalToConstant: 188),
                subtitle.heightAnchor.constraint(equalToConstant: 11),
            ])
            previousRow = row
        }

        return card
    }
}

private final class MeInsetLabel: UILabel {
    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
}

private final class MeProfileCardView: UIView {
    var onLoginTapped: (() -> Void)?
    var onProfileTapped: (() -> Void)?

    private let cardView = MeCardSurfaceView()
    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .tertiarySystemFill
        iv.layer.cornerRadius = 36
        return iv
    }()
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let levelLabel = MeInsetLabel(
        insets: UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    )
    private let loginButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "me.login")
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let chevronImageView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "chevron.right"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = .tertiaryLabel
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 1
        usernameLabel.font = .systemFont(ofSize: 14, weight: .regular)
        usernameLabel.textColor = .secondaryLabel
        levelLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        levelLabel.textAlignment = .center
        levelLabel.textColor = .systemBlue
        levelLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        levelLabel.layer.cornerRadius = 8
        levelLabel.layer.cornerCurve = .continuous
        levelLabel.layer.masksToBounds = true
        levelLabel.isHidden = true
        levelLabel.setContentHuggingPriority(.required, for: .horizontal)

        let infoStack = UIStackView(arrangedSubviews: [nameLabel, usernameLabel, levelLabel])
        infoStack.axis = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 6
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(avatarImageView)
        cardView.addSubview(infoStack)
        cardView.addSubview(chevronImageView)
        cardView.addSubview(loginButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        cardView.addGestureRecognizer(tap)
        cardView.isUserInteractionEnabled = true
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        let levelHeightConstraint = levelLabel.heightAnchor.constraint(equalToConstant: 26)
        levelHeightConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            avatarImageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),
            avatarImageView.widthAnchor.constraint(equalToConstant: 72),
            avatarImageView.heightAnchor.constraint(equalToConstant: 72),

            infoStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 16),
            infoStack.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            infoStack.trailingAnchor.constraint(lessThanOrEqualTo: chevronImageView.leadingAnchor, constant: -12),
            infoStack.trailingAnchor.constraint(lessThanOrEqualTo: loginButton.leadingAnchor, constant: -12),

            levelHeightConstraint,

            chevronImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            chevronImageView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 10),

            loginButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            loginButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            loginButton.heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    func configure(user: DiscourseCurrentUser?, profile: DiscourseUserProfile?, baseURL: String) {
        guard let user else {
            avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
            avatarImageView.tintColor = .tertiaryLabel
            nameLabel.text = String(localized: "me.not_logged_in")
            usernameLabel.text = String(localized: "me.login_prompt")
            levelLabel.isHidden = true
            chevronImageView.isHidden = true
            loginButton.isHidden = false
            return
        }

        loginButton.isHidden = true
        chevronImageView.isHidden = false
        nameLabel.text = profile?.name ?? user.name ?? user.username
        usernameLabel.text = "@\(user.username)"
        let levelText = UserProfileFormatting.trustLevelText(profile?.trustLevel)
        levelLabel.text = levelText
        levelLabel.isHidden = levelText == nil

        let avatarTemplate = profile?.avatarTemplate ?? user.avatarTemplate
        AvatarImageLoader.setImage(
            on: avatarImageView,
            template: avatarTemplate,
            baseURL: baseURL,
            size: 240,
            placeholder: UIImage(systemName: "person.crop.circle.fill")
        )
    }

    @objc private func loginTapped() {
        onLoginTapped?()
    }

    @objc private func profileTapped() {
        if loginButton.isHidden {
            onProfileTapped?()
        }
    }
}

private final class MeStatsCardView: UIView {
    var onCustomizeTapped: (() -> Void)?

    private let cardView = MeCardSurfaceView()
    private let titleLabel = UILabel()
    private let customizeButton = UIButton(type: .system)
    private let statsScrollView = UIScrollView()
    private let gridStackView = UIStackView()
    private let emptyLabel = UILabel()
    private var gridWidthConstraint: NSLayoutConstraint?
    private var statsHeightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = String(localized: "me.stats.title")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        customizeButton.setTitle(String(localized: "me.stats.customize"), for: .normal)
        customizeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        customizeButton.addTarget(self, action: #selector(customizeTapped), for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, UIView(), customizeButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        gridStackView.axis = .vertical
        gridStackView.spacing = 14
        gridStackView.translatesAutoresizingMaskIntoConstraints = false

        statsScrollView.translatesAutoresizingMaskIntoConstraints = false
        statsScrollView.showsHorizontalScrollIndicator = false
        statsScrollView.showsVerticalScrollIndicator = false
        statsScrollView.alwaysBounceVertical = false
        statsScrollView.addSubview(gridStackView)

        emptyLabel.text = String(localized: "me.stats.login_required")
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(headerStack)
        cardView.addSubview(statsScrollView)
        cardView.addSubview(emptyLabel)

        let widthConstraint = gridStackView.widthAnchor.constraint(equalTo: statsScrollView.frameLayoutGuide.widthAnchor)
        let heightConstraint = statsScrollView.heightAnchor.constraint(equalToConstant: 84)
        gridWidthConstraint = widthConstraint
        statsHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            statsScrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            statsScrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            statsScrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            statsScrollView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            heightConstraint,

            gridStackView.topAnchor.constraint(equalTo: statsScrollView.contentLayoutGuide.topAnchor),
            gridStackView.leadingAnchor.constraint(equalTo: statsScrollView.contentLayoutGuide.leadingAnchor),
            gridStackView.trailingAnchor.constraint(equalTo: statsScrollView.contentLayoutGuide.trailingAnchor),
            gridStackView.bottomAnchor.constraint(equalTo: statsScrollView.contentLayoutGuide.bottomAnchor),
            gridStackView.heightAnchor.constraint(equalTo: statsScrollView.frameLayoutGuide.heightAnchor),
            widthConstraint,

            emptyLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            emptyLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            emptyLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -18),
        ])
    }

    func configure(items: [MeStatItem], isLoggedIn: Bool, layout: MeStatsLayout) {
        gridStackView.arrangedSubviews.forEach { view in
            gridStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        customizeButton.isHidden = !isLoggedIn
        emptyLabel.isHidden = isLoggedIn
        statsScrollView.isHidden = !isLoggedIn
        guard isLoggedIn else { return }

        switch layout {
        case .grid:
            statsScrollView.isScrollEnabled = false
            gridStackView.axis = .vertical
            gridStackView.alignment = .fill
            gridStackView.distribution = .fill
            gridStackView.spacing = 14
            gridWidthConstraint?.isActive = true

            let rows = stride(from: 0, to: items.count, by: 4).map {
                Array(items[$0..<min($0 + 4, items.count)])
            }
            for rowItems in rows {
                let rowStack = UIStackView()
                rowStack.axis = .horizontal
                rowStack.distribution = .fillEqually
                rowStack.spacing = 8
                rowItems.forEach { rowStack.addArrangedSubview(MeStatView(item: $0)) }
                if rowItems.count < 4 {
                    for _ in rowItems.count..<4 {
                        rowStack.addArrangedSubview(UIView())
                    }
                }
                gridStackView.addArrangedSubview(rowStack)
            }
            let rowCount = max(rows.count, 1)
            statsHeightConstraint?.constant = CGFloat(rowCount * 84 + max(rowCount - 1, 0) * 14)
        case .horizontal:
            statsScrollView.isScrollEnabled = true
            gridStackView.axis = .horizontal
            gridStackView.alignment = .fill
            gridStackView.distribution = .fill
            gridStackView.spacing = 12
            gridWidthConstraint?.isActive = false
            for item in items {
                let statView = MeStatView(item: item)
                statView.widthAnchor.constraint(equalToConstant: 78).isActive = true
                gridStackView.addArrangedSubview(statView)
            }
            statsHeightConstraint?.constant = 84
        }
    }

    @objc private func customizeTapped() {
        onCustomizeTapped?()
    }
}

private final class MeStatView: UIView {
    init(item: MeStatItem) {
        super.init(frame: .zero)
        setup(item: item)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(item: MeStatItem) {
        let iconView = UIImageView(image: UIImage(systemName: item.type.symbolName))
        iconView.tintColor = item.type.tintColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = item.type.tintColor.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = 12
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.addSubview(iconView)

        let valueLabel = UILabel()
        valueLabel.text = item.valueText
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.75

        let titleLabel = UILabel()
        titleLabel.text = item.type.title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75

        let stack = UIStackView(arrangedSubviews: [iconContainer, valueLabel, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconContainer.widthAnchor.constraint(equalToConstant: 34),
            iconContainer.heightAnchor.constraint(equalToConstant: 34),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
}

private final class MeActionCardView: UIView {
    private let cardView = MeCardSurfaceView()
    private let titleLabel = UILabel()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(stackView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -6),
        ])
    }

    func configure(title: String, rows: [MeActionRow]) {
        titleLabel.text = title
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, row) in rows.enumerated() {
            let rowView = MeActionRowView(row: row, showsDivider: index < rows.count - 1)
            stackView.addArrangedSubview(rowView)
        }
    }
}

private final class MeActionRowView: UIControl {
    private let action: () -> Void

    init(row: MeActionRow, showsDivider: Bool) {
        self.action = row.action
        super.init(frame: .zero)
        setup(row: row, showsDivider: showsDivider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(row: MeActionRow, showsDivider: Bool) {
        isEnabled = row.isEnabled
        alpha = row.isEnabled ? 1 : 0.48
        addTarget(self, action: #selector(tapped), for: .touchUpInside)

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = row.tintColor.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = 11
        iconContainer.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: row.symbolName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = row.tintColor
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = row.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label

        let subtitleLabel = UILabel()
        subtitleLabel.text = row.subtitle
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
        divider.isHidden = !showsDivider

        addSubview(iconContainer)
        addSubview(textStack)
        addSubview(chevron)
        addSubview(divider)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 62),

            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 38),
            iconContainer.heightAnchor.constraint(equalToConstant: 38),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 19),
            iconView.heightAnchor.constraint(equalToConstant: 19),

            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 14),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),

            divider.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    @objc private func tapped() {
        action()
    }
}

class MeCardSurfaceView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.withAlphaComponent(0.22).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
