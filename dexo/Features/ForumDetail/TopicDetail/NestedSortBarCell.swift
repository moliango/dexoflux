import UIKit

/// Horizontal FluxDo-style sort chips (old / new / top) shown under OP in nested tree mode.
final class NestedSortBarCell: UITableViewCell {
    static let reuseIdentifier = "NestedSortBarCell"

    var onSelectSort: ((NestedReplySort) -> Void)?

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var buttons: [NestedReplySort: UIButton] = [:]
    private var currentSort: NestedReplySort = .old

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            stack.heightAnchor.constraint(equalToConstant: 32)
        ])

        for sort in NestedReplySort.allCases {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle(sort.title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.layer.cornerRadius = 14
            button.layer.cornerCurve = .continuous
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            button.accessibilityLabel = sort.title
            button.addAction(UIAction { [weak self] _ in
                self?.onSelectSort?(sort)
            }, for: .touchUpInside)
            buttons[sort] = button
            stack.addArrangedSubview(button)
        }
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(selected: NestedReplySort) {
        currentSort = selected
        applyTheme()
    }

    func applyTheme() {
        let accent = AppSettings.shared.themeStyle.accentColor
        for (sort, button) in buttons {
            let selected = sort == currentSort
            button.isUserInteractionEnabled = !selected
            button.accessibilityTraits = selected ? [.button, .selected] : .button
            if selected {
                button.backgroundColor = accent.withAlphaComponent(0.16)
                button.setTitleColor(accent, for: .normal)
            } else {
                button.backgroundColor = UIColor.tertiarySystemFill.withAlphaComponent(0.8)
                button.setTitleColor(.secondaryLabel, for: .normal)
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }
}
