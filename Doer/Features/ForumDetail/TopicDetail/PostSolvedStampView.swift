import UIKit

/// FluxDo `PostStampPainter` watermark: broken-border seal over an accepted answer.
final class PostSolvedStampView: UIView {
    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 18, weight: .black)
        return label
    }()

    private let borderLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 2.5
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "post.solved.stamp"
        clipsToBounds = false
        transform = CGAffineTransform(rotationAngle: -0.15)
        layer.addSublayer(borderLayer)
        addSubview(iconView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        borderLayer.frame = bounds
        borderLayer.path = Self.brokenStampPath(in: bounds).cgPath
    }

    func configure(acceptedAnswer: Bool, canAcceptAnswer: Bool, compact: Bool = false) {
        let scale: CGFloat = compact ? 0.78 : 1
        transform = CGAffineTransform(rotationAngle: -0.15).scaledBy(x: scale, y: scale)
        if acceptedAnswer {
            isHidden = false
            alpha = compact ? 0.22 : 0.16
            applyChrome(
                color: .systemGreen,
                symbolName: "checkmark.seal.fill",
                title: String(localized: "post.solved", defaultValue: "已解决")
            )
        } else if canAcceptAnswer {
            isHidden = false
            alpha = compact ? 0.10 : 0.06
            applyChrome(
                color: .secondaryLabel,
                symbolName: "questionmark.circle",
                title: String(localized: "post.unsolved", defaultValue: "未解决")
            )
        } else {
            isHidden = true
        }
    }

    private func applyChrome(color: UIColor, symbolName: String, title: String) {
        let symbol = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: symbol)
        iconView.tintColor = color
        titleLabel.text = title
        titleLabel.textColor = color
        let kern = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .black),
                .foregroundColor: color,
                .kern: 1.6,
            ]
        )
        titleLabel.attributedText = kern
        borderLayer.strokeColor = color.cgColor
        setNeedsLayout()
    }

    /// FluxDo `PostStampPainter`: incomplete rectangle so the seal looks stamped.
    private static func brokenStampPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let radius: CGFloat = 7
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: width * 0.1, y: 0.5))
        path.addLine(to: CGPoint(x: width - radius, y: 0.5))
        path.addQuadCurve(
            to: CGPoint(x: width - 0.5, y: radius),
            controlPoint: CGPoint(x: width - 0.5, y: 0.5)
        )
        path.addLine(to: CGPoint(x: width - 0.5, y: height * 0.7))

        path.move(to: CGPoint(x: width * 0.8, y: height - 0.5))
        path.addLine(to: CGPoint(x: radius, y: height - 0.5))
        path.addQuadCurve(
            to: CGPoint(x: 0.5, y: height - radius),
            controlPoint: CGPoint(x: 0.5, y: height - 0.5)
        )
        path.addLine(to: CGPoint(x: 0.5, y: height * 0.3))

        path.move(to: CGPoint(x: 0.5, y: height * 0.15))
        path.addLine(to: CGPoint(x: 0.5, y: radius))
        path.addQuadCurve(
            to: CGPoint(x: radius, y: 0.5),
            controlPoint: CGPoint(x: 0.5, y: 0.5)
        )
        return path
    }
}
