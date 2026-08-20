import SDWebImage
import UIKit

final class StickerMarketViewController: UIViewController {
    var onSubscriptionsChanged: (() -> Void)?

    private var groups: [StickerGroup] = []
    private var subscribed = Set(StickerMarketStore.shared.subscribedGroupIds())

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        return tv
    }()

    private let loading = UIActivityIndicatorView(style: .medium)
    private let errorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "sticker.market.title", defaultValue: "表情包市场")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "common.done", defaultValue: "完成"),
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: String(localized: "sticker.market.base_url", defaultValue: "市场地址"),
            style: .plain,
            target: self,
            action: #selector(editBaseURL)
        )

        loading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        view.addSubview(loading)
        view.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        loadGroups()
    }

    private func loadGroups() {
        loading.startAnimating()
        errorLabel.isHidden = true
        Task {
            do {
                let groups = try await StickerMarketStore.shared.fetchAllGroups()
                await MainActor.run {
                    self.loading.stopAnimating()
                    self.groups = groups
                    self.tableView.reloadData()
                    if groups.isEmpty {
                        self.errorLabel.text = String(localized: "sticker.market.empty", defaultValue: "市场暂无表情包")
                        self.errorLabel.isHidden = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.loading.stopAnimating()
                    self.errorLabel.text = error.localizedDescription
                    self.errorLabel.isHidden = false
                }
            }
        }
    }

    @objc private func doneTapped() {
        onSubscriptionsChanged?()
        dismiss(animated: true)
    }

    @objc private func editBaseURL() {
        let alert = UIAlertController(
            title: String(localized: "sticker.market.base_url", defaultValue: "市场地址"),
            message: String(localized: "sticker.market.base_url_message", defaultValue: "修改后会清空市场缓存"),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = StickerMarketStore.shared.baseURL
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "sticker.market.reset_default", defaultValue: "恢复默认"), style: .destructive) { [weak self] _ in
            StickerMarketStore.shared.resetBaseURL()
            self?.loadGroups()
        })
        alert.addAction(UIAlertAction(title: String(localized: "common.save", defaultValue: "保存"), style: .default) { [weak self] _ in
            let value = alert.textFields?.first?.text ?? ""
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            StickerMarketStore.shared.setBaseURL(value)
            self?.loadGroups()
        })
        present(alert, animated: true)
    }
}

extension StickerMarketViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        let group = groups[indexPath.row]
        content.text = group.name
        content.secondaryText = "\(group.emojiCount) " + String(localized: "sticker.market.count_suffix", defaultValue: "个表情")
        if let url = URL(string: group.icon) {
            // Keep system image placeholder; async icon optional.
            content.image = UIImage(systemName: "face.smiling")
            SDWebImageManager.shared.loadImage(with: url, options: [], progress: nil) { image, _, _, _, _, _ in
                Task { @MainActor in
                    guard tableView.cellForRow(at: indexPath) != nil else { return }
                    var updated = cell.defaultContentConfiguration()
                    updated.text = group.name
                    updated.secondaryText = content.secondaryText
                    updated.image = image ?? UIImage(systemName: "face.smiling")
                    updated.imageProperties.maximumSize = CGSize(width: 36, height: 36)
                    cell.contentConfiguration = updated
                }
            }
        } else {
            content.image = UIImage(systemName: "face.smiling")
        }
        content.imageProperties.maximumSize = CGSize(width: 36, height: 36)
        cell.contentConfiguration = content
        let isOn = subscribed.contains(group.id)
        cell.accessoryType = isOn ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let group = groups[indexPath.row]
        if subscribed.contains(group.id) {
            subscribed.remove(group.id)
            StickerMarketStore.shared.unsubscribe(group.id)
        } else {
            subscribed.insert(group.id)
            StickerMarketStore.shared.subscribe(group.id)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
