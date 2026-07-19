import CookedHTML
import SafariServices
import UIKit

enum ForumInternalLinkDestination {
    case topic(id: Int, postNumber: Int?)
    case category(slug: String, id: Int)
    case tag(name: String)
}

enum ForumInternalLinkParser {
    static func normalizedURL(from url: URL, baseURL: String) -> URL {
        if url.scheme == nil, url.absoluteString.hasPrefix("//") {
            return URL(string: "https:\(url.absoluteString)") ?? url
        }

        guard url.host == nil, url.scheme == nil,
              let base = URL(string: baseURL)
        else {
            return url
        }

        return URL(string: url.absoluteString, relativeTo: base)?.absoluteURL ?? url
    }

    static func isInternalURL(_ url: URL, baseURL: String) -> Bool {
        guard let baseHost = URL(string: baseURL)?.host,
              let linkHost = url.host
        else { return false }

        return normalizedHost(baseHost) == normalizedHost(linkHost)
    }

    static func destination(for url: URL) -> ForumInternalLinkDestination? {
        if let topic = parseTopicInfo(from: url) {
            return .topic(id: topic.id, postNumber: topic.postNumber)
        }
        if let (slug, categoryId) = parseCategoryInfo(from: url) {
            return .category(slug: slug, id: categoryId)
        }
        if let tagName = parseTagName(from: url) {
            return .tag(name: tagName)
        }
        return nil
    }

    private static func normalizedHost(_ host: String) -> String {
        var value = host.lowercased()
        while value.hasSuffix(".") {
            value.removeLast()
        }
        if value.hasPrefix("www.") {
            value.removeFirst(4)
        }
        return value
    }

    private static func parseTopicInfo(from url: URL) -> (id: Int, postNumber: Int?)? {
        let components = url.pathComponents
        guard let tIndex = components.firstIndex(of: "t") else { return nil }
        var numbers: [Int] = []
        for component in components.dropFirst(tIndex + 1) {
            let cleaned = component.replacingOccurrences(of: ".json", with: "")
            if let id = Int(cleaned) {
                numbers.append(id)
            }
        }
        guard let topicId = numbers.first else { return nil }
        return (topicId, numbers.dropFirst().first)
    }

    private static func parseCategoryInfo(from url: URL) -> (slug: String, id: Int)? {
        let components = url.pathComponents
        guard let cIndex = components.firstIndex(of: "c"),
              cIndex + 2 < components.count else { return nil }
        let remaining = Array(components[(cIndex + 1)...])
        for i in remaining.indices.reversed() {
            let cleaned = remaining[i].replacingOccurrences(of: ".json", with: "")
            if let id = Int(cleaned), i > 0 {
                return (remaining[i - 1], id)
            }
        }
        return nil
    }

    private static func parseTagName(from url: URL) -> String? {
        let components = url.pathComponents
        guard let tagIndex = components.firstIndex(where: { $0 == "tag" || $0 == "tags" }),
              tagIndex + 1 < components.count
        else { return nil }
        return components[tagIndex + 1].removingPercentEncoding ?? components[tagIndex + 1]
    }
}

enum ForumAttachmentLinkParser {
    private static let mediaExtensions: Set<String> = [
        "apng", "avif", "gif", "heic", "heif", "jpeg", "jpg", "mov", "mp3", "mp4", "mpeg", "ogg", "png", "svg",
        "wav", "webm", "webp",
    ]

    private static let fileExtensions: Set<String> = [
        "7z", "apk", "bz2", "c", "conf", "cpp", "csv", "dart", "db", "diff", "dmg", "doc", "docx", "gz",
        "h", "hpp", "html", "ipa", "java", "js", "json", "key", "kt", "log", "md", "msi", "numbers", "otf",
        "pages", "patch", "pdf", "php", "pkg", "ppt", "pptx", "py", "rar", "rb", "rs", "sh", "sql", "sqlite",
        "swift", "tar", "toml", "ts", "ttf", "txt", "woff", "woff2", "xls", "xlsx", "xml", "xz", "yaml", "yml",
        "zip",
    ]

    static func isAttachmentURL(_ url: URL) -> Bool {
        let path = url.path.removingPercentEncoding?.lowercased() ?? url.path.lowercased()
        let ext = url.pathExtension.lowercased()

        if mediaExtensions.contains(ext) {
            return false
        }

        if fileExtensions.contains(ext) {
            return true
        }

        if path.contains("/uploads/") || path.contains("/secure-uploads/") {
            return true
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return queryItems.contains { item in
            let name = item.name.lowercased()
            if name == "download" { return true }
            if name == "dl", item.value == "1" { return true }
            return false
        }
    }
}

enum ForumAttachmentDownloadError: LocalizedError {
    case invalidFile
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return String(localized: "attachment.download_failed")
        case let .httpStatus(statusCode):
            return "\(String(localized: "attachment.download_failed")) (\(statusCode))"
        }
    }
}

enum ForumAttachmentDownloader {
    static func download(url: URL, baseURL: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let cookieHeader = WebCookieStore.shared.cookieHeader(for: url)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let userAgent = WebCookieStore.shared.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        if let proxy = LightweightDohProxyService.shared.connectionProxyDictionary(for: proxyBaseURL(for: url, fallback: baseURL)) {
            config.connectionProxyDictionary = proxy
        }

        let session = URLSession(configuration: config)
        defer {
            session.finishTasksAndInvalidate()
        }

        let (temporaryURL, response) = try await session.download(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode) {
            throw ForumAttachmentDownloadError.httpStatus(httpResponse.statusCode)
        }

        let filename = sanitizedFilename(response.suggestedFilename, fallbackURL: url)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DexoAttachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: temporaryURL, to: destination)
        return destination
    }

    static func cleanupDownloadedFile(_ url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
    }

    private static func proxyBaseURL(for url: URL, fallback: String) -> String {
        guard let scheme = url.scheme, let host = url.host else {
            return fallback
        }
        return "\(scheme)://\(host)"
    }

    private static func sanitizedFilename(_ suggestedName: String?, fallbackURL: URL) -> String {
        let fallback = fallbackURL.lastPathComponent.removingPercentEncoding
        let rawName = [suggestedName, fallback, "attachment"]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "attachment"

        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let clean = rawName.components(separatedBy: forbidden).joined(separator: "_")
        return clean.isEmpty ? "attachment" : clean
    }
}

final class TopicDetailViewController: ObservableViewController {
    private let viewModel: TopicDetailViewModel
    private let api: DiscourseAPI
    private let topicId: Int
    private let initialFloor: Int?
    private let baseURL: String
    private var hasTitleHeader = false
    private var lastCategoryPresentation: TopicCategoryBadgePresentation?
    private var isLoadingEarlierLocally = false
    private var pendingScrollToFloor: Int?
    private var lastScrollOffset: CGFloat = 0
    /// Suppress load-earlier after a jump until user scrolls down first
    private var suppressLoadEarlier = false
    /// Anchor info for restoring scroll position after loading earlier posts
    private var earlierLoadAnchor: (postId: Int, cellTopOffset: CGFloat)?
    private struct PendingPostSnapshot {
        let itemIDs: [Int]
        let earlierAnchor: (postId: Int, cellTopOffset: CGFloat)?
    }
    private var isApplyingPostSnapshot = false
    private var pendingPostSnapshot: PendingPostSnapshot?
    private var lastReadingComfortMode = AppSettings.shared.readingComfortMode
    private var lastContentFontSize = AppSettings.shared.contentFontSize
    private var lastContentFontScalePercent = AppSettings.shared.contentFontScalePercent
    private var lastContentFontFamily = AppSettings.shared.contentFontFamily
    private var lastContentFontScope = AppSettings.shared.contentFontScope
    private var lastInterfaceFontScalePercent = AppSettings.shared.interfaceFontScalePercent
    private var lastThemeStyle = AppSettings.shared.themeStyle
    private var hasPresentedInitialContent = false
    private var isHandlingBackSwipeFallback = false
    private weak var backSwipeFallbackHostView: UIView?
    private lazy var readingTracker = TopicReadingTracker(api: api)
    private var isShowingCollapsedNavigationTitle = false
    private var lastBottomBarProgressState: (current: Int, total: Int)?
    private var downloadedAttachmentURLs: Set<URL> = []
    private var prefetchedImagePostIds = Set<Int>()
    private var pendingSharedIssueTopicIds = Set<Int>()
    private var cloudflareCompletionObservationToken: NSObjectProtocol?

    private var pluginScope: PluginScope {
        PluginScope(
            baseURL: api.baseURL,
            username: AuthManager.shared.username(for: api.baseURL)
        )
    }

    private enum BackSwipeFallbackMetrics {
        static let edgeActivationWidth: CGFloat = 44
        static let minimumCompletionTranslation: CGFloat = 64
        static let minimumCompletionVelocity: CGFloat = 480
    }

    private lazy var backSwipeFallbackGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleBackSwipeFallback(_:)))
        gesture.maximumNumberOfTouches = 1
        gesture.cancelsTouchesInView = true
        gesture.delegate = self
        return gesture
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(PostNativeCell.self, forCellReuseIdentifier: PostNativeCell.reuseIdentifier)
        tv.delegate = self
        tv.separatorStyle = .none
        tv.backgroundColor = .systemGroupedBackground
        tv.showsVerticalScrollIndicator = !AppSettings.shared.hideScrollIndicators
        tv.showsHorizontalScrollIndicator = false
        tv.isHidden = true
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = .init(tableView: tableView) { [weak self] tableView, indexPath, postId in
        guard let self,
              let post = self.viewModel.posts.first(where: { $0.id == postId })
        else {
            return UITableViewCell()
        }

        guard let annotatedBlocks = self.viewModel.parsedBlocks[postId],
              let cell = tableView.dequeueReusableCell(withIdentifier: PostNativeCell.reuseIdentifier, for: indexPath) as? PostNativeCell
        else {
            return UITableViewCell()
        }
        let visiblePosts = self.viewModel.visiblePosts
        let floorNumber: Int
        if self.viewModel.isFilteringByOP {
            floorNumber = (visiblePosts.firstIndex(where: { $0.id == postId }) ?? 0) + 1
        } else {
            // Use stream-based floor number when not filtering
            let allPostIds = self.viewModel.allPostIds
            if let streamIndex = allPostIds.firstIndex(of: postId) {
                floorNumber = streamIndex + 1
            } else {
                floorNumber = (visiblePosts.firstIndex(where: { $0.id == postId }) ?? 0) + 1
            }
        }
        let postLink = "\(self.baseURL)/t/\(self.topicId)/\(post.postNumber)"
        let renderContentWidth = PostNativeCell.renderContentWidth(
            for: tableView.bounds.width,
            isFirstPost: floorNumber == 1
        )
        let galleryImageURLs = TopicImageGallerySources.urls(from: annotatedBlocks)
        let config = NativeRenderConfig.default(
            contentWidth: renderContentWidth,
            baseURL: self.baseURL,
            postId: post.id,
            galleryImageURLs: galleryImageURLs,
            topicTagNames: Set(self.viewModel.topic?.tags.map(\.name) ?? [])
        )
        let hasUnsupported = self.viewModel.unsupportedPostIds.contains(postId)

        cell.configure(
            with: post,
            annotatedBlocks: annotatedBlocks,
            config: config,
            delegate: self,
            floorNumber: floorNumber,
            postLink: postLink,
            baseURL: self.baseURL,
            hasUnsupportedBlocks: hasUnsupported,
            cookedHTML: post.cooked,
            validReactions: self.viewModel.topic?.validReactions ?? [],
            sharedIssue: self.sharedIssueState(forFloorNumber: floorNumber),
        )
        return cell
    }

    private func sharedIssueState(forFloorNumber floorNumber: Int) -> PostNativeCell.SharedIssueState? {
        guard floorNumber == 1,
              let topic = viewModel.topic,
              topic.sharedIssueVisible
        else { return nil }

        return PostNativeCell.SharedIssueState(
            topicId: topic.id,
            canCreate: topic.canCreateSharedIssue,
            count: topic.sharedIssueCount,
            userCreated: topic.userCreatedSharedIssue
        )
    }

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private let loadingSkeletonView = TopicDetailSkeletonView()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = TopicDetailTypography.topicTitleFont()
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }()

    private let tagsContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let navTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.numberOfLines = 1
        return label
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let footerSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        return spinner
    }()

    private lazy var topLoadingBar: UIView = {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = .secondarySystemBackground
        bar.alpha = 0
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "topic_detail.loading_earlier")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 36),
        ])
        return bar
    }()

    private let bottomBar = TopicDetailBottomBar()

    private lazy var floatingReplyButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "arrowshape.turn.up.left")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        let accentColor = AppSettings.shared.themeStyle.accentColor
        config.baseForegroundColor = accentColor
        config.baseBackgroundColor = accentColor.withAlphaComponent(0.14)
        config.cornerStyle = .large
        button.configuration = config
        button.backgroundColor = .clear
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.layer.shadowColor = accentColor.cgColor
        button.layer.shadowOpacity = 0.20
        button.layer.shadowOffset = CGSize(width: 0, height: 8)
        button.layer.shadowRadius = 16
        button.isHidden = true
        button.accessibilityLabel = String(localized: "topic_detail.action.reply")
        button.addAction(UIAction { [weak self] _ in
            self?.replyButtonTapped()
        }, for: .touchUpInside)
        return button
    }()

    private lazy var jumpOverlay: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        v.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }()

    init(api: DiscourseAPI, topicId: Int, initialFloor: Int? = nil) {
        self.api = api
        self.viewModel = TopicDetailViewModel(api: api)
        self.topicId = topicId
        self.initialFloor = initialFloor
        self.baseURL = api.baseURL
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    deinit {
        if let cloudflareCompletionObservationToken {
            NotificationCenter.default.removeObserver(cloudflareCompletionObservationToken)
        }
        NotificationCenter.default.removeObserver(
            self,
            name: PluginStateStore.stateDidChangeNotification,
            object: nil
        )
        readingTracker.stop()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        title = String(localized: "topic_detail.default_title")
        startObservingCloudflareVerification()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pluginStateDidChange),
            name: PluginStateStore.stateDidChangeNotification,
            object: nil
        )
        configureTopicActions()
        applyTypography()
//        tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))

        view.addSubview(tableView)
        view.addSubview(loadingSkeletonView)
        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)
        view.addSubview(bottomBar)
        view.addSubview(floatingReplyButton)
        view.addSubview(topLoadingBar)

        bottomBar.delegate = self
        tableView.tableFooterView = footerSpinner

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingSkeletonView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            loadingSkeletonView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingSkeletonView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingSkeletonView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            bottomBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            floatingReplyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            floatingReplyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            floatingReplyButton.widthAnchor.constraint(equalToConstant: 56),
            floatingReplyButton.heightAnchor.constraint(equalToConstant: 56),

            topLoadingBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topLoadingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topLoadingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        Task {
            await viewModel.loadTopic(id: topicId, containerWidth: view.bounds.width)
            if let initialFloor {
                jumpToFloor(initialFloor)
            }
        }
        Task {
            await api.loadOrFetchEmojiMap()
            hasTitleHeader = false
            updateUI()
            tableView.reloadData()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        installBackSwipeFallbackGesture()
        isHandlingBackSwipeFallback = false
        syncOwningTabBarVisibility()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The system edge-pop is unreliable with the hidden-home-navigation setup,
        // so this page owns a narrow fallback edge gesture instead.
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        installBackSwipeFallbackGesture()
        readingTracker.start(topicId: topicId)
        updateVisibleReadingPosts()
        updateBottomBarProgress()
        syncOwningTabBarVisibility()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        uninstallBackSwipeFallbackGesture()
        readingTracker.stop()
    }

    private func syncOwningTabBarVisibility() {
        (tabBarController as? ForumTabBarController)?.syncTabBarVisibilityForCurrentContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Reserve bottom space for the centered floor control and the floating reply affordance.
        let bottomInset: CGFloat = 56 + 12 + 32
        if tableView.contentInset.bottom != bottomInset {
            tableView.contentInset.bottom = bottomInset
            tableView.verticalScrollIndicatorInsets.bottom = bottomInset
        }

        // Execute deferred jump scroll after layout is complete
        if !isApplyingPostSnapshot, let floor = pendingScrollToFloor {
            pendingScrollToFloor = nil
            let targetRow = viewModel.visibleRowForFloor(floor) ?? 0
            let rowCount = tableView.numberOfRows(inSection: 0)
            guard rowCount > 0 else { return }
            let safeRow = min(targetRow, rowCount - 1)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tableView.scrollToRow(at: IndexPath(row: safeRow, section: 0), at: .top, animated: false)
            CATransaction.commit()
            lastScrollOffset = tableView.contentOffset.y
        }
    }

    override func updateUI() {
        let settings = AppSettings.shared
        tableView.showsVerticalScrollIndicator = !settings.hideScrollIndicators
        applyThemeStyle()
        applyTypography()
        let didChangeThemeStyle = lastThemeStyle != settings.themeStyle
        let didChangeCategoryPresentation = lastCategoryPresentation != viewModel.categoryPresentation
        let shouldReloadVisibleContent = lastReadingComfortMode != settings.readingComfortMode
            || lastContentFontSize != settings.contentFontSize
            || lastContentFontScalePercent != settings.contentFontScalePercent
            || lastContentFontFamily != settings.contentFontFamily
            || lastContentFontScope != settings.contentFontScope
            || lastInterfaceFontScalePercent != settings.interfaceFontScalePercent
            || didChangeThemeStyle
        lastReadingComfortMode = settings.readingComfortMode
        lastContentFontSize = settings.contentFontSize
        lastContentFontScalePercent = settings.contentFontScalePercent
        lastContentFontFamily = settings.contentFontFamily
        lastContentFontScope = settings.contentFontScope
        lastInterfaceFontScalePercent = settings.interfaceFontScalePercent
        lastThemeStyle = settings.themeStyle
        lastCategoryPresentation = viewModel.categoryPresentation
        configureTopicActions()
        if didChangeThemeStyle || didChangeCategoryPresentation {
            hasTitleHeader = false
        }

        // Title header (set once, but rebuild when canLoadEarlier changes after a jump)
        if let topic = viewModel.topic, !hasTitleHeader {
            let displayTitle = topic.fancyTitle ?? topic.title
            configureTitleLabel(displayTitle)
            updateTitleHeader()
            hasTitleHeader = true
        }

        // Loading
        let showsInitialLoading = viewModel.isLoading && !viewModel.isReady && viewModel.errorMessage == nil
        if showsInitialLoading {
            activityIndicator.stopAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        loadingSkeletonView.setSkeletonActive(showsInitialLoading, animated: view.window != nil)

        // Error
        if let error = viewModel.errorMessage {
            errorLabel.text = error
            errorLabel.isHidden = false
        } else {
            errorLabel.isHidden = true
        }

        // Footer spinner
        if viewModel.isLoadingMore {
            tableView.tableFooterView = footerSpinner
            footerSpinner.startAnimating()
        } else {
            footerSpinner.stopAnimating()
            tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        }

        // Top loading bar for loading earlier posts
        if viewModel.isLoadingEarlier {
            DexoMotion.animate(duration: DexoMotion.quick) {
                self.topLoadingBar.alpha = 1
            }
        } else {
            DexoMotion.animate(duration: DexoMotion.quick, timingParameters: DexoMotion.easeInCubic) {
                self.topLoadingBar.alpha = 0
            }
        }

        bottomBar.isHidden = !viewModel.isReady
        floatingReplyButton.isHidden = !viewModel.isReady
        updateBottomBarProgress()

        // Show posts — all visible posts that have parsed blocks
        if viewModel.isReady {
            let shouldAnimateInitialContent = !hasPresentedInitialContent && tableView.isHidden
            if shouldAnimateInitialContent {
                prepareInitialContentTransition()
            }
            tableView.isHidden = false
            var seen = Set<Int>()
            let readyIds = viewModel.visiblePosts.compactMap { post -> Int? in
                guard viewModel.parsedBlocks[post.id] != nil,
                      seen.insert(post.id).inserted else { return nil }
                return post.id
            }
            prefetchContentImages(forPostIds: readyIds)
            let completedEarlierAnchor = viewModel.isLoadingEarlier ? nil : earlierLoadAnchor
            applyPostSnapshot(itemIDs: readyIds, earlierAnchor: completedEarlierAnchor)
            if shouldReloadVisibleContent {
                tableView.reloadData()
            }
            updateVisibleReadingPosts()
            updateBottomBarProgress()

            // After a jump, defer scroll to next layout pass so cells are sized
            if let targetFloor = viewModel.jumpTargetFloor {
                viewModel.jumpTargetFloor = nil
                pendingScrollToFloor = targetFloor
                tableView.setNeedsLayout()
            }
            if shouldAnimateInitialContent {
                animateInitialContentTransition()
            }
        } else {
            tableView.isHidden = true
        }
    }

    private func applyThemeStyle() {
        let accentColor = AppSettings.shared.themeStyle.accentColor
        let themeStyle = AppSettings.shared.themeStyle
        view.backgroundColor = themeStyle.topicListBackgroundColor
        tableView.backgroundColor = themeStyle.topicListBackgroundColor
        topLoadingBar.backgroundColor = themeStyle.topicCardBackgroundColor
        loadingSkeletonView.applyThemeStyle()
        var replyConfig = floatingReplyButton.configuration ?? UIButton.Configuration.filled()
        replyConfig.baseForegroundColor = accentColor
        replyConfig.baseBackgroundColor = accentColor.withAlphaComponent(0.14)
        floatingReplyButton.configuration = replyConfig
        floatingReplyButton.layer.shadowColor = accentColor.cgColor
    }

    private func applyTypography() {
        titleLabel.font = TopicDetailTypography.topicTitleFont()
        navTitleLabel.font = TopicDetailTypography.interfaceFont(ofSize: 17, weight: .semibold)
        errorLabel.font = TopicDetailTypography.interfaceFont(ofSize: 14, weight: .regular)
    }

    private func prepareInitialContentTransition() {
        tableView.alpha = 0
        tableView.transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.996, y: 0.996)
        bottomBar.alpha = 0
        bottomBar.transform = CGAffineTransform(translationX: 0, y: 8)
    }

    private func animateInitialContentTransition() {
        hasPresentedInitialContent = true
        let animations = {
            self.tableView.alpha = 1
            self.tableView.transform = .identity
            self.bottomBar.alpha = 1
            self.bottomBar.transform = .identity
        }
        DexoMotion.animate(
            duration: DexoMotion.standard,
            timingParameters: DexoMotion.easeOutCubic,
            animations: animations
        )
    }

    private func prefetchContentImages(forPostIds postIds: [Int]) {
        let newPostIds = postIds.filter { postId in
            prefetchedImagePostIds.insert(postId).inserted
        }
        let contentURLs = newPostIds.flatMap { postId in
            viewModel.parsedBlocks[postId]?.imageSourceURLs.compactMap(URL.init(string:)) ?? []
        }
        ForumImageLoader.prefetch(urls: contentURLs)
        AvatarImageLoader.prefetch(
            urls: avatarURLs(forPostIds: newPostIds),
            cloudflareBaseURL: baseURL
        )
    }

    private func avatarURLs(forPostIds postIds: [Int]) -> [URL] {
        let postIds = Set(postIds)
        return viewModel.posts.compactMap { post in
            guard postIds.contains(post.id) else { return nil }
            return AvatarImageLoader.url(
                from: post.avatarTemplate,
                baseURL: baseURL,
                size: AvatarImageLoader.primaryAvatarPixelSize
            )
        }
    }

    private func startObservingCloudflareVerification() {
        cloudflareCompletionObservationToken = NotificationCenter.default.addObserver(
            forName: DiscourseAPI.cloudflareVerificationCompletedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareVerificationCompleted(notification)
        }
    }

    private func handleCloudflareVerificationCompleted(_ notification: Notification) {
        guard let verifiedBaseURL = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String,
              ForumInstance.normalizedBaseURL(verifiedBaseURL) == ForumInstance.normalizedBaseURL(baseURL)
        else { return }

        let readyPostIds = viewModel.posts.compactMap { post in
            viewModel.parsedBlocks[post.id] == nil ? nil : post.id
        }
        AvatarImageLoader.credentialsDidChange(
            for: baseURL,
            retrying: avatarURLs(forPostIds: readyPostIds)
        )
        prefetchedImagePostIds.removeAll()
        prefetchContentImages(forPostIds: readyPostIds)
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            await self.viewModel.loadTopic(
                id: self.topicId,
                containerWidth: self.view.bounds.width
            )
        }
    }

    private func updateTitleHeader() {
        guard let topic = viewModel.topic else { return }
        let container = UIView()
        let metadataRow = makeTopicMetadataRow(topic)
        container.addSubview(titleLabel)
        container.addSubview(tagsContainer)
        container.addSubview(metadataRow)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let tags = topic.tags
        configureTaxonomy(tags: tags, category: viewModel.categoryPresentation)
        let hasVisibleTaxonomy = viewModel.categoryPresentation != nil || !tags.isEmpty

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            tagsContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: hasVisibleTaxonomy ? 8 : 0),
            tagsContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            tagsContainer.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            metadataRow.topAnchor.constraint(equalTo: tagsContainer.bottomAnchor, constant: 10),
            metadataRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            metadataRow.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            metadataRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
        ])
        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let size = container.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        container.frame.size = size
        tableView.tableHeaderView = container
    }

    private func makeTopicMetadataRow(_ topic: DiscourseTopicDetail) -> UIStackView {
        let replyCount = max(topic.replyCount, max(topic.postsCount - 1, 0))
        let row = UIStackView(arrangedSubviews: [
            makeTopicMetadataItem(
                symbolName: "bubble.left",
                value: formatCompactCount(replyCount),
                label: String(localized: "topic_detail.metadata.replies")
            ),
            makeTopicMetadataItem(
                symbolName: "eye",
                value: formatCompactCount(topic.views),
                label: String(localized: "topic_detail.metadata.views")
            ),
            makeTopicMetadataItem(
                symbolName: "clock",
                value: formatRelativeDate(topic.createdAt),
                label: nil
            ),
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.distribution = .fill
        return row
    }

    private func makeTopicMetadataItem(symbolName: String, value: String, label: String?) -> UIView {
        let iconView = UIImageView(image: UIImage(systemName: symbolName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)

        let valueLabel = UILabel()
        valueLabel.font = TopicDetailTypography.interfaceFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = .secondaryLabel
        valueLabel.text = value

        let stack = UIStackView(arrangedSubviews: [iconView, valueLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let label {
            let labelView = UILabel()
            labelView.font = TopicDetailTypography.interfaceFont(ofSize: 13, weight: .regular)
            labelView.textColor = .tertiaryLabel
            labelView.text = label
            stack.addArrangedSubview(labelView)
        }

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
        ])
        return stack
    }

    private func formatCompactCount(_ value: Int) -> String {
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func formatRelativeDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString)
        guard let date else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    private func configureTaxonomy(
        tags: [DiscourseTopicDetail.Tag],
        category: TopicCategoryBadgePresentation?
    ) {
        tagsContainer.subviews.forEach { $0.removeFromSuperview() }
        tagsContainer.constraints.forEach { tagsContainer.removeConstraint($0) }
        guard category != nil || !tags.isEmpty else {
            tagsContainer.heightAnchor.constraint(equalToConstant: 0).isActive = true
            return
        }

        let hSpacing: CGFloat = 6
        let vSpacing: CGFloat = 6
        let maxWidth = tableView.bounds.width - 32 // 16pt padding on each side

        var badges: [TopicTaxonomyBadgeView] = []
        if let category {
            let badge = TopicTaxonomyBadgeView(
                category: category,
                baseURL: baseURL,
                variant: .regular,
                isInteractive: true
            )
            badge.addAction(UIAction { [weak self] _ in
                guard let self, let resolvedCategory = self.viewModel.category else { return }
                let viewController = CategoryTopicsViewController(api: self.api, category: resolvedCategory)
                self.navigationController?.pushViewController(viewController, animated: true)
            }, for: .touchUpInside)
            badges.append(badge)
        }

        for tag in tags {
            let color = TopicTagVisualStyle.color(for: tag.name)
            let badge = TopicTaxonomyBadgeView(
                tag: tag.name,
                color: color,
                variant: .regular,
                isInteractive: true
            )
            let tagSlug = tag.slug
            badge.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                let vc = TagTopicsViewController(api: self.api, tagName: tagSlug)
                self.navigationController?.pushViewController(vc, animated: true)
            }, for: .touchUpInside)
            badges.append(badge)
        }

        // Flow layout: calculate positions with line wrapping
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for badge in badges {
            badge.translatesAutoresizingMaskIntoConstraints = true
            let size = badge.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + vSpacing
                lineHeight = 0
            }
            badge.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            tagsContainer.addSubview(badge)
            x += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
        }
        let totalHeight = y + lineHeight
        tagsContainer.heightAnchor.constraint(equalToConstant: totalHeight).isActive = true
    }

    // MARK: - Emoji Title

    private static let emojiPattern = try! NSRegularExpression(pattern: ":[\\w\\-+]+:")

    private func configureTitleLabel(_ title: String) {
        guard !EmojiStore.lookupMap.isEmpty else {
            titleLabel.text = title
            navTitleLabel.text = title
            return
        }
        let matches = Self.emojiPattern.matches(in: title, range: NSRange(title.startIndex..., in: title))
        let hasEmoji = matches.contains(where: {
            let nsTitle = title as NSString
            let full = nsTitle.substring(with: $0.range)
            let code = String(full.dropFirst().dropLast())
            return EmojiStore.url(for: code) != nil
        })
        guard hasEmoji else {
            titleLabel.text = title
            navTitleLabel.text = title
            return
        }

        let headerResult = buildEmojiAttributedString(title, font: titleLabel.font ?? TopicDetailTypography.topicTitleFont())
        let navResult = buildEmojiAttributedString(title, font: navTitleLabel.font ?? .systemFont(ofSize: 17, weight: .semibold))

        titleLabel.attributedText = headerResult
        navTitleLabel.attributedText = navResult
        navTitleLabel.sizeToFit()
        loadTitleEmojiImages(in: headerResult, label: titleLabel)
        loadTitleEmojiImages(in: navResult, label: navTitleLabel)
    }

    private func buildEmojiAttributedString(_ title: String, font: UIFont) -> NSMutableAttributedString {
        let matches = Self.emojiPattern.matches(in: title, range: NSRange(title.startIndex..., in: title))
        let result = NSMutableAttributedString()
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var lastEnd = title.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: title) else { continue }
            let code = String(title[fullRange].dropFirst().dropLast())

            if lastEnd < fullRange.lowerBound {
                result.append(NSAttributedString(string: String(title[lastEnd..<fullRange.lowerBound]), attributes: attrs))
            }

            if let urlString = EmojiStore.url(for: code), let url = URL(string: urlString) {
                let attachment = EmojiTextAttachment()
                attachment.emojiURL = url
                attachment.bounds = CGRect(x: 0, y: font.descender, width: font.lineHeight, height: font.lineHeight)
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(NSAttributedString(string: String(title[fullRange]), attributes: attrs))
            }

            lastEnd = fullRange.upperBound
        }

        if lastEnd < title.endIndex {
            result.append(NSAttributedString(string: String(title[lastEnd...]), attributes: attrs))
        }
        return result
    }

    private func loadTitleEmojiImages(in attributedString: NSMutableAttributedString, label: UILabel) {
        attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length)) { value, _, _ in
            guard let attachment = value as? EmojiTextAttachment, let url = attachment.emojiURL else { return }
            ForumImageLoader.loadImage(with: url) { [weak self] image in
                guard let image, let self else { return }
                attachment.image = image
                label.setNeedsDisplay()
                self.view.setNeedsLayout()
            }
        }
    }

    // MARK: - Reading Tracking

    private func updateVisibleReadingPosts() {
        guard isViewLoaded, view.window != nil, !isApplyingPostSnapshot else { return }
        let postNumbers = (tableView.indexPathsForVisibleRows ?? []).compactMap { indexPath -> Int? in
            guard let postId = dataSource.itemIdentifier(for: indexPath) else { return nil }
            return viewModel.posts.first(where: { $0.id == postId })?.postNumber
        }
        readingTracker.setVisiblePostNumbers(Set(postNumbers))
    }

    private func applyPostSnapshot(
        itemIDs: [Int],
        earlierAnchor: (postId: Int, cellTopOffset: CGFloat)?
    ) {
        let decision = TopicDetailSnapshotPolicy.decision(
            isApplying: isApplyingPostSnapshot,
            currentItemIDs: dataSource.snapshot().itemIdentifiers,
            requestedItemIDs: itemIDs
        )

        switch decision {
        case .skip:
            if earlierAnchor != nil {
                earlierLoadAnchor = nil
                isLoadingEarlierLocally = false
            }
        case .queue:
            pendingPostSnapshot = PendingPostSnapshot(
                itemIDs: itemIDs,
                earlierAnchor: earlierAnchor ?? pendingPostSnapshot?.earlierAnchor
            )
        case .apply:
            isApplyingPostSnapshot = true
            if earlierAnchor != nil {
                earlierLoadAnchor = nil
            }
            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            snapshot.appendSections([0])
            snapshot.appendItems(itemIDs, toSection: 0)
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let earlierAnchor {
                        if let newIndexPath = self.dataSource.indexPath(for: earlierAnchor.postId) {
                            UIView.performWithoutAnimation {
                                self.tableView.layoutIfNeeded()
                                let newCellTop = self.tableView.rectForRow(at: newIndexPath).minY
                                self.tableView.setContentOffset(
                                    CGPoint(x: self.tableView.contentOffset.x, y: newCellTop - earlierAnchor.cellTopOffset),
                                    animated: false
                                )
                            }
                            self.lastScrollOffset = self.tableView.contentOffset.y
                        }
                        self.isLoadingEarlierLocally = false
                    }

                    self.isApplyingPostSnapshot = false
                    if let pending = self.pendingPostSnapshot {
                        self.pendingPostSnapshot = nil
                        self.applyPostSnapshot(
                            itemIDs: pending.itemIDs,
                            earlierAnchor: pending.earlierAnchor
                        )
                    } else if self.pendingScrollToFloor != nil {
                        self.view.setNeedsLayout()
                    }
                    self.updateVisibleReadingPosts()
                    self.updateBottomBarProgress()
                }
            }
        }
    }

    // MARK: - Container Access

    private func replyButtonTapped() {
        performAuthenticated { [weak self] in
            self?.presentReplyComposer()
        }
    }

    private func performAuthenticated(_ action: @escaping () -> Void) {
        if let authGate = findAuthGating() {
            authGate.requireAuth(then: action)
        } else {
            action()
        }
    }

    private func findAuthGating() -> AuthGating? {
        nearestAuthGating()
    }

    private func showPostActionError(_ error: Error) {
        let alert = UIAlertController(
            title: String(localized: "post.action.failed"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func reloadPostCell(postId: Int) {
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(postId) != nil else { return }
        snapshot.reloadItems([postId])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func updateBottomBarProgress() {
        let current = currentVisibleFloor()
        let total = viewModel.totalFloors
        if let lastBottomBarProgressState,
           lastBottomBarProgressState.current == current,
           lastBottomBarProgressState.total == total {
            return
        }
        lastBottomBarProgressState = (current: current, total: total)
        bottomBar.configure(
            currentFloor: current,
            totalFloors: total
        )
    }

    private func currentVisibleFloor() -> Int {
        guard viewModel.totalFloors > 0 else { return 0 }
        let visibleIndexPath = tableView.indexPathsForVisibleRows?
            .sorted { $0.row < $1.row }
            .first
        guard let visibleIndexPath,
              let postId = dataSource.itemIdentifier(for: visibleIndexPath),
              let streamIndex = viewModel.allPostIds.firstIndex(of: postId)
        else {
            return max(1, min(viewModel.loadedRangeStart + 1, viewModel.totalFloors))
        }
        return streamIndex + 1
    }

    private func shareTopicLink(sourceView: UIView?) {
        let link = "\(baseURL)/t/\(topicId)"
        let activity = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = sourceView ?? view
        activity.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(activity, animated: true)
    }

    private func makeExportMenu() -> UIMenu {
        let formatMenus = TopicExportFormat.allCases.map { format in
            UIMenu(
                title: format.title,
                image: UIImage(systemName: format == .markdown ? "doc.plaintext" : "chevron.left.forwardslash.chevron.right"),
                children: TopicExportRange.allCases.map { range in
                    UIAction(title: range.title) { [weak self] _ in
                        self?.exportTopic(format: format, range: range)
                    }
                }
            )
        }
        return UIMenu(
            title: String(localized: "topic.export", defaultValue: "导出话题"),
            image: UIImage(systemName: "square.and.arrow.up"),
            children: formatMenus
        )
    }

    private func configureTopicActions() {
        let searchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(searchTopicTapped)
        )
        searchButton.accessibilityLabel = String(localized: "topic.search", defaultValue: "搜索话题")

        let topic = viewModel.topic
        let bookmarkTitle = topic?.bookmarked == true
            ? String(localized: "topic.bookmark.remove", defaultValue: "取消书签")
            : String(localized: "topic.bookmark.add", defaultValue: "添加书签")
        let bookmark = UIAction(title: bookmarkTitle, image: UIImage(systemName: topic?.bookmarked == true ? "bookmark.slash" : "bookmark")) { [weak self] _ in
            self?.bookmarkTopic()
        }
        let share = UIAction(title: String(localized: "topic.share", defaultValue: "分享链接"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            self?.shareTopicLink(sourceView: nil)
        }
        let username = AuthManager.shared.username(for: api.baseURL)
        let isReadLater = TopicReadLaterStore.shared.contains(
            topicId: topicId,
            baseURL: api.baseURL,
            username: username
        )
        let readLater = UIAction(
            title: isReadLater
                ? String(localized: "topic.read_later.remove", defaultValue: "移出稍后阅读")
                : String(localized: "topic.read_later.add", defaultValue: "稍后阅读"),
            image: UIImage(systemName: "square.stack.3d.up"),
            state: isReadLater ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            TopicReadLaterStore.shared.toggle(
                topicId: self.topicId,
                baseURL: self.api.baseURL,
                username: AuthManager.shared.username(for: self.api.baseURL)
            )
            self.configureTopicActions()
        }
        let shareImage = UIAction(title: String(localized: "topic.share_image", defaultValue: "生成分享图片"), image: UIImage(systemName: "photo")) { [weak self] _ in
            self?.shareTopicImage()
        }
        let opFilter = UIAction(
            title: viewModel.isFilteringByOP
                ? String(localized: "topic.filter_all", defaultValue: "显示全部回复")
                : String(localized: "topic.filter_op", defaultValue: "只看楼主"),
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            state: viewModel.isFilteringByOP ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.viewModel.setFilteringByOP(!self.viewModel.isFilteringByOP)
        }
        let notificationMenu = UIMenu(
            title: String(localized: "topic.notifications", defaultValue: "通知级别"),
            image: UIImage(systemName: "bell"),
            children: DiscourseTopicDetail.NotificationLevel.allCases.reversed().map { level in
                UIAction(
                    title: self.title(for: level),
                    state: topic?.notificationLevel == level ? .on : .off
                ) { [weak self] _ in
                    self?.setNotificationLevel(level)
                }
            }
        )
        let openBrowser = UIAction(title: String(localized: "topic.open_browser", defaultValue: "在浏览器打开"), image: UIImage(systemName: "globe")) { [weak self] _ in
            guard let self, let url = URL(string: "\(self.baseURL)/t/\(self.topicId)") else { return }
            let browser = InAppBrowserViewController(
                api: self.api,
                username: AuthManager.shared.username(for: self.api.baseURL),
                initialURL: url
            )
            self.navigationController?.pushViewController(browser, animated: true)
        }
        let readingSettings = UIAction(title: String(localized: "topic.reading_settings", defaultValue: "阅读设置"), image: UIImage(systemName: "book")) { [weak self] _ in
            self?.navigationController?.pushViewController(ReadingSettingsViewController(), animated: true)
        }
        var actions: [UIMenuElement] = [bookmark, readLater, notificationMenu, share, shareImage, opFilter]
        if topic?.canEdit == true {
            actions.append(UIAction(title: String(localized: "topic.edit", defaultValue: "编辑话题"), image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.editTopic()
            })
        }
        if DexoPluginRuntime.shared.registry.isPluginEnabled(BuiltInPluginID.topicExport, for: pluginScope) {
            actions.append(makeExportMenu())
        }
        actions.append(contentsOf: [openBrowser, readingSettings])

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: actions)
        )
        moreButton.accessibilityLabel = String(localized: "topic.more", defaultValue: "更多操作")
        navigationItem.rightBarButtonItems = [moreButton, searchButton]
    }

    @objc private func pluginStateDidChange() {
        configureTopicActions()
    }

    @objc private func searchTopicTapped() {
        let alert = UIAlertController(
            title: String(localized: "topic.search", defaultValue: "搜索话题"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = String(localized: "topic.search.placeholder", defaultValue: "输入关键词")
            field.returnKeyType = .search
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "topic.search", defaultValue: "搜索话题"), style: .default) { [weak self, weak alert] _ in
            guard let self, let query = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return }
            self.performTopicSearch(query)
        })
        present(alert, animated: true)
    }

    private func performTopicSearch(_ query: String) {
        Task {
            do {
                let result = try await api.searchTopic(topicId: topicId, term: query)
                let posts = (result.posts ?? []).filter { $0.topicId == topicId }
                presentSearchResults(posts, query: query)
            } catch {
                showPostActionError(error)
            }
        }
    }

    private func presentSearchResults(_ posts: [DiscourseSearchResult.SearchPost], query: String) {
        guard !posts.isEmpty else {
            let alert = UIAlertController(
                title: String(localized: "topic.search", defaultValue: "搜索话题"),
                message: String(localized: "topic.search.empty", defaultValue: "没有找到匹配内容"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default))
            present(alert, animated: true)
            return
        }
        let sheet = UIAlertController(title: query, message: nil, preferredStyle: .actionSheet)
        for post in posts.prefix(12) {
            let excerpt = post.blurb?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) ?? post.username
            let title = "#\(post.postNumber)  \(String(excerpt.prefix(70)))"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.jumpToFloor(post.postNumber)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        present(sheet, animated: true)
    }

    private func title(for level: DiscourseTopicDetail.NotificationLevel) -> String {
        switch level {
        case .watching: return String(localized: "topic.notifications.watching", defaultValue: "关注")
        case .tracking: return String(localized: "topic.notifications.tracking", defaultValue: "跟踪")
        case .regular: return String(localized: "topic.notifications.regular", defaultValue: "常规")
        case .muted: return String(localized: "topic.notifications.muted", defaultValue: "静音")
        }
    }

    private func setNotificationLevel(_ level: DiscourseTopicDetail.NotificationLevel) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.api.updateTopicNotificationLevel(topicId: self.topicId, level: level)
                    self.viewModel.topic?.notificationLevel = level
                    self.configureTopicActions()
                } catch {
                    self.showPostActionError(error)
                }
            }
        }
    }

    private func editTopic() {
        guard let topic = viewModel.topic, topic.canEdit else { return }
        let alert = UIAlertController(title: String(localized: "topic.edit", defaultValue: "编辑话题"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = topic.title }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default) { [weak self, weak alert] _ in
            guard let self, let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
            Task {
                do {
                    try await self.api.updateTopic(topicId: self.topicId, title: title)
                    self.hasTitleHeader = false
                    await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
                } catch {
                    self.showPostActionError(error)
                }
            }
        })
        present(alert, animated: true)
    }

    private func shareTopicImage() {
        guard let topic = viewModel.topic else { return }
        let displayTitle = topic.fancyTitle ?? topic.title
        let firstPost = viewModel.posts.first(where: { $0.actionCode == nil })
        let excerpt = firstPost?.cooked.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) ?? ""
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1350))
        let image = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1080, height: 1350))
            let titleAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 56, weight: .bold), .foregroundColor: UIColor.label]
            let bodyAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.secondaryLabel]
            (displayTitle as NSString).draw(in: CGRect(x: 72, y: 92, width: 936, height: 260), withAttributes: titleAttributes)
            (String(excerpt.prefix(500)) as NSString).draw(in: CGRect(x: 72, y: 390, width: 936, height: 700), withAttributes: bodyAttributes)
            ("\(baseURL)/t/\(topicId)" as NSString).draw(in: CGRect(x: 72, y: 1190, width: 936, height: 80), withAttributes: bodyAttributes)
        }
        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(activity, animated: true)
    }

    private func exportTopic(format: TopicExportFormat, range: TopicExportRange) {
        guard let topic = viewModel.topic else {
            showPostActionError(TopicExportError.noPosts)
            return
        }
        let title = topic.fancyTitle ?? topic.title
        let posts = viewModel.posts
        let username = findAuthGating()?.currentUsername()
        let service = TopicExportService(baseURL: baseURL, username: username)
        let history = ExportHistoryStore(baseURL: baseURL, username: username)
        let selectedPostCount = range == .firstPost ? min(posts.count, 1) : posts.filter { $0.actionCode == nil }.count

        do {
            let fileURL = try service.export(
                topicId: topicId,
                title: title,
                posts: posts,
                format: format,
                range: range
            )
            let record = TopicExportRecord(
                topicId: topicId,
                title: title,
                format: format,
                filePath: fileURL.path,
                postCount: selectedPostCount,
                errorMessage: nil
            )
            try history.add(record)
            let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
            present(activity, animated: true)
        } catch {
            let failedRecord = TopicExportRecord(
                topicId: topicId,
                title: title,
                format: format,
                filePath: nil,
                postCount: selectedPostCount,
                errorMessage: error.localizedDescription
            )
            try? history.add(failedRecord)
            showPostActionError(error)
        }
    }

    private func bookmarkTopic() {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    if self.viewModel.topic?.bookmarked == true,
                       let bookmarkId = self.viewModel.topic?.bookmarkId {
                        try await self.api.deleteBookmark(id: bookmarkId)
                    } else {
                        _ = try await self.api.createBookmark(topicId: self.topicId)
                    }
                    await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
                } catch {
                    self.showPostActionError(error)
                }
            }
        }
    }

    // MARK: - Link Handling

    private func handleLink(_ url: URL) {
        let linkURL = ForumInternalLinkParser.normalizedURL(from: url, baseURL: baseURL)
        if ForumInternalLinkParser.isInternalURL(linkURL, baseURL: baseURL),
           let destination = ForumInternalLinkParser.destination(for: linkURL) {
            openInternalDestination(destination)
        } else if ForumAttachmentLinkParser.isAttachmentURL(linkURL) {
            downloadAndShareAttachment(linkURL)
        } else {
            presentSafari(linkURL)
        }
    }

    private func openInternalDestination(_ destination: ForumInternalLinkDestination) {
        switch destination {
        case let .topic(topicId, postNumber):
            if topicId == self.topicId, let postNumber {
                jumpToFloor(postNumber)
                return
            }
            let detailVC = TopicDetailViewController(api: api, topicId: topicId, initialFloor: postNumber)
            openInternalViewController(detailVC)
        case let .category(slug, categoryId):
            let category = DiscourseCategory(id: categoryId, name: slug, slug: slug)
            let vc = CategoryTopicsViewController(api: api, category: category)
            openInternalViewController(vc)
        case let .tag(tagName):
            let vc = TagTopicsViewController(api: api, tagName: tagName)
            openInternalViewController(vc)
        }
    }

    private func downloadAndShareAttachment(_ url: URL) {
        let progressAlert = makeAttachmentDownloadAlert()
        present(progressAlert, animated: true)
        let attachmentBaseURL = baseURL

        Task { @MainActor [weak self, weak progressAlert] in
            do {
                let fileURL = try await ForumAttachmentDownloader.download(url: url, baseURL: attachmentBaseURL)
                guard let self else {
                    ForumAttachmentDownloader.cleanupDownloadedFile(fileURL)
                    return
                }
                self.downloadedAttachmentURLs.insert(fileURL)
                progressAlert?.dismiss(animated: true) {
                    self.presentAttachmentShareSheet(fileURL)
                }
            } catch {
                progressAlert?.dismiss(animated: true) { [weak self] in
                    self?.showPostActionError(error)
                }
            }
        }
    }

    private func makeAttachmentDownloadAlert() -> UIAlertController {
        let alert = UIAlertController(
            title: String(localized: "attachment.downloading"),
            message: "\n\n",
            preferredStyle: .alert
        )
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        alert.view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            indicator.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -22),
        ])
        return alert
    }

    private func presentAttachmentShareSheet(_ fileURL: URL) {
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = view.bounds
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.downloadedAttachmentURLs.remove(fileURL)
            ForumAttachmentDownloader.cleanupDownloadedFile(fileURL)
        }
        present(activity, animated: true)
    }

    private func openInternalViewController(_ viewController: UIViewController) {
        if let navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: viewController)
            present(nav, animated: true)
        }
    }

    private func presentSafari(_ url: URL) {
        guard AppSettings.shared.openExternalLinksInAppBrowser else {
            UIApplication.shared.open(url)
            return
        }
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }
}

private final class TopicDetailSkeletonView: DexoSkeletonPlaceholderView {
    private var cardSurfaces: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        skeletonContentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: skeletonContentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: skeletonContentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: skeletonContentView.bottomAnchor),
        ])

        stack.addArrangedSubview(makeTitleCard())
        for _ in 0 ..< 4 {
            stack.addArrangedSubview(makePostCard())
        }
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        applySkeletonTheme(
            backgroundColor: themeStyle.topicListBackgroundColor,
            blockColor: themeStyle.accentColor.withAlphaComponent(0.12)
        )
        cardSurfaces.forEach {
            $0.backgroundColor = themeStyle.topicCardBackgroundColor
            $0.layer.borderColor = UIColor.separator.withAlphaComponent(0.20).cgColor
        }
    }

    private func makeCard(height: CGFloat, cornerRadius: CGFloat = 16) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 0.5
        cardSurfaces.append(card)
        card.heightAnchor.constraint(equalToConstant: height).isActive = true
        return card
    }

    private func makeTitleCard() -> UIView {
        let card = makeCard(height: 118)
        let title = makeSkeletonBlock(cornerRadius: 6)
        let titleShort = makeSkeletonBlock(cornerRadius: 6)
        let chipOne = makeSkeletonBlock(cornerRadius: 11)
        let chipTwo = makeSkeletonBlock(cornerRadius: 11)
        let meta = makeSkeletonBlock(cornerRadius: 5)

        [title, titleShort, chipOne, chipTwo, meta].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -26),
            title.heightAnchor.constraint(equalToConstant: 20),

            titleShort.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 9),
            titleShort.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            titleShort.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -94),
            titleShort.heightAnchor.constraint(equalToConstant: 20),

            chipOne.topAnchor.constraint(equalTo: titleShort.bottomAnchor, constant: 14),
            chipOne.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            chipOne.widthAnchor.constraint(equalToConstant: 72),
            chipOne.heightAnchor.constraint(equalToConstant: 22),

            chipTwo.leadingAnchor.constraint(equalTo: chipOne.trailingAnchor, constant: 8),
            chipTwo.centerYAnchor.constraint(equalTo: chipOne.centerYAnchor),
            chipTwo.widthAnchor.constraint(equalToConstant: 56),
            chipTwo.heightAnchor.constraint(equalTo: chipOne.heightAnchor),

            meta.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            meta.topAnchor.constraint(equalTo: chipOne.bottomAnchor, constant: 12),
            meta.widthAnchor.constraint(equalToConstant: 188),
            meta.heightAnchor.constraint(equalToConstant: 12),
        ])

        return card
    }

    private func makePostCard() -> UIView {
        let card = makeCard(height: 132)
        let avatar = makeSkeletonBlock(cornerRadius: 16)
        let name = makeSkeletonBlock(cornerRadius: 5)
        let time = makeSkeletonBlock(cornerRadius: 4)
        let lineOne = makeSkeletonBlock(cornerRadius: 5)
        let lineTwo = makeSkeletonBlock(cornerRadius: 5)
        let lineThree = makeSkeletonBlock(cornerRadius: 5)
        let actionOne = makeSkeletonBlock(cornerRadius: 10)
        let actionTwo = makeSkeletonBlock(cornerRadius: 10)

        [avatar, name, time, lineOne, lineTwo, lineThree, actionOne, actionTwo].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            avatar.widthAnchor.constraint(equalToConstant: 32),
            avatar.heightAnchor.constraint(equalToConstant: 32),

            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            name.topAnchor.constraint(equalTo: avatar.topAnchor, constant: 2),
            name.widthAnchor.constraint(equalToConstant: 126),
            name.heightAnchor.constraint(equalToConstant: 14),

            time.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            time.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 7),
            time.widthAnchor.constraint(equalToConstant: 82),
            time.heightAnchor.constraint(equalToConstant: 11),

            lineOne.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            lineOne.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            lineOne.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 18),
            lineOne.heightAnchor.constraint(equalToConstant: 13),

            lineTwo.leadingAnchor.constraint(equalTo: lineOne.leadingAnchor),
            lineTwo.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -52),
            lineTwo.topAnchor.constraint(equalTo: lineOne.bottomAnchor, constant: 9),
            lineTwo.heightAnchor.constraint(equalToConstant: 13),

            lineThree.leadingAnchor.constraint(equalTo: lineOne.leadingAnchor),
            lineThree.widthAnchor.constraint(equalToConstant: 190),
            lineThree.topAnchor.constraint(equalTo: lineTwo.bottomAnchor, constant: 9),
            lineThree.heightAnchor.constraint(equalToConstant: 13),

            actionOne.leadingAnchor.constraint(equalTo: lineOne.leadingAnchor),
            actionOne.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            actionOne.widthAnchor.constraint(equalToConstant: 52),
            actionOne.heightAnchor.constraint(equalToConstant: 20),

            actionTwo.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            actionTwo.centerYAnchor.constraint(equalTo: actionOne.centerYAnchor),
            actionTwo.widthAnchor.constraint(equalToConstant: 84),
            actionTwo.heightAnchor.constraint(equalTo: actionOne.heightAnchor),
        ])

        return card
    }
}

// MARK: - TopicDetailBottomBarDelegate

extension TopicDetailViewController: TopicDetailBottomBarDelegate {
    func bottomBarDidTapTimeline() {
        showTimelineSheet()
    }

    func bottomBarDidSelectRadialAction(_ action: TopicDetailRadialAction) {
        switch action {
        case .timeline:
            showTimelineSheet()
        case .scrollToTop:
            scrollToTop()
        case .reply:
            replyButtonTapped()
        case .bookmark:
            bookmarkTopic()
        case .share:
            shareTopicLink(sourceView: bottomBar)
        }
    }

    private func scrollToTop() {
        guard tableView.numberOfRows(inSection: 0) > 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }

    private func showTimelineSheet() {
        let stream = viewModel.allPostIds
        guard !stream.isEmpty else { return }

        let timeline = TopicTimelineSheetViewController(
            currentIndex: currentVisibleFloor(),
            stream: stream,
            title: viewModel.topic?.fancyTitle ?? viewModel.topic?.title
        )
        timeline.onJumpToPostId = { [weak self] postId in
            self?.jumpToPostId(postId)
        }
        timeline.onDismiss = { [weak self] in
            self?.syncOwningTabBarVisibility()
        }
        timeline.modalPresentationStyle = .pageSheet
        timeline.isModalInPresentation = true
        if let sheet = timeline.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(timeline, animated: true)
    }

    private func showFloorJumpPrompt() {
        let total = viewModel.totalFloors
        guard total > 0 else { return }

        let alert = UIAlertController(
            title: String(localized: "topic_detail.bar.jump_to_floor"),
            message: String(localized: "topic_detail.jump.message \(total)"),
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "1-\(total)"
            textField.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "topic_detail.jump.confirm"), style: .default) { [weak self] _ in
            guard let self,
                  let text = alert.textFields?.first?.text,
                  let floor = Int(text),
                  floor >= 1, floor <= total
            else { return }

            self.jumpToFloor(floor)
        })
        present(alert, animated: true)
    }

    private func jumpToPostId(_ postId: Int) {
        guard let targetIndex = viewModel.allPostIds.firstIndex(of: postId) else { return }
        jumpToFloor(targetIndex + 1)
    }

    private func jumpToFloor(_ floor: Int) {
        let total = viewModel.totalFloors
        guard floor >= 1, floor <= total else { return }

        if viewModel.isFloorLoaded(floor),
           let visibleRow = viewModel.visibleRowForFloor(floor)
        {
            tableView.scrollToRow(
                at: IndexPath(row: visibleRow, section: 0),
                at: .top,
                animated: true
            )
            return
        }

        // Scroll is finalized in viewDidLayoutSubviews after the target batch has cells.
        showJumpOverlay()
        hasTitleHeader = false
        suppressLoadEarlier = true
        Task {
            await viewModel.jumpToFloor(floor, containerWidth: view.bounds.width)
            hideJumpOverlay()
        }
    }

    private func showJumpOverlay() {
        if jumpOverlay.superview == nil {
            view.addSubview(jumpOverlay)
            NSLayoutConstraint.activate([
                jumpOverlay.topAnchor.constraint(equalTo: tableView.topAnchor),
                jumpOverlay.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
                jumpOverlay.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
                jumpOverlay.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
            ])
        }
        jumpOverlay.isHidden = false
    }

    private func hideJumpOverlay() {
        jumpOverlay.isHidden = true
    }

    private var canNavigateBack: Bool {
        guard let navigationController else { return false }
        return navigationController.viewControllers.count > 1
            && navigationController.viewControllers.first !== self
    }

    private func installBackSwipeFallbackGesture() {
        guard let hostView = navigationController?.view else { return }
        if backSwipeFallbackHostView !== hostView {
            backSwipeFallbackGesture.view?.removeGestureRecognizer(backSwipeFallbackGesture)
            hostView.addGestureRecognizer(backSwipeFallbackGesture)
            backSwipeFallbackHostView = hostView
        }
        backSwipeFallbackGesture.isEnabled = canNavigateBack
    }

    private func uninstallBackSwipeFallbackGesture() {
        backSwipeFallbackGesture.view?.removeGestureRecognizer(backSwipeFallbackGesture)
        backSwipeFallbackHostView = nil
        backSwipeFallbackGesture.isEnabled = false
    }

    private var backSwipeCoordinateView: UIView {
        backSwipeFallbackGesture.view ?? view
    }

    private func shouldCompleteBackSwipe(translation: CGPoint, velocity: CGPoint) -> Bool {
        guard translation.x > 0 else { return false }
        return translation.x > BackSwipeFallbackMetrics.minimumCompletionTranslation
            || velocity.x > BackSwipeFallbackMetrics.minimumCompletionVelocity
    }

    @objc private func handleBackSwipeFallback(_ gesture: UIPanGestureRecognizer) {
        guard canNavigateBack, presentedViewController == nil else { return }

        switch gesture.state {
        case .began:
            isHandlingBackSwipeFallback = false
        case .ended:
            let coordinateView = backSwipeCoordinateView
            let translation = gesture.translation(in: coordinateView)
            let velocity = gesture.velocity(in: coordinateView)
            guard shouldCompleteBackSwipe(translation: translation, velocity: velocity),
                  !isHandlingBackSwipeFallback
            else { return }
            isHandlingBackSwipeFallback = true
            navigationController?.popViewController(animated: true)
        case .cancelled, .failed:
            isHandlingBackSwipeFallback = false
        default:
            break
        }
    }

}

// MARK: - Back Swipe Fallback

extension TopicDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === backSwipeFallbackGesture else { return true }
        guard canNavigateBack, presentedViewController == nil else { return false }

        let coordinateView = backSwipeCoordinateView
        let location = backSwipeFallbackGesture.location(in: coordinateView)
        guard location.x <= BackSwipeFallbackMetrics.edgeActivationWidth else { return false }

        let velocity = backSwipeFallbackGesture.velocity(in: coordinateView)
        guard velocity.x >= 0 else { return false }
        if abs(velocity.y) > abs(velocity.x), abs(velocity.y) > 40 {
            return false
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === backSwipeFallbackGesture || otherGestureRecognizer === backSwipeFallbackGesture else {
            return false
        }
        return otherGestureRecognizer === tableView.panGestureRecognizer
            || gestureRecognizer === tableView.panGestureRecognizer
            || otherGestureRecognizer.view is UIScrollView
            || gestureRecognizer.view is UIScrollView
    }
}

// MARK: - UITableViewDelegate

extension TopicDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        200
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        readingTracker.scrolled()
        updateVisibleReadingPosts()
        updateBottomBarProgress()

        guard let header = tableView.tableHeaderView else { return }
        let headerBottom = header.frame.maxY
        let offsetY = scrollView.contentOffset.y + scrollView.safeAreaInsets.top
        let shouldShowCollapsedTitle = offsetY >= headerBottom
        if shouldShowCollapsedTitle != isShowingCollapsedNavigationTitle {
            isShowingCollapsedNavigationTitle = shouldShowCollapsedTitle
            navigationItem.titleView = shouldShowCollapsedTitle ? navTitleLabel : nil
        }

        let currentOffset = scrollView.contentOffset.y
        let isScrollingUp = currentOffset < lastScrollOffset
        lastScrollOffset = currentOffset

        // Clear suppress flag once user scrolls down, meaning they've settled after a jump
        if !isScrollingUp {
            suppressLoadEarlier = false
        }

        // Only trigger load-earlier when user is actively scrolling UP
        // and within 200pt of the top — prevents false triggers after jump
        guard isScrollingUp,
              !suppressLoadEarlier,
              viewModel.canLoadEarlier,
              !isLoadingEarlierLocally
        else { return }
        let contentTop = -(scrollView.adjustedContentInset.top)
        if scrollView.contentOffset.y <= contentTop + 200 {
            // Capture anchor synchronously before any async work
            guard let anchorIndexPath = tableView.indexPathsForVisibleRows?.first,
                  let anchorId = dataSource.itemIdentifier(for: anchorIndexPath)
            else { return }
            let cellTopOffset = tableView.rectForRow(at: anchorIndexPath).minY - tableView.contentOffset.y
            earlierLoadAnchor = (postId: anchorId, cellTopOffset: cellTopOffset)
            isLoadingEarlierLocally = true
            Task {
                let didStart = await viewModel.loadEarlierPosts(containerWidth: view.bounds.width)
                if !didStart {
                    earlierLoadAnchor = nil
                    isLoadingEarlierLocally = false
                }
                // updateUI (triggered by DexoObservableObject) will handle position restoration
            }
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        DispatchQueue.main.async { [weak self] in
            self?.updateVisibleReadingPosts()
        }

        let totalRows = tableView.numberOfRows(inSection: 0)
        // Load more (forward)
        if indexPath.row >= totalRows - 3 {
            Task {
                await viewModel.loadMorePosts(containerWidth: view.bounds.width)
            }
        }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        DispatchQueue.main.async { [weak self] in
            self?.updateVisibleReadingPosts()
        }
    }
}

// MARK: - Topic Timeline Sheet

private final class TopicTimelineSheetViewController: UIViewController {
    var onJumpToPostId: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    private let initialIndex: Int
    private let stream: [Int]
    private let titleText: String?
    private var selectedIndex: Int
    private let feedback = UISelectionFeedbackGenerator()
    private var totalCount: Int { stream.count }

    private let grabberView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiaryLabel.withAlphaComponent(0.35)
        view.layer.cornerRadius = 2
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
        return label
    }()

    private let currentFloorCaptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "topic_detail.timeline.current_floor")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var floorTextField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.keyboardType = .numberPad
        field.textAlignment = .left
        field.font = .monospacedDigitSystemFont(ofSize: 52, weight: .black)
        field.textColor = .tintColor
        field.tintColor = .tintColor
        field.borderStyle = .none
        field.delegate = self
        field.addTarget(self, action: #selector(floorTextChanged), for: .editingChanged)
        return field
    }()

    private let totalLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 21, weight: .semibold)
        label.textColor = .tertiaryLabel
        return label
    }()

    private let editIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "pencil"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .label
        label.backgroundColor = UIColor.tintColor.withAlphaComponent(0.12)
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.textAlignment = .center
        return label
    }()

    private lazy var trackView: TopicTimelineTrackView = {
        let view = TopicTimelineTrackView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.totalCount = totalCount
        view.selectedIndex = selectedIndex
        view.addTarget(self, action: #selector(trackValueChanged(_:)), for: .valueChanged)
        return view
    }()

    init(currentIndex: Int, stream: [Int], title: String?) {
        self.stream = stream
        let safeTotal = max(stream.count, 1)
        self.initialIndex = min(max(currentIndex, 1), safeTotal)
        self.selectedIndex = min(max(currentIndex, 1), safeTotal)
        self.titleText = title
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let floorRow = UIStackView(arrangedSubviews: [floorTextField, totalLabel, editIconView])
        floorRow.translatesAutoresizingMaskIntoConstraints = false
        floorRow.axis = .horizontal
        floorRow.alignment = .bottom
        floorRow.spacing = 8

        let infoStack = UIStackView(arrangedSubviews: [currentFloorCaptionLabel, floorRow, statusLabel])
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.axis = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 10

        let contentRow = UIStackView(arrangedSubviews: [infoStack, trackView])
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        contentRow.axis = .horizontal
        contentRow.alignment = .center
        contentRow.spacing = 20

        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle(String(localized: "action.cancel"), for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let jumpButton = UIButton(type: .system)
        jumpButton.translatesAutoresizingMaskIntoConstraints = false
        var jumpConfig = UIButton.Configuration.filled()
        jumpConfig.title = String(localized: "topic_detail.jump.confirm")
        jumpConfig.cornerStyle = .large
        jumpConfig.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        jumpButton.configuration = jumpConfig
        jumpButton.addTarget(self, action: #selector(jumpTapped), for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [cancelButton, jumpButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 16

        titleLabel.text = titleText
        totalLabel.text = "/ \(totalCount)"

        view.addSubview(grabberView)
        view.addSubview(titleLabel)
        view.addSubview(contentRow)
        view.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            grabberView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            grabberView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 36),
            grabberView.heightAnchor.constraint(equalToConstant: 4),

            titleLabel.topAnchor.constraint(equalTo: grabberView.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            contentRow.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: titleText == nil ? 8 : 24),
            contentRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            contentRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            contentRow.bottomAnchor.constraint(lessThanOrEqualTo: buttonRow.topAnchor, constant: -20),

            floorTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            floorTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 62),
            editIconView.widthAnchor.constraint(equalToConstant: 16),
            editIconView.heightAnchor.constraint(equalToConstant: 16),
            statusLabel.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
            trackView.widthAnchor.constraint(equalToConstant: 64),
            trackView.heightAnchor.constraint(equalToConstant: 228),

            buttonRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttonRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttonRow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            buttonRow.heightAnchor.constraint(equalToConstant: 52),
        ])

        if titleText == nil {
            titleLabel.isHidden = true
        }
        feedback.prepare()
        updateFloorDisplay()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDismiss?()
    }

    @objc private func trackValueChanged(_ sender: TopicTimelineTrackView) {
        setSelectedIndex(sender.selectedIndex, haptic: true)
    }

    @objc private func floorTextChanged() {
        guard let text = floorTextField.text,
              let value = Int(text)
        else { return }
        setSelectedIndex(min(max(value, 1), totalCount), haptic: true, updateText: false)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func jumpTapped() {
        view.endEditing(true)
        normalizeInputFloor()
        let selectedPostId = stream[selectedIndex - 1]
        dismiss(animated: true) { [onJumpToPostId] in
            onJumpToPostId?(selectedPostId)
        }
    }

    private func setSelectedIndex(_ index: Int, haptic: Bool, updateText: Bool = true) {
        let next = min(max(index, 1), totalCount)
        guard next != selectedIndex else {
            updateFloorDisplay(updateText: updateText)
            return
        }
        selectedIndex = next
        trackView.selectedIndex = next
        if haptic {
            feedback.selectionChanged()
            feedback.prepare()
        }
        updateFloorDisplay(updateText: updateText)
    }

    private func updateFloorDisplay(updateText: Bool = true) {
        if updateText {
            floorTextField.text = "\(selectedIndex)"
        }
        statusLabel.text = selectedIndex == initialIndex
            ? String(localized: "topic_detail.timeline.current")
            : String(localized: "topic_detail.timeline.ready")
    }

    private func normalizeInputFloor() {
        guard let text = floorTextField.text,
              let value = Int(text)
        else {
            updateFloorDisplay()
            return
        }
        setSelectedIndex(value, haptic: false)
    }
}

extension TopicTimelineSheetViewController: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        normalizeInputFloor()
    }
}

private final class TopicTimelineTrackView: UIControl, UIGestureRecognizerDelegate {
    var totalCount: Int {
        get { totalCountValue }
        set {
            totalCountValue = max(newValue, 1)
            selectedIndexValue = clampedIndex(selectedIndexValue)
            setNeedsDisplay()
        }
    }

    var selectedIndex: Int {
        get { selectedIndexValue }
        set {
            let next = clampedIndex(newValue)
            guard next != selectedIndexValue else { return }
            selectedIndexValue = next
            setNeedsDisplay()
        }
    }

    private var totalCountValue = 1
    private var selectedIndexValue = 1
    private let trackInset: CGFloat = 24
    private let handleSize: CGFloat = 36

    override var intrinsicContentSize: CGSize {
        CGSize(width: 64, height: 228)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        accessibilityTraits = [.adjustable]

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let trackWidth: CGFloat = 5
        let top = trackInset
        let bottom = bounds.height - trackInset
        let height = max(bottom - top, 1)
        let x = bounds.midX - trackWidth / 2
        let trackRect = CGRect(x: x, y: top, width: trackWidth, height: height)
        let handleY = yPosition(for: selectedIndex)
        let activeRect = CGRect(x: x, y: top, width: trackWidth, height: max(handleY - top, 0))

        UIColor.tertiarySystemFill.setFill()
        UIBezierPath(roundedRect: trackRect, cornerRadius: trackWidth / 2).fill()

        tintColor.withAlphaComponent(0.45).setFill()
        UIBezierPath(roundedRect: activeRect, cornerRadius: trackWidth / 2).fill()

        drawEndpointMark(center: CGPoint(x: bounds.midX, y: top), filled: true)
        drawEndpointMark(center: CGPoint(x: bounds.midX, y: bottom), filled: false)

        let handleRect = CGRect(
            x: bounds.midX - handleSize / 2,
            y: handleY - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        UIColor.black.withAlphaComponent(0.10).setFill()
        UIBezierPath(ovalIn: handleRect.offsetBy(dx: 0, dy: 3)).fill()
        tintColor.setFill()
        UIBezierPath(ovalIn: handleRect).fill()

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        let image = UIImage(systemName: "arrow.up.arrow.down", withConfiguration: symbolConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let imageSize = CGSize(width: 18, height: 18)
        image?.draw(in: CGRect(
            x: handleRect.midX - imageSize.width / 2,
            y: handleRect.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        ))
    }

    override func accessibilityIncrement() {
        selectedIndex = clampedIndex(selectedIndex + 1)
        sendActions(for: .valueChanged)
    }

    override func accessibilityDecrement() {
        selectedIndex = clampedIndex(selectedIndex - 1)
        sendActions(for: .valueChanged)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateSelection(for: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateSelection(for: touch)
        return true
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            updateSelection(at: gesture.location(in: self).y)
        default:
            break
        }
    }

    private func updateSelection(for touch: UITouch) {
        updateSelection(at: touch.location(in: self).y)
    }

    private func updateSelection(at y: CGFloat) {
        let index = indexForY(y)
        guard index != selectedIndex else { return }
        selectedIndex = index
        sendActions(for: .valueChanged)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.y) >= abs(velocity.x)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard otherGestureRecognizer is UIPanGestureRecognizer else { return false }
        return otherGestureRecognizer.view !== self
    }

    private func clampedIndex(_ index: Int) -> Int {
        min(max(index, 1), max(totalCount, 1))
    }

    private func yPosition(for index: Int) -> CGFloat {
        let top = trackInset
        let bottom = bounds.height - trackInset
        guard totalCount > 1 else { return top }
        let percent = CGFloat(index - 1) / CGFloat(totalCount - 1)
        return top + (bottom - top) * percent
    }

    private func indexForY(_ y: CGFloat) -> Int {
        let top = trackInset
        let bottom = bounds.height - trackInset
        guard totalCount > 1 else { return 1 }
        let percent = min(max((y - top) / max(bottom - top, 1), 0), 1)
        return Int(round(percent * CGFloat(totalCount - 1))) + 1
    }

    private func drawEndpointMark(center: CGPoint, filled: Bool) {
        let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        if filled {
            tintColor.setFill()
            UIBezierPath(ovalIn: rect).fill()
        } else {
            UIColor.systemBackground.setFill()
            UIBezierPath(ovalIn: rect).fill()
        }
        tintColor.setStroke()
        let path = UIBezierPath(ovalIn: rect)
        path.lineWidth = 2
        path.stroke()
    }
}

// MARK: - TopicReadingTracker

@MainActor
private final class TopicReadingTracker {
    private let api: DiscourseAPI
    private var topicId: Int?
    private var visiblePostNumbers: Set<Int> = []
    private var pendingTimings: [Int: Int] = [:]
    private var pendingTopicTimeMilliseconds = 0
    private var timer: Timer?
    private var lastTickDate: Date?
    private var lastFlushDate = Date()
    private var isFlushInFlight = false

    init(api: DiscourseAPI) {
        self.api = api
    }

    func start(topicId: Int) {
        if self.topicId != topicId {
            pendingTimings.removeAll()
            pendingTopicTimeMilliseconds = 0
        }
        self.topicId = topicId
        lastTickDate = Date()
        lastFlushDate = Date()
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTickDate = nil
        visiblePostNumbers.removeAll()
        flush(force: true)
    }

    func setVisiblePostNumbers(_ postNumbers: Set<Int>) {
        visiblePostNumbers = postNumbers.filter { $0 > 0 }
    }

    func scrolled() {
        tick()
    }

    private func tick() {
        let now = Date()
        let elapsedMilliseconds: Int
        if let lastTickDate {
            elapsedMilliseconds = min(max(Int(now.timeIntervalSince(lastTickDate) * 1000), 0), 2_000)
        } else {
            elapsedMilliseconds = 0
        }
        lastTickDate = now

        guard elapsedMilliseconds > 0, !visiblePostNumbers.isEmpty else { return }
        pendingTopicTimeMilliseconds += elapsedMilliseconds
        for postNumber in visiblePostNumbers {
            pendingTimings[postNumber, default: 0] += elapsedMilliseconds
        }

        if now.timeIntervalSince(lastFlushDate) >= 60 {
            flush(force: false)
        }
    }

    private func flush(force: Bool) {
        guard !isFlushInFlight,
              let topicId,
              pendingTopicTimeMilliseconds > 0,
              !pendingTimings.isEmpty
        else { return }

        let topicTime = pendingTopicTimeMilliseconds
        let timings = pendingTimings
        pendingTopicTimeMilliseconds = 0
        pendingTimings.removeAll()
        lastFlushDate = Date()
        isFlushInFlight = true

        Task { [weak self, api, topicId, topicTime, timings] in
            let statusCode = await api.sendTopicTimings(
                topicId: topicId,
                topicTime: topicTime,
                timings: timings
            )
            await MainActor.run {
                guard let self else { return }
                self.isFlushInFlight = false
                if let statusCode,
                   (200 ..< 300).contains(statusCode),
                   let highestSeen = timings.keys.max() {
                    NotificationCenter.default.post(
                        name: .topicReadProgressDidChange,
                        object: nil,
                        userInfo: [
                            TopicReadProgressUserInfoKey.baseURL: api.baseURL,
                            TopicReadProgressUserInfoKey.topicId: topicId,
                            TopicReadProgressUserInfoKey.highestSeen: highestSeen,
                        ]
                    )
                }
                guard !force,
                      let statusCode,
                      !(200 ..< 300).contains(statusCode)
                else { return }
                self.pendingTopicTimeMilliseconds += topicTime
                for (postNumber, milliseconds) in timings {
                    self.pendingTimings[postNumber, default: 0] += milliseconds
                }
            }
        }
    }
}

// MARK: - PostCellDelegate

extension TopicDetailViewController: PostCellDelegate {
    func postCell(didTapImageURL url: URL, imageURLs: [URL]) {
        presentTopicImageGallery(currentURL: url, imageURLs: imageURLs)
    }

    func postCell(didTapLinkURL url: URL) {
        handleLink(url)
    }

    func postCell(didTapShowRepliesForPostId postId: Int) {
        let repliesVC = RepliesViewController(api: api, postId: postId, topicId: topicId)
        if let sheet = repliesVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(repliesVC, animated: true)
    }

    func postCell(didTapToggleDetails detailsIndex: Int, postId: Int) {
        // Details toggle not supported in native rendering — no-op
    }

    func postCell(didToggleBookmarkForPost post: DiscourseTopicDetail.Post, isBookmarked: Bool) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    if isBookmarked {
                        let response = try await self.api.createBookmark(postId: post.id)
                        self.viewModel.updatePostBookmark(postId: post.id, bookmarked: true, bookmarkId: response.id)
                    } else if let bookmarkId = post.bookmarkId {
                        try await self.api.deleteBookmark(id: bookmarkId)
                        self.viewModel.updatePostBookmark(postId: post.id, bookmarked: false, bookmarkId: nil)
                    } else {
                        await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
                    }
                    self.reloadPostCell(postId: post.id)
                } catch {
                    self.reloadPostCell(postId: post.id)
                    self.showPostActionError(error)
                }
            }
        }
    }

    func postCell(didTapReaction reactionId: String, forPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    if let response = try await self.api.toggleReaction(postId: post.id, reactionId: reactionId) {
                        self.viewModel.updatePostReaction(
                            postId: post.id,
                            reactions: response.reactions,
                            reactionUsersCount: response.reactionUsersCount,
                            currentUserReaction: response.currentUserReaction
                        )
                        self.reloadPostCell(postId: post.id)
                    } else {
                        await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
                    }
                } catch {
                    self.reloadPostCell(postId: post.id)
                    self.showPostActionError(error)
                }
            }
        }
    }

    func postCell(didTapToggleSharedIssueForTopicId topicId: Int) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            guard !self.pendingSharedIssueTopicIds.contains(topicId) else { return }
            self.pendingSharedIssueTopicIds.insert(topicId)

            Task { @MainActor in
                defer { self.pendingSharedIssueTopicIds.remove(topicId) }
                do {
                    let response = try await self.api.toggleSharedIssue(topicId: topicId)
                    self.viewModel.updateSharedIssue(
                        count: response.count,
                        userCreated: response.userCreatedSharedIssue
                    )
                    if let firstPostId = self.viewModel.topic?.postStream.posts.first?.id {
                        self.reloadPostCell(postId: firstPostId)
                    }
                } catch {
                    self.showPostActionError(error)
                }
            }
        }
    }

    func postCell(didSubmitPollVoteForPostId postId: Int, pollName: String, optionIds: [String]) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.viewModel.submitPollVote(postId: postId, pollName: pollName, optionIds: optionIds)
                    self.reloadPostCell(postId: postId)
                } catch {
                    self.reloadPostCell(postId: postId)
                    self.showPostActionError(error)
                }
            }
        }
    }

    func postCell(didTapBoostForPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.presentBoostInput(for: post)
        }
    }

    func postCell(didTapAvatarForUsername username: String) {
        let previewVC = UserProfilePreviewViewController(api: api, username: username)
        previewVC.onViewProfile = { [weak self] selectedUsername in
            guard let self else { return }
            let vc = UserProfileViewController(api: self.api, username: selectedUsername)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        present(previewVC, animated: true)
    }

    func postCell(didTapQuotedPostNumber postNumber: Int) {
        jumpToFloor(postNumber)
    }

    func postCell(didTapReplyToPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.presentReplyComposer(for: post)
        }
    }

    private func presentBoostInput(for post: DiscourseTopicDetail.Post) {
        let input = BoostInputViewController(api: api)
        input.onSubmit = { [weak self] result in
            guard let self else { return }
            switch result {
            case let .boost(raw):
                Task {
                    do {
                        let boost = try await self.api.createBoost(postId: post.id, raw: raw)
                        self.viewModel.appendPostBoost(postId: post.id, boost: boost)
                        self.reloadPostCell(postId: post.id)
                    } catch {
                        self.reloadPostCell(postId: post.id)
                        self.showPostActionError(error)
                    }
                }
            case let .reply(raw):
                self.presentReplyComposer(for: post, initialText: raw)
            }
        }
        input.modalPresentationStyle = .pageSheet
        if let sheet = input.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(input, animated: true)
    }

    private func presentReplyComposer(for post: DiscourseTopicDetail.Post? = nil, initialText: String? = nil) {
        let composer = ReplyComposerViewController(
            api: api,
            topicId: topicId,
            replyToPost: post,
            baseURL: baseURL,
            initialText: initialText
        )
        composer.onPostCreated = { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
            }
        }
        composer.modalPresentationStyle = .pageSheet
        if let sheet = composer.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(composer, animated: true)
    }
}
