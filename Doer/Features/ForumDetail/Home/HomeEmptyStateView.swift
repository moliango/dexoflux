import UIKit

final class HomeEmptyStateView: UIView {
    var onRefresh: (() -> Void)?

    private let cardView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 24
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconContainerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 22
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right.fill", withConfiguration: config))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "home.empty.title")
        label.font = AppSettings.shared.appInterfaceFont(
            ofSize: 16,
            weight: .semibold,
            fallback: .systemFont(ofSize: 16, weight: .semibold)
        )
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "home.empty.subtitle")
        label.font = AppSettings.shared.appInterfaceFont(
            ofSize: 13,
            weight: .regular,
            fallback: .systemFont(ofSize: 13, weight: .regular)
        )
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let refreshButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "action.refresh")
        config.image = UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = AppSettings.shared.appInterfaceFont(
                ofSize: 13,
                weight: .semibold,
                fallback: .systemFont(ofSize: 13, weight: .semibold)
            )
            return a
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        alpha = 0
        translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 7
        textStack.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconView)
        cardView.addSubview(textStack)
        cardView.addSubview(refreshButton)
        addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconContainerView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 24),
            iconContainerView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 44),
            iconContainerView.heightAnchor.constraint(equalToConstant: 44),

            iconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            textStack.topAnchor.constraint(equalTo: iconContainerView.bottomAnchor, constant: 14),
            textStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),

            refreshButton.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: 18),
            refreshButton.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            refreshButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24),
        ])

        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        titleLabel.text = String(localized: "home.empty.title")
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 16,
            weight: .semibold,
            fallback: .systemFont(ofSize: 16, weight: .semibold)
        )
        subtitleLabel.text = String(localized: "home.empty.subtitle")
        subtitleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 13,
            weight: .regular,
            fallback: .systemFont(ofSize: 13, weight: .regular)
        )
        cardView.backgroundColor = themeStyle.topicCardBackgroundColor
        cardView.layer.borderColor = themeStyle.accentColor.withAlphaComponent(0.12).cgColor
        cardView.layer.shadowColor = themeStyle.accentColor.cgColor
        cardView.layer.shadowOpacity = 0.06
        cardView.layer.shadowRadius = 18
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)

        iconContainerView.backgroundColor = themeStyle.accentColor.withAlphaComponent(0.14)
        iconView.tintColor = themeStyle.accentColor

        var config = refreshButton.configuration ?? UIButton.Configuration.filled()
        config.title = String(localized: "action.refresh")
        config.baseBackgroundColor = themeStyle.accentColor
        config.baseForegroundColor = .white
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = AppSettings.shared.appInterfaceFont(
                ofSize: 13,
                weight: .semibold,
                fallback: .systemFont(ofSize: 13, weight: .semibold)
            )
            return a
        }
        refreshButton.configuration = config
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        guard isHidden == visible else { return }
        if visible {
            isHidden = false
            transform = CGAffineTransform(translationX: 0, y: 8)
        }
        let changes = {
            self.alpha = visible ? 1 : 0
            self.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 8)
        }
        let finish: (UIViewAnimatingPosition) -> Void = { _ in
            if !visible {
                self.isHidden = true
            }
        }
        if animated {
            DoerMotion.animate(duration: DoerMotion.short, animations: changes, completion: finish)
        } else {
            changes()
            finish(.end)
        }
    }

    @objc private func refreshTapped() {
        onRefresh?()
    }
}
