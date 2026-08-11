import UIKit

/// FluxDo「追觅」: watch a user's activity stream (posts / replies / likes).
final class UserWatchFeedViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let username: String
    private var rows: [DiscourseUserAction] = []
    private var offset = 0
    private var isLoading = false
    private var canLoadMore = true
    private var errorMessage: String?

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "watch.row")
        table.refreshControl = UIRefreshControl()
        table.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        return table
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(
            format: String(localized: "user.watch.title", defaultValue: "追觅 @%@"),
            username
        )
        view.backgroundColor = .systemBackground
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
        Task { await load(reset: true) }
    }

    override func updateUI() {
        tableView.reloadData()
        tableView.refreshControl?.endRefreshing()
        emptyLabel.isHidden = isLoading || !rows.isEmpty
        emptyLabel.text = errorMessage
            ?? String(localized: "user.watch.empty", defaultValue: "暂无动态")
    }

    @objc private func refresh() {
        Task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        if reset {
            offset = 0
            canLoadMore = true
            errorMessage = nil
        }
        updateUI()
        do {
            // filter 4,5 = topics + replies (same as profile activity).
            let page = try await api.fetchUserActions(username: username, filter: "4,5", offset: offset)
            if reset {
                rows = page
            } else {
                rows.append(contentsOf: page)
            }
            offset = rows.count
            canLoadMore = !page.isEmpty
        } catch {
            errorMessage = error.localizedDescription
            if reset { rows = [] }
        }
        isLoading = false
        updateUI()
    }
}

extension UserWatchFeedViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "watch.row", for: indexPath)
        let action = rows[indexPath.row]
        var content = cell.defaultContentConfiguration()
        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.text = title.isEmpty ? (action.excerpt ?? "#\(action.topicId)") : title
        content.secondaryText = [
            (action.actingAt ?? action.createdAt).map(UserProfileFormatting.relativeDate),
            action.excerpt,
        ].compactMap { $0 }.joined(separator: " · ")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let action = rows[indexPath.row]
        guard action.topicId > 0 else { return }
        navigationController?.pushViewController(
            TopicDetailFactory.make(
                api: api,
                topicId: action.topicId,
                initialFloor: action.postNumber,
                preferNested: AppSettings.shared.nestedReplyViewEnabled
            ),
            animated: true
        )
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard canLoadMore, !isLoading, indexPath.row >= rows.count - 3 else { return }
        Task { await load(reset: false) }
    }
}
