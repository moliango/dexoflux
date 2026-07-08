import SDWebImage
import UIKit

final class NotificationsViewController: ObservableViewController {
    var onTopicSelected: ((Int) -> Void)?

    private let api: DiscourseAPI
    private let viewModel: NotificationsViewModel
    private weak var authGate: AuthGating?

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(NotificationCell.self, forCellReuseIdentifier: NotificationCell.reuseIdentifier)
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 84
        table.refreshControl = refreshControl
        return table
    }()

    private let refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        return control
    }()

    private let skeletonView = NotificationListSkeletonView()

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
        config.title = String(localized: "notifications.login_prompt")
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
        return stack
    }()

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.api = api
        self.viewModel = NotificationsViewModel(api: api)
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "notifications.title")
        applyThemeStyle()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark.circle"),
            style: .plain,
            target: self,
            action: #selector(markAllReadTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "notifications.mark_all_read")

        view.addSubview(tableView)
        view.addSubview(skeletonView)
        view.addSubview(stateStackView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            skeletonView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            skeletonView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stateStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateStackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateStackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            stateIconView.widthAnchor.constraint(equalToConstant: 52),
            stateIconView.heightAnchor.constraint(equalToConstant: 52),
        ])

        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        Task {
            await viewModel.loadNotifications()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureCloseButtonIfNeeded()
    }

    override func updateUI() {
        refreshControl.endRefreshing()
        applyThemeStyle()

        let hasNotifications = !viewModel.notifications.isEmpty
        let showSkeleton = viewModel.isLoading && !hasNotifications
        skeletonView.isHidden = !showSkeleton
        tableView.isHidden = !hasNotifications || showSkeleton
        stateStackView.isHidden = hasNotifications || showSkeleton
        navigationItem.rightBarButtonItem?.isEnabled = viewModel.notifications.contains { !$0.read }

        if viewModel.requiresLogin {
            configureState(
                iconName: "lock.circle",
                text: viewModel.errorMessage ?? String(localized: "notifications.login_prompt"),
                showLogin: true,
                showRetry: false
            )
        } else if let errorMessage = viewModel.errorMessage, !hasNotifications {
            configureState(
                iconName: "exclamationmark.triangle",
                text: errorMessage,
                showLogin: false,
                showRetry: true
            )
        } else if !hasNotifications, !viewModel.isLoading {
            configureState(
                iconName: "bell",
                text: String(localized: "notifications.empty"),
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
        skeletonView.applyThemeStyle()
        stateIconView.tintColor = themeStyle.accentColor.withAlphaComponent(0.78)
        loginButton.tintColor = themeStyle.accentColor
        retryButton.tintColor = themeStyle.accentColor
    }

    private func configureCloseButtonIfNeeded() {
        guard navigationController?.presentingViewController != nil else { return }
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
    }

    private func configureState(iconName: String, text: String, showLogin: Bool, showRetry: Bool) {
        stateIconView.image = UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 46, weight: .regular))
        stateLabel.text = text
        loginButton.isHidden = !showLogin
        retryButton.isHidden = !showRetry
    }

    @objc private func refreshPulled() {
        Task {
            await viewModel.loadNotifications()
        }
    }

    @objc private func retryTapped() {
        Task {
            await viewModel.loadNotifications()
        }
    }

    @objc private func loginTapped() {
        authGate?.requireAuth(then: { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.loadNotifications()
            }
        })
    }

    @objc private func markAllReadTapped() {
        Task {
            await viewModel.markAllRead()
        }
    }

    private func openNotification(_ notification: DiscourseNotification) {
        if !notification.read {
            Task {
                await viewModel.markNotificationRead(id: notification.id)
            }
        }

        guard let topicId = notification.topicId else { return }
        if let onTopicSelected {
            dismiss(animated: true) {
                onTopicSelected(topicId)
            }
        } else {
            let detailVC = TopicDetailViewController(api: api, topicId: topicId)
            navigationController?.pushViewController(detailVC, animated: true)
        }
    }
}

extension NotificationsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.notifications.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: NotificationCell.reuseIdentifier, for: indexPath) as? NotificationCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.notifications[indexPath.row], baseURL: api.baseURL)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        openNotification(viewModel.notifications[indexPath.row])
    }
}

private final class NotificationCell: UITableViewCell {
    static let reuseIdentifier = "NotificationCell"

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.backgroundColor = AppSettings.shared.themeStyle.topicChipBackgroundColor
        imageView.tintColor = .secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let badgeContainer: UIView = {
        let view = UIView()
        view.backgroundColor = AppSettings.shared.themeStyle.topicChipBackgroundColor
        view.layer.cornerRadius = 11
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.12
        view.layer.shadowRadius = 2
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let badgeIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let unreadDotView: UIView = {
        let view = UIView()
        view.backgroundColor = AppSettings.shared.themeStyle.accentColor
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(cardView)
        cardView.addSubview(avatarImageView)
        cardView.addSubview(badgeContainer)
        badgeContainer.addSubview(badgeIconView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(descriptionLabel)
        cardView.addSubview(timeLabel)
        cardView.addSubview(unreadDotView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            avatarImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),

            badgeContainer.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -3),
            badgeContainer.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 3),
            badgeContainer.widthAnchor.constraint(equalToConstant: 22),
            badgeContainer.heightAnchor.constraint(equalToConstant: 22),

            badgeIconView.centerXAnchor.constraint(equalTo: badgeContainer.centerXAnchor),
            badgeIconView.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),
            badgeIconView.widthAnchor.constraint(equalToConstant: 14),
            badgeIconView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: unreadDotView.leadingAnchor, constant: -10),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),
            descriptionLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            timeLabel.centerYAnchor.constraint(equalTo: descriptionLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            unreadDotView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            unreadDotView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            unreadDotView.widthAnchor.constraint(equalToConstant: 8),
            unreadDotView.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
        titleLabel.text = nil
        descriptionLabel.text = nil
        timeLabel.text = nil
    }

    func configure(with notification: DiscourseNotification, baseURL: String) {
        let themeStyle = AppSettings.shared.themeStyle
        let icon = Self.icon(for: notification.notificationType)
        let color = Self.color(for: notification.notificationType, themeStyle: themeStyle)
        cardView.backgroundColor = themeStyle.topicCardBackgroundColor
        avatarImageView.backgroundColor = themeStyle.topicChipBackgroundColor
        unreadDotView.backgroundColor = themeStyle.accentColor
        badgeIconView.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        badgeIconView.tintColor = notification.read ? .secondaryLabel : color
        badgeContainer.backgroundColor = notification.read
            ? themeStyle.topicChipBackgroundColor
            : themeStyle.accentColor.withAlphaComponent(0.12)
        badgeContainer.layer.shadowColor = themeStyle.accentColor.cgColor

        titleLabel.text = notification.displayTitle
        titleLabel.font = .systemFont(ofSize: 15, weight: notification.read ? .regular : .semibold)
        descriptionLabel.text = notification.displayDescription
        timeLabel.text = Self.formatDate(notification.createdAt)
        unreadDotView.isHidden = notification.read

        AvatarImageLoader.setImage(
            on: avatarImageView,
            url: Self.avatarURL(for: notification, baseURL: baseURL),
            placeholder: UIImage(systemName: "person.crop.circle")
        )
    }

    private static func avatarURL(for notification: DiscourseNotification, baseURL: String) -> URL? {
        guard let template = notification.actingUserAvatarTemplate ?? notification.data.avatarTemplate else { return nil }
        return AvatarImageLoader.url(from: template, baseURL: baseURL, size: 96)
    }

    private static func formatDate(_ string: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
        guard let date else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    private static func icon(for type: Int) -> String {
        switch type {
        case 1:
            return "at"
        case 2:
            return "arrowshape.turn.up.left.fill"
        case 3:
            return "quote.bubble.fill"
        case 5, 19:
            return "heart.fill"
        case 6, 7:
            return "envelope.fill"
        case 9:
            return "plus.bubble.fill"
        case 11, 39:
            return "link"
        case 12:
            return "seal.fill"
        case 15:
            return "person.2.fill"
        case 17:
            return "eye.fill"
        case 24:
            return "bookmark.fill"
        case 25:
            return "hand.thumbsup.fill"
        case 34:
            return "checklist"
        case 43:
            return "rocket.fill"
        default:
            return "bell.fill"
        }
    }

    private static func color(for type: Int, themeStyle: AppSettings.ThemeStyle) -> UIColor {
        if themeStyle != .systemDefault {
            return themeStyle.topicTagColor(for: "notification-\(type)")
        }
        switch type {
        case 5, 19, 25:
            return .systemRed
        case 6, 7:
            return .systemBlue
        case 12:
            return .systemYellow
        case 1, 15:
            return .systemBlue
        case 24:
            return .systemPurple
        case 43:
            return .systemIndigo
        default:
            return .secondaryLabel
        }
    }
}

private final class NotificationListSkeletonView: UIView {
    private var rows: [NotificationSkeletonRow] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        for _ in 0 ..< 8 {
            let row = NotificationSkeletonRow()
            rows.append(row)
            stack.addArrangedSubview(row)
        }
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        backgroundColor = themeStyle.topicListBackgroundColor
        rows.forEach { $0.applyThemeStyle(themeStyle) }
    }
}

private final class NotificationSkeletonRow: UIView {
    private var skeletonViews: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 76).isActive = true

        let avatar = makeSkeletonView(cornerRadius: 20)
        let title = makeSkeletonView(cornerRadius: 4)
        let titleShort = makeSkeletonView(cornerRadius: 4)
        let subtitle = makeSkeletonView(cornerRadius: 4)
        addSubview(avatar)
        addSubview(title)
        addSubview(titleShort)
        addSubview(subtitle)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            avatar.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),

            title.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            title.heightAnchor.constraint(equalToConstant: 14),

            titleShort.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            titleShort.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 7),
            titleShort.widthAnchor.constraint(equalToConstant: 150),
            titleShort.heightAnchor.constraint(equalToConstant: 14),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleShort.bottomAnchor, constant: 9),
            subtitle.widthAnchor.constraint(equalToConstant: 210),
            subtitle.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeSkeletonView(cornerRadius: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = AppSettings.shared.themeStyle.topicChipBackgroundColor
        view.layer.cornerRadius = cornerRadius
        view.translatesAutoresizingMaskIntoConstraints = false
        skeletonViews.append(view)
        return view
    }

    func applyThemeStyle(_ themeStyle: AppSettings.ThemeStyle) {
        backgroundColor = .clear
        skeletonViews.forEach { $0.backgroundColor = themeStyle.topicChipBackgroundColor }
    }
}
