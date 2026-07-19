import UIKit
import WebKit

final class InAppBrowserViewController: UIViewController {
    private let baseURL: URL
    private let store: BrowserHistoryStore
    private let initialURL: URL?
    let hidesHostTabBarAtRoot: Bool
    private let hidesBrowserControlBar: Bool

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        if let userAgent = WebCookieStore.shared.userAgent {
            webView.customUserAgent = userAgent
        }
        return webView
    }()

    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .bar)
        progress.translatesAutoresizingMaskIntoConstraints = false
        return progress
    }()

    private let addressField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .never
        field.returnKeyType = .go
        field.placeholder = String(localized: "me.browser.address.placeholder", defaultValue: "输入网址或路径")
        return field
    }()

    private let securityImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "lock.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let controlBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let addressCapsule = UIView()
    private let errorView = BrowserErrorView()
    private lazy var backButton = makeControlButton(systemName: "chevron.backward", action: #selector(backTapped))
    private lazy var forwardButton = makeControlButton(systemName: "chevron.forward", action: #selector(forwardTapped))
    private lazy var reloadButton = makeControlButton(systemName: "arrow.clockwise", action: #selector(reloadTapped))
    private lazy var moreButton = makeControlButton(systemName: "ellipsis", action: #selector(moreTapped))

    private var progressObservation: NSKeyValueObservation?
    private var popupWebView: WKWebView?
    init(
        api: DiscourseAPI,
        username: String?,
        initialURL: URL? = nil,
        hidesHostTabBarAtRoot: Bool = false,
        hidesBrowserControlBar: Bool = false
    ) {
        let normalizedBase = api.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.baseURL = URL(string: normalizedBase) ?? URL(string: "https://linux.do")!
        self.store = BrowserHistoryStore(baseURL: api.baseURL, username: username)
        self.initialURL = initialURL
        self.hidesHostTabBarAtRoot = hidesHostTabBarAtRoot
        self.hidesBrowserControlBar = hidesBrowserControlBar
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = String(localized: "me.browser", defaultValue: "内置浏览器")
        view.backgroundColor = .systemBackground
        addressField.delegate = self
        configureControlBar()
        controlBar.isHidden = hidesBrowserControlBar
        controlBar.isUserInteractionEnabled = !hidesBrowserControlBar
        configureNavigationItem()
        backButton.accessibilityLabel = String(localized: "me.browser.back", defaultValue: "后退")
        forwardButton.accessibilityLabel = String(localized: "me.browser.forward", defaultValue: "前进")
        reloadButton.accessibilityLabel = String(localized: "me.browser.reload", defaultValue: "刷新")
        moreButton.accessibilityLabel = String(localized: "me.browser.toolbar_action", defaultValue: "更多操作")

        view.addSubview(progressView)
        view.addSubview(webView)
        view.addSubview(errorView)
        view.addSubview(controlBar)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            controlBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            controlBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            controlBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            controlBar.heightAnchor.constraint(equalToConstant: 52),
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.progressView.progress = Float(webView.estimatedProgress)
                self?.progressView.isHidden = webView.estimatedProgress >= 1
            }
        }

        errorView.onRetry = { [weak self] in self?.reloadTapped() }
        Task { await load(initialURL ?? baseURL) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
        store.reload()
        updateControlState()
        if hidesHostTabBarAtRoot {
            (tabBarController as? ForumTabBarController)?.syncTabBarVisibilityForCurrentContent()
        }
    }

    private func configureNavigationItem() {
        if hidesHostTabBarAtRoot {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "xmark"),
                style: .plain,
                target: self,
                action: #selector(closeRootBrowserTapped)
            )
            navigationItem.leftBarButtonItem?.accessibilityLabel = String(
                localized: "plugins.ldc_store.close",
                defaultValue: "关闭 LD 士多"
            )
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "books.vertical"),
            style: .plain,
            target: self,
            action: #selector(libraryTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "me.browser.library", defaultValue: "浏览器资料库")
    }

    private func configureControlBar() {
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.layer.cornerRadius = 18
        controlBar.layer.cornerCurve = .continuous
        controlBar.clipsToBounds = true
        controlBar.layer.borderWidth = 0.5
        controlBar.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor

        addressCapsule.translatesAutoresizingMaskIntoConstraints = false
        addressCapsule.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.82)
        addressCapsule.layer.cornerRadius = 14
        addressCapsule.layer.cornerCurve = .continuous

        let stack = UIStackView(arrangedSubviews: [backButton, forwardButton, addressCapsule, reloadButton, moreButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5
        controlBar.contentView.addSubview(stack)
        addressCapsule.addSubview(securityImageView)
        addressCapsule.addSubview(addressField)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controlBar.contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: controlBar.contentView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: controlBar.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: controlBar.contentView.bottomAnchor, constant: -6),
            backButton.widthAnchor.constraint(equalToConstant: 34),
            forwardButton.widthAnchor.constraint(equalToConstant: 34),
            reloadButton.widthAnchor.constraint(equalToConstant: 34),
            moreButton.widthAnchor.constraint(equalToConstant: 34),
            securityImageView.leadingAnchor.constraint(equalTo: addressCapsule.leadingAnchor, constant: 10),
            securityImageView.centerYAnchor.constraint(equalTo: addressCapsule.centerYAnchor),
            securityImageView.widthAnchor.constraint(equalToConstant: 12),
            securityImageView.heightAnchor.constraint(equalToConstant: 12),
            addressField.leadingAnchor.constraint(equalTo: securityImageView.trailingAnchor, constant: 7),
            addressField.trailingAnchor.constraint(equalTo: addressCapsule.trailingAnchor, constant: -8),
            addressField.topAnchor.constraint(equalTo: addressCapsule.topAnchor),
            addressField.bottomAnchor.constraint(equalTo: addressCapsule.bottomAnchor),
        ])
    }

    private func makeControlButton(systemName: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func load(_ url: URL) async {
        guard let normalizedURL = BrowserHistoryStore.normalizedPageURL(url) else {
            showMessage(BrowserHistoryStoreError.unsupportedURL.localizedDescription)
            return
        }
        do {
            try store.recordVisit(url: normalizedURL, title: normalizedURL.host)
        } catch {
            showMessage(error.localizedDescription)
        }
        await WebCookieStore.shared.syncToWebView(webView.configuration.websiteDataStore, for: normalizedURL)
        addressField.text = normalizedURL.absoluteString
        errorView.isHidden = true
        webView.load(URLRequest(url: normalizedURL))
    }

    private func normalizedAddressURL() -> URL? {
        let text = addressField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("/") {
            return URL(string: text, relativeTo: baseURL)?.absoluteURL
        }
        let candidate = text.contains("://") ? text : "https://\(text)"
        return URL(string: candidate)
    }

    private func updateControlState() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
        reloadButton.setImage(UIImage(systemName: webView.isLoading ? "xmark" : "arrow.clockwise"), for: .normal)
        securityImageView.image = UIImage(systemName: webView.url?.scheme?.lowercased() == "https" ? "lock.fill" : "globe")
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }

    @objc private func goTapped() {
        guard let url = normalizedAddressURL() else {
            showMessage(String(localized: "me.browser.invalid_url", defaultValue: "请输入有效网址。"))
            return
        }
        Task { await load(url) }
    }

    @objc private func closeRootBrowserTapped() {
        tabBarController?.selectedIndex = 0
        (tabBarController as? ForumTabBarController)?.syncTabBarVisibilityForCurrentContent()
    }

    @objc private func backTapped() { webView.goBack() }
    @objc private func forwardTapped() { webView.goForward() }
    @objc private func reloadTapped() {
        if webView.isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
        updateControlState()
    }
    @objc private func homeTapped() { Task { await load(baseURL) } }

    @objc private func bookmarkTapped() {
        guard let url = webView.url else { return }
        do {
            if store.isBookmarked(url) {
                try store.removeBookmark(url: url)
            } else {
                try store.addBookmark(url: url, title: webView.title)
            }
            updateControlState()
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    @objc private func libraryTapped() {
        let library = BrowserLibraryViewController(store: store) { [weak self] url in
            guard let self else { return }
            self.navigationController?.popViewController(animated: true)
            Task { await self.load(url) }
        }
        navigationController?.pushViewController(library, animated: true)
    }

    @objc private func shareTapped() {
        guard let url = webView.url else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = moreButton
        activity.popoverPresentationController?.sourceRect = moreButton.bounds
        present(activity, animated: true)
    }

    @objc private func moreTapped() {
        let isBookmarked = store.isBookmarked(webView.url)
        let menu = UIAlertController(title: webView.title, message: webView.url?.host, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(
            title: isBookmarked
                ? String(localized: "me.browser.remove_bookmark", defaultValue: "取消书签")
                : String(localized: "me.browser.add_bookmark", defaultValue: "添加书签"),
            style: .default
        ) { [weak self] _ in self?.bookmarkTapped() })
        menu.addAction(UIAlertAction(title: String(localized: "me.browser.copy_url", defaultValue: "复制链接"), style: .default) { [weak self] _ in
            UIPasteboard.general.url = self?.webView.url
        })
        menu.addAction(UIAlertAction(title: String(localized: "me.browser.share", defaultValue: "分享当前网页"), style: .default) { [weak self] _ in
            self?.shareTapped()
        })
        menu.addAction(UIAlertAction(title: String(localized: "me.browser.open_external", defaultValue: "在系统浏览器打开"), style: .default) { [weak self] _ in
            guard let url = self?.webView.url else { return }
            UIApplication.shared.open(url)
        })
        menu.addAction(UIAlertAction(title: String(localized: "me.browser.home", defaultValue: "Linux.do 首页"), style: .default) { [weak self] _ in
            self?.homeTapped()
        })
        menu.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        menu.popoverPresentationController?.sourceView = moreButton
        menu.popoverPresentationController?.sourceRect = moreButton.bounds
        present(menu, animated: true)
    }
}

extension InAppBrowserViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        goTapped()
        textField.resignFirstResponder()
        return true
    }
}

extension InAppBrowserViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if webView !== self.webView {
            switch BrowserNavigationURLClassifier.classify(url) {
            case .web:
                self.webView.load(navigationAction.request)
                popupWebView = nil
                decisionHandler(.cancel)
            case .internalWebKit:
                decisionHandler(.allow)
            case .externalApp:
                popupWebView = nil
                decisionHandler(.cancel)
                confirmExternalScheme(url)
            case .invalid:
                popupWebView = nil
                decisionHandler(.cancel)
            }
            return
        }
        switch BrowserNavigationURLClassifier.classify(url) {
        case .web, .internalWebKit:
            decisionHandler(.allow)
        case .externalApp:
            decisionHandler(.cancel)
            confirmExternalScheme(url)
        case .invalid:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorView.isHidden = true
        updateControlState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else {
            updateControlState()
            return
        }
        guard BrowserNavigationURLClassifier.classify(url) == .web else {
            updateControlState()
            return
        }
        addressField.text = url.absoluteString
        navigationItem.title = webView.title?.isEmpty == false
            ? webView.title
            : String(localized: "me.browser", defaultValue: "内置浏览器")
        updateControlState()
        do {
            try store.recordVisit(url: url, title: webView.title)
        } catch {
            showMessage(error.localizedDescription)
        }
        Task {
            await WebCookieStore.shared.syncFromWebView(webView.configuration.websiteDataStore, for: url)
            if let userAgent = try? await webView.evaluateJavaScript("navigator.userAgent") as? String {
                WebCookieStore.shared.userAgent = userAgent
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        errorView.configure(message: error.localizedDescription)
        errorView.isHidden = false
        updateControlState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        errorView.configure(message: error.localizedDescription)
        errorView.isHidden = false
        updateControlState()
    }

    private func confirmExternalScheme(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            showMessage(BrowserHistoryStoreError.unsupportedURL.localizedDescription)
            return
        }
        let alert = UIAlertController(
            title: String(localized: "me.browser.external_scheme.title", defaultValue: "打开其他应用？"),
            message: String(
                format: String(localized: "me.browser.external_scheme.message %@", defaultValue: "此链接需要交给 %@ 应用处理。"),
                scheme
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "me.browser.external_scheme.open", defaultValue: "继续打开"), style: .default) { _ in
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }
}

extension InAppBrowserViewController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url
        else { return nil }
        switch BrowserNavigationURLClassifier.classify(url) {
        case .web:
            webView.load(navigationAction.request)
            return nil
        case .internalWebKit:
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popupWebView = popup
            return popup
        case .externalApp:
            confirmExternalScheme(url)
            return nil
        case .invalid:
            return nil
        }
    }
}

private final class BrowserErrorView: UIView {
    var onRetry: (() -> Void)?

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        let imageView = UIImageView(image: UIImage(systemName: "wifi.exclamationmark"))
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.heightAnchor.constraint(equalToConstant: 38).isActive = true

        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "action.retry", defaultValue: "重试")
        configuration.cornerStyle = .capsule
        let retryButton = UIButton(configuration: configuration)
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [imageView, messageLabel, retryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(message: String) {
        messageLabel.text = message
    }
}

private final class BrowserLibraryViewController: UIViewController {
    private enum Section: Int {
        case history
        case bookmarks
    }

    private let store: BrowserHistoryStore
    private let onOpen: (URL) -> Void
    private var selectedSection: Section = .history
    private var searchQuery = ""

    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchResultsUpdater = self
        controller.searchBar.placeholder = String(localized: "me.browser.library.search", defaultValue: "搜索标题或网址")
        return controller
    }()

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            String(localized: "me.browser.history", defaultValue: "历史"),
            String(localized: "me.browser.bookmarks", defaultValue: "书签"),
        ])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(sectionChanged), for: .valueChanged)
        return control
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 12
        return tableView
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    init(store: BrowserHistoryStore, onOpen: @escaping (URL) -> Void) {
        self.store = store
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.browser.library", defaultValue: "浏览器资料库")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.titleView = segmentedControl
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        let clearItem = UIBarButtonItem(
            title: String(localized: "action.clear", defaultValue: "清空"),
            style: .plain,
            target: self,
            action: #selector(clearTapped)
        )
        let addItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addBookmarkTapped)
        )
        addItem.accessibilityLabel = String(localized: "me.browser.bookmark.manual_add", defaultValue: "手动添加书签")
        navigationItem.rightBarButtonItems = [clearItem, addItem]
        navigationController?.setToolbarHidden(true, animated: false)

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
        reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.reload()
        reloadData()
    }

    private var records: [BrowserPageRecord] {
        let source = selectedSection == .history ? store.history : store.bookmarks
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter { record in
            record.title.localizedCaseInsensitiveContains(query)
                || record.urlString.localizedCaseInsensitiveContains(query)
        }
    }

    private var unfilteredRecords: [BrowserPageRecord] {
        selectedSection == .history ? store.history : store.bookmarks
    }

    private func reloadData() {
        tableView.reloadData()
        tableView.isHidden = !records.isEmpty
        stateLabel.isHidden = !records.isEmpty
        if !searchQuery.isEmpty, records.isEmpty, !unfilteredRecords.isEmpty {
            stateLabel.text = String(localized: "me.browser.library.search.empty", defaultValue: "没有匹配的记录")
        } else {
            stateLabel.text = selectedSection == .history
                ? String(localized: "me.browser.history.empty", defaultValue: "没有本地浏览记录")
                : String(localized: "me.browser.bookmarks.empty", defaultValue: "没有本地书签")
        }
        navigationItem.rightBarButtonItems?.first?.isEnabled = !unfilteredRecords.isEmpty
    }

    @objc private func sectionChanged() {
        selectedSection = Section(rawValue: segmentedControl.selectedSegmentIndex) ?? .history
        reloadData()
    }

    @objc private func clearTapped() {
        let alert = UIAlertController(
            title: String(localized: "me.browser.clear.title", defaultValue: "清空当前列表？"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "action.clear", defaultValue: "清空"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                if self.selectedSection == .history {
                    try self.store.clearHistory()
                } else {
                    try self.store.clearBookmarks()
                }
                self.reloadData()
            } catch {
                self.showError(error)
            }
        })
        present(alert, animated: true)
    }

    @objc private func addBookmarkTapped() {
        let alert = UIAlertController(
            title: String(localized: "me.browser.bookmark.manual_add", defaultValue: "手动添加书签"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = String(localized: "me.browser.bookmark.title", defaultValue: "名称（可选）")
        }
        alert.addTextField { field in
            field.placeholder = String(localized: "me.browser.address.placeholder", defaultValue: "输入网址或路径")
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "action.add", defaultValue: "添加"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let address = alert?.textFields?[safe: 1]?.text,
                  let url = Self.normalizedManualURL(address)
            else {
                self?.showError(BrowserHistoryStoreError.unsupportedURL)
                return
            }
            do {
                try self.store.addBookmark(url: url, title: alert?.textFields?[safe: 0]?.text)
                self.selectedSection = .bookmarks
                self.segmentedControl.selectedSegmentIndex = Section.bookmarks.rawValue
                self.reloadData()
            } catch {
                self.showError(error)
            }
        })
        present(alert, animated: true)
    }

    private static func normalizedManualURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate) else { return nil }
        return BrowserHistoryStore.normalizedPageURL(url)
    }

    private func rename(_ record: BrowserPageRecord) {
        let alert = UIAlertController(
            title: String(localized: "me.browser.bookmark.rename", defaultValue: "重命名书签"),
            message: record.urlString,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = record.title
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "action.save", defaultValue: "保存"), style: .default) { [weak self, weak alert] _ in
            guard let self, let title = alert?.textFields?.first?.text else { return }
            do {
                try self.store.renameBookmark(record, title: title)
                self.reloadData()
            } catch {
                self.showError(error)
            }
        })
        present(alert, animated: true)
    }

    private func remove(_ record: BrowserPageRecord) {
        do {
            if selectedSection == .history {
                try store.removeHistory(record)
            } else {
                try store.removeBookmark(record)
            }
            reloadData()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }
}

extension BrowserLibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchQuery = searchController.searchBar.text ?? ""
        reloadData()
    }
}

extension BrowserLibraryViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = records[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: selectedSection == .history ? "clock" : "bookmark.fill")
        content.imageProperties.tintColor = selectedSection == .history ? .systemTeal : .systemOrange
        content.text = record.title
        content.secondaryText = "\(record.urlString) · \(relativeDate(record.timestamp))"
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .secondarySystemGroupedBackground
        cell.layer.cornerRadius = 14
        cell.layer.cornerCurve = .continuous
        cell.clipsToBounds = true
        return cell
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension BrowserLibraryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let url = URL(string: records[indexPath.row].urlString) else { return }
        onOpen(url)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let record = records[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: String(localized: "action.delete", defaultValue: "删除")) { [weak self] _, _, completion in
            self?.remove(record)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        var actions = [delete]
        if selectedSection == .bookmarks {
            let rename = UIContextualAction(style: .normal, title: String(localized: "action.rename", defaultValue: "重命名")) { [weak self] _, _, completion in
                self?.rename(record)
                completion(true)
            }
            rename.backgroundColor = .systemBlue
            rename.image = UIImage(systemName: "pencil")
            actions.append(rename)
        }
        return UISwipeActionsConfiguration(actions: actions)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
