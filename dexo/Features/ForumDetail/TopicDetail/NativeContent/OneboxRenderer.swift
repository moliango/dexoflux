import CookedHTML
import SDWebImage
import UIKit

enum OneboxRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .onebox = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .onebox(let sourceURL, let title, let description, let imageURL, let imageWidth, let imageHeight, let faviconURL) = block else {
            return UIView()
        }

        let container = OneboxCardView(
            sourceURL: sourceURL,
            title: title,
            description: description,
            imageURL: imageURL,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            faviconURL: faviconURL,
            containerWidth: config.contentWidth
        )
        container.delegate = delegate
        return container
    }
}

// MARK: - OneboxCardView

final class OneboxCardView: UIView {
    weak var delegate: PostCellDelegate?
    private let sourceURL: String?
    private let imageView = UIImageView()
    private let faviconView = UIImageView()

    init(sourceURL: String?, title: String?, description: String?, imageURL: String?, imageWidth: Int?, imageHeight: Int?, faviconURL: String?, containerWidth: CGFloat) {
        self.sourceURL = sourceURL
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        TopicDetailContentStyle.applySurface(
            to: self,
            backgroundColor: TopicDetailContentStyle.cardBackground,
            cornerRadius: 14,
            borderAlpha: 0.30
        )
        clipsToBounds = true

        // MARK: Header — favicon + domain

        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)

        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.spacing = 6
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerStack)

        // Favicon
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.contentMode = .scaleAspectFit
        faviconView.clipsToBounds = true
        faviconView.layer.cornerRadius = 2
        let faviconSize: CGFloat = 16

        if let faviconURL, let url = URL(string: faviconURL) {
            faviconView.sd_setImage(with: url)
            headerStack.addArrangedSubview(faviconView)
            NSLayoutConstraint.activate([
                faviconView.widthAnchor.constraint(equalToConstant: faviconSize),
                faviconView.heightAnchor.constraint(equalToConstant: faviconSize),
            ])
        }

        // Domain label
        let domainLabel = UILabel()
        domainLabel.translatesAutoresizingMaskIntoConstraints = false
        domainLabel.font = .systemFont(ofSize: 12, weight: .medium)
        domainLabel.textColor = .secondaryLabel
        if let sourceURL, let url = URL(string: sourceURL), let host = url.host {
            domainLabel.text = host
        }
        headerStack.addArrangedSubview(domainLabel)

        let headerSeparator = UIView()
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.backgroundColor = UIColor.separator.withAlphaComponent(0.22)
        headerView.addSubview(headerSeparator)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            headerStack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            headerStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -12),
            headerStack.bottomAnchor.constraint(equalTo: headerSeparator.topAnchor, constant: -10),

            headerSeparator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            headerSeparator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            headerSeparator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])

        // MARK: Body

        let bodyStack = UIStackView()
        bodyStack.axis = .vertical
        bodyStack.spacing = 0
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bodyStack)

        NSLayoutConstraint.activate([
            bodyStack.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            bodyStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let contentRow = UIStackView()
        contentRow.axis = .horizontal
        contentRow.spacing = 12
        contentRow.alignment = .top
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        contentRow.isLayoutMarginsRelativeArrangement = true
        contentRow.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        bodyStack.addArrangedSubview(contentRow)

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentRow.addArrangedSubview(textStack)

        if let title, !title.isEmpty {
            let titleLabel = UILabel()
            titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            titleLabel.textColor = .label
            titleLabel.numberOfLines = 2
            titleLabel.text = title
            textStack.addArrangedSubview(titleLabel)
        }

        if let description, !description.isEmpty {
            let descLabel = UILabel()
            descLabel.font = .systemFont(ofSize: 13)
            descLabel.textColor = .secondaryLabel
            descLabel.numberOfLines = 3
            descLabel.text = description
            textStack.addArrangedSubview(descLabel)
        }
        if (title ?? "").isEmpty, (description ?? "").isEmpty, let sourceURL {
            let fallbackLabel = UILabel()
            fallbackLabel.font = .systemFont(ofSize: 13, weight: .medium)
            fallbackLabel.textColor = .link
            fallbackLabel.numberOfLines = 2
            fallbackLabel.text = sourceURL
            textStack.addArrangedSubview(fallbackLabel)
        }

        // Thumbnail image (only for actual content images, not favicons)
        if let imageURL, let url = URL(string: imageURL) {
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = .tertiarySystemFill
            imageView.layer.cornerRadius = 6

            contentRow.addArrangedSubview(imageView)
            let thumbnailWidth = min(92, max(72, containerWidth * 0.24))
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: thumbnailWidth),
                imageView.heightAnchor.constraint(equalToConstant: 72),
            ])

            imageView.sd_setImage(with: url) { [weak self] _, _, _, _ in
                self?.imageView.backgroundColor = .clear
            }
        }

        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func cardTapped() {
        guard let sourceURL, let url = URL(string: sourceURL) else { return }
        delegate?.postCell(didTapLinkURL: url)
    }

    func cancelImageLoad() {
        imageView.sd_cancelCurrentImageLoad()
        faviconView.sd_cancelCurrentImageLoad()
    }
}
