import UIKit

final class UserBadgesViewController: UIViewController {
    private let api: DiscourseAPI
    private let username: String
    private var sections: [(DiscourseBadge.BadgeType, [DiscourseUserBadge])] = []
    private var isLoading = false
    private var errorMessage: String?

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 76
        return table
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        return control
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
        title = String(localized: "me.badges")
        view.backgroundColor = .systemGroupedBackground
        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        view.addSubview(stateLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        loadBadges()
    }

    private func loadBadges() {
        isLoading = true
        errorMessage = nil
        updateState()
        Task {
            do {
                let response = try await api.fetchUserBadges(username: username)
                let grouped: [DiscourseBadge.BadgeType: [DiscourseUserBadge]] = Dictionary(grouping: response.userBadges) { badge in
                    badge.badge?.type ?? DiscourseBadge.BadgeType.bronze
                }
                let orderedTypes: [DiscourseBadge.BadgeType] = [.gold, .silver, .bronze]
                sections = orderedTypes.compactMap { type in
                    guard let badges = grouped[type], !badges.isEmpty else { return nil }
                    return (type, badges.sorted { ($0.badge?.name ?? "") < ($1.badge?.name ?? "") })
                }
            } catch {
                errorMessage = error.localizedDescription
                sections = []
            }
            isLoading = false
            refreshControl.endRefreshing()
            tableView.reloadData()
            updateState()
        }
    }

    private func updateState() {
        tableView.isHidden = sections.isEmpty
        stateLabel.isHidden = !sections.isEmpty
        if isLoading {
            stateLabel.text = String(localized: "badges.loading")
        } else if let errorMessage {
            stateLabel.text = errorMessage
        } else {
            stateLabel.text = String(localized: "badges.empty")
        }
    }

    @objc private func refreshPulled() {
        loadBadges()
    }
}

extension UserBadgesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].1.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let section = sections[section]
        return "\(section.0.title) · \(section.1.count)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let badge = sections[indexPath.section].1[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let type = badge.badge?.type ?? .bronze
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: "medal.fill")
        content.imageProperties.tintColor = type.color
        content.text = badge.badge?.name ?? String(localized: "badges.unknown")
        content.secondaryText = badge.topicTitle ?? badge.badge?.description
        content.secondaryTextProperties.color = .secondaryLabel
        content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.contentConfiguration = content
        if badge.count > 1 {
            let label = UILabel()
            label.text = "×\(badge.count)"
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            label.textColor = type.color
            cell.accessoryView = label
        } else if badge.topicId != nil {
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
}

extension UserBadgesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicId = sections[indexPath.section].1[indexPath.row].topicId else { return }
        let detail = TopicDetailViewController(api: api, topicId: topicId)
        navigationController?.pushViewController(detail, animated: true)
    }
}
