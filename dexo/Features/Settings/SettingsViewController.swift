import UIKit

final class SettingsViewController: ObservableViewController {
    enum Category: CaseIterable {
        case appearance
        case reading
        case network
        case preferences
        case miniPrograms
        case bottomBar
        case dataManagement
        case notion
        case about

        var title: String {
            switch self {
            case .appearance: return String(localized: "settings.appearance_design")
            case .reading: return String(localized: "settings.reading_design")
            case .network: return String(localized: "settings.network")
            case .preferences:
                return String(localized: "settings.preferences", defaultValue: "功能设置")
            case .miniPrograms:
                return String(localized: "mini_program.management.title", defaultValue: "小程序管理")
            case .bottomBar: return String(localized: "settings.bottom_bar")
            case .dataManagement: return String(localized: "settings.data_management")
            case .notion:
                return String(localized: "notion.settings.title", defaultValue: "Notion 同步")
            case .about: return String(localized: "settings.about")
            }
        }

        var subtitle: String {
            switch self {
            case .appearance: return String(localized: "settings.appearance.subtitle")
            case .reading: return String(localized: "settings.reading.subtitle")
            case .network: return String(localized: "settings.network.subtitle")
            case .preferences:
                return String(
                    localized: "settings.preferences.subtitle",
                    defaultValue: "剪贴板、启动和通用行为"
                )
            case .miniPrograms:
                return String(
                    localized: "settings.mini_programs.subtitle",
                    defaultValue: "开关、排序、编辑与 Logo"
                )
            case .bottomBar: return String(localized: "settings.bottom_bar.subtitle")
            case .dataManagement: return String(localized: "settings.data_management.subtitle")
            case .notion:
                return String(
                    localized: "settings.notion.subtitle",
                    defaultValue: "书签同步到 Notion 数据库"
                )
            case .about: return String(localized: "settings.about.subtitle")
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: return "paintpalette.fill"
            case .reading: return "book.closed.fill"
            case .network: return "network"
            case .preferences: return "slider.horizontal.3"
            case .miniPrograms: return "square.grid.2x2.fill"
            case .bottomBar: return "rectangle.bottomthird.inset.filled"
            case .dataManagement: return "externaldrive.fill"
            case .notion: return "cloud.fill"
            case .about: return "info.circle.fill"
            }
        }

        var tintColor: UIColor {
            switch self {
            case .appearance: return .systemTeal
            case .reading: return .systemOrange
            case .network: return .systemBlue
            case .preferences: return .systemPurple
            case .miniPrograms: return .systemGreen
            case .bottomBar: return .systemYellow
            case .dataManagement: return .systemBrown
            case .notion: return .systemPurple
            case .about: return .systemIndigo
            }
        }
    }

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemGroupedBackground
        table.separatorInset = UIEdgeInsets(top: 0, left: 68, bottom: 0, right: 0)
        table.dataSource = self
        table.delegate = self
        table.register(SettingsHubCell.self, forCellReuseIdentifier: SettingsHubCell.reuseID)
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        observe(AppSettings.shared)
        title = String(localized: "tab.settings")
        view.backgroundColor = .systemGroupedBackground
        view.tintColor = AppSettings.shared.themeStyle.accentColor

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    override func updateUI() {
        title = String(localized: "tab.settings")
        view.tintColor = AppSettings.shared.themeStyle.accentColor
        tableView.reloadData()
    }
}

extension SettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Category.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let category = Category.allCases[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: SettingsHubCell.reuseID, for: indexPath) as! SettingsHubCell
        cell.configure(
            title: category.title,
            subtitle: category.subtitle,
            symbolName: category.symbolName,
            tintColor: category.tintColor
        )
        return cell
    }
}

extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        64
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let category = Category.allCases[indexPath.row]
        switch category {
        case .appearance:
            navigationController?.pushViewController(AppearanceSettingsViewController(), animated: true)
        case .reading:
            navigationController?.pushViewController(ReadingSettingsViewController(), animated: true)
        case .network:
            navigationController?.pushViewController(NetworkSettingsViewController(), animated: true)
        case .preferences:
            navigationController?.pushViewController(PreferencesSettingsViewController(), animated: true)
        case .miniPrograms:
            let baseURL = ForumInstance.linuxDoBaseURL
            let username = AuthManager.shared.username(for: baseURL)
            navigationController?.pushViewController(
                PluginCenterViewController(baseURL: baseURL, username: username),
                animated: true
            )
        case .bottomBar:
            navigationController?.pushViewController(BottomBarLayoutViewController(), animated: true)
        case .dataManagement:
            navigationController?.pushViewController(DataManagementSettingsViewController(), animated: true)
        case .notion:
            let vc = NotionSettingsViewController(
                baseURL: ForumInstance.linuxDoBaseURL,
                username: AuthManager.shared.username(for: ForumInstance.linuxDoBaseURL)
            )
            navigationController?.pushViewController(vc, animated: true)
        case .about:
            navigationController?.pushViewController(AboutSettingsViewController(), animated: true)
        }
    }
}

/// FluxDO-style hub row: tinted icon well + title + subtitle + chevron.
private final class SettingsHubCell: UITableViewCell {
    static let reuseID = "SettingsHubCell"

    private let iconWell = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        accessoryType = .disclosureIndicator
        backgroundColor = .secondarySystemGroupedBackground

        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.layer.cornerRadius = 10
        iconWell.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconWell.addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(iconWell)
        contentView.addSubview(textStack)
        NSLayoutConstraint.activate([
            iconWell.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconWell.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconWell.widthAnchor.constraint(equalToConstant: 36),
            iconWell.heightAnchor.constraint(equalToConstant: 36),
            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            textStack.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, subtitle: String, symbolName: String, tintColor: UIColor) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        iconWell.backgroundColor = tintColor.withAlphaComponent(0.12)
        iconView.image = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        iconView.tintColor = tintColor
        accessibilityLabel = "\(title)，\(subtitle)"
    }
}
