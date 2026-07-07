import SDWebImage
import UIKit

enum TopicTagVisualStyle {
    static func color(for tag: String) -> UIColor {
        AppSettings.shared.themeStyle.topicTagColor(for: tag)
    }

    static func categoryColor(for name: String?, fallback: UIColor?) -> UIColor {
        AppSettings.shared.themeStyle.topicCategoryColor(for: name, fallback: fallback)
    }
}

final class TopicCell: UITableViewCell {
    static let reuseIdentifier = "TopicCell"
    static let estimatedHeight: CGFloat = 96
    private var currentAvatarURL: URL?

    private enum Metrics {
        static let titleFontSize: CGFloat = 16
        static let titleLineHeight: CGFloat = 21
        static let titleMaxLines = 3
        static let titleTopPadding: CGFloat = 9
        static let titleToBadgeMinimumSpacing: CGFloat = 7
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

    private let titleLabel: TopicTitleLabel = {
        let label = TopicTitleLabel()
        label.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: Metrics.titleFontSize, weight: .semibold)
        )
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = Metrics.titleMaxLines
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private let replyCountBadge: TopicCountBadgeView = {
        let badge = TopicCountBadgeView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        return badge
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
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
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
        cardView.addSubview(titleLabel)
        cardView.addSubview(replyCountBadge)
        cardView.addSubview(badgesStackView)
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

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Metrics.titleTopPadding),
            titleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: replyCountBadge.leadingAnchor, constant: -10),
            titleLabel.heightAnchor.constraint(lessThanOrEqualToConstant: Metrics.titleLineHeight * CGFloat(Metrics.titleMaxLines)),

            replyCountBadge.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            replyCountBadge.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            replyCountBadge.heightAnchor.constraint(equalToConstant: 22),

            badgesStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.titleToBadgeMinimumSpacing),
            badgesStackView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            badgesStackView.heightAnchor.constraint(equalToConstant: 18),
            badgesStackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -Metrics.badgeBottomPadding),

            timeLabel.centerYAnchor.constraint(equalTo: badgesStackView.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: badgesStackView.trailingAnchor, constant: 8),
        ])
    }

    func configure(
        with topic: DiscourseTopicList.Topic,
        avatarURL: URL?,
        categoryName: String?,
        categoryColor: UIColor?,
        tags: [String] = []
    ) {
        let themeStyle = AppSettings.shared.themeStyle
        cardView.backgroundColor = themeStyle.topicCardBackgroundColor
        configureTitleWithEmoji(topic.fancyTitle)

        let replies = max(topic.postsCount - 1, 0)
        replyCountBadge.configure(count: replies)

        configureBadges(
            categoryName: categoryName,
            categoryColor: categoryColor,
            tags: tags
        )

        // Time
        timeLabel.text = Self.formatDate(topic.lastPostedAt ?? topic.createdAt)

        // Avatar
        if currentAvatarURL != avatarURL || avatarImageView.image == nil {
            currentAvatarURL = avatarURL
            AvatarImageLoader.setImage(on: avatarImageView, url: avatarURL)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        titleLabel.attributedText = nil
        replyCountBadge.prepareForReuse()
        badgesStackView.arrangedSubviews.forEach { view in
            badgesStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        timeLabel.text = nil
        currentAvatarURL = nil
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
    }

    // MARK: - Emoji title

    private static let emojiPattern = try! NSRegularExpression(pattern: ":([\\w\\-+]+):")

    private func configureTitleWithEmoji(_ title: String) {
        guard !EmojiStore.lookupMap.isEmpty else {
            titleLabel.attributedText = nil
            titleLabel.text = title
            return
        }
        let matches = Self.emojiPattern.matches(in: title, range: NSRange(title.startIndex..., in: title))
        guard !matches.isEmpty, matches.contains(where: {
            let code = (title as NSString).substring(with: $0.range(at: 1))
            return EmojiStore.url(for: code) != nil
        }) else {
            titleLabel.attributedText = nil
            titleLabel.text = title
            return
        }

        let result = NSMutableAttributedString()
        let titleFont = titleLabel.font ?? .systemFont(ofSize: Metrics.titleFontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont]
        var lastEnd = title.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: title),
                  let codeRange = Range(match.range(at: 1), in: title)
            else { continue }

            let code = String(title[codeRange])

            // Append text before this match
            if lastEnd < fullRange.lowerBound {
                result.append(NSAttributedString(string: String(title[lastEnd..<fullRange.lowerBound]), attributes: attrs))
            }

            if let urlString = EmojiStore.url(for: code), let url = URL(string: urlString) {
                // Emoji image attachment
                let attachment = EmojiTextAttachment()
                attachment.emojiURL = url
                attachment.bounds = CGRect(x: 0, y: titleFont.descender, width: titleFont.lineHeight, height: titleFont.lineHeight)
                result.append(NSAttributedString(attachment: attachment))
            } else {
                // No URL found — keep original text
                result.append(NSAttributedString(string: String(title[fullRange]), attributes: attrs))
            }

            lastEnd = fullRange.upperBound
        }

        // Append remaining text
        if lastEnd < title.endIndex {
            result.append(NSAttributedString(string: String(title[lastEnd...]), attributes: attrs))
        }

        titleLabel.attributedText = result

        // Load emoji images
        loadEmojiImages(in: result)
    }

    private func loadEmojiImages(in attributedString: NSMutableAttributedString) {
        attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length)) { value, _, _ in
            guard let attachment = value as? EmojiTextAttachment, let url = attachment.emojiURL else { return }
            SDWebImageManager.shared.loadImage(with: url, options: [.retryFailed], progress: nil) { [weak self] image, _, _, _, _, _ in
                guard let image, let self else { return }
                attachment.image = image
                self.titleLabel.setNeedsDisplay()
                // Force layout update so the label redraws with the loaded image
                self.setNeedsLayout()
            }
        }
    }

    private func configureBadges(
        categoryName: String?,
        categoryColor: UIColor?,
        tags: [String]
    ) {
        badgesStackView.arrangedSubviews.forEach { view in
            badgesStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let categoryName {
            let themedColor = TopicTagVisualStyle.categoryColor(for: categoryName, fallback: categoryColor)
            let categoryBadge = TopicBadgeView(
                text: categoryName,
                style: .category(color: themedColor)
            )
            badgesStackView.addArrangedSubview(categoryBadge)
        }

        for tag in tags.prefix(2) where !tag.isEmpty {
            let tagBadge = TopicBadgeView(text: tag, style: .tag(color: TopicTagVisualStyle.color(for: tag)))
            badgesStackView.addArrangedSubview(tagBadge)
        }
    }

    // MARK: - Helpers

    private static func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else { return isoString }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

}

private final class TopicTitleLabel: UILabel {
    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        var rect = super.textRect(forBounds: bounds, limitedToNumberOfLines: numberOfLines)
        rect.origin.x = bounds.origin.x
        rect.origin.y = bounds.origin.y
        rect.size.width = bounds.width
        rect.size.height = min(rect.height, bounds.height)
        return rect
    }

    override func drawText(in rect: CGRect) {
        let topAlignedRect = textRect(forBounds: rect, limitedToNumberOfLines: numberOfLines)
        super.drawText(in: topAlignedRect)
    }
}

private final class TopicCountBadgeView: UIView {
    private static let hotCountThreshold = 50
    private var widthConstraint: NSLayoutConstraint?

    private let iconView: UIImageView = {
        let image = UIImage(systemName: "bubble.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textAlignment = .right
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.85
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 7, bottom: 0, trailing: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        layer.cornerRadius = 11
        layer.cornerCurve = .continuous
        clipsToBounds = true

        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(countLabel)
        addSubview(stackView)

        widthConstraint = widthAnchor.constraint(equalToConstant: 38)
        widthConstraint?.priority = .required

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        widthConstraint?.isActive = true
    }

    func configure(count: Int) {
        let displayText = "\(min(count, 9_999))"
        countLabel.text = displayText
        widthConstraint?.constant = Self.width(forDisplayText: displayText)
        let themeStyle = AppSettings.shared.themeStyle
        let isHot = count >= Self.hotCountThreshold
        let hotColor = themeStyle.hotTopicColor
        let foreground: UIColor = isHot ? hotColor : themeStyle.topicCountForegroundColor
        iconView.tintColor = foreground
        countLabel.textColor = foreground
        backgroundColor = isHot
            ? hotColor.withAlphaComponent(0.14)
            : themeStyle.topicCountBackgroundColor
    }

    func prepareForReuse() {
        countLabel.text = nil
        widthConstraint?.constant = 38
    }

    private static func width(forDisplayText text: String) -> CGFloat {
        switch text.count {
        case 0, 1:
            return 38
        case 2:
            return 46
        case 3:
            return 54
        default:
            return 62
        }
    }
}

private final class TopicBadgeView: UIView {
    enum Style {
        case category(color: UIColor)
        case tag(color: UIColor)
    }

    private let contentStack = UIStackView()

    init(text: String, style: Style) {
        super.init(frame: .zero)
        setup(text: text, style: style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(text: String, style: Style) {
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 4
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        switch style {
        case .category(let color):
            backgroundColor = color.withAlphaComponent(0.08)
            layer.borderColor = color.withAlphaComponent(0.20).cgColor
            layer.borderWidth = 1
            contentStack.addArrangedSubview(makeDot(color: color))
        case .tag(let color):
            backgroundColor = color.withAlphaComponent(0.10)
            layer.borderColor = color.withAlphaComponent(0.18).cgColor
            layer.borderWidth = 1
            contentStack.addArrangedSubview(makeSymbolIcon(name: "tag.fill", color: color))
        }

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = style.textColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.widthAnchor.constraint(lessThanOrEqualToConstant: style.maxTextWidth).isActive = true
        contentStack.addArrangedSubview(label)
    }

    private func makeDot(color: UIColor) -> UIView {
        let dot = UIView()
        dot.backgroundColor = color
        dot.layer.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
        ])
        return dot
    }

    private func makeSymbolIcon(name: String, color: UIColor) -> UIImageView {
        let config = UIImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: name, withConfiguration: config))
        imageView.tintColor = color
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 9),
            imageView.heightAnchor.constraint(equalToConstant: 9),
        ])
        return imageView
    }
}

private extension TopicBadgeView.Style {
    var textColor: UIColor {
        switch self {
        case .category(let color):
            return AppSettings.shared.themeStyle == .systemDefault ? .label : color
        case .tag(let color):
            return color
        }
    }

    var maxTextWidth: CGFloat {
        switch self {
        case .category:
            return 96
        case .tag:
            return 80
        }
    }
}
