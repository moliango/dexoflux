import UIKit
import WebKit

/// Presents a WKWebView so users can log in to a Discourse forum via their browser.
/// Fires onSuccess once the Discourse session cookie `_t` is detected.
final class WebLoginViewController: UIViewController {
    private let targetURL: URL
    private let onSuccess: ([HTTPCookie], String?) -> Void
    private let credentialStore: WebLoginCredentialStore

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let wv = WKWebView(frame: .zero, configuration: config)
        config.userContentController.add(coordinator, name: "dexoLoginCredentials")
        wv.navigationDelegate = coordinator
        wv.uiDelegate = coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()

    private lazy var coordinator = Coordinator(
        targetURL: targetURL,
        onCookiesReady: { [weak self] cookies in self?.handleCookiesReady(cookies) },
        onCredentialsCaptured: { [weak self] username, password in
            self?.credentialStore.save(username: username, password: password)
        }
    )

    private lazy var progressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.translatesAutoresizingMaskIntoConstraints = false
        return pv
    }()

    private var progressObservation: NSKeyValueObservation?

    init(targetURL: URL, onSuccess: @escaping ([HTTPCookie], String?) -> Void) {
        self.targetURL = targetURL
        self.onSuccess = onSuccess
        credentialStore = WebLoginCredentialStore(host: targetURL.host ?? "forum")
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "weblogin.title")
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        let doneButton = UIBarButtonItem(
            title: String(localized: "weblogin.done"), style: .done, target: self, action: #selector(doneTapped)
        )
        let pasteButton = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.clipboard"), style: .plain, target: self, action: #selector(pasteLoginLinkTapped)
        )
        pasteButton.accessibilityLabel = String(localized: "weblogin.paste_link", defaultValue: "粘贴邮箱登录链接")
        let credentialsButton = UIBarButtonItem(
            image: UIImage(systemName: "key.fill"), style: .plain, target: self, action: #selector(credentialsTapped)
        )
        credentialsButton.accessibilityLabel = String(localized: "weblogin.saved_password", defaultValue: "已保存的账号密码")
        navigationItem.rightBarButtonItems = [doneButton, credentialsButton, pasteButton]

        view.addSubview(webView)
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
            self?.progressView.progress = Float(wv.estimatedProgress)
            self?.progressView.isHidden = wv.estimatedProgress >= 1.0
        }

        coordinator.owner = self
        coordinator.attach(to: webView.configuration.websiteDataStore)
        webView.load(URLRequest(url: targetURL))
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        coordinator.collectAndFireIfPossible(from: webView, force: true)
    }

    @objc private func pasteLoginLinkTapped() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              url.host?.caseInsensitiveCompare(targetURL.host ?? "") == .orderedSame,
              url.path.hasPrefix("/session/email-login/")
        else {
            showMessage(String(localized: "weblogin.invalid_email_link", defaultValue: "剪切板中没有有效的邮箱登录链接。"))
            return
        }
        webView.load(URLRequest(url: url))
    }

    @objc private func credentialsTapped() {
        let sheet = UIAlertController(
            title: String(localized: "weblogin.saved_password", defaultValue: "已保存的账号密码"),
            message: credentialStore.username.map { String(localized: "weblogin.last_account", defaultValue: "上次登录：\($0)") },
            preferredStyle: .actionSheet
        )
        if credentialStore.hasCredentials {
            sheet.addAction(UIAlertAction(title: String(localized: "weblogin.fill_credentials", defaultValue: "填充账号密码"), style: .default) { [weak self] _ in
                self?.injectCredentialHelpers(fillSavedCredentials: true)
            })
            sheet.addAction(UIAlertAction(title: String(localized: "weblogin.clear_credentials", defaultValue: "清除保存的账号密码"), style: .destructive) { [weak self] _ in
                self?.credentialStore.clear()
            })
        } else {
            sheet.message = String(localized: "weblogin.no_credentials", defaultValue: "登录时输入的账号密码会安全保存在 Keychain。")
        }
        sheet.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?[1]
        present(sheet, animated: true)
    }

    private func injectCredentialHelpers(fillSavedCredentials: Bool = true) {
        let username = fillSavedCredentials ? credentialStore.username : nil
        let password = fillSavedCredentials ? credentialStore.password : nil
        let usernameLiteral = Self.javascriptLiteral(username)
        let passwordLiteral = Self.javascriptLiteral(password)
        let script = """
        (function() {
          const savedUser = \(usernameLiteral);
          const savedPass = \(passwordLiteral);
          let attempts = 0;
          const timer = setInterval(function() {
            const user = document.getElementById('login-account-name');
            const pass = document.getElementById('login-account-password');
            if (user && pass) {
              if (savedUser && savedPass) {
                user.value = savedUser;
                pass.value = savedPass;
                user.dispatchEvent(new Event('input', {bubbles:true}));
                pass.dispatchEvent(new Event('input', {bubbles:true}));
              }
              const button = document.getElementById('login-button');
              if (button && !button.dataset.dexoCredentialHook) {
                button.dataset.dexoCredentialHook = '1';
                button.addEventListener('click', function() {
                  if (user.value && pass.value) {
                    window.webkit.messageHandlers.dexoLoginCredentials.postMessage({username:user.value,password:pass.value});
                  }
                }, true);
              }
              clearInterval(timer);
            }
            if (++attempts > 30) clearInterval(timer);
          }, 300);
        })();
        """
        webView.evaluateJavaScript(script)
    }

    private static func javascriptLiteral(_ value: String?) -> String {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else { return "null" }
        return String(array.dropFirst().dropLast())
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
        present(alert, animated: true)
    }

    private func handleCookiesReady(_ cookies: [HTTPCookie]) {
        Task { @MainActor in
            await WebCookieStore.shared.syncFromWebView(webView.configuration.websiteDataStore)
            if let ua = try? await webView.evaluateJavaScript("navigator.userAgent") as? String {
                WebCookieStore.shared.userAgent = ua
            }
            let ua = WebCookieStore.shared.userAgent
            dismiss(animated: true) {
                self.onSuccess(cookies, ua)
            }
        }
    }

    private final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver, WKScriptMessageHandler {
        private let targetHost: String
        private let onCookiesReady: ([HTTPCookie]) -> Void
        private let onCredentialsCaptured: (String, String) -> Void
        private(set) var didCallback = false

        init(targetURL: URL, onCookiesReady: @escaping ([HTTPCookie]) -> Void, onCredentialsCaptured: @escaping (String, String) -> Void) {
            self.targetHost = targetURL.host ?? ""
            self.onCookiesReady = onCookiesReady
            self.onCredentialsCaptured = onCredentialsCaptured
        }

        func attach(to dataStore: WKWebsiteDataStore) {
            dataStore.httpCookieStore.add(self)
        }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
        {
            completionHandler(.performDefaultHandling, nil)
        }

        func collectAndFireIfPossible(from webView: WKWebView, force: Bool = false) {
            guard !didCallback else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.didCallback else { return }
                let relevant = cookies.filter { $0.domain.contains(self.targetHost) }
                let hasSession = relevant.contains { $0.name == "_t" }
                guard hasSession || force else { return }
                self.didCallback = true
                DispatchQueue.main.async { self.onCookiesReady(relevant) }
            }
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                cookieStore.getAllCookies { cookies in
                    guard !self.didCallback else { return }
                    let relevant = cookies.filter { $0.domain.contains(self.targetHost) }
                    let hasSession = relevant.contains { $0.name == "_t" }
                    guard hasSession else { return }
                    self.didCallback = true
                    DispatchQueue.main.async { self.onCookiesReady(relevant) }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            collectAndFireIfPossible(from: webView)
            (webView.navigationDelegate as? Coordinator)?.owner?.injectCredentialHelpers()
        }

        weak var owner: WebLoginViewController?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "dexoLoginCredentials",
                  let body = message.body as? [String: Any],
                  let username = body["username"] as? String, !username.isEmpty,
                  let password = body["password"] as? String, !password.isEmpty else { return }
            onCredentialsCaptured(username, password)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView?
        {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

private final class WebLoginCredentialStore {
    private let service: String
    private let usernameAccount = "username"
    private let passwordAccount = "password"

    init(host: String) {
        service = "com.naine.dexoflux.web-login.\(host.lowercased())"
    }

    var username: String? { KeychainHelper.string(service: service, account: usernameAccount) }
    var password: String? { KeychainHelper.string(service: service, account: passwordAccount) }
    var hasCredentials: Bool { username?.isEmpty == false && password?.isEmpty == false }

    func save(username: String, password: String) {
        try? KeychainHelper.setString(username, service: service, account: usernameAccount)
        try? KeychainHelper.setString(password, service: service, account: passwordAccount)
    }

    func clear() {
        KeychainHelper.deleteString(service: service, account: usernameAccount)
        KeychainHelper.deleteString(service: service, account: passwordAccount)
    }
}
