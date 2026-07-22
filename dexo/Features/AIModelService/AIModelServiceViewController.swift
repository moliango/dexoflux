import UIKit

/// AI 模型服务 hub（FluxDo AiProvidersPage 结构）：
/// 供应商 / 默认模型 / 聊天记录 / 快捷词管理 / 高级设置。
@MainActor
final class AIModelServiceViewController: UITableViewController {
    private struct Entry {
        let title: String
        let subtitle: String?
        let symbolName: String
        let action: () -> Void
    }

    private let api: DiscourseAPI?
    private let store = AIModelServiceStore.shared
    private var providers: [AIProvider] = []
    private var entries: [Entry] = []

    init(api: DiscourseAPI? = nil) {
        self.api = api
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "ai.service.title", defaultValue: "AI 模型服务")
        tableView.backgroundColor = .systemGroupedBackground
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reload() }
    }

    private func reload() async {
        providers = await store.providers()
        rebuildEntries()
        tableView.reloadData()
    }

    private func rebuildEntries() {
        var entries: [Entry] = []

        let providerSubtitle: String
        if providers.isEmpty {
            providerSubtitle = String(localized: "ai.hub.providers.none", defaultValue: "还没有配置 AI 供应商")
        } else {
            providerSubtitle = String(
                format: String(localized: "ai.hub.providers.count", defaultValue: "%d 个供应商"),
                providers.count
            )
        }
        entries.append(Entry(
            title: String(localized: "ai.hub.providers", defaultValue: "供应商"),
            subtitle: providerSubtitle,
            symbolName: "server.rack"
        ) { [weak self] in
            self?.openProviderList()
        })

        if providers.contains(where: { !$0.enabledModels.isEmpty }) {
            let subtitle: String
            if let ref = AIModelServiceStore.defaultModelRef(),
               let provider = providers.first(where: { $0.id == ref.providerID }),
               let model = provider.models.first(where: { $0.id == ref.modelID }) {
                subtitle = "\(provider.name) · \(model.displayName)"
            } else {
                subtitle = String(localized: "ai.service.default_model.none", defaultValue: "未选择")
            }
            entries.append(Entry(
                title: String(localized: "ai.hub.default_model", defaultValue: "默认模型"),
                subtitle: subtitle,
                symbolName: "slider.horizontal.3"
            ) { [weak self] in
                self?.openDefaultModelPicker()
            })
        }

        if let api {
            entries.append(Entry(
                title: String(localized: "ai.history.title", defaultValue: "聊天记录"),
                subtitle: nil,
                symbolName: "clock.arrow.circlepath"
            ) { [weak self] in
                self?.navigationController?.pushViewController(AIChatHistoryViewController(api: api), animated: true)
            })
        }

        entries.append(Entry(
            title: String(localized: "ai.presets.manage.title", defaultValue: "快捷词管理"),
            subtitle: String(localized: "ai.presets.manage.subtitle", defaultValue: "管理 AI 助手底部的快捷词"),
            symbolName: "bolt"
        ) { [weak self] in
            self?.navigationController?.pushViewController(AIPromptPresetsViewController(), animated: true)
        })

        entries.append(Entry(
            title: String(localized: "ai.advanced.title", defaultValue: "高级设置"),
            subtitle: nil,
            symbolName: "gearshape"
        ) { [weak self] in
            self?.navigationController?.pushViewController(AIAdvancedSettingsViewController(), animated: true)
        })

        self.entries = entries
    }

    private func openProviderList() {
        navigationController?.pushViewController(AIProviderListViewController(), animated: true)
    }

    private func openDefaultModelPicker() {
        let options: [(AIProvider, AIModel)] = providers.flatMap { provider in
            provider.enabledModels.map { (provider, $0) }
        }
        guard !options.isEmpty else { return }
        let controller = AIDefaultModelPickerViewController(options: options) { [weak self] in
            Task { await self?.reload() }
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let entry = entries[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = entry.title
        content.secondaryText = entry.subtitle
        content.textProperties.font = .systemFont(ofSize: 16, weight: .medium)
        content.secondaryTextProperties.font = .systemFont(ofSize: 12)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
        content.textToSecondaryTextVerticalPadding = 3
        content.image = UIImage(systemName: entry.symbolName)
        content.imageProperties.tintColor = .secondaryLabel
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        entries[indexPath.row].action()
    }
}

/// 供应商列表页（原主页面的供应商管理部分）。
@MainActor
final class AIProviderListViewController: UITableViewController {
    private let store = AIModelServiceStore.shared
    private var providers: [AIProvider] = []

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "ai.hub.providers", defaultValue: "供应商")
        tableView.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addProviderTapped)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reload() }
    }

    private func reload() async {
        providers = await store.providers()
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(providers.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        String(
            localized: "ai.service.section.providers.help",
            defaultValue: "支持 OpenAI 兼容接口（如 NewAPI 网关）、Gemini 和 Anthropic。API Key 保存在钥匙串中。"
        )
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !providers.isEmpty else {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = String(localized: "ai.service.empty.title", defaultValue: "还没有 AI 供应商")
            content.secondaryText = String(localized: "ai.service.empty.help", defaultValue: "点这里或右上角 + 添加")
            content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
            content.textProperties.alignment = .center
            content.secondaryTextProperties.font = .systemFont(ofSize: 12)
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.alignment = .center
            content.textToSecondaryTextVerticalPadding = 4
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 22, leading: 16, bottom: 22, trailing: 16)
            cell.contentConfiguration = content
            return cell
        }
        let provider = providers[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = provider.name
        var parts = [provider.type.label]
        if let host = URL(string: provider.baseURL)?.host {
            parts.append(host)
        }
        let enabledCount = provider.enabledModels.count
        if enabledCount > 0 {
            parts.append(String(
                format: String(localized: "ai.service.provider.models", defaultValue: "%d 个模型已启用"),
                enabledCount
            ))
        }
        content.secondaryText = parts.joined(separator: " · ")
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.secondaryTextProperties.font = .systemFont(ofSize: 12)
        content.secondaryTextProperties.color = .secondaryLabel
        content.textToSecondaryTextVerticalPadding = 3
        content.image = UIImage(systemName: providerSymbol(provider.type))
        content.imageProperties.tintColor = providerTint(provider.type)
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !providers.isEmpty else {
            addProviderTapped()
            return
        }
        openEditor(provider: providers[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !providers.isEmpty else { return nil }
        let provider = providers[indexPath.row]
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "common.delete", defaultValue: "删除")
        ) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            Task {
                do {
                    try await self.store.delete(providerID: provider.id)
                    await self.reload()
                    completion(true)
                } catch {
                    completion(false)
                }
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    @objc private func addProviderTapped() {
        let sheet = UIAlertController(
            title: String(localized: "ai.service.add", defaultValue: "添加供应商"),
            message: String(localized: "ai.service.add.help", defaultValue: "选择接口类型"),
            preferredStyle: .actionSheet
        )
        for type in AIProviderType.allCases {
            sheet.addAction(UIAlertAction(title: type.label, style: .default) { [weak self] _ in
                self?.openEditor(provider: nil, type: type)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    private func openEditor(provider: AIProvider?, type: AIProviderType = .openai) {
        let controller = AIProviderEditViewController(
            provider: provider,
            type: provider?.type ?? type
        ) { [weak self] in
            Task { await self?.reload() }
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func providerSymbol(_ type: AIProviderType) -> String {
        switch type {
        case .openai, .openaiResponse: return "cpu"
        case .gemini: return "diamond"
        case .anthropic: return "asterisk"
        }
    }

    private func providerTint(_ type: AIProviderType) -> UIColor {
        switch type {
        case .openai: return .systemTeal
        case .openaiResponse: return .systemCyan
        case .gemini: return .systemBlue
        case .anthropic: return .systemOrange
        }
    }
}

/// 默认模型选择列表（按供应商分组，勾选当前默认）。
@MainActor
final class AIDefaultModelPickerViewController: UITableViewController {
    private let groups: [(provider: AIProvider, models: [AIModel])]
    private let onChanged: () -> Void

    init(options: [(AIProvider, AIModel)], onChanged: @escaping () -> Void) {
        var grouped: [(AIProvider, [AIModel])] = []
        for (provider, model) in options {
            if let index = grouped.firstIndex(where: { $0.0.id == provider.id }) {
                grouped[index].1.append(model)
            } else {
                grouped.append((provider, [model]))
            }
        }
        groups = grouped.map { (provider: $0.0, models: $0.1) }
        self.onChanged = onChanged
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "ai.service.default_model.title", defaultValue: "选择默认模型")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        groups.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        groups[section].provider.name
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups[section].models.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let group = groups[indexPath.section]
        let model = group.models[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = model.displayName
        let tags = AIModelTagFormatter.tags(for: model)
        content.secondaryText = tags.isEmpty ? nil : tags.joined(separator: " · ")
        content.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
        content.secondaryTextProperties.font = .systemFont(ofSize: 11)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        let current = AIModelServiceStore.defaultModelRef()
        let isSelected = current?.providerID == group.provider.id && current?.modelID == model.id
        cell.accessoryType = isSelected ? .checkmark : .none
        cell.tintColor = AppSettings.shared.themeStyle.accentColor
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let group = groups[indexPath.section]
        let model = group.models[indexPath.row]
        AIModelServiceStore.setDefaultModelRef(
            AIDefaultModelRef(providerID: group.provider.id, modelID: model.id)
        )
        tableView.reloadData()
        onChanged()
        navigationController?.popViewController(animated: true)
    }
}

enum AIModelTagFormatter {
    static func tags(for model: AIModel) -> [String] {
        var tags: [String] = []
        if model.isVision {
            tags.append(String(localized: "ai.model.tag.vision", defaultValue: "视觉"))
        }
        if model.isReasoning {
            tags.append(String(localized: "ai.model.tag.reasoning", defaultValue: "推理"))
        }
        if model.isTool {
            tags.append(String(localized: "ai.model.tag.tool", defaultValue: "工具"))
        }
        if model.isImageOutput {
            tags.append(String(localized: "ai.model.tag.image", defaultValue: "生图"))
        }
        return tags
    }
}
