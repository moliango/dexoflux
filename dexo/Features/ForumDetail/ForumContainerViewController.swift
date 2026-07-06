import UIKit
import WebKit

final class ForumContainerViewController: UIViewController, AuthGating {
    private(set) var forum: ForumInstance
    private let api: DiscourseAPI
    private let authManager = AuthManager.shared
    private let showsDismissButton: Bool
    private var authObservationToken: NSObjectProtocol?
    private var cloudflareChallengeObservationToken: NSObjectProtocol?
    private var isPresentingCloudflareVerification = false

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
        configureNavItems()
        startObservingAuth()
        startObservingCloudflareChallenges()
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
    }

    @MainActor deinit {
        if let authObservationToken {
            NotificationCenter.default.removeObserver(authObservationToken)
        }
        if let cloudflareChallengeObservationToken {
            NotificationCenter.default.removeObserver(cloudflareChallengeObservationToken)
        }
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

    private func handleCloudflareChallengeNotification(_ notification: Notification) {
        guard !isPresentingCloudflareVerification else { return }
        guard let baseURLString = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURLString) == normalizedBaseURL(forum.baseURL) else { return }
        guard let baseURL = URL(string: baseURLString) ?? URL(string: forum.baseURL) else { return }
        let responseURL = notification.userInfo?[DiscourseAPI.cloudflareResponseURLUserInfoKey] as? URL
        DohDebugLog.record("container challenge detected; starting background verification", subsystem: "CF")
        CloudflareBackgroundVerificationService.shared.ensureInBackground(
            baseURL: baseURL,
            reason: "container_challenge",
            responseURL: responseURL
        )
    }

    private func presentCloudflareVerification(baseURL: URL) {
        guard view.window != nil else { return }
        guard let presenter = topMostPresenter(), !presenter.isBeingDismissed else { return }

        isPresentingCloudflareVerification = true
        let vc = CloudflareVerificationViewController(
            baseURL: baseURL,
            autoDismissOnSuccess: true
        ) { [weak self] in
            self?.isPresentingCloudflareVerification = false
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.presentationController?.delegate = self
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(nav, animated: true)
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
        isPresentingCloudflareVerification = false
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
