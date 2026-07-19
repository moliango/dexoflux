import UIKit

final class PluginCenterViewController: UITableViewController {
    private let registry = DexoPluginRuntime.shared.registry
    private let scope: PluginScope

    private var visiblePlugins: [PluginManifest] {
        registry.allPlugins.filter { $0.supports(scope) }
    }

    init(baseURL: String, username: String?) {
        scope = PluginScope(baseURL: baseURL, username: username)
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "plugins.title", defaultValue: "插件中心")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "plugin")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pluginStateDidChange),
            name: PluginStateStore.stateDidChangeNotification,
            object: nil
        )
    }

    @MainActor
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : visiblePlugins.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0
            ? String(localized: "plugins.safety", defaultValue: "运行保护")
            : String(localized: "plugins.internal", defaultValue: "内部插件")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else {
            return String(localized: "plugins.scope.footer", defaultValue: "启停状态按当前论坛和账号独立保存。关闭插件不会删除授权信息或历史数据。")
        }
        return String(localized: "plugins.safe_mode.footer", defaultValue: "安全模式会临时停用全部可选插件，但保留每个插件原来的启停设置。")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "plugin", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 1
        content.secondaryTextProperties.numberOfLines = 2

        let toggle = UISwitch()
        toggle.tag = indexPath.section == 0 ? -1 : indexPath.row
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)

        if indexPath.section == 0 {
            content.image = UIImage(systemName: "shield.lefthalf.filled")
            content.text = String(localized: "plugins.safe_mode", defaultValue: "安全模式")
            content.secondaryText = String(localized: "plugins.safe_mode.subtitle", defaultValue: "暂时停用所有内部插件")
            toggle.isOn = registry.isSafeModeEnabled
        } else {
            let plugin = visiblePlugins[indexPath.row]
            let iconName = iconName(for: plugin.id)
            if let assetImage = UIImage(named: iconName) {
                content.image = assetImage.withRenderingMode(.alwaysOriginal)
            } else {
                content.image = UIImage(systemName: iconName)
            }
            content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
            content.text = plugin.displayName
            let provider = String(
                format: String(localized: "plugins.provider_format", defaultValue: "提供者：%@"),
                plugin.publisher
            )
            content.secondaryText = "v\(plugin.version) · \(provider) · \(permissionSummary(for: plugin))"
            toggle.isOn = registry.isPluginEnabled(plugin.id, for: scope)
            toggle.isEnabled = !registry.isSafeModeEnabled
        }

        cell.contentConfiguration = content
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        return cell
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        if sender.tag == -1 {
            registry.setSafeModeEnabled(sender.isOn)
            return
        }

        guard visiblePlugins.indices.contains(sender.tag) else { return }
        registry.setPlugin(visiblePlugins[sender.tag].id, enabled: sender.isOn, for: scope)
    }

    @objc private func pluginStateDidChange() {
        tableView.reloadData()
    }

    private func iconName(for pluginID: String) -> String {
        switch pluginID {
        case BuiltInPluginID.ldc: return "creditcard.fill"
        case BuiltInPluginID.cdk: return "shippingbox.fill"
        case BuiltInPluginID.topicExport: return "square.and.arrow.up.fill"
        case BuiltInPluginID.newAPICheckIn: return "checkmark.circle.fill"
        case BuiltInPluginID.ldcStore: return "LDStoreLogo"
        default: return "puzzlepiece.extension.fill"
        }
    }

    private func permissionSummary(for plugin: PluginManifest) -> String {
        let values = plugin.capabilities.sorted { $0.rawValue < $1.rawValue }.prefix(3).map(capabilityTitle)
        return values.joined(separator: " · ")
    }

    private func capabilityTitle(_ capability: PluginCapability) -> String {
        switch capability {
        case .forumRead: return String(localized: "plugins.permission.forum_read", defaultValue: "论坛读取")
        case .topicRead: return String(localized: "plugins.permission.topic_read", defaultValue: "话题读取")
        case .topicExport: return String(localized: "plugins.permission.topic_export", defaultValue: "话题导出")
        case .browserNavigation: return String(localized: "plugins.permission.browser", defaultValue: "浏览器")
        case .pluginStorage: return String(localized: "plugins.permission.storage", defaultValue: "插件存储")
        case .secureStorage: return String(localized: "plugins.permission.secure_storage", defaultValue: "安全存储")
        case .restrictedNetwork: return String(localized: "plugins.permission.network", defaultValue: "受限网络")
        }
    }
}
