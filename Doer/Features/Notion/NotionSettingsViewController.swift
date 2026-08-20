import UIKit

/// FluxDO-style Notion setup: configured summary, or 3-step guided cards.
final class NotionSettingsViewController: UIViewController {
    private let baseURL: String
    private let username: String?
    private let store = NotionConfigStore.shared
    private lazy var scopeKey = store.scopeKey(baseURL: baseURL, username: username)

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let tokenField = UITextField()
    private let databaseField = UITextField()
    private let scopeControl = UISegmentedControl(items: NotionSyncScope.allCases.map(\.title))
    private let autoSyncSwitch = UISwitch()

    private var obscureToken = true
    private var isEditingConfig = false
    private var isTesting = false
    private var isCreatingDB = false

    private var tokenToggleButton: UIButton?
    private var statusBanner: UIView?
    private var configuredCard: UIView?

    init(baseURL: String, username: String?) {
        self.baseURL = baseURL
        self.username = username
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableInteractiveBackSwipe()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "notion.settings.title", defaultValue: "Notion 同步")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        setupChrome()
        reloadContent()
    }

    private var isConfigured: Bool {
        store.isComplete(scopeKey: scopeKey)
    }

    private var showSteps: Bool {
        !isConfigured || isEditingConfig
    }

    // MARK: - Layout shell

    private func setupChrome() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
        ])
    }

    private func reloadContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let cfg = store.loadConfig(scopeKey: scopeKey)
        if tokenField.text?.isEmpty != false, let token = store.token(scopeKey: scopeKey), !token.isEmpty {
            tokenField.text = token
        }
        if databaseField.text?.isEmpty != false, let db = cfg.databaseId, !db.isEmpty {
            databaseField.text = db
        }
        autoSyncSwitch.isOn = cfg.autoSyncOnBookmark
        scopeControl.selectedSegmentIndex = NotionSyncScope.allCases.firstIndex(of: cfg.syncScope) ?? 1

        // Header subtitle
        contentStack.addArrangedSubview(makePageSubtitle())

        if isConfigured && !isEditingConfig {
            contentStack.addArrangedSubview(makeConfiguredCard())
            contentStack.addArrangedSubview(makeSectionTitle(String(localized: "notion.sync_options", defaultValue: "同步选项")))
            contentStack.addArrangedSubview(makeSyncOptionsCard())
        } else {
            contentStack.addArrangedSubview(
                makeStepCard(
                    index: 1,
                    title: String(localized: "notion.step1.title", defaultValue: "创建 Integration 获取 Token"),
                    body: String(
                        localized: "notion.step1.body",
                        defaultValue: "1. 打开 notion.so/my-integrations\n2. 新建 Internal Integration 并关联 workspace\n3. 复制 Internal Integration Secret\n4. 粘贴到下方输入框"
                    ),
                    done: !(store.token(scopeKey: scopeKey) ?? "").isEmpty,
                    bodyViews: makeTokenStepBody()
                )
            )
            contentStack.addArrangedSubview(
                makeStepCard(
                    index: 2,
                    title: String(localized: "notion.step2.title", defaultValue: "准备 Database"),
                    body: String(
                        localized: "notion.step2.body",
                        defaultValue: "把 Integration 通过 Connections 分享给目标 Page/Database。可粘贴 Database ID，或提供 Page ID 一键创建模板 Database（含 Name/URL/Topic ID/Post ID 等字段）。"
                    ),
                    done: !(cfg.databaseId ?? "").isEmpty,
                    bodyViews: makeDatabaseStepBody()
                )
            )
            contentStack.addArrangedSubview(
                makeStepCard(
                    index: 3,
                    title: String(localized: "notion.step3.title", defaultValue: "保存并测试"),
                    body: String(
                        localized: "notion.step3.body",
                        defaultValue: "测试通过后配置生效，可在话题导出菜单选择同步到 Notion。"
                    ),
                    done: isConfigured && !isEditingConfig,
                    bodyViews: makeSaveStepBody()
                )
            )
            contentStack.addArrangedSubview(makeSectionTitle(String(localized: "notion.sync_options", defaultValue: "同步选项")))
            contentStack.addArrangedSubview(makeSyncOptionsCard())
        }

        contentStack.addArrangedSubview(makeSecurityNote())
        if isEditingConfig {
            contentStack.addArrangedSubview(makeCancelEditButton())
        }
    }

    // MARK: - Building blocks

    private func makePageSubtitle() -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.text = String(
            localized: "notion.subtitle",
            defaultValue: "将帖子完整同步到你的 Notion Database"
        )
        return label
    }

    private func makeSectionTitle(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrap = UIView()
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -2),
        ])
        return wrap
    }

    private func makeCardContainer() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        return card
    }

    private func makeConfiguredCard() -> UIView {
        let card = makeCardContainer()
        let icon = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
        icon.tintColor = .systemGreen
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = String(localized: "notion.configured", defaultValue: "已配置完成")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.numberOfLines = 0
        subtitle.font = .preferredFont(forTextStyle: .footnote)
        subtitle.textColor = .secondaryLabel
        let db = store.loadConfig(scopeKey: scopeKey).databaseId ?? ""
        let masked = db.count > 8 ? String(db.prefix(4)) + "…" + String(db.suffix(4)) : db
        subtitle.text = String(
            localized: "notion.configured.detail",
            defaultValue: "Database \(masked) · Token 已保存在 Keychain"
        )

        let edit = makeSecondaryButton(
            title: String(localized: "notion.edit_config", defaultValue: "修改配置"),
            systemName: "slider.horizontal.3"
        )
        edit.addTarget(self, action: #selector(editTapped), for: .touchUpInside)

        let disconnect = makeDestructiveButton(
            title: String(localized: "notion.disconnect", defaultValue: "断开")
        )
        disconnect.addTarget(self, action: #selector(disconnectTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [edit, disconnect])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillEqually
        buttons.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(icon)
        card.addSubview(title)
        card.addSubview(subtitle)
        card.addSubview(buttons)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            subtitle.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 10),
            subtitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            buttons.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14),
            buttons.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            buttons.heightAnchor.constraint(equalToConstant: 40),
        ])
        configuredCard = card
        return card
    }

    private func makeStepCard(index: Int, title: String, body: String, done: Bool, bodyViews: [UIView]) -> UIView {
        let card = makeCardContainer()
        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.textAlignment = .center
        badge.font = .systemFont(ofSize: 13, weight: .bold)
        badge.layer.cornerRadius = 12
        badge.clipsToBounds = true
        if done {
            badge.text = "✓"
            badge.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.18)
            badge.textColor = .systemGreen
        } else {
            badge.text = "\(index)"
            badge.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.14)
            badge.textColor = .systemBlue
        }

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.text = body
        bodyLabel.font = .preferredFont(forTextStyle: .footnote)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        let inner = UIStackView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.axis = .vertical
        inner.spacing = 10
        inner.addArrangedSubview(bodyLabel)
        bodyViews.forEach { inner.addArrangedSubview($0) }

        card.addSubview(badge)
        card.addSubview(titleLabel)
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            inner.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 12),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return card
    }

    private func makeTokenStepBody() -> [UIView] {
        configureField(
            tokenField,
            placeholder: "secret_xxxxxxxxxxxxxxxx",
            secure: obscureToken
        )
        let open = makeSecondaryButton(
            title: String(localized: "notion.open_integrations", defaultValue: "打开 Notion Integrations"),
            systemName: "arrow.up.right.square"
        )
        open.addTarget(self, action: #selector(openIntegrations), for: .touchUpInside)

        let toggle = UIButton(type: .system)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.setImage(UIImage(systemName: obscureToken ? "eye.slash" : "eye"), for: .normal)
        toggle.addTarget(self, action: #selector(toggleTokenVisibility), for: .touchUpInside)
        tokenToggleButton = toggle

        let fieldRow = UIView()
        tokenField.translatesAutoresizingMaskIntoConstraints = false
        fieldRow.addSubview(tokenField)
        fieldRow.addSubview(toggle)
        NSLayoutConstraint.activate([
            tokenField.topAnchor.constraint(equalTo: fieldRow.topAnchor),
            tokenField.leadingAnchor.constraint(equalTo: fieldRow.leadingAnchor),
            tokenField.bottomAnchor.constraint(equalTo: fieldRow.bottomAnchor),
            tokenField.heightAnchor.constraint(equalToConstant: 44),
            toggle.leadingAnchor.constraint(equalTo: tokenField.trailingAnchor, constant: 8),
            toggle.trailingAnchor.constraint(equalTo: fieldRow.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: tokenField.centerYAnchor),
            toggle.widthAnchor.constraint(equalToConstant: 36),
        ])
        return [open, fieldRow]
    }

    private func makeDatabaseStepBody() -> [UIView] {
        configureField(databaseField, placeholder: "Database ID 或 Page/DB 链接", secure: false)
        let paste = makeSecondaryButton(
            title: String(localized: "common.paste", defaultValue: "粘贴"),
            systemName: "doc.on.clipboard"
        )
        paste.addTarget(self, action: #selector(pasteDatabaseID), for: .touchUpInside)

        let create = makeSecondaryButton(
            title: String(localized: "notion.create_template_db", defaultValue: "一键创建模板 Database"),
            systemName: "sparkles"
        )
        create.addTarget(self, action: #selector(createTemplateDB), for: .touchUpInside)
        create.isEnabled = !isCreatingDB

        let row = UIStackView(arrangedSubviews: [paste, create])
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        return [databaseField, row]
    }

    private func makeSaveStepBody() -> [UIView] {
        let saveTest = makePrimaryButton(
            title: isTesting
                ? String(localized: "notion.settings.testing", defaultValue: "测试中…")
                : String(localized: "notion.save_and_test", defaultValue: "保存并测试连接")
        )
        saveTest.addTarget(self, action: #selector(saveAndTest), for: .touchUpInside)
        saveTest.isEnabled = !isTesting
        return [saveTest]
    }

    private func makeSyncOptionsCard() -> UIView {
        let card = makeCardContainer()
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = String(localized: "notion.auto_sync_bookmark", defaultValue: "收藏时自动同步")
        title.font = .systemFont(ofSize: 15, weight: .medium)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = String(
            localized: "notion.auto_sync_desc",
            defaultValue: "收藏话题后后台同步到 Notion（需已完成配置）"
        )
        subtitle.font = .preferredFont(forTextStyle: .footnote)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

        autoSyncSwitch.addTarget(self, action: #selector(autoSyncChanged), for: .valueChanged)
        autoSyncSwitch.translatesAutoresizingMaskIntoConstraints = false

        let scopeTitle = UILabel()
        scopeTitle.translatesAutoresizingMaskIntoConstraints = false
        scopeTitle.text = String(localized: "notion.sync_scope", defaultValue: "默认同步范围")
        scopeTitle.font = .systemFont(ofSize: 15, weight: .medium)

        scopeControl.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        scopeControl.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(title)
        card.addSubview(subtitle)
        card.addSubview(autoSyncSwitch)
        card.addSubview(scopeTitle)
        card.addSubview(scopeControl)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(lessThanOrEqualTo: autoSyncSwitch.leadingAnchor, constant: -10),

            autoSyncSwitch.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            autoSyncSwitch.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: autoSyncSwitch.leadingAnchor, constant: -10),

            scopeTitle.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            scopeTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scopeTitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            scopeControl.topAnchor.constraint(equalTo: scopeTitle.bottomAnchor, constant: 8),
            scopeControl.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scopeControl.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            scopeControl.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return card
    }

    private func makeSecurityNote() -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor.secondarySystemFill
        box.layer.cornerRadius = 10
        box.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
        icon.tintColor = .secondaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        label.text = String(
            localized: "notion.token_security_note",
            defaultValue: "Integration Token 仅保存在本机 Keychain，不会写入普通配置备份文件。"
        )

        box.addSubview(icon)
        box.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
        ])
        return box
    }

    private func makeCancelEditButton() -> UIButton {
        let button = makeSecondaryButton(
            title: String(localized: "common.cancel", defaultValue: "取消修改"),
            systemName: "xmark"
        )
        button.addTarget(self, action: #selector(cancelEditTapped), for: .touchUpInside)
        return button
    }

    private func configureField(_ field: UITextField, placeholder: String, secure: Bool) {
        field.borderStyle = .none
        field.backgroundColor = .tertiarySystemFill
        field.layer.cornerRadius = 10
        field.layer.cornerCurve = .continuous
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.rightViewMode = .always
        field.placeholder = placeholder
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .asciiCapable
        field.font = .preferredFont(forTextStyle: .body)
    }

    private func makePrimaryButton(title: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.title = title
        config.baseBackgroundColor = AppSettings.shared.themeStyle.accentColor
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return button
    }

    private func makeSecondaryButton(title: String, systemName: String) -> UIButton {
        var config = UIButton.Configuration.bordered()
        config.cornerStyle = .large
        config.title = title
        config.image = UIImage(systemName: systemName)
        config.imagePadding = 6
        config.baseForegroundColor = .label
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }

    private func makeDestructiveButton(title: String) -> UIButton {
        var config = UIButton.Configuration.borderedProminent()
        config.cornerStyle = .large
        config.title = title
        config.baseBackgroundColor = .systemRed
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }

    private func persistOptionsOnly() {
        let scope = NotionSyncScope.allCases[safe: scopeControl.selectedSegmentIndex] ?? .allPosts
        var cfg = store.loadConfig(scopeKey: scopeKey)
        cfg.autoSyncOnBookmark = autoSyncSwitch.isOn
        cfg.syncScope = scope
        // keep existing database id if fields empty during configured mode
        if let text = databaseField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            cfg.databaseId = NotionSyncService.normalizeNotionID(text)
        }
        store.saveConfig(cfg, scopeKey: scopeKey)
    }

    private func currentDraftConfig() -> (token: String, config: NotionConfig)? {
        let token = tokenField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dbRaw = databaseField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty, !dbRaw.isEmpty else { return nil }
        let scope = NotionSyncScope.allCases[safe: scopeControl.selectedSegmentIndex] ?? .allPosts
        let cfg = NotionConfig(
            databaseId: NotionSyncService.normalizeNotionID(dbRaw),
            autoSyncOnBookmark: autoSyncSwitch.isOn,
            syncScope: scope
        )
        return (token, cfg)
    }

    private func presentToast(_ message: String, isError: Bool) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "好"), style: .default))
        // Prefer lightweight feel: short auto-dismiss
        present(alert, animated: true)
        if !isError {
            Task { @MainActor [weak alert] in
                try? await Task.sleep(nanoseconds: UInt64(1.2 * 1_000_000_000))
                alert?.dismiss(animated: true)
            }
        }
    }

    // MARK: - Actions

    @objc private func editTapped() {
        isEditingConfig = true
        reloadContent()
    }

    @objc private func cancelEditTapped() {
        isEditingConfig = false
        reloadContent()
    }

    @objc private func disconnectTapped() {
        let alert = UIAlertController(
            title: String(localized: "notion.disconnect", defaultValue: "断开"),
            message: String(localized: "notion.disconnect.confirm", defaultValue: "将清除本机 Notion Token 与 Database 配置"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "notion.disconnect", defaultValue: "断开"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.store.clear(scopeKey: self.scopeKey)
            self.tokenField.text = nil
            self.databaseField.text = nil
            self.autoSyncSwitch.isOn = false
            self.scopeControl.selectedSegmentIndex = 1
            self.isEditingConfig = false
            self.reloadContent()
            self.presentToast(String(localized: "notion.disconnected", defaultValue: "已断开 Notion"), isError: false)
        })
        present(alert, animated: true)
    }

    @objc private func toggleTokenVisibility() {
        obscureToken.toggle()
        tokenField.isSecureTextEntry = obscureToken
        tokenToggleButton?.setImage(UIImage(systemName: obscureToken ? "eye.slash" : "eye"), for: .normal)
    }

    @objc private func openIntegrations() {
        guard let url = URL(string: "https://www.notion.so/my-integrations") else { return }
        UIApplication.shared.open(url)
    }

    @objc private func pasteDatabaseID() {
        if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            databaseField.text = NotionSyncService.normalizeNotionID(text)
        }
    }

    @objc private func autoSyncChanged() {
        persistOptionsOnly()
    }

    @objc private func scopeChanged() {
        persistOptionsOnly()
    }

    @objc private func saveAndTest() {
        guard let draft = currentDraftConfig() else {
            presentToast(String(localized: "notion.fill_token_and_db", defaultValue: "请填写 Token 和 Database ID"), isError: true)
            return
        }
        isTesting = true
        reloadContent()
        Task {
            do {
                try store.setToken(draft.token, scopeKey: scopeKey)
                store.saveConfig(draft.config, scopeKey: scopeKey)
                let title = try await NotionSyncService(
                    config: draft.config,
                    token: draft.token,
                    baseURL: baseURL
                ).testConnection()
                await MainActor.run {
                    self.isTesting = false
                    self.isEditingConfig = false
                    self.reloadContent()
                    self.presentToast(
                        String(localized: "notion.test_ok", defaultValue: "连接成功：\(title)"),
                        isError: false
                    )
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.reloadContent()
                    self.presentToast(
                        String(localized: "notion.test_failed", defaultValue: "连接失败：\(error.localizedDescription)"),
                        isError: true
                    )
                }
            }
        }
    }

    @objc private func createTemplateDB() {
        let token = tokenField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else {
            presentToast(String(localized: "notion.token_required", defaultValue: "请先填写 Integration Token"), isError: true)
            return
        }
        let alert = UIAlertController(
            title: String(localized: "notion.create_template_db", defaultValue: "一键创建模板 Database"),
            message: String(
                localized: "notion.parent_page_prompt",
                defaultValue: "粘贴已分享给 Integration 的 Page ID 或 Page 链接"
            ),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Page ID / URL"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                field.text = clip
            }
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.create", defaultValue: "创建"), style: .default) { [weak self] _ in
            guard let self else { return }
            let parent = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !parent.isEmpty else { return }
            self.isCreatingDB = true
            self.reloadContent()
            Task {
                do {
                    try self.store.setToken(token, scopeKey: self.scopeKey)
                    let cfg = NotionConfig(
                        databaseId: nil,
                        autoSyncOnBookmark: self.autoSyncSwitch.isOn,
                        syncScope: NotionSyncScope.allCases[safe: self.scopeControl.selectedSegmentIndex] ?? .allPosts
                    )
                    let service = NotionSyncService(config: cfg, token: token, baseURL: self.baseURL)
                    let dbID = try await service.createTemplateDatabase(parentPageId: parent)
                    var saved = cfg
                    saved.databaseId = dbID
                    self.store.saveConfig(saved, scopeKey: self.scopeKey)
                    await MainActor.run {
                        self.databaseField.text = dbID
                        self.isCreatingDB = false
                        self.reloadContent()
                        self.presentToast(
                            String(localized: "notion.database_created", defaultValue: "Database 已创建，ID 已填入"),
                            isError: false
                        )
                    }
                } catch {
                    await MainActor.run {
                        self.isCreatingDB = false
                        self.reloadContent()
                        self.presentToast(
                            String(localized: "notion.db_create_failed", defaultValue: "创建失败：\(error.localizedDescription)"),
                            isError: true
                        )
                    }
                }
            }
        })
        present(alert, animated: true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
