import UIKit

@MainActor
final class NewAPICheckInHistoryViewController: UITableViewController {
    private struct DaySection {
        let date: Date
        let attempts: [NewAPICheckInAttempt]
    }

    private let store: NewAPICheckInStore
    private var platforms: [NewAPICheckInPlatform] = []
    private var attempts: [NewAPICheckInAttempt] = []
    private var selectedPlatformID: UUID?
    private var sections: [DaySection] = []

    init(store: NewAPICheckInStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "plugins.newapi.history.title", defaultValue: "签到历史")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "history")
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(clearTapped)),
            UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"), menu: filterMenu()),
        ]
        Task { await reload() }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].attempts.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let day = sections[section]
        let date: String
        if Calendar.current.isDateInToday(day.date) {
            date = String(localized: "plugins.newapi.history.today", defaultValue: "今天")
        } else if Calendar.current.isDateInYesterday(day.date) {
            date = String(localized: "plugins.newapi.history.yesterday", defaultValue: "昨天")
        } else {
            date = Self.dayFormatter.string(from: day.date)
        }
        return "\(date) · \(day.attempts.count)"
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "history", for: indexPath)
        let attempt = sections[indexPath.section].attempts[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = platformName(for: attempt.platformID)
        content.secondaryText = [
            statusTitle(attempt.status),
            attempt.message,
            Self.timeFormatter.string(from: attempt.attemptedAt),
            "\(attempt.durationMilliseconds) ms",
        ].compactMap { $0 }.joined(separator: " · ")
        content.image = UIImage(systemName: statusIcon(attempt.status))
        content.imageProperties.tintColor = statusColor(attempt.status)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let attempt = sections[indexPath.section].attempts[indexPath.row]
        let body = [
            "HTTP: \(attempt.statusCode.map(String.init) ?? "-")",
            "\(String(localized: "plugins.newapi.detail.duration", defaultValue: "耗时")): \(attempt.durationMilliseconds) ms",
            attempt.message,
            attempt.rawResponse,
        ].compactMap { $0 }.joined(separator: "\n\n")
        let alert = UIAlertController(title: platformName(for: attempt.platformID), message: body, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "确定"), style: .default))
        present(alert, animated: true)
    }

    @objc private func refreshTriggered() {
        Task { await reload() }
    }

    @objc private func clearTapped() {
        guard !attempts.isEmpty else { return }
        let alert = UIAlertController(
            title: String(localized: "plugins.newapi.history.clear_title", defaultValue: "清空签到历史？"),
            message: String(localized: "plugins.newapi.history.clear_help", defaultValue: "只删除签到记录，不会删除平台和登录凭证。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "action.clear", defaultValue: "清空"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                try? await self.store.clearAttempts(platformID: self.selectedPlatformID)
                await self.reload()
            }
        })
        present(alert, animated: true)
    }

    private func filterMenu() -> UIMenu {
        var actions = [UIAction(
            title: String(localized: "plugins.newapi.history.all", defaultValue: "全部平台"),
            state: selectedPlatformID == nil ? .on : .off
        ) { [weak self] _ in
            self?.selectedPlatformID = nil
            Task { await self?.reload() }
        }]
        actions.append(contentsOf: platforms.map { platform in
            UIAction(
                title: platform.name,
                state: selectedPlatformID == platform.id ? .on : .off
            ) { [weak self] _ in
                self?.selectedPlatformID = platform.id
                Task { await self?.reload() }
            }
        })
        return UIMenu(children: actions)
    }

    private func reload() async {
        platforms = await store.platforms()
        attempts = await store.attempts(platformID: selectedPlatformID)
        let grouped = Dictionary(grouping: attempts) { Calendar.current.startOfDay(for: $0.attemptedAt) }
        sections = grouped.map { DaySection(date: $0.key, attempts: $0.value.sorted { $0.attemptedAt > $1.attemptedAt }) }
            .sorted { $0.date > $1.date }
        navigationItem.rightBarButtonItems?.last?.menu = filterMenu()
        navigationItem.rightBarButtonItems?.first?.isEnabled = !attempts.isEmpty
        refreshControl?.endRefreshing()
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        guard attempts.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        let label = UILabel()
        label.text = String(localized: "plugins.newapi.history.empty", defaultValue: "还没有签到记录")
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        tableView.backgroundView = label
    }

    private func platformName(for id: UUID) -> String {
        platforms.first(where: { $0.id == id })?.name
            ?? String(localized: "plugins.newapi.history.deleted_platform", defaultValue: "已删除的平台")
    }

    private func statusTitle(_ status: NewAPICheckInStatus) -> String {
        switch status {
        case .success: return String(localized: "plugins.newapi.status.success", defaultValue: "成功")
        case .alreadySigned: return String(localized: "plugins.newapi.status.already", defaultValue: "已签到")
        case .authenticationExpired: return String(localized: "plugins.newapi.status.expired", defaultValue: "登录失效")
        case .serverError: return String(localized: "plugins.newapi.status.server_error", defaultValue: "服务错误")
        case .unknown: return String(localized: "plugins.newapi.status.unknown", defaultValue: "未知结果")
        }
    }

    private func statusIcon(_ status: NewAPICheckInStatus) -> String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .alreadySigned: return "checkmark.circle"
        case .authenticationExpired: return "person.crop.circle.badge.exclamationmark"
        case .serverError, .unknown: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: NewAPICheckInStatus) -> UIColor {
        switch status {
        case .success, .alreadySigned: return .systemGreen
        case .authenticationExpired: return .systemOrange
        case .serverError, .unknown: return .systemRed
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
