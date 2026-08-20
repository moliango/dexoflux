import UIKit

/// FluxDo-style offline strip: sits under the home header, pushes content down.
/// Only UI — connectivity logic lives in `ConnectivityService`.
final class OfflineIndicatorView: UIView {
    var onRetry: (() -> Void)?

    /// Must fit icon/button (~28) without fighting the height constraint.
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
        // Compact insets so the control fits inside `expandedHeight` without Autolayout fights.
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
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

        // Center the row vertically instead of pinning top+bottom with padding.
        // Collapsed height is 0 — top/bottom padding (4+4) would be unsatisfiable and
        // spam `Unable to simultaneously satisfy constraints` on every home launch.
        NSLayoutConstraint.activate([
            rowStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            retryButton.widthAnchor.constraint(equalToConstant: 28),
            retryButton.heightAnchor.constraint(equalToConstant: 28),
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
            let targetAlpha: CGFloat = visible ? 1 : 0
            AnimationOptimizer.animateAlpha(self, to: targetAlpha, duration: 0.28) {
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
