import UIKit

/// FluxDo `CompactTopicCard`: pinned topics render as a single compact row
/// (pin + category mark + title + unread/reply), not a full topic card.
final class CompactPinnedTopicCell: UITableViewCell {
    static let reuseIdentifier = "CompactPinnedTopicCell"
    static let estimatedHeight: CGFloat = 48

    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 0
        return view
    }()

    private let pinView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let view = UIImageView(image: UIImage(systemName: "pin.fill", withConfiguration: configuration))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        return view
    }()

    private let categoryHost = UIView()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let unreadBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.layer.cornerCurve = .continuous
        label.layer.masksToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private let replyStack: UIStackView = {
        let icon = UIImageView(
            image: UIImage(
                systemName: "bubble.left.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            )
        )
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.tag = 1

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        stack.setContentHuggingPriority(.required, for: .horizontal)
        return stack
    }()

    private var emojiBaseURL: String?
    private var renderedTitle: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        categoryHost.translatesAutoresizingMaskIntoConstraints = false
        categoryHost.setContentHuggingPriority(.required, for: .horizontal)

        contentView.addSubview(cardView)
        cardView.addSubview(pinView)
        cardView.addSubview(categoryHost)
        cardView.addSubview(titleLabel)
        cardView.addSubview(unreadBadge)
        cardView.addSubview(replyStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),

            pinView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            pinView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            pinView.widthAnchor.constraint(equalToConstant: 14),
            pinView.heightAnchor.constraint(equalToConstant: 14),

            categoryHost.leadingAnchor.constraint(equalTo: pinView.trailingAnchor, constant: 8),
            categoryHost.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            categoryHost.widthAnchor.constraint(equalToConstant: 12),
            categoryHost.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: categoryHost.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: cardView.topAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -10),

            unreadBadge.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            unreadBadge.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            unreadBadge.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            unreadBadge.heightAnchor.constraint(equalToConstant: 18),
            unreadBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),

            replyStack.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            replyStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            replyStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
        ])
    }

    func configure(
        with topic: DiscourseTopicList.Topic,
        categoryColor: UIColor?,
        categoryPresentation: TopicCategoryBadgePresentation?,
        categoryBaseURL: String?
    ) {
        let theme = AppSettings.shared.themeStyle
        cardView.backgroundColor = theme.topicCardBackgroundColor.withAlphaComponent(0.72)
        pinView.tintColor = theme.accentColor

        let unread = topic.isUnreadForDisplay
        titleLabel.textColor = unread ? .label : .secondaryLabel
        titleLabel.font = .systemFont(ofSize: 13, weight: unread ? .medium : .regular)
        emojiBaseURL = categoryBaseURL
        renderedTitle = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
        TitleEmojiRenderer.apply(
            renderedTitle ?? topic.title,
            to: titleLabel,
            font: titleLabel.font,
            textColor: titleLabel.textColor,
            baseURL: categoryBaseURL
        )

        installCategoryMark(
            color: TopicTagVisualStyle.categoryColor(
                for: categoryPresentation?.name,
                fallback: categoryColor
            ),
            presentation: categoryPresentation,
            baseURL: categoryBaseURL
        )

        let unreadCount = topic.unreadPosts
        let replies = max(topic.postsCount - 1, 0)
        if unreadCount > 0 {
            unreadBadge.isHidden = false
            replyStack.isHidden = true
            unreadBadge.text = unreadCount > 99 ? " 99+ " : " \(unreadCount) "
            unreadBadge.textColor = theme.accentColor
            unreadBadge.backgroundColor = theme.accentColor.withAlphaComponent(0.16)
        } else if replies > 0 {
            unreadBadge.isHidden = true
            replyStack.isHidden = false
            (replyStack.arrangedSubviews.first as? UIImageView)?.tintColor = .tertiaryLabel
            (replyStack.viewWithTag(1) as? UILabel)?.text = "\(replies)"
            (replyStack.viewWithTag(1) as? UILabel)?.textColor = .tertiaryLabel
        } else {
            unreadBadge.isHidden = true
            replyStack.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        renderedTitle = nil
        emojiBaseURL = nil
        titleLabel.text = nil
        titleLabel.attributedText = nil
        unreadBadge.text = nil
        categoryHost.subviews.forEach { $0.removeFromSuperview() }
    }

    private func installCategoryMark(
        color: UIColor,
        presentation: TopicCategoryBadgePresentation?,
        baseURL: String?
    ) {
        categoryHost.subviews.forEach { $0.removeFromSuperview() }
        let mark = makeCategoryMark(color: color, presentation: presentation, baseURL: baseURL)
        mark.translatesAutoresizingMaskIntoConstraints = false
        categoryHost.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: categoryHost.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: categoryHost.centerYAnchor),
        ])
    }

    private func makeCategoryMark(
        color: UIColor,
        presentation: TopicCategoryBadgePresentation?,
        baseURL: String?
    ) -> UIView {
        switch presentation?.iconSource {
        case .fontAwesome(let name):
            let label = UILabel()
            label.text = DiscourseFontAwesomeIcon.glyph(for: name)
            label.font = UIFont(name: DiscourseFontAwesomeIcon.fontName, size: 12)
                ?? .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = color
            label.textAlignment = .center
            return label
        case .logo(let rawURL):
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            ForumImageLoader.setImage(
                on: imageView,
                url: Self.resolveURL(rawURL, baseURL: baseURL ?? ""),
                placeholder: UIImage(systemName: "circle.fill"),
                cloudflareBaseURL: baseURL
            )
            imageView.widthAnchor.constraint(equalToConstant: 12).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 12).isActive = true
            return imageView
        case .lock:
            let imageView = UIImageView(
                image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
            )
            imageView.tintColor = color
            return imageView
        case .dot, .none:
            let dot = UIView()
            dot.backgroundColor = color
            dot.layer.cornerRadius = 3
            dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
            return dot
        }
    }

    private static func resolveURL(_ rawURL: String, baseURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absoluteURL = URL(string: trimmed), absoluteURL.scheme != nil {
            return absoluteURL
        }
        guard let base = URL(string: baseURL) else { return URL(string: trimmed) }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }
}
