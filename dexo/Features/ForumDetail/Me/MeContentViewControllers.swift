import UIKit

@MainActor
final class PagedTopicListViewModel: DexoObservableObject {
    typealias Loader = (_ page: Int) async throws -> DiscourseTopicList

    private(set) var topics: [DiscourseTopicList.Topic] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = false
    private(set) var errorMessage: String?
    private(set) var loadMoreErrorMessage: String?

    private let loader: Loader
    private var currentPage = 0
    private var usersById: [Int: DiscourseTopicList.User] = [:]
    private var categoryIndex = DiscourseCategoryIndex()

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        loadMoreErrorMessage = nil
        notifyChanged()
        defer {
            isLoading = false
            notifyChanged()
        }

        do {
            let response = try await loader(0)
            topics = Self.uniqueTopics(response.topicList.topics)
            currentPage = 0
            canLoadMore = response.topicList.moreTopicsUrl != nil
            usersById.removeAll()
            categoryIndex.removeAll()
            index(response)
        } catch {
            errorMessage = error.localizedDescription
            if topics.isEmpty {
                canLoadMore = false
            }
        }
    }

    func loadMore() async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreErrorMessage = nil
        notifyChanged()
        defer {
            isLoadingMore = false
            notifyChanged()
        }

        let nextPage = currentPage + 1
        do {
            let response = try await loader(nextPage)
            let existingIds = Set(topics.map(\.id))
            topics.append(contentsOf: Self.uniqueTopics(response.topicList.topics).filter { !existingIds.contains($0.id) })
            currentPage = nextPage
            canLoadMore = response.topicList.moreTopicsUrl != nil
            index(response)
        } catch {
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    func avatarURL(for topic: DiscourseTopicList.Topic, baseURL: String) -> URL? {
        guard let poster = topic.posters?.first,
              let template = usersById[poster.userId]?.avatarTemplate else {
            return nil
        }
        return AvatarImageLoader.url(from: template, baseURL: baseURL, size: 96)
    }

    func category(for topic: DiscourseTopicList.Topic) -> DiscourseCategory? {
        guard let categoryId = topic.categoryId else { return nil }
        return categoryIndex[categoryId]
    }

    func categoryDisplayName(for category: DiscourseCategory?) -> String? {
        guard let category else { return nil }
        let parent = category.parentCategoryId.flatMap { categoryIndex[$0] }
        return category.displayName(parent: parent)
    }

    private func index(_ response: DiscourseTopicList) {
        response.users?.forEach { usersById[$0.id] = $0 }
        categoryIndex.merge(response.categories, source: .topicList)
    }

    private static func uniqueTopics(_ topics: [DiscourseTopicList.Topic]) -> [DiscourseTopicList.Topic] {
        var seen = Set<Int>()
        return topics.filter { seen.insert($0.id).inserted }
    }
}

final class PagedTopicListViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: PagedTopicListViewModel
    private let emptyMessage: String
    private let searchQuery: String?
    private let fixedSearchQualifier: String?

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(TopicCell.self, forCellReuseIdentifier: TopicCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = TopicCell.estimatedHeight
        tableView.showsVerticalScrollIndicator = false
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
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .tertiaryLabel
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

    private lazy var loadingFooter: UIView = {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 52))
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        footer.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        return footer
    }()

    private lazy var loadMoreErrorFooter: UIView = {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 68))
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "me.topic_list.load_more_failed", defaultValue: "加载更多失败，点击重试")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(String(localized: "action.retry"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.addTarget(self, action: #selector(loadMoreRetryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        footer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: footer.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: footer.trailingAnchor, constant: -20),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        return footer
    }()

    private let emptyFooter = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))

    init(
        api: DiscourseAPI,
        title: String,
        emptyMessage: String,
        searchQuery: String? = nil,
        fixedSearchQualifier: String? = nil,
        loader: @escaping PagedTopicListViewModel.Loader
    ) {
        self.api = api
        self.viewModel = PagedTopicListViewModel(loader: loader)
        self.emptyMessage = emptyMessage
        self.searchQuery = searchQuery
        self.fixedSearchQualifier = fixedSearchQualifier
        super.init(nibName: nil, bundle: nil)
        self.title = title
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyThemeStyle()
        tableView.refreshControl = refreshControl
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        if searchQuery != nil || fixedSearchQualifier != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .search,
                target: self,
                action: #selector(searchTapped)
            )
            navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "search.title")
        }

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
            stateIconView.widthAnchor.constraint(equalToConstant: 54),
            stateIconView.heightAnchor.constraint(equalToConstant: 54),
        ])

        Task { await viewModel.refresh() }
    }

    override func updateUI() {
        applyThemeStyle()
        refreshControl.endRefreshing()
        tableView.reloadData()

        let hasTopics = !viewModel.topics.isEmpty
        if viewModel.isLoading && !hasTopics {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        tableView.isHidden = !hasTopics
        stateStackView.isHidden = hasTopics || viewModel.isLoading
        retryButton.isHidden = viewModel.errorMessage == nil

        if let errorMessage = viewModel.errorMessage, !hasTopics {
            stateIconView.image = UIImage(systemName: "exclamationmark.triangle")
            stateLabel.text = errorMessage
        } else if !hasTopics, !viewModel.isLoading {
            stateIconView.image = UIImage(systemName: "text.page")
            stateLabel.text = emptyMessage
        }

        if viewModel.isLoadingMore {
            tableView.tableFooterView = loadingFooter
        } else if viewModel.loadMoreErrorMessage != nil || (viewModel.errorMessage != nil && hasTopics) {
            tableView.tableFooterView = loadMoreErrorFooter
        } else {
            tableView.tableFooterView = emptyFooter
        }
    }

    private func applyThemeStyle() {
        let theme = AppSettings.shared.themeStyle
        view.backgroundColor = theme.topicListBackgroundColor
        tableView.backgroundColor = theme.topicListBackgroundColor
        activityIndicator.color = theme.accentColor
        refreshControl.tintColor = theme.accentColor
        stateIconView.tintColor = theme.accentColor.withAlphaComponent(0.75)
        retryButton.tintColor = theme.accentColor
    }

    @objc private func refreshPulled() {
        Task { await viewModel.refresh() }
    }

    @objc private func retryTapped() {
        Task { await viewModel.refresh() }
    }

    @objc private func loadMoreRetryTapped() {
        Task {
            if viewModel.errorMessage != nil {
                await viewModel.refresh()
            } else {
                await viewModel.loadMore()
            }
        }
    }

    @objc private func searchTapped() {
        guard searchQuery != nil || fixedSearchQualifier != nil else { return }
        let search = SearchViewController(
            api: api,
            initialQuery: searchQuery,
            fixedQueryQualifier: fixedSearchQualifier
        )
        navigationController?.pushViewController(search, animated: true)
    }

    private static func color(fromHex hex: String) -> UIColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension PagedTopicListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.topics.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: TopicCell.reuseIdentifier,
            for: indexPath
        ) as? TopicCell else {
            return UITableViewCell()
        }

        let topic = viewModel.topics[indexPath.row]
        let category = viewModel.category(for: topic)
        cell.configure(
            with: topic,
            avatarURL: viewModel.avatarURL(for: topic, baseURL: api.baseURL),
            categoryName: viewModel.categoryDisplayName(for: category),
            categoryColor: category.flatMap { Self.color(fromHex: $0.color) },
            tags: topic.tags ?? []
        )
        return cell
    }
}

extension PagedTopicListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let topic = viewModel.topics[indexPath.row]
        navigationController?.pushViewController(
            TopicDetailViewController(api: api, topicId: topic.id),
            animated: true
        )
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= viewModel.topics.count - 5 else { return }
        Task { await viewModel.loadMore() }
    }
}
