import UIKit

@MainActor
final class NewAPICheckInViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case overview
        case platforms
    }

    private let store: NewAPICheckInStore
    private let service: NewAPICheckInService
    private var platforms: [NewAPICheckInPlatform] = []
    private var runningPlatformIDs = Set<UUID>()
    private var isRunningBatch = false

    // Auto-relogin queue: platforms whose sign-in came back authenticationExpired.
    private var reloginQueue: [UUID] = []
    private var pendingResignPlatformID: UUID?
    private var isAutoReloginActive = false
    private var lastLoginSaved = false

    init(store: NewAPICheckInStore, service: NewAPICheckInService) {
        self.store = store
        self.service = service
        super.init(style: .insetGrouped)
    }

    convenience init() {
        let runtime = NewAPICheckInRuntime.shared
        self.init(store: runtime.store, service: runtime.service)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "plugins.newapi.check_in", defaultValue: "签到")
        tableView.register(NewAPIPlatformCell.self, forCellReuseIdentifier: NewAPIPlatformCell.reuseIdentifier)
        tableView.backgroundColor = .systemGroupedBackground
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 76, bottom: 0, right: 16)
        tableView.sectionHeaderTopPadding = 12
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addPlatformTapped)
        )
        Task { await reload() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard isAutoReloginActive else { return }
        isAutoReloginActive = false
        if lastLoginSaved {
            let platformID = pendingResignPlatformID
            pendingResignPlatformID = nil
            Task {
                if let platformID,
                   let platform = await store.platforms().first(where: { $0.id == platformID }) {
                    // Fresh cookie just saved — retry once, but never loop back into relogin.
                    await signIn(platform, allowAutoRelogin: false)
                }
                processReloginQueueIfIdle()
            }
        } else {
            // User backed out of the login page — stop bothering them.
            reloginQueue.removeAll()
        }
    }

    // MARK: - Static cells

    private lazy var summaryCell: NewAPISummaryCell = {
        let cell = NewAPISummaryCell()
        cell.onSignInAll = { [weak self] in self?.signInAllTapped() }
        return cell
    }()

    private lazy var autoReloginCell: UITableViewCell = {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = String(localized: "plugins.newapi.auto_relogin", defaultValue: "自动重新登录")
        content.secondaryText = String(
            localized: "plugins.newapi.auto_relogin.help",
            defaultValue: "登录失效时自动打开登录页刷新 Cookie"
        )
        content.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
        content.secondaryTextProperties.font = .systemFont(ofSize: 12)
        content.secondaryTextProperties.color = .secondaryLabel
        content.textToSecondaryTextVerticalPadding = 3
        content.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        content.imageProperties.tintColor = AppSettings.shared.themeStyle.accentColor
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = NewAPICheckInRuntime.autoReloginEnabled
        toggle.onTintColor = AppSettings.shared.themeStyle.accentColor
        toggle.addTarget(self, action: #selector(autoReloginToggled(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }()

    private lazy var emptyCell: UITableViewCell = {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .default
        var content = cell.defaultContentConfiguration()
        content.text = String(localized: "plugins.newapi.empty.title", defaultValue: "还没有平台")
        content.secondaryText = String(
            localized: "plugins.newapi.empty.action",
            defaultValue: "点这里或右上角 + 添加 NewAPI 平台"
        )
        content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
        content.textProperties.alignment = .center
        content.secondaryTextProperties.font = .systemFont(ofSize: 12)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.alignment = .center
        content.textToSecondaryTextVerticalPadding = 4
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 22, leading: 16, bottom: 22, trailing: 16)
        cell.contentConfiguration = content
        return cell
    }()

    @objc private func autoReloginToggled(_ sender: UISwitch) {
        NewAPICheckInRuntime.autoReloginEnabled = sender.isOn
    }

    // MARK: - Table data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .overview: return 2
        case .platforms: return max(platforms.count, 1)
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard Section(rawValue: section) == .platforms else { return nil }
        return platforms.isEmpty
            ? String(localized: "plugins.newapi.section.platforms", defaultValue: "平台")
            : String(
                format: String(localized: "plugins.newapi.section.platforms_count", defaultValue: "平台 · %d"),
                platforms.count
            )
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .overview:
            return indexPath.row == 0 ? summaryCell : autoReloginCell
        case .platforms, nil:
            guard !platforms.isEmpty else { return emptyCell }
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: NewAPIPlatformCell.reuseIdentifier,
                for: indexPath
            ) as? NewAPIPlatformCell else {
                assertionFailure("NewAPIPlatformCell was not registered")
                return UITableViewCell()
            }
            let platform = platforms[indexPath.row]
            cell.configure(
                name: platform.name,
                metaText: metaText(for: platform),
                balance: balanceText(for: platform),
                statusText: statusTitle(platform.lastStatus),
                statusColor: tintColor(for: platform.lastStatus),
                monogramSeed: URL(string: platform.baseURL)?.host ?? platform.name,
                isRunning: runningPlatformIDs.contains(platform.id)
            )
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .platforms else { return }
        guard !platforms.isEmpty else {
            addPlatformTapped()
            return
        }
        let platform = platforms[indexPath.row]
        let controller = NewAPICheckInDetailViewController(
            platform: platform,
            store: store,
            service: service
        ) { [weak self] in
            Task { await self?.reload() }
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .platforms, !platforms.isEmpty else { return nil }
        let platform = platforms[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: String(localized: "common.delete", defaultValue: "删除")) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            Task {
                do {
                    try await self.store.delete(platformID: platform.id)
                    await self.reload()
                    completion(true)
                } catch {
                    self.presentError(error.localizedDescription)
                    completion(false)
                }
            }
        }
        let signIn = UIContextualAction(style: .normal, title: String(localized: "plugins.newapi.sign_in", defaultValue: "签到")) { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            Task {
                await self.signIn(platform)
                completion(true)
            }
        }
        signIn.backgroundColor = AppSettings.shared.themeStyle.accentColor
        return UISwipeActionsConfiguration(actions: [delete, signIn])
    }

    // MARK: - Actions

    @objc private func refreshTriggered() {
        Task { await reload() }
    }

    @objc private func addPlatformTapped() {
        let sheet = UIAlertController(
            title: String(localized: "plugins.newapi.add", defaultValue: "添加 NewAPI 平台"),
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: String(localized: "plugins.newapi.web_login", defaultValue: "网页登录"),
            style: .default
        ) { [weak self] _ in
            self?.promptForWebLoginURL()
        })
        sheet.addAction(UIAlertAction(
            title: String(localized: "plugins.newapi.manual_add", defaultValue: "手动添加"),
            style: .default
        ) { [weak self] _ in
            self?.presentManualAdd()
        })
        sheet.addAction(UIAlertAction(
            title: String(localized: "plugins.newapi.curl_import", defaultValue: "从 Curl 导入"),
            style: .default
        ) { [weak self] _ in
            self?.presentCurlImport()
        })
        sheet.addAction(UIAlertAction(
            title: String(localized: "plugins.newapi.history.title", defaultValue: "签到历史"),
            style: .default
        ) { [weak self] _ in
            guard let self else { return }
            navigationController?.pushViewController(NewAPICheckInHistoryViewController(store: store), animated: true)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    private func promptForWebLoginURL() {
        let controller = NewAPICheckInWebLoginEntryViewController(
            store: store,
            service: service
        ) { [weak self] in
            Task { await self?.reload() }
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func presentManualAdd() {
        let alert = UIAlertController(
            title: String(localized: "plugins.newapi.add", defaultValue: "添加 NewAPI 平台"),
            message: String(localized: "plugins.newapi.add.help", defaultValue: "实验版支持 Token、User ID 和 Cookie Header，凭证会保存到 Keychain。"),
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = String(localized: "plugins.newapi.name", defaultValue: "名称") }
        alert.addTextField {
            $0.placeholder = "https://api.example.com"
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
        }
        alert.addTextField {
            $0.placeholder = "Access Token"
            $0.isSecureTextEntry = true
            $0.autocapitalizationType = .none
        }
        alert.addTextField {
            $0.placeholder = "New-Api-User"
            $0.keyboardType = .numberPad
        }
        alert.addTextField {
            $0.placeholder = "Cookie: session=..."
            $0.isSecureTextEntry = true
            $0.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.save", defaultValue: "保存"), style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields else { return }
            Task { await self.savePlatform(fields: fields) }
        })
        present(alert, animated: true)
    }

    private func presentCurlImport() {
        let controller = UIViewController()
        controller.title = String(localized: "plugins.newapi.curl_import", defaultValue: "从 Curl 导入")
        controller.view.backgroundColor = .systemBackground

        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.layer.borderWidth = 1 / UIScreen.main.scale
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        controller.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: controller.view.keyboardLayoutGuide.topAnchor, constant: -16),
        ])
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(dismissPresentedController)
        )
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "common.import", defaultValue: "导入"),
            style: .done,
            target: self,
            action: #selector(importCurlFromPresentedController(_:))
        )
        controller.navigationItem.rightBarButtonItem?.accessibilityHint = String(localized: "plugins.newapi.curl_import.help", defaultValue: "解析 Curl 并安全保存请求和凭证")
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true) { textView.becomeFirstResponder() }
    }

    @objc private func dismissPresentedController() {
        presentedViewController?.dismiss(animated: true)
    }

    @objc private func importCurlFromPresentedController(_ sender: UIBarButtonItem) {
        guard let navigationController = presentedViewController as? UINavigationController,
              let controller = navigationController.topViewController,
              let textView = controller.view.subviews.compactMap({ $0 as? UITextView }).first
        else { return }
        do {
            let parsed = try NewAPICurlParser.parse(textView.text)
            sender.isEnabled = false
            Task {
                do {
                    try await saveCurlRequest(parsed)
                    navigationController.dismiss(animated: true)
                    await reload()
                } catch {
                    sender.isEnabled = true
                    presentError(error.localizedDescription)
                }
            }
        } catch {
            presentError(String(localized: "plugins.newapi.curl_import.invalid", defaultValue: "Curl 内容无法解析，请检查 URL、引号和参数。"))
        }
    }

    private func saveCurlRequest(_ request: NewAPICurlRequest) async throws {
        guard let scheme = request.url.scheme, let host = request.url.host else {
            throw NewAPICurlParseError.invalidURL(request.url.absoluteString)
        }
        var baseComponents = URLComponents()
        baseComponents.scheme = scheme
        baseComponents.host = host
        baseComponents.port = request.url.port
        guard let baseURL = baseComponents.url else {
            throw NewAPICurlParseError.invalidURL(request.url.absoluteString)
        }
        var endpointComponents = URLComponents()
        endpointComponents.path = request.url.path.isEmpty ? "/" : request.url.path
        endpointComponents.query = request.url.query

        var headers = request.headers
        let authorization = removeHeader(named: "Authorization", from: &headers)
        let accessToken: String? = {
            guard let authorization else { return nil }
            let prefix = "Bearer "
            return authorization.lowercased().hasPrefix(prefix.lowercased())
                ? String(authorization.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                : authorization
        }()
        let credential = NewAPICheckInCredential(
            accessToken: accessToken,
            userID: removeHeader(named: "New-Api-User", from: &headers),
            cookieHeader: removeHeader(named: "Cookie", from: &headers),
            additionalHeaders: headers
        )
        let platform = NewAPICheckInPlatform(
            name: host,
            baseURL: baseURL.absoluteString,
            endpoint: endpointComponents.string ?? request.url.path,
            method: request.method,
            body: request.body,
            source: .curl
        )
        try await store.save(platform, credential: credential)
    }

    private func removeHeader(named name: String, from headers: inout [String: String]) -> String? {
        guard let key = headers.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        return headers.removeValue(forKey: key)
    }

    private func signInAllTapped() {
        guard !isRunningBatch, !platforms.isEmpty else { return }
        isRunningBatch = true
        refreshSummary()
        Task {
            let summary = await service.signInAll()
            isRunningBatch = false
            await reload()
            let expired = platforms.filter { $0.lastStatus == .authenticationExpired }
            let autoRelogin = NewAPICheckInRuntime.autoReloginEnabled && !expired.isEmpty
            var message = summary.localizedSummary
            if autoRelogin {
                message += "\n" + String(
                    localized: "plugins.newapi.auto_relogin.starting",
                    defaultValue: "即将自动打开登录页刷新失效的平台。"
                )
            }
            let alert = UIAlertController(
                title: String(localized: "plugins.newapi.batch_result", defaultValue: "签到结果"),
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "确定"), style: .default) { [weak self] _ in
                guard let self, autoRelogin else { return }
                enqueueRelogin(expired.map(\.id))
            })
            present(alert, animated: true)
        }
    }

    private func savePlatform(fields: [UITextField]) async {
        let rawURL = fields.indices.contains(1) ? fields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" : ""
        guard let url = normalizedPlatformURL(rawURL), let host = url.host else {
            presentError(String(localized: "plugins.newapi.invalid_url", defaultValue: "平台地址无效"))
            return
        }
        let name = fields.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let platform = NewAPICheckInPlatform(
            name: name?.isEmpty == false ? name! : host,
            baseURL: url.absoluteString,
            source: .manual
        )
        let credential = NewAPICheckInCredential(
            accessToken: nonEmpty(fields[safe: 2]?.text),
            userID: nonEmpty(fields[safe: 3]?.text),
            cookieHeader: nonEmpty(fields[safe: 4]?.text)
        )
        do {
            try await store.save(platform, credential: credential)
            await reload()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func signIn(_ platform: NewAPICheckInPlatform, allowAutoRelogin: Bool = true) async {
        guard !runningPlatformIDs.contains(platform.id) else { return }
        runningPlatformIDs.insert(platform.id)
        tableView.reloadData()
        let result = await service.signIn(platform)
        runningPlatformIDs.remove(platform.id)
        await reload()
        if allowAutoRelogin,
           result.status == .authenticationExpired,
           NewAPICheckInRuntime.autoReloginEnabled {
            enqueueRelogin([platform.id])
        }
    }

    // MARK: - Auto relogin

    private func enqueueRelogin(_ platformIDs: [UUID]) {
        for id in platformIDs where !reloginQueue.contains(id) {
            reloginQueue.append(id)
        }
        processReloginQueueIfIdle()
    }

    private func processReloginQueueIfIdle() {
        guard !isAutoReloginActive, !reloginQueue.isEmpty else { return }
        guard presentedViewController == nil,
              navigationController?.topViewController === self
        else { return }
        let platformID = reloginQueue.removeFirst()
        guard let platform = platforms.first(where: { $0.id == platformID }),
              let url = URL(string: platform.baseURL)
        else {
            processReloginQueueIfIdle()
            return
        }
        isAutoReloginActive = true
        lastLoginSaved = false
        pendingResignPlatformID = nil
        let controller = NewAPICheckInLoginViewController(
            baseURL: url,
            mode: (platform.platformType ?? .newAPI) == .custom ? .custom : .newAPI,
            store: store,
            service: service,
            existingPlatform: platform
        ) { [weak self] in
            guard let self else { return }
            lastLoginSaved = true
            pendingResignPlatformID = platformID
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: - State

    private func reload() async {
        platforms = await store.platforms()
        refreshControl?.endRefreshing()
        tableView.reloadData()
        refreshSummary()
    }

    private func refreshSummary() {
        let signed = platforms.filter { $0.lastStatus == .success || $0.lastStatus == .alreadySigned }.count
        let expired = platforms.filter { $0.lastStatus == .authenticationExpired }.count
        summaryCell.update(
            platformCount: platforms.count,
            signedCount: signed,
            expiredCount: expired,
            isRunning: isRunningBatch,
            canRun: !platforms.isEmpty
        )
    }

    // MARK: - Presentation helpers

    private func statusTitle(_ status: NewAPICheckInStatus?) -> String {
        switch status {
        case .success:
            return String(localized: "plugins.newapi.status.success", defaultValue: "成功")
        case .alreadySigned:
            return String(localized: "plugins.newapi.status.already", defaultValue: "已签到")
        case .authenticationExpired:
            return String(localized: "plugins.newapi.status.expired", defaultValue: "登录失效")
        case .serverError:
            return String(localized: "plugins.newapi.status.server_error", defaultValue: "服务错误")
        case .unknown:
            return String(localized: "plugins.newapi.status.unknown", defaultValue: "未知结果")
        case nil:
            return String(localized: "plugins.newapi.detail.not_run", defaultValue: "尚未签到")
        }
    }

    private func tintColor(for status: NewAPICheckInStatus?) -> UIColor {
        switch status {
        case .success, .alreadySigned: return .systemGreen
        case .authenticationExpired: return .systemOrange
        case .serverError, .unknown: return .systemRed
        case nil: return .systemGray
        }
    }

    private func metaText(for platform: NewAPICheckInPlatform) -> String {
        var parts: [String] = []
        if let host = URL(string: platform.baseURL)?.host {
            parts.append(host)
        }
        if let attemptedAt = platform.lastAttemptAt {
            parts.append(Self.relativeFormatter.localizedString(for: attemptedAt, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    private func balanceText(for platform: NewAPICheckInPlatform) -> String? {
        guard let value = platform.lastQuotaValue else { return nil }
        let unit = (platform.lastQuotaUnit ?? "quota").lowercased()
        if unit == "quota" || unit == "remain_quota" {
            return String(format: "$%.2f", Double(value) / 500_000)
        }
        let formatted = Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return unit == "credit" || unit == "balance" ? "$\(formatted)" : formatted
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedPlatformURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: normalized), components.host != nil else { return nil }
        components.query = nil
        components.fragment = nil
        if components.path == "/" { components.path = "" }
        return components.url
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(
            title: String(localized: "common.error", defaultValue: "错误"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "确定"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Summary cell

private final class NewAPISummaryCell: UITableViewCell {
    var onSignInAll: (() -> Void)?

    private let statsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private let signAllButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "plugins.newapi.sign_in_all", defaultValue: "全部签到")
        config.image = UIImage(systemName: "checkmark.seal.fill")
        config.imagePadding = 6
        config.cornerStyle = .large
        config.baseBackgroundColor = AppSettings.shared.themeStyle.accentColor
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return button
    }()

    init() {
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground

        let stack = UIStackView(arrangedSubviews: [statsLabel, signAllButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
        signAllButton.addAction(UIAction { [weak self] _ in self?.onSignInAll?() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(platformCount: Int, signedCount: Int, expiredCount: Int, isRunning: Bool, canRun: Bool) {
        var parts = [String(
            format: String(localized: "plugins.newapi.summary.platforms", defaultValue: "%d 个平台"),
            platformCount
        )]
        if signedCount > 0 {
            parts.append(String(
                format: String(localized: "plugins.newapi.summary.signed", defaultValue: "%d 已签到"),
                signedCount
            ))
        }
        if expiredCount > 0 {
            parts.append(String(
                format: String(localized: "plugins.newapi.summary.expired", defaultValue: "%d 待重新登录"),
                expiredCount
            ))
        }
        statsLabel.text = platformCount == 0
            ? String(localized: "plugins.newapi.summary.empty", defaultValue: "添加平台后可一键完成每日签到")
            : parts.joined(separator: " · ")

        signAllButton.isEnabled = canRun && !isRunning
        signAllButton.configuration?.showsActivityIndicator = isRunning
        signAllButton.configuration?.title = isRunning
            ? String(localized: "plugins.newapi.signing", defaultValue: "签到中…")
            : String(localized: "plugins.newapi.sign_in_all", defaultValue: "全部签到")
    }
}

// MARK: - Platform cell

private final class NewAPIPlatformCell: UITableViewCell {
    static let reuseIdentifier = "NewAPIPlatformCell"

    private let monogramView = NewAPIMonogramView()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let metaLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    private let balanceLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .systemGreen
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let statusPill = NewAPIStatusPill()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        let selected = UIView()
        selected.backgroundColor = .tertiarySystemGroupedBackground
        selectedBackgroundView = selected

        let textStack = UIStackView(arrangedSubviews: [nameLabel, metaLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let trailingStack = UIStackView(arrangedSubviews: [balanceLabel, statusPill])
        trailingStack.axis = .vertical
        trailingStack.alignment = .trailing
        trailingStack.spacing = 5

        [monogramView, textStack, trailingStack, activityIndicator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            monogramView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            monogramView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            monogramView.widthAnchor.constraint(equalToConstant: 44),
            monogramView.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: monogramView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14),

            trailingStack.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 10),
            trailingStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            trailingStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: monogramView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: monogramView.centerYAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        activityIndicator.stopAnimating()
        monogramView.alpha = 1
        balanceLabel.isHidden = true
    }

    func configure(
        name: String,
        metaText: String,
        balance: String?,
        statusText: String,
        statusColor: UIColor,
        monogramSeed: String,
        isRunning: Bool
    ) {
        nameLabel.text = name
        metaLabel.text = metaText
        metaLabel.isHidden = metaText.isEmpty
        balanceLabel.text = balance
        balanceLabel.isHidden = balance == nil
        statusPill.configure(text: statusText, color: statusColor)
        monogramView.configure(seed: monogramSeed, letter: String(name.prefix(1)).uppercased())

        monogramView.alpha = isRunning ? 0.25 : 1
        if isRunning {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        accessibilityLabel = [name, metaText, balance, statusText].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = .button
    }
}

// MARK: - Status pill

private final class NewAPIStatusPill: UIView {
    private let dotView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 3
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 6),
            view.heightAnchor.constraint(equalToConstant: 6),
        ])
        return view
    }()

    private let textLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        let stack = UIStackView(arrangedSubviews: [dotView, textLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3.5),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3.5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, color: UIColor) {
        textLabel.text = text
        textLabel.textColor = color
        dotView.backgroundColor = color
        backgroundColor = color.withAlphaComponent(0.12)
    }
}

// MARK: - Monogram

private final class NewAPIMonogramView: UIView {
    private let gradientLayer = CAGradientLayer()

    private let letterLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 19, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private static let gradientPalettes: [(UIColor, UIColor)] = [
        (.systemBlue, .systemCyan),
        (.systemIndigo, .systemPurple),
        (.systemPink, .systemOrange),
        (.systemTeal, .systemGreen),
        (.systemPurple, .systemPink),
        (.systemOrange, .systemYellow),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradientLayer)
        addSubview(letterLabel)
        NSLayoutConstraint.activate([
            letterLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            letterLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(seed: String, letter: String) {
        letterLabel.text = letter
        // Stable per-host palette so a platform keeps its color across launches.
        let index = abs(seed.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.gradientPalettes.count
        let palette = Self.gradientPalettes[index]
        gradientLayer.colors = [palette.0.cgColor, palette.1.cgColor]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
