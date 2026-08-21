import UIKit

final class ExportHistoryViewController: ObservableViewController {
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

    private let baseURL: String
    private let store: ExportHistoryStore
    private var filter: Filter = .all
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private let tabStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let tabSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var filterBar: UIView = {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(tabStack)
        bar.addSubview(tabSeparator)
        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 2),
            tabStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            tabStack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            tabStack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -2),
            tabSeparator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            tabSeparator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            tabSeparator.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            tabSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
        return bar
    }()

    private var tabButtons: [ExportHistoryFilterTab] = []

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = DraftCell.estimatedHeight
        tableView.showsVerticalScrollIndicator = !AppSettings.shared.hideScrollIndicators
        tableView.alwaysBounceVertical = true
        TopicListCellFactory.registerCells(on: tableView)
        tableView.register(DraftCell.self, forCellReuseIdentifier: DraftCell.reuseIdentifier)
        return tableView
    }()

    private let stateIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .tertiaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var stateStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [stateIconView, stateLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }()

    private var filterBarHeightConstraint: NSLayoutConstraint?

    init(baseURL: String, username: String?) {
        self.baseURL = baseURL
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
        observe(AppSettings.shared)
        title = String(localized: "topic.export.history", defaultValue: "导出历史")
        applyThemeStyle()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "action.clear", defaultValue: "清空"),
            style: .plain,
            target: self,
            action: #selector(clearTapped)
        )

        view.addSubview(filterBar)
        view.addSubview(tableView)
        view.addSubview(stateStackView)
        buildFilterTabs()
        let filterHeight = filterBar.heightAnchor.constraint(equalToConstant: 48)
        filterBarHeightConstraint = filterHeight
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterHeight,

            tableView.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stateStackView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            stateStackView.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            stateStackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateStackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            stateIconView.widthAnchor.constraint(equalToConstant: 48),
            stateIconView.heightAnchor.constraint(equalToConstant: 48),
        ])
        reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        store.reload()
        super.viewWillAppear(animated)
    }

    override func updateUI() {
        applyThemeStyle()
        reloadData()
    }

    private var records: [TopicExportRecord] {
        switch filter {
        case .all: return store.records
        case .markdown: return store.records.filter { $0.format == .markdown }
        case .html: return store.records.filter { $0.format == .html }
        }
    }

    private func applyThemeStyle() {
        let theme = AppSettings.shared.themeStyle
        view.backgroundColor = theme.topicListBackgroundColor
        filterBar.backgroundColor = theme.topicListBackgroundColor
        tableView.backgroundColor = theme.topicListBackgroundColor
        tableView.estimatedRowHeight = TopicListLayoutKind.current.usesChatSessionRows
            ? TopicListCellFactory.estimatedRowHeight
            : DraftCell.estimatedHeight
        tableView.showsVerticalScrollIndicator = !AppSettings.shared.hideScrollIndicators
        view.tintColor = theme.accentColor
        stateIconView.tintColor = theme.accentColor.withAlphaComponent(0.78)
        stateLabel.font = AppSettings.shared.appInterfaceFont(matching: .systemFont(ofSize: 15))
        navigationItem.rightBarButtonItem?.tintColor = theme.accentColor
        tabSeparator.backgroundColor = UIColor.separator.withAlphaComponent(
            TopicListLayoutKind.current.usesChatSessionRows ? 0.28 : 0
        )
        refreshFilterTabs()
    }

    private func reloadData() {
        let hasStoreRecords = !store.records.isEmpty
        let hasVisibleRecords = !records.isEmpty
        filterBar.isHidden = !hasStoreRecords
        filterBarHeightConstraint?.constant = hasStoreRecords ? 48 : 0
        refreshFilterTabs()
        tableView.reloadData()
        let animated = view.window != nil
        AnimationOptimizer.setVisible(tableView, hasVisibleRecords, animated: animated)
        AnimationOptimizer.setVisible(stateStackView, !hasVisibleRecords, animated: animated)
        navigationItem.rightBarButtonItem?.isEnabled = hasStoreRecords
        if !hasVisibleRecords {
            configureEmptyState()
        }
    }

    private func configureEmptyState() {
        let text: String
        switch (store.records.isEmpty, filter) {
        case (true, _):
            text = String(localized: "topic.export.history.empty", defaultValue: "还没有导出记录")
        case (false, .markdown):
            text = String(localized: "topic.export.history.empty.markdown", defaultValue: "没有 Markdown 导出记录")
        case (false, .html):
            text = String(localized: "topic.export.history.empty.html", defaultValue: "没有 HTML 导出记录")
        case (false, .all):
            text = String(localized: "topic.export.history.empty", defaultValue: "还没有导出记录")
        }
        stateIconView.image = UIImage(
            systemName: "square.and.arrow.up.on.square",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 42)
        )
        stateLabel.text = text
    }

    private func buildFilterTabs() {
        tabStack.arrangedSubviews.forEach { view in
            tabStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        tabButtons.removeAll()
        for item in Filter.allCases {
            let tab = ExportHistoryFilterTab()
            tab.tag = item.rawValue
            tab.addTarget(self, action: #selector(filterTabTapped(_:)), for: .touchUpInside)
            tabStack.addArrangedSubview(tab)
            tabButtons.append(tab)
        }
        refreshFilterTabs()
    }

    private func refreshFilterTabs() {
        let chatTabs = TopicListLayoutKind.current.usesChatSessionRows
        tabStack.spacing = chatTabs ? 0 : 8
        for tab in tabButtons {
            let item = Filter(rawValue: tab.tag) ?? .all
            tab.configure(title: item.title, selected: item == filter, usesUnderline: chatTabs)
        }
    }

    @objc private func filterTabTapped(_ sender: UIControl) {
        let next = Filter(rawValue: sender.tag) ?? .all
        guard next != filter else { return }
        filter = next
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

    private func timeText(for record: TopicExportRecord) -> String {
        relativeFormatter.localizedString(for: record.timestamp, relativeTo: Date())
    }

    private func statusText(for record: TopicExportRecord) -> String {
        if let errorMessage = record.errorMessage {
            return errorMessage
        }
        if !record.fileExists {
            return String(localized: "topic.export.history.missing", defaultValue: "文件缺失")
        }
        return String(
            format: String(localized: "topic.export.history.posts %lld", defaultValue: "%lld 篇帖子"),
            record.postCount
        )
    }

    private func symbolName(for record: TopicExportRecord) -> String {
        if record.errorMessage != nil { return "exclamationmark.triangle.fill" }
        if !record.fileExists { return "doc.badge.ellipsis" }
        return record.format == .markdown ? "doc.plaintext.fill" : "chevron.left.forwardslash.chevron.right"
    }

    private func tintColor(for record: TopicExportRecord) -> UIColor {
        if record.errorMessage != nil { return .systemRed }
        if !record.fileExists { return .systemGray }
        return AppSettings.shared.themeStyle.accentColor
    }

    private func sessionItem(for record: TopicExportRecord) -> TopicListSessionItem {
        TopicListSessionItem(
            title: record.title,
            subtitle: statusText(for: record),
            timeText: timeText(for: record),
            isEmphasized: record.fileExists && record.errorMessage == nil,
            badgeText: record.format.title,
            baseURL: baseURL
        )
    }

    private func makeCardCell(
        tableView: UITableView,
        indexPath: IndexPath,
        record: TopicExportRecord
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: DraftCell.reuseIdentifier,
            for: indexPath
        ) as? DraftCell else {
            return UITableViewCell()
        }
        cell.configure(
            title: record.title,
            excerpt: statusText(for: record),
            timeText: timeText(for: record),
            kindTitle: record.format.title,
            taxonomyText: nil,
            symbolName: symbolName(for: record),
            accent: tintColor(for: record)
        )
        return cell
    }
}

extension ExportHistoryViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = records[indexPath.row]
        let layout = TopicListLayoutKind.current
        if layout.usesChatSessionRows {
            return TopicListCellFactory.makeSessionCell(
                tableView: tableView,
                indexPath: indexPath,
                item: sessionItem(for: record),
                layout: layout
            )
        }
        return makeCardCell(tableView: tableView, indexPath: indexPath, record: record)
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
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let record = records[indexPath.row]
        guard record.fileExists else { return nil }
        let share = UIContextualAction(
            style: .normal,
            title: String(localized: "action.share", defaultValue: "分享")
        ) { [weak self] _, _, completion in
            guard let self, let cell = tableView.cellForRow(at: indexPath) else {
                completion(false)
                return
            }
            self.open(record, sourceView: cell)
            completion(true)
        }
        share.image = UIImage(systemName: "square.and.arrow.up")
        share.backgroundColor = AppSettings.shared.themeStyle.accentColor
        return UISwipeActionsConfiguration(actions: [share])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let record = records[indexPath.row]
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "action.delete", defaultValue: "删除")
        ) { [weak self] _, _, completion in
            self?.remove(record)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let record = records[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var actions: [UIMenuElement] = []
            if record.fileExists {
                actions.append(
                    UIAction(
                        title: String(localized: "action.share", defaultValue: "分享"),
                        image: UIImage(systemName: "square.and.arrow.up")
                    ) { [weak self] _ in
                        guard let self, let cell = tableView.cellForRow(at: indexPath) else { return }
                        self.open(record, sourceView: cell)
                    }
                )
            }
            actions.append(
                UIAction(
                    title: String(localized: "action.delete", defaultValue: "删除"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.remove(record)
                }
            )
            return UIMenu(children: actions)
        }
    }
}

private final class ExportHistoryFilterTab: UIControl {
    private let backgroundView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private let indicatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 1.5
        view.layer.cornerCurve = .continuous
        view.isUserInteractionEnabled = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addSubview(backgroundView)
        addSubview(titleLabel)
        addSubview(indicatorView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),

            indicatorView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            indicatorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicatorView.widthAnchor.constraint(equalToConstant: 22),
            indicatorView.heightAnchor.constraint(equalToConstant: 3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, selected: Bool, usesUnderline: Bool) {
        let theme = AppSettings.shared.themeStyle
        titleLabel.text = title
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            matching: .systemFont(ofSize: 15, weight: selected ? .semibold : .regular)
        )
        accessibilityLabel = title
        accessibilityTraits = selected ? [.button, .selected] : [.button]

        if usesUnderline {
            backgroundView.backgroundColor = .clear
            backgroundView.layer.cornerRadius = 0
            titleLabel.textColor = selected ? theme.accentColor : .secondaryLabel
            indicatorView.isHidden = !selected
            indicatorView.backgroundColor = theme.accentColor
        } else {
            indicatorView.isHidden = true
            backgroundView.layer.cornerRadius = 16
            backgroundView.layer.cornerCurve = .continuous
            backgroundView.backgroundColor = selected ? theme.accentColor : theme.topicChipBackgroundColor
            titleLabel.textColor = selected ? .white : .secondaryLabel
        }
    }
}
