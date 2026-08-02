import UIKit

extension UIViewController {
    func enableSettingsInteractiveBackSwipe() {
        guard let navigationController,
              navigationController.viewControllers.count > 1
        else { return }
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = nil
    }
}
