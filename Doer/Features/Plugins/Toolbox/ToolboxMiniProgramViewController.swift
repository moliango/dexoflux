import UIKit

/// Built-in「工具箱」mini-program root: list of local utility tools.
@MainActor
final class ToolboxMiniProgramViewController: UITableViewController {
    private enum Tool: Int, CaseIterable {
        case base64

        var title: String {
            switch self {
            case .base64:
                return String(localized: "toolbox.tool.base64.title", defaultValue: "Base64")
            }
        }

        var subtitle: String {
            switch self {
            case .base64:
                return String(
                    localized: "toolbox.tool.base64.subtitle",
                    defaultValue: "文本编码 / 解码"
                )
            }
        }

        var symbolName: String {
            switch self {
            case .base64:
                return "lock.doc.fill"
            }
        }
    }

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "toolbox.title", defaultValue: "工具箱")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ToolCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        navigationItem.largeTitleDisplayMode = .never
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Tool.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        String(localized: "toolbox.section.encoding", defaultValue: "编解码")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ToolCell", for: indexPath)
        let tool = Tool.allCases[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = tool.title
        config.secondaryText = tool.subtitle
        config.image = UIImage(systemName: tool.symbolName)
        config.imageProperties.tintColor = .systemIndigo
        config.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 20,
            weight: .semibold
        )
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Tool.allCases[indexPath.row] {
        case .base64:
            navigationController?.pushViewController(Base64ToolViewController(), animated: true)
        }
    }
}
