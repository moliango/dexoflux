import SDWebImage
import UIKit

final class SearchViewController: ObservableViewController, UISearchBarDelegate {
    private let api: DiscourseAPI
    private let viewModel: SearchViewModel
    private let initialQuery: String?
    private let fixedQueryQualifier: String?

    private var searchTask: Task<Void, Never>?

    private let searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = String(localized: "search.placeholder")
        return sc
    }()

    // MARK: - Filter Bar

    private let filterBar: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var categoryButton: UIButton = {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.buildCategoryMenuElements() ?? [])
            },
        ])
        return button
    }()

    private lazy var sortButton: UIButton = {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.buildSortMenuElements() ?? [])
            },
        ])
        return button
    }()

    private lazy var advancedFilterButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.presentFilterPanel()
        }, for: .touchUpInside)
        return button
    }()

    private let filterSeparator: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Active filter chips (FluxDo ActiveSearchFiltersBar)

    private let chipsScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let chipsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var chipsHeightConstraint: NSLayoutConstraint?

    // MARK: - Table

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.reuseIdentifier)
        tv.delegate = self
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = .init(tableView: tableView) { [weak self] tableView, indexPath, postId in
        guard let self,
              let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.reuseIdentifier, for: indexPath) as? SearchResultCell,
              let post = self.viewModel.searchResults.first(where: { $0.id == postId })
        else {
            return UITableViewCell()
        }
        cell.configure(
            with: post,
            baseURL: self.api.baseURL,
            isAIResult: self.viewModel.aiTopicIds.contains(post.topicId)
        )
        return cell
    }

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "search.no_results")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    init(api: DiscourseAPI, initialQuery: String? = nil, fixedQueryQualifier: String? = nil) {
        self.api = api
        self.viewModel = SearchViewModel(api: api)
        self.initialQuery = initialQuery
        self.fixedQueryQualifier = fixedQueryQualifier
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "search.title")
        view.backgroundColor = .systemBackground
        definesPresentationContext = true

        searchController.searchBar.delegate = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        setupFilterBar()
        updateFilterButtons()

        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: chipsScrollView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        Task {
            await viewModel.loadCategories()
        }
        Task {
            await viewModel.loadRecentSearches()
        }
        if let initialQuery, !initialQuery.isEmpty {
            searchController.searchBar.text = initialQuery
            triggerSearch()
        }
    }

    // MARK: - Filter Bar Setup

    private func setupFilterBar() {
        view.addSubview(filterBar)
        filterBar.addSubview(categoryButton)
        filterBar.addSubview(sortButton)
        filterBar.addSubview(advancedFilterButton)
        filterBar.addSubview(filterSeparator)
        view.addSubview(chipsScrollView)
        chipsScrollView.addSubview(chipsStack)

        let chipsHeightConstraint = chipsScrollView.heightAnchor.constraint(equalToConstant: 0)
        self.chipsHeightConstraint = chipsHeightConstraint

        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterBar.heightAnchor.constraint(equalToConstant: 44),

            categoryButton.leadingAnchor.constraint(equalTo: filterBar.leadingAnchor, constant: 16),
            categoryButton.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),

            sortButton.leadingAnchor.constraint(equalTo: categoryButton.trailingAnchor, constant: 8),
            sortButton.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),

            advancedFilterButton.leadingAnchor.constraint(equalTo: sortButton.trailingAnchor, constant: 8),
            advancedFilterButton.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),
            advancedFilterButton.trailingAnchor.constraint(lessThanOrEqualTo: filterBar.trailingAnchor, constant: -16),

            filterSeparator.leadingAnchor.constraint(equalTo: filterBar.leadingAnchor),
            filterSeparator.trailingAnchor.constraint(equalTo: filterBar.trailingAnchor),
            filterSeparator.bottomAnchor.constraint(equalTo: filterBar.bottomAnchor),
            filterSeparator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            chipsScrollView.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
            chipsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chipsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chipsHeightConstraint,

            chipsStack.topAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.topAnchor),
            chipsStack.bottomAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.bottomAnchor),
            chipsStack.leadingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            chipsStack.trailingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            chipsStack.heightAnchor.constraint(equalTo: chipsScrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    // MARK: - Filter Button Appearance

    private func updateFilterButtons() {
        // Category button
        if let cat = viewModel.selectedCategory() {
            applyButtonConfig(
                categoryButton,
                title: viewModel.categoryDisplayName(for: cat) ?? cat.name,
                systemImage: "folder.fill",
                isActive: true,
                dotColor: Self.color(fromHex: cat.color)
            )
        } else {
            applyButtonConfig(
                categoryButton,
                title: String(localized: "search.filter.all_categories"),
                systemImage: "folder",
                isActive: false
            )
        }

        // Sort button
        let isSortActive = viewModel.selectedSortOrder != .relevance
        applyButtonConfig(
            sortButton,
            title: viewModel.selectedSortOrder.displayName,
            systemImage: isSortActive ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle",
            isActive: isSortActive
        )

        // Advanced filter button (FluxDo tune icon + active count)
        let activeCount = viewModel.advancedFilter.activeCount
        applyButtonConfig(
            advancedFilterButton,
            title: activeCount > 0
                ? String(
                    format: String(localized: "search.filter.advanced_count", defaultValue: "筛选 · %d"),
                    activeCount
                )
                : String(localized: "search.filter.advanced", defaultValue: "筛选"),
            systemImage: activeCount > 0 ? "slider.horizontal.3" : "slider.horizontal.3",
            isActive: activeCount > 0
        )

        rebuildActiveFilterChips()
    }

    private func applyButtonConfig(
        _ button: UIButton,
        title: String,
        systemImage: String,
        isActive: Bool,
        dotColor: UIColor? = nil
    ) {
        var config: UIButton.Configuration
        if isActive {
            config = .tinted()
            config.baseBackgroundColor = .systemBlue
            config.baseForegroundColor = .systemBlue
        } else {
            config = .gray()
            config.baseForegroundColor = .secondaryLabel
        }
        config.cornerStyle = .capsule
        config.buttonSize = .small
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)

        config.title = title
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 13, weight: .medium)
            return out
        }

        if let dotColor {
            config.image = UIImage(systemName: "circle.fill")?
                .withTintColor(dotColor, renderingMode: .alwaysOriginal)
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 8))
        } else {
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            config.image = UIImage(systemName: systemImage, withConfiguration: symbolConfig)
        }
        config.imagePlacement = .leading
        config.imagePadding = 4

        button.configuration = config
    }

    // MARK: - Active filter chips

    private func rebuildActiveFilterChips() {
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let filter = viewModel.advancedFilter
        guard !filter.isEmpty else {
            chipsHeightConstraint?.constant = 0
            chipsScrollView.isHidden = true
            return
        }
        chipsScrollView.isHidden = false
        chipsHeightConstraint?.constant = 40

        for tag in filter.tags {
            chipsStack.addArrangedSubview(makeChip(title: "#\(tag)") { [weak self] in
                guard let self else { return }
                viewModel.advancedFilter.tags.removeAll { $0 == tag }
                filterDidChange()
            })
        }
        if let status = filter.status {
            chipsStack.addArrangedSubview(makeChip(title: status.label) { [weak self] in
                self?.viewModel.advancedFilter.status = nil
                self?.filterDidChange()
            })
        }
        if filter.afterDate != nil || filter.beforeDate != nil {
            var parts: [String] = []
            if let after = filter.afterDate {
                parts.append(SearchAdvancedFilter.dateFormatter.string(from: after) + " 起")
            }
            if let before = filter.beforeDate {
                parts.append(SearchAdvancedFilter.dateFormatter.string(from: before) + " 止")
            }
            chipsStack.addArrangedSubview(makeChip(title: parts.joined(separator: " ")) { [weak self] in
                self?.viewModel.advancedFilter.afterDate = nil
                self?.viewModel.advancedFilter.beforeDate = nil
                self?.filterDidChange()
            })
        }

        var clearConfig = UIButton.Configuration.plain()
        clearConfig.title = String(localized: "search.filter.clear_all", defaultValue: "清除全部筛选")
        clearConfig.baseForegroundColor = .systemRed
        clearConfig.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
        clearConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 12, weight: .medium)
            return out
        }
        let clearButton = UIButton(configuration: clearConfig)
        clearButton.addAction(UIAction { [weak self] _ in
            self?.viewModel.advancedFilter = SearchAdvancedFilter()
            self?.filterDidChange()
        }, for: .touchUpInside)
        chipsStack.addArrangedSubview(clearButton)
    }

    private func makeChip(title: String, onRemove: @escaping () -> Void) -> UIView {
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .systemBlue
        config.cornerStyle = .capsule
        config.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        )
        config.imagePlacement = .trailing
        config.imagePadding = 5
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 8)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 12, weight: .medium)
            return out
        }
        let button = UIButton(configuration: config)
        button.addAction(UIAction { _ in onRemove() }, for: .touchUpInside)
        return button
    }

    private func filterDidChange() {
        updateFilterButtons()
        triggerSearch()
    }

    // MARK: - Category Menu

    private func buildCategoryMenuElements() -> [UIMenuElement] {
        if viewModel.categories.isEmpty {
            return [UIAction(title: String(localized: "search.filter.loading"), attributes: .disabled) { _ in }]
        }

        var elements: [UIMenuElement] = []

        // "All Categories"
        let allAction = UIAction(
            title: String(localized: "search.filter.all_categories"),
            image: UIImage(systemName: "square.grid.2x2"),
            state: viewModel.selectedCategoryId == nil ? .on : .off
        ) { [weak self] _ in
            self?.selectCategory(nil)
        }
        elements.append(allAction)

        for cat in viewModel.categories {
            let catAction = UIAction(
                title: viewModel.categoryDisplayName(for: cat) ?? cat.name,
                image: colorDotImage(hex: cat.color),
                state: viewModel.selectedCategoryId == cat.id ? .on : .off
            ) { [weak self] _ in
                self?.selectCategory(cat.id)
            }

            if let subs = cat.subcategoryList, !subs.isEmpty {
                var groupChildren: [UIAction] = [catAction]
                for sub in subs {
                    let subAction = UIAction(
                        title: viewModel.categoryDisplayName(for: sub) ?? sub.name,
                        image: colorDotImage(hex: sub.color),
                        state: viewModel.selectedCategoryId == sub.id ? .on : .off
                    ) { [weak self] _ in
                        self?.selectCategory(sub.id)
                    }
                    groupChildren.append(subAction)
                }
                let inlineMenu = UIMenu(title: "", options: .displayInline, children: groupChildren)
                elements.append(inlineMenu)
            } else {
                elements.append(catAction)
            }
        }

        return elements
    }

    // MARK: - Advanced filter panel

    private func presentFilterPanel() {
        let panel = SearchFilterPanelViewController(
            api: api,
            categoryId: viewModel.selectedCategoryId,
            filter: viewModel.advancedFilter
        ) { [weak self] filter in
            guard let self else { return }
            viewModel.advancedFilter = filter
            filterDidChange()
        }
        let nav = UINavigationController(rootViewController: panel)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    // MARK: - Filter Selection

    private func selectCategory(_ categoryId: Int?) {
        viewModel.selectedCategoryId = categoryId
        updateFilterButtons()
        triggerSearch()
    }

    private func selectSortOrder(_ order: SearchSortOrder) {
        viewModel.selectedSortOrder = order
        updateFilterButtons()
        triggerSearch()
    }

    // MARK: - Sort Menu

    private func buildSortMenuElements() -> [UIMenuElement] {
        SearchSortOrder.allCases.map { order in
            UIAction(
                title: order.displayName,
                state: viewModel.selectedSortOrder == order ? .on : .off
            ) { [weak self] _ in
                self?.selectSortOrder(order)
            }
        }
    }

    // MARK: - Recent searches (empty state)

    private func makeRecentSearchesView() -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = String(localized: "search.recent.title", defaultValue: "最近搜索")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel

        var clearConfig = UIButton.Configuration.plain()
        clearConfig.title = String(localized: "search.recent.clear", defaultValue: "清空")
        clearConfig.baseForegroundColor = .secondaryLabel
        clearConfig.contentInsets = .zero
        clearConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 12)
            return out
        }
        let clearButton = UIButton(configuration: clearConfig)
        clearButton.addAction(UIAction { [weak self] _ in
            Task { await self?.viewModel.clearRecentSearches() }
        }, for: .touchUpInside)

        let headerRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), clearButton])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        stack.addArrangedSubview(headerRow)
        stack.setCustomSpacing(8, after: headerRow)

        for term in viewModel.recentSearches.prefix(10) {
            var config = UIButton.Configuration.plain()
            config.title = term
            config.image = UIImage(
                systemName: "clock.arrow.circlepath",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            )
            config.imagePadding = 10
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 2, bottom: 10, trailing: 2)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = .systemFont(ofSize: 15)
                return out
            }
            let button = UIButton(configuration: config)
            button.contentHorizontalAlignment = .leading
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                searchController.searchBar.text = term
                triggerSearch()
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        return container
    }

    // MARK: - User results header

    private func makeUsersHeaderView() -> UIView? {
        guard !viewModel.userResults.isEmpty else { return nil }
        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 64))
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        for user in viewModel.userResults.prefix(10) {
            var config = UIButton.Configuration.gray()
            config.title = user.username
            config.cornerStyle = .capsule
            config.buttonSize = .small
            config.image = UIImage(systemName: "person.crop.circle")
            config.imagePadding = 5
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 12)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = .systemFont(ofSize: 13, weight: .medium)
                return out
            }
            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                let profile = UserProfileViewController(api: api, username: user.username)
                navigationController?.pushViewController(profile, animated: true)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        header.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: header.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        return header
    }

    // MARK: - Search

    override func updateUI() {
        if viewModel.isSearching {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        if let error = viewModel.errorMessage {
            emptyLabel.text = error
            emptyLabel.isHidden = false
        } else if viewModel.hasSearched, viewModel.searchResults.isEmpty, !viewModel.isSearching {
            emptyLabel.text = String(localized: "search.no_results")
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }

        updateFilterButtons()

        // FluxDo：未搜索时展示服务端「最近搜索」
        if !viewModel.hasSearched, !viewModel.recentSearches.isEmpty {
            tableView.backgroundView = makeRecentSearchesView()
        } else {
            tableView.backgroundView = nil
        }
        tableView.tableHeaderView = viewModel.hasSearched ? makeUsersHeaderView() : nil

        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        var seen = Set<Int>()
        let uniqueIds = viewModel.searchResults.compactMap { post -> Int? in
            guard seen.insert(post.id).inserted else { return nil }
            return post.id
        }
        snapshot.appendItems(uniqueIds, toSection: 0)
        snapshot.reconfigureItems(uniqueIds)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        triggerSearch()
    }

    private func triggerSearch() {
        let term = searchController.searchBar.text ?? ""
        guard !term.isEmpty else { return }
        let effectiveTerm: String
        if let fixedQueryQualifier, !fixedQueryQualifier.isEmpty {
            effectiveTerm = "\(term.trimmingCharacters(in: .whitespacesAndNewlines)) \(fixedQueryQualifier)"
        } else {
            effectiveTerm = term
        }
        searchTask?.cancel()
        searchTask = Task {
            await viewModel.search(term: effectiveTerm)
        }
    }

    func refreshAfterCloudflareVerification() {
        triggerSearch()
    }

    // MARK: - Helpers

    private func colorDotImage(hex: String) -> UIImage? {
        guard let color = Self.color(fromHex: hex) else { return nil }
        return UIImage(systemName: "circle.fill")?
            .withTintColor(color, renderingMode: .alwaysOriginal)
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 10))
    }

    private static func color(fromHex hex: String) -> UIColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - UITableViewDelegate

extension SearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let postId = dataSource.itemIdentifier(for: indexPath),
              let post = viewModel.searchResults.first(where: { $0.id == postId })
        else { return }
        let detailVC = TopicDetailViewController(api: api, topicId: post.topicId)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let totalRows = tableView.numberOfRows(inSection: 0)
        if indexPath.row >= totalRows - 5 {
            Task {
                await viewModel.loadMoreResults()
            }
        }
    }
}
