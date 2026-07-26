import UIKit

final class PendingPostsViewController: UITableViewController {
    private let api: DiscourseAPI
    private let username: String
    private var items: [DiscoursePendingPost] = []
    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        l.text = String(localized: "pending.empty", defaultValue: "暂无待审内容")
        return l
    }()

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "pending.title", defaultValue: "待审内容")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        reload()
    }

    @objc private func reload() {
        Task {
            do {
                let list = try await api.fetchPendingPosts(username: username)
                await MainActor.run {
                    self.items = list
                    self.tableView.backgroundView = list.isEmpty ? emptyLabel : nil
                    self.tableView.reloadData()
                    self.refreshControl?.endRefreshing()
                }
            } catch {
                await MainActor.run {
                    self.refreshControl?.endRefreshing()
                    let alert = UIAlertController(title: String(localized: "common.error", defaultValue: "错误"), message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "好"), style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = items[indexPath.row]
        var c = cell.defaultContentConfiguration()
        c.text = item.title?.isEmpty == false ? item.title : String(localized: "pending.untitled", defaultValue: "待审内容")
        let kind = item.isNewTopic
            ? String(localized: "pending.new_topic", defaultValue: "新主题")
            : String(localized: "pending.reply", defaultValue: "回复")
        let preview = item.raw.replacingOccurrences(of: "\n", with: " ")
        c.secondaryText = "\(kind) · \(String(preview.prefix(80)))"
        c.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = c
        cell.accessoryType = item.topicId == nil ? .none : .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        if let topicId = item.topicId {
            let detail = TopicDetailViewController(api: api, topicId: topicId)
            navigationController?.pushViewController(detail, animated: true)
        } else {
            let alert = UIAlertController(
                title: item.title ?? String(localized: "pending.untitled", defaultValue: "待审内容"),
                message: item.raw,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "好"), style: .default))
            present(alert, animated: true)
        }
    }
}
