import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        let defaultForum = DatabaseManager.shared.defaultForum()
        window.rootViewController = ForumContainerViewController(forum: defaultForum, showsDismissButton: false)
        window.makeKeyAndVisible()
        self.window = window
        AppSettings.shared.applyAppearance()
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {
        refreshWebSessionAfterForeground(reason: "scene_did_become_active")
    }
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {
//        ProxyManager.shared.start()
        refreshWebSessionAfterForeground(reason: "scene_will_enter_foreground")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
//        ProxyManager.shared.stop()
    }

    private func refreshWebSessionAfterForeground(reason: String) {
        let forum = DatabaseManager.shared.defaultForum()
        guard AuthManager.shared.hasWebSession(for: forum.baseURL) else { return }
        WebSessionRefreshService.shared.ensureInBackground(forum: forum, reason: reason)
    }
}
