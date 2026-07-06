import UIKit

final class TagPickerViewController: UIViewController, UISearchBarDelegate {
    private let api: DiscourseAPI
    private let categoryId: Int?
    private let currentTag: String?
    var onTagSelected: ((String?) -> Void)?

    private var tags: [DiscourseTag] = []
    private var searchTask: Task<Void, Never>?

    /// Sentinel item identifier for the "clear filter" row
    private static let clearItem = "__clear__"

    private let searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.placeholder = String(localized: "search.tag_picker.placeholder")
        sb.searchBarStyle = .minimal
        sb.translatesAutoresizingMaskIntoConstraints = false
        return sb
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, String> = {
        UITableViewDiffableDataSource<Int, String>(tableView: tableView) { [weak self] tableView, indexPath, identifier in
            guard let self else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") ?? UITableViewCell(style: .value1, reuseIdentifier: "Cell")

            if identifier == Self.clearItem {
                var content = cell.defaultContentConfiguration()
                content.text = String(localized: "search.tag_picker.clear")
                content.image = UIImage(systemName: "xmark.circle")
                content.imageProperties.tintColor = .systemRed
                cell.contentConfiguration = content
                cell.accessoryType = .none
            } else if let tag = self.tags.first(where: { $0.text == identifier }) {
                var content = cell.defaultContentConfiguration()
                content.text = "#\(tag.text)"
                content.textProperties.font = .systemFont(ofSize: 16, weight: .medium)
                content.secondaryText = "\(tag.count)"
                content.secondaryTextProperties.color = .secondaryLabel
                cell.contentConfiguration = content
                cell.accessoryType = tag.text == self.currentTag ? .checkmark : .none
            }

            return cell
        }
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "search.tag_picker.empty")
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    // MARK: - Init

    init(api: DiscourseAPI, categoryId: Int?, selectedTag: String?) {
        self.api = api
        self.categoryId = categoryId
        self.currentTag = selectedTag
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "search.tag_picker.title")
        view.backgroundColor = .systemGroupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        searchBar.delegate = self

        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 60),

            activityIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 60),
        ])

        fetchTags(query: "")
    }

    // MARK: - Data

    private func fetchTags(query: String) {
        searchTask?.cancel()
        activityIndicator.startAnimating()
        emptyLabel.isHidden = true

        searchTask = Task {
            if !query.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }
            do {
                let results = try await api.searchTags(query: query, categoryId: categoryId)
                guard !Task.isCancelled else { return }
                tags = results
                applySnapshot()
            } catch {
                guard !Task.isCancelled else { return }
                tags = []
                applySnapshot()
            }
            activityIndicator.stopAnimating()
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()

        if currentTag != nil {
            snapshot.appendSections([0])
            snapshot.appendItems([Self.clearItem], toSection: 0)
        }

        snapshot.appendSections([1])
        snapshot.appendItems(tags.map(\.text), toSection: 1)

        dataSource.apply(snapshot, animatingDifferences: true)
        emptyLabel.isHidden = !tags.isEmpty
    }

    // MARK: - UISearchBarDelegate

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        fetchTags(query: searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDelegate

extension TagPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let identifier = dataSource.itemIdentifier(for: indexPath) else { return }

        if identifier == Self.clearItem {
            onTagSelected?(nil)
        } else {
            onTagSelected?(identifier)
        }
        dismiss(animated: true)
    }
}
