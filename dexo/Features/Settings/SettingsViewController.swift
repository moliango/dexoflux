import SDWebImage
import UIKit
import WebKit

final class SettingsViewController: ObservableViewController {
    fileprivate enum Category: CaseIterable {
        case appearance
        case reading
        case network
        case bottomBar
        case dataManagement
        #if DEBUG
        case debug
        #endif

        var title: String {
            switch self {
            case .appearance: return String(localized: "settings.appearance_design")
            case .reading: return String(localized: "settings.reading_design")
            case .network: return String(localized: "settings.network")
            case .bottomBar: return String(localized: "settings.bottom_bar")
            case .dataManagement: return String(localized: "settings.data_management")
            #if DEBUG
            case .debug: return "Debug"
            #endif
            }
        }

        var subtitle: String {
            switch self {
            case .appearance: return String(localized: "settings.appearance.subtitle")
            case .reading: return String(localized: "settings.reading.subtitle")
            case .network: return String(localized: "settings.network.subtitle")
            case .bottomBar: return String(localized: "settings.bottom_bar.subtitle")
            case .dataManagement: return String(localized: "settings.data_management.subtitle")
            #if DEBUG
            case .debug: return "Render preview"
            #endif
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: return "paintpalette.fill"
            case .reading: return "book.closed.fill"
            case .network: return "network"
            case .bottomBar: return "rectangle.bottomthird.inset.filled"
            case .dataManagement: return "externaldrive.fill"
            #if DEBUG
            case .debug: return "hammer.fill"
            #endif
            }
        }

        var tintColor: UIColor {
            switch self {
            case .appearance: return .systemTeal
            case .reading: return .systemOrange
            case .network: return .systemBlue
            case .bottomBar: return .systemPurple
            case .dataManagement: return .systemBrown
            #if DEBUG
            case .debug: return .systemRed
            #endif
            }
        }
    }

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "tab.settings")
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    override func updateUI() {
        tableView.reloadData()
    }
}

extension SettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Category.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let category = Category.allCases[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: category.symbolName)
        content.imageProperties.tintColor = category.tintColor
        content.text = category.title
        content.secondaryText = category.subtitle
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let category = Category.allCases[indexPath.row]
        if category == .bottomBar {
            navigationController?.pushViewController(BottomBarLayoutViewController(), animated: true)
            return
        }
        let vc = SettingsCategoryViewController(category: category)
        navigationController?.pushViewController(vc, animated: true)
    }
}

private final class SettingsCategoryViewController: ObservableViewController {
    private let settings = AppSettings.shared
    private let category: SettingsViewController.Category

    private enum Row {
        case appearanceMode
        case readingComfort
        case hideScrollIndicators
        case dohToggle
        case dohDebugLog
        case dohStatus
        case dohProvider
        case dohCustomURL
        case cloudflareVerify
        case bottomBarLayout
        case bottomAutoHide
        case clearImageCache
        case autoOpen
        #if DEBUG
        case renderPreview
        #endif
    }

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        return table
    }()

    init(category: SettingsViewController.Category) {
        self.category = category
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = category.title
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    override func updateUI() {
        tableView.reloadData()
    }

    private var rows: [Row] {
        switch category {
        case .appearance:
            return [.appearanceMode]
        case .reading:
            return [.readingComfort, .hideScrollIndicators]
        case .network:
            var rows: [Row] = [.cloudflareVerify, .dohToggle, .dohDebugLog]
            if settings.dohEnabled {
                rows.append(.dohStatus)
                rows.append(.dohProvider)
                rows.append(.dohCustomURL)
            }
            return rows
        case .bottomBar:
            return [.bottomBarLayout, .bottomAutoHide]
        case .dataManagement:
            return [.clearImageCache, .autoOpen]
        #if DEBUG
        case .debug:
            return [.renderPreview]
        #endif
        }
    }
}

extension SettingsCategoryViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        switch row {
        case .appearanceMode:
            return valueCell(title: String(localized: "settings.dark_mode"), detail: settings.appearanceMode.title)
        case .readingComfort:
            return switchCell(title: String(localized: "settings.reading.comfort"), isOn: settings.readingComfortMode, action: #selector(readingComfortChanged(_:)))
        case .hideScrollIndicators:
            return switchCell(title: String(localized: "settings.reading.hide_scroll_indicators"), isOn: settings.hideScrollIndicators, action: #selector(hideScrollIndicatorsChanged(_:)))
        case .dohToggle:
            return switchCell(title: "DNS over HTTPS", isOn: settings.dohEnabled, action: #selector(dohToggleChanged(_:)))
        case .dohDebugLog:
            return valueCell(title: "调试日志", detail: "查看并复制最近 200 行")
        case .dohStatus:
            return infoCell(title: "DoH 状态", detail: LightweightDohProxyService.shared.statusDescription)
        case .dohProvider:
            return valueCell(title: String(localized: "settings.network.provider"), detail: settings.dohProvider.title)
        case .dohCustomURL:
            return valueCell(
                title: String(localized: "settings.network.custom_url"),
                detail: settings.dohServerURL.isEmpty ? String(localized: "settings.not_set") : settings.dohServerURL
            )
        case .cloudflareVerify:
            let hasClearance = URL(string: ForumInstance.linuxDoBaseURL)
                .map { WebCookieStore.shared.hasCookie(named: "cf_clearance", for: $0) } ?? false
            return valueCell(
                title: String(localized: "settings.network.cloudflare_verify"),
                detail: hasClearance
                    ? String(localized: "settings.network.cloudflare_ready")
                    : String(localized: "settings.network.cloudflare_required")
            )
        case .bottomBarLayout:
            return valueCell(title: "底栏布局", detail: bottomBarLayoutSummary())
        case .bottomAutoHide:
            return switchCell(title: String(localized: "settings.bottom_bar.auto_hide"), isOn: settings.bottomBarAutoHideEnabled, action: #selector(bottomAutoHideChanged(_:)))
        case .clearImageCache:
            return valueCell(title: String(localized: "settings.data.clear_image_cache"), detail: nil)
        case .autoOpen:
            return switchCell(title: String(localized: "settings.auto_open_last_forum"), isOn: settings.autoOpenLastForum, action: #selector(autoOpenToggleChanged(_:)))
        #if DEBUG
        case .renderPreview:
            return valueCell(title: "Render Preview", detail: nil)
        #endif
        }
    }

    private func valueCell(title: String, detail: String?) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = detail
        cell.detailTextLabel?.textColor = detail == nil ? .placeholderText : .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func switchCell(title: String, isOn: Bool, action: Selector) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.addTarget(self, action: action, for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    private func infoCell(title: String, detail: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = detail
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.selectionStyle = .none
        return cell
    }
}

extension SettingsCategoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = rows[indexPath.row]
        switch row {
        case .appearanceMode:
            showAppearancePicker(sourceView: tableView.cellForRow(at: indexPath))
        case .dohProvider:
            showDohProviderPicker(sourceView: tableView.cellForRow(at: indexPath))
        case .dohCustomURL:
            showCustomURLInput()
        case .dohDebugLog:
            navigationController?.pushViewController(DohDebugLogViewController(), animated: true)
        case .cloudflareVerify:
            guard let baseURL = URL(string: ForumInstance.linuxDoBaseURL) else { return }
            let vc = CloudflareVerificationViewController(baseURL: baseURL) { [weak self] in
                self?.tableView.reloadData()
            }
            navigationController?.pushViewController(vc, animated: true)
        case .bottomBarLayout:
            navigationController?.pushViewController(BottomBarLayoutViewController(), animated: true)
        case .clearImageCache:
            clearImageCache()
        #if DEBUG
        case .renderPreview:
            showRenderPreviewInput()
        #endif
        default:
            break
        }
    }
}

private extension SettingsCategoryViewController {
    @objc func autoOpenToggleChanged(_ sender: UISwitch) {
        settings.autoOpenLastForum = sender.isOn
    }

    @objc func readingComfortChanged(_ sender: UISwitch) {
        settings.readingComfortMode = sender.isOn
    }

    @objc func hideScrollIndicatorsChanged(_ sender: UISwitch) {
        settings.hideScrollIndicators = sender.isOn
    }

    @objc func bottomAutoHideChanged(_ sender: UISwitch) {
        settings.bottomBarAutoHideEnabled = sender.isOn
    }

    func bottomBarLayoutSummary() -> String {
        let visibleItems = settings.forumVisibleDynamicTabItems.map(\.title).joined(separator: " / ")
        if visibleItems.isEmpty {
            return "首页 + 我的"
        }
        return "首页 + \(visibleItems) + 我的"
    }

    @objc func dohToggleChanged(_ sender: UISwitch) {
        settings.dohEnabled = sender.isOn
        LightweightDohProxyService.shared.configureFromSettings()
        tableView.reloadData()
    }

    func showAppearancePicker(sourceView: UIView?) {
        let alert = UIAlertController(title: String(localized: "settings.dark_mode"), message: nil, preferredStyle: .actionSheet)
        for mode in AppSettings.AppearanceMode.allCases {
            let action = UIAlertAction(title: mode.title, style: .default) { [weak self] _ in
                self?.settings.appearanceMode = mode
                self?.tableView.reloadData()
            }
            action.setValue(mode == settings.appearanceMode, forKey: "checked")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true)
    }

    func showDohProviderPicker(sourceView: UIView?) {
        let alert = UIAlertController(title: "DoH Provider", message: nil, preferredStyle: .actionSheet)
        for provider in AppSettings.DoHProvider.allCases {
            let action = UIAlertAction(title: provider.title, style: .default) { [weak self] _ in
                self?.settings.dohProvider = provider
                LightweightDohProxyService.shared.configureFromSettings()
                self?.tableView.reloadData()
            }
            action.setValue(provider == settings.dohProvider, forKey: "checked")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true)
    }

    func showCustomURLInput() {
        let alert = UIAlertController(
            title: String(localized: "settings.network.custom_url"),
            message: String(localized: "settings.network.custom_url.message"),
            preferredStyle: .alert
        )
        alert.addTextField { [weak self] textField in
            guard let self else { return }
            textField.text = settings.dohCustomURL.isEmpty ? settings.dohServerURL : settings.dohCustomURL
            textField.placeholder = "https://dns.alidns.com/dns-query"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            let value = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self?.settings.dohCustomURL = value
            if !value.isEmpty {
                self?.settings.dohProvider = .custom
            }
            LightweightDohProxyService.shared.configureFromSettings()
            self?.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    func clearImageCache() {
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk { [weak self] in
            let alert = UIAlertController(
                title: nil,
                message: String(localized: "settings.data.cache_cleared"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
    }

    #if DEBUG
    func showRenderPreviewInput() {
        let alert = UIAlertController(title: "Render Preview", message: "Enter Topic URL", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "https://linux.do/t/topic/12345"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            guard let self,
                  let text = alert.textFields?.first?.text,
                  let url = URL(string: text),
                  let host = url.host,
                  let topicId = url.pathComponents.last.flatMap(Int.init)
            else { return }
            let scheme = url.scheme ?? "https"
            let api = DiscourseAPI(baseURL: "\(scheme)://\(host)")
            let vc = TopicDetailViewController(api: api, topicId: topicId)
            self.navigationController?.pushViewController(vc, animated: true)
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }
    #endif
}

private final class BottomBarLayoutViewController: ObservableViewController {
    private enum Section: Int, CaseIterable {
        case enabled
        case available
        case behavior

        var title: String {
            switch self {
            case .enabled: return "底栏布局"
            case .available: return "可添加"
            case .behavior: return "行为"
            }
        }
    }

    private let settings = AppSettings.shared

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        table.isEditing = true
        table.allowsSelectionDuringEditing = true
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "底栏"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "恢复默认",
            style: .plain,
            target: self,
            action: #selector(restoreDefaultTapped)
        )

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    override func updateUI() {
        tableView.reloadData()
    }

    @objc private func restoreDefaultTapped() {
        settings.resetForumDynamicTabItems()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var configuredItems: [AppSettings.ForumDynamicTabItem] {
        settings.forumDynamicTabItems
    }

    private var availableItems: [AppSettings.ForumDynamicTabItem] {
        let configured = Set(configuredItems)
        return AppSettings.ForumDynamicTabItem.allCases.filter { !configured.contains($0) }
    }

    private func item(for indexPath: IndexPath) -> AppSettings.ForumDynamicTabItem? {
        guard let section = Section(rawValue: indexPath.section) else { return nil }
        switch section {
        case .enabled:
            guard indexPath.row > 0 else { return nil }
            let itemIndex = indexPath.row - 1
            guard itemIndex < configuredItems.count else { return nil }
            return configuredItems[itemIndex]
        case .available:
            guard indexPath.row < availableItems.count else { return nil }
            return availableItems[indexPath.row]
        case .behavior:
            return nil
        }
    }

    private func setConfiguredItems(_ items: [AppSettings.ForumDynamicTabItem]) {
        settings.forumDynamicTabItems = items
    }

    private func addAvailableItem(at indexPath: IndexPath) {
        guard Section(rawValue: indexPath.section) == .available,
              let item = item(for: indexPath)
        else { return }

        guard configuredItems.count < AppSettings.maximumConfiguredForumDynamicTabItems else {
            showLimitMessage("最多保留 \(AppSettings.maximumConfiguredForumDynamicTabItems) 个功能候选。")
            return
        }

        setConfiguredItems(configuredItems + [item])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func actualBottomBarSummary() -> String {
        let visibleTitles = settings.forumVisibleDynamicTabItems.map(\.title)
        if visibleTitles.isEmpty {
            return "当前实际底栏：首页 + 我的。"
        }
        return "当前实际底栏：首页 + \(visibleTitles.joined(separator: " / ")) + 我的。"
    }

    private func showLimitMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension BottomBarLayoutViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .enabled:
            return configuredItems.count + 1
        case .available:
            return availableItems.count
        case .behavior:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .enabled where indexPath.row == 0:
            return fixedHomeCell()
        case .enabled:
            guard let item = item(for: indexPath) else { return UITableViewCell() }
            return configuredCell(for: item, itemIndex: indexPath.row - 1)
        case .available:
            guard let item = item(for: indexPath) else { return UITableViewCell() }
            return availableCell(for: item)
        case .behavior:
            return behaviorCell()
        }
    }

    private func fixedHomeCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: "house")
        content.imageProperties.tintColor = .systemBlue
        content.text = String(localized: "tab.home")
        content.secondaryText = "固定第一位"
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        let lockView = UIImageView(image: UIImage(systemName: "lock.fill"))
        lockView.tintColor = .tertiaryLabel
        cell.accessoryView = lockView
        cell.selectionStyle = .none
        return cell
    }

    private func configuredCell(for item: AppSettings.ForumDynamicTabItem, itemIndex: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: item.symbolName)
        content.imageProperties.tintColor = itemIndex < AppSettings.maximumVisibleForumDynamicTabItems ? .systemBlue : .secondaryLabel
        content.text = item.title
        content.secondaryText = itemIndex < AppSettings.maximumVisibleForumDynamicTabItems ? "显示在底栏" : "候选保留，暂不显示"
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.showsReorderControl = true
        return cell
    }

    private func availableCell(for item: AppSettings.ForumDynamicTabItem) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let canAdd = configuredItems.count < AppSettings.maximumConfiguredForumDynamicTabItems
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: item.symbolName)
        content.imageProperties.tintColor = canAdd ? .systemBlue : .tertiaryLabel
        content.text = item.title
        content.secondaryText = item.subtitle
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.textProperties.color = canAdd ? .label : .tertiaryLabel
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.selectionStyle = canAdd ? .default : .none
        return cell
    }

    private func behaviorCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = String(localized: "settings.bottom_bar.auto_hide")
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = settings.bottomBarAutoHideEnabled
        toggle.addTarget(self, action: #selector(bottomAutoHideChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    @objc private func bottomAutoHideChanged(_ sender: UISwitch) {
        settings.bottomBarAutoHideEnabled = sender.isOn
    }
}

extension BottomBarLayoutViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .enabled:
            return "\(actualBottomBarSummary())\n首页固定第一位，我的固定在底栏末尾但不显示在这个配置列表里。系统底栏最多 5 个入口，所以优先显示前 \(AppSettings.maximumVisibleForumDynamicTabItems) 个功能项。"
        case .available:
            if availableItems.isEmpty {
                return "没有更多可添加。"
            }
            return configuredItems.count >= AppSettings.maximumConfiguredForumDynamicTabItems
                ? "候选已满，先删除一个功能再添加。"
                : "最多保留 \(AppSettings.maximumConfiguredForumDynamicTabItems) 个功能候选；拖动已启用项目可调整显示优先级。"
        case .behavior:
            return "开启后，首页向上滑动会隐藏底栏，向下滑动或回到顶部会显示底栏。"
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        addAvailableItem(at: indexPath)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let section = Section(rawValue: indexPath.section) else { return false }
        switch section {
        case .enabled:
            return indexPath.row > 0
        case .available:
            return true
        case .behavior:
            return false
        }
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        guard let section = Section(rawValue: indexPath.section) else { return .none }
        switch section {
        case .enabled:
            return indexPath.row == 0 ? .none : .delete
        case .available:
            return .insert
        case .behavior:
            return .none
        }
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch editingStyle {
        case .delete:
            guard Section(rawValue: indexPath.section) == .enabled, indexPath.row > 0 else { return }
            guard configuredItems.count > AppSettings.minimumConfiguredForumDynamicTabItems else {
                showLimitMessage("至少保留 \(AppSettings.minimumConfiguredForumDynamicTabItems) 个功能入口。")
                return
            }
            var items = configuredItems
            items.remove(at: indexPath.row - 1)
            setConfiguredItems(items)
        case .insert:
            addAvailableItem(at: indexPath)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .enabled && indexPath.row > 0
    }

    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard Section(rawValue: sourceIndexPath.section) == .enabled,
              Section(rawValue: destinationIndexPath.section) == .enabled,
              sourceIndexPath.row > 0
        else {
            tableView.reloadData()
            return
        }

        var items = configuredItems
        let sourceIndex = sourceIndexPath.row - 1
        let destinationIndex = max(destinationIndexPath.row - 1, 0)
        guard sourceIndex < items.count, destinationIndex <= items.count else {
            tableView.reloadData()
            return
        }

        let item = items.remove(at: sourceIndex)
        items.insert(item, at: min(destinationIndex, items.count))
        setConfiguredItems(items)
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard Section(rawValue: proposedDestinationIndexPath.section) == .enabled else {
            return sourceIndexPath
        }
        return IndexPath(row: max(proposedDestinationIndexPath.row, 1), section: proposedDestinationIndexPath.section)
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .enabled && indexPath.row > 0
    }
}

private final class DohDebugLogViewController: UIViewController {
    private lazy var textView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.textColor = .label
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.isEditable = false
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "调试日志"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "复制",
            style: .plain,
            target: self,
            action: #selector(copyLog)
        )

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        reloadLog()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
        reloadLog()
    }

    private func reloadLog() {
        let log = DohDebugLog.snapshot()
        textView.text = log.isEmpty ? "暂无调试日志。刷新首页或重试网络请求。" : log
        if !textView.text.isEmpty {
            let length = (textView.text as NSString).length
            let bottom = NSRange(location: max(length - 1, 0), length: 1)
            textView.scrollRangeToVisible(bottom)
        }
    }

    @objc private func copyLog() {
        let log = DohDebugLog.snapshot()
        UIPasteboard.general.string = log.isEmpty ? textView.text : log
        let alert = UIAlertController(title: nil, message: "日志已复制", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

final class CloudflareVerificationViewController: UIViewController {
    private let baseURL: URL
    private let challengeURL: URL
    private let autoDismissOnSuccess: Bool
    private let onFinish: () -> Void
    private var progressObservation: NSKeyValueObservation?
    private var didDetectClearance = false
    private var isCheckingClearance = false
    private var needsVerificationRecheck = false
    private var initialClearanceValue: String?
    private var verificationCheckTask: Task<Void, Never>?

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let statusContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        return view
    }()

    private let statusIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "shield.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "cloudflare.verify.instructions")
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }()

    private let progressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .bar)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(baseURL: URL, autoDismissOnSuccess: Bool = false, onFinish: @escaping () -> Void) {
        self.baseURL = baseURL
        self.challengeURL = URL(string: "/challenge", relativeTo: baseURL)?.absoluteURL ?? baseURL
        self.autoDismissOnSuccess = autoDismissOnSuccess
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor deinit {
        verificationCheckTask?.cancel()
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "cloudflare.verify.title")
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "weblogin.done"),
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(reloadTapped)
        )
        navigationItem.leftItemsSupplementBackButton = true

        statusContainer.addSubview(statusIconView)
        statusContainer.addSubview(statusLabel)
        view.addSubview(statusContainer)
        view.addSubview(progressView)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            statusContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            statusContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            statusIconView.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 16),
            statusIconView.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 12),
            statusIconView.widthAnchor.constraint(equalToConstant: 20),
            statusIconView.heightAnchor.constraint(equalToConstant: 20),
            statusIconView.bottomAnchor.constraint(lessThanOrEqualTo: statusContainer.bottomAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: statusIconView.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor, constant: -10),

            progressView.topAnchor.constraint(equalTo: statusContainer.bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            self?.progressView.progress = Float(webView.estimatedProgress)
            self?.progressView.isHidden = webView.estimatedProgress >= 1.0
            guard webView.estimatedProgress >= 1.0 else { return }
            Task { @MainActor [weak self] in
                self?.scheduleVerificationChecks()
            }
        }

        initialClearanceValue = WebCookieStore.shared.cookieValue(named: "cf_clearance", for: baseURL)
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
        Task { @MainActor [weak self] in
            await self?.prepareAndLoadChallenge()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    @objc private func doneTapped() {
        onFinish()
        if navigationController?.viewControllers.first === self,
           navigationController?.presentingViewController != nil {
            navigationController?.dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func reloadTapped() {
        log("foreground reload tapped base=\(baseURL.absoluteString)")
        didDetectClearance = false
        isCheckingClearance = false
        needsVerificationRecheck = false
        verificationCheckTask?.cancel()
        verificationCheckTask = nil
        updateStatus(
            text: String(localized: "cloudflare.verify.instructions"),
            symbolName: "shield.fill",
            color: .systemOrange
        )
        Task { @MainActor [weak self] in
            await self?.prepareAndLoadChallenge()
        }
    }

    @MainActor
    private func prepareAndLoadChallenge() async {
        log("foreground load challenge base=\(baseURL.absoluteString) autoDismiss=\(autoDismissOnSuccess)")
        if autoDismissOnSuccess {
            WebCookieStore.shared.deleteCookie(named: "cf_clearance", for: baseURL)
            await deleteWebViewCookie(named: "cf_clearance")
        }
        webView.load(URLRequest(url: challengeURL))
    }

    @MainActor
    private func deleteWebViewCookie(named name: String) async {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        guard let host = baseURL.host?.lowercased() else { return }
        for cookie in cookies where cookie.name == name {
            let domain = cookie.domain.lowercased()
            let domainMatch = host == domain
                || (domain.hasPrefix(".") && (host == String(domain.dropFirst()) || host.hasSuffix(domain)))
            guard domainMatch else { continue }
            await withCheckedContinuation { continuation in
                cookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func syncCookiesAndDetectClearance() async {
        guard !didDetectClearance else { return }
        if isCheckingClearance {
            needsVerificationRecheck = true
            return
        }

        isCheckingClearance = true
        defer {
            isCheckingClearance = false
            if needsVerificationRecheck, !didDetectClearance {
                scheduleVerificationChecks()
            }
        }

        repeat {
            needsVerificationRecheck = false
            await performVerificationCheck()
        } while needsVerificationRecheck && !didDetectClearance
    }

    @MainActor
    private func performVerificationCheck() async {
        await syncCloudflareCookieFromWebView()
        let clearanceValue = WebCookieStore.shared.cookieValue(named: "cf_clearance", for: baseURL)
        let hasNewClearance = clearanceValue?.isEmpty == false
            && (!autoDismissOnSuccess || clearanceValue != initialClearanceValue)
        let hasKnownVerifiedRedirect = isKnownVerifiedRedirectURL(webView.url)
        let hasLoadedVerifiedPage = hasKnownVerifiedRedirect ? true : await hasLoadedVerifiedBasePage()
        let hasVerifiedPage = hasKnownVerifiedRedirect || hasLoadedVerifiedPage
        log(
            "foreground check url=\(webView.url?.absoluteString ?? "none") cf=\(clearanceValue?.isEmpty == false) newCf=\(hasNewClearance) verifiedPage=\(hasVerifiedPage)"
        )
        guard hasNewClearance || hasVerifiedPage else { return }
        let hasActiveChallenge = hasKnownVerifiedRedirect ? false : await pageHasActiveCloudflareChallenge()
        if hasActiveChallenge {
            log("foreground check active challenge still present")
            return
        }
        await updateStoredUserAgentFromWebView()
        completeVerification()
    }

    @MainActor
    private func completeIfKnownVerifiedRedirect(_ url: URL?) async {
        guard isKnownVerifiedRedirectURL(url) else { return }
        log("foreground known verified redirect url=\(url?.absoluteString ?? "none")")
        await drainCloudflareCookieFromWebView(maxAttempts: 6)
        await updateStoredUserAgentFromWebView()
        completeVerification()
    }

    @MainActor
    private func syncCloudflareCookieFromWebView() async {
        await WebCookieStore.shared.syncFromWebView(
            webView.configuration.websiteDataStore,
            names: ["cf_clearance"],
            for: baseURL
        )
    }

    @MainActor
    @discardableResult
    private func drainCloudflareCookieFromWebView(maxAttempts: Int) async -> String? {
        let attempts = max(maxAttempts, 1)
        for attempt in 0 ..< attempts {
            await syncCloudflareCookieFromWebView()
            if let clearanceValue = WebCookieStore.shared.cookieValue(named: "cf_clearance", for: baseURL),
               !clearanceValue.isEmpty {
                return clearanceValue
            }
            guard attempt < attempts - 1 else { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    @MainActor
    private func updateStoredUserAgentFromWebView() async {
        if let userAgent = try? await webView.evaluateJavaScript("navigator.userAgent") as? String {
            WebCookieStore.shared.userAgent = userAgent
        }
    }

    @MainActor
    private func completeVerification() {
        guard !didDetectClearance else { return }
        log("foreground complete base=\(baseURL.absoluteString)")
        didDetectClearance = true
        needsVerificationRecheck = false
        verificationCheckTask?.cancel()
        verificationCheckTask = nil
        updateStatus(
            text: String(localized: "cloudflare.verify.success"),
            symbolName: "checkmark.shield.fill",
            color: .systemGreen
        )
        NotificationCenter.default.post(
            name: DiscourseAPI.cloudflareVerificationCompletedNotification,
            object: nil,
            userInfo: [
                DiscourseAPI.cloudflareBaseURLUserInfoKey: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            ]
        )
        onFinish()
        guard autoDismissOnSuccess else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    @MainActor
    private func hasLoadedVerifiedBasePage() async -> Bool {
        guard let currentURL = webView.url,
              let currentHost = currentURL.host?.lowercased(),
              let baseHost = baseURL.host?.lowercased()
        else { return false }

        let hostMatches = currentHost == baseHost || currentHost.hasSuffix(".\(baseHost)")
        guard hostMatches else { return false }

        let path = currentURL.path.lowercased()
        guard !path.contains("/cdn-cgi/") else { return false }
        return !(await pageHasActiveCloudflareChallenge())
    }

    private func isKnownVerifiedRedirectURL(_ url: URL?) -> Bool {
        guard let url,
              let currentHost = url.host?.lowercased(),
              let baseHost = baseURL.host?.lowercased()
        else { return false }

        let hostMatches = currentHost == baseHost || currentHost.hasSuffix(".\(baseHost)")
        guard hostMatches else { return false }

        let path = url.path.lowercased()
        return path == "/404" || path == "/404/"
    }

    @MainActor
    private func pageHasActiveCloudflareChallenge() async -> Bool {
        guard let pageText = try? await webView.evaluateJavaScript("""
            [
              document.title || '',
              document.body ? document.body.innerText : '',
              document.body ? document.body.innerHTML : ''
            ].join('\\n')
            """) as? String else {
            return false
        }
        return Self.hasActiveCloudflareChallenge(in: pageText)
    }

    @MainActor
    private func scheduleVerificationChecks() {
        guard !didDetectClearance else { return }
        verificationCheckTask?.cancel()
        verificationCheckTask = Task { @MainActor [weak self] in
            let delays: [UInt64] = [
                0,
                250_000_000,
                700_000_000,
                1_500_000_000,
                2_500_000_000,
                4_000_000_000,
                7_000_000_000,
                10_000_000_000,
            ]
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled, let self, !self.didDetectClearance else { return }
                await self.syncCookiesAndDetectClearance()
            }
        }
    }

    private static func hasActiveCloudflareChallenge(in pageText: String) -> Bool {
        let lowerText = pageText.lowercased()
        return lowerText.contains("cf-turnstile")
            || lowerText.contains("challenge-running")
            || lowerText.contains("challenge-stage")
            || lowerText.contains("cf_chl_opt")
            || lowerText.contains("challenge-platform")
            || (lowerText.contains("just a moment") && lowerText.contains("cloudflare"))
    }

    private func failingURL(from error: Error) -> URL? {
        let nsError = error as NSError
        if let url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            return url
        }
        if let urlString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            return URL(string: urlString)
        }
        return nil
    }

    private func log(_ message: String) {
        DohDebugLog.record(message, subsystem: "CF")
    }

    private func updateStatus(text: String, symbolName: String, color: UIColor) {
        statusLabel.text = text
        statusIconView.image = UIImage(systemName: symbolName)
        statusIconView.tintColor = color
    }
}

extension CloudflareVerificationViewController: WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            await self?.syncCookiesAndDetectClearance()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        Task { @MainActor [weak self] in
            await self?.completeIfKnownVerifiedRedirect(url)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.completeIfKnownVerifiedRedirect(url)
            self.scheduleVerificationChecks()
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let url = webView.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.completeIfKnownVerifiedRedirect(url)
            self.scheduleVerificationChecks()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if didDetectClearance { return }
        if let url = failingURL(from: error), isKnownVerifiedRedirectURL(url) {
            log("foreground didFail verified url=\(url.absoluteString) error=\(error.localizedDescription)")
            Task { @MainActor [weak self] in
                await self?.completeIfKnownVerifiedRedirect(url)
            }
            return
        }
        log("foreground didFail url=\(webView.url?.absoluteString ?? "none") error=\(error.localizedDescription)")
        updateStatus(
            text: String(localized: "cloudflare.verify.load_failed"),
            symbolName: "exclamationmark.triangle.fill",
            color: .systemRed
        )
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if didDetectClearance { return }
        if let url = failingURL(from: error), isKnownVerifiedRedirectURL(url) {
            log("foreground didFailProvisional verified url=\(url.absoluteString) error=\(error.localizedDescription)")
            Task { @MainActor [weak self] in
                await self?.completeIfKnownVerifiedRedirect(url)
            }
            return
        }
        log("foreground didFailProvisional url=\(webView.url?.absoluteString ?? "none") error=\(error.localizedDescription)")
        updateStatus(
            text: String(localized: "cloudflare.verify.load_failed"),
            symbolName: "exclamationmark.triangle.fill",
            color: .systemRed
        )
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

private extension UIViewController {
    func enableSettingsInteractiveBackSwipe() {
        guard let navigationController,
              navigationController.viewControllers.count > 1
        else { return }
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = nil
    }
}
