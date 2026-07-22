import UIKit

enum DexoLaunchAppearance {
    static let backgroundColorName = "LaunchBackground"
    static let backgroundColor = UIColor(named: backgroundColorName)
        ?? UIColor(red: 0.946, green: 0.944, blue: 0.922, alpha: 1)
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        window.backgroundColor = DexoLaunchAppearance.backgroundColor
        AppSettings.shared.applyAppearance()
        let defaultForum = DatabaseManager.shared.defaultForum()
        window.rootViewController = ForumContainerViewController(forum: defaultForum, showsDismissButton: false)
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {
        refreshWebSessionAfterForeground(reason: "scene_did_become_active")
        if let window {
            ForumNotificationRoutePresenter.presentPendingRouteIfNeeded(in: window)
        }
    }
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {
//        ProxyManager.shared.start()
        refreshWebSessionAfterForeground(reason: "scene_will_enter_foreground")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
//        ProxyManager.shared.stop()
        BackgroundNotificationRefreshService.shared.scheduleIfNeeded()
    }

    private func refreshWebSessionAfterForeground(reason: String) {
        let forum = DatabaseManager.shared.defaultForum()
        guard AuthManager.shared.hasWebSession(for: forum.baseURL) else { return }
        WebSessionRefreshService.shared.ensureInBackground(forum: forum, reason: reason)
    }
}
