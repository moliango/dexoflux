import UIKit

/// Keeps one mini-program in a WeChat-style floating bubble after「浮窗」.
@MainActor
final class MiniProgramFloatingManager {
    static let shared = MiniProgramFloatingManager()

    private struct Session {
        let program: MiniProgramDescriptor
        let host: MiniProgramHostViewController
        let api: DiscourseAPI
        let username: String?
        let bubble: UIView
    }

    private var session: Session?
    private weak var anchorWindow: UIWindow?

    var hasFloatedProgram: Bool { session != nil }

    private init() {}

    /// Minimize the full-screen host into a draggable bubble on the key window.
    func float(
        host: MiniProgramHostViewController,
        program: MiniProgramDescriptor,
        api: DiscourseAPI,
        username: String?
    ) {
        // Replace any previous float so only one bubble is active.
        discard(animated: false)

        guard let window = host.view.window
            ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else {
            host.destroyAndDismiss()
            return
        }

        anchorWindow = window
        let bubble = makeBubble(icon: MiniProgramFactory.icon(for: program.id), title: program.displayName)
        window.addSubview(bubble)
        positionBubble(bubble, in: window)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(bubblePanned(_:)))
        bubble.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(bubbleTapped))
        bubble.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(bubbleLongPressed(_:)))
        longPress.minimumPressDuration = 0.45
        bubble.addGestureRecognizer(longPress)

        session = Session(
            program: program,
            host: host,
            api: api,
            username: username,
            bubble: bubble
        )

        // Settle forum chrome under the still-visible fullScreen host, then
        // dismiss. Same flash class as close if tab bar pops in mid-transition.
        host.settleUnderlyingChromeBeforeDismiss()
        if host.presentingViewController != nil {
            host.dismiss(animated: true)
        } else {
            host.view.isHidden = true
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        animateBubbleIn(bubble)
    }

    /// Restore the floated mini-program full screen from the bubble.
    func restore(from presenter: UIViewController? = nil) {
        guard let session else { return }
        let host = session.host
        let bubble = session.bubble

        UIView.animate(withDuration: 0.18, animations: {
            bubble.alpha = 0
            bubble.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        }, completion: { _ in
            bubble.removeFromSuperview()
        })

        self.session = nil

        let presenterVC = presenter
            ?? topPresenter()
        guard let presenterVC else {
            discard(animated: false)
            return
        }

        host.view.isHidden = false
        if host.presentingViewController == nil {
            host.modalPresentationStyle = .fullScreen
            presenterVC.present(host, animated: true)
        }
    }

    /// Drop the floating session and destroy hosted content.
    func discard(animated: Bool = true) {
        guard let session else { return }
        let bubble = session.bubble
        let host = session.host
        self.session = nil

        let removeBubble = {
            bubble.removeFromSuperview()
        }
        if animated {
            UIView.animate(withDuration: 0.18, animations: {
                bubble.alpha = 0
                bubble.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            }, completion: { _ in removeBubble() })
        } else {
            removeBubble()
        }

        host.destroyAndDismiss()
    }

    // MARK: - Bubble UI

    private func makeBubble(icon: UIImage?, title: String) -> UIView {
        let size: CGFloat = 56
        let container = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        container.backgroundColor = .clear
        container.layer.cornerRadius = size / 2
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.22
        container.layer.shadowRadius = 12
        container.layer.shadowOffset = CGSize(width: 0, height: 6)
        container.isUserInteractionEnabled = true
        container.accessibilityLabel = title
        container.accessibilityTraits = .button
        container.accessibilityHint = String(
            localized: "mini_program.float.restore_hint",
            defaultValue: "点按重新打开；长按关闭浮窗"
        )

        // Full circular WeChat-style icon (edge-to-edge).
        let imageView = UIImageView(image: icon ?? MiniProgramIconBadge.image(for: "", size: size))
        imageView.frame = container.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = size / 2
        imageView.layer.borderWidth = 1.0 / UIScreen.main.scale
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        imageView.isUserInteractionEnabled = false
        container.addSubview(imageView)
        return container
    }

    private func positionBubble(_ bubble: UIView, in window: UIWindow) {
        let size = bubble.bounds.size.width > 0 ? bubble.bounds.size.width : 56
        let margin: CGFloat = 16
        let safe = window.safeAreaInsets
        bubble.frame = CGRect(
            x: window.bounds.width - size - margin,
            y: window.bounds.height - safe.bottom - size - 96,
            width: size,
            height: size
        )
        bubble.alpha = 0
        bubble.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
    }

    private func animateBubbleIn(_ bubble: UIView) {
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.6,
            options: [.curveEaseOut]
        ) {
            bubble.alpha = 1
            bubble.transform = .identity
        }
    }

    private func snapBubbleToEdge(_ bubble: UIView, in window: UIWindow) {
        let size = bubble.bounds.width
        let margin: CGFloat = 12
        let safe = window.safeAreaInsets
        let midX = bubble.center.x
        let targetX: CGFloat = midX < window.bounds.midX
            ? margin + size / 2
            : window.bounds.width - margin - size / 2
        var targetY = bubble.center.y
        let minY = safe.top + size / 2 + 8
        let maxY = window.bounds.height - safe.bottom - size / 2 - 8
        targetY = min(max(targetY, minY), maxY)
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.4,
            options: [.curveEaseOut]
        ) {
            bubble.center = CGPoint(x: targetX, y: targetY)
        }
    }

    private func topPresenter() -> UIViewController? {
        let window = anchorWindow
            ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    @objc private func bubbleTapped() {
        restore()
    }

    @objc private func bubblePanned(_ gesture: UIPanGestureRecognizer) {
        guard let bubble = session?.bubble,
              let window = bubble.window
        else { return }
        let translation = gesture.translation(in: window)
        switch gesture.state {
        case .changed:
            bubble.center = CGPoint(
                x: bubble.center.x + translation.x,
                y: bubble.center.y + translation.y
            )
            gesture.setTranslation(.zero, in: window)
        case .ended, .cancelled:
            snapBubbleToEdge(bubble, in: window)
        default:
            break
        }
    }

    @objc private func bubbleLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let alert = UIAlertController(
            title: String(localized: "mini_program.float.close_title", defaultValue: "关闭浮窗"),
            message: String(
                localized: "mini_program.float.close_message",
                defaultValue: "关闭后将退出该小程序"
            ),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(
            title: String(localized: "mini_program.float.close_action", defaultValue: "关闭"),
            style: .destructive,
            handler: { [weak self] _ in
                self?.discard(animated: true)
            }
        ))
        alert.addAction(UIAlertAction(
            title: String(localized: "common.cancel", defaultValue: "取消"),
            style: .cancel
        ))
        if let popover = alert.popoverPresentationController, let bubble = session?.bubble {
            popover.sourceView = bubble
            popover.sourceRect = bubble.bounds
        }
        topPresenter()?.present(alert, animated: true)
    }
}
