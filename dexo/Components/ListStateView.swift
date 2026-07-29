import UIKit

final class ListStateView: UIView {
    enum State: Equatable {
        case loading
        case error(String)
        case empty
        case retry
    }

    private let icon = UIImageView()
    private let label = UILabel()
    private let button = UIButton()

    private var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .tertiaryLabel

        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true

        button.configuration = .filled()
        button.configuration?.title = String(localized: "action.retry")
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, label, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func configure(_ state: State, onRetry: @escaping () -> Void) {
        self.onRetry = onRetry

        switch state {
        case .loading:
            icon.image = UIImage(systemName: "arrow.clockwise")
            label.text = String(localized: "me.topic_list.loading")
            button.isHidden = true
        case .error(let message):
            icon.image = UIImage(systemName: "exclamationmark.triangle")
            label.text = message
            button.isHidden = false
        case .empty:
            icon.image = UIImage(systemName: "text.page")
            label.text = String(localized: "me.topic_list.empty")
            button.isHidden = true
        case .retry:
            icon.image = UIImage(systemName: "arrow.clockwise")
            label.text = String(localized: "me.topic_list.retry")
            button.isHidden = false
        }

        // Reduce Motion: only suppress decorative rotation, keep retry actionable.
        if UIAccessibility.isReduceMotionEnabled {
            icon.layer.removeAllAnimations()
        }
    }

    @objc private func retryTapped() {
        onRetry?()
    }
}
