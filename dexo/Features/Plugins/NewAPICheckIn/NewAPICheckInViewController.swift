import UIKit

@MainActor
final class NewAPICheckInViewController: UITableViewController {
    private let store: NewAPICheckInStore
    private let service: NewAPICheckInService
    private var platforms: [NewAPICheckInPlatform] = []
    private var runningPlatformIDs = Set<UUID>()
    private var isRunningBatch = false

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
        tableView.estimatedRowHeight = 118
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 86, bottom: 0, right: 16)
        tableView.sectionHeaderTopPadding = 16
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addPlatformTapped)),
            UIBarButtonItem(
                image: UIImage(systemName: "checkmark.circle.fill"),
                style: .plain,
                target: self,
                action: #selector(signInAllTapped)
            ),
        ]
        navigationItem.rightBarButtonItems?.last?.accessibilityLabel = String(
            localized: "plugins.newapi.sign_in_all",
            defaultValue: "全部签到"
        )
        updateEmptyState()
        Task { await reload() }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        platforms.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
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
            typeText: platformTypeText(for: platform),
            sourceText: platformSourceText(for: platform),
            balance: balanceText(for: platform),
            statusText: statusText(for: platform),
            statusColor: tintColor(for: platform.lastStatus),
            isRunning: runningPlatformIDs.contains(platform.id)
        )
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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
        signIn.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [delete, signIn])
    }

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
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
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

    @objc private func signInAllTapped() {
        guard !isRunningBatch, !platforms.isEmpty else { return }
        isRunningBatch = true
        navigationItem.rightBarButtonItems?.last?.isEnabled = false
        Task {
            let summary = await service.signInAll()
            isRunningBatch = false
            navigationItem.rightBarButtonItems?.last?.isEnabled = true
            await reload()
            let alert = UIAlertController(
                title: String(localized: "plugins.newapi.batch_result", defaultValue: "签到结果"),
                message: summary.localizedSummary,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "确定"), style: .default))
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

    private func signIn(_ platform: NewAPICheckInPlatform) async {
        guard !runningPlatformIDs.contains(platform.id) else { return }
        runningPlatformIDs.insert(platform.id)
        tableView.reloadData()
        _ = await service.signIn(platform)
        runningPlatformIDs.remove(platform.id)
        await reload()
    }

    private func reload() async {
        platforms = await store.platforms()
        refreshControl?.endRefreshing()
        tableView.reloadData()
        navigationItem.rightBarButtonItems?.last?.isEnabled = !isRunningBatch && !platforms.isEmpty
        updateEmptyState()
    }

    private func updateEmptyState() {
        guard platforms.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        let label = UILabel()
        label.text = String(localized: "plugins.newapi.empty.help", defaultValue: "还没有平台\n点右上角 + 添加")
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        tableView.backgroundView = label
    }

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
        case .authenticationExpired: return .systemRed
        case .serverError, .unknown: return .systemRed
        case nil: return .systemGray3
        }
    }

    private func statusText(for platform: NewAPICheckInPlatform) -> String {
        let title = statusTitle(platform.lastStatus)
        guard let message = nonEmpty(platform.lastMessage), message != title else { return title }
        return "\(title) · \(message)"
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

    private func platformTypeText(for platform: NewAPICheckInPlatform) -> String {
        switch platform.platformType ?? .newAPI {
        case .newAPI: return "NEWAPI"
        case .custom: return String(localized: "plugins.newapi.platform.type.custom", defaultValue: "自定义")
        }
    }

    private func platformSourceText(for platform: NewAPICheckInPlatform) -> String {
        switch platform.source ?? .webView {
        case .webView: return "WebView"
        case .curl: return "Curl"
        case .manual: return String(localized: "plugins.newapi.platform.source.manual", defaultValue: "手动")
        }
    }

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

private final class NewAPIPlatformCell: UITableViewCell {
    static let reuseIdentifier = "NewAPIPlatformCell"

    private let logoView = NewAPIPlatformLogoView()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let typeBadge = NewAPIBadgeLabel(
        textColor: .systemGreen,
        backgroundColor: .systemGreen.withAlphaComponent(0.12)
    )
    private let sourceBadge = NewAPIBadgeLabel(
        textColor: .systemBlue,
        backgroundColor: .systemBlue.withAlphaComponent(0.12)
    )
    private let balanceBadge = NewAPIBadgeLabel(
        textColor: .systemGreen,
        backgroundColor: .systemGreen.withAlphaComponent(0.12)
    )

    private let statusDot: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 3.5
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 7),
            view.heightAnchor.constraint(equalToConstant: 7),
        ])
        return view
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let chevronView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let view = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: configuration))
        view.tintColor = .tertiaryLabel
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }()

    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        selectedBackgroundView = Self.makeSelectedBackgroundView()

        typeBadge.text = "NEWAPI"
        sourceBadge.text = "WebView"
        balanceBadge.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let badgeStack = UIStackView(arrangedSubviews: [typeBadge, sourceBadge, balanceBadge])
        badgeStack.axis = .horizontal
        badgeStack.alignment = .center
        badgeStack.spacing = 6

        let statusStack = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 6

        let informationStack = UIStackView(arrangedSubviews: [nameLabel, badgeStack, statusStack])
        informationStack.translatesAutoresizingMaskIntoConstraints = false
        informationStack.axis = .vertical
        informationStack.alignment = .leading
        informationStack.spacing = 7

        [logoView, informationStack, chevronView, activityIndicator].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            logoView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            logoView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 54),
            logoView.heightAnchor.constraint(equalToConstant: 54),

            informationStack.leadingAnchor.constraint(equalTo: logoView.trailingAnchor, constant: 14),
            informationStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            informationStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            chevronView.leadingAnchor.constraint(greaterThanOrEqualTo: informationStack.trailingAnchor, constant: 10),
            chevronView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: chevronView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: chevronView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        activityIndicator.stopAnimating()
        chevronView.isHidden = false
        balanceBadge.isHidden = true
    }

    func configure(
        name: String,
        typeText: String,
        sourceText: String,
        balance: String?,
        statusText: String,
        statusColor: UIColor,
        isRunning: Bool
    ) {
        nameLabel.text = name
        typeBadge.text = typeText
        sourceBadge.text = sourceText
        statusLabel.text = statusText
        statusDot.backgroundColor = statusColor
        if let balance {
            balanceBadge.attributedText = Self.balanceBadgeText(balance)
        } else {
            balanceBadge.attributedText = nil
        }
        balanceBadge.isHidden = balance == nil

        chevronView.isHidden = isRunning
        if isRunning {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        accessibilityLabel = [name, typeText, sourceText, balance, statusText]
            .compactMap { $0 }
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    private static func balanceBadgeText(_ balance: String) -> NSAttributedString {
        let text = NSMutableAttributedString()
        if let image = UIImage(systemName: "creditcard.fill")?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: -1.5, width: 13, height: 10)
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: "  "))
        }
        text.append(NSAttributedString(
            string: balance,
            attributes: [
                .foregroundColor: UIColor.systemGreen,
                .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold),
            ]
        ))
        return text
    }

    private static func makeSelectedBackgroundView() -> UIView {
        let view = UIView()
        view.backgroundColor = .tertiarySystemGroupedBackground
        return view
    }
}

private final class NewAPIBadgeLabel: UILabel {
    private let contentInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    init(textColor: UIColor, backgroundColor: UIColor) {
        super.init(frame: .zero)
        font = .systemFont(ofSize: 11.5, weight: .semibold)
        adjustsFontForContentSizeCategory = true
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        textAlignment = .center
        numberOfLines = 1
        lineBreakMode = .byTruncatingTail
        layer.cornerRadius = 7
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }
}

private final class NewAPIPlatformLogoView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let colorView = UIView()
    private let iconView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let view = UIImageView(image: UIImage(systemName: "sparkles", withConfiguration: configuration))
        view.tintColor = .white
        view.contentMode = .center
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemGroupedBackground
        layer.cornerRadius = 14

        colorView.translatesAutoresizingMaskIntoConstraints = false
        colorView.layer.cornerRadius = 18
        colorView.layer.masksToBounds = true
        colorView.layer.addSublayer(gradientLayer)
        addSubview(colorView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        colorView.addSubview(iconView)

        gradientLayer.colors = [
            UIColor.systemCyan.cgColor,
            UIColor.systemPurple.cgColor,
            UIColor.systemPink.cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)

        NSLayoutConstraint.activate([
            colorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            colorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorView.widthAnchor.constraint(equalToConstant: 36),
            colorView.heightAnchor.constraint(equalToConstant: 36),
            iconView.centerXAnchor.constraint(equalTo: colorView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: colorView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = colorView.bounds
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
