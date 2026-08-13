import UIKit

/// Root of the NewAPI mini-program — mirrors original NewAPSign tabs:
/// 签到 / 自定义 / 历史 / 设置.
@MainActor
final class NewAPICheckInTabBarController: UITabBarController {
    private let store: NewAPICheckInStore
    private let service: NewAPICheckInService

    init(store: NewAPICheckInStore, service: NewAPICheckInService) {
        self.store = store
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tabBar.tintColor = AppSettings.shared.themeStyle.accentColor
        rebuildTabs()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tabConfigChanged),
            name: NewAPICheckInTabConfig.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func tabConfigChanged() {
        let previous = selectedIndex
        rebuildTabs()
        if let count = viewControllers?.count, count > 0 {
            selectedIndex = min(previous, count - 1)
        }
    }

    private func rebuildTabs() {
        var tabs: [UIViewController] = []

        let checkIn = NewAPICheckInViewController(store: store, service: service)
        checkIn.tabBarItem = UITabBarItem(
            title: String(localized: "plugins.newapi.tab.check_in", defaultValue: "签到"),
            image: UIImage(systemName: "checkmark.circle"),
            selectedImage: UIImage(systemName: "checkmark.circle.fill")
        )
        tabs.append(UINavigationController(rootViewController: checkIn))

        if NewAPICheckInTabConfig.showCustomTab {
            let custom = NewAPICheckInCustomPagesViewController(store: store)
            custom.tabBarItem = UITabBarItem(
                title: String(localized: "plugins.newapi.tab.custom", defaultValue: "自定义"),
                image: UIImage(systemName: "globe"),
                selectedImage: UIImage(systemName: "globe")
            )
            tabs.append(UINavigationController(rootViewController: custom))
        }

        if NewAPICheckInTabConfig.showHistoryTab {
            let history = NewAPICheckInHistoryViewController(store: store)
            history.tabBarItem = UITabBarItem(
                title: String(localized: "plugins.newapi.tab.history", defaultValue: "历史"),
                image: UIImage(systemName: "clock.arrow.circlepath"),
                selectedImage: UIImage(systemName: "clock.arrow.circlepath")
            )
            tabs.append(UINavigationController(rootViewController: history))
        }

        let settings = NewAPICheckInSettingsViewController(store: store, service: service)
        settings.tabBarItem = UITabBarItem(
            title: String(localized: "plugins.newapi.tab.settings", defaultValue: "设置"),
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )
        tabs.append(UINavigationController(rootViewController: settings))

        viewControllers = tabs
    }
}

/// Tab visibility — same keys as original NewAPSign TabBarConfig.
enum NewAPICheckInTabConfig {
    static let didChangeNotification = Notification.Name("DoerNewAPICheckInTabConfigChanged")

    private static let customKey = "plugin.newapi.tab.show_custom"
    private static let historyKey = "plugin.newapi.tab.show_history"

    static var showCustomTab: Bool {
        get {
            if UserDefaults.standard.object(forKey: customKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: customKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: customKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static var showHistoryTab: Bool {
        get {
            if UserDefaults.standard.object(forKey: historyKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: historyKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: historyKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
