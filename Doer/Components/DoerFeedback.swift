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

        UIView.animate(withDuration: 0.2) { stack.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            UIView.animate(withDuration: 0.2, animations: { stack.alpha = 0 }) { _ in
                stack.removeFromSuperview()
            }
        }
    }

    // MARK: - Loading HUD (improved with rotating spinner)

    @MainActor
    static func presentLoadingHUD(_ message: String?, on host: UIViewController) {
        dismissLoadingHUD(on: host, animated: false)

        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        overlay.tag = LoadingHUD.tag

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

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
        overlay.addSubview(card)

        host.view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: host.view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),

            card.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            card.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, multiplier: 0.7),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
        ])
        overlay.alpha = 0
        UIView.animate(withDuration: 0.18) { overlay.alpha = 1 }
    }

    @MainActor
    static func dismissLoadingHUD(on host: UIViewController, animated: Bool = true) {
        guard let overlay = host.view.viewWithTag(LoadingHUD.tag) else { return }
        guard animated else {
            overlay.removeFromSuperview()
            return
        }
        UIView.animate(withDuration: 0.15, animations: { overlay.alpha = 0 }) { _ in
            overlay.removeFromSuperview()
        }
    }

    private enum LoadingHUD {
        static let tag = 9_101_203
    }
}
