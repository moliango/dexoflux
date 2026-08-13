import UIKit

final class UserProfileTabsSettingsViewController: UITableViewController {
    private let preferences = UserProfileTabPreferences()
    private var visibleSections: [UserProfileSection] = []
    private var hiddenSections: [UserProfileSection] = []

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "settings.profile_tabs")
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? visibleSections.count : hiddenSections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0
            ? String(localized: "settings.profile_tabs.visible")
            : String(localized: "settings.profile_tabs.hidden")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return visibleSections.count == 1
                ? String(localized: "settings.profile_tabs.minimum_one")
                : String(localized: "settings.profile_tabs.visible_help")
        }
        return hiddenSections.isEmpty ? String(localized: "settings.profile_tabs.hidden_empty") : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sectionValue(at: indexPath)
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: symbolName(for: section))
        content.imageProperties.tintColor = AppSettings.shared.themeStyle.accentColor
        content.text = section.title
        content.secondaryText = indexPath.section == 0
            ? String(localized: "settings.profile_tabs.item_visible")
            : String(localized: "settings.profile_tabs.item_hidden")
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
        if indexPath.section == 0 {
            return visibleSections.count > 1 ? .delete : .none
        }
        return .insert
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch (indexPath.section, editingStyle) {
        case (0, .delete):
            guard visibleSections.count > 1, visibleSections.indices.contains(indexPath.row) else { return }
            visibleSections.remove(at: indexPath.row)
        case (1, .insert):
            guard hiddenSections.indices.contains(indexPath.row) else { return }
            visibleSections.append(hiddenSections[indexPath.row])
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
            return IndexPath(row: max(visibleSections.count - 1, 0), section: 0)
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
              visibleSections.indices.contains(sourceIndexPath.row) else { return }
        let section = visibleSections.remove(at: sourceIndexPath.row)
        let destination = min(destinationIndexPath.row, visibleSections.count)
        visibleSections.insert(section, at: destination)
        preferences.setVisibleSections(visibleSections)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @objc private func restoreDefaultTapped() {
        preferences.reset()
        reloadConfiguration()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func sectionValue(at indexPath: IndexPath) -> UserProfileSection {
        indexPath.section == 0 ? visibleSections[indexPath.row] : hiddenSections[indexPath.row]
    }

    private func reloadConfiguration() {
        visibleSections = preferences.visibleSections
        let visibleSet = Set(visibleSections)
        hiddenSections = UserProfileSection.allCases.filter { !visibleSet.contains($0) }
        tableView.reloadData()
    }

    private func persistAndReload() {
        preferences.setVisibleSections(visibleSections)
        reloadConfiguration()
    }

    private func symbolName(for section: UserProfileSection) -> String {
        switch section {
        case .summary: return "chart.bar.doc.horizontal.fill"
        case .activity: return "bolt.fill"
        case .topics: return "text.bubble.fill"
        case .replies: return "quote.bubble.fill"
        case .likesReceived: return "heart.fill"
        case .likesGiven: return "hand.thumbsup.fill"
        case .reactions: return "face.smiling.fill"
        }
    }
}
