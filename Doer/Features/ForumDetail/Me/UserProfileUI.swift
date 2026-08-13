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
        // Recover `:shortcode:` from emoji <img> before flattening so signatures keep Discourse emojis.
        let recovered = bio.contains("<")
            ? TitleEmojiRenderer.recoverShortcodesFromHTML(bio)
            : bio
        let cleaned = CookedContentPipeline.plainTextPreview(fromCooked: recovered)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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

    nonisolated static func relativeDate(_ dateString: String?) -> String {
        guard let date = parsedDate(dateString) else { return "--" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    nonisolated private static func parsedDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return isoWithFraction.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)
    }
}

/// FluxDo-aligned geometry for the compact user card (avatar stamps out of the top edge).
enum UserProfileCardLayout {
    static let avatarRadius: CGFloat = 38
    static let avatarOverflow: CGFloat = 24
    static let avatarBorderWidth: CGFloat = 3
    static let avatarDiameter: CGFloat = avatarRadius * 2
    /// Body leading inset plus this spacer puts the name 8pt past the avatar.
    static let identityLeading: CGFloat = avatarDiameter + 8
    static let cardCornerRadius: CGFloat = 20
    static let bodyTop: CGFloat = 12
    static let bodyHorizontal: CGFloat = 16
    static let bodyBottom: CGFloat = 16
    static let screenMargin: CGFloat = 16
    static let dockedTopGap: CGFloat = 6
    static let actionHeight: CGFloat = 40
    static let nameSize: CGFloat = 20
    static let usernameSize: CGFloat = 14
    static let metaSize: CGFloat = 13
}

/// Compact card loading placeholder — mirrors identity, bio, chips, and actions.
final class UserProfileCardSkeletonView: DoerSkeletonPlaceholderView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        let name = makeSkeletonBlock(cornerRadius: 7)
        let username = makeSkeletonBlock(cornerRadius: 5)
        let bio1 = makeSkeletonBlock(cornerRadius: 4)
        let bio2 = makeSkeletonBlock(cornerRadius: 4)
        let chip1 = makeSkeletonBlock(cornerRadius: 8)
        let chip2 = makeSkeletonBlock(cornerRadius: 8)
        let meta1 = makeSkeletonBlock(cornerRadius: 4)
        let meta2 = makeSkeletonBlock(cornerRadius: 4)
        let action1 = makeSkeletonBlock(cornerRadius: 12)
        let action2 = makeSkeletonBlock(cornerRadius: 12)
        let viewProfile = makeSkeletonBlock(cornerRadius: 12)
        let more = makeSkeletonBlock(cornerRadius: 12)

        [
            name, username, bio1, bio2, chip1, chip2, meta1, meta2,
            action1, action2, viewProfile, more,
        ].forEach { skeletonContentView.addSubview($0) }

        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: skeletonContentView.topAnchor, constant: 12),
            name.leadingAnchor.constraint(
                equalTo: skeletonContentView.leadingAnchor,
                constant: UserProfileCardLayout.identityLeading
            ),
            name.widthAnchor.constraint(equalToConstant: 140),
            name.heightAnchor.constraint(equalToConstant: 22),

            username.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 8),
            username.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            username.widthAnchor.constraint(equalToConstant: 168),
            username.heightAnchor.constraint(equalToConstant: 14),

            bio1.topAnchor.constraint(equalTo: username.bottomAnchor, constant: 22),
            bio1.leadingAnchor.constraint(equalTo: skeletonContentView.leadingAnchor, constant: 16),
            bio1.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor, constant: -16),
            bio1.heightAnchor.constraint(equalToConstant: 12),

            bio2.topAnchor.constraint(equalTo: bio1.bottomAnchor, constant: 8),
            bio2.leadingAnchor.constraint(equalTo: bio1.leadingAnchor),
            bio2.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor, constant: -72),
            bio2.heightAnchor.constraint(equalToConstant: 12),

            chip1.topAnchor.constraint(equalTo: bio2.bottomAnchor, constant: 12),
            chip1.leadingAnchor.constraint(equalTo: bio1.leadingAnchor),
            chip1.widthAnchor.constraint(equalToConstant: 72),
            chip1.heightAnchor.constraint(equalToConstant: 24),

            chip2.centerYAnchor.constraint(equalTo: chip1.centerYAnchor),
            chip2.leadingAnchor.constraint(equalTo: chip1.trailingAnchor, constant: 8),
            chip2.widthAnchor.constraint(equalToConstant: 118),
            chip2.heightAnchor.constraint(equalToConstant: 24),

            meta1.topAnchor.constraint(equalTo: chip1.bottomAnchor, constant: 14),
            meta1.leadingAnchor.constraint(equalTo: bio1.leadingAnchor),
            meta1.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor, constant: -28),
            meta1.heightAnchor.constraint(equalToConstant: 11),

            meta2.topAnchor.constraint(equalTo: meta1.bottomAnchor, constant: 8),
            meta2.leadingAnchor.constraint(equalTo: bio1.leadingAnchor),
            meta2.widthAnchor.constraint(equalToConstant: 180),
            meta2.heightAnchor.constraint(equalToConstant: 11),

            action1.topAnchor.constraint(equalTo: meta2.bottomAnchor, constant: 16),
            action1.leadingAnchor.constraint(equalTo: bio1.leadingAnchor),
            action1.heightAnchor.constraint(equalToConstant: UserProfileCardLayout.actionHeight),

            action2.topAnchor.constraint(equalTo: action1.topAnchor),
            action2.leadingAnchor.constraint(equalTo: action1.trailingAnchor, constant: 8),
            action2.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor, constant: -16),
            action2.heightAnchor.constraint(equalToConstant: UserProfileCardLayout.actionHeight),
            action2.widthAnchor.constraint(equalTo: action1.widthAnchor),

            viewProfile.topAnchor.constraint(equalTo: action1.bottomAnchor, constant: 8),
            viewProfile.leadingAnchor.constraint(equalTo: bio1.leadingAnchor),
            viewProfile.heightAnchor.constraint(equalToConstant: UserProfileCardLayout.actionHeight),
            viewProfile.bottomAnchor.constraint(equalTo: skeletonContentView.bottomAnchor, constant: -16),

            more.topAnchor.constraint(equalTo: viewProfile.topAnchor),
            more.leadingAnchor.constraint(equalTo: viewProfile.trailingAnchor, constant: 8),
            more.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor, constant: -16),
            more.widthAnchor.constraint(equalToConstant: UserProfileCardLayout.actionHeight),
            more.heightAnchor.constraint(equalToConstant: UserProfileCardLayout.actionHeight),
        ])
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyThemeStyle() {
        applySkeletonTheme(
            backgroundColor: .clear,
            blockColor: UIColor.secondarySystemFill
        )
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
