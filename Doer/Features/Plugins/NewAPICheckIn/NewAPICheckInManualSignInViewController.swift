import UIKit
import WebKit

/// 「网页签到」— 对应原 NewAPSign `ManualSignInView`。
///
/// 与 `NewAPICheckInLoginViewController` 的区别:
/// - **不自动检测登录完成**,没有轮询 / 探针 / fallback 计时器,也不弹「完成登录」按钮。
/// - 打开站点时**预注入已保存的 Cookie**,让用户落在已登录状态,在网页里手动点签到按钮。
/// - 每次导航结束后**把 WebView 里最新的 Cookie 写回** credential,后续「立即签到」可用。
/// - 主要给被 Cloudflare / Aliyun WAF 拦截、URLSession TLS 指纹被识别的站点用:
///   WKWebView 是浏览器级网络栈,WAF 放行;URLSession 过不去。
///
/// ponytail: Doer 没有 NewAPSign 的 `SharedCookiesRepository`(跨平台共享 OAuth
/// Cookie,如 LinuxDo / GitHub),所以只预注入当前平台自己的 Cookie,不注入共享 OAuth
/// 会话。需要多平台共用同一 OAuth 提供商时,每个平台仍需各自走一次登录。
@MainActor
final class NewAPICheckInManualSignInViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let platform: NewAPICheckInPlatform
    private let store: NewAPICheckInStore
    private let onChange: () -> Void

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // OAuth 提供商(LinuxDo / GitHub)常通过 `window.open(...)` 发起异步授权,
        // 不开此项弹窗会在 WKUIDelegate 看到之前被静默丢弃。
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        // 伪装成 Mobile Safari。不加 `Safari/X` 后缀,Cloudflare 的机器人检测会
        // 让 JS 挑战页无限转圈。与 NewAPICheckInLoginViewController 保持一致。
        configuration.applicationNameForUserAgent = "Version/17.4 Mobile/15E148 Safari/604.1"
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        return view
    }()

    private var persistTask: Task<Void, Never>?

    init(
        platform: NewAPICheckInPlatform,
        store: NewAPICheckInStore,
        onChange: @escaping () -> Void
    ) {
        self.platform = platform
        self.store = store
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = platform.name
        view.backgroundColor = .systemBackground
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        configureToolbar()

        // 先注入已存 Cookie,再加载站点;否则会与 cookie store 竞争,落在登录页。
        Task { [weak self] in
            guard let self else { return }
            await self.injectStoredCookies()
            if let url = URL(string: self.platform.baseURL) {
                self.webView.load(URLRequest(url: url))
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true || isBeingDismissed {
            persistTask?.cancel()
            persistTask = nil
        }
    }

    deinit {
        persistTask?.cancel()
    }

    // MARK: - Toolbar

    private func configureToolbar() {
        let reload = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(reloadTapped)
        )
        reload.accessibilityLabel = String(localized: "common.reload", defaultValue: "刷新")

        let clearPlatform = UIAction(
            title: String(localized: "plugins.newapi.manual.clear_platform", defaultValue: "清除当前平台 Cookie"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            Task { await self?.clearCookies(includingShared: false) }
        }

        let clearAll = UIAction(
            title: String(localized: "plugins.newapi.manual.clear_all", defaultValue: "清除全部 Cookie"),
            image: UIImage(systemName: "trash.fill"),
            attributes: .destructive
        ) { [weak self] _ in
            Task { await self?.clearCookies(includingShared: true) }
        }

        let more = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(title: "", children: [clearPlatform, clearAll])
        )
        more.accessibilityLabel = String(localized: "common.more", defaultValue: "更多")

        navigationItem.rightBarButtonItems = [more, reload]
    }

    @objc private func reloadTapped() {
        webView.reload()
    }

    // MARK: - Cookie injection (initial)

    private func injectStoredCookies() async {
        guard
            let baseURL = URL(string: platform.baseURL),
            let credential = try? await store.credential(for: platform.id),
            let header = credential.cookieHeader,
            !header.isEmpty
        else { return }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in Self.parseCookieHeader(header, baseURL: baseURL) {
            await store.setCookie(cookie)
        }
    }

    /// 把 `Cookie: a=1; b=2` 请求头拆成单个 `HTTPCookie`。
    /// `HTTPCookie.cookies(withResponseHeaderFields:for:)` 解析的是 `Set-Cookie`,
    /// 不能用来解析请求头,所以手动拆。
    private static func parseCookieHeader(_ header: String, baseURL: URL) -> [HTTPCookie] {
        let host = baseURL.host ?? ""
        return header.split(separator: ";").compactMap { piece in
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { return nil }
            let name = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            guard !name.isEmpty else { return nil }
            return HTTPCookie(properties: [
                .name: name,
                .value: value,
                .domain: host,
                .path: "/",
            ])
        }
    }

    // MARK: - Cookie persistence

    /// 导航结束后把 WebView 当前 Cookie 分区写回:
    /// - 匹配平台域名的 → 写进 credential.cookieHeader(后续「立即签到」会用)
    /// - 同时尝试从 localStorage 抽 userID / accessToken,补进 credential
    /// 仅在停在平台域名上时才写;OAuth 回调中间页跳过。
    private func persistCookies() async {
        guard
            let baseURL = URL(string: platform.baseURL),
            let currentURL = webView.url,
            NewAPICheckInLoginSupport.samePlatformFamily(baseURL, currentURL)
        else { return }

        // OAuth 回调 URL(code= / token= + state=)是中间步骤,会话未建立,跳过。
        if Self.isOAuthCallback(currentURL) { return }

        let allCookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let cookieHeader = NewAPICheckInLoginSupport.cookieHeader(
            from: allCookies,
            baseURL: baseURL,
            currentURL: currentURL
        )
        guard cookieHeader != nil else { return }

        let localStorageValue = try? await webView.evaluateJavaScript(NewAPICheckInLoginSupport.localStorageScript)
        let hints = NewAPICheckInLoginSupport.parseLocalStorageResult(localStorageValue)

        let previous = try? await store.credential(for: platform.id)
        let credential = NewAPICheckInCredential(
            accessToken: hints.accessToken ?? previous?.accessToken,
            userID: hints.userID ?? previous?.userID,
            cookieHeader: cookieHeader ?? previous?.cookieHeader,
            additionalHeaders: previous?.additionalHeaders ?? [:]
        )

        var updated = platform
        try? await store.save(updated, credential: credential)
        onChange()
    }

    private static func isOAuthCallback(_ url: URL) -> Bool {
        guard let query = url.query else { return false }
        let lower = query.lowercased()
        return (lower.contains("code=") || lower.contains("token=")) && lower.contains("state=")
    }

    // MARK: - Cookie clearing

    private func clearCookies(includingShared: Bool) async {
        let dataStore = webView.configuration.websiteDataStore
        if includingShared {
            await dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            )
        } else if let baseURL = URL(string: platform.baseURL),
                  let targetHost = baseURL.host?.lowercased() {
            let allCookies = await dataStore.httpCookieStore.allCookies()
            for cookie in allCookies where NewAPICheckInLoginSupport.cookieDomain(cookie.domain, matchesHost: targetHost) {
                await dataStore.httpCookieStore.deleteCookie(cookie)
            }
        }

        // 同步清掉 credential 里的 cookieHeader,保持一致。
        if let previous = try? await store.credential(for: platform.id) {
            let cleaned = NewAPICheckInCredential(
                accessToken: previous.accessToken,
                userID: previous.userID,
                cookieHeader: nil,
                additionalHeaders: previous.additionalHeaders
            )
            var updated = platform
            try? await store.save(updated, credential: cleaned)
            onChange()
        }

        if let url = URL(string: platform.baseURL) {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 等 JS 执行完再读 localStorage / cookie,延迟 2 秒。
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.persistCookies()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        switch url.scheme?.lowercased() {
        case "http", "https", "about", "data", "blob", nil:
            break
        default:
            decisionHandler(.cancel)
            return
        }
        // `target="_blank"` / window.open 落回当前 WebView,OAuth 弹窗才不会丢。
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let requestURL = navigationAction.request.url {
            webView.load(URLRequest(url: requestURL))
        }
        return nil
    }
}
