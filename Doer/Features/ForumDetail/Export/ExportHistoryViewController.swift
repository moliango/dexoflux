import UIKit

final class ExportHistoryViewController: UIViewController {
    private enum Filter: Int, CaseIterable {
        case all
        case markdown
        case html

        var title: String {
            switch self {
            case .all: return String(localized: "common.all", defaultValue: "全部")
            case .markdown: return "Markdown"
            case .html: return "HTML"
            }
        }
    }

    private let store: ExportHistoryStore
    private var filter: Filter = .all

    private lazy var filterControl: UISegmentedControl = {
        let control = UISegmentedControl(items: Filter.allCases.map(\.title))
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        return control
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 82
        return tableView
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.text = String(localized: "topic.export.history.empty", defaultValue: "还没有导出记录")
        return label
    }()

    init(baseURL: String, username: String?) {
        self.store = ExportHistoryStore(baseURL: baseURL, username: username)
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "topic.export.history", defaultValue: "导出历史")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.titleView = filterControl
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "action.clear", defaultValue: "清空"),
            style: .plain,
            target: self,
            action: #selector(clearTapped)
        )

        view.addSubview(tableView)
        view.addSubview(stateLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
        reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.reload()
        reloadData()
    }

    private var records: [TopicExportRecord] {
        switch filter {
        case .all: return store.records
        case .markdown: return store.records.filter { $0.format == .markdown }
        case .html: return store.records.filter { $0.format == .html }
        }
    }

    private func reloadData() {
        tableView.reloadData()
        tableView.isHidden = !records.isEmpty
        stateLabel.isHidden = !records.isEmpty
        navigationItem.rightBarButtonItem?.isEnabled = !store.records.isEmpty
    }

    @objc private func filterChanged() {
        filter = Filter(rawValue: filterControl.selectedSegmentIndex) ?? .all
        reloadData()
    }

    @objc private func clearTapped() {
        let alert = UIAlertController(
            title: String(localized: "topic.export.history.clear.title", defaultValue: "清空导出历史？"),
            message: String(localized: "topic.export.history.clear.message", defaultValue: "相关导出文件也会一并删除。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "action.clear", defaultValue: "清空"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try self.store.clear()
                self.reloadData()
            } catch {
                self.showMessage(error.localizedDescription)
            }
        })
        present(alert, animated: true)
    }

    private func open(_ record: TopicExportRecord, sourceView: UIView) {
        if let errorMessage = record.errorMessage, record.filePath == nil {
            showMessage(errorMessage)
            return
        }
        guard let fileURL = record.fileURL, record.fileExists else {
            showMessage(String(localized: "topic.export.history.file_missing", defaultValue: "导出文件已不存在，可以删除这条历史记录。"))
            return
        }
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = sourceView
        activity.popoverPresentationController?.sourceRect = sourceView.bounds
        present(activity, animated: true)
    }

    private func remove(_ record: TopicExportRecord) {
        do {
            try store.remove(record)
            reloadData()
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }
}

extension ExportHistoryViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = records[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: symbolName(for: record))
        content.imageProperties.tintColor = tintColor(for: record)
        content.text = record.title
        content.secondaryText = subtitle(for: record)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.contentConfiguration = content
        cell.accessoryType = record.fileExists ? .disclosureIndicator : .none
        return cell
    }

    private func symbolName(for record: TopicExportRecord) -> String {
        if record.errorMessage != nil { return "exclamationmark.triangle.fill" }
        if !record.fileExists { return "doc.badge.ellipsis" }
        return record.format == .markdown ? "doc.plaintext.fill" : "chevron.left.forwardslash.chevron.right"
    }

    private func tintColor(for record: TopicExportRecord) -> UIColor {
        if record.errorMessage != nil { return .systemRed }
        if !record.fileExists { return .systemGray }
        return record.format == .markdown ? .systemBlue : .systemOrange
    }

    private func subtitle(for record: TopicExportRecord) -> String {
        let dateFormatter = RelativeDateTimeFormatter()
        dateFormatter.unitsStyle = .full
        let time = dateFormatter.localizedString(for: record.timestamp, relativeTo: Date())
        let status: String
        if let errorMessage = record.errorMessage {
            status = errorMessage
        } else if !record.fileExists {
            status = String(localized: "topic.export.history.missing", defaultValue: "文件缺失")
        } else {
            status = String(format: String(localized: "topic.export.history.posts %lld", defaultValue: "%lld 篇帖子"), record.postCount)
        }
        return "\(record.format.title) · \(status) · \(time)"
    }
}

extension ExportHistoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        open(records[indexPath.row], sourceView: cell)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let record = records[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: String(localized: "action.delete", defaultValue: "删除")) { [weak self] _, _, completion in
            self?.remove(record)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
