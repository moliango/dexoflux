import CookedHTML
import SDWebImage
import UIKit

enum VideoRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .video = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .video(let url, let thumbnailURL, let title, let width, let height, _, _) = block else {
            return UIView()
        }

        let container = VideoCardView(
            url: url,
            thumbnailURL: thumbnailURL,
            title: title,
            width: width,
            height: height,
            containerWidth: config.contentWidth
        )
        container.delegate = delegate
        return container
    }
}

// MARK: - VideoCardView

final class VideoCardView: UIView {
    weak var delegate: PostCellDelegate?
    private let videoURL: String
    private let thumbnailImageView = UIImageView()

    init(url: String, thumbnailURL: String?, title: String?, width: Int?, height: Int?, containerWidth: CGFloat) {
        self.videoURL = url
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // Thumbnail
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.backgroundColor = .black
        addSubview(thumbnailImageView)

        layer.cornerRadius = 6
        clipsToBounds = true
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.cgColor

        let imageH: CGFloat
        if let w = width, let h = height, w > 0 {
            imageH = containerWidth * CGFloat(h) / CGFloat(w)
        } else {
            imageH = containerWidth * 9.0 / 16.0
        }

        NSLayoutConstraint.activate([
            thumbnailImageView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: imageH),
            thumbnailImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if let thumbnailURL, let thumbURL = URL(string: thumbnailURL) {
            ForumImageLoader.setImage(on: thumbnailImageView, url: thumbURL)
        }

        // Play button with shadow for contrast on any background
        let playButton = UIImageView()
        playButton.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 48, weight: .ultraLight)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.white, UIColor(white: 0, alpha: 0.5)]))
        playButton.image = UIImage(systemName: "play.circle.fill", withConfiguration: symbolConfig)
        playButton.contentMode = .center
        playButton.layer.shadowColor = UIColor.black.cgColor
        playButton.layer.shadowOpacity = 0.6
        playButton.layer.shadowRadius = 8
        playButton.layer.shadowOffset = .zero
        addSubview(playButton)

        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor),
        ])

        // Title overlay at top of thumbnail with gradient
        if let title, !title.isEmpty {
            let gradientContainer = UIView()
            gradientContainer.translatesAutoresizingMaskIntoConstraints = false
            gradientContainer.isUserInteractionEnabled = false
            addSubview(gradientContainer)

            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
            titleLabel.textColor = .white
            titleLabel.numberOfLines = 2
            titleLabel.text = title
            titleLabel.layer.shadowColor = UIColor.black.cgColor
            titleLabel.layer.shadowOpacity = 0.8
            titleLabel.layer.shadowRadius = 2
            titleLabel.layer.shadowOffset = .zero
            gradientContainer.addSubview(titleLabel)

            NSLayoutConstraint.activate([
                gradientContainer.leadingAnchor.constraint(equalTo: thumbnailImageView.leadingAnchor),
                gradientContainer.trailingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor),
                gradientContainer.topAnchor.constraint(equalTo: thumbnailImageView.topAnchor),

                titleLabel.topAnchor.constraint(equalTo: gradientContainer.topAnchor, constant: 6),
                titleLabel.leadingAnchor.constraint(equalTo: gradientContainer.leadingAnchor, constant: 10),
                titleLabel.trailingAnchor.constraint(equalTo: gradientContainer.trailingAnchor, constant: -10),
                titleLabel.bottomAnchor.constraint(equalTo: gradientContainer.bottomAnchor, constant: -10),
            ])

            let gradient = CAGradientLayer()
            gradient.colors = [UIColor(white: 0, alpha: 0.6).cgColor, UIColor.clear.cgColor]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
            gradientContainer.layer.insertSublayer(gradient, at: 0)
            self.gradientLayer = gradient
        }

        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(videoTapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    private var gradientLayer: CAGradientLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = gradientLayer?.superlayer?.bounds ?? .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func videoTapped() {
        guard let url = URL(string: videoURL) else { return }
        delegate?.postCell(didTapLinkURL: url)
    }

    func cancelImageLoad() {
        thumbnailImageView.sd_cancelCurrentImageLoad()
    }
}
