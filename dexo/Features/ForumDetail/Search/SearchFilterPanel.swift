import UIKit

/// 话题状态过滤（移植自 FluxDo SearchStatus）。
enum SearchTopicStatus: String, CaseIterable {
    case open
    case closed
    case archived
    case solved
    case unsolved

    var label: String {
        switch self {
        case .open: return String(localized: "search.status.open", defaultValue: "未关闭")
        case .closed: return String(localized: "search.status.closed", defaultValue: "已关闭")
        case .archived: return String(localized: "search.status.archived", defaultValue: "已归档")
        case .solved: return String(localized: "search.status.solved", defaultValue: "已解决")
        case .unsolved: return String(localized: "search.status.unsolved", defaultValue: "未解决")
        }
    }
}

/// 高级搜索过滤条件（移植自 FluxDo SearchFilter；分类沿用现有快捷栏）。
struct SearchAdvancedFilter: Equatable {
    var tags: [String] = []
    var status: SearchTopicStatus?
    var afterDate: Date?
    var beforeDate: Date?

    var isEmpty: Bool {
        tags.isEmpty && status == nil && afterDate == nil && beforeDate == nil
    }

    var activeCount: Int {
        var count = tags.count
        if status != nil { count += 1 }
        if afterDate != nil || beforeDate != nil { count += 1 }
        return count
    }

    /// 生成 Discourse 查询片段：tags:x status:open after:2024-01-01 before:…
    func queryParts() -> [String] {
        var parts: [String] = []
        for tag in tags {
            parts.append("tags:\(tag)")
        }
        if let status {
            parts.append("status:\(status.rawValue)")
        }
        if let afterDate {
            parts.append("after:\(Self.dateFormatter.string(from: afterDate))")
        }
        if let beforeDate {
            parts.append("before:\(Self.dateFormatter.string(from: beforeDate))")
        }
        return parts
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// 高级筛选面板（FluxDo 的过滤 bottom sheet 对应物）：改动即时生效。
@MainActor
final class SearchFilterPanelViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case tags
        case status
        case dates
        case clear
    }

    private let api: DiscourseAPI
    private let categoryId: Int?
    private var filter: SearchAdvancedFilter
    private let onChanged: (SearchAdvancedFilter) -> Void

    init(
        api: DiscourseAPI,
        categoryId: Int?,
        filter: SearchAdvancedFilter,
        onChanged: @escaping (SearchAdvancedFilter) -> Void
    ) {
        self.api = api
        self.categoryId = categoryId
        self.filter = filter
        self.onChanged = onChanged
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "search.filter.title", defaultValue: "高级筛选")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private func filterDidChange() {
        onChanged(filter)
    }

    // MARK: - Data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .tags: return 1
        case .status: return SearchTopicStatus.allCases.count + 1
        case .dates: return 2
        case .clear: return 1
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .tags: return String(localized: "search.filter.tags", defaultValue: "标签")
        case .status: return String(localized: "search.filter.status", defaultValue: "话题状态")
        case .dates: return String(localized: "search.filter.dates", defaultValue: "时间范围")
        case .clear, nil: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .tags:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = String(localized: "search.filter.tags.select", defaultValue: "选择标签")
            content.secondaryText = filter.tags.isEmpty
                ? String(localized: "search.filter.none", defaultValue: "不限")
                : filter.tags.map { "#\($0)" }.joined(separator: " ")
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.lineBreakMode = .byTruncatingTail
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .status:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            let status: SearchTopicStatus? = indexPath.row == 0
                ? nil
                : SearchTopicStatus.allCases[indexPath.row - 1]
            content.text = status?.label ?? String(localized: "search.filter.none", defaultValue: "不限")
            cell.contentConfiguration = content
            cell.accessoryType = filter.status == status ? .checkmark : .none
            cell.tintColor = AppSettings.shared.themeStyle.accentColor
            return cell

        case .dates:
            let isAfter = indexPath.row == 0
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            var content = cell.defaultContentConfiguration()
            content.text = isAfter
                ? String(localized: "search.filter.after", defaultValue: "开始日期")
                : String(localized: "search.filter.before", defaultValue: "结束日期")
            cell.contentConfiguration = content

            let currentDate = isAfter ? filter.afterDate : filter.beforeDate
            let picker = UIDatePicker()
            picker.datePickerMode = .date
            picker.preferredDatePickerStyle = .compact
            picker.maximumDate = Date()
            if let currentDate {
                picker.date = currentDate
            }
            picker.addAction(UIAction { [weak self] action in
                guard let self, let picker = action.sender as? UIDatePicker else { return }
                if isAfter {
                    filter.afterDate = picker.date
                } else {
                    filter.beforeDate = picker.date
                }
                filterDidChange()
                tableView.reloadSections(IndexSet(integer: Section.dates.rawValue), with: .none)
            }, for: .valueChanged)

            if currentDate != nil {
                let clearButton = UIButton(type: .system)
                clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
                clearButton.tintColor = .tertiaryLabel
                clearButton.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    if isAfter {
                        filter.afterDate = nil
                    } else {
                        filter.beforeDate = nil
                    }
                    filterDidChange()
                    tableView.reloadSections(IndexSet(integer: Section.dates.rawValue), with: .none)
                }, for: .touchUpInside)
                let stack = UIStackView(arrangedSubviews: [clearButton, picker])
                stack.axis = .horizontal
                stack.spacing = 6
                stack.alignment = .center
                let size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
                stack.frame = CGRect(origin: .zero, size: size)
                cell.accessoryView = stack
            } else {
                let size = picker.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
                picker.frame = CGRect(origin: .zero, size: size)
                cell.accessoryView = picker
            }
            return cell

        case .clear, nil:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = String(localized: "search.filter.clear_all", defaultValue: "清除全部筛选")
            content.textProperties.alignment = .center
            content.textProperties.color = filter.isEmpty ? .tertiaryLabel : .systemRed
            cell.contentConfiguration = content
            cell.selectionStyle = filter.isEmpty ? .none : .default
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .tags:
            presentTagPicker()
        case .status:
            let status: SearchTopicStatus? = indexPath.row == 0
                ? nil
                : SearchTopicStatus.allCases[indexPath.row - 1]
            filter.status = status
            filterDidChange()
            tableView.reloadSections(IndexSet(integer: Section.status.rawValue), with: .none)
        case .clear:
            guard !filter.isEmpty else { return }
            filter = SearchAdvancedFilter()
            filterDidChange()
            tableView.reloadData()
        case .dates, nil:
            break
        }
    }

    private func presentTagPicker() {
        let picker = TagPickerViewController(api: api, categoryId: categoryId, selectedTags: filter.tags)
        picker.onTagsSelected = { [weak self] tags in
            guard let self else { return }
            filter.tags = tags
            filterDidChange()
            tableView.reloadSections(IndexSet(integer: Section.tags.rawValue), with: .none)
        }
        let nav = UINavigationController(rootViewController: picker)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }
}
