import UIKit

final class UserProfileContentView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onSelectRow: ((UserProfileContentRow) -> Void)?
    var onRefresh: (() -> Void)?
    var onLoadMore: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let refreshControl = UIRefreshControl()
    private var rows: [UserProfileContentRow] = []
    private var isLoadingMore = false
    private var loadMoreErrorMessage: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(viewModel: UserProfileContentViewModel) {
        rows = viewModel.rows
        isLoadingMore = viewModel.isLoadingMore
        loadMoreErrorMessage = viewModel.loadMoreErrorMessage
        refreshControl.endRefreshing()

        if viewModel.isLoading {
            loadingIndicator.startAnimating()
            stateLabel.isHidden = true
        } else {
            loadingIndicator.stopAnimating()
            stateLabel.isHidden = !rows.isEmpty
            stateLabel.text = viewModel.errorMessage
                ?? String(localized: "search.no_results")
        }
        tableView.reloadData()
        updateFooter()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 18, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.dataSource = self
        tableView.delegate = self
        tableView.refreshControl = refreshControl
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProfileContentCell")
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)

        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.textAlignment = .center
        stateLabel.textColor = .secondaryLabel
        stateLabel.numberOfLines = 0
        stateLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 13,
            weight: .medium,
            fallback: .systemFont(ofSize: 13, weight: .medium)
        )

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tableView)
        addSubview(stateLabel)
        addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func updateFooter() {
        guard isLoadingMore || loadMoreErrorMessage != nil else {
            tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 12))
            return
        }
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: bounds.width, height: 52))
        if isLoadingMore {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.center = CGPoint(x: footer.bounds.midX, y: footer.bounds.midY)
            indicator.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
            indicator.startAnimating()
            footer.addSubview(indicator)
        } else {
            let button = UIButton(type: .system)
            button.frame = footer.bounds.insetBy(dx: 18, dy: 6)
            button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            button.setTitle(loadMoreErrorMessage, for: .normal)
            button.titleLabel?.font = AppSettings.shared.appInterfaceFont(
                ofSize: 12,
                weight: .semibold,
                fallback: .systemFont(ofSize: 12, weight: .semibold)
            )
            button.addTarget(self, action: #selector(loadMoreRetryTapped), for: .touchUpInside)
            footer.addSubview(button)
        }
        tableView.tableFooterView = footer
    }

    @objc private func refreshPulled() {
        onRefresh?()
    }

    @objc private func loadMoreRetryTapped() {
        onLoadMore?()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileContentCell", for: indexPath)
        cell.backgroundColor = .clear
        cell.selectionStyle = .default
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.numberOfLines = 2
        content.textProperties.font = AppSettings.shared.appInterfaceFont(
            ofSize: 15,
            weight: .semibold,
            fallback: .systemFont(ofSize: 15, weight: .semibold)
        )
        content.secondaryTextProperties.numberOfLines = 2
        content.secondaryTextProperties.font = AppSettings.shared.appInterfaceFont(
            ofSize: 11.5,
            weight: .medium,
            fallback: .systemFont(ofSize: 11.5, weight: .medium)
        )
        content.secondaryTextProperties.color = .secondaryLabel
        content.imageProperties.maximumSize = CGSize(width: 21, height: 21)
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12,
            leading: 14,
            bottom: 12,
            trailing: 14
        )
        content.imageToTextPadding = 12
        configure(content: &content, row: rows[indexPath.row], cell: cell)
        cell.contentConfiguration = content
        if case .header = rows[indexPath.row] {
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
        } else {
            var background = UIBackgroundConfiguration.listPlainCell()
            background.backgroundColor = .secondarySystemBackground
            background.cornerRadius = 15
            background.backgroundInsets = NSDirectionalEdgeInsets(
                top: 5,
                leading: 2,
                bottom: 5,
                trailing: 2
            )
            cell.backgroundConfiguration = background
        }
        return cell
    }

    private func configure(
        content: inout UIListContentConfiguration,
        row: UserProfileContentRow,
        cell: UITableViewCell
    ) {
        let accent = AppSettings.shared.themeStyle.accentColor
        switch row {
        case .header(let title, let symbol):
            content.text = title
            content.textProperties.font = AppSettings.shared.appInterfaceFont(
                ofSize: 14,
                weight: .heavy,
                fallback: .systemFont(ofSize: 14, weight: .heavy)
            )
            content.textProperties.color = accent
            content.image = UIImage(systemName: symbol)
            content.imageProperties.tintColor = accent
            cell.selectionStyle = .none
        case .summaryTopic(let topic):
            content.text = topic.title
            content.secondaryText = "\(topic.likesCount ?? 0) \(String(localized: "me.stats.likes")) · \(topic.postsCount ?? 0) \(String(localized: "user.profile.replies"))"
            content.image = UIImage(systemName: "text.bubble.fill")
        case .summaryReply(let reply):
            content.text = reply.topic?.title ?? String(localized: "user.profile.replies")
            content.secondaryText = "#\(reply.postNumber) · \(reply.likeCount) \(String(localized: "me.stats.likes"))"
            content.image = UIImage(systemName: "quote.bubble.fill")
        case .summaryLink(let link):
            content.text = link.title ?? link.url
            content.secondaryText = "\(link.clicks) clicks"
            content.image = UIImage(systemName: "link")
        case .summaryUser(let label, let user):
            let displayName = user.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            content.text = (displayName?.isEmpty == false ? displayName : nil) ?? "@\(user.username)"
            content.secondaryText = "\(label) · \(user.count)"
            content.image = UIImage(systemName: "person.crop.circle")
        case .summaryCategory(let category):
            content.text = category.name
            content.secondaryText = "\(category.topicCount) \(String(localized: "me.stats.topics")) · \(category.postCount) \(String(localized: "user.profile.replies"))"
            content.image = UIImage(systemName: "square.grid.2x2")
        case .summaryBadge(let badge):
            content.text = badge.name
            content.secondaryText = badge.description
            content.image = UIImage(systemName: "medal")
        case .action(let action):
            content.text = action.title
            content.secondaryText = UserProfileFormatting.cleanBio(action.excerpt)
            content.image = UIImage(systemName: action.actionType == 4 ? "text.bubble.fill" : "quote.bubble.fill")
        case .reaction(let reaction):
            content.text = reaction.topicTitle ?? String(localized: "user.profile.reactions")
            content.secondaryText = UserProfileFormatting.cleanBio(reaction.excerpt)
            content.image = UIImage(systemName: "face.smiling.fill")
        }
        content.imageProperties.tintColor = accent
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = rows[indexPath.row]
        if case .header = row { return }
        onSelectRow?(row)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row >= rows.count - 4 else { return }
        onLoadMore?()
    }
}
