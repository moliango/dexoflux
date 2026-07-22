import UIKit

// MARK: - 聊天记录

@MainActor
final class AIChatHistoryViewController: UITableViewController {
    private let api: DiscourseAPI
    private var sessions: [AIChatSession] = []

    init(api: DiscourseAPI) {
        self.api = api
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "ai.history.title", defaultValue: "聊天记录")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task {
            sessions = await AIChatStore.shared.sessions()
            tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(sessions.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        guard !sessions.isEmpty else {
            content.text = String(localized: "ai.history.empty", defaultValue: "还没有聊天记录")
            content.textProperties.color = .secondaryLabel
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            return cell
        }
        let session = sessions[indexPath.row]
        content.text = session.topicTitle
        var parts: [String] = []
        if let preview = session.lastMessagePreview, !preview.isEmpty {
            parts.append(preview)
        }
        parts.append(Self.dateFormatter.string(from: session.updatedAt))
        content.secondaryText = parts.joined(separator: " · ")
        content.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
        content.textProperties.numberOfLines = 1
        content.secondaryTextProperties.font = .systemFont(ofSize: 12)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 1
        content.textToSecondaryTextVerticalPadding = 3
        content.image = UIImage(systemName: "bubble.left.and.text.bubble.right")
        content.imageProperties.tintColor = AppSettings.shared.themeStyle.accentColor
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !sessions.isEmpty else { return }
        let session = sessions[indexPath.row]
        let chat = AIChatSheetViewController(
            api: api,
            topicId: session.topicId,
            topicTitle: session.topicTitle,
            session: session
        )
        if let sheet = chat.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(chat, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !sessions.isEmpty else { return nil }
        let session = sessions[indexPath.row]
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "common.delete", defaultValue: "删除")
        ) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            Task {
                try? await AIChatStore.shared.deleteSession(id: session.id)
                self.sessions = await AIChatStore.shared.sessions()
                self.tableView.reloadData()
                completion(true)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

// MARK: - 快捷词管理

@MainActor
final class AIPromptPresetsViewController: UITableViewController {
    private var presets: [AIPromptPreset] = []

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "ai.presets.manage.title", defaultValue: "快捷词管理")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addTapped)
        )
        Task { await reload() }
    }

    private func reload() async {
        presets = await AIChatStore.shared.presets()
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(presets.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        String(localized: "ai.presets.footer", defaultValue: "快捷词显示在 AI 助手底部，点按即可向 AI 发送对应内容。")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        guard !presets.isEmpty else {
            content.text = String(localized: "ai.presets.empty", defaultValue: "还没有快捷词，点右上角 + 添加")
            content.textProperties.color = .secondaryLabel
            content.textProperties.alignment = .center
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            return cell
        }
        let preset = presets[indexPath.row]
        content.text = preset.title
        content.secondaryText = preset.prompt
        content.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
        content.secondaryTextProperties.font = .systemFont(ofSize: 12)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.textToSecondaryTextVerticalPadding = 3
        content.image = UIImage(systemName: "bolt")
        content.imageProperties.tintColor = AppSettings.shared.themeStyle.accentColor
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !presets.isEmpty else {
            addTapped()
            return
        }
        presentEditor(preset: presets[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !presets.isEmpty else { return nil }
        let preset = presets[indexPath.row]
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "common.delete", defaultValue: "删除")
        ) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            Task {
                try? await AIChatStore.shared.deletePreset(id: preset.id)
                await self.reload()
                completion(true)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    @objc private func addTapped() {
        presentEditor(preset: nil)
    }

    private func presentEditor(preset: AIPromptPreset?) {
        let alert = UIAlertController(
            title: preset == nil
                ? String(localized: "ai.presets.add", defaultValue: "添加快捷词")
                : String(localized: "ai.presets.edit", defaultValue: "编辑快捷词"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = String(localized: "ai.presets.name", defaultValue: "名称，例如 总结这个话题")
            $0.text = preset?.title
        }
        alert.addTextField {
            $0.placeholder = String(localized: "ai.presets.prompt", defaultValue: "发送给 AI 的内容")
            $0.text = preset?.prompt
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.save", defaultValue: "保存"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let fields = alert?.textFields,
                  let title = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let prompt = fields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty
            else { return }
            Task {
                try? await AIChatStore.shared.savePreset(AIPromptPreset(
                    id: preset?.id ?? UUID(),
                    title: title,
                    prompt: prompt
                ))
                await self.reload()
            }
        })
        present(alert, animated: true)
    }
}

// MARK: - 高级设置

@MainActor
final class AIAdvancedSettingsViewController: UITableViewController, UITextViewDelegate {
    private enum Section: Int, CaseIterable {
        case contextScope
        case systemPrompt
    }

    private let promptTextView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 14)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "ai.advanced.title", defaultValue: "高级设置")
        tableView.keyboardDismissMode = .interactive
        promptTextView.delegate = self
        promptTextView.text = AIChatSettings.customSystemPrompt
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .contextScope: return AIContextScope.allCases.count
        case .systemPrompt: return 1
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .contextScope:
            return String(localized: "ai.advanced.context", defaultValue: "默认上下文范围")
        case .systemPrompt:
            return String(localized: "ai.advanced.system_prompt", defaultValue: "自定义系统提示词")
        case nil:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .contextScope:
            return String(localized: "ai.advanced.context.help", defaultValue: "打开 AI 助手时默认携带的话题楼层数量。")
        case .systemPrompt:
            return String(localized: "ai.advanced.system_prompt.help", defaultValue: "会追加在默认系统提示之后，留空表示不追加。")
        case nil:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .contextScope:
            let scope = AIContextScope.allCases[indexPath.row]
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = scope.label
            cell.contentConfiguration = content
            cell.accessoryType = scope == AIChatSettings.defaultContextScope ? .checkmark : .none
            cell.tintColor = AppSettings.shared.themeStyle.accentColor
            return cell
        case .systemPrompt, nil:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.contentView.addSubview(promptTextView)
            NSLayoutConstraint.activate([
                promptTextView.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                promptTextView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 4),
                promptTextView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -4),
                promptTextView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                promptTextView.heightAnchor.constraint(equalToConstant: 120),
            ])
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .contextScope else { return }
        AIChatSettings.defaultContextScope = AIContextScope.allCases[indexPath.row]
        tableView.reloadSections(IndexSet(integer: Section.contextScope.rawValue), with: .none)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        AIChatSettings.customSystemPrompt = textView.text ?? ""
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AIChatSettings.customSystemPrompt = promptTextView.text ?? ""
    }
}
