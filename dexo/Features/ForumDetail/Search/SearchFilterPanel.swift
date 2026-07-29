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
        case .open: return String(localized: "search.status.open", defaultValue: "进行中")
        case .closed: return String(localized: "search.status.closed", defaultValue: "已关闭")
        case .archived: return String(localized: "search.status.archived", defaultValue: "已归档")
        case .solved: return String(localized: "search.status.solved", defaultValue: "已解决")
        case .unsolved: return String(localized: "search.status.unsolved", defaultValue: "未解决")
        }
    }
}

/// 高级搜索过滤条件（移植自 FluxDo SearchFilter）。
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

private enum SearchDatePreset: Equatable {
    case none
    case week
    case month
    case year
    case custom

    var label: String {
        switch self {
        case .none: return String(localized: "search.date.unlimited", defaultValue: "不限")
        case .week: return String(localized: "search.date.week", defaultValue: "最近一周")
        case .month: return String(localized: "search.date.month", defaultValue: "最近一月")
        case .year: return String(localized: "search.date.year", defaultValue: "最近一年")
        case .custom: return String(localized: "search.date.custom", defaultValue: "自定义")
        }
    }
}

/// FluxDO-style advanced search bottom sheet with chip selectors.
@MainActor
final class SearchFilterPanelViewController: UIViewController {
    private let api: DiscourseAPI
    private let categories: [DiscourseCategory]
    private var selectedCategoryId: Int?
    private var filter: SearchAdvancedFilter
    private let onApply: (_ categoryId: Int?, _ filter: SearchAdvancedFilter) -> Void

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let applyButton = UIButton(type: .system)

    private var statusChips: [UIButton] = []
    private var dateChips: [UIButton] = []
    private var categoryButtons: [Int?: UIButton] = [:]
    private var datePreset: SearchDatePreset = .none

    init(
        api: DiscourseAPI,
        categories: [DiscourseCategory],
        selectedCategoryId: Int?,
        filter: SearchAdvancedFilter,
        onApply: @escaping (_ categoryId: Int?, _ filter: SearchAdvancedFilter) -> Void
    ) {
        self.api = api
        self.categories = categories
        self.selectedCategoryId = selectedCategoryId
        self.filter = filter
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
        datePreset = Self.inferPreset(from: filter)
    }

    /// Backward-compatible convenience used by older call sites.
    convenience init(
        api: DiscourseAPI,
        categoryId: Int?,
        filter: SearchAdvancedFilter,
        onChanged: @escaping (SearchAdvancedFilter) -> Void
    ) {
        self.init(
            api: api,
            categories: [],
            selectedCategoryId: categoryId,
            filter: filter,
            onApply: { _, filter in onChanged(filter) }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = String(localized: "search.filter.advanced_title", defaultValue: "高级搜索")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 22
        contentStack.alignment = .fill

        applyButton.translatesAutoresizingMaskIntoConstraints = false
        var applyConfig = UIButton.Configuration.filled()
        applyConfig.cornerStyle = .large
        applyConfig.baseBackgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.85)
        applyConfig.baseForegroundColor = .white
        applyConfig.title = String(localized: "search.filter.apply", defaultValue: "应用筛选")
        applyConfig.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        applyButton.configuration = applyConfig
        applyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onApply(self.selectedCategoryId, self.filter)
            self.dismiss(animated: true)
        }, for: .touchUpInside)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(applyButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

            applyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            applyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            applyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            applyButton.heightAnchor.constraint(equalToConstant: 52),
        ])

        rebuildContent()
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        statusChips.removeAll()
        dateChips.removeAll()
        categoryButtons.removeAll()

        contentStack.addArrangedSubview(
            makeSection(
                title: String(localized: "search.filter.status", defaultValue: "状态"),
                chips: makeStatusChips()
            )
        )
        contentStack.addArrangedSubview(
            makeSection(
                title: String(localized: "search.filter.date_range", defaultValue: "时间范围"),
                chips: makeDateChips()
            )
        )
        if !categories.isEmpty {
            contentStack.addArrangedSubview(
                makeSection(
                    title: String(localized: "search.filter.category", defaultValue: "分类"),
                    chips: makeCategoryChips()
                )
            )
        }
    }

    private func makeSection(title: String, chips: [UIView]) -> UIView {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.text = title

        let wrap = WrappingChipView()
        wrap.spacing = 10
        wrap.lineSpacing = 10
        chips.forEach { wrap.addArrangedSubview($0) }

        let stack = UIStackView(arrangedSubviews: [titleLabel, wrap])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        return stack
    }

    private func makeStatusChips() -> [UIView] {
        var views: [UIView] = []
        let all = makeChip(
            title: String(localized: "search.filter.all", defaultValue: "全部"),
            selected: filter.status == nil
        ) { [weak self] in
            self?.filter.status = nil
            self?.rebuildContent()
        }
        views.append(all)
        statusChips.append(all)

        for status in SearchTopicStatus.allCases {
            let chip = makeChip(title: status.label, selected: filter.status == status) { [weak self] in
                self?.filter.status = status
                self?.rebuildContent()
            }
            views.append(chip)
            statusChips.append(chip)
        }
        return views
    }

    private func makeDateChips() -> [UIView] {
        let presets: [SearchDatePreset] = [.none, .week, .month, .year, .custom]
        return presets.map { preset in
            let selected = datePreset == preset
            let title: String = {
                if preset == .custom {
                    return " " + preset.label
                }
                return preset.label
            }()
            let chip = makeChip(
                title: title,
                selected: selected,
                systemImage: preset == .custom ? "calendar" : nil
            ) { [weak self] in
                self?.selectDatePreset(preset)
            }
            dateChips.append(chip)
            return chip
        }
    }

    private func makeCategoryChips() -> [UIView] {
        var views: [UIView] = []
        let all = makeChip(
            title: String(localized: "search.filter.all", defaultValue: "全部"),
            selected: selectedCategoryId == nil,
            systemImage: "infinity"
        ) { [weak self] in
            self?.selectedCategoryId = nil
            self?.rebuildContent()
        }
        categoryButtons[nil] = all
        views.append(all)

        for category in categories {
            views.append(contentsOf: makeCategoryTreeChips(category, depth: 0))
        }
        return views
    }

    private func makeCategoryTreeChips(_ category: DiscourseCategory, depth: Int) -> [UIView] {
        var views: [UIView] = []
        let selected = selectedCategoryId == category.id
        let name = category.displayName(parent: nil)
        let chip = makeChip(
            title: name,
            selected: selected,
            tint: color(fromHex: category.color),
            leadingInset: CGFloat(depth) * 18
        ) { [weak self] in
            self?.selectedCategoryId = category.id
            self?.rebuildContent()
        }
        categoryButtons[category.id] = chip
        views.append(chip)
        for child in category.subcategoryList ?? [] {
            views.append(contentsOf: makeCategoryTreeChips(child, depth: depth + 1))
        }
        return views
    }

    private func makeChip(
        title: String,
        selected: Bool,
        systemImage: String? = nil,
        tint: UIColor? = nil,
        leadingInset: CGFloat = 0,
        action: @escaping () -> Void
    ) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.title = title
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12 + leadingInset, bottom: 8, trailing: 12)
        if let systemImage {
            config.image = UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        }
        if selected {
            config.baseBackgroundColor = (tint ?? .systemBlue).withAlphaComponent(0.16)
            config.baseForegroundColor = tint ?? .systemBlue
            config.image = (config.image ?? UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)))
            if systemImage == nil {
                config.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
                config.imagePlacement = .trailing
                config.imagePadding = 6
            }
        } else {
            config.baseBackgroundColor = UIColor.secondarySystemFill
            config.baseForegroundColor = .label
        }
        if let tint, !selected {
            config.baseBackgroundColor = tint.withAlphaComponent(0.12)
            config.baseForegroundColor = .label
        }
        let button = UIButton(configuration: config)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func selectDatePreset(_ preset: SearchDatePreset) {
        datePreset = preset
        let now = Date()
        switch preset {
        case .none:
            filter.afterDate = nil
            filter.beforeDate = nil
            rebuildContent()
        case .week:
            filter.afterDate = Calendar.current.date(byAdding: .day, value: -7, to: now)
            filter.beforeDate = nil
            rebuildContent()
        case .month:
            filter.afterDate = Calendar.current.date(byAdding: .month, value: -1, to: now)
            filter.beforeDate = nil
            rebuildContent()
        case .year:
            filter.afterDate = Calendar.current.date(byAdding: .year, value: -1, to: now)
            filter.beforeDate = nil
            rebuildContent()
        case .custom:
            presentCustomDatePicker()
        }
    }

    private func presentCustomDatePicker() {
        let alert = UIAlertController(
            title: String(localized: "search.date.custom", defaultValue: "自定义"),
            message: String(localized: "search.date.custom_message", defaultValue: "选择起始日期（之后的内容）"),
            preferredStyle: .alert
        )
        // Use a simple date picker VC
        let pickerVC = UIViewController()
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .wheels
        picker.maximumDate = Date()
        picker.date = filter.afterDate ?? Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        picker.translatesAutoresizingMaskIntoConstraints = false
        pickerVC.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: pickerVC.view.centerXAnchor),
            picker.centerYAnchor.constraint(equalTo: pickerVC.view.centerYAnchor),
        ])
        pickerVC.preferredContentSize = CGSize(width: 320, height: 180)

        // Present as action sheet with embedded picker via alert is limited; use sheet.
        let sheet = UIViewController()
        sheet.view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = String(localized: "search.date.custom", defaultValue: "自定义起始日期")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let done = UIButton(type: .system)
        done.setTitle(String(localized: "common.done", defaultValue: "完成"), for: .normal)
        done.translatesAutoresizingMaskIntoConstraints = false
        sheet.view.addSubview(title)
        sheet.view.addSubview(picker)
        sheet.view.addSubview(done)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: sheet.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            title.centerXAnchor.constraint(equalTo: sheet.view.centerXAnchor),
            picker.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            picker.centerXAnchor.constraint(equalTo: sheet.view.centerXAnchor),
            done.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8),
            done.centerXAnchor.constraint(equalTo: sheet.view.centerXAnchor),
            done.bottomAnchor.constraint(equalTo: sheet.view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        done.addAction(UIAction { [weak self, weak sheet] _ in
            guard let self else { return }
            self.filter.afterDate = picker.date
            self.filter.beforeDate = nil
            self.datePreset = .custom
            sheet?.dismiss(animated: true) {
                self.rebuildContent()
            }
        }, for: .touchUpInside)
        if let sheetPC = sheet.sheetPresentationController {
            sheetPC.detents = [.medium()]
            sheetPC.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
        _ = alert
    }

    private static func inferPreset(from filter: SearchAdvancedFilter) -> SearchDatePreset {
        guard let after = filter.afterDate else { return .none }
        let days = Calendar.current.dateComponents([.day], from: after, to: Date()).day ?? 0
        if (6...8).contains(days) { return .week }
        if (28...32).contains(days) { return .month }
        if (360...370).contains(days) { return .year }
        return .custom
    }

    private func color(fromHex hex: String?) -> UIColor? {
        guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let int = UInt64(value, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Simple wrapping layout for chips.
private final class WrappingChipView: UIView {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    private var chips: [UIView] = []

    func addArrangedSubview(_ view: UIView) {
        chips.append(view)
        addSubview(view)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        let maxWidth = bounds.width
        for chip in chips {
            let size = chip.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            chip.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        layoutIfNeeded()
        let maxY = chips.map { $0.frame.maxY }.max() ?? 0
        return CGSize(width: UIView.noIntrinsicMetric, height: maxY)
    }
}
