import SDWebImage
import UIKit

/// Search result card that mirrors Home `TopicCell` layout, plus one blurb line
/// under the title (FluxDO search content density).
final class SearchResultCell: UITableViewCell {
    static let reuseIdentifier = "SearchResultCell"

    private var currentAvatarURL: URL?
    private var renderedTitle: String?
    private var emojiBaseURL: String?

    private enum Metrics {
        static let titleFontSize = AppSettings.topicTitleReferencePointSize
        static let titleLineHeight: CGFloat = 20
        static let titleMaxLines = 3
        static let blurbMaxLines = 2
        static let titleTopPadding: CGFloat = 9
        static let titleToBlurbSpacing: CGFloat = 5
        static let blurbToBadgeSpacing: CGFloat = 7
        static let badgeBottomPadding: CGFloat = 8
    }

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 17
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = Metrics.titleMaxLines
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }()

    private let replyCountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let replyIconView: UIImageView = {
        let image = UIImage(systemName: "bubble.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        let view = UIImageView(image: image)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .secondaryLabel
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }()

    private lazy var replyStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [replyIconView, replyCountLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 8)
        stack.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.65)
        stack.layer.cornerRadius = 11
        stack.layer.cornerCurve = .continuous
        stack.clipsToBounds = true
        return stack
    }()

    private let floorBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.backgroundColor = UIColor.secondarySystemFill
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.isHidden = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let aiIcon: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "sparkles"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .systemPurple
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }()

    private let blurbLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = Metrics.blurbMaxLines
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let badgesStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return stack
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private var blurbHeightConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let titleTrailing = UIStackView(arrangedSubviews: [aiIcon, floorBadge, replyStack])
        titleTrailing.translatesAutoresizingMaskIntoConstraints = false
        titleTrailing.axis = .horizontal
        titleTrailing.alignment = .center
        titleTrailing.spacing = 6

        contentView.addSubview(cardView)
        cardView.addSubview(avatarImageView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(titleTrailing)
        cardView.addSubview(blurbLabel)
        cardView.addSubview(badgesStackView)
        cardView.addSubview(timeLabel)

        let blurbHeight = blurbLabel.heightAnchor.constraint(equalToConstant: 0)
        blurbHeightConstraint = blurbHeight

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            avatarImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 13),
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Metrics.titleTopPadding),
            titleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: titleTrailing.leadingAnchor, constant: -8),

            titleTrailing.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            titleTrailing.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            aiIcon.widthAnchor.constraint(equalToConstant: 14),
            aiIcon.heightAnchor.constraint(equalToConstant: 14),
            floorBadge.heightAnchor.constraint(equalToConstant: 20),

            blurbLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.titleToBlurbSpacing),
            blurbLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            blurbLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            badgesStackView.topAnchor.constraint(equalTo: blurbLabel.bottomAnchor, constant: Metrics.blurbToBadgeSpacing),
            badgesStackView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            badgesStackView.heightAnchor.constraint(equalToConstant: 18),
            badgesStackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -Metrics.badgeBottomPadding),

            timeLabel.centerYAnchor.constraint(equalTo: badgesStackView.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: badgesStackView.trailingAnchor, constant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        with post: DiscourseSearchResult.SearchPost,
        topic: DiscourseSearchResult.SearchTopic? = nil,
        baseURL: String,
        categoryName: String? = nil,
        categoryColor: UIColor? = nil,
        isAIResult: Bool = false
    ) {
        let themeStyle = AppSettings.shared.themeStyle
        cardView.backgroundColor = themeStyle.topicCardBackgroundColor

        let rawTitle = post.topicTitleHeadline?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleSource: String = {
            if let rawTitle, !rawTitle.isEmpty { return rawTitle }
            if let fancy = topic?.fancyTitle, !fancy.isEmpty { return fancy }
            if let title = topic?.title, !title.isEmpty { return title }
            return String(localized: "search.untitled", defaultValue: "无标题")
        }()
        let plain = Self.stripHTML(titleSource)
        renderedTitle = plain
        emojiBaseURL = baseURL
        let titleFont = UIFont.systemFont(ofSize: Metrics.titleFontSize, weight: .semibold)
        titleLabel.font = titleFont
        titleLabel.textColor = .label
        TitleEmojiRenderer.apply(
            plain,
            to: titleLabel,
            font: titleFont,
            textColor: .label,
            baseURL: baseURL
        )

        let replies = max((topic?.postsCount ?? 1) - 1, 0)
        if replies >= 1000 {
            let k = Double(replies) / 1000.0
            replyCountLabel.text = String(format: "%.1fk", k).replacingOccurrences(of: ".0k", with: "k")
        } else {
            replyCountLabel.text = "\(replies)"
        }
        replyStack.isHidden = false

        if post.postNumber > 1 {
            floorBadge.isHidden = false
            floorBadge.text = "  #\(post.postNumber)  "
        } else {
            floorBadge.isHidden = true
        }
        aiIcon.isHidden = !isAIResult

        let blurb = Self.stripHTML(post.blurb ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        blurbLabel.text = blurb
        blurbLabel.isHidden = blurb.isEmpty

        // badges
        badgesStackView.arrangedSubviews.forEach {
            badgesStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        // username chip first (FluxDO search has username under avatar row; Topic puts avatar left.
        // Keep Topic layout: avatar left of title; badges row under blurb with category/tags.
        // Show username as first badge-like label for search attribution.
        let userLabel = UILabel()
        userLabel.font = .systemFont(ofSize: 12, weight: .medium)
        userLabel.textColor = .secondaryLabel
        userLabel.text = post.username.isEmpty ? nil : post.username
        if let text = userLabel.text, !text.isEmpty {
            badgesStackView.addArrangedSubview(userLabel)
        }
        if let categoryName, !categoryName.isEmpty, AppSettings.shared.showTopicCardCategory {
            badgesStackView.addArrangedSubview(makeCategoryChip(name: categoryName, color: categoryColor))
        }
        if AppSettings.shared.showTopicCardTags {
            for tag in (topic?.tags ?? []).prefix(3) {
                badgesStackView.addArrangedSubview(makeTagChip(tag))
            }
        }

        timeLabel.text = TopicCell.formatDate(post.createdAt ?? "")

        let avatarURL = post.avatarTemplate.flatMap {
            AvatarImageLoader.url(from: $0, baseURL: baseURL, size: 72)
        }
        if currentAvatarURL != avatarURL || avatarImageView.image == nil {
            currentAvatarURL = avatarURL
            AvatarImageLoader.setImage(on: avatarImageView, url: avatarURL)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        renderedTitle = nil
        emojiBaseURL = nil
        titleLabel.text = nil
        titleLabel.attributedText = nil
        blurbLabel.text = nil
        replyCountLabel.text = nil
        timeLabel.text = nil
        floorBadge.isHidden = true
        aiIcon.isHidden = true
        currentAvatarURL = nil
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
        badgesStackView.arrangedSubviews.forEach {
            badgesStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func makeCategoryChip(name: String, color: UIColor?) -> UIView {
        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = TopicTagVisualStyle.categoryColor(for: name, fallback: color)
        dot.layer.cornerRadius = 3
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
        ])
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = name
        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        return stack
    }

    private func makeTagChip(_ tag: String) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = TopicTagVisualStyle.color(for: tag)
        label.text = tag.hasPrefix("#") ? tag : "#\(tag)"
        return label
    }

    private static func stripHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
