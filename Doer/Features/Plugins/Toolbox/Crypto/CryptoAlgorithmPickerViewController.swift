import UIKit

final class CryptoAlgorithmPickerViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate {
    var onSelect: ((String) -> Void)?

    private let currentAlgorithmId: String
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchBar = UISearchBar()
    private var gridMode = false
    private var query = ""

    private let categoryOrder: [CryptoAlgorithmCategory] = [
        .symmetric, .encoding, .hash, .asymmetric, .classic,
    ]

    init(currentAlgorithmId: String) {
        self.currentAlgorithmId = currentAlgorithmId
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "crypto.algorithm", defaultValue: "算法")
        view.backgroundColor = CryptoChrome.screen
        view.tintColor = CryptoChrome.accent
        navigationController?.navigationBar.tintColor = CryptoChrome.accent
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.grid.2x2"),
            style: .plain,
            target: self,
            action: #selector(toggleLayout)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        searchBar.placeholder = String(localized: "crypto.algorithm.search", defaultValue: "搜索算法")
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Algo")
        tableView.register(CryptoAlgorithmGridCell.self, forCellReuseIdentifier: CryptoAlgorithmGridCell.reuseID)
        tableView.keyboardDismissMode = .onDrag
        tableView.backgroundColor = .clear
        tableView.separatorColor = CryptoChrome.border
        tableView.tintColor = CryptoChrome.accent

        view.addSubview(searchBar)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private var recent: [any CryptoAlgorithm] {
        AppSettings.shared.cryptoRecentAlgorithms.compactMap { CryptoToolbox.byId($0) }
    }

    private var filtered: [any CryptoAlgorithm] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return CryptoToolbox.allAlgorithms.filter {
            $0.id.lowercased().contains(q) || $0.displayName.lowercased().contains(q)
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func toggleLayout() {
        gridMode.toggle()
        navigationItem.rightBarButtonItem?.image = UIImage(systemName: gridMode ? "list.bullet" : "square.grid.2x2")
        tableView.reloadData()
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText
        tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        if isSearching { return 1 }
        return (recent.isEmpty ? 0 : 1) + categoryOrder.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isSearching {
            return String(localized: "crypto.algorithm.search.results", defaultValue: "搜索结果")
        }
        var index = section
        if !recent.isEmpty {
            if index == 0 {
                return String(localized: "crypto.recent", defaultValue: "最近使用")
            }
            index -= 1
        }
        return categoryOrder[index].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isSearching { return max(filtered.count, 1) }
        let algos = algorithms(in: section)
        if gridMode { return 1 }
        return algos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isSearching {
            if filtered.isEmpty {
                let cell = tableView.dequeueReusableCell(withIdentifier: "Algo", for: indexPath)
                cell.textLabel?.text = String(localized: "crypto.algorithm.empty", defaultValue: "没有匹配的算法")
                cell.textLabel?.textColor = .secondaryLabel
                cell.accessoryType = .none
                cell.selectionStyle = .none
                return cell
            }
            return listCell(tableView, indexPath: indexPath, algorithm: filtered[indexPath.row])
        }
        let algos = algorithms(in: indexPath.section)
        if gridMode {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: CryptoAlgorithmGridCell.reuseID,
                for: indexPath
            ) as! CryptoAlgorithmGridCell
            cell.configure(algorithms: algos, selectedID: currentAlgorithmId) { [weak self] id in
                self?.select(id)
            }
            return cell
        }
        return listCell(tableView, indexPath: indexPath, algorithm: algos[indexPath.row])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if gridMode, !isSearching { return }
        if isSearching {
            guard filtered.indices.contains(indexPath.row) else { return }
            select(filtered[indexPath.row].id)
            return
        }
        select(algorithms(in: indexPath.section)[indexPath.row].id)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if gridMode, !isSearching {
            let count = algorithms(in: indexPath.section).count
            let rows = Int(ceil(Double(count) / 3.0))
            return CGFloat(max(rows, 1) * 44 + 8)
        }
        return UITableView.automaticDimension
    }

    private func algorithms(in section: Int) -> [any CryptoAlgorithm] {
        var index = section
        if !recent.isEmpty {
            if index == 0 { return recent }
            index -= 1
        }
        return CryptoToolbox.algorithms(in: categoryOrder[index])
    }

    private func listCell(_ tableView: UITableView, indexPath: IndexPath, algorithm: any CryptoAlgorithm) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Algo", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = algorithm.displayName
        config.secondaryText = algorithm.id
        cell.contentConfiguration = config
        cell.accessoryType = algorithm.id == currentAlgorithmId ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    private func select(_ id: String) {
        AppSettings.shared.rememberCryptoAlgorithm(id)
        onSelect?(id)
        dismiss(animated: true)
    }
}

private final class CryptoAlgorithmGridCell: UITableViewCell {
    static let reuseID = "CryptoAlgorithmGridCell"
    private var buttons: [UIButton] = []
    private var onSelect: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(algorithms: [any CryptoAlgorithm], selectedID: String, onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        contentView.subviews.forEach { $0.removeFromSuperview() }
        let columns = 3
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
        var index = 0
        while index < algorithms.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
            for _ in 0..<columns {
                if index < algorithms.count {
                    row.addArrangedSubview(makeChip(algorithms[index], selected: algorithms[index].id == selectedID))
                    index += 1
                } else {
                    row.addArrangedSubview(UIView())
                }
            }
            stack.addArrangedSubview(row)
        }
    }

    private func makeChip(_ algorithm: any CryptoAlgorithm, selected: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .medium
        config.baseBackgroundColor = selected
            ? CryptoChrome.accent.withAlphaComponent(0.22)
            : CryptoChrome.card
        config.baseForegroundColor = .label
        config.title = algorithm.displayName
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var next = incoming
            next.font = .systemFont(ofSize: 12, weight: selected ? .bold : .medium)
            return next
        }
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in
            self?.onSelect?(algorithm.id)
        }, for: .touchUpInside)
        return button
    }
}
