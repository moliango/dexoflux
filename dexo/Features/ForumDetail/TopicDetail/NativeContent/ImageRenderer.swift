import CookedHTML
import SDWebImage
import UIKit

// MARK: - TappableImageContainer

final class TappableImageContainer: UIView {
    /// URL used when tapped — prefers the full-size href over the img src.
    var imageURL: URL?
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

    init(url: URL, width: Int?, height: Int?, containerWidth: CGFloat, href: URL? = nil) {
        imageURL = href ?? url
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

        let hasOriginalSize = width != nil && height != nil

        ForumImageLoader.setImage(on: imageView, url: url) { [weak self] image, _, _, _ in
            guard let self, let image else { return }
            self.imageView.backgroundColor = .clear
            if !hasOriginalSize {
                let ratio = containerWidth / image.size.width
                self.imageHeightConstraint.constant = image.size.height * ratio
            }
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func imageTapped() {
        guard let imageURL else { return }
        delegate?.postCell(didTapImageURL: imageURL)
    }

    func cancelImageLoad() {
        imageView.sd_cancelCurrentImageLoad()
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
        guard case .image(let src, _, let width, let height, let href) = block,
              let url = URL(string: src)
        else {
            return UIView()
        }

        let hrefURL: URL? = {
            guard let href, !href.isEmpty else { return nil }
            return URL(string: href)
        }()

        let container = TappableImageContainer(
            url: url,
            width: width,
            height: height,
            containerWidth: config.contentWidth,
            href: hrefURL
        )
        container.delegate = delegate
        return container
    }
}
