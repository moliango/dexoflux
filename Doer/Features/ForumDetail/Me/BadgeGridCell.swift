import SDWebImage
import UIKit

/// FluxDo my-badges grid card (`_buildBadgeItem`).
final class BadgeGridCell: UICollectionViewCell {
    static let reuseIdentifier = "BadgeGridCell"

    private let cardView = UIView()
    private let iconWell = UIView()
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let countPill = UILabel()

    private var badgeType: DiscourseBadge.BadgeType = .bronze

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.sd_cancelCurrentImageLoad()
        iconView.image = nil
        nameLabel.text = nil
        countPill.isHidden = true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyChrome()
    }

    func configure(userBadge: DiscourseUserBadge, baseURL: String) {
        let badge = userBadge.badge
        badgeType = badge?.type ?? .bronze
        nameLabel.text = badge?.name ?? String(localized: "badges.unknown")
        nameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .semibold,
            fallback: .systemFont(ofSize: 14, weight: .semibold)
        )

        let count = userBadge.count
        if count > 1 {
            countPill.isHidden = false
            countPill.text = "×\(count)"
            countPill.textColor = badgeType.color
            countPill.backgroundColor = badgeType.color.withAlphaComponent(0.15)
            countPill.layer.borderColor = badgeType.color.withAlphaComponent(0.30).cgColor
        } else {
            countPill.isHidden = true
        }

        BadgeUIStyle.badgeIconImage(
            icon: badge?.icon,
            imageURL: badge?.imageURL,
            type: badgeType,
            baseURL: baseURL,
            pointSize: 22,
            into: iconView
        )
        applyChrome()
    }

    private func setupUI() {
        contentView.backgroundColor = .clear
        backgroundColor = .clear

        cardView.translatesAutoresizingMaskIntoConstraints = false
        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        countPill.translatesAutoresizingMaskIntoConstraints = false

        iconWell.layer.cornerRadius = 24
        iconWell.layer.cornerCurve = .continuous

        iconView.contentMode = .scaleAspectFit

        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.textColor = .label

        countPill.font = .monospacedDigitSystemFont(ofSize: 11, weight: .heavy)
        countPill.textAlignment = .center
        countPill.layer.cornerRadius = 12
        countPill.layer.cornerCurve = .continuous
        countPill.layer.borderWidth = 1
        countPill.clipsToBounds = true

        contentView.addSubview(cardView)
        cardView.addSubview(iconWell)
        iconWell.addSubview(iconView)
        cardView.addSubview(nameLabel)
        cardView.addSubview(countPill)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconWell.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            iconWell.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            iconWell.widthAnchor.constraint(equalToConstant: 48),
            iconWell.heightAnchor.constraint(equalToConstant: 48),

            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.topAnchor.constraint(equalTo: iconWell.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12),

            countPill.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            countPill.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10),
            countPill.heightAnchor.constraint(equalToConstant: 22),
            countPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])
        countPill.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func applyChrome() {
        BadgeUIStyle.applyCardChrome(to: cardView, type: badgeType)
        iconWell.backgroundColor = BadgeUIStyle.iconWellBackground(trait: traitCollection)
        let medal = badgeType.color
        iconWell.layer.shadowColor = medal.cgColor
        iconWell.layer.shadowOpacity = 0.20
        iconWell.layer.shadowRadius = 10
        iconWell.layer.shadowOffset = CGSize(width: 0, height: 4)
    }
}
