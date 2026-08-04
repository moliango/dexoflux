import CookedHTML
import SafariServices
import UIKit

final class TopicDetailViewController: ObservableViewController {
    let viewModel: TopicDetailViewModel
    let api: DiscourseAPI
    let topicId: Int
    let initialFloor: Int?
    /// Last read post number from list/detail — used by jump-to-unread (Phase 1).
    var lastReadPostNumber: Int?
    let baseURL: String
    var hasTitleHeader = false
    var lastCategoryPresentation: TopicCategoryBadgePresentation?
    var isLoadingEarlierLocally = false
    var pendingScrollToFloor: Int?
    var lastScrollOffset: CGFloat = 0
    /// Measured row heights keyed by post id — stabilizes estimatedHeight while scrolling.
    var postRowHeightCache: [Int: CGFloat] = [:]
    /// Suppress load-earlier after a jump until user scrolls down first
    var suppressLoadEarlier = false
    /// Anchor info for restoring scroll position after loading earlier posts
    var earlierLoadAnchor: (postId: Int, cellTopOffset: CGFloat)?
    struct PendingPostSnapshot {
        let itemIDs: [Int]
        let earlierAnchor: (postId: Int, cellTopOffset: CGFloat)?
    }
    var isApplyingPostSnapshot = false
    var pendingPostSnapshot: PendingPostSnapshot?
    var lastReadingComfortMode = AppSettings.shared.readingComfortMode
    var lastContentFontSize = AppSettings.shared.contentFontSize
    var lastContentFontScalePercent = AppSettings.shared.contentFontScalePercent
    var lastContentFontFamily = AppSettings.shared.contentFontFamily
    var lastContentFontScope = AppSettings.shared.contentFontScope
    var lastInterfaceFontScalePercent = AppSettings.shared.interfaceFontScalePercent
    var lastThemeStyle = AppSettings.shared.themeStyle
    var hasPresentedInitialContent = false
    var isHandlingBackSwipeFallback = false
    weak var backSwipeFallbackHostView: UIView?
    lazy var readingTracker = TopicReadingTracker(api: api)
    var isShowingCollapsedNavigationTitle = false
    var lastBottomBarProgressState: (current: Int, total: Int)?
    var downloadedAttachmentURLs: Set<URL> = []
    var prefetchedImagePostIds = Set<Int>()
    var pendingSharedIssueTopicIds = Set<Int>()
    var cloudflareCompletionObservationToken: NSObjectProtocol?

    var pluginScope: PluginScope {
        PluginScope(
            baseURL: api.baseURL,
            username: AuthManager.shared.username(for: api.baseURL)
        )
    }

    enum BackSwipeFallbackMetrics {
        static let edgeActivationWidth: CGFloat = 44
        static let minimumCompletionTranslation: CGFloat = 64
        static let minimumCompletionVelocity: CGFloat = 480
    }

    lazy var backSwipeFallbackGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleBackSwipeFallback(_:)))
        gesture.maximumNumberOfTouches = 1
        // Don't cancel child touches by default — progress-bar pans live on a
        // descendant and must keep receiving the touch sequence.
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    lazy var tableView: UITableView = {
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

    lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = .init(tableView: tableView) { [weak self] tableView, indexPath, postId in
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
            topicTagNames: Set(self.viewModel.topic?.tags.map(\.name) ?? []),
            topicCategoryPresentation: self.viewModel.categoryPresentation
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

    func sharedIssueState(forFloorNumber floorNumber: Int) -> PostNativeCell.SharedIssueState? {
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

    let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    let loadingSkeletonView = TopicDetailSkeletonView()

    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = TopicDetailTypography.topicTitleFont()
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }()

    var renderedTopicTitle: String?
    var emojiUpdateObserver: NSObjectProtocol?

    let tagsContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let navTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.numberOfLines = 1
        return label
    }()

    let errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let footerSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        return spinner
    }()

    lazy var topLoadingBar: UIView = {
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

    let bottomBar = TopicDetailBottomBar()

    lazy var floatingReplyButton: UIButton = {
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

    lazy var jumpOverlay: UIView = {
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

    init(
        api: DiscourseAPI,
        topicId: Int,
        initialFloor: Int? = nil,
        lastReadPostNumber: Int? = nil
    ) {
        self.api = api
        self.viewModel = TopicDetailViewModel(api: api)
        self.topicId = topicId
        self.initialFloor = initialFloor
        self.lastReadPostNumber = lastReadPostNumber
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
        if let emojiUpdateObserver {
            NotificationCenter.default.removeObserver(emojiUpdateObserver)
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
        observe(viewModel)
        observe(AppSettings.shared)
        emojiUpdateObserver = NotificationCenter.default.addObserver(
            forName: EmojiStore.didUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let renderedTopicTitle else { return }
            self.configureTitleLabel(renderedTopicTitle)
        }
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
            // Prefer list hint; fall back to detail payload when present.
            if let detailLastRead = viewModel.topic?.lastReadPostNumber {
                lastReadPostNumber = max(lastReadPostNumber ?? 0, detailLastRead)
            }
            if let initialFloor {
                jumpToFloor(initialFloor)
            } else if let resume = resumeUnreadFloor() {
                jumpToFloor(resume)
            }
        }
        Task {
            await api.loadOrFetchEmojiMap()
            hasTitleHeader = false
            updateUI()
            // Diffable data source forbids direct reloadRows/reloadData.
            reconfigureVisiblePostCells()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        installBackSwipeFallbackGesture()
        isHandlingBackSwipeFallback = false
        syncOwningTabBarVisibility()
        bottomBar.refreshGestureRecognizers()
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

    func syncOwningTabBarVisibility() {
        (tabBarController as? ForumTabBarController)?.syncTabBarVisibilityForCurrentContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keep the progress capsule above the full-screen table so pan/long-press
        // hit-test the bar instead of scrolling the topic list. Reply stays trailing
        // and must not cover the centered capsule — bring bar last.
        view.bringSubviewToFront(floatingReplyButton)
        view.bringSubviewToFront(bottomBar)
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
            || didChangeCategoryPresentation
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
            let displayTitle = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
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
        // Settings observe → updateUI; keep swipe/long-press enablement in sync.
        bottomBar.refreshGestureRecognizers()
        updateBottomBarProgress()

        // Show posts — all visible posts that have parsed blocks
        if viewModel.isReady {
            let shouldAnimateInitialContent = !hasPresentedInitialContent && tableView.isHidden
            if shouldAnimateInitialContent {
                prepareInitialContentTransition()
            }
            tableView.isHidden = false
            var seen = Set<Int>()
            let sourcePosts: [DiscourseTopicDetail.Post] = {
                if AppSettings.shared.nestedReplyViewEnabled {
                    return NestedReplyOrdering.ordered(viewModel.visiblePosts).map { $0.post }
                }
                return viewModel.visiblePosts
            }()
            let readyIds = sourcePosts.compactMap { post -> Int? in
                guard viewModel.parsedBlocks[post.id] != nil,
                      seen.insert(post.id).inserted else { return nil }
                return post.id
            }
            prefetchContentImages(forPostIds: readyIds)
            let completedEarlierAnchor = viewModel.isLoadingEarlier ? nil : earlierLoadAnchor
            applyPostSnapshot(itemIDs: readyIds, earlierAnchor: completedEarlierAnchor)
            if shouldReloadVisibleContent {
                reconfigureVisiblePostCells(reloadAllIfNoneVisible: true)
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

    func applyThemeStyle() {
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

    func applyTypography() {
        titleLabel.font = TopicDetailTypography.topicTitleFont()
        navTitleLabel.font = TopicDetailTypography.interfaceFont(ofSize: 17, weight: .semibold)
        errorLabel.font = TopicDetailTypography.interfaceFont(ofSize: 14, weight: .regular)
    }

    func prepareInitialContentTransition() {
        tableView.alpha = 0
        tableView.transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.996, y: 0.996)
        bottomBar.alpha = 0
        bottomBar.transform = CGAffineTransform(translationX: 0, y: 8)
    }

    func animateInitialContentTransition() {
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

    func prefetchContentImages(forPostIds postIds: [Int]) {
        let newPostIds = postIds.filter { postId in
            prefetchedImagePostIds.insert(postId).inserted
        }
        let contentURLs = newPostIds.flatMap { postId in
            viewModel.parsedBlocks[postId]?.imageSourceURLs.compactMap(URL.init(string:)) ?? []
        }
        ForumImageLoader.prefetch(urls: contentURLs, cloudflareBaseURL: baseURL)
        AvatarImageLoader.prefetch(
            urls: avatarURLs(forPostIds: newPostIds),
            cloudflareBaseURL: baseURL
        )
    }

    func avatarURLs(forPostIds postIds: [Int]) -> [URL] {
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

    func startObservingCloudflareVerification() {
        cloudflareCompletionObservationToken = NotificationCenter.default.addObserver(
            forName: DiscourseAPI.cloudflareVerificationCompletedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareVerificationCompleted(notification)
        }
    }

    func handleCloudflareVerificationCompleted(_ notification: Notification) {
        guard let verifiedBaseURL = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String,
              ForumInstance.normalizedBaseURL(verifiedBaseURL) == ForumInstance.normalizedBaseURL(baseURL)
        else { return }

        // Flip CF error copy immediately so dismiss doesn't leave "still need to verify".
        viewModel.errorMessage = String(
            localized: "cloudflare.recovering",
            defaultValue: "验证已通过，正在重新加载…"
        )
        viewModel.notifyChanged()
        errorLabel.text = viewModel.errorMessage
        errorLabel.isHidden = false
        loadingSkeletonView.setSkeletonActive(true, animated: true)

        Task { [weak self] in
            guard let self else { return }
            await WebCookieStore.shared.forceSyncCloudflareClearance(for: self.baseURL)
            self.api.resetSession()

            let readyPostIds = self.viewModel.posts.compactMap { post in
                self.viewModel.parsedBlocks[post.id] == nil ? nil : post.id
            }
            AvatarImageLoader.credentialsDidChange(
                for: self.baseURL,
                retrying: self.avatarURLs(forPostIds: readyPostIds)
            )
            self.prefetchedImagePostIds.removeAll()

            await self.viewModel.recoverAfterCloudflare(
                id: self.topicId,
                containerWidth: self.view.bounds.width
            )

            await MainActor.run {
                self.loadingSkeletonView.setSkeletonActive(false, animated: true)
                if self.viewModel.isReady {
                    let ids = self.viewModel.posts.compactMap {
                        self.viewModel.parsedBlocks[$0.id] == nil ? nil : $0.id
                    }
                    self.prefetchContentImages(forPostIds: ids)
                }
            }
        }
    }

    func updateTitleHeader() {
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

    func makeTopicMetadataRow(_ topic: DiscourseTopicDetail) -> UIStackView {
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

    func makeTopicMetadataItem(symbolName: String, value: String, label: String?) -> UIView {
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

    func formatCompactCount(_ value: Int) -> String {
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    func formatRelativeDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString)
        guard let date else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    func configureTaxonomy(
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

    func configureTitleLabel(_ title: String) {
        renderedTopicTitle = title
        let headerFont = titleLabel.font ?? TopicDetailTypography.topicTitleFont()
        let navFont = navTitleLabel.font ?? .systemFont(ofSize: 17, weight: .semibold)
        TitleEmojiRenderer.apply(
            title,
            to: titleLabel,
            font: headerFont,
            textColor: titleLabel.textColor,
            baseURL: baseURL
        )
        TitleEmojiRenderer.apply(
            title,
            to: navTitleLabel,
            font: navFont,
            textColor: navTitleLabel.textColor,
            baseURL: baseURL
        )
        navTitleLabel.sizeToFit()
    }

    // MARK: - Reading Tracking

    func updateVisibleReadingPosts() {
        guard isViewLoaded, view.window != nil, !isApplyingPostSnapshot else { return }
        let postNumbers = (tableView.indexPathsForVisibleRows ?? []).compactMap { indexPath -> Int? in
            guard let postId = dataSource.itemIdentifier(for: indexPath) else { return nil }
            return viewModel.posts.first(where: { $0.id == postId })?.postNumber
        }
        readingTracker.setVisiblePostNumbers(Set(postNumbers))
    }

    func applyPostSnapshot(
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

    func replyButtonTapped() {
        performAuthenticated { [weak self] in
            self?.presentReplyComposer()
        }
    }

    func performAuthenticated(_ action: @escaping () -> Void) {
        if let authGate = findAuthGating() {
            authGate.requireAuth(then: action)
        } else {
            action()
        }
    }

    func findAuthGating() -> AuthGating? {
        nearestAuthGating()
    }

    func showPostActionError(_ error: Error) {
        let alert = UIAlertController(
            title: String(localized: "post.action.failed"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func reloadPostCell(postId: Int) {
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(postId) != nil else { return }
        snapshot.reloadItems([postId])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Safe refresh for DiffableDataSource-backed table (never call reloadData/reloadRows directly).
    func reconfigureVisiblePostCells(reloadAllIfNoneVisible: Bool = false) {
        var snapshot = dataSource.snapshot()
        guard !snapshot.itemIdentifiers.isEmpty else { return }

        let visibleIds = (tableView.indexPathsForVisibleRows ?? []).compactMap {
            dataSource.itemIdentifier(for: $0)
        }.filter { snapshot.indexOfItem($0) != nil }

        let ids: [Int]
        if !visibleIds.isEmpty {
            ids = visibleIds
        } else if reloadAllIfNoneVisible {
            ids = snapshot.itemIdentifiers
        } else {
            return
        }

        snapshot.reloadItems(ids)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func updateBottomBarProgress() {
        let current = currentVisibleFloor()
        let total = viewModel.totalFloors
        if let lastBottomBarProgressState,
           lastBottomBarProgressState.current == current,
           lastBottomBarProgressState.total == total {
            // Numbers unchanged, but still re-apply gesture enablement in case
            // the user toggled Reading → 进度条手势 while this page stayed alive.
            bottomBar.refreshGestureRecognizers()
            return
        }
        lastBottomBarProgressState = (current: current, total: total)
        bottomBar.configure(
            currentFloor: current,
            totalFloors: total
        )
    }

    func currentVisibleFloor() -> Int {
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

    func shareTopicLink(sourceView: UIView?) {
        let link = "\(baseURL)/t/\(topicId)"
        let activity = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = sourceView ?? view
        activity.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(activity, animated: true)
    }

    func makeExportMenu() -> UIMenu {
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
        let notionMenus = NotionSyncScope.allCases.map { scope in
            UIAction(title: scope.title) { [weak self] _ in
                self?.syncTopicToNotion(scope: scope)
            }
        }
        let notionMenu = UIMenu(
            title: String(localized: "notion.sync", defaultValue: "同步到 Notion"),
            image: UIImage(systemName: "tray.and.arrow.up"),
            children: notionMenus
        )
        return UIMenu(
            title: String(localized: "topic.export", defaultValue: "导出话题"),
            image: UIImage(systemName: "square.and.arrow.up"),
            children: formatMenus + [notionMenu]
        )
    }

    func configureTopicActions() {
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
        // AI 助手只保留在进度条长按弧形菜单里，避免顶栏重复入口。
        navigationItem.rightBarButtonItems = [moreButton, searchButton]
    }

    @objc func aiAssistantTapped() {
        let chat = AIChatSheetViewController(
            api: api,
            topicId: topicId,
            topicTitle: viewModel.topic?.title
        )
        if let sheet = chat.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = .medium
        }
        present(chat, animated: true)
    }

    @objc func pluginStateDidChange() {
        configureTopicActions()
    }

    @objc func searchTopicTapped() {
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

    func performTopicSearch(_ query: String) {
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

    func presentSearchResults(_ posts: [DiscourseSearchResult.SearchPost], query: String) {
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
            let excerptSource = post.blurb ?? post.username
            let excerpt = CookedContentPipeline.plainTextPreview(fromCooked: excerptSource)
            let title = "#\(post.postNumber)  \(String((excerpt.isEmpty ? post.username : excerpt).prefix(70)))"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.jumpToFloor(post.postNumber)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        present(sheet, animated: true)
    }

    func title(for level: DiscourseTopicDetail.NotificationLevel) -> String {
        switch level {
        case .watching: return String(localized: "topic.notifications.watching", defaultValue: "关注")
        case .tracking: return String(localized: "topic.notifications.tracking", defaultValue: "跟踪")
        case .regular: return String(localized: "topic.notifications.regular", defaultValue: "常规")
        case .muted: return String(localized: "topic.notifications.muted", defaultValue: "静音")
        }
    }

    func setNotificationLevel(_ level: DiscourseTopicDetail.NotificationLevel) {
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

    func editTopic() {
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

    func shareTopicImage(postId: Int? = nil) {
        guard let topic = viewModel.topic else { return }
        let post: DiscourseTopicDetail.Post? = {
            if let postId {
                return viewModel.posts.first(where: { $0.id == postId })
            }
            return viewModel.posts.first(where: { $0.postNumber == 1 && $0.actionCode == nil })
                ?? viewModel.posts.first(where: { $0.actionCode == nil })
        }()
        guard let post else {
            showPostActionError(NSError(domain: "ShareImage", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "share.image.no_content", defaultValue: "暂无可分享内容")]))
            return
        }

        let displayTitle = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
        let authorName = (post.name?.isEmpty == false ? post.name! : post.username)
        let createdAtText: String? = {
            let createdAt = post.createdAt
            guard !createdAt.isEmpty else { return nil }
            return TopicCell.formatDate(createdAt)
        }()
        let avatarURL = AvatarImageLoader.url(from: post.avatarTemplate, baseURL: baseURL, size: 120)
        let host = URL(string: baseURL)?.host?.lowercased() ?? ""
        let brandName = host.contains("linux.do") ? "LINUX DO" : "DexoFlux"
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let shareURL = "\(trimmedBase)/t/\(topicId)/\(post.postNumber)"

        // Always share **readable cooked HTML**. Never paint markdown `raw` as-is.
        // If cooked is missing, convert raw → simple HTML first.
        let cookedTrimmed = post.cooked.trimmingCharacters(in: .whitespacesAndNewlines)
        let shareHTML: String = {
            if !cookedTrimmed.isEmpty {
                return PostImageLinkPreprocessor.rewrite(cookedTrimmed)
            }
            if let raw = post.raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return ShareImageBodyComposer.normalizeCookedInput(raw)
            }
            return ""
        }()
        let contentBlocks = (viewModel.parsedBlocks[post.id] ?? []).map(\.block)

        let preview = ShareImagePreviewViewController(
            model: .init(
                topicId: topicId,
                baseURL: baseURL,
                title: displayTitle,
                brandName: brandName,
                authorName: authorName,
                username: post.username,
                createdAtText: createdAtText,
                avatarURL: avatarURL,
                cookedHTML: shareHTML,
                contentBlocks: contentBlocks,
                shareURL: shareURL,
                postNumber: post.postNumber
            )
        )
        present(preview, animated: true)
    }


    func syncTopicToNotion(scope: NotionSyncScope, duplicate: NotionDuplicateAction = .skip) {
        guard let topic = viewModel.topic else { return }
        let username = findAuthGating()?.currentUsername()
        let scopeKey = NotionConfigStore.shared.scopeKey(baseURL: baseURL, username: username)
        guard let token = NotionConfigStore.shared.token(scopeKey: scopeKey), !token.isEmpty,
              NotionConfigStore.shared.isComplete(scopeKey: scopeKey) else {
            let alert = UIAlertController(
                title: String(localized: "notion.not_configured", defaultValue: "请先配置 Notion"),
                message: String(localized: "notion.not_configured.message", defaultValue: "在「我的」里打开 Notion 同步并填写 Token 与 Database ID"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "好"), style: .default))
            present(alert, animated: true)
            return
        }

        let config = NotionConfigStore.shared.loadConfig(scopeKey: scopeKey)
        let title = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
        let posts = viewModel.posts
        let hud = UIAlertController(
            title: String(localized: "notion.syncing", defaultValue: "正在同步到 Notion…"),
            message: nil,
            preferredStyle: .alert
        )
        present(hud, animated: true)

        Task { [weak self] in
            guard let self else { return }
            do {
                let service = NotionSyncService(config: config, token: token, baseURL: self.baseURL)
                let result = try await service.syncTopic(
                    topicId: self.topicId,
                    title: title,
                    posts: posts,
                    scope: scope,
                    onDuplicate: duplicate
                )
                await MainActor.run {
                    hud.dismiss(animated: true) {
                        if result.duplicated && duplicate == .skip {
                            let ask = UIAlertController(
                                title: String(localized: "notion.duplicate.title", defaultValue: "Notion 中已存在"),
                                message: String(localized: "notion.duplicate.message", defaultValue: "该话题已同步过，选择跳过或覆盖"),
                                preferredStyle: .alert
                            )
                            ask.addAction(UIAlertAction(title: String(localized: "notion.duplicate.skip", defaultValue: "跳过"), style: .cancel))
                            ask.addAction(UIAlertAction(title: String(localized: "notion.open_page", defaultValue: "打开已有页面"), style: .default) { _ in
                                if let url = URL(string: result.pageURL) {
                                    UIApplication.shared.open(url)
                                }
                            })
                            ask.addAction(UIAlertAction(title: String(localized: "notion.duplicate.overwrite", defaultValue: "覆盖"), style: .destructive) { [weak self] _ in
                                self?.syncTopicToNotion(scope: scope, duplicate: .overwrite)
                            })
                            self.present(ask, animated: true)
                        } else {
                            self.presentNotionSuccess(result)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    hud.dismiss(animated: true) {
                        self.showPostActionError(error)
                    }
                }
            }
        }
    }

    func maybeAutoSyncNotionAfterBookmark() {
        let username = findAuthGating()?.currentUsername()
        let scopeKey = NotionConfigStore.shared.scopeKey(baseURL: baseURL, username: username)
        let config = NotionConfigStore.shared.loadConfig(scopeKey: scopeKey)
        guard config.autoSyncOnBookmark,
              let token = NotionConfigStore.shared.token(scopeKey: scopeKey),
              NotionConfigStore.shared.isComplete(scopeKey: scopeKey),
              let topic = viewModel.topic
        else { return }
        Task {
            let service = NotionSyncService(config: config, token: token, baseURL: baseURL)
            _ = try? await service.syncTopic(
                topicId: topicId,
                title: TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title),
                posts: viewModel.posts,
                scope: config.syncScope,
                onDuplicate: .skip
            )
        }
    }

    func presentNotionSuccess(_ result: NotionSyncResult) {
        let alert = UIAlertController(
            title: String(localized: "notion.sync.success", defaultValue: "同步成功"),
            message: String(localized: "notion.sync.success_message", defaultValue: "已写入 Notion"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "好"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "notion.open_page", defaultValue: "打开页面"), style: .default) { _ in
            if let url = URL(string: result.pageURL) {
                UIApplication.shared.open(url)
            }
        })
        present(alert, animated: true)
    }

    func exportTopic(format: TopicExportFormat, range: TopicExportRange) {
        guard let topic = viewModel.topic else {
            showPostActionError(TopicExportError.noPosts)
            return
        }
        let title = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
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

    func bookmarkTopic() {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    if self.viewModel.topic?.bookmarked == true,
                       let bookmarkId = self.viewModel.topic?.bookmarkId {
                        try await self.api.deleteBookmark(id: bookmarkId)
                    } else {
                        _ = try await self.api.createBookmark(topicId: self.topicId)
                        await MainActor.run { self.maybeAutoSyncNotionAfterBookmark() }
                    }
                    await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
                } catch {
                    self.showPostActionError(error)
                }
            }
        }
    }

    // MARK: - Link Handling

    func handleLink(_ url: URL) {
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

    func openInternalDestination(_ destination: ForumInternalLinkDestination) {
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

    func downloadAndShareAttachment(_ url: URL) {
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

    func makeAttachmentDownloadAlert() -> UIAlertController {
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

    func presentAttachmentShareSheet(_ fileURL: URL) {
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = view.bounds
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.downloadedAttachmentURLs.remove(fileURL)
            ForumAttachmentDownloader.cleanupDownloadedFile(fileURL)
        }
        present(activity, animated: true)
    }

    func openInternalViewController(_ viewController: UIViewController) {
        if let navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: viewController)
            present(nav, animated: true)
        }
    }

    func presentSafari(_ url: URL) {
        guard AppSettings.shared.openExternalLinksInAppBrowser else {
            UIApplication.shared.open(url)
            return
        }
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }
}

