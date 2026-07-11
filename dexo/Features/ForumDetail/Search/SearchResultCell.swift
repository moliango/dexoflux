import SDWebImage
import UIKit

final class SearchResultCell: UITableViewCell {
    static let reuseIdentifier = "SearchResultCell"

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 18
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let blurbLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
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
        contentView.addSubview(avatarImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(blurbLabel)
        contentView.addSubview(usernameLabel)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            blurbLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            blurbLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            blurbLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            usernameLabel.topAnchor.constraint(equalTo: blurbLabel.bottomAnchor, constant: 4),
            usernameLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            usernameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    func configure(with post: DiscourseSearchResult.SearchPost, baseURL: String) {
        // Strip HTML tags from headline for plain text display
        if let headline = post.topicTitleHeadline {
            titleLabel.text = Self.cleanedSearchText(headline)
        } else {
            titleLabel.text = nil
        }

        blurbLabel.text = Self.cleanedSearchText(post.blurb ?? "")
        usernameLabel.text = "@\(post.username) · #\(post.postNumber)"

        AvatarImageLoader.setImage(
            on: avatarImageView,
            template: post.avatarTemplate,
            baseURL: baseURL,
            size: 96
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        blurbLabel.text = nil
        usernameLabel.text = nil
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
    }

    private static func cleanedSearchText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&hellip;", with: "…")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
