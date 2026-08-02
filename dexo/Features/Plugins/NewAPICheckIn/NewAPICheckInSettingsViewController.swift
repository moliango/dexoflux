import UIKit

/// 「设置」tab — auto-relogin + tab visibility (from original NewAPSign).
@MainActor
final class NewAPICheckInSettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case checkIn
        case tabs
        case about
    }

    private let store: NewAPICheckInStore
    private let service: NewAPICheckInService

    init(store: NewAPICheckInStore, service: NewAPICheckInService) {
        self.store = store
        self.service = service
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "plugins.newapi.tab.settings", defaultValue: "设置")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .checkIn: return 1
        case .tabs: return 2
        case .about: return 1
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .checkIn:
            return String(localized: "plugins.newapi.settings.check_in", defaultValue: "签到")
        case .tabs:
            return String(localized: "plugins.newapi.settings.tabs", defaultValue: "底部标签")
        case .about:
            return String(localized: "plugins.newapi.settings.about", defaultValue: "关于")
        case nil:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .checkIn:
            return String(
                localized: "plugins.newapi.auto_relogin.help",
                defaultValue: "登录失效时自动打开登录页刷新 Cookie"
            )
        case .tabs:
            return String(
                localized: "plugins.newapi.settings.tabs.footer",
                defaultValue: "关闭后对应标签会从底部栏隐藏，可随时再打开。"
            )
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.selectionStyle = .none
        cell.accessoryView = nil
        cell.accessoryType = .none

        switch Section(rawValue: indexPath.section) {
        case .checkIn:
            content.text = String(localized: "plugins.newapi.auto_relogin", defaultValue: "自动重新登录")
            content.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            content.imageProperties.tintColor = AppSettings.shared.themeStyle.accentColor
            let toggle = UISwitch()
            toggle.isOn = NewAPICheckInRuntime.autoReloginEnabled
            toggle.onTintColor = AppSettings.shared.themeStyle.accentColor
            toggle.addAction(UIAction { action in
                guard let switchControl = action.sender as? UISwitch else { return }
                NewAPICheckInRuntime.autoReloginEnabled = switchControl.isOn
            }, for: .valueChanged)
            cell.accessoryView = toggle

        case .tabs:
            if indexPath.row == 0 {
                content.text = String(localized: "plugins.newapi.tab.custom", defaultValue: "自定义")
                content.image = UIImage(systemName: "globe")
                let toggle = UISwitch()
                toggle.isOn = NewAPICheckInTabConfig.showCustomTab
                toggle.onTintColor = AppSettings.shared.themeStyle.accentColor
                toggle.addAction(UIAction { action in
                    guard let switchControl = action.sender as? UISwitch else { return }
                    NewAPICheckInTabConfig.showCustomTab = switchControl.isOn
                }, for: .valueChanged)
                cell.accessoryView = toggle
            } else {
                content.text = String(localized: "plugins.newapi.tab.history", defaultValue: "历史")
                content.image = UIImage(systemName: "clock.arrow.circlepath")
                let toggle = UISwitch()
                toggle.isOn = NewAPICheckInTabConfig.showHistoryTab
                toggle.onTintColor = AppSettings.shared.themeStyle.accentColor
                toggle.addAction(UIAction { action in
                    guard let switchControl = action.sender as? UISwitch else { return }
                    NewAPICheckInTabConfig.showHistoryTab = switchControl.isOn
                }, for: .valueChanged)
                cell.accessoryView = toggle
            }

        case .about:
            content.text = String(localized: "plugins.newapi.settings.version", defaultValue: "NewAPI 签到")
            content.secondaryText = String(
                localized: "plugins.newapi.settings.version_detail",
                defaultValue: "小程序版 · 布局对齐 NewAPSign"
            )
            content.image = UIImage(systemName: "info.circle")
            content.secondaryTextProperties.color = .secondaryLabel

        case nil:
            break
        }

        cell.contentConfiguration = content
        return cell
    }
}
