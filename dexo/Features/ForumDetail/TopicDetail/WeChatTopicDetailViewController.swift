import CookedHTML
import SafariServices
import UIKit

/// WeChat chat-style Topic Detail. Parallel to `TopicDetailViewController` — classic path unchanged.
final class WeChatTopicDetailViewController: ObservableViewController {
    let api: DiscourseAPI
    let viewModel: TopicDetailViewModel
    let topicId: Int
    let initialFloor: Int?
    let initialPostId: Int?
    let baseURL: String
    private let forum: ForumInstance?

    private var didLoad = false
    private var cloudflareCompletionObservationToken: NSObjectProtocol?
    private var isRecoveringAfterCloudflare = false
    private var isLoadingMore = false
    private var isLoadingEarlier = false

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(WeChatChatPostCell.self, forCellReuseIdentifier: WeChatChatPostCell.reuseIdentifier)
        tv.separatorStyle = .none
        tv.backgroundColor = Self.chatBackgroundColor
        tv.keyboardDismissMode = .interactive
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 120
        tv.showsVerticalScrollIndicator = !AppSettings.shared.hideScrollIndicators
        tv.showsHorizontalScrollIndicator = false
        tv.delegate = self
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = {
        UITableViewDiffableDataSource<Int, Int>(tableView: tableView) { [weak self] tableView, indexPath, postId in
            guard let self,
                  let post = self.viewModel.posts.first(where: { $0.id == postId }),
                  let cell = tableView.dequeueReusableCell(
                    withIdentifier: WeChatChatPostCell.reuseIdentifier,
                    for: indexPath
                  ) as? WeChatChatPostCell
            else {
                return UITableViewCell()
            }

            // Prefer parsed blocks; empty array still renders plain-text fallback in the cell.
            let annotatedBlocks = self.viewModel.parsedBlocks[postId] ?? []
            let floorNumber = self.floorNumber(for: postId)
            let tableWidth = tableView.bounds.width > 1 ? tableView.bounds.width : UIScreen.main.bounds.width
            // Row: 12 + avatar40 + 8 + bubble + 12(trailing margin) ≈ usable bubble outer.
            // Inner content width = outer - bubble padding*2; keep generous for forum posts.
            let maxOuter = tableWidth - 12 - 40 - 8 - 12
            let bubbleOuter = max(maxOuter * 0.92, 200)
            let bubbleWidth = max(bubbleOuter - 24, 160) // inner content width for NativeRenderConfig
            let galleryImageURLs = TopicImageGallerySources.urls(from: annotatedBlocks)
            var config = NativeRenderConfig.default(
                contentWidth: bubbleWidth,
                baseURL: self.baseURL,
                postId: post.id,
                galleryImageURLs: galleryImageURLs,
                topicTagNames: Set(self.viewModel.topic?.tags.map(\.name) ?? []),
                topicCategoryPresentation: self.viewModel.categoryPresentation
            )
            // Slightly denser body for chat bubbles.
            config = NativeRenderConfig(
                baseFont: config.baseFont,
                baseColor: post.yours ? UIColor.black.withAlphaComponent(0.9) : .label,
                linkColor: post.yours
                    ? UIColor(red: 0.05, green: 0.35, blue: 0.75, alpha: 1)
                    : config.linkColor,
                codeFont: config.codeFont,
                codeBackgroundColor: config.codeBackgroundColor,
                contentWidth: config.contentWidth,
                baseURL: config.baseURL,
                postId: config.postId,
                galleryImageURLs: config.galleryImageURLs,
                topicTagNames: config.topicTagNames,
                topicCategoryPresentation: config.topicCategoryPresentation,
                defaultLineSpacing: config.defaultLineSpacing,
                defaultParagraphSpacing: config.defaultParagraphSpacing
            )

            cell.actionDelegate = self
            cell.configure(
                with: post,
                annotatedBlocks: annotatedBlocks,
                config: config,
                floorNumber: floorNumber,
                baseURL: self.baseURL,
                contentDelegate: self
            )
            return cell
        }
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
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

    /// WeChat-like bottom composer entry (opens full ReplyComposer).
    private lazy var inputBar: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "wechat_chat.input_placeholder", defaultValue: "回复…")
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        config.background.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.16, alpha: 1)
                : UIColor.white
        }
        config.background.cornerRadius = 6
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] _ in
            self?.performAuthenticated { self?.presentReplyComposer(for: nil) }
        }, for: .touchUpInside)
        return button
    }()

    private let inputContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.11, alpha: 1)
                : UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        }
        return view
    }()

    private static var chatBackgroundColor: UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
            }
            // WeChat light chat gray
            return UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
        }
    }

    init(
        api: DiscourseAPI,
        topicId: Int,
        initialFloor: Int? = nil,
        initialPostId: Int? = nil,
        lastReadPostNumber: Int? = nil,
        forum: ForumInstance? = nil
    ) {
        self.api = api
        self.viewModel = TopicDetailViewModel(api: api)
        self.topicId = topicId
        self.initialFloor = initialFloor
        self.initialPostId = initialPostId
        self.baseURL = api.baseURL
        self.forum = forum
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
        _ = lastReadPostNumber // reserved for jump-to-unread follow-up
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
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observe(viewModel)
        startObservingCloudflareVerification()
        view.backgroundColor = Self.chatBackgroundColor
        navigationItem.largeTitleDisplayMode = .never
        title = String(localized: "topic_detail.default_title", defaultValue: "话题")

        inputContainer.addSubview(inputBar)
        view.addSubview(tableView)
        view.addSubview(inputContainer)
        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)

        let topLine = UIView()
        topLine.translatesAutoresizingMaskIntoConstraints = false
        topLine.backgroundColor = UIColor.separator.withAlphaComponent(0.45)
        inputContainer.addSubview(topLine)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor),

            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topLine.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            topLine.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            inputBar.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 8),
            inputBar.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            inputBar.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),
            inputBar.bottomAnchor.constraint(equalTo: inputContainer.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            inputBar.heightAnchor.constraint(equalToConstant: 40),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didLoad else { return }
        didLoad = true
        Task { await loadInitial() }
    }

    override func updateUI() {
        tableView.showsVerticalScrollIndicator = !AppSettings.shared.hideScrollIndicators
        tableView.showsHorizontalScrollIndicator = false
        if let topic = viewModel.topic {
            let display = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
            title = display
            navigationItem.title = display
        }

        if viewModel.isLoading && !viewModel.isReady {
            activityIndicator.startAnimating()
            tableView.isHidden = true
            errorLabel.isHidden = true
        } else {
            activityIndicator.stopAnimating()
            tableView.isHidden = false
        }

        if let error = viewModel.errorMessage, !viewModel.isReady {
            errorLabel.isHidden = false
            errorLabel.text = error
            tableView.isHidden = true
        } else {
            errorLabel.isHidden = true
        }

        if viewModel.isReady {
            applySnapshot()
        }
    }

    private func loadInitial() async {
        await viewModel.loadTopic(id: topicId, containerWidth: max(view.bounds.width, UIScreen.main.bounds.width))
        if let postId = initialPostId {
            scrollToPostId(postId)
        } else if let floor = initialFloor {
            await jumpToFloor(floor)
        }
    }

    private func applySnapshot() {
        // Only show posts that finished HTML parse — same gate as classic Topic Detail.
        // (Cell still has plain-text fallback if blocks are empty.)
        var seen = Set<Int>()
        let ids = viewModel.visiblePosts.compactMap { post -> Int? in
            guard viewModel.parsedBlocks[post.id] != nil,
                  seen.insert(post.id).inserted
            else { return nil }
            return post.id
        }
        let current = dataSource.snapshot().itemIdentifiers
        guard ids != current else {
            // Same IDs: still reconfigure visible rows so reaction/bookmark state refreshes.
            var snapshot = dataSource.snapshot()
            let visible = (tableView.indexPathsForVisibleRows ?? []).compactMap {
                dataSource.itemIdentifier(for: $0)
            }.filter { snapshot.indexOfItem($0) != nil }
            if !visible.isEmpty {
                snapshot.reloadItems(visible)
                dataSource.apply(snapshot, animatingDifferences: false)
            }
            return
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func floorNumber(for postId: Int) -> Int {
        let allPostIds = viewModel.allPostIds
        if let streamIndex = allPostIds.firstIndex(of: postId) {
            return streamIndex + 1
        }
        return (viewModel.visiblePosts.firstIndex(where: { $0.id == postId }) ?? 0) + 1
    }

    private func reloadPostCell(postId: Int) {
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(postId) != nil else { return }
        snapshot.reloadItems([postId])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func scrollToPostId(_ postId: Int) {
        guard let index = dataSource.snapshot().indexOfItem(postId) else { return }
        let indexPath = IndexPath(row: index, section: 0)
        tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
    }

    private func jumpToFloor(_ floor: Int) async {
        await viewModel.jumpToFloor(floor, containerWidth: view.bounds.width)
        applySnapshot()
        let ids = viewModel.allPostIds
        guard floor >= 1, floor <= ids.count else { return }
        let postId = ids[floor - 1]
        DispatchQueue.main.async { [weak self] in
            self?.scrollToPostId(postId)
        }
    }

    // MARK: - Auth / errors

    private func performAuthenticated(_ action: @escaping () -> Void) {
        if let gate = nearestAuthGating() {
            gate.requireAuth(then: action)
        } else {
            action()
        }
    }

    private func showPostActionError(_ error: Error) {
        let alert = UIAlertController(
            title: String(localized: "post.action.failed", defaultValue: "操作失败"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Composer / boost

    private func presentReplyComposer(for post: DiscourseTopicDetail.Post?, initialText: String? = nil) {
        let composer = ReplyComposerViewController(
            api: api,
            topicId: topicId,
            replyToPost: post,
            baseURL: baseURL,
            initialText: initialText,
            mentionSeedUsers: mentionSeedUsers()
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
        }
        present(composer, animated: true)
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
        }
        present(input, animated: true)
    }

    private func mentionSeedUsers() -> [DiscourseMentionUser] {
        var seen = Set<String>()
        var users: [DiscourseMentionUser] = []
        for post in viewModel.posts {
            let key = post.username.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            users.append(
                DiscourseMentionUser(
                    username: post.username,
                    name: post.name,
                    avatarTemplate: post.avatarTemplate
                )
            )
            if users.count >= 12 { break }
        }
        return users
    }

    private func handleLink(_ url: URL) {
        let linkURL = ForumInternalLinkParser.normalizedURL(from: url, baseURL: baseURL)
        if ForumInternalLinkParser.isInternalURL(linkURL, baseURL: baseURL),
           let destination = ForumInternalLinkParser.destination(for: linkURL) {
            switch destination {
            case let .topic(id, postNumber):
                if id == topicId, let postNumber {
                    Task { await jumpToFloor(postNumber) }
                } else {
                    let vc = TopicDetailFactory.make(
                        api: api,
                        topicId: id,
                        initialFloor: postNumber,
                        forum: forum
                    )
                    navigationController?.pushViewController(vc, animated: true)
                }
            case let .category(slug, categoryId):
                let category = DiscourseCategory(id: categoryId, name: slug, slug: slug)
                navigationController?.pushViewController(
                    CategoryTopicsViewController(api: api, category: category),
                    animated: true
                )
            case let .tag(tagName):
                navigationController?.pushViewController(
                    TagTopicsViewController(api: api, tagName: tagName),
                    animated: true
                )
            }
        } else {
            present(SFSafariViewController(url: linkURL), animated: true)
        }
    }

// MARK: - Cloudflare recovery

    private func startObservingCloudflareVerification() {
        guard cloudflareCompletionObservationToken == nil else { return }
        cloudflareCompletionObservationToken = NotificationCenter.default.addObserver(
            forName: DiscourseAPI.cloudflareVerificationCompletedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareVerificationCompleted(notification)
        }
    }

    /// Also invoked as a backup from ForumContainer after CF sheet dismiss.
    func handleCloudflareVerificationCompleted(_ notification: Notification) {
        if let verifiedBaseURL = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String {
            guard ForumInstance.normalizedBaseURL(verifiedBaseURL) == ForumInstance.normalizedBaseURL(baseURL)
            else { return }
        }
        guard !isRecoveringAfterCloudflare else { return }
        isRecoveringAfterCloudflare = true

        // Unstick UI immediately — CF sheet / grace races must not leave the chat frozen.
        view.isUserInteractionEnabled = true
        tableView.isUserInteractionEnabled = true
        tableView.isScrollEnabled = true
        errorLabel.isHidden = false
        errorLabel.text = String(
            localized: "cloudflare.recovering",
            defaultValue: "验证已通过，正在重新加载…"
        )

        Task { [weak self] in
            guard let self else { return }
            defer { self.isRecoveringAfterCloudflare = false }
            await WebCookieStore.shared.forceSyncCloudflareClearance(for: self.baseURL)
            self.api.resetSession()
            let width = max(self.view.bounds.width, UIScreen.main.bounds.width)
            await self.viewModel.recoverAfterCloudflare(id: self.topicId, containerWidth: width)
            await MainActor.run {
                self.view.isUserInteractionEnabled = true
                self.tableView.isUserInteractionEnabled = true
                self.tableView.isScrollEnabled = true
                self.applySnapshot()
                if self.viewModel.isReady {
                    self.errorLabel.isHidden = true
                    self.tableView.isHidden = false
                }
            }
        }
    }

}

// MARK: - Table

extension WeChatTopicDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        140
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? WeChatChatPostCell)?.requestHeightReconciliation()

        guard let postId = dataSource.itemIdentifier(for: indexPath) else { return }
        if let streamIndex = viewModel.allPostIds.firstIndex(of: postId) {
            let width = max(view.bounds.width, UIScreen.main.bounds.width)
            viewModel.acknowledgeVisibleTailIfNeeded(visibleStreamIndex: streamIndex)
            Task {
                await viewModel.ensureForwardWindowReady(
                    visibleStreamIndex: streamIndex,
                    containerWidth: width
                )
            }
        }

        let total = tableView.numberOfRows(inSection: 0)
        if indexPath.row >= max(0, total - 4) {
            loadMoreIfNeeded()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard viewModel.isReady else { return }
        let offsetY = scrollView.contentOffset.y
        let contentH = scrollView.contentSize.height
        let frameH = scrollView.frame.height

        if offsetY > contentH - frameH * 1.6 {
            loadMoreIfNeeded()
        }
        if offsetY < 80 {
            loadEarlierIfNeeded()
        }
    }

    private func loadMoreIfNeeded() {
        guard !isLoadingMore, viewModel.canLoadMore else { return }
        isLoadingMore = true
        let width = max(view.bounds.width, UIScreen.main.bounds.width)
        Task {
            await viewModel.loadMorePosts(containerWidth: width)
            isLoadingMore = false
        }
    }

    private func loadEarlierIfNeeded() {
        guard !isLoadingEarlier, viewModel.canLoadEarlier else { return }
        isLoadingEarlier = true
        let width = max(view.bounds.width, UIScreen.main.bounds.width)
        Task {
            _ = await viewModel.loadEarlierPosts(containerWidth: width)
            isLoadingEarlier = false
        }
    }
}

// MARK: - Long-press actions

extension WeChatTopicDetailViewController: WeChatChatPostCellDelegate {
    func weChatChatPostCell(_ cell: WeChatChatPostCell, didRequestLike post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            let reactionId = post.currentUserReaction?.id ?? "heart"
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

    func weChatChatPostCell(_ cell: WeChatChatPostCell, didRequestReply post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.presentReplyComposer(for: post)
        }
    }

    func weChatChatPostCell(_ cell: WeChatChatPostCell, didRequestBookmark post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            let shouldBookmark = !post.bookmarked
            Task {
                do {
                    if shouldBookmark {
                        let response = try await self.api.createBookmark(postId: post.id)
                        self.viewModel.updatePostBookmark(
                            postId: post.id,
                            bookmarked: true,
                            bookmarkId: response.id
                        )
                    } else if let bookmarkId = post.bookmarkId {
                        try await self.api.deleteBookmark(id: bookmarkId)
                        self.viewModel.updatePostBookmark(
                            postId: post.id,
                            bookmarked: false,
                            bookmarkId: nil
                        )
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

    func weChatChatPostCell(_ cell: WeChatChatPostCell, didRequestBoost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.presentBoostInput(for: post)
        }
    }

    func weChatChatPostCell(_ cell: WeChatChatPostCell, didTapAvatar username: String) {
        let previewVC = UserProfilePreviewViewController(api: api, username: username)
        previewVC.onViewProfile = { [weak self] selectedUsername in
            guard let self else { return }
            let vc = UserProfileViewController(api: self.api, username: selectedUsername)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        present(previewVC, animated: true)
    }
}

// MARK: - Content taps (native blocks inside bubble)

extension WeChatTopicDetailViewController: PostCellDelegate {
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

    func postCell(didTapToggleDetails detailsIndex: Int, postId: Int) {}

    func postCell(didTapReplyToPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.presentReplyComposer(for: post)
        }
    }

    func postCell(didTapEditPost post: DiscourseTopicDetail.Post) {}

    func postCell(didTapShareImageForPost post: DiscourseTopicDetail.Post) {}

    func postCell(didTapShowRevisionForPost post: DiscourseTopicDetail.Post) {}

    func postCell(didToggleBookmarkForPost post: DiscourseTopicDetail.Post, isBookmarked: Bool) {
        // Route through the same bookmark action used by long-press.
        performAuthenticated { [weak self] in
            guard let self else { return }
            let shouldBookmark = isBookmarked
            Task {
                do {
                    if shouldBookmark {
                        let response = try await self.api.createBookmark(postId: post.id)
                        self.viewModel.updatePostBookmark(postId: post.id, bookmarked: true, bookmarkId: response.id)
                    } else if let bookmarkId = post.bookmarkId {
                        try await self.api.deleteBookmark(id: bookmarkId)
                        self.viewModel.updatePostBookmark(postId: post.id, bookmarked: false, bookmarkId: nil)
                    }
                    self.reloadPostCell(postId: post.id)
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
        let previewVC = UserProfilePreviewViewController(api: api, username: username)
        previewVC.onViewProfile = { [weak self] selectedUsername in
            guard let self else { return }
            let vc = UserProfileViewController(api: self.api, username: selectedUsername)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        present(previewVC, animated: true)
    }

    func postCell(didTapQuotedPostNumber postNumber: Int) {
        Task { await jumpToFloor(postNumber) }
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
                    }
                } catch {
                    self.showPostActionError(error)
                }
            }
        }
    }

    func postCell(didTapToggleSharedIssueForTopicId topicId: Int) {}

    func postCell(didSubmitPollVoteForPostId postId: Int, pollName: String, optionIds: [String]) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.viewModel.submitPollVote(
                        postId: postId,
                        pollName: pollName,
                        optionIds: optionIds
                    )
                    self.reloadPostCell(postId: postId)
                } catch {
                    self.reloadPostCell(postId: postId)
                    self.showPostActionError(error)
                }
            }
        }
    }
}
