import UIKit

/// 供应商编辑页（移植自 FluxDo AiProviderEditPage 的核心：基本信息、拉取模型、
/// 按模型启用、连通性测试、删除）。
@MainActor
final class AIProviderEditViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case basics
        case models
        case test
        case delete
    }

    private let store = AIModelServiceStore.shared
    private let existingProvider: AIProvider?
    private let providerType: AIProviderType
    private let onSaved: () -> Void

    private var models: [AIModel] = []
    private var isFetchingModels = false
    private var isTesting = false

    private let nameField: UITextField = {
        let field = UITextField()
        field.placeholder = String(localized: "ai.provider.name.placeholder", defaultValue: "名称，例如 My NewAPI")
        field.clearButtonMode = .whileEditing
        return field
    }()

    private let baseURLField: UITextField = {
        let field = UITextField()
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        return field
    }()

    private let apiKeyField: UITextField = {
        let field = UITextField()
        field.placeholder = "API Key"
        field.isSecureTextEntry = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        return field
    }()

    init(provider: AIProvider?, type: AIProviderType, onSaved: @escaping () -> Void) {
        existingProvider = provider
        providerType = type
        self.onSaved = onSaved
        super.init(style: .insetGrouped)
        models = provider?.models ?? []
        nameField.text = provider?.name
        baseURLField.text = provider?.baseURL ?? type.defaultBaseURL
        baseURLField.placeholder = type.defaultBaseURL
        if provider != nil {
            apiKeyField.placeholder = String(
                localized: "ai.provider.key.saved",
                defaultValue: "已保存，留空表示不修改"
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = existingProvider?.name ?? providerType.label
        tableView.keyboardDismissMode = .interactive
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "common.save", defaultValue: "保存"),
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
    }

    // MARK: - Data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        existingProvider == nil ? Section.allCases.count - 1 : Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .basics: return 3
        case .models: return models.count + 1
        case .test, .delete: return 1
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .basics:
            return String(
                format: String(localized: "ai.provider.section.basics", defaultValue: "基本信息 · %@"),
                providerType.label
            )
        case .models:
            return models.isEmpty
                ? String(localized: "ai.provider.section.models", defaultValue: "模型")
                : String(
                    format: String(localized: "ai.provider.section.models_count", defaultValue: "模型 · %d 已启用"),
                    models.filter(\.enabled).count
                )
        case .test, .delete, nil:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .basics:
            return String(
                localized: "ai.provider.section.basics.help",
                defaultValue: "地址未包含 /v1 时会自动补全；以 # 结尾表示严格使用原始地址。API Key 保存在钥匙串。"
            )
        case .models:
            return providerType == .anthropic
                ? String(localized: "ai.provider.models.anthropic.help", defaultValue: "Anthropic 使用预置模型列表。")
                : String(localized: "ai.provider.models.help", defaultValue: "拉取后可按需启用；重新拉取会保留已有的启用状态。")
        case .test, .delete, nil:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .basics:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            let field: UITextField
            switch indexPath.row {
            case 0: field = nameField
            case 1: field = baseURLField
            default: field = apiKeyField
            }
            embed(field, in: cell)
            return cell
        case .models:
            if indexPath.row == 0 {
                return makeFetchModelsCell()
            }
            return makeModelCell(models[indexPath.row - 1])
        case .test:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = isTesting
                ? String(localized: "ai.provider.testing", defaultValue: "测试中…")
                : String(localized: "ai.provider.test", defaultValue: "测试连接")
            content.textProperties.color = isTesting ? .secondaryLabel : AppSettings.shared.themeStyle.accentColor
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            return cell
        case .delete, nil:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = String(localized: "ai.provider.delete", defaultValue: "删除供应商")
            content.textProperties.color = .systemRed
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            return cell
        }
    }

    private func embed(_ field: UITextField, in cell: UITableViewCell) {
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
        ])
    }

    private func makeFetchModelsCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = isFetchingModels
            ? String(localized: "ai.provider.fetching", defaultValue: "正在拉取模型…")
            : String(localized: "ai.provider.fetch_models", defaultValue: "拉取模型列表")
        content.image = UIImage(systemName: isFetchingModels ? "hourglass" : "arrow.down.circle")
        content.imageProperties.tintColor = AppSettings.shared.themeStyle.accentColor
        content.textProperties.color = isFetchingModels ? .secondaryLabel : AppSettings.shared.themeStyle.accentColor
        cell.contentConfiguration = content
        return cell
    }

    private func makeModelCell(_ model: AIModel) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        var content = cell.defaultContentConfiguration()
        content.text = model.displayName
        let tags = AIModelTagFormatter.tags(for: model)
        var secondary = model.name == nil ? [] : [model.id]
        if !tags.isEmpty { secondary.append(tags.joined(separator: " · ")) }
        content.secondaryText = secondary.isEmpty ? nil : secondary.joined(separator: "  ")
        content.textProperties.font = .systemFont(ofSize: 14, weight: .medium)
        content.secondaryTextProperties.font = .systemFont(ofSize: 11)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
        cell.contentConfiguration = content

        let toggle = UISwitch()
        toggle.isOn = model.enabled
        toggle.onTintColor = AppSettings.shared.themeStyle.accentColor
        toggle.addAction(UIAction { [weak self] action in
            guard let self,
                  let toggle = action.sender as? UISwitch,
                  let index = models.firstIndex(where: { $0.id == model.id })
            else { return }
            models[index].enabled = toggle.isOn
            tableView.reloadSections(IndexSet(integer: Section.models.rawValue), with: .none)
        }, for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    // MARK: - Interaction

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .models where indexPath.row == 0:
            fetchModels()
        case .test:
            runTest()
        case .delete:
            confirmDelete()
        default:
            break
        }
    }

    private var trimmedBaseURL: String {
        baseURLField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func effectiveAPIKey() async -> String? {
        let typed = apiKeyField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !typed.isEmpty { return typed }
        guard let existingProvider else { return nil }
        return await store.apiKey(for: existingProvider.id)
    }

    private func fetchModels() {
        guard !isFetchingModels else { return }
        view.endEditing(true)
        isFetchingModels = true
        tableView.reloadSections(IndexSet(integer: Section.models.rawValue), with: .none)
        Task {
            defer {
                isFetchingModels = false
                tableView.reloadData()
            }
            guard let apiKey = await effectiveAPIKey(), !trimmedBaseURL.isEmpty else {
                presentMessage(String(localized: "ai.provider.need_key", defaultValue: "请先填写 API 地址和 API Key"))
                return
            }
            do {
                let fetched = try await AIProviderAPIService.fetchModels(
                    type: providerType,
                    baseURL: trimmedBaseURL,
                    apiKey: apiKey
                )
                // 重新拉取保留已有条目的启用状态与用户编辑过的能力。
                let existing = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
                models = fetched.map { model in
                    guard let old = existing[model.id] else { return model }
                    var merged = old.capabilitiesUserEdited ? old : model
                    merged.enabled = old.enabled
                    merged.name = model.name ?? old.name
                    return merged
                }
            } catch {
                presentMessage(error.localizedDescription)
            }
        }
    }

    private func runTest() {
        guard !isTesting else { return }
        view.endEditing(true)
        guard let model = models.first(where: \.enabled) ?? models.first else {
            presentMessage(String(localized: "ai.provider.test.no_model", defaultValue: "请先拉取并启用至少一个模型"))
            return
        }
        isTesting = true
        tableView.reloadSections(IndexSet(integer: Section.test.rawValue), with: .none)
        Task {
            defer {
                isTesting = false
                tableView.reloadSections(IndexSet(integer: Section.test.rawValue), with: .none)
            }
            guard let apiKey = await effectiveAPIKey() else {
                presentMessage(String(localized: "ai.provider.need_key", defaultValue: "请先填写 API 地址和 API Key"))
                return
            }
            let failure = await AIProviderAPIService.testModel(
                type: providerType,
                baseURL: trimmedBaseURL,
                apiKey: apiKey,
                modelID: model.id
            )
            if let failure {
                presentMessage(failure)
            } else {
                presentMessage(String(
                    format: String(localized: "ai.provider.test.ok", defaultValue: "连接成功（%@）"),
                    model.displayName
                ))
            }
        }
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedBaseURL.isEmpty else {
            presentMessage(String(localized: "ai.provider.need_url", defaultValue: "请填写 API 地址"))
            return
        }
        let typedKey = apiKeyField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if existingProvider == nil, typedKey.isEmpty {
            presentMessage(String(localized: "ai.provider.need_key_new", defaultValue: "请填写 API Key"))
            return
        }
        let fallbackName = URL(string: trimmedBaseURL)?.host ?? providerType.label
        let provider = AIProvider(
            id: existingProvider?.id ?? UUID().uuidString,
            name: name.isEmpty ? fallbackName : name,
            type: providerType,
            baseURL: trimmedBaseURL,
            models: models,
            pinned: existingProvider?.pinned ?? false
        )
        Task {
            do {
                try await store.save(provider, apiKey: typedKey.isEmpty ? nil : typedKey)
                onSaved()
                navigationController?.popViewController(animated: true)
            } catch {
                presentMessage(error.localizedDescription)
            }
        }
    }

    private func confirmDelete() {
        guard let existingProvider else { return }
        let alert = UIAlertController(
            title: String(localized: "ai.provider.delete.title", defaultValue: "删除供应商？"),
            message: String(
                localized: "ai.provider.delete.help",
                defaultValue: "供应商配置与钥匙串中的 API Key 都会被删除。"
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: String(localized: "common.delete", defaultValue: "删除"),
            style: .destructive
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await self.store.delete(providerID: existingProvider.id)
                    self.onSaved()
                    self.navigationController?.popViewController(animated: true)
                } catch {
                    self.presentMessage(error.localizedDescription)
                }
            }
        })
        present(alert, animated: true)
    }

    private func presentMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "确定"), style: .default))
        present(alert, animated: true)
    }
}
