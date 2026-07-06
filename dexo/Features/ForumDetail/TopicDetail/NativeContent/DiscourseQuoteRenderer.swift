import CookedHTML
import UIKit

enum DiscourseQuoteRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        guard case .discourseQuote(_, _, _, _, _, _, let content) = block else { return false }
        return NativeContentRenderer.canRenderNatively(content)
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .discourseQuote(let username, let avatarURL, let topicTitle, let topicURL, let categoryName, let categoryURL, let content) = block else {
            return UIView()
        }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        TopicDetailContentStyle.applySurface(
            to: container,
            backgroundColor: TopicDetailContentStyle.mutedBackground,
            cornerRadius: 14,
            borderAlpha: 0.24
        )
        container.clipsToBounds = true

        // Header: avatar + (username OR topic title + category badge)
        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.spacing = 6
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerStack)

        let avatarSize: CGFloat = 20
        let avatarImageView = UIImageView()
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarImageView.backgroundColor = .secondarySystemFill
        headerStack.addArrangedSubview(avatarImageView)

        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),
        ])

        AvatarImageLoader.setImage(
            on: avatarImageView,
            url: AvatarImageLoader.url(from: avatarURL, baseURL: config.baseURL ?? "", size: 48),
            placeholder: UIImage(systemName: "person.crop.circle")
        )

        if let topicTitle, !topicTitle.isEmpty {
            // Topic-link variant: title button + optional category badge
            let titleButton = UIButton(type: .system)
            titleButton.setTitle(topicTitle, for: .normal)
            titleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            titleButton.titleLabel?.lineBreakMode = .byTruncatingTail
            titleButton.setTitleColor(.link, for: .normal)
            titleButton.contentHorizontalAlignment = .leading
            titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            if let topicURL, let url = URL(string: topicURL) {
                titleButton.addAction(UIAction { _ in
                    delegate?.postCell(didTapLinkURL: url)
                }, for: .touchUpInside)
            }
            headerStack.addArrangedSubview(titleButton)

            if let categoryName, !categoryName.isEmpty {
                let badge = CategoryBadgeView(name: categoryName)
                badge.setContentHuggingPriority(.required, for: .horizontal)
                badge.setContentCompressionResistancePriority(.required, for: .horizontal)
                if let categoryURL, let url = URL(string: categoryURL) {
                    let tap = UITapGestureRecognizer()
                    badge.addGestureRecognizer(tap)
                    badge.isUserInteractionEnabled = true
                    tap.addTarget(badge, action: #selector(CategoryBadgeView.handleTap))
                    badge.tapAction = { delegate?.postCell(didTapLinkURL: url) }
                }
                headerStack.addArrangedSubview(badge)
            }
        } else if let username, !username.isEmpty {
            // Username variant (existing behavior)
            let nameLabel = UILabel()
            nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            nameLabel.textColor = .secondaryLabel
            nameLabel.text = username
            headerStack.addArrangedSubview(nameLabel)
        }

        // Vertical bar + content
        let bar = UIView()
        bar.backgroundColor = UIColor.systemTeal.withAlphaComponent(0.72)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.layer.cornerRadius = 2
        container.addSubview(bar)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentStack)

        let quoteConfig = NativeRenderConfig(
            baseFont: config.baseFont.withSize(config.baseFont.pointSize - 1),
            baseColor: UIColor.label.withAlphaComponent(0.78),
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: config.contentWidth - 44,
            baseURL: config.baseURL
        )

        let views = NativeContentRenderer.renderBlocks(content, config: quoteConfig, delegate: delegate)
        for view in views {
            contentStack.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            bar.widthAnchor.constraint(equalToConstant: 4),

            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            headerStack.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            { let c = headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14); c.priority = .init(999); return c }(),

            contentStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            { let c = contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14); c.priority = .init(999); return c }(),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        return container
    }
}

// MARK: - Category Badge

private class CategoryBadgeView: UIView {
    var tapAction: (() -> Void)?

    init(name: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = name
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func handleTap() {
        tapAction?()
    }
}
