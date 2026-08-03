import UIKit

/// Shared empty / loading / error state for list screens (Phase 6).
final class ListStateView: UIView {
    enum State: Equatable {
        case loading
        case error(String)
        case empty
        /// Custom empty with optional subtitle.
        case emptyCustom(title: String, subtitle: String? = nil, symbol: String = "text.page")
        case retry
    }

    private let icon = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()
    private let subtitleLabel = UILabel()
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

        spinner.hidesWhenStopped = true
        spinner.color = .tertiaryLabel

        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true

        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.isHidden = true

        button.configuration = .filled()
        button.configuration?.title = String(localized: "action.retry")
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, icon, label, subtitleLabel, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func configure(_ state: State, onRetry: @escaping () -> Void = {}) {
        self.onRetry = onRetry
        subtitleLabel.isHidden = true
        subtitleLabel.text = nil

        switch state {
        case .loading:
            icon.isHidden = true
            spinner.startAnimating()
            label.text = String(localized: "me.topic_list.loading")
            button.isHidden = true
        case .error(let message):
            spinner.stopAnimating()
            icon.isHidden = false
            icon.image = UIImage(systemName: "exclamationmark.triangle")
            label.text = message
            button.isHidden = false
            button.configuration?.title = String(localized: "action.retry")
        case .empty:
            spinner.stopAnimating()
            icon.isHidden = false
            icon.image = UIImage(systemName: "text.page")
            label.text = String(localized: "me.topic_list.empty")
            button.isHidden = true
        case .emptyCustom(let title, let subtitle, let symbol):
            spinner.stopAnimating()
            icon.isHidden = false
            icon.image = UIImage(systemName: symbol)
            label.text = title
            if let subtitle, !subtitle.isEmpty {
                subtitleLabel.text = subtitle
                subtitleLabel.isHidden = false
            }
            button.isHidden = true
        case .retry:
            spinner.stopAnimating()
            icon.isHidden = false
            icon.image = UIImage(systemName: "arrow.clockwise")
            label.text = String(localized: "me.topic_list.retry")
            button.isHidden = false
            button.configuration?.title = String(localized: "action.retry")
        }

        if UIAccessibility.isReduceMotionEnabled {
            icon.layer.removeAllAnimations()
        }
    }

    @objc private func retryTapped() {
        onRetry?()
    }
}
