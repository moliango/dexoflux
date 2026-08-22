import UIKit

enum CryptoChrome {
    static var accent: UIColor { AppSettings.shared.themeStyle.accentColor }
    static var screen: UIColor { AppSettings.shared.themeStyle.topicListBackgroundColor }
    static var card: UIColor { AppSettings.shared.themeStyle.topicCardBackgroundColor }
    static var border: UIColor { UIColor.separator.withAlphaComponent(0.18) }

    static func applyCard(_ view: UIView) {
        view.backgroundColor = card
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = border.cgColor
        view.clipsToBounds = true
    }

    static func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }

    static func iconBadge(symbolName: String, size: CGFloat = 44) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.backgroundColor = accent.withAlphaComponent(0.14)
        wrap.layer.cornerRadius = size / 2
        wrap.layer.cornerCurve = .continuous
        let image = UIImageView(image: UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.38, weight: .semibold)
        ))
        image.translatesAutoresizingMaskIntoConstraints = false
        image.tintColor = accent
        image.contentMode = .scaleAspectFit
        wrap.addSubview(image)
        NSLayoutConstraint.activate([
            wrap.widthAnchor.constraint(equalToConstant: size),
            wrap.heightAnchor.constraint(equalToConstant: size),
            image.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
        ])
        return wrap
    }

    static func primaryButton(title: String, symbolName: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.baseBackgroundColor = accent
        config.baseForegroundColor = .white
        config.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        config.imagePadding = 8
        config.title = title
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var next = incoming
            next.font = .systemFont(ofSize: 17, weight: .semibold)
            return next
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    static func secondaryButton(title: String, symbolName: String) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.cornerStyle = .medium
        config.baseForegroundColor = accent
        config.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        config.imagePadding = 6
        config.title = title
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var next = incoming
            next.font = .systemFont(ofSize: 14, weight: .semibold)
            return next
        }
        return UIButton(configuration: config)
    }

    static func styleField(_ field: UITextField) {
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.font = .systemFont(ofSize: 16)
        field.textColor = .label
    }

    static func styleTextView(_ textView: UITextView) {
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .label
        textView.tintColor = accent
    }
}
