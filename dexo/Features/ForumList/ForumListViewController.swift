import UIKit

final class ForumListViewController: ObservableViewController {
    private let viewModel = ForumListViewModel()
    private let settings = AppSettings.shared
    private var hasAttemptedAutoOpen = false

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(ForumListCell.self, forCellReuseIdentifier: ForumListCell.reuseIdentifier)
        tv.delegate = self
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int64> = {
        UITableViewDiffableDataSource<Int, Int64>(tableView: tableView) { [weak self] tableView, indexPath, forumId in
            guard let self,
                  let cell = tableView.dequeueReusableCell(withIdentifier: ForumListCell.reuseIdentifier, for: indexPath) as? ForumListCell,
                  let forum = self.viewModel.forums.first(where: { $0.id == forumId }) else {
                return UITableViewCell()
            }
            cell.configure(with: forum)
            return cell
        }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "tab.forums")
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        viewModel.loadForums()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAttemptedAutoOpen else { return }
        hasAttemptedAutoOpen = true
        guard settings.autoOpenLastForum,
              let lastId = settings.lastOpenedForumId,
              let forum = viewModel.forums.first(where: { $0.id == lastId }),
              let window = view.window else { return }
        ForumOverlayManager.shared.present(forum: forum, in: window)
    }

    override func updateUI() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int64>()
        snapshot.appendSections([0])
        let ids = viewModel.forums.compactMap(\.id)
        snapshot.appendItems(ids, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

}

// MARK: - UITableViewDelegate

extension ForumListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < viewModel.forums.count,
              let window = view.window else { return }
        let forum = viewModel.forums[indexPath.row]
        settings.lastOpenedForumId = forum.id
        ForumOverlayManager.shared.present(forum: forum, in: window)
        showAutoOpenPromptIfNeeded()
    }

    private func showAutoOpenPromptIfNeeded() {
        guard !settings.hasShownAutoOpenPrompt else { return }
        settings.hasShownAutoOpenPrompt = true
        let alert = UIAlertController(
            title: String(localized: "forum.auto_open.title"),
            message: String(localized: "forum.auto_open.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.enable"), style: .default) { [weak self] _ in
            self?.settings.autoOpenLastForum = true
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.no_thanks"), style: .cancel))
        if let containerVC = ForumOverlayManager.shared.currentContainer {
            containerVC.present(alert, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        nil
    }
}
