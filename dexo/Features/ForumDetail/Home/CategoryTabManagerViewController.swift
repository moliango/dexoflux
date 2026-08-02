import UIKit

final class CategoryTabManagerViewController: UITableViewController {
    var onPinnedCategoryIdsChanged: (([Int]) -> Void)?

    private enum Section: Int, CaseIterable {
        case pinned
        case available
    }

    private let allCategories: [DiscourseCategory]
    private var pinnedCategoryIds: [Int]
    private let displayNameProvider: (DiscourseCategory) -> String
    private let parentNameProvider: (DiscourseCategory) -> String?
    private let colorProvider: (DiscourseCategory) -> UIColor?

    private var categoriesById: [Int: DiscourseCategory] {
        Dictionary(uniqueKeysWithValues: allCategories.map { ($0.id, $0) })
    }

    private var pinnedCategories: [DiscourseCategory] {
        let lookup = categoriesById
        return pinnedCategoryIds.compactMap { lookup[$0] }
    }

    private var availableCategories: [DiscourseCategory] {
        let pinned = Set(pinnedCategoryIds)
        return allCategories.filter { !pinned.contains($0.id) }
    }

    init(
        categories: [DiscourseCategory],
        pinnedCategoryIds: [Int],
        displayNameProvider: @escaping (DiscourseCategory) -> String,
        parentNameProvider: @escaping (DiscourseCategory) -> String?,
        colorProvider: @escaping (DiscourseCategory) -> UIColor?
    ) {
        self.allCategories = categories
        self.pinnedCategoryIds = Self.validPinnedIds(pinnedCategoryIds, categories: categories)
        self.displayNameProvider = displayNameProvider
        self.parentNameProvider = parentNameProvider
        self.colorProvider = colorProvider
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "home.category_manager.title")
        view.backgroundColor = .systemGroupedBackground
        tableView.register(CategoryManagerCell.self, forCellReuseIdentifier: CategoryManagerCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EmptyCell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "home.category_manager.done"),
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .pinned:
            return max(pinnedCategories.count, 1)
        case .available:
            return max(availableCategories.count, 1)
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .pinned:
            return String(localized: "home.category_manager.my_categories")
        case .available:
            return String(localized: "home.category_manager.all_categories")
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .pinned:
            return String(localized: "home.category_manager.remove_hint")
        case .available:
            return String(localized: "home.category_manager.add_hint")
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .pinned:
            let categories = pinnedCategories
            guard !categories.isEmpty else {
                return emptyCell(text: String(localized: "home.category_manager.empty_pinned"), indexPath: indexPath)
            }
            return categoryCell(category: categories[indexPath.row], mode: .remove, indexPath: indexPath)
        case .available:
            let categories = availableCategories
            guard !categories.isEmpty else {
                return emptyCell(text: String(localized: "home.category_manager.empty_available"), indexPath: indexPath)
            }
            return categoryCell(category: categories[indexPath.row], mode: .add, indexPath: indexPath)
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .pinned:
            let categories = pinnedCategories
            guard categories.indices.contains(indexPath.row) else { return }
            pinnedCategoryIds.removeAll { $0 == categories[indexPath.row].id }
            commitPinnedCategoryChange()
        case .available:
            let categories = availableCategories
            guard categories.indices.contains(indexPath.row) else { return }
            pinnedCategoryIds.append(categories[indexPath.row].id)
            commitPinnedCategoryChange()
        case .none:
            break
        }
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .pinned && pinnedCategories.count > 1
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard Section(rawValue: sourceIndexPath.section) == .pinned,
              Section(rawValue: destinationIndexPath.section) == .pinned,
              pinnedCategoryIds.indices.contains(sourceIndexPath.row)
        else {
            tableView.reloadData()
            return
        }
        let id = pinnedCategoryIds.remove(at: sourceIndexPath.row)
        let destination = min(destinationIndexPath.row, pinnedCategoryIds.count)
        pinnedCategoryIds.insert(id, at: destination)
        commitPinnedCategoryChange(reload: false)
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        if proposedDestinationIndexPath.section == Section.pinned.rawValue {
            return proposedDestinationIndexPath
        }
        return sourceIndexPath
    }

    private func categoryCell(category: DiscourseCategory, mode: CategoryManagerCell.Mode, indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: CategoryManagerCell.reuseIdentifier,
            for: indexPath
        ) as? CategoryManagerCell else {
            return UITableViewCell()
        }
        cell.configure(
            title: displayNameProvider(category),
            subtitle: parentNameProvider(category),
            color: colorProvider(category),
            mode: mode
        )
        return cell
    }

    private func emptyCell(text: String, indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyCell", for: indexPath)
        var config = UIListContentConfiguration.cell()
        config.text = text
        config.textProperties.color = .secondaryLabel
        config.textProperties.font = .systemFont(ofSize: 14, weight: .regular)
        cell.contentConfiguration = config
        cell.selectionStyle = .none
        cell.accessoryType = .none
        return cell
    }

    private func commitPinnedCategoryChange(reload: Bool = true) {
        pinnedCategoryIds = Self.validPinnedIds(pinnedCategoryIds, categories: allCategories)
        onPinnedCategoryIdsChanged?(pinnedCategoryIds)
        if reload {
            tableView.reloadData()
        }
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    private static func validPinnedIds(_ ids: [Int], categories: [DiscourseCategory]) -> [Int] {
        let validIds = Set(categories.map(\.id))
        var seen = Set<Int>()
        return ids.filter { validIds.contains($0) && seen.insert($0).inserted }
    }
}

final class CategoryManagerCell: UITableViewCell {
    enum Mode {
        case add
        case remove
    }

    static let reuseIdentifier = "CategoryManagerCell"

    private let colorDotView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 6
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16, weight: .medium))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .regular))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }()

    private let modeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

        contentView.addSubview(colorDotView)
        contentView.addSubview(textStack)
        contentView.addSubview(modeImageView)

        NSLayoutConstraint.activate([
            colorDotView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            colorDotView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            colorDotView.widthAnchor.constraint(equalToConstant: 12),
            colorDotView.heightAnchor.constraint(equalToConstant: 12),

            textStack.leadingAnchor.constraint(equalTo: colorDotView.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(equalTo: modeImageView.leadingAnchor, constant: -12),

            modeImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            modeImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            modeImageView.widthAnchor.constraint(equalToConstant: 22),
            modeImageView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        modeImageView.image = nil
    }

    func configure(title: String, subtitle: String?, color: UIColor?, mode: Mode) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        colorDotView.backgroundColor = TopicTagVisualStyle.categoryColor(for: title, fallback: color ?? .tertiaryLabel)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        switch mode {
        case .add:
            modeImageView.image = UIImage(systemName: "plus.circle.fill", withConfiguration: symbolConfig)
            modeImageView.tintColor = AppSettings.shared.themeStyle.accentColor
            accessibilityHint = String(localized: "home.category_manager.add_hint")
        case .remove:
            modeImageView.image = UIImage(systemName: "minus.circle.fill", withConfiguration: symbolConfig)
            modeImageView.tintColor = .systemRed
            accessibilityHint = String(localized: "home.category_manager.remove_hint")
        }
    }
}
