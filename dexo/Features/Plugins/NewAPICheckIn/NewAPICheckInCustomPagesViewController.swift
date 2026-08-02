import UIKit

/// 「自定义」tab — lightweight bookmark pages opened in the in-app browser.
@MainActor
final class NewAPICheckInCustomPagesViewController: UITableViewController {
    private let store: NewAPICheckInStore
    private var pages: [NewAPICheckInCustomPage] = []

    init(store: NewAPICheckInStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "plugins.newapi.tab.custom", defaultValue: "自定义")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "page")
        tableView.rowHeight = 72
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addTapped)
        )
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        pages = NewAPICheckInCustomPageStore.shared.all()
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(pages.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "page", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if pages.isEmpty {
            content.text = String(localized: "plugins.newapi.custom.empty", defaultValue: "还没有自定义页面")
            content.secondaryText = String(
                localized: "plugins.newapi.custom.empty_hint",
                defaultValue: "点右上角 + 添加常用网页"
            )
            content.textProperties.color = .secondaryLabel
            content.secondaryTextProperties.color = .tertiaryLabel
            cell.accessoryType = .none
            cell.selectionStyle = .default
        } else {
            let page = pages[indexPath.row]
            content.text = page.name
            content.secondaryText = page.urlString
            content.image = UIImage(systemName: "globe")
            content.imageProperties.tintColor = AppSettings.shared.themeStyle.accentColor
            content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
            content.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if pages.isEmpty {
            addTapped()
            return
        }
        let page = pages[indexPath.row]
        guard let url = URL(string: page.urlString) else { return }
        // Reuse forum API host only as cookie scope; page itself may be any URL.
        let browser = InAppBrowserViewController(
            api: DiscourseAPI(baseURL: "https://linux.do"),
            username: nil,
            initialURL: url,
            hidesHostTabBarAtRoot: false,
            hidesBrowserControlBar: false
        )
        navigationController?.pushViewController(browser, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !pages.isEmpty else { return nil }
        let page = pages[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: String(localized: "common.delete", defaultValue: "删除")) { [weak self] _, _, done in
            NewAPICheckInCustomPageStore.shared.delete(id: page.id)
            self?.reload()
            done(true)
        }
        let edit = UIContextualAction(style: .normal, title: String(localized: "common.edit", defaultValue: "编辑")) { [weak self] _, _, done in
            self?.presentEditor(existing: page)
            done(true)
        }
        edit.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }

    @objc private func addTapped() {
        presentEditor(existing: nil)
    }

    private func presentEditor(existing: NewAPICheckInCustomPage?) {
        let alert = UIAlertController(
            title: existing == nil
                ? String(localized: "plugins.newapi.custom.add", defaultValue: "添加页面")
                : String(localized: "plugins.newapi.custom.edit", defaultValue: "编辑页面"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = String(localized: "plugins.newapi.custom.name", defaultValue: "名称")
            $0.text = existing?.name
        }
        alert.addTextField {
            $0.placeholder = "https://example.com"
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
            $0.text = existing?.urlString
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.save", defaultValue: "保存"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  let raw = alert?.textFields?.dropFirst().first?.text,
                  let url = self.normalizedURL(raw)
            else { return }
            var page = existing ?? NewAPICheckInCustomPage(name: name, urlString: url.absoluteString)
            page.name = name
            page.urlString = url.absoluteString
            page.updatedAt = Date()
            NewAPICheckInCustomPageStore.shared.save(page)
            self.reload()
        })
        present(alert, animated: true)
    }

    private func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://\(trimmed)")
    }
}

// MARK: - Model + store

struct NewAPICheckInCustomPage: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var urlString: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

final class NewAPICheckInCustomPageStore {
    static let shared = NewAPICheckInCustomPageStore()

    private let defaultsKey = "plugin.newapi.custom_pages.v1"
    private let lock = NSLock()
    private var cache: [NewAPICheckInCustomPage]

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([NewAPICheckInCustomPage].self, from: data) {
            cache = decoded
        } else {
            cache = []
        }
    }

    func all() -> [NewAPICheckInCustomPage] {
        lock.lock()
        defer { lock.unlock() }
        return cache.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ page: NewAPICheckInCustomPage) {
        lock.lock()
        if let index = cache.firstIndex(where: { $0.id == page.id }) {
            cache[index] = page
        } else {
            cache.append(page)
        }
        persistLocked()
        lock.unlock()
    }

    func delete(id: UUID) {
        lock.lock()
        cache.removeAll { $0.id == id }
        persistLocked()
        lock.unlock()
    }

    private func persistLocked() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
