import UIKit

/// Card-style draft row for standard / Xiaohongshu themes (chat themes use session cells).
final class DraftCell: UITableViewCell {
    static let reuseIdentifier = "DraftCell"
    static let estimatedHeight: CGFloat = 96

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        view.layer.cornerRadius = AppSettings.shared.themeStyle.chromeCornerRadius
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let kindBadge = DraftKindBadgeView()

    private let taxonomyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let excerptLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private lazy var metaRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [kindBadge, spacer, timeLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var textStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, taxonomyLabel, metaRow, excerptLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        iconContainer.addSubview(iconView)
        contentView.addSubview(cardView)
        cardView.addSubview(iconContainer)
        cardView.addSubview(textStack)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            iconContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            iconContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 13),
            iconContainer.widthAnchor.constraint(equalToConstant: 36),
            iconContainer.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -10),

            metaRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
    }

    func configure(
        title: String,
        excerpt: String?,
        timeText: String?,
        kindTitle: String,
        taxonomyText: String?,
        symbolName: String,
        accent: UIColor
    ) {
        applyThemeStyle(accent: accent)
        titleLabel.text = title
        taxonomyLabel.text = taxonomyText
        taxonomyLabel.isHidden = taxonomyText == nil
        taxonomyLabel.textColor = accent.withAlphaComponent(0.82)
        let cleaned = excerpt?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        excerptLabel.text = cleaned.flatMap { $0.isEmpty ? nil : String($0.prefix(140)) }
        excerptLabel.isHidden = excerptLabel.text == nil
        timeLabel.text = timeText
        kindBadge.configure(text: kindTitle, accent: accent)

        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: config)
        iconView.tintColor = accent
        iconContainer.backgroundColor = accent.withAlphaComponent(0.12)
    }

    private func applyThemeStyle(accent: UIColor) {
        let theme = AppSettings.shared.themeStyle
        cardView.backgroundColor = theme.topicCardBackgroundColor
        cardView.layer.cornerRadius = theme.chromeCornerRadius
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 15, weight: .semibold)
        )
        excerptLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 12, weight: .regular)
        )
        taxonomyLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 12, weight: .medium)
        )
        timeLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 12, weight: .regular)
        )
        titleLabel.textColor = .label
        excerptLabel.textColor = .secondaryLabel
        timeLabel.textColor = .tertiaryLabel
        iconView.tintColor = accent
        iconContainer.backgroundColor = accent.withAlphaComponent(0.12)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        taxonomyLabel.text = nil
        taxonomyLabel.isHidden = false
        excerptLabel.text = nil
        excerptLabel.isHidden = false
        timeLabel.text = nil
        kindBadge.prepareForReuse()
        iconView.image = nil
    }
}

private final class DraftKindBadgeView: UIView {
    private let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stackView.addArrangedSubview(label)
        addSubview(stackView)
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, accent: UIColor) {
        label.text = text
        label.textColor = accent
        label.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 11, weight: .medium)
        )
        backgroundColor = accent.withAlphaComponent(0.12)
        layer.borderColor = accent.withAlphaComponent(0.18).cgColor
    }

    func prepareForReuse() {
        label.text = nil
    }
}
