import UIKit

final class AccountFunctionsEditorViewController: UITableViewController {
    private let preferences = MeAccountFunctionPreferences()
    private var visibleFunctions: [MeAccountFunction] = []
    private var hiddenFunctions: [MeAccountFunction] = []

    init() {
        super.init(style: .insetGrouped)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.account_functions.customize", defaultValue: "自定义账号功能")
        tableView.backgroundColor = AppSettings.shared.themeStyle.topicListBackgroundColor
        tableView.tintColor = AppSettings.shared.themeStyle.accentColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "settings.bottom_bar.restore_default", defaultValue: "恢复默认"),
            style: .plain,
            target: self,
            action: #selector(restoreDefaultTapped)
        )
        reloadConfiguration()
        setEditing(true, animated: false)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? visibleFunctions.count : hiddenFunctions.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0
            ? String(localized: "me.account_functions.visible", defaultValue: "显示")
            : String(localized: "me.account_functions.hidden", defaultValue: "已隐藏")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return visibleFunctions.isEmpty
                ? String(localized: "me.account_functions.all_hidden", defaultValue: "已隐藏全部账号功能，「我的」页不会显示账号功能列表。")
                : String(localized: "me.account_functions.visible_help", defaultValue: "拖动右侧排序；点减号隐藏入口。")
        }
        return hiddenFunctions.isEmpty
            ? String(localized: "me.account_functions.hidden_empty", defaultValue: "没有隐藏的账号功能。")
            : String(localized: "me.account_functions.hidden_help", defaultValue: "点加号恢复到显示列表末尾。")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let function = functionValue(at: indexPath)
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: function.symbolName)
        content.imageProperties.tintColor = AppSettings.shared.themeStyle.accentColor
        content.text = function.title
        content.secondaryText = indexPath.section == 0
            ? String(localized: "me.account_functions.item_visible", defaultValue: "显示在账号功能列表")
            : String(localized: "me.account_functions.item_hidden", defaultValue: "已隐藏")
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        cell.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        indexPath.section == 0 ? .delete : .insert
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch (indexPath.section, editingStyle) {
        case (0, .delete):
            guard visibleFunctions.indices.contains(indexPath.row) else { return }
            hiddenFunctions.append(visibleFunctions.remove(at: indexPath.row))
        case (1, .insert):
            guard hiddenFunctions.indices.contains(indexPath.row) else { return }
            visibleFunctions.append(hiddenFunctions.remove(at: indexPath.row))
        default:
            return
        }
        persistAndReload()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 0
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard proposedDestinationIndexPath.section == 0 else {
            return IndexPath(row: max(visibleFunctions.count - 1, 0), section: 0)
        }
        return proposedDestinationIndexPath
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard sourceIndexPath.section == 0,
              destinationIndexPath.section == 0,
              visibleFunctions.indices.contains(sourceIndexPath.row) else { return }
        let function = visibleFunctions.remove(at: sourceIndexPath.row)
        visibleFunctions.insert(function, at: min(destinationIndexPath.row, visibleFunctions.count))
        preferences.setVisibleFunctions(visibleFunctions)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @objc private func restoreDefaultTapped() {
        preferences.reset()
        reloadConfiguration()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func functionValue(at indexPath: IndexPath) -> MeAccountFunction {
        indexPath.section == 0 ? visibleFunctions[indexPath.row] : hiddenFunctions[indexPath.row]
    }

    private func reloadConfiguration() {
        visibleFunctions = preferences.visibleFunctions
        hiddenFunctions = preferences.hiddenFunctions
        tableView.reloadData()
    }

    private func persistAndReload() {
        preferences.setVisibleFunctions(visibleFunctions)
        reloadConfiguration()
    }
}
