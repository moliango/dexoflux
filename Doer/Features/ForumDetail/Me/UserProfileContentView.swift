import SDWebImage
import UIKit

final class UserProfileContentView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onSelectRow: ((UserProfileContentRow) -> Void)?
    var onRefresh: (() -> Void)?
    var onLoadMore: (() -> Void)?
    var baseURL: String = ""
    var avatarTemplate: String = ""

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
        let chat = TopicListLayoutKind.current.usesChatSessionRows
        backgroundColor = .clear
        tableView.backgroundColor = .clear
        tableView.contentInset = UIEdgeInsets(top: chat ? 0 : 4, left: 0, bottom: 18, right: 0)
        tableView.estimatedRowHeight = TopicListCellFactory.estimatedRowHeight
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
        tableView.estimatedRowHeight = TopicListCellFactory.estimatedRowHeight
        tableView.dataSource = self
        tableView.delegate = self
        tableView.refreshControl = refreshControl
        TopicListCellFactory.registerCells(on: tableView)
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

        let layout = TopicListLayoutKind.current
        if layout.usesChatSessionRows {
            return TopicListCellFactory.makeSessionCell(
                tableView: tableView,
                indexPath: indexPath,
                item: sessionItem(for: row),
                layout: layout
            )
        }

        let cell = tableView.dequeueReusableCell(
            withIdentifier: UserProfileContentCell.reuseID,
            for: indexPath
        ) as! UserProfileContentCell
        cell.configure(row: row, baseURL: baseURL, fallbackAvatarTemplate: avatarTemplate)
        return cell
    }

    private func sessionItem(for row: UserProfileContentRow) -> TopicListSessionItem {
        let presentation = UserProfileContentPresentation.make(
            from: row,
            fallbackAvatarTemplate: avatarTemplate
        )
        return TopicListSessionItem(
            title: presentation.title,
            subtitle: presentation.subtitle,
            timeText: presentation.timeText,
            avatarTemplate: presentation.avatarTemplate,
            isEmphasized: true,
            baseURL: baseURL
        )
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

/// Section title row — small accent glyph + label, no card/chevron.
private final class UserProfileContentHeaderCell: UITableViewCell {
    static let reuseID = "UserProfileContentHeaderCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private var iconLeading: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = TopicListTypography.font(for: .title, weight: .semibold)

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        iconLeading = iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        NSLayoutConstraint.activate([
            iconLeading,
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

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
        let layout = TopicListLayoutKind.current
        iconLeading.constant = layout == .telegram ? 12 : 16
        titleLabel.font = TopicListTypography.font(for: .title, weight: .semibold)
        titleLabel.text = title
        titleLabel.textColor = accent
        iconView.image = UIImage(systemName: symbolName)
        iconView.tintColor = accent
    }
}

/// Inset card matching Home `TopicCell` / `BookmarkCell` (default, eye-care, xiaohongshu).
private final class UserProfileContentCell: UITableViewCell {
    static let reuseID = "UserProfileContentCell"

    private let cardView = UIView()
    private let avatarImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let timeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerCurve = .continuous

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 18
        avatarImageView.layer.cornerCurve = .continuous

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.textAlignment = .right
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(cardView)
        cardView.addSubview(avatarImageView)
        cardView.addSubview(textStack)
        cardView.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            avatarImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 13),
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -13),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            timeLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
        avatarImageView.tintColor = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        timeLabel.text = nil
        cardView.transform = .identity
        cardView.alpha = 1
    }

    func configure(row: UserProfileContentRow, baseURL: String, fallbackAvatarTemplate: String = "") {
        let theme = AppSettings.shared.themeStyle
        let presentation = UserProfileContentPresentation.make(
            from: row,
            fallbackAvatarTemplate: fallbackAvatarTemplate
        )

        cardView.layer.cornerRadius = theme.chromeCornerRadius
        cardView.backgroundColor = theme.topicCardBackgroundColor
        contentView.backgroundColor = .clear
        backgroundColor = .clear

        titleLabel.font = TopicListTypography.font(for: .title, weight: .semibold)
        subtitleLabel.font = TopicListTypography.font(for: .subtitle, weight: .regular)
        timeLabel.font = TopicListTypography.font(for: .meta, weight: .regular)
        titleLabel.textColor = .label
        subtitleLabel.textColor = .secondaryLabel
        timeLabel.textColor = .tertiaryLabel

        titleLabel.text = presentation.title
        subtitleLabel.text = presentation.subtitle
        subtitleLabel.isHidden = presentation.subtitle == nil || presentation.subtitle?.isEmpty == true
        timeLabel.text = presentation.timeText
        timeLabel.isHidden = presentation.timeText == nil || presentation.timeText?.isEmpty == true

        let symbol = UIImage(
            systemName: presentation.symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        if let template = presentation.avatarTemplate, !template.isEmpty, !baseURL.isEmpty {
            AvatarImageLoader.setImage(
                on: avatarImageView,
                template: template,
                baseURL: baseURL,
                size: AvatarImageLoader.primaryAvatarPixelSize,
                placeholder: symbol
            )
            avatarImageView.tintColor = nil
            avatarImageView.contentMode = .scaleAspectFill
            avatarImageView.backgroundColor = theme.topicChipBackgroundColor
        } else {
            avatarImageView.sd_cancelCurrentImageLoad()
            avatarImageView.image = symbol
            avatarImageView.tintColor = theme.accentColor
            avatarImageView.contentMode = .center
            avatarImageView.backgroundColor = theme.topicChipBackgroundColor
        }
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        let theme = AppSettings.shared.themeStyle
        let background = highlighted ? theme.mutedContentBackgroundColor : theme.topicCardBackgroundColor
        UIView.animate(withDuration: animated ? 0.12 : 0) {
            self.cardView.backgroundColor = background
            self.cardView.alpha = highlighted ? 0.92 : 1
        }
    }
}

struct UserProfileContentPresentation: Equatable {
    let title: String
    let subtitle: String?
    let timeText: String?
    let symbol: String
    let avatarTemplate: String?

    static func make(
        from row: UserProfileContentRow,
        fallbackAvatarTemplate: String? = nil
    ) -> UserProfileContentPresentation {
        let trimmedFallback = fallbackAvatarTemplate?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = (trimmedFallback?.isEmpty == false) ? trimmedFallback : nil
        switch row {
        case .header(let title, let symbol):
            return UserProfileContentPresentation(
                title: title,
                subtitle: nil,
                timeText: nil,
                symbol: symbol,
                avatarTemplate: nil
            )
        case .summaryTopic(let topic):
            return UserProfileContentPresentation(
                title: topic.title,
                subtitle: "\(topic.likesCount ?? 0) \(String(localized: "me.stats.likes")) · \(topic.postsCount ?? 0) \(String(localized: "user.profile.replies"))",
                timeText: topic.createdAt.map(TopicCell.formatDate),
                symbol: "text.bubble.fill",
                avatarTemplate: fallback
            )
        case .summaryReply(let reply):
            return UserProfileContentPresentation(
                title: reply.topic?.title ?? String(localized: "user.profile.replies"),
                subtitle: "#\(reply.postNumber) · \(reply.likeCount) \(String(localized: "me.stats.likes"))",
                timeText: reply.createdAt.map(TopicCell.formatDate),
                symbol: "quote.bubble.fill",
                avatarTemplate: fallback
            )
        case .summaryLink(let link):
            return UserProfileContentPresentation(
                title: link.title ?? link.url,
                subtitle: "\(link.clicks) \(String(localized: "user.profile.clicks", defaultValue: "clicks"))",
                timeText: nil,
                symbol: "link",
                avatarTemplate: fallback
            )
        case .summaryUser(let label, let user):
            let displayName = user.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (displayName?.isEmpty == false ? displayName : nil) ?? "@\(user.username)"
            return UserProfileContentPresentation(
                title: name,
                subtitle: "\(label) · \(user.count)",
                timeText: nil,
                symbol: "person.crop.circle.fill",
                avatarTemplate: user.avatarTemplate
            )
        case .summaryCategory(let category):
            return UserProfileContentPresentation(
                title: category.name,
                subtitle: "\(category.topicCount) \(String(localized: "me.stats.topics")) · \(category.postCount) \(String(localized: "user.profile.replies"))",
                timeText: nil,
                symbol: "square.grid.2x2.fill",
                avatarTemplate: nil
            )
        case .summaryBadge(let badge):
            return UserProfileContentPresentation(
                title: badge.name,
                subtitle: badge.description,
                timeText: nil,
                symbol: "medal.fill",
                avatarTemplate: nil
            )
        case .action(let action):
            let actionAvatar = action.avatarTemplate?.trimmingCharacters(in: .whitespacesAndNewlines)
            return UserProfileContentPresentation(
                title: action.title,
                subtitle: UserProfileFormatting.cleanBio(action.excerpt),
                timeText: (action.actingAt ?? action.createdAt).map(TopicCell.formatDate),
                symbol: actionSymbolName(for: action.actionType),
                avatarTemplate: (actionAvatar?.isEmpty == false) ? actionAvatar : fallback
            )
        case .reaction(let reaction):
            let reactionAvatar = reaction.avatarTemplate?.trimmingCharacters(in: .whitespacesAndNewlines)
            return UserProfileContentPresentation(
                title: reaction.topicTitle ?? String(localized: "user.profile.reactions"),
                subtitle: UserProfileFormatting.cleanBio(reaction.excerpt),
                timeText: reaction.createdAt.map(TopicCell.formatDate),
                symbol: "face.smiling.fill",
                avatarTemplate: (reactionAvatar?.isEmpty == false) ? reactionAvatar : fallback
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
