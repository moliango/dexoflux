import UIKit

enum LinuxDoExtensionService: String, CaseIterable, Codable {
    case ldc
    case cdk

    var baseURL: URL {
        switch self {
        case .ldc: return URL(string: "https://credit.linux.do")!
        case .cdk: return URL(string: "https://cdk.linux.do")!
        }
    }

    var title: String { self == .ldc ? "LINUX DO Credits" : "LINUX DO CDK" }
    var dashboardURL: URL { baseURL.appendingPathComponent(self == .ldc ? "home" : "dashboard") }
    var symbolName: String { self == .ldc ? "creditcard.fill" : "seal.fill" }
}

struct LinuxDoExtensionUserInfo: Codable {
    let id: Int
    let username: String
    let nickname: String
    let trustLevel: Int
    let avatarURL: String
    let availableBalance: String?
    let communityBalance: String?
    let score: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, score
        case trustLevel = "trust_level"
        case avatarURL = "avatar_url"
        case availableBalance = "available_balance"
        case communityBalance = "community_balance"
    }

    var balanceText: String { availableBalance ?? score.map(String.init) ?? "--" }
}

private struct LinuxDoExtensionEnvelope<T: Decodable>: Decodable {
    let data: T
}

enum LinuxDoExtensionError: LocalizedError {
    case invalidResponse
    case authorizationPage
    case callback
    case cloudflare(URL, URL?)
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return String(localized: "extensions.error.response", defaultValue: "服务返回了无效响应。")
        case .authorizationPage: return String(localized: "extensions.error.authorization", defaultValue: "无法解析授权页面。")
        case .callback: return String(localized: "extensions.error.callback", defaultValue: "授权回调缺少必要参数。")
        case .cloudflare: return String(localized: "cloudflare.challenge.required", defaultValue: "需要完成 Cloudflare 验证后重试。")
        case let .http(code, message): return message?.isEmpty == false ? message : "HTTP \(code)"
        }
    }
}

final class LinuxDoExtensionHTTPClient {
    struct Response {
        let data: Data
        let http: HTTPURLResponse
    }

    private let forumBaseURL: String

    init(forumBaseURL: String) {
        self.forumBaseURL = forumBaseURL
    }

    func request(
        _ url: URL,
        method: String = "GET",
        form: [String: String]? = nil,
        json: [String: Any]? = nil,
        headers: [String: String] = [:],
        followRedirects: Bool = true
    ) async throws -> Data {
        try await requestResponse(
            url,
            method: method,
            form: form,
            json: json,
            headers: headers,
            followRedirects: followRedirects
        ).data
    }

    func requestResponse(
        _ url: URL,
        method: String = "GET",
        form: [String: String]? = nil,
        json: [String: Any]? = nil,
        headers: [String: String] = [:],
        followRedirects: Bool = true
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json, text/html;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        if let userAgent = WebCookieStore.shared.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        let cookieHeader = WebCookieStore.shared.cookieHeader(for: url)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let json {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if let form {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = form
                .map { key, value in "\(Self.escape(key))=\(Self.escape(value))" }
                .sorted()
                .joined(separator: "&")
                .data(using: .utf8)
        }

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        if let proxy = LightweightDohProxyService.shared.connectionProxyDictionary(for: forumBaseURL) {
            configuration.connectionProxyDictionary = proxy
        }
        let session = URLSession(
            configuration: configuration,
            delegate: LinuxDoExtensionRedirectDelegate(followRedirects: followRedirects),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LinuxDoExtensionError.invalidResponse }
        var responseHeaderFields: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            responseHeaderFields[String(describing: key)] = String(describing: value)
        }
        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: responseHeaderFields, for: url)
        if !responseCookies.isEmpty {
            WebCookieStore.shared.setCookies(responseCookies)
        }
        if DiscourseAPI.isCloudflareChallengeResponse(http, data: data) {
            // connect.linux.do 的 OAuth 同意页也会带 cloudflare 脚本标记；
            // 若已能解析 approve 链接，说明不是挑战页，继续静默授权。
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let isOAuthConsentPage = bodyText.contains("/oauth2/approve/")
                || bodyText.localizedCaseInsensitiveContains("LINUX DO Connect")
                || bodyText.localizedCaseInsensitiveContains("获取你的用户基本信息")
            if !isOAuthConsentPage {
                guard let scheme = url.scheme, let host = url.host else {
                    throw LinuxDoExtensionError.invalidResponse
                }
                var components = URLComponents()
                components.scheme = scheme
                components.host = host
                components.port = url.port
                guard let challengedBaseURL = components.url else {
                    throw LinuxDoExtensionError.invalidResponse
                }
                throw LinuxDoExtensionError.cloudflare(challengedBaseURL, http.url)
            }
        }
        guard (200..<400).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["message"] ?? $0["msg"] ?? $0["error"]) as? String }
            throw LinuxDoExtensionError.http(http.statusCode, message)
        }
        return Response(data: data, http: http)
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private final class LinuxDoExtensionRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private let followRedirects: Bool

    init(followRedirects: Bool) {
        self.followRedirects = followRedirects
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let responseURL = response.url {
            WebCookieStore.shared.mergeResponseHeaders(
                response.allHeaderFields,
                for: responseURL
            )
        }
        guard followRedirects else {
            completionHandler(nil)
            return
        }
        guard let targetURL = request.url else {
            completionHandler(request)
            return
        }
        var redirectedRequest = request
        redirectedRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        let cookieHeader = WebCookieStore.shared.cookieHeader(for: targetURL)
        if !cookieHeader.isEmpty {
            redirectedRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let userAgent = WebCookieStore.shared.userAgent {
            redirectedRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        completionHandler(redirectedRequest)
    }
}

final class LinuxDoExtensionOAuthCoordinator {
    private let service: LinuxDoExtensionService
    private let client: LinuxDoExtensionHTTPClient

    init(service: LinuxDoExtensionService, forumBaseURL: String) {
        self.service = service
        client = LinuxDoExtensionHTTPClient(forumBaseURL: forumBaseURL)
    }

    func authorize(from viewController: UIViewController) async throws -> LinuxDoExtensionUserInfo? {
        // FluxDo 同款静默 OAuth：API 拉授权页 → 原生确认弹窗 → approve → callback，不打开内置浏览器。
        let loginData = try await client.request(service.baseURL.appendingPathComponent("api/v1/oauth/login"))
        let authURLString = try JSONDecoder().decode(LinuxDoExtensionEnvelope<String>.self, from: loginData).data
        guard let authURL = URL(string: authURLString) else { throw LinuxDoExtensionError.invalidResponse }

        // 模拟业务页加载完成再跳 OAuth 同意页
        try await Task.sleep(nanoseconds: UInt64.random(in: 600_000_000...1_200_000_000))

        let pageData = try await client.request(authURL, followRedirects: false)
        guard let html = String(data: pageData, encoding: .utf8),
              let approvePath = Self.approvePath(in: html)
        else { throw LinuxDoExtensionError.authorizationPage }

        guard let approveURL = URL(string: approvePath, relativeTo: URL(string: "https://connect.linux.do"))?.absoluteURL else {
            throw LinuxDoExtensionError.authorizationPage
        }

        let allowed = await Self.presentAuthorizationConfirm(
            from: viewController,
            service: service
        )
        guard allowed else { return nil }

        try await Task.sleep(nanoseconds: UInt64.random(in: 400_000_000...900_000_000))

        let approveResponse = try await client.requestResponse(
            approveURL,
            followRedirects: false
        )
        let location = approveResponse.http.value(forHTTPHeaderField: "Location")
        let callbackURL = location.flatMap { URL(string: $0, relativeTo: approveURL)?.absoluteURL }
            ?? Self.callbackURL(from: approveResponse.data)
            ?? approveURL
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        else { throw LinuxDoExtensionError.callback }

        try await Task.sleep(nanoseconds: UInt64.random(in: 300_000_000...700_000_000))

        _ = try await client.request(
            service.baseURL.appendingPathComponent("api/v1/oauth/callback"),
            method: "POST",
            json: ["code": code, "state": state],
            headers: ["X-Requested-With": "XMLHttpRequest"]
        )
        return try await fetchUserInfo()
    }

    @MainActor
    private static func presentAuthorizationConfirm(
        from viewController: UIViewController,
        service: LinuxDoExtensionService
    ) async -> Bool {
        let message: String
        switch service {
        case .ldc:
            message = String(
                localized: "extensions.auth.ldc.message",
                defaultValue: "Linux.do Credit 将获取你的基本信息，是否允许？"
            )
        case .cdk:
            message = String(
                localized: "extensions.auth.cdk.message",
                defaultValue: "Linux.do CDK 将获取你的基本信息，是否允许？"
            )
        }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: String(localized: "extensions.auth.confirm_title", defaultValue: "授权确认"),
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(
                title: String(localized: "extensions.auth.deny", defaultValue: "拒绝"),
                style: .cancel
            ) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(
                title: String(localized: "extensions.auth.allow", defaultValue: "允许"),
                style: .default
            ) { _ in
                continuation.resume(returning: true)
            })
            viewController.present(alert, animated: true)
        }
    }

    func fetchUserInfo() async throws -> LinuxDoExtensionUserInfo {
        let data = try await client.request(service.baseURL.appendingPathComponent("api/v1/oauth/user-info"))
        return try JSONDecoder().decode(LinuxDoExtensionEnvelope<LinuxDoExtensionUserInfo>.self, from: data).data
    }

    func logout() async throws {
        _ = try await client.request(service.baseURL.appendingPathComponent("api/v1/oauth/logout"))
    }

    private static func approvePath(in html: String) -> String? {
        let patterns = [
            #"href=["']([^"']*/oauth2/approve/[^"']*)["']"#,
            #"action=["']([^"']*/oauth2/approve/[^"']*)["']"#,
            #"["'](/oauth2/approve/[^"']+)["']"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html)
            else { continue }
            return String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
        }
        return nil
    }

    private static func callbackURL(from data: Data) -> URL? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #"https?://[^\"'<>\s]+[?&]code=[^\"'<>\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return URL(string: String(text[range]).replacingOccurrences(of: "&amp;", with: "&"))
    }

}

final class LinuxDoExtensionCache {
    private let scope: String
    private let defaults: UserDefaults

    init(baseURL: String, username: String?, defaults: UserDefaults = .standard) {
        scope = AccountScopeKey.make(baseURL: baseURL, username: username)
        self.defaults = defaults
    }

    func isEnabled(_ service: LinuxDoExtensionService) -> Bool { defaults.bool(forKey: key(service, "enabled")) }
    func setEnabled(_ enabled: Bool, service: LinuxDoExtensionService) { defaults.set(enabled, forKey: key(service, "enabled")) }
    func userInfo(_ service: LinuxDoExtensionService) -> LinuxDoExtensionUserInfo? {
        defaults.data(forKey: key(service, "user")) .flatMap { try? JSONDecoder().decode(LinuxDoExtensionUserInfo.self, from: $0) }
    }
    func setUserInfo(_ info: LinuxDoExtensionUserInfo?, service: LinuxDoExtensionService) {
        defaults.set(info.flatMap { try? JSONEncoder().encode($0) }, forKey: key(service, "user"))
    }
    private func key(_ service: LinuxDoExtensionService, _ suffix: String) -> String { "extensions.\(scope).\(service.rawValue).\(suffix)" }
}

final class LDCMerchantCredentialsStore {
    struct Credentials { let clientID: String; let clientSecret: String }
    private let account: String
    private let service = "com.naine.dexoflux.ldc-reward"

    init(baseURL: String, username: String?) { account = AccountScopeKey.make(baseURL: baseURL, username: username) }
    func load() -> Credentials? {
        guard let raw = KeychainHelper.string(service: service, account: account),
              let data = raw.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: String].self, from: data),
              let id = object["id"], let secret = object["secret"] else { return nil }
        return Credentials(clientID: id, clientSecret: secret)
    }
    func save(clientID: String, clientSecret: String) throws {
        let data = try JSONEncoder().encode(["id": clientID, "secret": clientSecret])
        try KeychainHelper.setString(String(decoding: data, as: UTF8.self), service: service, account: account)
    }
    func clear() { KeychainHelper.deleteString(service: service, account: account) }
}

final class LDCRewardService {
    private let client: LinuxDoExtensionHTTPClient
    init(forumBaseURL: String) { client = LinuxDoExtensionHTTPClient(forumBaseURL: forumBaseURL) }

    func reward(credentials: LDCMerchantCredentialsStore.Credentials, userID: Int, username: String, amount: Decimal, topicID: Int, postID: Int, remark: String?) async throws {
        let auth = Data("\(credentials.clientID):\(credentials.clientSecret)".utf8).base64EncodedString()
        let trade = "LDR_T\(topicID)_P\(postID)_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 1000...9999))"
        var payload: [String: Any] = [
            "user_id": userID,
            "username": username,
            "amount": NSDecimalNumber(decimal: amount).stringValue,
            "out_trade_no": trade,
        ]
        if let remark, !remark.isEmpty { payload["remark"] = remark }
        _ = try await client.request(
            URL(string: "https://credit.linux.do/epay/pay/distribute")!,
            method: "POST",
            json: payload,
            headers: ["Authorization": "Basic \(auth)"]
        )
    }
}

final class MetaverseServicesViewController: UITableViewController {
    private let api: DiscourseAPI
    private let username: String
    private let cache: LinuxDoExtensionCache
    private let credentialStore: LDCMerchantCredentialsStore
    private var processing = Set<LinuxDoExtensionService>()

    private var pluginScope: PluginScope {
        PluginScope(baseURL: api.baseURL, username: username)
    }

    private var visibleServices: [LinuxDoExtensionService] {
        let registry = DexoPluginRuntime.shared.registry
        return LinuxDoExtensionService.allCases.filter { service in
            registry.isPluginEnabled(pluginID(for: service), for: pluginScope)
        }
    }

    private var isLDCPluginEnabled: Bool {
        DexoPluginRuntime.shared.registry.isPluginEnabled(BuiltInPluginID.ldc, for: pluginScope)
    }

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
        cache = LinuxDoExtensionCache(baseURL: api.baseURL, username: username)
        credentialStore = LDCMerchantCredentialsStore(baseURL: api.baseURL, username: username)
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "extensions.title", defaultValue: "元宇宙")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "service")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshServices), for: .valueChanged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pluginStateDidChange),
            name: PluginStateStore.stateDidChangeNotification,
            object: nil
        )
        Task { await refreshEnabledServices() }
    }

    @MainActor
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { isLDCPluginEnabled ? 2 : 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? visibleServices.count : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? String(localized: "extensions.services", defaultValue: "我的服务") : String(localized: "extensions.ldc.reward", defaultValue: "LDC 打赏")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "service", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let service = visibleServices[indexPath.row]
            let enabled = cache.isEnabled(service)
            let info = cache.userInfo(service)
            content.image = UIImage(systemName: service.symbolName)
            content.text = service.title
            content.secondaryText = enabled ? "\(info?.username ?? username) · \(info?.balanceText ?? "--")" : String(localized: "extensions.connect", defaultValue: "点击连接账户")
            cell.accessoryType = enabled ? .detailButton : .disclosureIndicator
            cell.isUserInteractionEnabled = !processing.contains(service)
        } else {
            content.image = UIImage(systemName: "hands.sparkles.fill")
            content.text = String(localized: "extensions.ldc.credentials", defaultValue: "商户凭证")
            content.secondaryText = credentialStore.load() == nil ? String(localized: "extensions.ldc.credentials.empty", defaultValue: "配置后可向帖子作者打赏") : String(localized: "extensions.ldc.credentials.ready", defaultValue: "已安全保存在 Keychain")
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 { showCredentialEditor(); return }
        let service = visibleServices[indexPath.row]
        if cache.isEnabled(service) { showEnabledActions(service, source: tableView.cellForRow(at: indexPath)) }
        else { Task { await authorize(service) } }
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard indexPath.section == 0 else { return }
        showEnabledActions(visibleServices[indexPath.row], source: tableView.cellForRow(at: indexPath))
    }

    @objc private func refreshServices() { Task { await refreshEnabledServices() } }
    private func refreshEnabledServices() async {
        for service in visibleServices where cache.isEnabled(service) {
            do {
                let info = try await LinuxDoExtensionOAuthCoordinator(service: service, forumBaseURL: api.baseURL).fetchUserInfo()
                cache.setUserInfo(info, service: service)
            } catch { }
        }
        refreshControl?.endRefreshing()
        tableView.reloadData()
    }

    @objc private func pluginStateDidChange() {
        guard !visibleServices.isEmpty else {
            navigationController?.popViewController(animated: true)
            return
        }
        tableView.reloadData()
    }

    private func pluginID(for service: LinuxDoExtensionService) -> String {
        switch service {
        case .ldc: return BuiltInPluginID.ldc
        case .cdk: return BuiltInPluginID.cdk
        }
    }

    private func authorize(
        _ service: LinuxDoExtensionService,
        allowCloudflareVerification: Bool = true
    ) async {
        guard processing.insert(service).inserted else { return }
        tableView.reloadData()
        defer { processing.remove(service); tableView.reloadData() }
        do {
            if let info = try await LinuxDoExtensionOAuthCoordinator(service: service, forumBaseURL: api.baseURL).authorize(from: self) {
                cache.setEnabled(true, service: service)
                cache.setUserInfo(info, service: service)
            }
        } catch LinuxDoExtensionError.cloudflare(let baseURL, let responseURL) {
            if allowCloudflareVerification {
                presentServiceCloudflareVerification(
                    service: service,
                    baseURL: baseURL,
                    responseURL: responseURL
                )
            } else {
                show(LinuxDoExtensionError.cloudflare(baseURL, responseURL))
            }
        } catch {
            show(error)
        }
    }

    private func presentServiceCloudflareVerification(
        service: LinuxDoExtensionService,
        baseURL: URL,
        responseURL: URL?
    ) {
        // 验证页只用站点根地址换 cf_clearance，绝不用 OAuth 同意页 URL（否则会整页嵌进 WebView）。
        let verificationURL = service.baseURL
        let verifier = CloudflareVerificationViewController(
            baseURL: baseURL.host?.contains("connect.linux.do") == true
                ? URL(string: "https://connect.linux.do")!
                : service.baseURL,
            responseURL: nil,
            verificationURL: verificationURL,
            autoDismissOnSuccess: true
        ) { [weak self] in
            guard let self else { return }
            Task {
                await self.authorize(
                    service,
                    allowCloudflareVerification: false
                )
            }
        }
        let navigation = UINavigationController(rootViewController: verifier)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }

    private func showEnabledActions(_ service: LinuxDoExtensionService, source: UIView?) {
        let sheet = UIAlertController(title: service.title, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "extensions.open_dashboard", defaultValue: "打开服务页面"), style: .default) { [weak self] _ in
            guard let self else { return }
            let browser = InAppBrowserViewController(
                api: self.api,
                username: self.username,
                initialURL: service.dashboardURL
            )
            self.navigationController?.pushViewController(browser, animated: true)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "extensions.reauthorize", defaultValue: "重新授权"), style: .default) { [weak self] _ in Task { await self?.authorize(service) } })
        sheet.addAction(UIAlertAction(title: String(localized: "extensions.disable", defaultValue: "停用服务"), style: .destructive) { [weak self] _ in Task { await self?.disable(service) } })
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = source ?? view
        sheet.popoverPresentationController?.sourceRect = source?.bounds ?? view.bounds
        present(sheet, animated: true)
    }

    private func disable(_ service: LinuxDoExtensionService) async {
        try? await LinuxDoExtensionOAuthCoordinator(service: service, forumBaseURL: api.baseURL).logout()
        cache.setEnabled(false, service: service)
        cache.setUserInfo(nil, service: service)
        tableView.reloadData()
    }

    private func showCredentialEditor() {
        let existing = credentialStore.load()
        let alert = UIAlertController(title: String(localized: "extensions.ldc.credentials", defaultValue: "商户凭证"), message: "credit.linux.do/merchant", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Client ID"; $0.text = existing?.clientID }
        alert.addTextField { $0.placeholder = "Client Secret"; $0.isSecureTextEntry = true; $0.text = existing?.clientSecret }
        if existing != nil { alert.addAction(UIAlertAction(title: String(localized: "extensions.credentials.clear", defaultValue: "清除凭证"), style: .destructive) { [weak self] _ in self?.credentialStore.clear(); self?.tableView.reloadData() }) }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields, fields.count == 2 else { return }
            let id = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let secret = fields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty, !secret.isEmpty else { return }
            do { try self.credentialStore.save(clientID: id, clientSecret: secret); self.tableView.reloadData() } catch { self.show(error) }
        })
        present(alert, animated: true)
    }

    private func show(_ error: Error) {
        let alert = UIAlertController(title: String(localized: "extensions.error.title", defaultValue: "操作失败"), message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default))
        present(alert, animated: true)
    }
}

final class LDCRewardFormViewController: UIViewController {
    private let api: DiscourseAPI
    private let targetUserID: Int
    private let targetUsername: String
    private let topicID: Int
    private let postID: Int
    private let credentials: LDCMerchantCredentialsStore.Credentials
    private let amountField = UITextField()
    private let remarkField = UITextField()

    init(api: DiscourseAPI, targetUserID: Int, targetUsername: String, topicID: Int, postID: Int, credentials: LDCMerchantCredentialsStore.Credentials) {
        self.api = api; self.targetUserID = targetUserID; self.targetUsername = targetUsername; self.topicID = topicID; self.postID = postID; self.credentials = credentials
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "extensions.ldc.reward", defaultValue: "LDC 打赏")
        view.backgroundColor = .systemGroupedBackground
        amountField.placeholder = "1 / 5 / 10 / 50 LDC"
        amountField.keyboardType = .decimalPad
        amountField.borderStyle = .roundedRect
        remarkField.placeholder = String(localized: "extensions.ldc.remark", defaultValue: "备注（可选）")
        remarkField.borderStyle = .roundedRect
        let button = UIButton(type: .system)
        button.configuration = .filled()
        button.setTitle(String(localized: "extensions.ldc.reward.confirm", defaultValue: "确认打赏"), for: .normal)
        button.addTarget(self, action: #selector(submit), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [amountField, remarkField, button])
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24), stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), amountField.heightAnchor.constraint(equalToConstant: 48), remarkField.heightAnchor.constraint(equalToConstant: 48), button.heightAnchor.constraint(equalToConstant: 48)])
    }

    @objc private func submit() {
        guard let text = amountField.text, let decimal = Decimal(string: text), decimal >= 0.01, decimal <= 10000 else { return }
        let alert = UIAlertController(title: String(localized: "extensions.ldc.reward.confirm", defaultValue: "确认打赏"), message: "@\(targetUsername) · \(text) LDC", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await LDCRewardService(forumBaseURL: self.api.baseURL).reward(credentials: self.credentials, userID: self.targetUserID, username: self.targetUsername, amount: decimal, topicID: self.topicID, postID: self.postID, remark: self.remarkField.text)
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    let errorAlert = UIAlertController(title: String(localized: "extensions.error.title", defaultValue: "操作失败"), message: error.localizedDescription, preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default))
                    self.present(errorAlert, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }
}
