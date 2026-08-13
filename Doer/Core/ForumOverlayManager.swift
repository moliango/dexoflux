import SDWebImage
import UIKit

final class ForumOverlayManager {
    static let shared = ForumOverlayManager()

    private(set) var currentContainer: ForumContainerViewController?
    private var floatingButton: UIView?
    private var isMinimized = false
    private weak var mainWindow: UIWindow?
    private var overlayWindow: UIWindow?

    /// Snapshot used during animations
    private var snapshotView: UIView?

    /// Tracks the floating button position for animation target
    private var floatingButtonCenter: CGPoint {
        guard let mainWindow else { return .zero }
        let safeArea = mainWindow.safeAreaInsets
        return CGPoint(
            x: mainWindow.bounds.width - 44 - 16,
            y: mainWindow.bounds.height - safeArea.bottom - 44 - 16
        )
    }

    private init() {}

    // MARK: - Present

    func present(forum: ForumInstance, in window: UIWindow) {
        // Clean up any existing instance
        dismissOverlayWindow()
        removeFloatingButton()
        isMinimized = false

        mainWindow = window

        guard let scene = window.windowScene else { return }

        let containerVC = ForumContainerViewController(forum: forum)
        currentContainer = containerVC

        let overlay = UIWindow(windowScene: scene)
        overlay.rootViewController = containerVC
        overlay.windowLevel = .normal
        overlay.overrideUserInterfaceStyle = window.overrideUserInterfaceStyle
        overlay.makeKeyAndVisible()
        overlayWindow = overlay

        // Animate in from bottom
        overlay.frame = window.bounds
        overlay.transform = CGAffineTransform(translationX: 0, y: window.bounds.height)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            overlay.transform = .identity
        }
    }

    // MARK: - Minimize

    func minimize() {
        guard let containerVC = currentContainer,
              let mainWindow,
              let overlayWindow,
              !isMinimized else { return }

        isMinimized = true

        // Take snapshot for animation
        guard let snapshot = overlayWindow.snapshotView(afterScreenUpdates: false) else {
            overlayWindow.isHidden = true
            mainWindow.makeKeyAndVisible()
            showFloatingButton(for: containerVC.forum)
            return
        }

        snapshot.frame = mainWindow.bounds
        snapshot.layer.cornerRadius = 0
        snapshot.clipsToBounds = true
        mainWindow.addSubview(snapshot)
        snapshotView = snapshot

        // Hide overlay window immediately
        overlayWindow.isHidden = true
        mainWindow.makeKeyAndVisible()

        let targetCenter = floatingButtonCenter
        let targetSize: CGFloat = 56

        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
            let scaleX = targetSize / snapshot.bounds.width
            let scaleY = targetSize / snapshot.bounds.height
            snapshot.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            snapshot.center = targetCenter
            snapshot.layer.cornerRadius = targetSize / 2
        } completion: { _ in
            snapshot.removeFromSuperview()
            self.snapshotView = nil
            self.showFloatingButton(for: containerVC.forum)
        }
    }

    // MARK: - Restore

    func prepareForNotificationRoute(in container: ForumContainerViewController) -> Bool {
        if currentContainer === container {
            guard isMinimized || overlayWindow?.isHidden == true else { return true }
            restore()
            return false
        }

        if !isMinimized, overlayWindow?.isHidden == false {
            minimize()
            return false
        }
        return true
    }

    func restore() {
        guard let currentContainer,
              let mainWindow,
              let overlayWindow,
              isMinimized else { return }

        isMinimized = false

        let targetSize: CGFloat = 56
        let startCenter = floatingButton?.center ?? floatingButtonCenter

        removeFloatingButton()

        // Show overlay briefly to get snapshot, then hide again for animation
        overlayWindow.isHidden = false
        guard let snapshot = overlayWindow.snapshotView(afterScreenUpdates: true) else {
            overlayWindow.makeKeyAndVisible()
            return
        }
        overlayWindow.isHidden = true

        // Start snapshot small at button position
        snapshot.frame = mainWindow.bounds
        let scaleX = targetSize / mainWindow.bounds.width
        let scaleY = targetSize / mainWindow.bounds.height
        snapshot.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        snapshot.center = startCenter
        snapshot.layer.cornerRadius = targetSize / 2
        snapshot.clipsToBounds = true
        mainWindow.addSubview(snapshot)
        snapshotView = snapshot

        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
            snapshot.transform = .identity
            snapshot.center = CGPoint(x: mainWindow.bounds.midX, y: mainWindow.bounds.midY)
            snapshot.layer.cornerRadius = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
            self.snapshotView = nil
            overlayWindow.isHidden = false
            overlayWindow.makeKeyAndVisible()
        }
    }

    // MARK: - Dismiss

    func dismiss() {
        dismissOverlayWindow()
        removeFloatingButton()
        isMinimized = false
        snapshotView?.removeFromSuperview()
        snapshotView = nil
        mainWindow?.makeKeyAndVisible()
    }

    // MARK: - Floating Button

    private func showFloatingButton(for forum: ForumInstance) {
        guard let mainWindow else { return }

        removeFloatingButton()

        let size: CGFloat = 56

        // Container view
        let button = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        button.center = floatingButtonCenter
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = false
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowRadius = 8
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 2)

        // Blur background
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        blur.frame = button.bounds
        blur.layer.cornerRadius = size / 2
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false
        button.addSubview(blur)

        // Favicon
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.frame = CGRect(x: 12, y: 12, width: size - 24, height: size - 24)

        if let iconURLString = forum.iconURL, let iconURL = URL(string: iconURLString) {
            imageView.sd_setImage(with: iconURL, placeholderImage: UIImage(systemName: "globe"))
        } else {
            imageView.image = UIImage(systemName: "globe")
            imageView.tintColor = .label
        }
        button.addSubview(imageView)

        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(floatingButtonTapped))
        button.addGestureRecognizer(tap)

        // Pan gesture for dragging
        let pan = UIPanGestureRecognizer(target: self, action: #selector(floatingButtonPanned(_:)))
        button.addGestureRecognizer(pan)

        // Long press to dismiss
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(floatingButtonLongPressed(_:)))
        button.addGestureRecognizer(longPress)

        button.isUserInteractionEnabled = true
        mainWindow.addSubview(button)
        floatingButton = button

        // Appear animation
        button.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
            button.transform = .identity
        }
    }

    private func removeFloatingButton() {
        floatingButton?.removeFromSuperview()
        floatingButton = nil
    }

    // MARK: - Gesture Handlers

    @objc private func floatingButtonTapped() {
        restore()
    }

    @objc private func floatingButtonPanned(_ gesture: UIPanGestureRecognizer) {
        guard let button = floatingButton, let mainWindow else { return }

        let translation = gesture.translation(in: mainWindow)

        switch gesture.state {
        case .changed:
            button.center = CGPoint(
                x: button.center.x + translation.x,
                y: button.center.y + translation.y
            )
            gesture.setTranslation(.zero, in: mainWindow)

        case .ended, .cancelled:
            // Snap to nearest left/right edge
            let safeArea = mainWindow.safeAreaInsets
            let halfWidth = button.bounds.width / 2
            let margin: CGFloat = 16

            let leftX = safeArea.left + margin + halfWidth
            let rightX = mainWindow.bounds.width - safeArea.right - margin - halfWidth
            let targetX = button.center.x < mainWindow.bounds.midX ? leftX : rightX

            // Clamp Y within safe area
            let minY = safeArea.top + margin + halfWidth
            let maxY = mainWindow.bounds.height - safeArea.bottom - margin - halfWidth
            let targetY = min(max(button.center.y, minY), maxY)

            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                button.center = CGPoint(x: targetX, y: targetY)
            }

        default:
            break
        }
    }

    @objc private func floatingButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        let alert = UIAlertController(
            title: nil,
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: String(localized: "forum.overlay.close"), style: .destructive) { [weak self] _ in
            self?.dismiss()
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))

        // Present from rootVC of main window
        if let rootVC = mainWindow?.rootViewController {
            if let popover = alert.popoverPresentationController {
                popover.sourceView = floatingButton
                popover.sourceRect = floatingButton?.bounds ?? .zero
            }
            rootVC.present(alert, animated: true)
        }
    }

    // MARK: - Helpers

    private func dismissOverlayWindow() {
        currentContainer = nil
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
    }
}
