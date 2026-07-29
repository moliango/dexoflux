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
    private let bodyStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        return stack
    }()
    private let dividerBottom = UIView()
    private let linkIcon = UIImageView()
    private let linkLabel = UILabel()

    private var theme: ShareImageTheme = .classic
    private let cardWidth: CGFloat = 375
    private let maxBodyHeight: CGFloat = 720
    private let maxImageHeight: CGFloat = 240
    private var bodyHeightConstraint: NSLayoutConstraint?
    private var loadGeneration = 0

    /// Fires on main when body images finished loading (success/fail) or there are no images.
    var onBodyImagesReady: (() -> Void)?

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
        bodyContainer.clipsToBounds = true

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
        bodyContainer.addSubview(bodyStack)
        addSubview(dividerBottom)
        addSubview(linkIcon)
        addSubview(linkLabel)

        let bodyHeight = bodyContainer.heightAnchor.constraint(lessThanOrEqualToConstant: maxBodyHeight)
        bodyHeightConstraint = bodyHeight

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
            metaLabel.bottomAnchor.constraint(lessThanOrEqualTo: avatarView.bottomAnchor),

            dividerTop.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 14),
            dividerTop.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dividerTop.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            dividerTop.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            bodyContainer.topAnchor.constraint(equalTo: dividerTop.bottomAnchor, constant: 12),
            bodyContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bodyContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            bodyHeight,

            bodyStack.topAnchor.constraint(equalTo: bodyContainer.topAnchor, constant: 12),
            bodyStack.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: 12),
            bodyStack.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -12),
            bodyStack.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -12),

            dividerBottom.topAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: 12),
            dividerBottom.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dividerBottom.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            dividerBottom.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

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

        linkIcon.tintColor = theme.secondaryTextColor
        linkLabel.text = shareURL
        linkLabel.textColor = theme.secondaryTextColor

        rebuildBody(cookedHTML: cookedHTML, baseURL: baseURL, textColor: theme.primaryTextColor.withAlphaComponent(0.88))
    }

    private func rebuildBody(cookedHTML: String, baseURL: String, textColor: UIColor) {
        loadGeneration += 1
        let generation = loadGeneration

        bodyStack.arrangedSubviews.forEach {
            bodyStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let segments = ShareImageBodyComposer.segments(from: cookedHTML, baseURL: baseURL)
        let imageURLs = ShareImageBodyComposer.imageURLs(in: segments)
        let contentWidth = cardWidth - 16 * 2 - 12 * 2

        if segments.isEmpty {
            let label = makeTextLabel(
                String(localized: "share.image.empty_body", defaultValue: "（无正文）"),
                color: textColor.withAlphaComponent(0.6)
            )
            bodyStack.addArrangedSubview(label)
            notifyBodyReady(generation: generation)
            return
        }

        final class PendingCounter {
            var value: Int
            init(_ value: Int) { self.value = value }
        }
        let pending = PendingCounter(imageURLs.count)

        for segment in segments {
            switch segment {
            case .text(let text):
                bodyStack.addArrangedSubview(makeTextLabel(text, color: textColor))

            case .image(let url):
                let imageView = makeImageView(contentWidth: contentWidth)
                bodyStack.addArrangedSubview(imageView)
                loadImage(url, into: imageView, baseURL: baseURL, contentWidth: contentWidth, generation: generation) { [weak self] in
                    pending.value -= 1
                    if pending.value <= 0 {
                        self?.notifyBodyReady(generation: generation)
                    }
                }

            case .moreImages(let count):
                let footnote = makeTextLabel(
                    String(format: String(localized: "share.image.more_images", defaultValue: "还有 %d 张图未展示"), count),
                    color: textColor.withAlphaComponent(0.65)
                )
                footnote.font = .systemFont(ofSize: 13, weight: .medium)
                bodyStack.addArrangedSubview(footnote)
            }
        }

        if imageURLs.isEmpty {
            notifyBodyReady(generation: generation)
        }
    }

    private func makeTextLabel(_ text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15)
        label.textColor = color
        if TitleEmojiRenderer.containsShortcode(text) {
            label.attributedText = TitleEmojiRenderer.attributedTitle(
                text,
                font: .systemFont(ofSize: 15),
                textColor: color,
                baseURL: ""
            )
        } else {
            label.text = text
        }
        return label
    }

    private func makeImageView(contentWidth: CGFloat) -> UIImageView {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = theme.borderColor.withAlphaComponent(0.35)
        imageView.heightAnchor.constraint(equalToConstant: min(maxImageHeight, contentWidth * 0.56)).isActive = true
        return imageView
    }

    private func loadImage(
        _ url: URL,
        into imageView: UIImageView,
        baseURL: String,
        contentWidth: CGFloat,
        generation: Int,
        completion: @escaping () -> Void
    ) {
        let finish: (UIImage?) -> Void = { [weak self, weak imageView] image in
            DispatchQueue.main.async {
                guard let self, let imageView, self.loadGeneration == generation else {
                    completion()
                    return
                }
                if let image {
                    imageView.image = image
                    imageView.contentMode = .scaleAspectFill
                    self.updateImageHeight(imageView, image: image, contentWidth: contentWidth)
                } else {
                    imageView.image = UIImage(systemName: "photo")
                    imageView.tintColor = self.theme.secondaryTextColor
                    imageView.contentMode = .scaleAspectFit
                }
                completion()
            }
        }

        if let cached = SDImageCache.shared.imageFromCache(forKey: url.absoluteString) {
            finish(cached)
            return
        }

        ExternalImageFetcher.fetch(url: url, refererBaseURL: baseURL) { image in
            if let image {
                SDImageCache.shared.store(image, forKey: url.absoluteString, completion: nil)
            }
            finish(image)
        }
    }

    private func updateImageHeight(_ imageView: UIImageView, image: UIImage, contentWidth: CGFloat) {
        let ratio = image.size.height / max(image.size.width, 1)
        var height = contentWidth * ratio
        height = min(max(height, 80), maxImageHeight)
        imageView.constraints
            .filter { $0.firstAttribute == .height && $0.secondItem == nil }
            .forEach { $0.isActive = false }
        imageView.heightAnchor.constraint(equalToConstant: height).isActive = true
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func notifyBodyReady(generation: Int) {
        guard loadGeneration == generation else { return }
        onBodyImagesReady?()
    }
}
