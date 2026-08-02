import UIKit

/// FluxDo-style offline strip: sits under the home header, pushes content down.
/// Only UI — connectivity logic lives in `ConnectivityService`.
final class OfflineIndicatorView: UIView {
    var onRetry: (() -> Void)?

    private static let expandedHeight: CGFloat = 36
    private var heightConstraint: NSLayoutConstraint?

    private let iconView: UIImageView = {
        let imageView = UIImageView(
            image: UIImage(systemName: "wifi.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = String(localized: "home.network.disconnected", defaultValue: "网络已断开")
        return label
    }()

    private lazy var retryButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = String(localized: "action.refresh", defaultValue: "刷新")
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        return button
    }()

    private let rowStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        isHidden = true

        rowStack.addArrangedSubview(iconView)
        rowStack.addArrangedSubview(titleLabel)
        rowStack.addArrangedSubview(UIView()) // spacer
        rowStack.addArrangedSubview(retryButton)
        addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            retryButton.widthAnchor.constraint(equalToConstant: 32),
            retryButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        let height = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint = height
        height.isActive = true
        alpha = 0
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        let targetHeight: CGFloat = visible ? Self.expandedHeight : 0
        let currentlyVisible = (heightConstraint?.constant ?? 0) > 0.5
        guard currentlyVisible != visible else { return }

        let updates = {
            self.heightConstraint?.constant = targetHeight
            self.alpha = visible ? 1 : 0
            self.superview?.layoutIfNeeded()
        }

        if visible {
            isHidden = false
        }

        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
                updates()
            } completion: { _ in
                self.isHidden = !visible
            }
        } else {
            updates()
            isHidden = !visible
        }
    }

    @objc private func retryTapped() {
        onRetry?()
    }
}
