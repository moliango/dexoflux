import UIKit

final class DraftsViewController: UIViewController {
    private let api: DiscourseAPI
    private var drafts: [DiscourseDraft] = []
    private var hasMore = false
    private var isLoading = false
    private var isLoadingMore = false
    private var isOpeningDraft = false
    private var errorMessage: String?

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 82
        tableView.showsVerticalScrollIndicator = false
        return tableView
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
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
        let stack = UIStackView(arrangedSubviews: [stateLabel, retryButton])
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
        title = String(localized: "me.drafts", defaultValue: "草稿")
        view.backgroundColor = .systemGroupedBackground
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
        ])

        Task { await loadDrafts(reset: true) }
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
    }

    private func updateState() {
        tableView.reloadData()
        let hasDrafts = !drafts.isEmpty
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
            stateLabel.text = errorMessage
        } else if !hasDrafts, !isLoading {
            stateLabel.text = String(localized: "me.drafts.empty", defaultValue: "没有保存的草稿")
        }

        if isLoadingMore {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 48)
            spinner.startAnimating()
            tableView.tableFooterView = spinner
        } else if errorMessage != nil && hasDrafts {
            let button = UIButton(type: .system)
            button.frame = CGRect(x: 0, y: 0, width: 0, height: 52)
            button.setTitle(String(localized: "me.topic_list.load_more_failed", defaultValue: "加载更多失败，点击重试"), for: .normal)
            button.addTarget(self, action: #selector(loadMoreRetryTapped), for: .touchUpInside)
            tableView.tableFooterView = button
        } else {
            tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        }
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

    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }
}

extension DraftsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        drafts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let draft = drafts[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: symbolName(for: draft.destination))
        content.imageProperties.tintColor = tintColor(for: draft.destination)
        content.text = displayTitle(for: draft)
        content.secondaryText = displaySubtitle(for: draft)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func displayTitle(for draft: DiscourseDraft) -> String {
        if let title = draft.data.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        switch draft.destination {
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

    private func displaySubtitle(for draft: DiscourseDraft) -> String {
        let raw = draft.data.reply ?? draft.excerpt ?? ""
        let excerpt = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let time = UserProfileFormatting.relativeDate(draft.updatedAt)
        if excerpt.isEmpty {
            return time
        }
        return "\(String(excerpt.prefix(120))) · \(time)"
    }

    private func symbolName(for destination: DiscourseDraftDestination) -> String {
        switch destination {
        case .newTopic: return "square.and.pencil"
        case .topicReply: return "arrowshape.turn.up.left.fill"
        case .privateMessage: return "envelope.fill"
        case .unsupported: return "questionmark.folder.fill"
        }
    }

    private func tintColor(for destination: DiscourseDraftDestination) -> UIColor {
        switch destination {
        case .newTopic: return .systemBlue
        case .topicReply: return .systemGreen
        case .privateMessage: return .systemIndigo
        case .unsupported: return .systemOrange
        }
    }
}

extension DraftsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(drafts[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let draft = drafts[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: String(localized: "action.delete", defaultValue: "删除")) { [weak self] _, _, completion in
            self?.confirmDelete(draft)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
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
