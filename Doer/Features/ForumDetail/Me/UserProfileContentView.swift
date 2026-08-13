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
        applyThemeChrome()

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

    private func applyThemeChrome() {
        let theme = AppSettings.shared.themeStyle
        backgroundColor = .clear
        tableView.backgroundColor = .clear
        refreshControl.tintColor = theme.accentColor
        loadingIndicator.color = theme.accentColor
        stateLabel.textColor = .secondaryLabel
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 18, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.dataSource = self
        tableView.delegate = self
        tableView.refreshControl = refreshControl
        tableView.register(UserProfileContentCell.self, forCellReuseIdentifier: UserProfileContentCell.reuseID)
        tableView.register(UserProfileContentHeaderCell.self, forCellReuseIdentifier: UserProfileContentHeaderCell.reuseID)
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
        applyThemeChrome()
    }

    private func updateFooter() {
        guard isLoadingMore || loadMoreErrorMessage != nil else {
            tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 12))
            return
        }
        let theme = AppSettings.shared.themeStyle
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: bounds.width, height: 52))
        if isLoadingMore {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = theme.accentColor
            indicator.center = CGPoint(x: footer.bounds.midX, y: footer.bounds.midY)
            indicator.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
            indicator.startAnimating()
            footer.addSubview(indicator)
        } else {
            let button = UIButton(type: .system)
            button.frame = footer.bounds.insetBy(dx: 18, dy: 6)
            button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            button.tintColor = theme.accentColor
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
        let row = rows[indexPath.row]
        if case .header(let title, let symbol) = row {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: UserProfileContentHeaderCell.reuseID,
                for: indexPath
            ) as! UserProfileContentHeaderCell
            cell.configure(title: title, symbolName: symbol)
            return cell
        }

        let cell = tableView.dequeueReusableCell(
            withIdentifier: UserProfileContentCell.reuseID,
            for: indexPath
        ) as! UserProfileContentCell
        cell.configure(row: row)
        return cell
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

// MARK: - Themed cells

/// Section title row ("热门话题") — accent icon + label, no gray card.
private final class UserProfileContentHeaderCell: UITableViewCell {
    static let reuseID = "UserProfileContentHeaderCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .heavy,
            fallback: .systemFont(ofSize: 14, weight: .heavy)
        )

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, symbolName: String) {
        let accent = AppSettings.shared.themeStyle.accentColor
        titleLabel.text = title
        titleLabel.textColor = accent
        iconView.image = UIImage(systemName: symbolName)
        iconView.tintColor = accent
    }
}

/// Content item card — themed chip surface + accent icon well (matches Me action rows).
private final class UserProfileContentCell: UITableViewCell {
    static let reuseID = "UserProfileContentCell"

    private let cardView = UIView()
    private let iconWell = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectedBackgroundView = UIView()

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerCurve = .continuous

        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.numberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingTail

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.contentMode = .scaleAspectFit
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        contentView.addSubview(cardView)
        cardView.addSubview(iconWell)
        iconWell.addSubview(iconView)
        cardView.addSubview(textStack)
        cardView.addSubview(chevronView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),

            iconWell.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            iconWell.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconWell.widthAnchor.constraint(equalToConstant: 36),
            iconWell.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            textStack.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -10),

            chevronView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            chevronView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 10),
            chevronView.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        let theme = AppSettings.shared.themeStyle
        let base = theme.topicChipBackgroundColor
        UIView.animate(withDuration: animated ? 0.12 : 0) {
            self.cardView.backgroundColor = highlighted
                ? theme.accentColor.withAlphaComponent(0.10)
                : base
        }
    }

    func configure(row: UserProfileContentRow) {
        let theme = AppSettings.shared.themeStyle
        let accent = theme.accentColor
        let radius = max(theme.chromeCornerRadius + 2, 12)

        cardView.backgroundColor = theme.topicChipBackgroundColor
        cardView.layer.cornerRadius = radius
        iconWell.backgroundColor = accent.withAlphaComponent(0.14)
        iconWell.layer.cornerRadius = radius - 2
        iconView.tintColor = accent
        chevronView.tintColor = accent.withAlphaComponent(0.45)

        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 15,
            weight: .semibold,
            fallback: .systemFont(ofSize: 15, weight: .semibold)
        )
        titleLabel.textColor = .label

        subtitleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 12,
            weight: .medium,
            fallback: .systemFont(ofSize: 12, weight: .medium)
        )
        subtitleLabel.textColor = .secondaryLabel

        let presentation = Self.presentation(for: row)
        titleLabel.text = presentation.title
        subtitleLabel.text = presentation.subtitle
        subtitleLabel.isHidden = presentation.subtitle == nil || presentation.subtitle?.isEmpty == true
        iconView.image = UIImage(systemName: presentation.symbol)
    }

    private struct RowPresentation {
        let title: String
        let subtitle: String?
        let symbol: String
    }

    private static func presentation(for row: UserProfileContentRow) -> RowPresentation {
        switch row {
        case .header(let title, let symbol):
            return RowPresentation(title: title, subtitle: nil, symbol: symbol)
        case .summaryTopic(let topic):
            return RowPresentation(
                title: topic.title,
                subtitle: "\(topic.likesCount ?? 0) \(String(localized: "me.stats.likes")) · \(topic.postsCount ?? 0) \(String(localized: "user.profile.replies"))",
                symbol: "text.bubble.fill"
            )
        case .summaryReply(let reply):
            return RowPresentation(
                title: reply.topic?.title ?? String(localized: "user.profile.replies"),
                subtitle: "#\(reply.postNumber) · \(reply.likeCount) \(String(localized: "me.stats.likes"))",
                symbol: "quote.bubble.fill"
            )
        case .summaryLink(let link):
            return RowPresentation(
                title: link.title ?? link.url,
                subtitle: "\(link.clicks) clicks",
                symbol: "link"
            )
        case .summaryUser(let label, let user):
            let displayName = user.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (displayName?.isEmpty == false ? displayName : nil) ?? "@\(user.username)"
            return RowPresentation(
                title: name,
                subtitle: "\(label) · \(user.count)",
                symbol: "person.crop.circle.fill"
            )
        case .summaryCategory(let category):
            return RowPresentation(
                title: category.name,
                subtitle: "\(category.topicCount) \(String(localized: "me.stats.topics")) · \(category.postCount) \(String(localized: "user.profile.replies"))",
                symbol: "square.grid.2x2.fill"
            )
        case .summaryBadge(let badge):
            return RowPresentation(
                title: badge.name,
                subtitle: badge.description,
                symbol: "medal.fill"
            )
        case .action(let action):
            return RowPresentation(
                title: action.title,
                subtitle: UserProfileFormatting.cleanBio(action.excerpt),
                symbol: actionSymbolName(for: action.actionType)
            )
        case .reaction(let reaction):
            return RowPresentation(
                title: reaction.topicTitle ?? String(localized: "user.profile.reactions"),
                subtitle: UserProfileFormatting.cleanBio(reaction.excerpt),
                symbol: "face.smiling.fill"
            )
        }
    }

    private static func actionSymbolName(for actionType: Int?) -> String {
        switch actionType {
        case 1: return "heart.fill"
        case 2: return "hand.thumbsup.fill"
        case 4: return "text.bubble.fill"
        case 5: return "quote.bubble.fill"
        default: return "bubble.left.fill"
        }
    }
}
