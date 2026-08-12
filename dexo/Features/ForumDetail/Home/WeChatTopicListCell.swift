import SDWebImage
import UIKit

/// WeChat-style full-bleed list row for Home when `ThemeStyle.weChat` is active.
/// Telegram uses a separate `TelegramTopicListCell` — do not recolor this for TG.
final class WeChatTopicListCell: UITableViewCell {
    static let reuseIdentifier = "WeChatTopicListCell"
    static let estimatedHeight: CGFloat = 76

    private var currentAvatarURL: URL?
    private var renderedTitle: String?
    private var emojiBaseURL: String?
    private var emojiUpdateObserver: NSObjectProtocol?

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 6
        iv.layer.cornerCurve = .continuous
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .tertiaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let replyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .tertiaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private let separator: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.separator.withAlphaComponent(0.28)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let textColumn: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let metaColumn: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .trailing
        stack.distribution = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }()

    private let metaSpacer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        emojiUpdateObserver = NotificationCenter.default.addObserver(
            forName: EmojiStore.didUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let title = self.renderedTitle else { return }
            self.applyTitle(title)
        }
    }

    deinit {
        if let emojiUpdateObserver {
            NotificationCenter.default.removeObserver(emojiUpdateObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .default
        backgroundColor = .clear
        contentView.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor

        textColumn.addArrangedSubview(titleLabel)
        textColumn.addArrangedSubview(subtitleLabel)
        metaColumn.addArrangedSubview(timeLabel)
        metaColumn.addArrangedSubview(metaSpacer)
        metaColumn.addArrangedSubview(replyLabel)

        contentView.addSubview(avatarImageView)
        contentView.addSubview(textColumn)
        contentView.addSubview(metaColumn)
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 48),
            avatarImageView.heightAnchor.constraint(equalToConstant: 48),

            textColumn.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            textColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            textColumn.trailingAnchor.constraint(equalTo: metaColumn.leadingAnchor, constant: -10),
            textColumn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            metaColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            metaColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            metaColumn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            separator.leadingAnchor.constraint(equalTo: textColumn.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
    }

    func configure(
        with topic: DiscourseTopicList.Topic,
        avatarURL: URL?,
        avatarUserId: Int? = nil,
        categoryName: String?,
        categoryColor: UIColor?,
        tags: [String] = [],
        categoryPresentation: TopicCategoryBadgePresentation? = nil,
        categoryBaseURL: String? = nil
    ) {
        let theme = AppSettings.shared.themeStyle
        contentView.backgroundColor = theme.topicCardBackgroundColor
        backgroundColor = theme.topicListBackgroundColor
        separator.backgroundColor = UIColor.separator.withAlphaComponent(0.28)

        let titlePoint = AppSettings.shared.effectiveInterfacePointSize(for: 16)
        let subPoint = AppSettings.shared.effectiveInterfacePointSize(for: 13)
        let unread = topic.isUnreadForDisplay
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: titlePoint, weight: unread ? .semibold : .regular)
        )
        subtitleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: subPoint, weight: .regular)
        )
        timeLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 12, weight: .regular)
        )
        replyLabel.font = timeLabel.font

        titleLabel.textColor = unread ? .label : .secondaryLabel
        emojiBaseURL = categoryBaseURL
        let plain = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
        renderedTitle = plain
        applyTitle(plain)

        var parts: [String] = []
        if let categoryName, !categoryName.isEmpty {
            parts.append(categoryName)
        }
        if let tag = tags.first, !tag.isEmpty {
            parts.append(tag)
        }
        if parts.isEmpty, let excerpt = topic.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
            parts.append(excerpt)
        }
        subtitleLabel.text = parts.isEmpty ? " " : parts.joined(separator: " · ")
        subtitleLabel.textColor = .secondaryLabel

        timeLabel.text = TopicCell.formatDate(topic.lastPostedAt ?? topic.createdAt)
        let replies = max(topic.postsCount - 1, 0)
        if AppSettings.shared.showTopicCardCounts, replies > 0 {
            replyLabel.text = replies > 99 ? "99+" : "\(replies)"
            replyLabel.isHidden = false
        } else {
            replyLabel.text = nil
            replyLabel.isHidden = true
        }

        currentAvatarURL = avatarURL
        avatarImageView.layer.cornerRadius = 6
        AvatarImageLoader.setImage(
            on: avatarImageView,
            url: avatarURL,
            cloudflareBaseURL: categoryBaseURL,
            avatarBaseURL: categoryBaseURL,
            userId: avatarUserId
        )
    }

    /// Generic session row (notifications / bookmarks / channels) — same chrome as topic rows.
    func configure(session item: TopicListSessionItem) {
        let theme = AppSettings.shared.themeStyle
        contentView.backgroundColor = theme.topicCardBackgroundColor
        backgroundColor = theme.topicListBackgroundColor
        separator.backgroundColor = UIColor.separator.withAlphaComponent(0.28)

        let titlePoint = AppSettings.shared.effectiveInterfacePointSize(for: 16)
        let subPoint = AppSettings.shared.effectiveInterfacePointSize(for: 13)
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: titlePoint, weight: item.isEmphasized ? .semibold : .regular)
        )
        subtitleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: subPoint, weight: .regular)
        )
        timeLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 12, weight: .regular)
        )
        replyLabel.font = timeLabel.font

        titleLabel.textColor = item.isEmphasized ? .label : .secondaryLabel
        emojiBaseURL = item.baseURL
        renderedTitle = item.title
        applyTitle(item.title)

        let sub = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        subtitleLabel.text = sub.isEmpty ? " " : sub
        subtitleLabel.textColor = .secondaryLabel

        timeLabel.text = item.timeText
        if let badge = item.badgeText, !badge.isEmpty {
            replyLabel.text = badge
            replyLabel.isHidden = false
            replyLabel.textColor = theme.accentColor
        } else {
            replyLabel.text = nil
            replyLabel.isHidden = true
            replyLabel.textColor = .tertiaryLabel
        }

        let resolvedURL = item.avatarURL ?? AvatarImageLoader.url(
            from: item.avatarTemplate,
            baseURL: item.baseURL ?? "",
            size: AvatarImageLoader.primaryAvatarPixelSize
        )
        currentAvatarURL = resolvedURL
        avatarImageView.layer.cornerRadius = 6
        AvatarImageLoader.setImage(
            on: avatarImageView,
            url: resolvedURL,
            cloudflareBaseURL: item.baseURL,
            avatarBaseURL: item.baseURL,
            userId: nil
        )
    }

    private func applyTitle(_ title: String) {
        TitleEmojiRenderer.apply(
            title,
            to: titleLabel,
            font: titleLabel.font ?? .systemFont(ofSize: 16, weight: .medium),
            textColor: titleLabel.textColor ?? .label,
            baseURL: emojiBaseURL
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        renderedTitle = nil
        emojiBaseURL = nil
        currentAvatarURL = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        timeLabel.text = nil
        replyLabel.text = nil
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        let theme = AppSettings.shared.themeStyle
        let base = theme.topicCardBackgroundColor
        UIView.animate(withDuration: animated ? 0.12 : 0) {
            self.contentView.backgroundColor = highlighted
                ? theme.mutedContentBackgroundColor
                : base
        }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        if !selected {
            contentView.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        }
    }
}
