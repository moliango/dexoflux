import UIKit

final class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let forumListVC = ForumListViewController()
        let forumListNav = UINavigationController(rootViewController: forumListVC)
        forumListNav.tabBarItem = UITabBarItem(title: String(localized: "tab.forums"), image: UIImage(systemName: "list.bullet"), tag: 0)

        let settingsVC = SettingsViewController()
        let settingsNav = UINavigationController(rootViewController: settingsVC)
        settingsNav.tabBarItem = UITabBarItem(title: String(localized: "tab.settings"), image: UIImage(systemName: "gearshape"), tag: 1)

        viewControllers = [forumListNav, settingsNav]
    }
}
