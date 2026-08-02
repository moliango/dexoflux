import UIKit

final class IncomingTopicsBannerView: UIControl {
    private let iconContainer: UIView = {
        let view = UIView()
        view.backgroundColor = AppSettings.shared.themeStyle.accentColor.withAlphaComponent(0.14)
        view.layer.cornerRadius = 17
        view.layer.cornerCurve = .continuous
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let view = UIImageView(image: UIImage(systemName: "arrow.up", withConfiguration: config))
        view.tintColor = AppSettings.shared.themeStyle.accentColor
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.86
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "action.refresh")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let chevronView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let view = UIImageView(image: UIImage(systemName: "chevron.up", withConfiguration: config))
        view.tintColor = .tertiaryLabel
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    override var isHighlighted: Bool {
        didSet {
            DexoMotion.animate(duration: DexoMotion.quick) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
                self.alpha = self.isHighlighted ? 0.82 : 1
            }
        }
    }

    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.72
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isLoading: Bool) {
        titleLabel.text = title
        applyThemeStyle()
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        chevronView.isHidden = isLoading
        iconView.isHidden = isLoading
        activityIndicator.isHidden = !isLoading
        accessibilityLabel = title
        accessibilityTraits = [.button]
    }

    func setFloating(_ isFloating: Bool) {
        layer.shadowOpacity = isFloating ? 0.08 : 0.02
        layer.shadowRadius = isFloating ? 14 : 8
        layer.shadowOffset = isFloating ? CGSize(width: 0, height: 6) : CGSize(width: 0, height: 2)
    }

    func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        backgroundColor = themeStyle.topicCardBackgroundColor
        layer.borderColor = themeStyle.accentColor.withAlphaComponent(0.12).cgColor
        iconContainer.backgroundColor = themeStyle.accentColor.withAlphaComponent(0.14)
        iconView.tintColor = themeStyle.accentColor
        activityIndicator.color = themeStyle.accentColor
    }

    private func setupUI() {
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 5)

        iconContainer.addSubview(iconView)
        iconContainer.addSubview(activityIndicator)
        addSubview(iconContainer)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(chevronView)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 34),
            iconContainer.heightAnchor.constraint(equalToConstant: 34),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),

            activityIndicator.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -10),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),
        ])
    }
}
