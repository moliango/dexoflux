import UIKit

protocol AuthGating: AnyObject {
    func requireAuth(then action: @escaping () -> Void)
    func isAuthenticated() -> Bool
    func currentUsername() -> String?
    func performLogout()
}

extension UIViewController {
    func nearestAuthGating() -> AuthGating? {
        if let gate = self as? AuthGating {
            return gate
        }

        var current = parent
        while let viewController = current {
            if let gate = viewController as? AuthGating {
                return gate
            }
            current = viewController.parent
        }

        var presenter = presentingViewController
        while let viewController = presenter {
            var visited = Set<ObjectIdentifier>()
            if let gate = firstAuthGating(in: viewController, visited: &visited) {
                return gate
            }
            presenter = viewController.presentingViewController
        }

        guard let rootViewController = view.window?.rootViewController else {
            return nil
        }
        var visited = Set<ObjectIdentifier>()
        return firstAuthGating(in: rootViewController, visited: &visited)
    }

    private func firstAuthGating(
        in viewController: UIViewController,
        visited: inout Set<ObjectIdentifier>
    ) -> AuthGating? {
        let key = ObjectIdentifier(viewController)
        guard visited.insert(key).inserted else { return nil }

        if let gate = viewController as? AuthGating {
            return gate
        }
        for child in viewController.children {
            if let gate = firstAuthGating(in: child, visited: &visited) {
                return gate
            }
        }
        if let presented = viewController.presentedViewController,
           let gate = firstAuthGating(in: presented, visited: &visited) {
            return gate
        }
        return nil
    }
}
