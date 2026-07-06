import UIKit

final class CategoryCell: UITableViewCell {
    static let reuseIdentifier = "CategoryCell"

    private let colorView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let topicCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let subcategoryStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private var subcategoryStackBottomWithDesc: NSLayoutConstraint!
    private var descriptionBottomNoSubs: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        accessoryType = .disclosureIndicator

        contentView.addSubview(colorView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(topicCountLabel)
        contentView.addSubview(subcategoryStack)

        subcategoryStackBottomWithDesc = subcategoryStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        descriptionBottomNoSubs = descriptionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)

        NSLayoutConstraint.activate([
            colorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            colorView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            colorView.widthAnchor.constraint(equalToConstant: 20),
            colorView.heightAnchor.constraint(equalToConstant: 20),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: colorView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: topicCountLabel.leadingAnchor, constant: -10),

            topicCountLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            topicCountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            descriptionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            descriptionLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            subcategoryStack.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 6),
            subcategoryStack.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subcategoryStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -40),
        ])
    }

    func configure(with category: DiscourseCategory) {
        nameLabel.text = category.name
        colorView.backgroundColor = Self.color(fromHex: category.color) ?? .systemGray

        if let excerpt = category.descriptionExcerpt, !excerpt.isEmpty {
            descriptionLabel.text = excerpt.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        } else {
            descriptionLabel.text = nil
        }

        topicCountLabel.text = "\(category.topicCount)"

        subcategoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let subs = category.subcategoryList ?? []
        if subs.isEmpty {
            subcategoryStack.isHidden = true
            subcategoryStackBottomWithDesc.isActive = false
            descriptionBottomNoSubs.isActive = true
        } else {
            subcategoryStack.isHidden = false
            descriptionBottomNoSubs.isActive = false
            subcategoryStackBottomWithDesc.isActive = true
            for sub in subs {
                let tag = makeSubcategoryTag(name: sub.displayName(parent: category), hex: sub.color)
                subcategoryStack.addArrangedSubview(tag)
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        descriptionLabel.text = nil
        topicCountLabel.text = nil
        colorView.backgroundColor = .systemGray
        subcategoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    // MARK: - Helpers

    private func makeSubcategoryTag(name: String, hex: String) -> UIView {
        let label = UILabel()
        label.text = name
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = Self.color(fromHex: hex) ?? .systemGray
        dot.layer.cornerRadius = 4
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        return stack
    }

    private static func color(fromHex hex: String) -> UIColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
