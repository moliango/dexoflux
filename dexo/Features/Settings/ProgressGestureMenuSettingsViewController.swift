import UIKit

/// FluxDO-style editor for long-press radial menu actions on the topic progress bar.
final class ProgressGestureMenuSettingsViewController: UITableViewController {
    private let settings = AppSettings.shared
    private var selected: [ProgressGestureAction]

    init() {
        selected = AppSettings.shared.progressGestureMenuActions
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "progress_gesture.long_press_menu", defaultValue: "长按菜单")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = editButtonItem
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
        selected = settings.progressGestureMenuActions
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? selected.count : ProgressGestureAction.menuCandidates.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return String(
                format: String(localized: "progress_gesture.menu.selected_format", defaultValue: "已选 %lld / %lld"),
                selected.count,
                ProgressGestureAction.menuMaxCount
            )
        }
        return String(localized: "progress_gesture.menu.available", defaultValue: "可添加")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0
            ? String(
                localized: "progress_gesture.menu.footer",
                defaultValue: "长按话题进度条时展开这些动作。可拖动排序，最多 8 项。"
            )
            : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let action = selected[indexPath.row]
            content.text = action.title
            content.image = UIImage(systemName: action.symbolName)
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            let action = ProgressGestureAction.menuCandidates[indexPath.row]
            content.text = action.title
            content.image = UIImage(systemName: action.symbolName)
            let isSelected = selected.contains(action)
            cell.accessoryType = isSelected ? .checkmark : .none
            cell.selectionStyle = .default
            content.secondaryText = isSelected
                ? String(localized: "progress_gesture.menu.already_added", defaultValue: "已添加")
                : nil
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        let action = ProgressGestureAction.menuCandidates[indexPath.row]
        if let index = selected.firstIndex(of: action) {
            selected.remove(at: index)
        } else if selected.count < ProgressGestureAction.menuMaxCount {
            selected.append(action)
        } else {
            let alert = UIAlertController(
                title: nil,
                message: String(
                    format: String(localized: "progress_gesture.menu.limit", defaultValue: "最多选择 %lld 项"),
                    ProgressGestureAction.menuMaxCount
                ),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
            present(alert, animated: true)
            return
        }
        persist()
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 0
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard indexPath.section == 0, editingStyle == .delete else { return }
        selected.remove(at: indexPath.row)
        persist()
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 0
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard sourceIndexPath.section == 0, destinationIndexPath.section == 0 else {
            tableView.reloadData()
            return
        }
        let action = selected.remove(at: sourceIndexPath.row)
        selected.insert(action, at: destinationIndexPath.row)
        persist()
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        proposedDestinationIndexPath.section == 0
            ? proposedDestinationIndexPath
            : IndexPath(row: selected.count - 1, section: 0)
    }

    private func persist() {
        settings.progressGestureMenuActions = selected
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
