import UIKit

// MARK: - Balance card (LDC / CDK)

struct MeBalanceRowModel {
    let service: LinuxDoExtensionService
    let title: String
    let valueText: String
    let dailyIncomeText: String?
    let isLoading: Bool
    let isConnected: Bool
}

final class MeBalanceCardView: UIView {
    var onSelect: ((LinuxDoExtensionService) -> Void)?

    private let cardView = MeCardSurfaceView()
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)
        cardView.addSubview(stackView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 4),
            stackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(rows: [MeBalanceRowModel]) {
        isHidden = rows.isEmpty
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, row) in rows.enumerated() {
            if index > 0 {
                stackView.addArrangedSubview(makeDivider())
            }
            stackView.addArrangedSubview(makeRow(row))
        }
    }

    private func makeDivider() -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let line = UIView()
        line.backgroundColor = UIColor.separator.withAlphaComponent(0.28)
        line.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 62),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
        return wrap
    }

    private func makeRow(_ model: MeBalanceRowModel) -> UIControl {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.accessibilityIdentifier = "me.balance.\(model.service.rawValue)"
        control.addAction(UIAction { [weak self] _ in
            self?.onSelect?(model.service)
        }, for: .touchUpInside)

        let iconBg = UIView()
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.layer.cornerRadius = 18
        iconBg.layer.cornerCurve = .continuous
        let accent = model.service == .ldc
            ? UIColor.systemBlue
            : UIColor.systemPurple
        iconBg.backgroundColor = accent.withAlphaComponent(0.14)

        let icon = UIImageView(image: UIImage(systemName: model.service == .ldc ? "creditcard.fill" : "shippingbox.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = accent
        icon.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = model.title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabel

        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = model.isLoading && !model.isConnected ? "…" : model.valueText
        valueLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        valueLabel.textColor = .label

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit

        control.addSubview(iconBg)
        iconBg.addSubview(icon)
        control.addSubview(titleLabel)
        control.addSubview(valueLabel)
        control.addSubview(chevron)

        var trailingAnchor: NSLayoutXAxisAnchor = chevron.leadingAnchor
        if let income = model.dailyIncomeText {
            let badge = UIView()
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.backgroundColor = accent.withAlphaComponent(0.12)
            badge.layer.cornerRadius = 12
            badge.layer.cornerCurve = .continuous

            let trend = UIImageView(image: UIImage(systemName: "chart.line.uptrend.xyaxis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)))
            trend.translatesAutoresizingMaskIntoConstraints = false
            trend.tintColor = accent

            let incomeLabel = UILabel()
            incomeLabel.translatesAutoresizingMaskIntoConstraints = false
            incomeLabel.text = income
            incomeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            incomeLabel.textColor = .label

            badge.addSubview(trend)
            badge.addSubview(incomeLabel)
            control.addSubview(badge)

            NSLayoutConstraint.activate([
                badge.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                badge.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
                badge.heightAnchor.constraint(equalToConstant: 24),
                trend.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8),
                trend.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
                incomeLabel.leadingAnchor.constraint(equalTo: trend.trailingAnchor, constant: 3),
                incomeLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
                incomeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            ])
            trailingAnchor = badge.leadingAnchor
        }

        NSLayoutConstraint.activate([
            control.heightAnchor.constraint(equalToConstant: 68),
            iconBg.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 14),
            iconBg.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 36),
            iconBg.heightAnchor.constraint(equalToConstant: 36),
            icon.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: control.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

            chevron.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 12),
        ])
        return control
    }
}

// MARK: - Quick actions grid

struct MeQuickActionItem {
    let title: String
    let symbolName: String
    let tintColor: UIColor
    let action: () -> Void
}

final class MeQuickActionsCardView: UIView {
    private let cardView = MeCardSurfaceView()
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)
        cardView.addSubview(stackView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            stackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14),
            stackView.heightAnchor.constraint(equalToConstant: 78),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(items: [MeQuickActionItem]) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for item in items {
            stackView.addArrangedSubview(makeItemButton(item))
        }
    }

    private func makeItemButton(_ item: MeQuickActionItem) -> UIControl {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addAction(UIAction { _ in item.action() }, for: .touchUpInside)

        let iconBg = UIView()
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.backgroundColor = item.tintColor.withAlphaComponent(0.14)
        iconBg.layer.cornerRadius = 14
        iconBg.layer.cornerCurve = .continuous
        iconBg.isUserInteractionEnabled = false

        let icon = UIImageView(image: UIImage(systemName: item.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = item.tintColor
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = item.title
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .label
        title.textAlignment = .center
        title.numberOfLines = 1
        title.isUserInteractionEnabled = false

        control.addSubview(iconBg)
        iconBg.addSubview(icon)
        control.addSubview(title)

        NSLayoutConstraint.activate([
            iconBg.topAnchor.constraint(equalTo: control.topAnchor, constant: 2),
            iconBg.centerXAnchor.constraint(equalTo: control.centerXAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 44),
            iconBg.heightAnchor.constraint(equalToConstant: 44),
            icon.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            title.topAnchor.constraint(equalTo: iconBg.bottomAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 2),
            title.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -2),
            title.bottomAnchor.constraint(lessThanOrEqualTo: control.bottomAnchor),
        ])
        return control
    }
}
