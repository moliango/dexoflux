import UIKit
import WebKit

final class ForumContainerViewController: UIViewController, AuthGating {
    private static let cloudflareShieldSuppressionDuration: TimeInterval = 6

    private(set) var forum: ForumInstance
    private let api: DiscourseAPI
    private let authManager = AuthManager.shared
    private let showsDismissButton: Bool
    private var authObservationToken: NSObjectProtocol?
    private var cloudflareChallengeObservationToken: NSObjectProtocol?
    private var cloudflareCompletionObservationToken: NSObjectProtocol?
    private var cloudflareNeedsUserObservationToken: NSObjectProtocol?
    private var isPresentingCloudflareVerification = false
    private var shouldShowCloudflareShieldButton = false
    private var cloudflareShieldSuppressedUntil: Date?
    private var pendingCloudflareBaseURL: URL?
    private var cloudflareShieldButtonConstraints: [NSLayoutConstraint] = []
    private weak var cloudflareShieldButtonHostView: UIView?

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
        view.backgroundColor = .systemGroupedBackground

        authManager.restoreAuthState(for: forum)
        if authManager.hasWebSession(for: forum.baseURL) {
            WebSessionRefreshService.shared.ensureInBackground(forum: forum, reason: "forum_container_loaded")
        }

        setupTabBar()
        setupCloudflareShieldButton()
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
        if let cloudflareChallengeObservationToken {
            NotificationCenter.default.removeObserver(cloudflareChallengeObservationToken)
        }
        if let cloudflareCompletionObservationToken {
            NotificationCenter.default.removeObserver(cloudflareCompletionObservationToken)
        }
        if let cloudflareNeedsUserObservationToken {
            NotificationCenter.default.removeObserver(cloudflareNeedsUserObservationToken)
        }
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
                self?.performLogout()
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
        presentCloudflareVerification(baseURL: baseURL)
    }

    private func handleCloudflareChallengeNotification(_ notification: Notification) {
        guard let baseURLString = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURLString) == normalizedBaseURL(forum.baseURL) else { return }
        guard let baseURL = URL(string: baseURLString) ?? URL(string: forum.baseURL) else { return }
        let responseURL = notification.userInfo?[DiscourseAPI.cloudflareResponseURLUserInfoKey] as? URL
        pendingCloudflareBaseURL = baseURL
        guard !isCloudflareShieldSuppressed() else {
            logCloudflareState("challenge ignored while shield is suppressed base=\(baseURLString)")
            setCloudflareShieldButtonVisible(false, animated: true)
            return
        }
        logCloudflareState("challenge detected; starting background verification base=\(baseURLString)")
        if !isPresentingCloudflareVerification {
            setCloudflareShieldButtonVisible(true, animated: true)
        }
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
        pendingCloudflareBaseURL = baseURL
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
        isPresentingCloudflareVerification = false
        pendingCloudflareBaseURL = nil
        suppressCloudflareShieldTemporarily()
        setCloudflareShieldButtonVisible(false, animated: true)
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

    private func presentCloudflareVerification(baseURL: URL) {
        guard !isPresentingCloudflareVerification else {
            logCloudflareState("foreground verification skipped because verification is already presented")
            return
        }
        guard view.window != nil else { return }
        guard let presenter = topMostPresenter(), !presenter.isBeingDismissed else { return }

        pendingCloudflareBaseURL = baseURL
        isPresentingCloudflareVerification = true
        setCloudflareShieldButtonVisible(false, animated: true)
        let vc = CloudflareVerificationViewController(
            baseURL: baseURL,
            autoDismissOnSuccess: true
        ) { [weak self] in
            self?.handleCloudflareVerificationClosed()
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = self
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        presenter.present(nav, animated: true)
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

    func performLogout() {
        authManager.logout(forum: forum)
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
                let didRecover = await self.authManager.refreshWebSessionUserIfPossible(forum: self.forum)
                await MainActor.run {
                    self.refreshForumFromDatabase()
                    if didRecover {
                        action()
                    } else {
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
        let vc = WebLoginViewController(targetURL: url) { [weak self] cookies, userAgent in
            guard let self else { return }
            Task {
                let didLogin = await self.authManager.loginViaWeb(forum: self.forum, cookies: cookies, userAgent: userAgent)
                self.refreshForumFromDatabase()
                guard didLogin else { return }
                action()
            }
        }
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
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

extension ForumContainerViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        handleCloudflareVerificationClosed()
    }
}

@MainActor
final class CloudflareBackgroundVerificationService {
    static let shared = CloudflareBackgroundVerificationService()
    static let needsUserInteractionNotification = Notification.Name("CloudflareBackgroundVerificationNeedsUserInteraction")

    private let attemptCooldown: TimeInterval = 12
    private var activeAttempts: [String: Task<Bool, Never>] = [:]
    private var lastAttemptAt: [String: Date] = [:]

    private init() {}

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
        activeAttempts[key] = nil

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

    init(baseURL: URL, responseURL: URL?, reason: String) {
        self.baseURL = baseURL
        self.responseURL = responseURL
        self.reason = reason
        super.init()
    }

    func run() async -> Bool {
        let startedAt = Date()
        log("started reason=\(reason) base=\(baseURL.absoluteString) response=\(responseURL?.absoluteString ?? "none")")
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
        let hasClearance = clearanceValue?.isEmpty == false
        let activeChallenge = await pageHasActiveCloudflareChallenge(in: webView)
        let currentURL = webView.url?.absoluteString ?? "none"

        log("check url=\(currentURL) cf=\(hasClearance) activeChallenge=\(activeChallenge)")
        return hasClearance && !activeChallenge
    }

    private func verificationURL() -> URL {
        URL(string: "/404?__dexo_cf_bg=\(Int(Date().timeIntervalSince1970))", relativeTo: baseURL)?.absoluteURL
            ?? responseURL
            ?? baseURL
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
