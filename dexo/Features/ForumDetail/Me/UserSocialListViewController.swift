import UIKit

final class UserSocialListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    enum Mode: Equatable {
        case followers
        case following

        var title: String {
            switch self {
            case .followers: return String(localized: "user.profile.followers")
            case .following: return String(localized: "user.profile.following")
            }
        }
    }

    private let api: DiscourseAPI
    private let username: String
    private let mode: Mode
    private var users: [DiscourseFollowUser] = []
    private var isLoading = false
    private var errorMessage: String?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let stateLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let refreshControl = UIRefreshControl()

    init(api: DiscourseAPI, username: String, mode: Mode) {
        self.api = api
        self.username = username
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        title = mode.title
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppSettings.shared.themeStyle.contentBackgroundColor
        setupUI()
        load()
    }

    private func setupUI() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.refreshControl = refreshControl
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SocialUserCell")
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)

        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.textAlignment = .center
        stateLabel.textColor = .secondaryLabel
        stateLabel.numberOfLines = 0

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(stateLabel)
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        updateState()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch mode {
                case .followers:
                    users = try await api.fetchFollowers(username: username)
                case .following:
                    users = try await api.fetchFollowing(username: username)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            refreshControl.endRefreshing()
            tableView.reloadData()
            updateState()
        }
    }

    private func updateState() {
        isLoading ? loadingIndicator.startAnimating() : loadingIndicator.stopAnimating()
        tableView.isHidden = users.isEmpty
        stateLabel.isHidden = !users.isEmpty || isLoading
        stateLabel.text = errorMessage ?? String(localized: "search.no_results")
    }

    @objc private func refreshPulled() {
        load()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        users.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SocialUserCell", for: indexPath)
        let user = users[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = user.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? user.name
            : user.username
        content.secondaryText = "@\(user.username)"
        content.image = UIImage(systemName: "person.crop.circle.fill")
        content.imageProperties.tintColor = AppSettings.shared.themeStyle.accentColor
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = users[indexPath.row]
        navigationController?.pushViewController(
            UserProfileViewController(api: api, username: user.username),
            animated: true
        )
    }
}
