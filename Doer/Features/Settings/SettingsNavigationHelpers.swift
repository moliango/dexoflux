import UIKit

/// Enables system interactive pop (follow-finger edge swipe) on a UINavigationController.
/// Attach once per navigation stack. Do not add a competing pan that pops on lift.
final class NavigationPopGestureEnabler: NSObject, UIGestureRecognizerDelegate {
    private weak var navigationController: UINavigationController?

    func attach(to navigationController: UINavigationController) {
        self.navigationController = navigationController
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = self
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController else { return false }
        return nav.viewControllers.count > 1
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
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
