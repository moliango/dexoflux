import UIKit

fileprivate enum DraftsListSection: Int, CaseIterable {
    case local = 0
    case cloud = 1
}

final class DraftsViewController: ObservableViewController {
    private let api: DiscourseAPI
    private var localDrafts: [ComposerLocalDraftStore.ListedDraft] = []
    private var drafts: [DiscourseDraft] = []
    private var hasMore = false
    private var isLoading = false
    private var isLoadingMore = false
    private var isOpeningDraft = false
    private var errorMessage: String?

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = DraftCell.estimatedHeight
        tableView.showsVerticalScrollIndicator = !AppSettings.shared.hideScrollIndicators
        TopicListCellFactory.registerCells(on: tableView)
        tableView.register(DraftCell.self, forCellReuseIdentifier: DraftCell.reuseIdentifier)
        return tableView
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private let stateIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .tertiaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        return label
    }()

    private let retryButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = String(localized: "action.retry")
        configuration.cornerStyle = .medium
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var stateStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [stateIconView, stateLabel, retryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        return control
    }()

    init(api: DiscourseAPI) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observe(AppSettings.shared)
        title = String(localized: "me.drafts", defaultValue: "草稿")
        applyThemeStyle()
        tableView.refreshControl = refreshControl
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(stateStackView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            stateStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateStackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateStackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            stateIconView.widthAnchor.constraint(equalToConstant: 48),
            stateIconView.heightAnchor.constraint(equalToConstant: 48),
        ])

        Task { await loadDrafts(reset: true) }
    }

    override func updateUI() {
        applyThemeStyle()
        tableView.reloadData()
    }

    private func applyThemeStyle() {
        let theme = AppSettings.shared.themeStyle
        let pageBackground = theme.topicListBackgroundColor
        view.backgroundColor = pageBackground
        tableView.backgroundColor = pageBackground
        tableView.estimatedRowHeight = TopicListLayoutKind.current.usesChatSessionRows
            ? TopicListCellFactory.estimatedRowHeight
            : DraftCell.estimatedHeight
        tableView.showsVerticalScrollIndicator = !AppSettings.shared.hideScrollIndicators
        view.tintColor = theme.accentColor
        refreshControl.tintColor = theme.accentColor
        activityIndicator.color = theme.accentColor
        stateIconView.tintColor = theme.accentColor.withAlphaComponent(0.78)
        retryButton.tintColor = theme.accentColor
        stateLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 15, weight: .regular)
        )
    }

    private func loadDrafts(reset: Bool) async {
        if reset {
            guard !isLoading else { return }
            isLoading = true
            errorMessage = nil
        } else {
            guard hasMore, !isLoading, !isLoadingMore else { return }
            isLoadingMore = true
        }
        updateState()
        defer {
            if reset {
                isLoading = false
            } else {
                isLoadingMore = false
            }
            refreshControl.endRefreshing()
            updateState()
        }

        do {
            let offset = reset ? 0 : drafts.count
            let response = try await api.fetchDrafts(offset: offset, limit: 20)
            if reset {
                drafts = Self.uniqueDrafts(response.drafts)
            } else {
                let existingKeys = Set(drafts.map(\.draftKey))
                drafts.append(contentsOf: Self.uniqueDrafts(response.drafts).filter { !existingKeys.contains($0.draftKey) })
            }
            hasMore = response.hasMore
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            if reset && drafts.isEmpty {
                hasMore = false
            }
        }
        // Local drafts always refresh (even if server fetch fails).
        localDrafts = ComposerLocalDraftStore.listedDrafts(baseURL: api.baseURL)
    }

    private func updateState() {
        tableView.reloadData()
        let hasDrafts = !drafts.isEmpty || !localDrafts.isEmpty
        tableView.isHidden = !hasDrafts
        stateStackView.isHidden = hasDrafts || isLoading
        retryButton.isHidden = errorMessage == nil

        if (isLoading && !hasDrafts) || isOpeningDraft {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        tableView.isUserInteractionEnabled = !isOpeningDraft

        if let errorMessage, !hasDrafts {
            configureState(
                iconName: "exclamationmark.triangle",
                text: errorMessage
            )
        } else if !hasDrafts, !isLoading {
            configureState(
                iconName: "doc.text",
                text: String(
                    localized: "me.drafts.empty",
                    defaultValue: "没有本地或云端草稿\n在发帖/回帖时输入内容会自动保存"
                )
            )
        }

        if isLoadingMore {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = AppSettings.shared.themeStyle.accentColor
            spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 48)
            spinner.startAnimating()
            tableView.tableFooterView = spinner
        } else if errorMessage != nil && hasDrafts {
            let button = UIButton(type: .system)
            button.frame = CGRect(x: 0, y: 0, width: 0, height: 52)
            button.tintColor = AppSettings.shared.themeStyle.accentColor
            button.setTitle(
                String(localized: "me.topic_list.load_more_failed", defaultValue: "加载更多失败，点击重试"),
                for: .normal
            )
            button.addTarget(self, action: #selector(loadMoreRetryTapped), for: .touchUpInside)
            tableView.tableFooterView = button
        } else {
            tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        }
    }

    private func configureState(iconName: String, text: String) {
        stateIconView.image = UIImage(
            systemName: iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 42, weight: .regular)
        )
        stateLabel.text = text
    }

    private static func uniqueDrafts(_ drafts: [DiscourseDraft]) -> [DiscourseDraft] {
        var seen = Set<String>()
        return drafts.filter { seen.insert($0.draftKey).inserted }
    }

    @objc private func refreshPulled() {
        Task { await loadDrafts(reset: true) }
    }

    @objc private func retryTapped() {
        Task { await loadDrafts(reset: true) }
    }

    @objc private func loadMoreRetryTapped() {
        Task { await loadDrafts(reset: false) }
    }

    private func confirmDelete(_ draft: DiscourseDraft) {
        let alert = UIAlertController(
            title: String(localized: "me.drafts.delete.title", defaultValue: "删除草稿？"),
            message: String(localized: "me.drafts.delete.message", defaultValue: "删除后无法恢复。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "action.delete", defaultValue: "删除"), style: .destructive) { [weak self] _ in
            Task { await self?.deleteDraft(draft, showError: true) }
        })
        present(alert, animated: true)
    }

    private func deleteDraft(_ draft: DiscourseDraft, showError: Bool) async {
        do {
            try await api.deleteDraft(key: draft.draftKey, sequence: draft.sequence)
            drafts.removeAll { $0.draftKey == draft.draftKey }
            updateState()
        } catch {
            guard showError else { return }
            showErrorAlert(error.localizedDescription)
        }
    }

    private func open(_ draft: DiscourseDraft) {
        isOpeningDraft = true
        updateState()
        Task {
            defer {
                isOpeningDraft = false
                updateState()
            }
            do {
                switch draft.destination {
                case .newTopic:
                    try await presentNewTopicDraft(draft)
                case .topicReply(let topicId, let postNumber):
                    try await presentReplyDraft(draft, topicId: topicId, postNumber: postNumber)
                case .privateMessage(let recipient):
                    guard let recipient, !recipient.isEmpty else {
                        throw DraftOpenError.missingRecipient
                    }
                    presentPrivateMessageDraft(draft, recipient: recipient)
                case .unsupported:
                    presentUnsupportedDraft(draft)
                }
            } catch {
                showErrorAlert(error.localizedDescription)
            }
        }
    }

    private func presentNewTopicDraft(_ draft: DiscourseDraft) async throws {
        let siteCategories = (try? await api.fetchSiteCategories()) ?? []
        let categories: [DiscourseCategory]
        if !siteCategories.isEmpty {
            categories = siteCategories
        } else {
            let response = try await api.fetchCategories()
            categories = DiscourseCategory.normalizedTree(fromNested: response.categoryList.categories)
        }

        let composer = NewTopicComposerViewController(
            api: api,
            categories: categories,
            initialCategoryId: draft.data.categoryId,
            initialTitle: draft.data.title ?? draft.title ?? "",
            initialRaw: draft.data.reply ?? draft.excerpt ?? "",
            initialTags: draft.data.tags
        )
        composer.onTopicCreated = { [weak self] _ in
            Task { await self?.deleteDraft(draft, showError: false) }
        }
        let navigation = UINavigationController(rootViewController: composer)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
        }
        present(navigation, animated: true)
    }

    private func presentReplyDraft(
        _ draft: DiscourseDraft,
        topicId: Int,
        postNumber: Int?
    ) async throws {
        let detail = try await api.fetchTopic(id: topicId)
        var replyTarget = postNumber.flatMap { number in
            detail.postStream.posts.first { $0.postNumber == number }
        }

        if replyTarget == nil,
           let postNumber,
           let stream = detail.postStream.stream,
           stream.indices.contains(postNumber - 1) {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: [stream[postNumber - 1]])
            replyTarget = response.postStream.posts.first
        }

        if postNumber != nil, replyTarget == nil {
            throw DraftOpenError.missingReplyTarget
        }

        let composer = ReplyComposerViewController(
            api: api,
            topicId: topicId,
            replyToPost: replyTarget,
            baseURL: api.baseURL,
            initialText: draft.data.reply ?? draft.excerpt
        )
        composer.onPostCreated = { [weak self] in
            Task { await self?.deleteDraft(draft, showError: false) }
        }
        composer.modalPresentationStyle = .pageSheet
        if let sheet = composer.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        present(composer, animated: true)
    }

    private func presentPrivateMessageDraft(_ draft: DiscourseDraft, recipient: String) {
        let composer = PrivateMessageComposerViewController(
            api: api,
            recipient: recipient,
            initialTitle: draft.data.title ?? draft.title ?? "",
            initialRaw: draft.data.reply ?? draft.excerpt ?? ""
        )
        composer.onMessageSent = { [weak self] _ in
            Task { await self?.deleteDraft(draft, showError: false) }
        }
        let navigation = UINavigationController(rootViewController: composer)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
        }
        present(navigation, animated: true)
    }

    private func presentUnsupportedDraft(_ draft: DiscourseDraft) {
        let alert = UIAlertController(
            title: String(localized: "me.drafts.unsupported.title", defaultValue: "无法恢复这个草稿"),
            message: String(localized: "me.drafts.unsupported.message", defaultValue: "草稿类型无法识别，可以保留或删除。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "action.delete", defaultValue: "删除"), style: .destructive) { [weak self] _ in
            Task { await self?.deleteDraft(draft, showError: true) }
        })
        present(alert, animated: true)
    }

    private func confirmDeleteLocal(_ draft: ComposerLocalDraftStore.ListedDraft) {
        let alert = UIAlertController(
            title: String(localized: "me.drafts.delete.title", defaultValue: "删除草稿？"),
            message: String(localized: "me.drafts.delete.local_message", defaultValue: "仅删除本机草稿，云端副本不受影响。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "action.delete", defaultValue: "删除"), style: .destructive) { [weak self] _ in
            ComposerLocalDraftStore.removeListedDraft(draft)
            self?.localDrafts.removeAll { $0.id == draft.id }
            self?.updateState()
        })
        present(alert, animated: true)
    }

    private func openLocal(_ draft: ComposerLocalDraftStore.ListedDraft) {
        isOpeningDraft = true
        updateState()
        Task {
            defer {
                isOpeningDraft = false
                updateState()
            }
            do {
                switch draft.kind {
                case .newTopic:
                    try await presentLocalNewTopic(draft)
                case .reply:
                    guard let topicId = draft.topicId else {
                        throw DraftOpenError.missingReplyTarget
                    }
                    try await presentLocalReply(draft, topicId: topicId, postNumber: draft.replyToPostNumber)
                case .privateMessage:
                    guard let recipient = draft.recipient, !recipient.isEmpty else {
                        throw DraftOpenError.missingRecipient
                    }
                    presentLocalPrivateMessage(draft, recipient: recipient)
                }
            } catch {
                showErrorAlert(error.localizedDescription)
            }
        }
    }

    private func presentLocalNewTopic(_ draft: ComposerLocalDraftStore.ListedDraft) async throws {
        let siteCategories = (try? await api.fetchSiteCategories()) ?? []
        let categories: [DiscourseCategory]
        if !siteCategories.isEmpty {
            categories = siteCategories
        } else {
            let response = try await api.fetchCategories()
            categories = DiscourseCategory.normalizedTree(fromNested: response.categoryList.categories)
        }
        let composer = NewTopicComposerViewController(
            api: api,
            categories: categories,
            initialCategoryId: draft.categoryId,
            initialTitle: draft.rawTitle,
            initialRaw: draft.raw,
            initialTags: draft.tags
        )
        composer.onTopicCreated = { [weak self] _ in
            ComposerLocalDraftStore.removeListedDraft(draft)
            self?.localDrafts.removeAll { $0.id == draft.id }
            self?.updateState()
        }
        let navigation = UINavigationController(rootViewController: composer)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
        }
        present(navigation, animated: true)
    }

    private func presentLocalReply(
        _ draft: ComposerLocalDraftStore.ListedDraft,
        topicId: Int,
        postNumber: Int?
    ) async throws {
        let detail = try await api.fetchTopic(id: topicId)
        var replyTarget = postNumber.flatMap { number in
            detail.postStream.posts.first { $0.postNumber == number }
        }
        if replyTarget == nil,
           let postNumber,
           let stream = detail.postStream.stream,
           stream.indices.contains(postNumber - 1) {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: [stream[postNumber - 1]])
            replyTarget = response.postStream.posts.first
        }
        let composer = ReplyComposerViewController(
            api: api,
            topicId: topicId,
            replyToPost: replyTarget,
            baseURL: api.baseURL,
            initialText: draft.raw
        )
        composer.onPostCreated = { [weak self] in
            ComposerLocalDraftStore.removeListedDraft(draft)
            self?.localDrafts.removeAll { $0.id == draft.id }
            self?.updateState()
        }
        composer.modalPresentationStyle = .pageSheet
        if let sheet = composer.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        present(composer, animated: true)
    }

    private func presentLocalPrivateMessage(_ draft: ComposerLocalDraftStore.ListedDraft, recipient: String) {
        let composer = PrivateMessageComposerViewController(
            api: api,
            recipient: recipient,
            initialTitle: draft.rawTitle,
            initialRaw: draft.raw
        )
        composer.onMessageSent = { [weak self] _ in
            ComposerLocalDraftStore.removeListedDraft(draft)
            self?.localDrafts.removeAll { $0.id == draft.id }
            self?.updateState()
        }
        let navigation = UINavigationController(rootViewController: composer)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
        }
        present(navigation, animated: true)
    }

    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }

    // MARK: - Presentation helpers

    private func displayTitle(for draft: DiscourseDraft) -> String {
        if let title = draft.data.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return kindTitle(for: draft.destination)
    }

    private func displayExcerpt(for draft: DiscourseDraft) -> String? {
        let raw = draft.data.reply ?? draft.excerpt ?? ""
        let excerpt = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return excerpt.isEmpty ? nil : excerpt
    }

    private func displaySubtitle(for draft: DiscourseDraft) -> String {
        let time = UserProfileFormatting.relativeDate(draft.updatedAt)
        if let excerpt = displayExcerpt(for: draft) {
            return "\(String(excerpt.prefix(120))) · \(time)"
        }
        return time
    }

    private func kindTitle(for destination: DiscourseDraftDestination) -> String {
        switch destination {
        case .newTopic:
            return String(localized: "me.drafts.new_topic", defaultValue: "新主题草稿")
        case .topicReply:
            return String(localized: "me.drafts.reply", defaultValue: "回复草稿")
        case .privateMessage:
            return String(localized: "me.drafts.private_message", defaultValue: "私信草稿")
        case .unsupported:
            return String(localized: "me.drafts.unknown", defaultValue: "未识别草稿")
        }
    }

    private func kindTitle(forLocal kind: ComposerLocalDraftStore.ListedKind) -> String {
        switch kind {
        case .newTopic:
            return String(localized: "me.drafts.new_topic", defaultValue: "新主题草稿")
        case .reply:
            return String(localized: "me.drafts.reply", defaultValue: "回复草稿")
        case .privateMessage:
            return String(localized: "me.drafts.private_message", defaultValue: "私信草稿")
        }
    }

    private func symbolName(for destination: DiscourseDraftDestination) -> String {
        switch destination {
        case .newTopic: return "square.and.pencil"
        case .topicReply: return "arrowshape.turn.up.left.fill"
        case .privateMessage: return "envelope.fill"
        case .unsupported: return "questionmark.folder.fill"
        }
    }

    private func symbolName(forLocal kind: ComposerLocalDraftStore.ListedKind) -> String {
        switch kind {
        case .newTopic: return "iphone"
        case .reply: return "arrowshape.turn.up.left"
        case .privateMessage: return "envelope"
        }
    }

    private func tintColor(for destination: DiscourseDraftDestination) -> UIColor {
        let accent = AppSettings.shared.themeStyle.accentColor
        switch destination {
        case .newTopic: return accent
        case .topicReply: return .systemGreen
        case .privateMessage: return .systemIndigo
        case .unsupported: return .systemOrange
        }
    }

    private func tintColor(forLocal kind: ComposerLocalDraftStore.ListedKind) -> UIColor {
        let accent = AppSettings.shared.themeStyle.accentColor
        switch kind {
        case .newTopic: return accent
        case .reply: return .systemGreen
        case .privateMessage: return .systemIndigo
        }
    }

    private func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func sessionItem(forLocal draft: ComposerLocalDraftStore.ListedDraft) -> TopicListSessionItem {
        let time = UserProfileFormatting.relativeDate(isoString(from: draft.updatedAt))
        let preview = draft.preview
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TopicListSessionItem(
            title: draft.title ?? String(localized: "me.drafts.local", defaultValue: "本地草稿"),
            subtitle: preview.isEmpty
                ? kindTitle(forLocal: draft.kind)
                : "\(kindTitle(forLocal: draft.kind)) · \(String(preview.prefix(100)))",
            timeText: time,
            isEmphasized: false,
            badgeText: String(localized: "me.drafts.badge.local", defaultValue: "本机"),
            baseURL: api.baseURL
        )
    }

    private func sessionItem(for draft: DiscourseDraft) -> TopicListSessionItem {
        TopicListSessionItem(
            title: displayTitle(for: draft),
            subtitle: displaySubtitle(for: draft),
            timeText: UserProfileFormatting.relativeDate(draft.updatedAt),
            isEmphasized: false,
            badgeText: kindTitle(for: draft.destination),
            baseURL: api.baseURL
        )
    }
}

extension DraftsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        DraftsListSection.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch DraftsListSection(rawValue: section) {
        case .local: return localDrafts.count
        case .cloud: return drafts.count
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch DraftsListSection(rawValue: section) {
        case .local:
            return localDrafts.isEmpty
                ? nil
                : String(localized: "me.drafts.section.local", defaultValue: "本机草稿")
        case .cloud:
            // Keep section header only when both sections have content, or cloud alone.
            if drafts.isEmpty { return nil }
            return String(localized: "me.drafts.section.cloud", defaultValue: "云端草稿（与网页 / FluxDo 同步）")
        case .none:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        let theme = AppSettings.shared.themeStyle
        header.textLabel?.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 13, weight: .semibold)
        )
        header.textLabel?.textColor = .secondaryLabel
        header.contentConfiguration = nil
        header.backgroundConfiguration = UIBackgroundConfiguration.clear()
        header.tintColor = theme.topicListBackgroundColor
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let layout = TopicListLayoutKind.current
        switch DraftsListSection(rawValue: indexPath.section) {
        case .local:
            let draft = localDrafts[indexPath.row]
            if layout.usesChatSessionRows {
                return TopicListCellFactory.makeSessionCell(
                    tableView: tableView,
                    indexPath: indexPath,
                    item: sessionItem(forLocal: draft),
                    layout: layout
                )
            }
            return makeCardCell(
                tableView: tableView,
                indexPath: indexPath,
                title: draft.title ?? String(localized: "me.drafts.local", defaultValue: "本地草稿"),
                excerpt: draft.preview,
                timeText: UserProfileFormatting.relativeDate(isoString(from: draft.updatedAt)),
                kindTitle: kindTitle(forLocal: draft.kind),
                symbolName: symbolName(forLocal: draft.kind),
                accent: tintColor(forLocal: draft.kind)
            )
        case .cloud:
            let draft = drafts[indexPath.row]
            if layout.usesChatSessionRows {
                return TopicListCellFactory.makeSessionCell(
                    tableView: tableView,
                    indexPath: indexPath,
                    item: sessionItem(for: draft),
                    layout: layout
                )
            }
            return makeCardCell(
                tableView: tableView,
                indexPath: indexPath,
                title: displayTitle(for: draft),
                excerpt: displayExcerpt(for: draft),
                timeText: UserProfileFormatting.relativeDate(draft.updatedAt),
                kindTitle: kindTitle(for: draft.destination),
                symbolName: symbolName(for: draft.destination),
                accent: tintColor(for: draft.destination)
            )
        case .none:
            return UITableViewCell()
        }
    }

    private func makeCardCell(
        tableView: UITableView,
        indexPath: IndexPath,
        title: String,
        excerpt: String?,
        timeText: String?,
        kindTitle: String,
        symbolName: String,
        accent: UIColor
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: DraftCell.reuseIdentifier,
            for: indexPath
        ) as? DraftCell else {
            return UITableViewCell()
        }
        cell.configure(
            title: title,
            excerpt: excerpt,
            timeText: timeText,
            kindTitle: kindTitle,
            symbolName: symbolName,
            accent: accent
        )
        return cell
    }
}

extension DraftsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch DraftsListSection(rawValue: indexPath.section) {
        case .local:
            openLocal(localDrafts[indexPath.row])
        case .cloud:
            open(drafts[indexPath.row])
        case .none:
            break
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "action.delete", defaultValue: "删除")
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            switch DraftsListSection(rawValue: indexPath.section) {
            case .local:
                self.confirmDeleteLocal(self.localDrafts[indexPath.row])
            case .cloud:
                self.confirmDelete(self.drafts[indexPath.row])
            case .none:
                break
            }
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.section == DraftsListSection.cloud.rawValue else { return }
        guard indexPath.row >= drafts.count - 4 else { return }
        Task { await loadDrafts(reset: false) }
    }
}

private enum DraftOpenError: LocalizedError {
    case missingRecipient
    case missingReplyTarget

    var errorDescription: String? {
        switch self {
        case .missingRecipient:
            return String(localized: "me.drafts.missing_recipient", defaultValue: "草稿缺少私信收件人。")
        case .missingReplyTarget:
            return String(localized: "me.drafts.missing_reply_target", defaultValue: "找不到草稿对应的回复楼层。")
        }
    }
}
