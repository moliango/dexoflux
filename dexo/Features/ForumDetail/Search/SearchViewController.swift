import UIKit

final class SearchViewController: ObservableViewController, UISearchBarDelegate {
    private let api: DiscourseAPI
    private let viewModel: SearchViewModel

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

    private lazy var tagButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.presentTagPicker()
        }, for: .touchUpInside)
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

    private let filterSeparator: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

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
        cell.configure(with: post, baseURL: self.api.baseURL)
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

    init(api: DiscourseAPI) {
        self.api = api
        self.viewModel = SearchViewModel(api: api)
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
            tableView.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
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
    }

    // MARK: - Filter Bar Setup

    private func setupFilterBar() {
        view.addSubview(filterBar)
        filterBar.addSubview(categoryButton)
        filterBar.addSubview(tagButton)
        filterBar.addSubview(sortButton)
        filterBar.addSubview(filterSeparator)

        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterBar.heightAnchor.constraint(equalToConstant: 44),

            categoryButton.leadingAnchor.constraint(equalTo: filterBar.leadingAnchor, constant: 16),
            categoryButton.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),

            tagButton.leadingAnchor.constraint(equalTo: categoryButton.trailingAnchor, constant: 8),
            tagButton.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),

            sortButton.leadingAnchor.constraint(equalTo: tagButton.trailingAnchor, constant: 8),
            sortButton.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),
            sortButton.trailingAnchor.constraint(lessThanOrEqualTo: filterBar.trailingAnchor, constant: -16),

            filterSeparator.leadingAnchor.constraint(equalTo: filterBar.leadingAnchor),
            filterSeparator.trailingAnchor.constraint(equalTo: filterBar.trailingAnchor),
            filterSeparator.bottomAnchor.constraint(equalTo: filterBar.bottomAnchor),
            filterSeparator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
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

        // Tag button
        if let tag = viewModel.selectedTag {
            applyButtonConfig(tagButton, title: "#\(tag)", systemImage: "tag.fill", isActive: true)
        } else {
            applyButtonConfig(
                tagButton,
                title: String(localized: "search.filter.all_tags"),
                systemImage: "tag",
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

    // MARK: - Tag Picker

    private func presentTagPicker() {
        let picker = TagPickerViewController(
            api: api,
            categoryId: viewModel.selectedCategoryId,
            selectedTag: viewModel.selectedTag
        )
        picker.onTagSelected = { [weak self] tag in
            self?.selectTag(tag)
        }
        let nav = UINavigationController(rootViewController: picker)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    // MARK: - Filter Selection

    private func selectCategory(_ categoryId: Int?) {
        viewModel.selectedCategoryId = categoryId
        viewModel.selectedTag = nil
        updateFilterButtons()
        triggerSearch()
    }

    private func selectTag(_ tag: String?) {
        viewModel.selectedTag = tag
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

        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        var seen = Set<Int>()
        let uniqueIds = viewModel.searchResults.compactMap { post -> Int? in
            guard seen.insert(post.id).inserted else { return nil }
            return post.id
        }
        snapshot.appendItems(uniqueIds, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        triggerSearch()
    }

    private func triggerSearch() {
        let term = searchController.searchBar.text ?? ""
        guard !term.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            await viewModel.search(term: term)
        }
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
