import SDWebImage
import UIKit

final class ShareImageCardView: UIView {
    private let brandIconView = UIImageView()
    private let brandLabel = UILabel()
    private let titleLabel = UILabel()
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()
    private let dividerTop = UIView()
    private let bodyContainer = UIView()
    private let bodyLabel = UILabel()
    private let dividerBottom = UIView()
    private let linkIcon = UIImageView()
    private let linkLabel = UILabel()

    private var theme: ShareImageTheme = .classic
    private let cardWidth: CGFloat = 375
    private let maxBodyHeight: CGFloat = 520

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 0

        brandIconView.translatesAutoresizingMaskIntoConstraints = false
        brandIconView.contentMode = .scaleAspectFit
        brandIconView.tintColor = .label

        brandLabel.translatesAutoresizingMaskIntoConstraints = false
        brandLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 0
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 18
        avatarView.backgroundColor = .secondarySystemFill

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.font = .systemFont(ofSize: 12, weight: .regular)

        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.layer.cornerRadius = 10
        bodyContainer.layer.cornerCurve = .continuous

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.numberOfLines = 0
        bodyLabel.font = .systemFont(ofSize: 15)

        linkIcon.translatesAutoresizingMaskIntoConstraints = false
        linkIcon.image = UIImage(systemName: "link")
        linkIcon.contentMode = .scaleAspectFit

        linkLabel.translatesAutoresizingMaskIntoConstraints = false
        linkLabel.font = .systemFont(ofSize: 11)
        linkLabel.lineBreakMode = .byTruncatingTail

        [dividerTop, dividerBottom].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        addSubview(brandIconView)
        addSubview(brandLabel)
        addSubview(titleLabel)
        addSubview(avatarView)
        addSubview(nameLabel)
        addSubview(metaLabel)
        addSubview(dividerTop)
        addSubview(bodyContainer)
        bodyContainer.addSubview(bodyLabel)
        addSubview(dividerBottom)
        addSubview(linkIcon)
        addSubview(linkLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: cardWidth),

            brandIconView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            brandIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            brandIconView.widthAnchor.constraint(equalToConstant: 28),
            brandIconView.heightAnchor.constraint(equalToConstant: 28),

            brandLabel.centerYAnchor.constraint(equalTo: brandIconView.centerYAnchor),
            brandLabel.leadingAnchor.constraint(equalTo: brandIconView.trailingAnchor, constant: 8),
            brandLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),

            titleLabel.topAnchor.constraint(equalTo: brandIconView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            avatarView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            avatarView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            nameLabel.topAnchor.constraint(equalTo: avatarView.topAnchor, constant: 1),

            metaLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            dividerTop.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 14),
            dividerTop.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dividerTop.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            dividerTop.heightAnchor.constraint(equalToConstant: 1),

            bodyContainer.topAnchor.constraint(equalTo: dividerTop.bottomAnchor, constant: 14),
            bodyContainer.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            bodyLabel.topAnchor.constraint(equalTo: bodyContainer.topAnchor, constant: 12),
            bodyLabel.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: 12),
            bodyLabel.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -12),
            bodyLabel.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -12),
            bodyLabel.heightAnchor.constraint(lessThanOrEqualToConstant: maxBodyHeight),

            dividerBottom.topAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: 14),
            dividerBottom.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dividerBottom.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            dividerBottom.heightAnchor.constraint(equalToConstant: 1),

            linkIcon.topAnchor.constraint(equalTo: dividerBottom.bottomAnchor, constant: 12),
            linkIcon.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            linkIcon.widthAnchor.constraint(equalToConstant: 14),
            linkIcon.heightAnchor.constraint(equalToConstant: 14),
            linkIcon.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

            linkLabel.centerYAnchor.constraint(equalTo: linkIcon.centerYAnchor),
            linkLabel.leadingAnchor.constraint(equalTo: linkIcon.trailingAnchor, constant: 6),
            linkLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
    }

    func configure(
        theme: ShareImageTheme,
        brandName: String,
        title: String,
        baseURL: String,
        authorName: String,
        username: String,
        createdAt: String?,
        avatarURL: URL?,
        cookedHTML: String,
        shareURL: String
    ) {
        self.theme = theme
        backgroundColor = theme.backgroundColor
        bodyContainer.backgroundColor = theme.cardColor
        dividerTop.backgroundColor = theme.borderColor
        dividerBottom.backgroundColor = theme.borderColor

        brandIconView.image = UIImage(systemName: "circle.lefthalf.filled")
        brandIconView.tintColor = theme.primaryTextColor.withAlphaComponent(0.85)
        brandLabel.text = brandName
        brandLabel.textColor = theme.primaryTextColor.withAlphaComponent(0.85)

        TitleEmojiRenderer.apply(
            title,
            to: titleLabel,
            font: .systemFont(ofSize: 18, weight: .semibold),
            textColor: theme.primaryTextColor.withAlphaComponent(0.92),
            baseURL: baseURL
        )

        nameLabel.text = authorName
        nameLabel.textColor = theme.primaryTextColor.withAlphaComponent(0.9)
        metaLabel.text = "@\(username)" + (createdAt.map { " · \($0)" } ?? "")
        metaLabel.textColor = theme.secondaryTextColor

        avatarView.sd_cancelCurrentImageLoad()
        if let avatarURL {
            AvatarImageLoader.setImage(on: avatarView, url: avatarURL)
        } else {
            avatarView.image = nil
        }

        bodyLabel.attributedText = Self.htmlBody(cookedHTML, textColor: theme.primaryTextColor.withAlphaComponent(0.88), baseURL: baseURL)
        linkIcon.tintColor = theme.secondaryTextColor
        linkLabel.text = shareURL
        linkLabel.textColor = theme.secondaryTextColor
    }

    private static func htmlBody(_ html: String, textColor: UIColor, baseURL: String) -> NSAttributedString {
        let wrapped = """
        <div style="font-family:-apple-system;font-size:15px;line-height:1.45;color:\(textColor.hexString);">
        \(html)
        </div>
        """
        guard let data = wrapped.data(using: .utf8),
              let attr = try? NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              )
        else {
            return NSAttributedString(string: stripTags(html), attributes: [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: textColor
            ])
        }

        // Convert remaining :shortcode: in plain runs if possible
        let plain = attr.string
        if TitleEmojiRenderer.containsShortcode(plain) {
            return TitleEmojiRenderer.attributedTitle(plain, font: .systemFont(ofSize: 15), textColor: textColor, baseURL: baseURL)
        }
        return attr
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
