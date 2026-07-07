import Lightbox
import SafariServices
import SDWebImage
import UIKit

enum ForumInternalLinkDestination {
    case topic(id: Int)
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
        if let topicId = parseTopicId(from: url) {
            return .topic(id: topicId)
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

    private static func parseTopicId(from url: URL) -> Int? {
        let components = url.pathComponents
        guard let tIndex = components.firstIndex(of: "t") else { return nil }
        for component in components.dropFirst(tIndex + 1) {
            let cleaned = component.replacingOccurrences(of: ".json", with: "")
            if let id = Int(cleaned) {
                return id
            }
        }
        return nil
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
    private let baseURL: String
    private var hasTitleHeader = false
    private var isLoadingEarlierLocally = false
    private var pendingScrollToFloor: Int?
    private var lastScrollOffset: CGFloat = 0
    /// Suppress load-earlier after a jump until user scrolls down first
    private var suppressLoadEarlier = false
    /// Anchor info for restoring scroll position after loading earlier posts
    private var earlierLoadAnchor: (postId: Int, cellTopOffset: CGFloat)?
    private var lastReadingComfortMode = AppSettings.shared.readingComfortMode
    private var lastContentFontSize = AppSettings.shared.contentFontSize
    private var lastThemeStyle = AppSettings.shared.themeStyle
    private var hasPresentedInitialContent = false
    private var isHandlingBackSwipeFallback = false
    private weak var backSwipeFallbackHostView: UIView?
    private lazy var readingTracker = TopicReadingTracker(api: api)
    private var isShowingCollapsedNavigationTitle = false
    private var lastBottomBarProgressState: (current: Int, total: Int)?
    private var downloadedAttachmentURLs: Set<URL> = []

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
        let renderContentWidth = floorNumber == 1
            ? PostNativeCell.firstPostRenderContentWidth(for: tableView.bounds.width)
            : tableView.bounds.width - 24
        let config = NativeRenderConfig.default(contentWidth: renderContentWidth, baseURL: self.baseURL)
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
        )
        return cell
    }

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 22, weight: .semibold)
        )
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

    init(api: DiscourseAPI, topicId: Int) {
        self.api = api
        self.viewModel = TopicDetailViewModel(api: api)
        self.topicId = topicId
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
        readingTracker.stop()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        title = String(localized: "topic_detail.default_title")
//        tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))

        view.addSubview(tableView)
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
        }
        Task {
            await api.loadOrFetchEmojiMap()
            hasTitleHeader = false
            updateUI()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        installBackSwipeFallbackGesture()
        isHandlingBackSwipeFallback = false
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
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        uninstallBackSwipeFallbackGesture()
        readingTracker.stop()
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
        if let floor = pendingScrollToFloor {
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
        let didChangeThemeStyle = lastThemeStyle != settings.themeStyle
        let shouldReloadVisibleContent = lastReadingComfortMode != settings.readingComfortMode
            || lastContentFontSize != settings.contentFontSize
            || didChangeThemeStyle
        lastReadingComfortMode = settings.readingComfortMode
        lastContentFontSize = settings.contentFontSize
        lastThemeStyle = settings.themeStyle
        if didChangeThemeStyle {
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
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

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
            UIView.animate(withDuration: 0.25) {
                self.topLoadingBar.alpha = 1
            }
        } else {
            UIView.animate(withDuration: 0.25) {
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
            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            snapshot.appendSections([0])
            var seen = Set<Int>()
            let readyIds = viewModel.visiblePosts.compactMap { post -> Int? in
                guard viewModel.parsedBlocks[post.id] != nil,
                      seen.insert(post.id).inserted else { return nil }
                return post.id
            }
            snapshot.appendItems(readyIds, toSection: 0)

            // Restore scroll position when earlier posts were prepended
            if let anchor = earlierLoadAnchor {
                earlierLoadAnchor = nil
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                dataSource.apply(snapshot, animatingDifferences: false)
                tableView.layoutIfNeeded()
                if let newIndexPath = dataSource.indexPath(for: anchor.postId) {
                    let newCellTop = tableView.rectForRow(at: newIndexPath).minY
                    tableView.contentOffset.y = newCellTop - anchor.cellTopOffset
                }
                CATransaction.commit()
                isLoadingEarlierLocally = false
            } else {
                dataSource.apply(snapshot, animatingDifferences: false)
            }
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
        var replyConfig = floatingReplyButton.configuration ?? UIButton.Configuration.filled()
        replyConfig.baseForegroundColor = accentColor
        replyConfig.baseBackgroundColor = accentColor.withAlphaComponent(0.14)
        floatingReplyButton.configuration = replyConfig
        floatingReplyButton.layer.shadowColor = accentColor.cgColor
    }

    private func prepareInitialContentTransition() {
        tableView.alpha = 0
        tableView.transform = CGAffineTransform(translationX: 0, y: 8)
        bottomBar.alpha = 0
        bottomBar.transform = CGAffineTransform(translationX: 0, y: 6)
    }

    private func animateInitialContentTransition() {
        hasPresentedInitialContent = true
        let animations = {
            self.tableView.alpha = 1
            self.tableView.transform = .identity
            self.bottomBar.alpha = 1
            self.bottomBar.transform = .identity
        }
        if UIAccessibility.isReduceMotionEnabled {
            animations()
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
            animations: animations
        )
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
        configureTags(tags)
        let hasVisibleTags = !tags.isEmpty

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            tagsContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: hasVisibleTags ? 8 : 0),
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
        valueLabel.font = .systemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = .secondaryLabel
        valueLabel.text = value

        let stack = UIStackView(arrangedSubviews: [iconView, valueLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let label {
            let labelView = UILabel()
            labelView.font = .systemFont(ofSize: 13, weight: .regular)
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

    private func configureTags(_ tags: [DiscourseTopicDetail.Tag]) {
        tagsContainer.subviews.forEach { $0.removeFromSuperview() }
        tagsContainer.constraints.forEach { tagsContainer.removeConstraint($0) }
        guard !tags.isEmpty else {
            tagsContainer.heightAnchor.constraint(equalToConstant: 0).isActive = true
            return
        }

        let hSpacing: CGFloat = 6
        let vSpacing: CGFloat = 6
        let maxWidth = tableView.bounds.width - 32 // 16pt padding on each side

        var buttons: [UIButton] = []
        for tag in tags {
            let button = UIButton(type: .system)
            let color = TopicTagVisualStyle.color(for: tag.name)
            var config = UIButton.Configuration.filled()
            config.title = tag.name
            config.baseForegroundColor = color
            config.baseBackgroundColor = color.withAlphaComponent(0.10)
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 11)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 13, weight: .medium)
                return outgoing
            }
            config.image = UIImage(systemName: "tag.fill")
            config.imagePadding = 4
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            button.configuration = config
            button.layer.borderColor = color.withAlphaComponent(0.18).cgColor
            button.layer.borderWidth = 1
            button.layer.cornerCurve = .continuous
            let tagSlug = tag.slug
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                let vc = TagTopicsViewController(api: self.api, tagName: tagSlug)
                self.navigationController?.pushViewController(vc, animated: true)
            }, for: .touchUpInside)
            buttons.append(button)
        }

        // Flow layout: calculate positions with line wrapping
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for button in buttons {
            let size = button.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + vSpacing
                lineHeight = 0
            }
            button.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            button.layer.cornerRadius = size.height / 2
            tagsContainer.addSubview(button)
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

        let headerResult = buildEmojiAttributedString(title, font: titleLabel.font ?? .systemFont(ofSize: 22, weight: .semibold))
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
            SDWebImageManager.shared.loadImage(with: url, progress: nil) { [weak self] image, _, _, _, _, _ in
                guard let image, let self else { return }
                attachment.image = image
                label.setNeedsDisplay()
                self.view.setNeedsLayout()
            }
        }
    }

    // MARK: - Reading Tracking

    private func updateVisibleReadingPosts() {
        guard isViewLoaded, view.window != nil else { return }
        let postNumbers = (tableView.indexPathsForVisibleRows ?? []).compactMap { indexPath -> Int? in
            guard let postId = dataSource.itemIdentifier(for: indexPath) else { return nil }
            return viewModel.posts.first(where: { $0.id == postId })?.postNumber
        }
        readingTracker.setVisiblePostNumbers(Set(postNumbers))
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
        case let .topic(topicId):
            let detailVC = TopicDetailViewController(api: api, topicId: topicId)
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
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
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
        timeline.modalPresentationStyle = .pageSheet
        if let sheet = timeline.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
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
            if let anchorIndexPath = tableView.indexPathsForVisibleRows?.first,
               let anchorId = dataSource.itemIdentifier(for: anchorIndexPath)
            {
                let cellTopOffset = tableView.rectForRow(at: anchorIndexPath).minY - tableView.contentOffset.y
                earlierLoadAnchor = (postId: anchorId, cellTopOffset: cellTopOffset)
            }
            isLoadingEarlierLocally = true
            Task {
                await viewModel.loadEarlierPosts(containerWidth: view.bounds.width)
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
        contentRow.alignment = .fill
        contentRow.spacing = 24

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
            contentRow.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -20),

            floorTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            floorTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 62),
            editIconView.widthAnchor.constraint(equalToConstant: 16),
            editIconView.heightAnchor.constraint(equalToConstant: 16),
            statusLabel.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
            trackView.widthAnchor.constraint(equalToConstant: 88),

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

private final class TopicTimelineTrackView: UIControl {
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
    private let trackInset: CGFloat = 30
    private let handleSize: CGFloat = 46

    override var intrinsicContentSize: CGSize {
        CGSize(width: 88, height: 240)
    }

    override func draw(_ rect: CGRect) {
        let trackWidth: CGFloat = 6
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

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let image = UIImage(systemName: "arrow.up.arrow.down", withConfiguration: symbolConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let imageSize = CGSize(width: 22, height: 22)
        image?.draw(in: CGRect(
            x: handleRect.midX - imageSize.width / 2,
            y: handleRect.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        ))
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateSelection(for: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateSelection(for: touch)
        return true
    }

    private func updateSelection(for touch: UITouch) {
        let index = indexForY(touch.location(in: self).y)
        guard index != selectedIndex else { return }
        selectedIndex = index
        sendActions(for: .valueChanged)
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
    func postCell(didTapImageURL url: URL) {
        SDWebImageManager.shared.loadImage(with: url, progress: nil) { [weak self] image, _, _, _, _, _ in
            guard let self, let image else { return }
            let controller = LightboxController(images: [LightboxImage(image: image)])
            controller.dynamicBackground = true
            controller.modalPresentationStyle = .fullScreen
            self.present(controller, animated: true)
        }
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

    func postCell(didTapBoostForPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.presentBoostInput(for: post)
        }
    }

    func postCell(didTapAvatarForUsername username: String) {
        let vc = UserProfileViewController(api: api, username: username)
        navigationController?.pushViewController(vc, animated: true)
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
