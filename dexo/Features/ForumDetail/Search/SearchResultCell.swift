import SDWebImage
import UIKit

/// FluxDO-aligned search result card using the same visual language as Home `TopicCell`
/// (card surface, title typography, category/tag chips, avatar, reply count).
final class SearchResultCell: UITableViewCell {
    static let reuseIdentifier = "SearchResultCell"

    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        return label
    }()

    private let lockIcon: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "lock.fill"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = .secondaryLabel
        view.isHidden = true
        return view
    }()

    private let floorBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()

    private let aiIcon: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "sparkles"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = .systemPurple
        view.isHidden = true
        return view
    }()

    private let blurbLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        return label
    }()

    private let avatarView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 14
        view.backgroundColor = .tertiarySystemFill
        return view
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .label
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let badgesStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        return stack
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .tertiaryLabel
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let replyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .tertiaryLabel
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private var currentAvatarURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        let titleRow = UIStackView(arrangedSubviews: [lockIcon, titleLabel, aiIcon, floorBadge])
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.axis = .horizontal
        titleRow.alignment = .top
        titleRow.spacing = 6

        let metaTrailing = UIStackView(arrangedSubviews: [timeLabel, replyLabel])
        metaTrailing.axis = .vertical
        metaTrailing.alignment = .trailing
        metaTrailing.spacing = 2

        let nameColumn = UIStackView(arrangedSubviews: [usernameLabel, badgesStack])
        nameColumn.axis = .vertical
        nameColumn.alignment = .leading
        nameColumn.spacing = 3

        let bottomRow = UIStackView(arrangedSubviews: [avatarView, nameColumn, UIView(), metaTrailing])
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center
        bottomRow.spacing = 8

        contentView.addSubview(cardView)
        cardView.addSubview(titleRow)
        cardView.addSubview(blurbLabel)
        cardView.addSubview(bottomRow)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),

            titleRow.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            titleRow.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            titleRow.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),

            lockIcon.widthAnchor.constraint(equalToConstant: 12),
            lockIcon.heightAnchor.constraint(equalToConstant: 14),
            aiIcon.widthAnchor.constraint(equalToConstant: 14),
            aiIcon.heightAnchor.constraint(equalToConstant: 14),
            floorBadge.heightAnchor.constraint(equalToConstant: 18),
            floorBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),

            blurbLabel.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 6),
            blurbLabel.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            blurbLabel.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),

            bottomRow.topAnchor.constraint(equalTo: blurbLabel.bottomAnchor, constant: 10),
            bottomRow.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            bottomRow.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
            bottomRow.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            avatarView.widthAnchor.constraint(equalToConstant: 28),
            avatarView.heightAnchor.constraint(equalToConstant: 28),
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
        let theme = AppSettings.shared.themeStyle
        cardView.backgroundColor = theme.topicCardBackgroundColor
        titleLabel.textColor = .label
        floorBadge.backgroundColor = UIColor.secondarySystemFill
        floorBadge.textColor = .secondaryLabel

        let rawTitle = post.topicTitleHeadline?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let titleSource: String = {
            if let rawTitle, !rawTitle.isEmpty { return rawTitle }
            if let fancy = topic?.fancyTitle, !fancy.isEmpty { return fancy }
            if let title = topic?.title, !title.isEmpty { return title }
            return String(localized: "search.untitled", defaultValue: "无标题")
        }()
        let plainTitle = Self.stripHTML(titleSource)
        TitleEmojiRenderer.apply(
            plainTitle,
            to: titleLabel,
            font: .systemFont(ofSize: 16, weight: .semibold),
            textColor: .label,
            baseURL: baseURL
        )

        let closed = topic?.closed == true || topic?.archived == true
        lockIcon.isHidden = !closed

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

        usernameLabel.text = post.username.isEmpty ? "—" : post.username
        timeLabel.text = TopicCell.formatDate(post.createdAt ?? "")
        let replies = max((topic?.postsCount ?? 1) - 1, 0)
        let replyText: String
        if replies >= 1000 {
            let k = Double(replies) / 1000.0
            replyText = String(format: "%.1fk", k).replacingOccurrences(of: ".0k", with: "k")
        } else {
            replyText = "\(replies)"
        }
        // bubble icon prefix via attributed
        let replyIcon = NSTextAttachment()
        if let img = UIImage(systemName: "bubble.right")?.withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal) {
            replyIcon.image = img
            replyIcon.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
        }
        let replyAttr = NSMutableAttributedString(attachment: replyIcon)
        replyAttr.append(NSAttributedString(string: " \(replyText)", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel,
        ]))
        replyLabel.attributedText = replyAttr

        badgesStack.arrangedSubviews.forEach {
            badgesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if let categoryName, !categoryName.isEmpty {
            badgesStack.addArrangedSubview(makeCategoryChip(name: categoryName, color: categoryColor))
        }
        for tag in (topic?.tags ?? []).prefix(3) {
            badgesStack.addArrangedSubview(makeTagChip(tag))
        }

        let avatarURL = post.avatarTemplate.flatMap {
            AvatarImageLoader.url(from: $0, baseURL: baseURL, size: 64)
        }
        if currentAvatarURL != avatarURL || avatarView.image == nil {
            currentAvatarURL = avatarURL
            AvatarImageLoader.setImage(on: avatarView, url: avatarURL)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        titleLabel.attributedText = nil
        blurbLabel.text = nil
        usernameLabel.text = nil
        timeLabel.text = nil
        replyLabel.attributedText = nil
        floorBadge.isHidden = true
        aiIcon.isHidden = true
        lockIcon.isHidden = true
        currentAvatarURL = nil
        avatarView.sd_cancelCurrentImageLoad()
        avatarView.image = nil
        badgesStack.arrangedSubviews.forEach {
            badgesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func makeCategoryChip(name: String, color: UIColor?) -> UIView {
        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = color ?? .systemGreen
        dot.layer.cornerRadius = 3
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
        ])
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
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
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel
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
