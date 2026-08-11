import UIKit

/// “查看 N 个新的或更新的话题” banner — restyles for WeChat / Telegram chat themes.
final class IncomingTopicsBannerView: UIControl {
    private let iconContainer: UIView = {
        let view = UIView()
        view.layer.cornerCurve = .continuous
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.86
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "action.refresh")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let chevronView: UIImageView = {
        let view = UIImageView()
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

    private var titleTopConstraint: NSLayoutConstraint?
    private var titleCenterYConstraint: NSLayoutConstraint?
    private var subtitleHeightConstraint: NSLayoutConstraint?
    private var iconSizeConstraints: [NSLayoutConstraint] = []
    private var isFloatingStyle = true

    override var isHighlighted: Bool {
        didSet {
            DexoMotion.animate(duration: DexoMotion.quick) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
                self.alpha = self.isHighlighted ? 0.88 : 1
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
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        switch AppSettings.shared.themeStyle {
        case .telegram:
            // Compact pill sized to title — parent centers it.
            let titleW = titleLabel.intrinsicContentSize.width
            let width = min(max(titleW + 78, 168), UIScreen.main.bounds.width - 64)
            return CGSize(width: width, height: 40)
        case .weChat:
            return CGSize(width: UIView.noIntrinsicMetric, height: 44)
        default:
            return CGSize(width: UIView.noIntrinsicMetric, height: 52)
        }
    }

    func setFloating(_ isFloating: Bool) {
        isFloatingStyle = isFloating
        applyThemeStyle()
    }

    func applyThemeStyle() {
        let theme = AppSettings.shared.themeStyle
        let accent = theme.accentColor

        switch theme {
        case .telegram:
            applyTelegramStyle(accent: accent)
        case .weChat:
            applyWeChatStyle(accent: accent)
        default:
            applyDefaultStyle(theme: theme, accent: accent)
        }
    }

    // MARK: - Theme skins

    /// Telegram: solid brand-blue capsule toast (like in-app “N new messages”).
    private func applyTelegramStyle(accent: UIColor) {
        backgroundColor = accent
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 0
        layer.borderColor = UIColor.clear.cgColor
        layer.shadowColor = accent.cgColor
        layer.shadowOpacity = isFloatingStyle ? 0.28 : 0.12
        layer.shadowRadius = isFloatingStyle ? 12 : 6
        layer.shadowOffset = CGSize(width: 0, height: isFloatingStyle ? 4 : 2)

        iconContainer.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        iconContainer.layer.cornerRadius = 15
        iconView.tintColor = .white
        activityIndicator.color = .white
        chevronView.tintColor = UIColor.white.withAlphaComponent(0.85)

        let titlePoint = AppSettings.shared.effectiveInterfacePointSize(for: 15)
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: titlePoint, weight: .semibold)
        )
        titleLabel.textColor = .white

        // Single-line capsule — hide “刷新” subtitle for a cleaner TG look.
        subtitleLabel.isHidden = true
        subtitleHeightConstraint?.constant = 0
        titleTopConstraint?.isActive = false
        titleCenterYConstraint?.isActive = true

        setIconSymbol("arrow.up", pointSize: 15, weight: .bold)
        setChevronSymbol("chevron.up", pointSize: 11, weight: .semibold)
        setIconContainerSize(30)
    }

    /// WeChat: soft green tip bar matching session-list density (not iOS card chrome).
    private func applyWeChatStyle(accent: UIColor) {
        let isDark = traitCollection.userInterfaceStyle == .dark
        // Light mint wash / dark green-gray — reads as WeChat tip, not system material card.
        backgroundColor = isDark
            ? UIColor(red: 0.12, green: 0.18, blue: 0.14, alpha: 1)
            : UIColor(red: 0.91, green: 0.97, blue: 0.93, alpha: 1)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.borderWidth = 0
        layer.borderColor = UIColor.clear.cgColor
        layer.shadowOpacity = 0

        iconContainer.backgroundColor = accent
        iconContainer.layer.cornerRadius = 6
        iconView.tintColor = .white
        activityIndicator.color = accent
        chevronView.tintColor = accent.withAlphaComponent(0.7)

        let titlePoint = AppSettings.shared.effectiveInterfacePointSize(for: 14)
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: titlePoint, weight: .medium)
        )
        titleLabel.textColor = isDark ? UIColor.white.withAlphaComponent(0.92) : UIColor(red: 0.12, green: 0.35, blue: 0.20, alpha: 1)
        // Single line tip — denser like WeChat list chrome.
        subtitleLabel.isHidden = true
        subtitleHeightConstraint?.constant = 0
        titleTopConstraint?.isActive = false
        titleCenterYConstraint?.isActive = true

        setIconSymbol("arrow.up", pointSize: 13, weight: .bold)
        setChevronSymbol("chevron.up", pointSize: 11, weight: .semibold)
        setIconContainerSize(26)
    }

    private func applyDefaultStyle(theme: AppSettings.ThemeStyle, accent: UIColor) {
        backgroundColor = theme.topicCardBackgroundColor
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = accent.withAlphaComponent(0.12).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = isFloatingStyle ? 0.08 : 0.02
        layer.shadowRadius = isFloatingStyle ? 14 : 8
        layer.shadowOffset = isFloatingStyle ? CGSize(width: 0, height: 6) : CGSize(width: 0, height: 2)

        iconContainer.backgroundColor = accent.withAlphaComponent(0.14)
        iconContainer.layer.cornerRadius = 17
        iconView.tintColor = accent
        activityIndicator.color = accent
        chevronView.tintColor = .tertiaryLabel

        let titlePoint = AppSettings.shared.effectiveInterfacePointSize(for: 15)
        let subPoint = AppSettings.shared.effectiveInterfacePointSize(for: 11)
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: titlePoint, weight: .semibold)
        )
        titleLabel.textColor = .label
        subtitleLabel.isHidden = false
        subtitleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: subPoint, weight: .medium)
        )
        subtitleLabel.textColor = .secondaryLabel
        subtitleHeightConstraint?.constant = 14
        titleCenterYConstraint?.isActive = false
        titleTopConstraint?.isActive = true

        setIconSymbol("arrow.up", pointSize: 16, weight: .bold)
        setChevronSymbol("chevron.up", pointSize: 12, weight: .semibold)
        setIconContainerSize(34)
    }

    private func setIconSymbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        iconView.image = UIImage(systemName: name, withConfiguration: config)
    }

    private func setChevronSymbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        chevronView.image = UIImage(systemName: name, withConfiguration: config)
    }

    private func setIconContainerSize(_ size: CGFloat) {
        iconSizeConstraints.forEach { $0.isActive = false }
        let w = iconContainer.widthAnchor.constraint(equalToConstant: size)
        let h = iconContainer.heightAnchor.constraint(equalToConstant: size)
        iconSizeConstraints = [w, h]
        NSLayoutConstraint.activate(iconSizeConstraints)
        iconContainer.layer.cornerRadius = AppSettings.shared.themeStyle == .weChat
            ? 6
            : size / 2
    }

    private func setupUI() {
        layer.cornerCurve = .continuous
        clipsToBounds = false

        iconContainer.addSubview(iconView)
        iconContainer.addSubview(activityIndicator)
        addSubview(iconContainer)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(chevronView)

        let titleTop = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9)
        let titleCenterY = titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        titleTopConstraint = titleTop
        titleCenterYConstraint = titleCenterY
        titleCenterY.isActive = false

        let subHeight = subtitleLabel.heightAnchor.constraint(equalToConstant: 14)
        subtitleHeightConstraint = subHeight

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(lessThanOrEqualTo: iconContainer.widthAnchor, multiplier: 0.55),
            iconView.heightAnchor.constraint(lessThanOrEqualTo: iconContainer.heightAnchor, multiplier: 0.55),

            activityIndicator.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),
            titleTop,

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subHeight,

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),
        ])

        setIconContainerSize(34)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyThemeStyle()
    }
}
