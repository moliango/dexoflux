import CookedHTML
import SDWebImage
import UIKit

// MARK: - TappableImageContainer

final class TappableImageContainer: UIView {
    /// URL used when tapped — prefers the full-size href over the img src.
    var imageURL: URL?
    var galleryImageURLs: [URL] = []
    weak var delegate: PostCellDelegate?

    private let imageView: SDAnimatedImageView = {
        let iv = SDAnimatedImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private var imageHeightConstraint: NSLayoutConstraint!
    private var imageWidthConstraint: NSLayoutConstraint!

    /// Discourse renders images at a reference width of 690px.
    /// Images narrower than this are displayed proportionally smaller on screen.
    private static let referenceWidth: CGFloat = 690

    private let refererBaseURL: String?
    private let sourceURL: URL
    private let loadContainerWidth: CGFloat
    private let loadHasOriginalSize: Bool
    private var didFailLoad = false

    init(
        url: URL,
        width: Int?,
        height: Int?,
        containerWidth: CGFloat,
        href: URL? = nil,
        galleryImageURLs: [URL] = [],
        refererBaseURL: String? = nil
    ) {
        imageURL = href ?? url
        self.galleryImageURLs = galleryImageURLs
        self.refererBaseURL = refererBaseURL
        self.sourceURL = url
        self.loadContainerWidth = containerWidth
        self.loadHasOriginalSize = width != nil && height != nil
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)

        let displayWidth: CGFloat
        let displayHeight: CGFloat
        if let w = width, let h = height, w > 0 {
            let fraction = min(CGFloat(w) / Self.referenceWidth, 1)
            displayWidth = containerWidth * fraction
            displayHeight = CGFloat(h) * (displayWidth / CGFloat(w))
        } else {
            displayWidth = containerWidth
            displayHeight = containerWidth * 9.0 / 16.0
        }

        let isFullWidth = displayWidth >= containerWidth

        if isFullWidth {
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: displayWidth)
        imageWidthConstraint.isActive = !isFullWidth
        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: displayHeight)
        imageHeightConstraint.isActive = true

        backgroundColor = isFullWidth ? .tertiarySystemGroupedBackground : .clear
        layer.cornerRadius = isFullWidth ? 10 : 0
        layer.cornerCurve = .continuous
        clipsToBounds = isFullWidth
        imageView.backgroundColor = .secondarySystemFill
        imageView.layer.cornerRadius = 10
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true

        // Pause GIF animation by default; resumed when visible on screen
        imageView.autoPlayAnimatedImage = false

        loadImage(url: url, containerWidth: containerWidth, hasOriginalSize: loadHasOriginalSize)

        let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
        accessibilityHint = String(
            localized: "topic.image.retry_hint",
            defaultValue: "加载失败时可点按重试"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadImage(url: URL, containerWidth: CGFloat, hasOriginalSize: Bool) {
        didFailLoad = false
        imageView.backgroundColor = .secondarySystemFill
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = nil
        imageView.image = nil

        let apply: (UIImage?) -> Void = { [weak self] image in
            guard let self else { return }
            guard let image else {
                self.didFailLoad = true
                self.imageView.backgroundColor = .tertiarySystemFill
                self.imageView.contentMode = .center
                let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
                self.imageView.image = UIImage(
                    systemName: "arrow.clockwise.circle",
                    withConfiguration: config
                )
                self.imageView.tintColor = .tertiaryLabel
                self.accessibilityLabel = String(
                    localized: "topic.image.load_failed",
                    defaultValue: "图片加载失败，点按重试"
                )
                return
            }
            self.didFailLoad = false
            self.accessibilityLabel = nil
            self.imageView.backgroundColor = .clear
            self.imageView.contentMode = .scaleAspectFill
            self.imageView.tintColor = nil
            self.imageView.image = image
            if !hasOriginalSize, image.size.width > 0 {
                let ratio = containerWidth / image.size.width
                let newHeight = image.size.height * ratio
                // Only relayout when height actually changes — avoids thrash on cache hits.
                if abs(newHeight - self.imageHeightConstraint.constant) > 1.5 {
                    self.imageHeightConstraint.constant = newHeight
                    self.invalidateIntrinsicContentSize()
                    self.superview?.setNeedsLayout()
                    self.notifyPostCellHeightChanged()
                }
            }
        }

        // Prefer FluxDo-style URLSession fetch for third-party hosts (badge / image beds).
        // Keep SDWebImage for forum hosts (secure-uploads + CF cookie semantics).
        if shouldUseExternalFetcher(for: url) {
            ExternalImageFetcher.fetch(url: url, refererBaseURL: refererBaseURL, completion: apply)
            return
        }

        ForumImageLoader.setImage(
            on: imageView,
            url: url,
            cloudflareBaseURL: refererBaseURL
        ) { image, _, _, _ in
            apply(image)
        }
    }

    private func shouldUseExternalFetcher(for url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return true }
        if let base = refererBaseURL,
           let baseHost = URL(string: base)?.host?.lowercased(),
           !baseHost.isEmpty {
            if host == baseHost || host.hasSuffix("." + baseHost) {
                return false
            }
        }
        if host == "linux.do" || host.hasSuffix(".linux.do") {
            return false
        }
        // Forum CDN still works better with SDWebImage cookie path when needed.
        if host.contains("ldstatic.com") {
            return true
        }
        return true
    }

    @objc private func imageTapped() {
        // Failed load → tap retries instead of opening the gallery (Phase 1).
        if didFailLoad {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            loadImage(
                url: sourceURL,
                containerWidth: loadContainerWidth,
                hasOriginalSize: loadHasOriginalSize
            )
            return
        }
        guard let imageURL else { return }
        let imageURLs = galleryImageURLs.isEmpty ? [imageURL] : galleryImageURLs
        delegate?.postCell(didTapImageURL: imageURL, imageURLs: imageURLs)
    }

    func cancelImageLoad() {
        imageView.sd_cancelCurrentImageLoad()
    }

    /// Bubble size changes up to `PostNativeCell` so row height updates coalesce
    /// instead of each image calling `beginUpdates` independently.
    private func notifyPostCellHeightChanged() {
        var view: UIView? = superview
        while let current = view {
            if let cell = current as? PostNativeCell {
                cell.requestHeightReconciliation()
                return
            }
            view = current.superview
        }
    }

    // MARK: - GIF Animation Control

    func startAnimating() {
        imageView.startAnimating()
    }

    func stopAnimating() {
        imageView.stopAnimating()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            imageView.startAnimating()
        } else {
            imageView.stopAnimating()
        }
    }
}

// MARK: - ImageRenderer

enum ImageRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .image = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .image(let src, _, let width, let height, let href) = block else {
            return UIView()
        }

        let primaryURL = Self.makeURL(src)
        let hrefURL = href.flatMap(Self.makeURL)

        // FluxDo-style badge/music cards: parse query params and draw a native card.
        // Prefer href (original link) when present.
        if let cardURL = hrefURL ?? primaryURL,
           let model = BadgeCardModel.parse(url: cardURL) {
            let card = BadgeCardView(model: model, containerWidth: config.contentWidth)
            card.delegate = delegate
            return card
        }

        guard let url = primaryURL else {
            return UIView()
        }

        let container = TappableImageContainer(
            url: url,
            width: width,
            height: height,
            containerWidth: config.contentWidth,
            href: hrefURL,
            galleryImageURLs: config.galleryImageURLs,
            refererBaseURL: config.baseURL
        )
        container.delegate = delegate
        return container
    }

    private static func makeURL(_ raw: String) -> URL? {
        let cleaned = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: cleaned) { return url }
        if let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
            return URL(string: encoded)
        }
        return nil
    }
}
