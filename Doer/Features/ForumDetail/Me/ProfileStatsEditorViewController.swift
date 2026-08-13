import UIKit

final class ProfileStatsEditorViewController: UIViewController {
    var onChange: ((MeStatsConfiguration) -> Void)?

    private var configuration: MeStatsConfiguration
    private var displayedMetrics: [MeStatType] = []

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setEditing(true, animated: false)
        return tableView
    }()

    private lazy var layoutControl: UISegmentedControl = {
        let control = UISegmentedControl(items: MeStatsLayout.allCases.map(\.title))
        control.selectedSegmentIndex = MeStatsLayout.allCases.firstIndex(of: configuration.layout) ?? 0
        control.addTarget(self, action: #selector(layoutChanged), for: .valueChanged)
        return control
    }()

    init(configuration: MeStatsConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        rebuildDisplayedMetrics()
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.stats.customize")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "common.done", defaultValue: "完成"),
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: String(localized: "action.reset", defaultValue: "重置"),
            style: .plain,
            target: self,
            action: #selector(resetTapped)
        )

        tableView.tableHeaderView = makeLayoutHeader()
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func makeLayoutHeader() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 92))
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "me.stats.layout", defaultValue: "展示布局")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        layoutControl.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(layoutControl)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            layoutControl.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            layoutControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            layoutControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            layoutControl.heightAnchor.constraint(equalToConstant: 34),
        ])
        return container
    }

    private func rebuildDisplayedMetrics() {
        let selected = configuration.orderedMetrics
        let remaining = MeStatType.allCases.filter { !selected.contains($0) }
        displayedMetrics = selected + remaining
    }

    private func publishChanges() {
        onChange?(configuration)
    }

    @objc private func layoutChanged() {
        guard MeStatsLayout.allCases.indices.contains(layoutControl.selectedSegmentIndex) else { return }
        configuration.layout = MeStatsLayout.allCases[layoutControl.selectedSegmentIndex]
        publishChanges()
    }

    @objc private func resetTapped() {
        configuration = MeStatsConfiguration(
            orderedMetrics: [.daysVisited, .postCount, .likesReceived, .topicCount],
            layout: .grid
        )
        layoutControl.selectedSegmentIndex = MeStatsLayout.allCases.firstIndex(of: .grid) ?? 0
        rebuildDisplayedMetrics()
        tableView.reloadData()
        publishChanges()
    }

    @objc private func doneTapped() {
        navigationController?.popViewController(animated: true)
    }

    private func toggle(_ metric: MeStatType) {
        if let index = configuration.orderedMetrics.firstIndex(of: metric) {
            guard configuration.orderedMetrics.count > 2 else {
                let alert = UIAlertController(
                    title: nil,
                    message: String(localized: "me.stats.minimum_two", defaultValue: "至少保留两个统计项目。"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
                present(alert, animated: true)
                return
            }
            configuration.orderedMetrics.remove(at: index)
        } else {
            configuration.orderedMetrics.append(metric)
        }
        rebuildDisplayedMetrics()
        tableView.reloadData()
        publishChanges()
    }
}

extension ProfileStatsEditorViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayedMetrics.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let metric = displayedMetrics[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: metric.symbolName)
        content.imageProperties.tintColor = metric.tintColor
        content.text = metric.title
        cell.contentConfiguration = content
        cell.accessoryType = configuration.orderedMetrics.contains(metric) ? .checkmark : .none
        cell.showsReorderControl = true
        return cell
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        configuration.orderedMetrics.contains(displayedMetrics[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        let metric = displayedMetrics.remove(at: sourceIndexPath.row)
        displayedMetrics.insert(metric, at: destinationIndexPath.row)
        let selected = Set(configuration.orderedMetrics)
        configuration.orderedMetrics = displayedMetrics.filter { selected.contains($0) }
        rebuildDisplayedMetrics()
        tableView.reloadData()
        publishChanges()
    }
}

extension ProfileStatsEditorViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        toggle(displayedMetrics[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        let lastSelectedIndex = max(configuration.orderedMetrics.count - 1, 0)
        return IndexPath(row: min(proposedDestinationIndexPath.row, lastSelectedIndex), section: 0)
    }
}
