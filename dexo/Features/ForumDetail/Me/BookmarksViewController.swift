import UIKit

final class BookmarksViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: BookmarksViewModel
    private weak var authGate: AuthGating?

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(BookmarkCell.self, forCellReuseIdentifier: BookmarkCell.reuseIdentifier)
        tv.delegate = self
        tv.dataSource = self
        tv.separatorStyle = .none
        tv.backgroundColor = .clear
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = BookmarkCell.estimatedHeight
        tv.showsVerticalScrollIndicator = false
        return tv
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
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
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let loginButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "me.login")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    private let retryButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = String(localized: "action.retry")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    private lazy var stateStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [stateIconView, stateLabel, loginButton, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        return rc
    }()

    init(api: DiscourseAPI, username: String, authGate: AuthGating? = nil) {
        self.api = api
        self.viewModel = BookmarksViewModel(api: api, username: username)
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    init(api: DiscourseAPI, authGate: AuthGating?) {
        self.api = api
        self.viewModel = BookmarksViewModel(api: api, username: authGate?.currentUsername())
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.bookmarks")
        applyThemeStyle()

        tableView.refreshControl = refreshControl

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

            stateIconView.widthAnchor.constraint(equalToConstant: 58),
            stateIconView.heightAnchor.constraint(equalToConstant: 58),
        ])

        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        Task {
            await loadBookmarks()
        }
    }

    override func updateUI() {
        refreshControl.endRefreshing()
        applyThemeStyle()

        let hasBookmarks = !viewModel.bookmarks.isEmpty
        if viewModel.isLoading && !hasBookmarks {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        tableView.isHidden = !hasBookmarks
        stateStackView.isHidden = hasBookmarks || viewModel.isLoading

        if viewModel.requiresLogin {
            configureState(
                iconName: "lock.circle",
                text: viewModel.errorMessage ?? String(localized: "login.required.message"),
                showLogin: authGate != nil,
                showRetry: authGate == nil
            )
        } else if let errorMessage = viewModel.errorMessage, !hasBookmarks {
            configureState(
                iconName: "exclamationmark.triangle",
                text: errorMessage,
                showLogin: false,
                showRetry: true
            )
        } else if !hasBookmarks, !viewModel.isLoading {
            configureState(
                iconName: "bookmark",
                text: String(localized: "me.bookmarks.empty"),
                showLogin: false,
                showRetry: false
            )
        }

        tableView.reloadData()
    }

    private func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        let pageBackground = themeStyle.topicListBackgroundColor
        view.backgroundColor = pageBackground
        tableView.backgroundColor = pageBackground
        view.tintColor = themeStyle.accentColor
        refreshControl.tintColor = themeStyle.accentColor
        activityIndicator.color = themeStyle.accentColor
        stateIconView.tintColor = themeStyle.accentColor.withAlphaComponent(0.78)
        loginButton.tintColor = themeStyle.accentColor
        retryButton.tintColor = themeStyle.accentColor
    }

    private func configureState(iconName: String, text: String, showLogin: Bool, showRetry: Bool) {
        stateIconView.image = UIImage(
            systemName: iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 50, weight: .regular)
        )
        stateLabel.text = text
        loginButton.isHidden = !showLogin
        retryButton.isHidden = !showRetry
    }

    private func refreshUsernameFromAuthGate() {
        viewModel.updateUsername(authGate?.currentUsername())
    }

    private func loadBookmarks() async {
        if authGate != nil {
            refreshUsernameFromAuthGate()
        }
        await viewModel.loadBookmarks()
    }

    @objc private func pullToRefresh() {
        Task {
            if authGate != nil {
                refreshUsernameFromAuthGate()
            }
            await viewModel.reload()
        }
    }

    @objc private func retryTapped() {
        Task {
            await loadBookmarks()
        }
    }

    @objc private func loginTapped() {
        authGate?.requireAuth(then: { [weak self] in
            guard let self else { return }
            Task {
                await self.loadBookmarks()
            }
        })
    }
}

// MARK: - UITableViewDataSource

extension BookmarksViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.bookmarks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: BookmarkCell.reuseIdentifier, for: indexPath) as? BookmarkCell else {
            return UITableViewCell()
        }
        let bookmark = viewModel.bookmarks[indexPath.row]
        cell.configure(with: bookmark, baseURL: api.baseURL)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension BookmarksViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let bookmark = viewModel.bookmarks[indexPath.row]
        if let topicId = bookmark.topicId {
            let detailVC = TopicDetailViewController(api: api, topicId: topicId)
            navigationController?.pushViewController(detailVC, animated: true)
        }
    }
}
