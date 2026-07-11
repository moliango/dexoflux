import UIKit

enum UserProfileFormatting {
    static func displayName(profile: DiscourseUserProfile?, fallbackUsername: String) -> String {
        if let name = profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return profile?.username ?? fallbackUsername
    }

    static func cleanBio(_ bio: String?) -> String? {
        guard let bio, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let stripped = bio
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = stripped.data(using: .utf8),
           let decoded = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
           ).string.trimmingCharacters(in: .whitespacesAndNewlines),
           !decoded.isEmpty {
            return decoded
        }

        return stripped.isEmpty ? nil : stripped
    }

    static func trustLevelText(_ level: Int?) -> String? {
        switch level {
        case 0: return String(localized: "me.profile.level_0")
        case 1: return String(localized: "me.profile.level_1")
        case 2: return String(localized: "me.profile.level_2")
        case 3: return String(localized: "me.profile.level_3")
        case 4: return String(localized: "me.profile.level_4")
        default: return nil
        }
    }

    static func compactNumber(_ value: Int?) -> String {
        guard let value else { return "--" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        if value >= 10_000 {
            let shortValue = Double(value) / 10_000
            return "\(formatter.string(from: NSNumber(value: shortValue)) ?? "\(shortValue)")w"
        }
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func duration(seconds: Int?) -> String {
        guard let seconds else { return "--" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.day, .hour] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(seconds)) ?? "--"
    }

    static func joinedDate(_ dateString: String?) -> String {
        guard let date = parsedDate(dateString) else { return "--" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func shortDate(_ dateString: String?) -> String {
        guard let date = parsedDate(dateString) else { return "--" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    static func relativeDate(_ dateString: String?) -> String {
        guard let date = parsedDate(dateString) else { return "--" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func parsedDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return isoWithFraction.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)
    }
}

final class UserProfileStatView: UIControl {
    private let valueLabel = UILabel()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 17,
            weight: .bold,
            fallback: .systemFont(ofSize: 17, weight: .bold)
        )
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center

        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 12,
            weight: .medium,
            fallback: .systemFont(ofSize: 12, weight: .medium)
        )
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75

        let labelStack = UIStackView(arrangedSubviews: [valueLabel, titleLabel])
        labelStack.axis = .vertical
        labelStack.alignment = .center
        labelStack.spacing = 2
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labelStack)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            labelStack.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            labelStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            labelStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            labelStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    func configure(title: String, value: String, symbolName: String, tintColor: UIColor, isTappable: Bool = false) {
        valueLabel.text = value
        titleLabel.text = title
        iconView.image = UIImage(systemName: symbolName)
        iconView.tintColor = tintColor
        backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        isUserInteractionEnabled = isTappable
        accessibilityTraits = isTappable ? [.button] : [.staticText]
        accessibilityLabel = "\(title) \(value)"
    }
}

final class UserProfileActionCard: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        accessibilityTraits = .button

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 15,
            weight: .semibold,
            fallback: .systemFont(ofSize: 15, weight: .semibold)
        )
        titleLabel.textColor = .label

        subtitleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 12,
            weight: .regular,
            fallback: .systemFont(ofSize: 12)
        )
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.isUserInteractionEnabled = false

        addSubview(iconView)
        addSubview(textStack)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -12),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
        ])
    }

    func configure(title: String, subtitle: String, symbolName: String, tintColor: UIColor) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        iconView.image = UIImage(systemName: symbolName)
        iconView.tintColor = tintColor
        backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        accessibilityLabel = "\(title)，\(subtitle)"
    }
}
