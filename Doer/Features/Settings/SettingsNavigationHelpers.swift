import UIKit

/// Enables both system interactive pop (edge swipe) and a left-edge pan fallback
/// on a UINavigationController. Attach once per navigation stack.
final class NavigationPopGestureEnabler: NSObject, UIGestureRecognizerDelegate {
    private weak var navigationController: UINavigationController?
    private var fallbackPan: UIPanGestureRecognizer?

    func attach(to navigationController: UINavigationController) {
        self.navigationController = navigationController

        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = self

        if fallbackPan == nil {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleFallbackPan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delegate = self
            navigationController.view.addGestureRecognizer(pan)
            fallbackPan = pan
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController,
              nav.viewControllers.count > 1
        else { return false }

        let top = nav.topViewController
        if top is TopicDetailViewController || top is ChatTopicDetailViewController {
            return false
        }

        if gestureRecognizer === fallbackPan {
            let location = gestureRecognizer.location(in: nav.view)
            return location.x <= 80
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }

    @objc private func handleFallbackPan(_ gesture: UIPanGestureRecognizer) {
        guard let nav = navigationController,
              nav.viewControllers.count > 1,
              gesture.state == .ended
        else { return }

        let translation = gesture.translation(in: nav.view)
        let velocity = gesture.velocity(in: nav.view)
        if translation.x > 64 || velocity.x > 480 {
            nav.popViewController(animated: true)
        }
    }
}

extension UIViewController {
    func enableSettingsInteractiveBackSwipe() {
        enableInteractiveBackSwipe()
    }

    func enableInteractiveBackSwipe() {
        guard let navigationController,
              navigationController.viewControllers.count > 1
        else { return }
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
    }
}