import UIKit

/// 「我的小程序」：按分类展示全部小程序，支持搜索。
@MainActor
final class MiniProgramLauncherViewController: UIViewController {
    private let api: DiscourseAPI
    private var username: String?
    private var filteredQuery = ""
    private var catalogObservation: NSObjectProtocol?

    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchBar.placeholder = String(
            localized: "mini_program.drawer.search_placeholder",
            defaultValue: "搜索小程序"
        )
        controller.searchResultsUpdater = self
        controller.searchBar.autocapitalizationType = .none
        controller.searchBar.returnKeyType = .search
        return controller
    }()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .onDrag
        return scrollView
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 22
        return stack
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.numberOfLines = 0
        label.text = String(localized: "mini_program.empty", defaultValue: "暂无可用小程序")
        label.isHidden = true
        return label
    }()

    init(api: DiscourseAPI, username: String?) {
        self.api = api
        self.username = username
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let catalogObservation {
            NotificationCenter.default.removeObserver(catalogObservation)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "mini_program.my_programs.title", defaultValue: "我的小程序")
        view.backgroundColor = AppSettings.shared.themeStyle.topicListBackgroundColor
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "mini_program.management.title", defaultValue: "小程序管理"),
            style: .plain,
            target: self,
            action: #selector(manageTapped)
        )

        view.addSubview(scrollView)
        view.addSubview(emptyLabel)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        catalogObservation = NotificationCenter.default.addObserver(
            forName: MiniProgramStore.catalogDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildContent()
        }

        rebuildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildContent()
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let query = filteredQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let all = MiniProgramFactory.firstPartyPrograms
        let programs: [MiniProgramDescriptor]
        if query.isEmpty {
            programs = all
        } else {
            programs = all.filter { $0.displayName.lowercased().contains(query) }
        }

        let categories = MiniProgramStore.shared.allCategories()
        var didAddAny = false

        for category in categories {
            let inCategory = programs.filter { $0.categoryID == category.id }
            guard !inCategory.isEmpty else { continue }
            contentStack.addArrangedSubview(makeSectionHeader(title: category.name))
            contentStack.addArrangedSubview(makeGrid(programs: inCategory))
            didAddAny = true
        }

        // Programs whose category is missing still show under a fallback bucket.
        let knownIDs = Set(categories.map(\.id))
        let uncategorized = programs.filter { !knownIDs.contains($0.categoryID) }
        if !uncategorized.isEmpty {
            contentStack.addArrangedSubview(makeSectionHeader(
                title: String(localized: "mini_program.category.other", defaultValue: "其他")
            ))
            contentStack.addArrangedSubview(makeGrid(programs: uncategorized))
            didAddAny = true
        }

        // If catalog has no categories at all, flat-list every matching program.
        if !didAddAny, !programs.isEmpty {
            contentStack.addArrangedSubview(makeSectionHeader(
                title: String(localized: "mini_program.all_section", defaultValue: "全部小程序")
            ))
            contentStack.addArrangedSubview(makeGrid(programs: programs))
            didAddAny = true
        }

        emptyLabel.isHidden = didAddAny
        emptyLabel.text = query.isEmpty
            ? String(localized: "mini_program.empty", defaultValue: "暂无可用小程序")
            : String(localized: "mini_program.search.empty", defaultValue: "未找到匹配的小程序")
        scrollView.isHidden = !didAddAny
    }

    private func makeSectionHeader(title: String) -> UIView {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .secondaryLabel

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeGrid(programs: [MiniProgramDescriptor]) -> UIView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16

        let columns = 4
        var index = 0
        while index < programs.count {
            let rowPrograms = Array(programs[index..<min(index + columns, programs.count)])
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = 8
            for program in rowPrograms {
                row.addArrangedSubview(makeTile(for: program))
            }
            while row.arrangedSubviews.count < columns {
                let spacer = UIView()
                spacer.isUserInteractionEnabled = false
                row.addArrangedSubview(spacer)
            }
            stack.addArrangedSubview(row)
            index += columns
        }
        return stack
    }

    private func makeTile(for program: MiniProgramDescriptor) -> UIView {
        let container = UIControl()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.accessibilityLabel = program.displayName
        container.accessibilityTraits = .button

        let iconBadge = MiniProgramIconBadge.view(for: program.id, size: MiniProgramIconBadge.defaultSize)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = program.displayName
        titleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.isUserInteractionEnabled = false

        container.addSubview(iconBadge)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconBadge.topAnchor.constraint(equalTo: container.topAnchor),
            iconBadge.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: iconBadge.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            titleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            MiniProgramFactory.present(
                program: program,
                from: self,
                api: self.api,
                username: self.username
            )
        }, for: .touchUpInside)

        return container
    }

    @objc private func manageTapped() {
        let vc = PluginCenterViewController(baseURL: api.baseURL, username: username)
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension MiniProgramLauncherViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        filteredQuery = searchController.searchBar.text ?? ""
        rebuildContent()
    }
}
