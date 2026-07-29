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
    case none, week, month, year, custom

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

/// FluxDO-style advanced search bottom sheet.
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

    private var datePreset: SearchDatePreset = .none
    private var hotTags: [DiscourseTag] = []
    private var categoriesSectionContainer = UIStackView()
    private var tagsSectionContainer = UIStackView()

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
        let theme = AppSettings.shared.themeStyle
        view.backgroundColor = theme.topicListBackgroundColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = String(localized: "search.filter.advanced_title", defaultValue: "高级搜索")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 28
        contentStack.alignment = .fill

        applyButton.translatesAutoresizingMaskIntoConstraints = false
        var applyConfig = UIButton.Configuration.filled()
        applyConfig.cornerStyle = .large
        applyConfig.baseBackgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.28, alpha: 1)
                : UIColor(red: 0.29, green: 0.37, blue: 0.47, alpha: 1)
        }
        applyConfig.baseForegroundColor = .white
        applyConfig.title = String(localized: "search.filter.apply", defaultValue: "应用筛选")
        applyConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        applyConfig.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)
        applyButton.configuration = applyConfig
        applyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onApply(self.selectedCategoryId, self.filter)
            self.dismiss(animated: true)
        }, for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(applyButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),

            applyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            applyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            applyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            applyButton.heightAnchor.constraint(equalToConstant: 52),
        ])

        rebuildContent()
        Task { await loadHotTags() }
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        contentStack.addArrangedSubview(makeStatusSection())
        contentStack.addArrangedSubview(makeDateSection())
        if !categories.isEmpty {
            contentStack.addArrangedSubview(makeCategorySection())
        }
        contentStack.addArrangedSubview(makeTagsSection())
    }

    // MARK: - Status / Date

    private func makeStatusSection() -> UIView {
        var chips: [UIView] = [
            makePlainChip(
                title: String(localized: "search.filter.all", defaultValue: "全部"),
                selected: filter.status == nil,
                action: { [weak self] in
                    self?.filter.status = nil
                    self?.rebuildContent()
                }
            )
        ]
        for status in SearchTopicStatus.allCases {
            chips.append(
                makePlainChip(title: status.label, selected: filter.status == status) { [weak self] in
                    self?.filter.status = status
                    self?.rebuildContent()
                }
            )
        }
        return sectionStack(
            title: String(localized: "search.filter.status", defaultValue: "状态"),
            body: wrap(chips)
        )
    }

    private func makeDateSection() -> UIView {
        let presets: [SearchDatePreset] = [.none, .week, .month, .year, .custom]
        let chips: [UIView] = presets.map { preset in
            makePlainChip(
                title: preset.label,
                selected: datePreset == preset,
                systemImage: preset == .custom ? "calendar" : nil
            ) { [weak self] in
                self?.selectDatePreset(preset)
            }
        }
        return sectionStack(
            title: String(localized: "search.filter.date_range", defaultValue: "时间范围"),
            body: wrap(chips)
        )
    }

    // MARK: - Categories (FluxDO hierarchy)

    private func makeCategorySection() -> UIView {
        let flat = flattenCategories(categories)
        let top = flat.filter { $0.parentCategoryId == nil }
        let childrenByParent = Dictionary(grouping: flat.filter { $0.parentCategoryId != nil }) {
            $0.parentCategoryId ?? -1
        }

        var isolated: [DiscourseCategory] = []
        var grouped: [DiscourseCategory] = []
        for parent in top {
            if let kids = childrenByParent[parent.id], !kids.isEmpty {
                grouped.append(parent)
            } else {
                isolated.append(parent)
            }
        }

        let root = UIStackView()
        root.axis = .vertical
        root.spacing = 16
        root.alignment = .fill

        // Top: 全部 + isolated parents
        var topChips: [UIView] = [
            makeCategoryChip(
                title: String(localized: "search.filter.all", defaultValue: "全部"),
                color: .systemGray,
                selected: selectedCategoryId == nil,
                isAll: true
            ) { [weak self] in
                self?.selectedCategoryId = nil
                self?.rebuildContent()
            }
        ]
        for category in isolated {
            let color = parseColor(category.color) ?? .systemGray
            let selected = selectedCategoryId == category.id
            topChips.append(
                makeCategoryChip(
                    title: category.name,
                    color: color,
                    selected: selected,
                    category: category
                ) { [weak self] in
                    self?.selectedCategoryId = selected ? nil : category.id
                    self?.rebuildContent()
                }
            )
        }
        root.addArrangedSubview(wrap(topChips))

        // Grouped parents with guide line + children
        for parent in grouped {
            let kids = childrenByParent[parent.id] ?? []
            let parentColor = parseColor(parent.color) ?? .systemGray
            let parentSelected = selectedCategoryId == parent.id

            let group = UIStackView()
            group.axis = .vertical
            group.spacing = 8
            group.alignment = .fill

            group.addArrangedSubview(
                makeCategoryChip(
                    title: parent.name,
                    color: parentColor,
                    selected: parentSelected,
                    category: parent
                ) { [weak self] in
                    self?.selectedCategoryId = parentSelected ? nil : parent.id
                    self?.rebuildContent()
                }
            )

            let kidsRow = UIStackView()
            kidsRow.axis = .horizontal
            kidsRow.alignment = .fill
            kidsRow.spacing = 12

            let guide = UIView()
            guide.translatesAutoresizingMaskIntoConstraints = false
            guide.backgroundColor = parentColor.withAlphaComponent(0.30)
            guide.layer.cornerRadius = 1
            guide.widthAnchor.constraint(equalToConstant: 2).isActive = true

            let kidsWrap = wrap(
                kids.map { sub in
                    let subColor = parseColor(sub.color) ?? parentColor
                    let selected = selectedCategoryId == sub.id
                    let title = sub.displayName(parent: parent)
                    return makeCategoryChip(
                        title: title,
                        color: subColor,
                        selected: selected,
                        category: sub,
                        isSubcategory: true
                    ) { [weak self] in
                        self?.selectedCategoryId = selected ? nil : sub.id
                        self?.rebuildContent()
                    }
                }
            )

            let guideBox = UIView()
            guideBox.addSubview(guide)
            NSLayoutConstraint.activate([
                guide.topAnchor.constraint(equalTo: guideBox.topAnchor, constant: 4),
                guide.bottomAnchor.constraint(equalTo: guideBox.bottomAnchor, constant: -4),
                guide.centerXAnchor.constraint(equalTo: guideBox.centerXAnchor),
                guideBox.widthAnchor.constraint(equalToConstant: 14),
            ])

            kidsRow.addArrangedSubview(guideBox)
            kidsRow.addArrangedSubview(kidsWrap)
            group.addArrangedSubview(kidsRow)
            root.addArrangedSubview(group)
        }

        return sectionStack(
            title: String(localized: "search.filter.category", defaultValue: "分类"),
            body: root
        )
    }

    // MARK: - Tags

    private func makeTagsSection() -> UIView {
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center

        let title = UILabel()
        title.text = String(localized: "search.filter.tags", defaultValue: "标签")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let more = UIButton(type: .system)
        var moreConfig = UIButton.Configuration.plain()
        moreConfig.title = String(localized: "search.filter.search_more_tags", defaultValue: "搜索更多")
        moreConfig.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        moreConfig.imagePadding = 4
        moreConfig.baseForegroundColor = AppSettings.shared.themeStyle.accentColor
        moreConfig.contentInsets = .zero
        more.configuration = moreConfig
        more.addAction(UIAction { [weak self] _ in
            self?.openTagPicker()
        }, for: .touchUpInside)

        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(more)

        let hotTitle = UILabel()
        hotTitle.text = String(localized: "search.filter.hot_tags", defaultValue: "热门标签")
        hotTitle.font = .systemFont(ofSize: 13, weight: .medium)
        hotTitle.textColor = .secondaryLabel

        let selected = Set(filter.tags)
        let tagViews: [UIView] = hotTags.prefix(36).map { tag in
            makeTagChip(name: tag.text, selected: selected.contains(tag.text)) { [weak self] in
                self?.toggleTag(tag.text)
            }
        }

        let body = UIStackView()
        body.axis = .vertical
        body.spacing = 12
        body.addArrangedSubview(hotTitle)
        if tagViews.isEmpty {
            let empty = UILabel()
            empty.text = String(localized: "search.filter.tags_loading", defaultValue: "加载热门标签…")
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .tertiaryLabel
            body.addArrangedSubview(empty)
        } else {
            body.addArrangedSubview(wrap(tagViews))
        }

        // selected tags not in hot list
        let extra = filter.tags.filter { name in !hotTags.contains(where: { $0.text == name }) }
        if !extra.isEmpty {
            let extraTitle = UILabel()
            extraTitle.text = String(localized: "search.filter.selected_tags", defaultValue: "已选标签")
            extraTitle.font = .systemFont(ofSize: 13, weight: .medium)
            extraTitle.textColor = .secondaryLabel
            body.addArrangedSubview(extraTitle)
            body.addArrangedSubview(
                wrap(extra.map { name in
                    makeTagChip(name: name, selected: true) { [weak self] in
                        self?.toggleTag(name)
                    }
                })
            )
        }

        let stack = UIStackView(arrangedSubviews: [header, body])
        stack.axis = .vertical
        stack.spacing = 14
        return stack
    }

    private func toggleTag(_ name: String) {
        if let idx = filter.tags.firstIndex(of: name) {
            filter.tags.remove(at: idx)
        } else {
            filter.tags.append(name)
        }
        rebuildContent()
    }

    private func openTagPicker() {
        let picker = TagPickerViewController(api: api, categoryId: selectedCategoryId, selectedTags: filter.tags)
        picker.onTagsSelected = { [weak self] tags in
            self?.filter.tags = tags
            self?.rebuildContent()
        }
        let nav = UINavigationController(rootViewController: picker)
        present(nav, animated: true)
    }

    private func loadHotTags() async {
        do {
            let list = try await api.fetchTags()
            hotTags = Array(list.tags.sorted { $0.count > $1.count }.prefix(40))
            rebuildContent()
        } catch {
            // Keep empty; user can still "搜索更多"
        }
    }

    // MARK: - Chips

    private func makeCategoryChip(
        title: String,
        color: UIColor,
        selected: Bool,
        category: DiscourseCategory? = nil,
        isAll: Bool = false,
        isSubcategory: Bool = false,
        action: @escaping () -> Void
    ) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .small
        config.title = title
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(
            top: isSubcategory ? 6 : 7,
            leading: isSubcategory ? 8 : 10,
            bottom: isSubcategory ? 6 : 7,
            trailing: 10
        )
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: isSubcategory ? 12 : 14, weight: selected ? .semibold : .medium)
            outgoing.foregroundColor = UIColor.label
            return outgoing
        }

        if isAll {
            config.image = UIImage(systemName: "infinity", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        } else if let icon = category?.icon,
                  let image = DiscourseFontAwesomeIcon.image(for: icon, color: color, size: 12) {
            config.image = image
        } else {
            // colored dot via attachment-like small circle image
            config.image = Self.dotImage(color: color, size: 8)
        }

        config.baseBackgroundColor = color.withAlphaComponent(selected ? 0.15 : 0.08)
        config.baseForegroundColor = .label
        if selected {
            let check = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
            // Keep category icon; append check via title suffix is ugly — use trailing image by combining
            if config.image == nil {
                config.image = check
                config.imagePlacement = .trailing
            }
        }

        let button = UIButton(configuration: config)
        button.layer.cornerRadius = 8
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.layer.borderWidth = 1
        button.layer.borderColor = (selected ? color : color.withAlphaComponent(0.22)).cgColor
        if selected {
            // trailing check as separate overlay is complex; add checkmark to title
            var cfg = button.configuration
            cfg?.title = title + "  "
            cfg?.imagePlacement = .leading
            button.configuration = cfg
            let checkView = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)))
            checkView.tintColor = color
            checkView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(checkView)
            NSLayoutConstraint.activate([
                checkView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -8),
                checkView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                checkView.widthAnchor.constraint(equalToConstant: 12),
                checkView.heightAnchor.constraint(equalToConstant: 12),
            ])
            // pad trailing for check
            button.configuration?.contentInsets.trailing = 26
        }
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeTagChip(name: String, selected: Bool, action: @escaping () -> Void) -> UIButton {
        let info = SearchTagVisual.icon(for: name)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .medium
        config.title = name
        config.imagePadding = 5
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
            return outgoing
        }
        if let symbol = info.systemName {
            config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        }
        let tint = info.color
        if selected {
            config.baseBackgroundColor = tint.withAlphaComponent(0.16)
            config.baseForegroundColor = tint
            config.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
            config.imagePlacement = .trailing
        } else {
            config.baseBackgroundColor = AppSettings.shared.themeStyle.topicChipBackgroundColor
            config.baseForegroundColor = .label
            if let symbol = info.systemName {
                config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
                config.baseForegroundColor = tint
            }
        }
        let button = UIButton(configuration: config)
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makePlainChip(
        title: String,
        selected: Bool,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> UIButton {
        let accent = AppSettings.shared.themeStyle.accentColor
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .medium
        config.title = title
        config.imagePadding = 5
        config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 14, weight: selected ? .semibold : .medium)
            return outgoing
        }
        if let systemImage {
            config.image = UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        }
        if selected {
            config.baseBackgroundColor = accent.withAlphaComponent(0.14)
            config.baseForegroundColor = accent
            if systemImage == nil {
                config.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
                config.imagePlacement = .trailing
            }
        } else {
            config.baseBackgroundColor = AppSettings.shared.themeStyle.topicChipBackgroundColor
            config.baseForegroundColor = .label
        }
        let button = UIButton(configuration: config)
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        if selected {
            button.layer.borderWidth = 1
            button.layer.borderColor = accent.withAlphaComponent(0.28).cgColor
        }
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Helpers

    private func sectionStack(title: String, body: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        let stack = UIStackView(arrangedSubviews: [titleLabel, body])
        stack.axis = .vertical
        stack.spacing = 14
        return stack
    }

    private func wrap(_ views: [UIView]) -> WrappingChipView {
        let wrap = WrappingChipView()
        wrap.spacing = 8
        wrap.lineSpacing = 8
        views.forEach { wrap.addArrangedSubview($0) }
        return wrap
    }

    private func flattenCategories(_ cats: [DiscourseCategory]) -> [DiscourseCategory] {
        var result: [DiscourseCategory] = []
        func walk(_ list: [DiscourseCategory]) {
            for cat in list {
                result.append(cat)
                if let subs = cat.subcategoryList, !subs.isEmpty {
                    walk(subs)
                }
            }
        }
        walk(cats)
        // If already flat (no subcategoryList), categories array itself is fine.
        if result.count == cats.count, cats.contains(where: { $0.parentCategoryId != nil }) {
            return cats
        }
        if result.isEmpty { return cats }
        // Prefer hierarchy expansion when subcategoryList present; otherwise use as-is.
        if cats.contains(where: { ($0.subcategoryList?.isEmpty == false) }) {
            return result
        }
        return cats
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
        let sheet = UIViewController()
        sheet.view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = String(localized: "search.date.custom", defaultValue: "自定义起始日期")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .wheels
        picker.maximumDate = Date()
        picker.date = filter.afterDate ?? Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        picker.translatesAutoresizingMaskIntoConstraints = false
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
            sheet?.dismiss(animated: true) { self.rebuildContent() }
        }, for: .touchUpInside)
        if let sheetPC = sheet.sheetPresentationController {
            sheetPC.detents = [.medium()]
            sheetPC.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    private static func inferPreset(from filter: SearchAdvancedFilter) -> SearchDatePreset {
        guard let after = filter.afterDate else { return .none }
        let days = Calendar.current.dateComponents([.day], from: after, to: Date()).day ?? 0
        if (6...8).contains(days) { return .week }
        if (28...32).contains(days) { return .month }
        if (360...370).contains(days) { return .year }
        return .custom
    }

    private func parseColor(_ hex: String?) -> UIColor? {
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

    private static func dotImage(color: UIColor, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()
        }
    }
}

// MARK: - Tag visual map (FluxDO TagIconList subset → SF Symbols)

private enum SearchTagVisual {
    struct Info {
        let systemName: String?
        let color: UIColor
    }

    static func icon(for name: String) -> Info {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let map: [String: (String, String)] = [
            "纯水": ("drop.fill", "F7941D"),
            "快问快答": ("questionmark.circle.fill", "34C759"),
            "人工智能": ("brain.head.profile", "BD93F9"),
            "软件开发": ("chevron.left.forwardslash.chevron.right", "669D34"),
            "夸克网盘": ("externaldrive.fill", "669D34"),
            "chatgpt": ("bubble.left.and.bubble.right.fill", "10A37F"),
            "病友": ("person.2.fill", "F7941D"),
            "树洞": ("leaf.fill", "669D34"),
            "openai": ("circle.hexagongrid.fill", "10A37F"),
            "百度网盘": ("externaldrive.fill.badge.icloud", "2932E1"),
            "影视": ("film.fill", "669D34"),
            "aff": ("hand.point.up.left.fill", "F7941D"),
            "vps": ("server.rack", "669D34"),
            "职场": ("briefcase.fill", "669D34"),
            "网络安全": ("lock.shield.fill", "FF1111"),
            "抽奖": ("gift.fill", "F7941D"),
            "动漫": ("face.smiling.fill", "669D34"),
            "晒年味": ("house.fill", "F7941D"),
            "订阅节点": ("network", "669D34"),
            "claude": ("sparkles", "D97757"),
            "游戏": ("gamecontroller.fill", "669D34"),
            "作品集": ("paintpalette.fill", "669D34"),
            "转载": ("arrowshape.turn.up.right.fill", "669D34"),
            "gemini": ("sparkle", "4285F4"),
            "nsfw": ("eye.trianglebadge.exclamationmark.fill", "FF5555"),
            "金融经济": ("dollarsign.circle.fill", "669D34"),
            "cursor": ("chevron.left.forwardslash.chevron.right", "669D34"),
            "开源推广": ("shippingbox.fill", "F5BF03"),
            "拼车": ("car.fill", "669D34"),
            "配置优化": ("terminal.fill", "669D34"),
            "pt": ("arrow.down.circle.fill", "669D34"),
        ]
        if let hit = map[key] ?? map[name] {
            return Info(systemName: hit.0, color: color(hit.1))
        }
        return Info(systemName: nil, color: AppSettings.shared.themeStyle.accentColor)
    }

    private static func color(_ hex: String) -> UIColor {
        var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let int = UInt64(value, radix: 16) else { return .systemGray }
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
        let maxWidth = max(bounds.width, 1)
        for chip in chips {
            chip.setNeedsLayout()
            chip.layoutIfNeeded()
            var size = chip.intrinsicContentSize
            if size.width <= 0 || size.width > 10_000 {
                size = chip.sizeThatFits(CGSize(width: maxWidth, height: 44))
            }
            size.height = max(size.height, 34)
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
        let maxY = chips.map(\.frame.maxY).max() ?? 0
        return CGSize(width: UIView.noIntrinsicMetric, height: maxY)
    }
}
