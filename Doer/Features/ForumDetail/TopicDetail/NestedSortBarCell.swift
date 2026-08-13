import UIKit

/// Horizontal FluxDo-style sort chips (top / new / old) shown under OP in nested tree mode.
final class NestedSortBarCell: UITableViewCell {
    static let reuseIdentifier = "NestedSortBarCell"

    var onSelectSort: ((NestedReplySort) -> Void)?

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.clipsToBounds = false
        return scroll
    }()

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
        contentView.clipsToBounds = false
        clipsToBounds = false

        contentView.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            scrollView.heightAnchor.constraint(equalToConstant: 32),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        for sort in NestedReplySort.chipOrder {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle(sort.title, for: .normal)
            button.titleLabel?.font = TopicDetailTypography.chromeFont(.sortChip, weight: .semibold)
            button.layer.cornerRadius = 14
            button.layer.cornerCurve = .continuous
            var config = UIButton.Configuration.plain()
            config.title = sort.title
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            button.configuration = config
            button.accessibilityLabel = sort.title
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        for (sort, button) in buttons {
            button.setTitle(sort.title, for: .normal)
            button.titleLabel?.font = TopicDetailTypography.chromeFont(.sortChip, weight: .semibold)
            button.accessibilityLabel = sort.title
        }
        applyTheme()
    }

    func applyTheme() {
        let accent = AppSettings.shared.themeStyle.accentColor
        for (sort, button) in buttons {
            let selected = sort == currentSort
            button.isUserInteractionEnabled = !selected
            button.accessibilityTraits = selected ? [.button, .selected] : .button
            if selected {
                button.backgroundColor = accent.withAlphaComponent(0.22)
                button.setTitleColor(accent, for: .normal)
                button.layer.borderWidth = 1
                button.layer.borderColor = accent.withAlphaComponent(0.35).cgColor
            } else {
                button.backgroundColor = UIColor.tertiarySystemFill.withAlphaComponent(0.55)
                button.setTitleColor(.secondaryLabel, for: .normal)
                button.layer.borderWidth = 0
                button.layer.borderColor = UIColor.clear.cgColor
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }
}
