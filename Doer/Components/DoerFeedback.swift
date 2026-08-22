import UIKit

/// Shared toast + loading HUD (Phase 6) — no third-party HUD libs.
enum DoerFeedback {
    // MARK: - Toast

    @MainActor
    static func presentToast(_ message: String, on host: UIViewController, duration: TimeInterval = 1.6) {
        guard host.isViewLoaded, let view = host.view else { return }

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [label])
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        stack.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        stack.layer.cornerRadius = 14
        stack.layer.cornerCurve = .continuous
        stack.clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alpha = 0
        stack.isUserInteractionEnabled = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])

        AnimationOptimizer.animateAlpha(stack, to: 1, duration: 0.2)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            AnimationOptimizer.animateAlpha(stack, to: 0, duration: 0.2) {
                stack.removeFromSuperview()
            }
        }
    }

    // MARK: - Loading HUD (improved with rotating spinner)

    @MainActor
    static func presentLoadingHUD(_ message: String?, on host: UIViewController) {
        dismissLoadingHUD(on: host, animated: false)
        host.loadViewIfNeeded()

        let overlay = LoadingHUDOverlay(message: message)
        overlay.tag = LoadingHUD.tag
        host.view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: host.view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        ])
        host.view.bringSubviewToFront(overlay)
        overlay.startSpinner()
    }

    @MainActor
    static func dismissLoadingHUD(on host: UIViewController, animated: Bool = true) {
        guard let overlay = host.view.viewWithTag(LoadingHUD.tag) else { return }
        guard animated else {
            overlay.removeFromSuperview()
            return
        }
        AnimationOptimizer.animateAlpha(overlay, to: 0, duration: 0.15) {
            overlay.removeFromSuperview()
        }
    }

    private enum LoadingHUD {
        static let tag = 9_101_203
    }
}

private final class LoadingHUDOverlay: UIView {
    private let spinner = UIActivityIndicatorView(style: .large)

    init(message: String?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.28)

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = false

        var arranged: [UIView] = [spinner]
        if let message, !message.isEmpty {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = message
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            arranged.append(label)
        }

        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            card.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.7),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func startSpinner() {
        spinner.startAnimating()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            spinner.startAnimating()
        }
    }
}
