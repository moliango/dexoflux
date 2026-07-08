import UIKit

final class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let forumListVC = ForumListViewController()
        let forumListNav = UINavigationController(rootViewController: forumListVC)
        forumListNav.tabBarItem = UITabBarItem(
            title: String(localized: "tab.forums"),
            image: DexoTabBarIconStyle.image(named: "list.bullet.circle.fill", selected: false),
            selectedImage: DexoTabBarIconStyle.image(named: "list.bullet.circle.fill", selected: true)
        )
        forumListNav.tabBarItem.tag = 0

        let settingsVC = SettingsViewController()
        let settingsNav = UINavigationController(rootViewController: settingsVC)
        settingsNav.tabBarItem = UITabBarItem(
            title: String(localized: "tab.settings"),
            image: DexoTabBarIconStyle.image(named: "gearshape.fill", selected: false),
            selectedImage: DexoTabBarIconStyle.image(named: "gearshape.fill", selected: true)
        )
        settingsNav.tabBarItem.tag = 1

        viewControllers = [forumListNav, settingsNav]
    }
}
