import UIKit
import WebKit

final class ForumContainerViewController: UIViewController, AuthGating {
    private static let cloudflareShieldSuppressionDuration: TimeInterval = 6
    private static let launchOverlayMinimumDuration: TimeInterval = 1.15
    private static let launchOverlayMaximumDurationNanoseconds: UInt64 = 4_200_000_000

    private(set) var forum: ForumInstance
    private let api: DiscourseAPI
    private let authManager = AuthManager.shared
    private let showsDismissButton: Bool
    private var launchOverlayStartedAt = Date()
    private var launchOverlayDismissed = false
    private var isHomeInitialContentReady = false
    private var launchOverlayObservationToken: NSObjectProtocol?
    private var launchOverlayFallbackTask: Task<Void, Never>?
    private var authObservationToken: NSObjectProtocol?
    private var cloudflareChallengeObservationToken: NSObjectProtocol?
    private var cloudflareCompletionObservationToken: NSObjectProtocol?
    private var cloudflareNeedsUserObservationToken: NSObjectProtocol?
    private var isPresentingCloudflareVerification = false
    private var shouldShowCloudflareShieldButton = false
    private var cloudflareShieldSuppressedUntil: Date?
    private var pendingCloudflareBaseURL: URL?
    private var pendingCloudflareResponseURL: URL?
    private var cloudflareShieldButtonConstraints: [NSLayoutConstraint] = []
    private weak var cloudflareShieldButtonHostView: UIView?

    private let launchLoadingView = DexoLaunchLoadingView()

    private let authSyncOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.78)
        view.alpha = 0
        view.isHidden = true
        view.isUserInteractionEnabled = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let authSyncCardView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.96)
        view.layer.cornerRadius = 22
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.10
        view.layer.shadowRadius = 24
        view.layer.shadowOffset = CGSize(width: 0, height: 10)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let authSyncSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        return spinner
    }()

    private let authSyncTitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold)
        )
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let authSyncMessageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14, weight: .medium)
        )
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        button.alpha = 0
        button.isHidden = true
        return button
    }()

    init(forum: ForumInstance, showsDismissButton: Bool = true) {
        self.forum = forum
        self.api = DiscourseAPI(forum: forum)
        self.showsDismissButton = showsDismissButton
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DexoLaunchAppearance.backgroundColor

        authManager.restoreAuthState(for: forum)
        if authManager.hasWebSession(for: forum.baseURL) {
            WebSessionRefreshService.shared.ensureInBackground(forum: forum, reason: "forum_container_loaded")
        }

        startObservingHomeInitialContent()
        setupTabBar()
        setupAuthSyncOverlay()
        setupCloudflareShieldButton()
        setupLaunchLoadingOverlay()
        configureNavItems()
        startObservingAuth()
        startObservingCloudflareChallenges()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if shouldShowCloudflareShieldButton {
            installCloudflareShieldButtonIfNeeded()
        }
    }

    private func startObservingAuth() {
        authObservationToken = NotificationCenter.default.addObserver(
            forName: DexoObservableObject.didChangeNotification,
            object: authManager,
            queue: .main
        ) { [weak self] _ in
            self?.configureNavItems()
        }
    }

    private func startObservingCloudflareChallenges() {
        cloudflareChallengeObservationToken = NotificationCenter.default.addObserver(
            forName: DiscourseAPI.cloudflareChallengeDetectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareChallengeNotification(notification)
        }
        cloudflareCompletionObservationToken = NotificationCenter.default.addObserver(
            forName: DiscourseAPI.cloudflareVerificationCompletedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareVerificationCompleted(notification)
        }
        cloudflareNeedsUserObservationToken = NotificationCenter.default.addObserver(
            forName: CloudflareBackgroundVerificationService.needsUserInteractionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareNeedsUserInteraction(notification)
        }
    }

    @MainActor deinit {
        if let authObservationToken {
            NotificationCenter.default.removeObserver(authObservationToken)
        }
        if let launchOverlayObservationToken {
            NotificationCenter.default.removeObserver(launchOverlayObservationToken)
        }
        if let cloudflareChallengeObservationToken {
            NotificationCenter.default.removeObserver(cloudflareChallengeObservationToken)
        }
        if let cloudflareCompletionObservationToken {
            NotificationCenter.default.removeObserver(cloudflareCompletionObservationToken)
        }
        if let cloudflareNeedsUserObservationToken {
            NotificationCenter.default.removeObserver(cloudflareNeedsUserObservationToken)
        }
        launchOverlayFallbackTask?.cancel()
        NSLayoutConstraint.deactivate(cloudflareShieldButtonConstraints)
        cloudflareShieldButton.removeFromSuperview()
    }

    private func setupTabBar() {
        let tabBarVC = ForumTabBarController(api: api, authGate: self)
        tabBarVC.onNavigationControllersChanged = { [weak self] in
            self?.configureNavItems()
        }
        addChild(tabBarVC)
        view.addSubview(tabBarVC.view)
        tabBarVC.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tabBarVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        tabBarVC.configureTabBarSurface()

        tabBarVC.didMove(toParent: self)
    }

    private func setupCloudflareShieldButton() {
        cloudflareShieldButton.addTarget(self, action: #selector(cloudflareShieldTapped), for: .touchUpInside)
        installCloudflareShieldButtonIfNeeded()
    }

    private func setupLaunchLoadingOverlay() {
        launchOverlayStartedAt = Date()
        launchLoadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(launchLoadingView)

        NSLayoutConstraint.activate([
            launchLoadingView.topAnchor.constraint(equalTo: view.topAnchor),
            launchLoadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            launchLoadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            launchLoadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        launchLoadingView.applyThemeStyle()
        launchLoadingView.startPresenting()
        scheduleLaunchOverlayFallbackDismiss()
        if isHomeInitialContentReady {
            dismissLaunchLoadingOverlayRespectingMinimumDuration()
        }
    }

    private func startObservingHomeInitialContent() {
        launchOverlayObservationToken = NotificationCenter.default.addObserver(
            forName: HomeViewController.initialContentReadyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleHomeInitialContentReady(notification)
        }
    }

    private func scheduleLaunchOverlayFallbackDismiss() {
        launchOverlayFallbackTask?.cancel()
        launchOverlayFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.launchOverlayMaximumDurationNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismissLaunchLoadingOverlayRespectingMinimumDuration()
            }
        }
    }

    private func handleHomeInitialContentReady(_ notification: Notification) {
        guard let baseURL = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURL) == normalizedBaseURL(forum.baseURL) else { return }
        isHomeInitialContentReady = true
        guard launchLoadingView.superview != nil else { return }
        dismissLaunchLoadingOverlayRespectingMinimumDuration()
    }

    private func dismissLaunchLoadingOverlayRespectingMinimumDuration() {
        guard !launchOverlayDismissed else { return }
        guard launchLoadingView.superview != nil else { return }
        let elapsed = Date().timeIntervalSince(launchOverlayStartedAt)
        let delay = max(0, Self.launchOverlayMinimumDuration - elapsed)

        launchOverlayDismissed = true
        launchOverlayFallbackTask?.cancel()
        launchOverlayFallbackTask = nil

        let dismiss = { [weak self] in
            guard let self else { return }
            self.launchLoadingView.dismiss {
                self.launchLoadingView.removeFromSuperview()
            }
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: dismiss)
        } else {
            dismiss()
        }
    }

    private func setupAuthSyncOverlay() {
        view.addSubview(authSyncOverlayView)
        authSyncOverlayView.addSubview(authSyncCardView)
        authSyncCardView.addSubview(authSyncSpinner)
        authSyncCardView.addSubview(authSyncTitleLabel)
        authSyncCardView.addSubview(authSyncMessageLabel)

        NSLayoutConstraint.activate([
            authSyncOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            authSyncOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            authSyncOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            authSyncOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            authSyncCardView.centerXAnchor.constraint(equalTo: authSyncOverlayView.centerXAnchor),
            authSyncCardView.centerYAnchor.constraint(equalTo: authSyncOverlayView.centerYAnchor),
            authSyncCardView.leadingAnchor.constraint(greaterThanOrEqualTo: authSyncOverlayView.leadingAnchor, constant: 42),
            authSyncCardView.trailingAnchor.constraint(lessThanOrEqualTo: authSyncOverlayView.trailingAnchor, constant: -42),

            authSyncSpinner.topAnchor.constraint(equalTo: authSyncCardView.topAnchor, constant: 24),
            authSyncSpinner.centerXAnchor.constraint(equalTo: authSyncCardView.centerXAnchor),

            authSyncTitleLabel.topAnchor.constraint(equalTo: authSyncSpinner.bottomAnchor, constant: 16),
            authSyncTitleLabel.leadingAnchor.constraint(equalTo: authSyncCardView.leadingAnchor, constant: 24),
            authSyncTitleLabel.trailingAnchor.constraint(equalTo: authSyncCardView.trailingAnchor, constant: -24),

            authSyncMessageLabel.topAnchor.constraint(equalTo: authSyncTitleLabel.bottomAnchor, constant: 8),
            authSyncMessageLabel.leadingAnchor.constraint(equalTo: authSyncCardView.leadingAnchor, constant: 24),
            authSyncMessageLabel.trailingAnchor.constraint(equalTo: authSyncCardView.trailingAnchor, constant: -24),
            authSyncMessageLabel.bottomAnchor.constraint(equalTo: authSyncCardView.bottomAnchor, constant: -24),
        ])
    }

    private func installCloudflareShieldButtonIfNeeded() {
        let hostView: UIView = view.window ?? view
        if cloudflareShieldButtonHostView === hostView {
            hostView.bringSubviewToFront(cloudflareShieldButton)
            return
        }

        NSLayoutConstraint.deactivate(cloudflareShieldButtonConstraints)
        cloudflareShieldButton.removeFromSuperview()
        hostView.addSubview(cloudflareShieldButton)
        cloudflareShieldButtonHostView = hostView

        let centerYConstraint = cloudflareShieldButton.centerYAnchor.constraint(
            equalTo: hostView.safeAreaLayoutGuide.centerYAnchor,
            constant: 72
        )
        centerYConstraint.priority = UILayoutPriority.defaultHigh
        cloudflareShieldButtonConstraints = [
            cloudflareShieldButton.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            centerYConstraint,
            cloudflareShieldButton.bottomAnchor.constraint(lessThanOrEqualTo: hostView.safeAreaLayoutGuide.bottomAnchor, constant: -96),
            cloudflareShieldButton.widthAnchor.constraint(equalToConstant: 50),
            cloudflareShieldButton.heightAnchor.constraint(equalToConstant: 44),
        ]
        NSLayoutConstraint.activate(cloudflareShieldButtonConstraints)
        hostView.bringSubviewToFront(cloudflareShieldButton)
    }

    private func configureNavItems() {
        guard let tabBarVC = children.first as? ForumTabBarController else { return }

        for nav in tabBarVC.navigationControllers {
            guard let rootVC = nav.viewControllers.first else { continue }
            if rootVC.title == nil {
                rootVC.title = nav.tabBarItem.title
            }
            guard showsDismissButton else { continue }
            rootVC.navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "smallcircle.filled.circle"),
                style: .plain,
                target: self,
                action: #selector(dismissButtonTapped)
            )
        }
    }

    // MARK: - Actions

    @objc private func menuButtonTapped() {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if authManager.isAuthenticated(for: baseURL) {
            if let username = authManager.username(for: baseURL) {
                alert.title = "@\(username)"
            }
            alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.performLogout()
                }
            })
        } else {
            alert.addAction(UIAlertAction(title: "Log In", style: .default) { [weak self] _ in
                self?.performLogin()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func dismissButtonTapped() {
        ForumOverlayManager.shared.minimize()
    }

    @objc private func cloudflareShieldTapped() {
        let baseURL = pendingCloudflareBaseURL
            ?? URL(string: forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard let baseURL else {
            logCloudflareState("shield tap ignored because base URL is invalid")
            return
        }
        logCloudflareState("shield tapped; presenting foreground verification")
        presentCloudflareVerification(
            baseURL: baseURL,
            responseURL: pendingCloudflareResponseURL
        )
    }

    private func handleCloudflareChallengeNotification(_ notification: Notification) {
        guard let baseURLString = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURLString) == normalizedBaseURL(forum.baseURL) else { return }
        guard let baseURL = URL(string: baseURLString) ?? URL(string: forum.baseURL) else { return }
        let responseURL = notification.userInfo?[DiscourseAPI.cloudflareResponseURLUserInfoKey] as? URL
        pendingCloudflareBaseURL = baseURL
        pendingCloudflareResponseURL = responseURL
        guard !isCloudflareShieldSuppressed() else {
            logCloudflareState("challenge ignored while shield is suppressed base=\(baseURLString)")
            setCloudflareShieldButtonVisible(false, animated: true)
            return
        }
        logCloudflareState("challenge detected; starting background verification base=\(baseURLString)")
        guard !isPresentingCloudflareVerification else {
            logCloudflareState("background verification skipped because foreground verification is active base=\(baseURLString)")
            return
        }
        setCloudflareShieldButtonVisible(true, animated: true)
        CloudflareBackgroundVerificationService.shared.ensureInBackground(
            baseURL: baseURL,
            reason: "container_challenge",
            responseURL: responseURL
        )
    }

    private func handleCloudflareNeedsUserInteraction(_ notification: Notification) {
        guard let baseURLString = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURLString) == normalizedBaseURL(forum.baseURL) else { return }
        guard let baseURL = URL(string: baseURLString) ?? URL(string: forum.baseURL) else { return }
        let responseURL = notification.userInfo?[DiscourseAPI.cloudflareResponseURLUserInfoKey] as? URL
        pendingCloudflareBaseURL = baseURL
        pendingCloudflareResponseURL = responseURL
        guard !isCloudflareShieldSuppressed() else {
            logCloudflareState("needs-user ignored while shield is suppressed base=\(baseURLString)")
            setCloudflareShieldButtonVisible(false, animated: true)
            return
        }
        guard !isPresentingCloudflareVerification else {
            logCloudflareState("needs-user ignored because foreground verification is already presented base=\(baseURLString)")
            return
        }
        logCloudflareState("background verification needs user; showing global shield base=\(baseURLString)")
        setCloudflareShieldButtonVisible(true, animated: true)
    }

    private func handleCloudflareVerificationCompleted(_ notification: Notification) {
        guard let baseURLString = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURLString) == normalizedBaseURL(forum.baseURL) else { return }
        logCloudflareState("verification completed base=\(baseURLString)")
        pendingCloudflareBaseURL = nil
        pendingCloudflareResponseURL = nil
        suppressCloudflareShieldTemporarily()
        setCloudflareShieldButtonVisible(false, animated: true)
        refreshVisiblePageAfterCloudflareVerification()
    }

    private func refreshVisiblePageAfterCloudflareVerification() {
        guard let tabBar = children.first as? ForumTabBarController,
              let navigation = tabBar.selectedViewController as? UINavigationController,
              let visible = navigation.visibleViewController
        else { return }
        switch visible {
        case is HomeViewController:
            break
        case is TopicDetailViewController:
            // Topic Detail observes the completion notification directly.
            break
        case let me as MeViewController:
            me.refreshAfterCloudflareVerification()
        case let search as SearchViewController:
            search.refreshAfterCloudflareVerification()
        default:
            break
        }
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
            installCloudflareShieldButtonIfNeeded()
            cloudflareShieldButton.isHidden = false
        }

        guard animated else {
            updates()
            completion(true)
            return
        }

        DexoMotion.animate(
            duration: DexoMotion.quick,
            animations: updates
        ) { _ in
            completion(true)
        }
    }

    private func showAuthSyncOverlay(title: String, message: String, animated: Bool = true) {
        authSyncTitleLabel.text = title
        authSyncMessageLabel.text = message
        authSyncSpinner.color = AppSettings.shared.themeStyle.accentColor
        authSyncSpinner.startAnimating()
        view.bringSubviewToFront(authSyncOverlayView)
        authSyncOverlayView.isHidden = false

        let updates = {
            self.authSyncOverlayView.alpha = 1
        }
        guard animated else {
            updates()
            return
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: updates)
    }

    private func hideAuthSyncOverlay(animated: Bool = true, completion: (() -> Void)? = nil) {
        let finish = {
            self.authSyncSpinner.stopAnimating()
            self.authSyncOverlayView.isHidden = true
            completion?()
        }
        let updates = {
            self.authSyncOverlayView.alpha = 0
        }
        guard animated else {
            updates()
            finish()
            return
        }
        UIView.animate(withDuration: 0.20, delay: 0, options: [.curveEaseInOut], animations: updates) { _ in
            finish()
        }
    }

    private func presentCloudflareVerification(baseURL: URL, responseURL: URL?) {
        guard !isPresentingCloudflareVerification else {
            logCloudflareState("foreground verification skipped because verification is already presented")
            return
        }
        guard view.window != nil else { return }
        guard let presenter = topMostPresenter(), !presenter.isBeingDismissed else { return }

        pendingCloudflareBaseURL = baseURL
        pendingCloudflareResponseURL = responseURL
        isPresentingCloudflareVerification = true
        setCloudflareShieldButtonVisible(false, animated: true)
        Task { @MainActor [weak self] in
            await CloudflareBackgroundVerificationService.shared.beginForegroundVerification(
                baseURL: baseURL
            )
            guard let self, self.isPresentingCloudflareVerification else {
                CloudflareBackgroundVerificationService.shared.endForegroundVerification(
                    baseURL: baseURL
                )
                return
            }
            guard !presenter.isBeingDismissed, presenter.view.window != nil else {
                CloudflareBackgroundVerificationService.shared.endForegroundVerification(
                    baseURL: baseURL
                )
                self.handleCloudflareVerificationClosed()
                return
            }

            let vc = CloudflareVerificationViewController(
                baseURL: baseURL,
                responseURL: responseURL,
                autoDismissOnSuccess: true
            ) { [weak self] in
                CloudflareBackgroundVerificationService.shared.endForegroundVerification(
                    baseURL: baseURL
                )
                self?.handleCloudflareVerificationClosed()
            }
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .pageSheet
            nav.isModalInPresentation = true
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 20
            }
            presenter.present(nav, animated: true)
        }
    }

    private func handleCloudflareVerificationClosed() {
        isPresentingCloudflareVerification = false
        guard pendingCloudflareBaseURL != nil, !isCloudflareShieldSuppressed() else { return }
        setCloudflareShieldButtonVisible(true, animated: true)
    }

    private func topMostPresenter() -> UIViewController? {
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            if let nav = presented as? UINavigationController,
               nav.viewControllers.first is CloudflareVerificationViewController {
                return nil
            }
            presenter = presented
        }
        return presenter
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }


    private func logCloudflareState(_ message: String) {
        DohDebugLog.record("container \(message)", subsystem: "CF")
    }

    // MARK: - Auth Actions

    private func performLogin() {
        presentWebLogin {}
    }

    func performLogout() async {
        let baseURL = forum.baseURL
        authManager.logout(forum: forum)
        await WebCookieStore.shared.clearWebViewAuthCookies(for: baseURL)
        refreshForumFromDatabase()
    }

    // MARK: - AuthGating

    func requireAuth(then action: @escaping () -> Void) {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if authManager.isAuthenticated(for: baseURL) {
            action()
            return
        }

        if authManager.hasWebSession(for: baseURL) {
            Task { [weak self] in
                guard let self else { return }
                await MainActor.run {
                    self.showAuthSyncOverlay(
                        title: String(localized: "weblogin.restore.title"),
                        message: String(localized: "weblogin.restore.message")
                    )
                }
                let didRecover = await self.authManager.refreshWebSessionUserIfPossible(forum: self.forum)
                await MainActor.run {
                    self.refreshForumFromDatabase()
                    if didRecover {
                        self.hideAuthSyncOverlay {
                            action()
                        }
                    } else {
                        self.hideAuthSyncOverlay()
                        self.presentWebLogin(then: action)
                    }
                }
            }
            return
        }

        presentWebLogin(then: action)
    }

    private func presentWebLogin(then action: @escaping () -> Void) {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/login") ?? URL(string: forum.baseURL) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await WebCookieStore.shared.clearWebViewAuthCookies(for: baseURL)
            let vc = WebLoginViewController(targetURL: url) { [weak self] cookies, userAgent in
                guard let self else { return }
                self.showAuthSyncOverlay(
                    title: String(localized: "weblogin.success.title"),
                    message: String(localized: "weblogin.success.message")
                )
                Task { @MainActor in
                    let didLogin = await self.authManager.loginViaWeb(forum: self.forum, cookies: cookies, userAgent: userAgent)
                    self.refreshForumFromDatabase()
                    guard didLogin else {
                        self.hideAuthSyncOverlay()
                        return
                    }
                    self.hideAuthSyncOverlay {
                        action()
                    }
                }
            }
            let nav = UINavigationController(rootViewController: vc)
            self.present(nav, animated: true)
        }
    }

    private func refreshForumFromDatabase() {
        if let forums = try? DatabaseManager.shared.fetchAllForums(),
           let updated = forums.first(where: { $0.id == forum.id })
        {
            forum = updated
        }
    }

    func isAuthenticated() -> Bool {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return authManager.isAuthenticated(for: baseURL)
    }

    func currentUsername() -> String? {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return authManager.username(for: baseURL)
    }
}

private final class DexoLaunchLoadingView: UIView {
    private let rootStackView = UIStackView()
    private let linuxLogoView = UIImageView()
    private let brandLabel = UILabel()
    private let valuesLabel = UILabel()
    private let loadingLabel = UILabel()
    private let dotsStackView = UIStackView()
    private var dotViews: [UIView] = []
    private let linuxDoTextColor = UIColor(red: 0.095, green: 0.096, blue: 0.105, alpha: 1)
    private let linuxDoYellow = UIColor(red: 1.0, green: 0.68, blue: 0.02, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DexoLaunchAppearance.backgroundColor
        isOpaque = true
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "launch.loading.accessibility")
        setupUI()
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyThemeStyle() {
        backgroundColor = DexoLaunchAppearance.backgroundColor
        brandLabel.textColor = linuxDoTextColor
        brandLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 30,
            weight: .heavy,
            fallback: .systemFont(ofSize: 30, weight: .heavy)
        )
        valuesLabel.text = String(localized: "launch.loading.values")
        valuesLabel.textColor = linuxDoTextColor.withAlphaComponent(0.72)
        valuesLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 15,
            weight: .semibold,
            fallback: .systemFont(ofSize: 15, weight: .semibold)
        )
        loadingLabel.text = String(localized: "launch.loading.subtitle")
        loadingLabel.textColor = linuxDoTextColor.withAlphaComponent(0.62)
        loadingLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 12,
            weight: .medium,
            fallback: .systemFont(ofSize: 12, weight: .medium)
        )
        dotViews.forEach { $0.backgroundColor = linuxDoYellow }
    }

    func startPresenting() {
        alpha = 1
        rootStackView.alpha = 0
        rootStackView.transform = CGAffineTransform(translationX: 0, y: 16).scaledBy(x: 0.96, y: 0.96)
        valuesLabel.alpha = 0
        valuesLabel.transform = CGAffineTransform(translationX: 0, y: 8)
        loadingLabel.alpha = 0
        dotsStackView.alpha = 0

        let heroAnimator = DexoMotion.propertyAnimator(
            duration: DexoMotion.emphasized,
            timingParameters: DexoMotion.softSpring
        )
        heroAnimator.addAnimations {
            self.rootStackView.alpha = 1
            self.rootStackView.transform = .identity
        }
        heroAnimator.startAnimation()
        DexoMotion.animate(duration: DexoMotion.standard, delay: 0.12) {
            self.valuesLabel.alpha = 1
            self.valuesLabel.transform = .identity
        }
        DexoMotion.animate(duration: DexoMotion.standard, delay: 0.22) {
            self.loadingLabel.alpha = 1
            self.dotsStackView.alpha = 1
        }
        startLoadingDots()
        startLogoBreathing()
    }

    func dismiss(completion: @escaping () -> Void) {
        stopLogoBreathing()
        DexoMotion.animate(
            duration: DexoMotion.standard,
            timingParameters: DexoMotion.easeInOutCubic,
            animations: {
                self.alpha = 0
                self.rootStackView.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            }
        ) { _ in
            self.stopLoadingDots()
            completion()
        }
    }

    private func setupUI() {
        rootStackView.axis = .vertical
        rootStackView.alignment = .center
        rootStackView.spacing = 18
        rootStackView.translatesAutoresizingMaskIntoConstraints = false

        linuxLogoView.image = UIImage(named: "LinuxDoLogo") ?? UIImage(named: "launchImg")
        linuxLogoView.contentMode = .scaleAspectFit
        linuxLogoView.translatesAutoresizingMaskIntoConstraints = false

        brandLabel.text = "DexoFlux"
        brandLabel.textAlignment = .center
        brandLabel.translatesAutoresizingMaskIntoConstraints = false

        valuesLabel.textAlignment = .center
        valuesLabel.numberOfLines = 2

        loadingLabel.textAlignment = .center

        dotsStackView.axis = .horizontal
        dotsStackView.alignment = .center
        dotsStackView.spacing = 7
        dotsStackView.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<3 {
            let dot = UIView()
            dot.layer.cornerRadius = 3.5
            dot.layer.cornerCurve = .continuous
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
            dotsStackView.addArrangedSubview(dot)
            dotViews.append(dot)
        }

        let loadingStack = UIStackView(arrangedSubviews: [loadingLabel, dotsStackView])
        loadingStack.axis = .vertical
        loadingStack.alignment = .center
        loadingStack.spacing = 12
        loadingStack.translatesAutoresizingMaskIntoConstraints = false

        rootStackView.addArrangedSubview(linuxLogoView)
        rootStackView.setCustomSpacing(24, after: linuxLogoView)
        rootStackView.addArrangedSubview(brandLabel)
        rootStackView.addArrangedSubview(valuesLabel)
        rootStackView.setCustomSpacing(28, after: valuesLabel)
        rootStackView.addArrangedSubview(loadingStack)
        addSubview(rootStackView)

        let preferredLogoWidth = linuxLogoView.widthAnchor.constraint(equalToConstant: 300)
        preferredLogoWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            rootStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            rootStackView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
            rootStackView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 26),
            rootStackView.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -26),

            preferredLogoWidth,
            linuxLogoView.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, multiplier: 0.84),
            linuxLogoView.heightAnchor.constraint(equalTo: linuxLogoView.widthAnchor, multiplier: 1.0 / 3.0),
        ])
    }

    private func startLoadingDots() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        for (index, dot) in dotViews.enumerated() {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.25
            animation.toValue = 1
            animation.duration = 0.62
            animation.beginTime = CACurrentMediaTime() + (Double(index) * 0.16)
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.layer.add(animation, forKey: "dexo.launch.dot")
        }
    }

    private func stopLoadingDots() {
        dotViews.forEach { $0.layer.removeAnimation(forKey: "dexo.launch.dot") }
    }

    private func startLogoBreathing() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1
        animation.toValue = 1.025
        animation.duration = 1.1
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        linuxLogoView.layer.add(animation, forKey: "dexo.launch.breathe")
    }

    private func stopLogoBreathing() {
        linuxLogoView.layer.removeAnimation(forKey: "dexo.launch.breathe")
    }
}

@MainActor
final class CloudflareBackgroundVerificationService {
    static let shared = CloudflareBackgroundVerificationService()
    static let needsUserInteractionNotification = Notification.Name("CloudflareBackgroundVerificationNeedsUserInteraction")

    private let attemptCooldown: TimeInterval = 12
    private var activeAttempts: [String: Task<Bool, Never>] = [:]
    private var lastAttemptAt: [String: Date] = [:]
    private var foregroundVerificationKeys = Set<String>()

    private init() {}

    func beginForegroundVerification(baseURL rawBaseURL: URL) async {
        let baseURL = normalizedBaseURL(rawBaseURL)
        let key = baseURL.absoluteString
        foregroundVerificationKeys.insert(key)
        guard let task = activeAttempts[key] else { return }
        log("cancelled base=\(key) reason=foreground_verification")
        task.cancel()
        _ = await task.value
        activeAttempts[key] = nil
    }

    func endForegroundVerification(baseURL rawBaseURL: URL) {
        let key = normalizedBaseURL(rawBaseURL).absoluteString
        foregroundVerificationKeys.remove(key)
        log("foreground verification ended base=\(key)")
    }

    func ensureInBackground(baseURL rawBaseURL: String, reason: String, responseURL: URL? = nil, force: Bool = false) {
        guard let baseURL = URL(string: normalizedBaseURL(rawBaseURL)) else { return }
        ensureInBackground(baseURL: baseURL, reason: reason, responseURL: responseURL, force: force)
    }

    func ensureInBackground(baseURL: URL, reason: String, responseURL: URL? = nil, force: Bool = false) {
        Task { @MainActor in
            _ = await ensureVerified(baseURL: baseURL, reason: reason, responseURL: responseURL, force: force)
        }
    }

    @discardableResult
    func ensureVerified(baseURL rawBaseURL: URL, reason: String, responseURL: URL? = nil, force: Bool = false) async -> Bool {
        let baseURL = normalizedBaseURL(rawBaseURL)
        let key = baseURL.absoluteString

        guard !foregroundVerificationKeys.contains(key) else {
            log("skipped reason=\(reason) base=\(key) skip=foreground_verification")
            return false
        }

        if let active = activeAttempts[key] {
            log("joined active attempt reason=\(reason) base=\(key)")
            return await active.value
        }

        if !force, let lastAttempt = lastAttemptAt[key],
           Date().timeIntervalSince(lastAttempt) < attemptCooldown {
            log("skipped reason=\(reason) base=\(key) skip=attempt_cooldown")
            postNeedsUserInteraction(baseURL: baseURL, responseURL: responseURL, reason: "cooldown")
            return false
        }

        lastAttemptAt[key] = Date()
        let task = Task { @MainActor in
            let attempt = CloudflareBackgroundVerificationAttempt(baseURL: baseURL, responseURL: responseURL, reason: reason)
            return await attempt.run()
        }
        activeAttempts[key] = task
        let ok = await task.value
        let wasCancelled = task.isCancelled
        activeAttempts[key] = nil

        if wasCancelled {
            log("discarded cancelled attempt reason=\(reason) base=\(key)")
            return false
        }

        if ok {
            log("completed reason=\(reason) base=\(key)")
            NotificationCenter.default.post(
                name: DiscourseAPI.cloudflareVerificationCompletedNotification,
                object: nil,
                userInfo: [
                    DiscourseAPI.cloudflareBaseURLUserInfoKey: key.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                ]
            )
        } else {
            postNeedsUserInteraction(baseURL: baseURL, responseURL: responseURL, reason: reason)
        }

        return ok
    }

    private func postNeedsUserInteraction(baseURL: URL, responseURL: URL?, reason: String) {
        log("needs user interaction reason=\(reason) base=\(baseURL.absoluteString)")
        var userInfo: [String: Any] = [
            DiscourseAPI.cloudflareBaseURLUserInfoKey: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
        ]
        if let responseURL {
            userInfo[DiscourseAPI.cloudflareResponseURLUserInfoKey] = responseURL
        }
        NotificationCenter.default.post(
            name: Self.needsUserInteractionNotification,
            object: nil,
            userInfo: userInfo
        )
    }

    private func normalizedBaseURL(_ url: URL) -> URL {
        let text = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: text) ?? url
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func log(_ message: String) {
        DohDebugLog.record("background \(message)", subsystem: "CF")
    }
}

@MainActor
private final class CloudflareBackgroundVerificationAttempt: NSObject, WKNavigationDelegate {
    private let baseURL: URL
    private let responseURL: URL?
    private let reason: String
    private let dataStore = WKWebsiteDataStore.default()
    private let maxDurationNanoseconds: UInt64 = 12_000_000_000
    private let checkDelays: [UInt64] = [
        250_000_000,
        700_000_000,
        1_500_000_000,
        2_500_000_000,
        4_000_000_000,
        7_000_000_000,
        10_000_000_000,
    ]

    private var webView: WKWebView?
    private var didFinish = false
    private var didFail = false
    private var lastFailure: String?
    private var initialClearanceValue: String?

    init(baseURL: URL, responseURL: URL?, reason: String) {
        self.baseURL = baseURL
        self.responseURL = responseURL
        self.reason = reason
        super.init()
    }

    func run() async -> Bool {
        let startedAt = Date()
        log("started reason=\(reason) base=\(baseURL.absoluteString) response=\(responseURL?.absoluteString ?? "none")")
        initialClearanceValue = WebCookieStore.shared.cookieValue(named: "cf_clearance", for: baseURL)
        await WebCookieStore.shared.syncToWebView(dataStore, for: baseURL)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        webView.navigationDelegate = self
        webView.customUserAgent = WebCookieStore.shared.userAgent
            ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        self.webView = webView

        var request = URLRequest(url: verificationURL())
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        webView.load(request)

        let ok = await runChecks()
        if ok {
            await updateStoredUserAgentFromWebView()
        }

        webView.stopLoading()
        webView.navigationDelegate = nil
        self.webView = nil

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        log("finished reason=\(reason) ok=\(ok) elapsedMs=\(elapsedMs) didFinish=\(didFinish) didFail=\(didFail) failure=\(lastFailure ?? "none")")
        return ok
    }

    private func runChecks() async -> Bool {
        let startedAt = Date()
        for delay in checkDelays {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return false }
            if UInt64(Date().timeIntervalSince(startedAt) * 1_000_000_000) > maxDurationNanoseconds {
                break
            }
            if await checkClearance() {
                return true
            }
        }
        return false
    }

    private func checkClearance() async -> Bool {
        await syncCloudflareCookieFromWebView()
        guard let webView else { return false }

        let clearanceValue = WebCookieStore.shared.cookieValue(named: "cf_clearance", for: baseURL)
        let hasClearance = CloudflareVerificationPolicy.hasUsableClearance(
            currentValue: clearanceValue,
            initialValue: initialClearanceValue,
            requiresFreshValue: responseURL != nil
        )
        let activeChallenge = await pageHasActiveCloudflareChallenge(in: webView)
        let currentURL = webView.url?.absoluteString ?? "none"

        log("check url=\(currentURL) cf=\(hasClearance) activeChallenge=\(activeChallenge)")
        return hasClearance && !activeChallenge
    }

    private func verificationURL() -> URL {
        CloudflareVerificationPolicy.verificationURL(
            baseURL: baseURL,
            responseURL: responseURL
        )
    }

    private func syncCloudflareCookieFromWebView() async {
        await WebCookieStore.shared.syncFromWebView(
            dataStore,
            names: ["cf_clearance"],
            for: baseURL
        )
    }

    private func updateStoredUserAgentFromWebView() async {
        guard let webView,
              let userAgent = try? await webView.evaluateJavaScript("navigator.userAgent") as? String
        else { return }
        WebCookieStore.shared.userAgent = userAgent
    }

    private func pageHasActiveCloudflareChallenge(in webView: WKWebView) async -> Bool {
        guard let pageText = try? await webView.evaluateJavaScript("""
            [
              document.title || '',
              document.body ? document.body.innerText : '',
              document.body ? document.body.innerHTML : ''
            ].join('\\n')
            """) as? String else {
            return true
        }
        return Self.hasActiveCloudflareChallenge(in: pageText)
    }

    private static func hasActiveCloudflareChallenge(in pageText: String) -> Bool {
        let lowerText = pageText.lowercased()
        return lowerText.contains("cf-turnstile")
            || lowerText.contains("challenge-running")
            || lowerText.contains("challenge-stage")
            || lowerText.contains("cf_chl_opt")
            || lowerText.contains("challenge-platform")
            || (lowerText.contains("just a moment") && lowerText.contains("cloudflare"))
    }

    private func log(_ message: String) {
        DohDebugLog.record("background attempt \(message)", subsystem: "CF")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish = true
        log("didFinish url=\(webView.url?.absoluteString ?? "none")")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        log("didCommit url=\(webView.url?.absoluteString ?? "none")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        didFail = true
        lastFailure = error.localizedDescription
        log("didFail url=\(webView.url?.absoluteString ?? "none") error=\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        didFail = true
        lastFailure = error.localizedDescription
        log("didFailProvisional url=\(webView.url?.absoluteString ?? "none") error=\(error.localizedDescription)")
    }
}
